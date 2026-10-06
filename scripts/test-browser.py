#!/usr/bin/env python3
"""Headless Chrome test: real Native Messaging + DNR, using a disposable profile.

Requires Playwright and its Chromium browser. All site traffic resolves to a
local fixture server; no real Gmail, LinkedIn, or personal browser is opened.
"""
import json
import argparse
import os
import shlex
import shutil
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / '.build/debug/OrtusBrowserBridge'
EXTENSION_ID = json.loads((ROOT / 'BrowserExtension/identity.json').read_text())['id']
HOST_NAME = 'com.ortus.browser.integration_test'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--extension', type=Path, default=ROOT / 'BrowserExtension')
args = parser.parse_args()


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<html><title>Local fixture</title><body><h1>Website fixture</h1></body></html>')
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='ortus-browser-qa-') as tmp:
        temp = Path(tmp)
        extension = temp / 'extension'
        shutil.copytree(args.extension, extension, ignore=shutil.ignore_patterns('tests', 'package.json'))
        (extension / 'config.js').write_text(f"export const NATIVE_HOST = '{HOST_NAME}';\n")
        state = temp / 'state'
        state.mkdir()
        wrapper = temp / 'native-host'
        wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(str(BRIDGE)) + ' --state-directory ' + shlex.quote(str(state)) + '\n')
        wrapper.chmod(0o700)
        manifest = {'name': HOST_NAME, 'description': 'Isolated Ortus test host', 'path': str(wrapper), 'type': 'stdio', 'allowed_origins': [f'chrome-extension://{EXTENSION_ID}/']}
        profile_hosts = temp / 'profile/NativeMessagingHosts'
        profile_hosts.mkdir(parents=True)
        (profile_hosts / (HOST_NAME + '.json')).write_text(json.dumps(manifest))

        def publish(domains, lifetime=180, lease=20):
            now = time.time()
            policy = {'schemaVersion': 1, 'generatedAt': now, 'heartbeatExpiresAt': now + lease,
                      'rules': [{'domain': domain, 'expiresAt': now + lifetime} for domain in domains]}
            staging = state / 'next.json'
            staging.write_text(json.dumps(policy))
            staging.replace(state / 'policy.json')

        publish([])
        with sync_playwright() as p:
            context = p.chromium.launch_persistent_context(str(temp / 'profile'), channel='chromium', headless=True,
                args=[f'--disable-extensions-except={extension}', f'--load-extension={extension}',
                      '--host-resolver-rules=MAP * 127.0.0.1', '--no-proxy-server'],
                viewport={'width': 1100, 'height': 780})
            worker = context.service_workers[0] if context.service_workers else context.wait_for_event('serviceworker')
            for _ in range(60):
                connection = worker.evaluate("async () => (await chrome.storage.local.get('connection')).connection")
                if connection and connection.get('connected'):
                    break
                context.pages[0].wait_for_timeout(200)
            else:
                raise AssertionError(f'Native host did not connect: {connection}')
            client_id = worker.evaluate("async () => (await chrome.storage.local.get('clientID')).clientID")
            client_file = state / 'clients' / (client_id + '.json')
            for _ in range(60):
                if client_file.exists() and json.loads(client_file.read_text()).get('state') == 'ready':
                    break
                context.pages[0].wait_for_timeout(100)
            else:
                raise AssertionError('The native app never received the browser enforcement acknowledgement')
            print('PASS: companion connects to the actual Swift native host', flush=True)
            port = server.server_address[1]
            gmail = context.new_page()
            gmail.goto(f'http://mail.google.com:{port}/mail/inbox')
            assert gmail.title() == 'Local fixture'
            publish(['mail.google.com', 'linkedin.com'])
            gmail.wait_for_url(lambda url: url.startswith(f'chrome-extension://{EXTENSION_ID}/blocked.html'))
            gmail.locator('#title').filter(has_text='Gmail is set aside').wait_for()
            gmail.screenshot(path=str(ROOT / '.context/website-blocked.png'))
            print('PASS: an already-open Gmail tab is blocked', flush=True)

            linkedin = context.new_page()
            linkedin.goto(f'http://www.linkedin.com:{port}/feed', wait_until='domcontentloaded')
            linkedin.wait_for_url(lambda url: url.startswith(f'chrome-extension://{EXTENSION_ID}/blocked.html'))
            print('PASS: LinkedIn navigation and subdomains are redirected', flush=True)
            for domain in ['docs.google.com', 'notlinkedin.com', 'linkedin.com.example.test']:
                page = context.new_page()
                page.goto(f'http://{domain}:{port}/')
                assert page.title() == 'Local fixture'
                page.close()
            print('PASS: Google Docs and lookalike domains stay available', flush=True)
            rules = worker.evaluate('() => chrome.declarativeNetRequest.getSessionRules()')
            assert len(rules) == 2 and rules[1]['action']['type'] == 'block'
            # Use the browser's fetch implementation so DNR proves it blocks background requests too.
            allowed = context.new_page()
            allowed.goto(f'http://docs.google.com:{port}/')
            fetch_result = allowed.evaluate("async url => { try { await fetch(url, { mode:'no-cors' }); return 'allowed'; } catch { return 'blocked'; } }", f'http://mail.google.com:{port}/background')
            assert fetch_result == 'blocked'
            print('PASS: background requests to blocked domains fail', flush=True)

            publish([])
            gmail.locator('#return').wait_for(state='visible')
            gmail.locator('#return').click()
            gmail.wait_for_url(f'http://mail.google.com:{port}/mail/inbox')
            assert gmail.title() == 'Local fixture'
            print('PASS: ending focus releases sites and restores the original URL', flush=True)

            publish(['mail.google.com'], lifetime=2)
            gmail.wait_for_url(lambda url: url.startswith(f'chrome-extension://{EXTENSION_ID}/blocked.html'))
            gmail.locator('#return').wait_for(state='visible', timeout=10000)
            print('PASS: a session deadline releases the block without a stop message', flush=True)
            publish(['linkedin.com'], lease=2)
            linkedin.locator('#return').wait_for(state='hidden')
            linkedin.locator('#return').wait_for(state='visible', timeout=10000)
            assert worker.evaluate('() => chrome.declarativeNetRequest.getSessionRules()') == []
            print('PASS: a stale app heartbeat clears all browser rules', flush=True)
            context.close()
finally:
    server.shutdown()
