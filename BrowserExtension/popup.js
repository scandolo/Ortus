import { effectiveRules, siteGroups, connectionMessage } from './core.js';
import { glyph } from './glyphs.js';
const title = document.querySelector('#title');
const status = document.querySelector('#status');
const blockedSites = document.querySelector('#blocked-sites');
const list = document.querySelector('#sites');
const reconnect = document.querySelector('#reconnect');
const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
const clock = seconds => new Date(seconds * 1000).toLocaleTimeString([], { hour:'numeric', minute:'2-digit' });
async function render() {
  const { connection } = await chrome.storage.local.get('connection');
  const { policy } = await chrome.storage.session.get('policy');
  const connected = Boolean(connection?.connected);
  const live = policy?.heartbeatExpiresAt > Date.now() / 1000;
  const groups = connected && live ? siteGroups(effectiveRules(policy)) : [];
  const end = Math.max(0, ...groups.map(group => group.expiresAt));
  if (!connected) { setText(title, 'Not connected'); setText(status, connectionMessage(connection?.error)); }
  else if (!live) { setText(title, 'Ortus isn’t running'); setText(status, 'Open Ortus to keep your focus sessions going.'); }
  else if (groups.length) { setText(title, 'Focus is on'); setText(status, `Until ${clock(end)}`); }
  else { setText(title, 'Ready when you are'); setText(status, 'Websites are blocked when a focus session starts.'); }
  const signature = JSON.stringify(groups);
  if (list.dataset.signature !== signature) {
    list.replaceChildren(...groups.map(group => {
      const row = document.createElement('li');
      const mark = document.createElement('span'); mark.className = 'glyph'; mark.innerHTML = glyph(group.name);
      const name = document.createElement('span'); name.className = 'name'; name.textContent = group.name;
      row.append(mark, name);
      // Only sites ending at a different time need their own time.
      if (group.expiresAt !== end) { const time = document.createElement('time'); time.textContent = clock(group.expiresAt); row.append(time); }
      return row;
    }));
    list.dataset.signature = signature;
  }
  blockedSites.hidden = !groups.length;
  reconnect.hidden = connected;
}
reconnect.addEventListener('click', () => { chrome.runtime.sendMessage({ type:'reconnect' }); setText(status, 'Checking the connection…'); });
chrome.storage.onChanged.addListener(render);
render();
