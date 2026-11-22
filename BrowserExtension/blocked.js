import { effectiveRules, matchingRule, originalURL, siteName, timeLeft } from './core.js';
const original = originalURL(location.hash);
const host = original ? new URL(original).hostname.replace(/^www\./, '') : null;
const root = document.documentElement;
const label = document.querySelector('#label');
const title = document.querySelector('#title');
const status = document.querySelector('#status');
const left = document.querySelector('#left');
const help = document.querySelector('#help');
const back = document.querySelector('#return');
const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
const clock = seconds => new Date(seconds * 1000).toLocaleTimeString([], { hour:'numeric', minute:'2-digit' });
back.addEventListener('click', () => { if (original) location.replace(original); });
// Remember when the session ended. A rule that disappears early (Ortus quit, say) ended
// when this page noticed, not at its planned time.
let lastEnd = null;
let endedAt = null;
async function render() {
  const { policy } = await chrome.storage.session.get('policy');
  const now = Date.now() / 1000;
  const rule = original && matchingRule(original, effectiveRules(policy));
  const name = rule ? siteName(rule.domain) : host ? siteName(host) : 'This website';
  const genZ = policy?.tone === 'genz';
  // Bone is free, ink is locked: the stylesheet picks the ground from data-state.
  root.dataset.state = rule ? 'locked' : 'free';
  back.hidden = Boolean(rule) || !original;
  setText(back, genZ ? `go to ${name}` : `Go to ${name}`);
  if (rule) {
    lastEnd = rule.expiresAt; endedAt = null;
    const end = clock(rule.expiresAt);
    setText(label, `Locked in · until ${end}`);
    setText(title, genZ ? 'not today bestie.' : 'Not yet.');
    setText(status, genZ ? `${name}? back at ${end}.` : `${name} is closed until ${end}.`);
    setText(left, genZ ? 'lock in.' : `${timeLeft(rule.expiresAt - now)} to go.`);
    setText(help, genZ ? `need something from ${name}? ask your agent in Ortus.` : `Need something from ${name}? Ask your agent in Ortus.`);
    document.title = `${name} is closed · Ortus`;
  } else {
    if (lastEnd && !endedAt) endedAt = Math.min(lastEnd, now);
    setText(title, genZ ? `${name} is back on the menu.` : `${name} is back.`);
    const ended = endedAt ? ` at ${clock(endedAt)}` : '';
    setText(status, genZ ? `session ended${ended}.` : `The session ended${ended}.`);
    setText(left, '');
    document.title = `${name} is back · Ortus`;
  }
}
chrome.storage.onChanged.addListener(render);
setInterval(render, 5000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
render();
