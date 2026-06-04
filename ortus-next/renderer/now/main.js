// `ortus` is exposed as a global via contextBridge in preload.js.
const timeEl = document.getElementById('time');
const intentionEl = document.getElementById('intention');
const ringEl = document.getElementById('ring');

const C = 62.83; // 2π × r where r = 10

let totalMs = null;

function fmtClock(min) {
  if (min < 0) min = 0;
  const totalSec = Math.round(min * 60);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

ortus.onChannel('focus:tick', ({ remaining, elapsed, intention }) => {
  timeEl.textContent = fmtClock(remaining);
  intentionEl.textContent = intention || '—';
  if (totalMs === null && remaining + elapsed > 0) {
    totalMs = (remaining + elapsed) * 60_000;
  }
  if (totalMs) {
    const pct = Math.max(0, Math.min(1, (remaining * 60_000) / totalMs));
    ringEl.setAttribute('stroke-dashoffset', String(C * (1 - pct)));
  }
});

// Initial hydrate
ortus.getState().then((state) => {
  if (state?.currentIntention) intentionEl.textContent = state.currentIntention;
  if (state?.focusStartedAt && state?.focusEndsAt) {
    totalMs = state.focusEndsAt - state.focusStartedAt;
    const remaining = Math.max(0, state.focusEndsAt - Date.now()) / 60_000;
    timeEl.textContent = fmtClock(remaining);
    const pct = Math.max(0, Math.min(1, (remaining * 60_000) / totalMs));
    ringEl.setAttribute('stroke-dashoffset', String(C * (1 - pct)));
  }
});
