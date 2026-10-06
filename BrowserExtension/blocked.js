import { effectiveRules, matchingRule, originalURL, siteName } from './core.js';
const original = originalURL(location.hash);
const host = original ? new URL(original).hostname.replace(/^www\./, '') : null;
const title = document.querySelector('#title');
const status = document.querySelector('#status');
const back = document.querySelector('#return');
const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
back.addEventListener('click', () => { if (original) location.replace(original); });
async function render() {
  const { policy } = await chrome.storage.session.get('policy');
  const rule = original && matchingRule(original, effectiveRules(policy));
  const name = rule ? siteName(rule.domain) : host ? siteName(host) : 'This website';
  back.hidden = Boolean(rule) || !original;
  setText(back, `Go to ${name}`);
  if (rule) {
    const end = new Date(rule.expiresAt * 1000).toLocaleTimeString([], { hour:'numeric', minute:'2-digit' });
    setText(title, `${name} is set aside`);
    setText(status, `Back at ${end}`);
  } else {
    setText(title, `${name} is available again`);
    setText(status, '');
  }
  document.title = `${title.textContent} · Ortus`;
}
chrome.storage.onChanged.addListener(render);
setInterval(render, 5000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
render();
