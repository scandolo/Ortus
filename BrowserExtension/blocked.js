import { effectiveRules, matchingRule, originalURL, siteName } from './core.js';
const original = originalURL(location.hash);
const host = original ? new URL(original).hostname.replace(/^www\./, '') : null;
const title = document.querySelector('#title');
const status = document.querySelector('#status');
const back = document.querySelector('#return');
const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
back.addEventListener('click', () => { if (original) location.replace(original); });
// A small sunrise when the mark is clicked.
const emblem = document.querySelector('#emblem');
emblem.addEventListener('click', () => {
  emblem.classList.remove('rise');
  void emblem.offsetWidth; // restart the animation on repeated clicks
  emblem.classList.add('rise');
});
emblem.addEventListener('animationend', event => { if (event.target === emblem) emblem.classList.remove('rise'); });
async function render() {
  const { policy } = await chrome.storage.session.get('policy');
  const rule = original && matchingRule(original, effectiveRules(policy));
  const name = rule ? siteName(rule.domain) : host ? siteName(host) : 'This website';
  const genZ = policy?.tone === 'genz';
  back.hidden = Boolean(rule) || !original;
  setText(back, genZ ? `go to ${name}` : `Go to ${name}`);
  if (rule) {
    const end = new Date(rule.expiresAt * 1000).toLocaleTimeString([], { hour:'numeric', minute:'2-digit' });
    setText(title, genZ ? `${name}? not today bestie` : `${name} is set aside`);
    setText(status, genZ ? `back at ${end}. lock in.` : `Back at ${end}`);
  } else {
    setText(title, genZ ? `${name} is back on the menu` : `${name} is available again`);
    setText(status, '');
  }
  document.title = `${title.textContent} · Ortus`;
}
chrome.storage.onChanged.addListener(render);
setInterval(render, 5000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
render();
