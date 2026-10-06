import { NATIVE_HOST } from './config.js';
import { effectiveRules, matchingRule, networkRules } from './core.js';

let port;
let connecting = false;
let policy = null;
let updateQueue = Promise.resolve();
let retryTimer;
const blockedPage = chrome.runtime.getURL('blocked.html');

async function protectOpenTabs(rules) {
  for (const tab of await chrome.tabs.query({})) {
    const url = tab.pendingUrl || tab.url;
    if (tab.id !== undefined && url && matchingRule(url, rules)) {
      await chrome.tabs.update(tab.id, { url: blockedPage + '#url=' + encodeURIComponent(url) }).catch(() => {});
    }
  }
}

function apply(nextPolicy, connected, error = null) {
  // Serialize rule replacement, storage, and tab redirects. Rapid start/end messages
  // must never leave a stale start applied after a newer stop.
  updateQueue = updateQueue.catch(() => {}).then(async () => {
    policy = nextPolicy;
    const rules = effectiveRules(policy);
    const existing = await chrome.declarativeNetRequest.getSessionRules();
    const next = networkRules(rules, chrome.runtime.getURL(''));
    if (JSON.stringify(existing) !== JSON.stringify(next)) {
      await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: existing.map(rule => rule.id), addRules: next });
    }
    await chrome.storage.local.set({ connection: { connected, error, updatedAt: Date.now() } });
    await chrome.storage.session.set({ policy });
    await chrome.alarms.clear('expire');
    if (rules.length) {
      const expires = Math.min(policy.heartbeatExpiresAt, ...rules.map(rule => rule.expiresAt));
      await chrome.alarms.create('expire', { when: Math.max(Date.now() + 50, expires * 1000) });
      await protectOpenTabs(rules);
    }
    await chrome.action.setBadgeText({ text: error ? '!' : rules.length ? String(new Set(rules.map(r => r.domain)).size) : '' });
    await chrome.action.setBadgeBackgroundColor({ color: error ? '#B74327' : '#AC501A' });
    port?.postMessage({ type: 'status', state: 'ready' });
  }).catch(async error => {
    // Report enforcement errors instead of claiming that the browser is protected.
    await chrome.storage.local.set({ connection: { connected: false, error: error.message, updatedAt: Date.now() } });
    await chrome.action.setBadgeText({ text: '!' });
    port?.postMessage({ type: 'status', state: 'error' });
  });
  return updateQueue;
}

async function connect() {
  if (port || connecting) return;
  connecting = true;
  clearTimeout(retryTimer);
  try {
    const saved = await chrome.storage.local.get(['clientID', 'browserName']);
    const clientID = saved.clientID || crypto.randomUUID();
    await chrome.storage.local.set({ clientID });
    // Chromium user agents don't reliably identify Arc; the companion popup lets a
    // user label that connection without collecting their profile or account name.
    const browser = saved.browserName || (/Edg\//.test(navigator.userAgent) ? 'Edge' : 'Chrome');
    const connection = chrome.runtime.connectNative(NATIVE_HOST);
    port = connection;
    connection.onMessage.addListener(message => {
      if (port === connection) apply(message, true);
    });
    connection.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError?.message || 'Ortus connection closed.';
      if (port !== connection) return;
      port = null;
      apply(null, false, error);
      retryTimer = setTimeout(connect, 3000);
    });
    connection.postMessage({ type: 'hello', clientID, browser });
  } catch (error) {
    port = null;
    apply(null, false, error.message);
    retryTimer = setTimeout(connect, 3000);
  } finally { connecting = false; }
}

chrome.tabs.onUpdated.addListener((_id, change) => {
  if (change.url || change.status === 'complete') {
    const rules = effectiveRules(policy);
    if (rules.length) protectOpenTabs(rules).catch(() => {});
  }
});
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === 'expire') apply(policy, Boolean(port));
  if (alarm.name === 'reconnect') connect();
});
chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message?.type === 'open-ortus') {
    if (port) { port.postMessage({ type: 'open', destination: message.destination === 'browser' ? 'browser' : 'focus' }); reply({ ok: true }); }
    else { reply({ ok: false }); connect(); }
    return;
  }
  if (message?.type === 'reconnect') {
    const old = port;
    port = null;
    old?.disconnect();
    connect();
  }
});
chrome.runtime.onStartup.addListener(() => ready.then(connect));
chrome.runtime.onInstalled.addListener(() => ready.then(connect));
// Session rules survive service-worker suspension, but expire using the saved
// heartbeat before a fresh native handshake can arrive.
async function boot() {
  const saved = await chrome.storage.session.get('policy');
  await apply(saved.policy || null, false);
  await chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
  await connect();
}
const ready = boot();
