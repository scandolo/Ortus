#!/usr/bin/env python3
"""Install the preview and expose a selectable browser extension folder. No UI is opened."""
import argparse
import datetime
import json
import shutil
import subprocess
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--browser-only', action='store_true', help='Prepare the companion for the installed preview without restarting the app.')
parser.add_argument("--variant", choices=["preview", "native", "glass"], default="preview")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
app_name = {'preview':'Ortus Preview','native':'Ortus Native','glass':'Ortus Glass'}[args.variant]
source = root / (app_name + '.app')
destination = Path('/Applications') / (app_name + '.app')
if not args.browser_only:
    if not source.is_dir():
        raise SystemExit(f'Run ./build.sh {args.variant} first.')
    running = subprocess.run(['pgrep', '-f', '^' + re.escape(str(destination / 'Contents/MacOS/Ortus')) + '$'], capture_output=True)
    if running.returncode == 0:
        raise SystemExit(f'Quit {app_name} before replacing it, then run this installer again.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
    staging = destination.parent / ('.' + app_name + '.installing.app')
    if staging.exists():
        raise SystemExit(f'An earlier install is staged at {staging}. Inspect it before retrying.')
    shutil.copytree(source, staging)
    if destination.exists():
        backup = root / '.context' / (app_name.replace(' ','-') + '-backup-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '.app')
        destination.rename(backup)
    staging.rename(destination)

bundled = destination / 'Contents/Resources/BrowserExtension'
extension = destination.parent / 'Ortus Preview Browser'
if not (bundled / 'manifest.json').is_file():
    raise SystemExit('The installed preview is missing its browser companion. Rebuild and install it first.')
identity = json.loads((bundled / 'identity.json').read_text())['id']
if extension.exists() and any(extension.iterdir()):
    existing = extension / 'identity.json'
    if not existing.is_file() or json.loads(existing.read_text()).get('id') != identity:
        raise SystemExit(f'Refusing to replace an unrelated folder: {extension}')
extension.mkdir(exist_ok=True)
# The distributed companion is flat. Preserve its stable path across app rebuilds,
# and avoid rewriting unchanged files while the browser is using them.
for item in bundled.iterdir():
    if not item.is_file():
        continue
    target = extension / item.name
    data = item.read_bytes()
    if target.exists() and target.read_bytes() == data:
        continue
    temporary = extension / ('.' + item.name + '.installing')
    temporary.write_bytes(data)
    temporary.replace(target)
manifest = {'name': 'com.ortus.browser.preview', 'description': 'Ortus Preview focus rules',
            'path': str(destination / 'Contents/MacOS/OrtusBrowserBridge'), 'type': 'stdio',
            'allowed_origins': [f'chrome-extension://{identity}/']}
for browser in ['Google/Chrome', 'Arc/User Data', 'Microsoft Edge', 'BraveSoftware/Brave-Browser', 'Chromium']:
    folder = Path.home() / 'Library/Application Support' / browser / 'NativeMessagingHosts'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'com.ortus.browser.preview.json').write_text(json.dumps(manifest, indent=2) + '\n')
registrar = Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
if registrar.is_file():
    subprocess.run([str(registrar), '-f', str(destination)], check=True)
print(f'App: {destination}')
print(f'Load unpacked from: {extension}')
print('Website blocking stays inactive until the browser companion connects.')
