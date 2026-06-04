// `ortus` is exposed as a global via contextBridge in preload.js.

const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);

const OUTCOMES = {
  shipped:       { label: 'Shipped', cls: 'out-shipped' },
  partial:       { label: 'Partial', cls: 'out-partial' },
  stuck:         { label: 'Stuck',   cls: 'out-stuck' },
  'pulled-away': { label: 'Pulled away', cls: 'out-pulled-away' },
};

const TAGLINES = [
  'First light. First task.',
  'Ortus, n. — the rising of the sun',
  'Wake. Work. Wonder.',
  'Carpe lucem.',
  'Focus mode for deep work',
];
let taglineIndex = 0;

let state = null;
let currentTab = 'focus';

// ── Tab switching ──
$$('.tab').forEach((t) => {
  t.addEventListener('click', () => switchTab(t.dataset.tab));
});
function switchTab(name) {
  currentTab = name;
  $$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
  $$('.pane').forEach((p) => p.classList.toggle('active', p.dataset.pane === name));
  if (name === 'settings') loadLedger();
}

// ── Sunrise duration slider ──
// Hidden range input drives the SVG visual. Snaps to ticks with subtle animation.
const TICKS = [15, 30, 60, 90, 120, 180, 240];
const SVG_W = 360;
const PADDING = 10;
const USABLE_W = SVG_W - PADDING * 2 - 22; // 22 = thumb size, leaves room at edges

const durationInput = $('#duration');
const trackFillRect = $('#trackFillRect');
const tickDotsG = $('#tickDots');
const thumb = $('#thumb');
const thumbHalo = $('#thumbHalo');
const chipGroup = $('#chipGroup');
const chipPath = $('#chipPath');
const chipText = $('#chipText');
const chipUnit = $('#chipUnit');

function renderTickDots(value) {
  tickDotsG.innerHTML = '';
  for (const t of TICKS) {
    const x = posForValue(t);
    const past = t <= value + 0.001;
    const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    c.setAttribute('cx', x);
    c.setAttribute('cy', 49);
    c.setAttribute('r', past ? 2 : 1.6);
    c.setAttribute('fill', past ? 'rgba(255,255,255,0.85)' : 'rgba(255,255,255,0.32)');
    tickDotsG.appendChild(c);
  }
}

function posForValue(v) {
  const p = (v - 15) / (240 - 15);
  return PADDING + 11 + p * USABLE_W;
}

function fmtClock(min) {
  if (min >= 60) {
    const h = Math.floor(min / 60);
    const m = min - h * 60;
    return m === 0 ? `${h}h` : `${h}h ${m}`;
  }
  return String(min);
}

function buildChipPath(centerX, value) {
  const w = 58;
  const h = 26;
  const r = 8;
  const tailH = 5;
  const tailHalf = 4.5;
  const clampedCenter = Math.min(Math.max(centerX, PADDING + w / 2), SVG_W - PADDING - w / 2);
  const left = clampedCenter - w / 2;
  const right = clampedCenter + w / 2;
  const top = 4;
  const bubbleBot = top + h;
  // Tail tip is aimed at the actual centerX (thumb position)
  const tailTipX = Math.min(Math.max(centerX, left + r + tailHalf), right - r - tailHalf);

  return `M ${left + r} ${top}
          L ${right - r} ${top}
          Q ${right} ${top}, ${right} ${top + r}
          L ${right} ${bubbleBot - r}
          Q ${right} ${bubbleBot}, ${right - r} ${bubbleBot}
          L ${tailTipX + tailHalf} ${bubbleBot}
          L ${tailTipX} ${bubbleBot + tailH}
          L ${tailTipX - tailHalf} ${bubbleBot}
          L ${left + r} ${bubbleBot}
          Q ${left} ${bubbleBot}, ${left} ${bubbleBot - r}
          L ${left} ${top + r}
          Q ${left} ${top}, ${left + r} ${top} Z`;
}

function renderSlider(value) {
  const x = posForValue(value);
  const fillW = x - PADDING;
  trackFillRect.setAttribute('width', Math.max(6, fillW));
  thumb.setAttribute('cx', x);
  thumbHalo.setAttribute('cx', x);

  // Halo intensity scales with value
  const intensity = (value - 15) / (240 - 15);
  thumbHalo.setAttribute('opacity', String(0.18 + 0.32 * intensity));
  thumbHalo.setAttribute('r', String(20 + intensity * 6));

  chipPath.setAttribute('d', buildChipPath(x, value));
  chipText.textContent = fmtClock(value);
  // Position chip texts
  const clampedCenter = Math.min(Math.max(x, PADDING + 29), SVG_W - PADDING - 29);
  chipText.setAttribute('x', clampedCenter - 6);
  chipUnit.setAttribute('x', clampedCenter + 14);

  renderTickDots(value);
}

function snapToNearestTick(raw) {
  // Snap if within 5 of a tick
  for (const t of TICKS) {
    if (Math.abs(t - raw) <= 5) return t;
  }
  return Math.round(raw / 5) * 5;
}

durationInput.addEventListener('input', (e) => {
  const raw = Number(e.target.value);
  const snapped = snapToNearestTick(raw);
  if (snapped !== raw) durationInput.value = String(snapped);
  renderSlider(snapped);
});

// ── Intention input ──
const intentionEl = $('#intention');
const beginBtn = $('#begin');

function refreshBeginButton() {
  const hasIntention = (intentionEl.value || '').trim().length >= 3;
  beginBtn.disabled = !hasIntention;
}
intentionEl.addEventListener('input', refreshBeginButton);

beginBtn.addEventListener('click', async () => {
  if (beginBtn.disabled) return;
  beginBtn.disabled = true;
  beginBtn.textContent = 'Starting…';
  const res = await ortus.dispatch('focus:start', {
    intention: intentionEl.value.trim(),
    durationMin: Number(durationInput.value),
  });
  if (!res?.ok) {
    beginBtn.disabled = false;
    beginBtn.textContent = res?.error || 'Try again';
    setTimeout(() => { beginBtn.textContent = 'Begin focus'; refreshBeginButton(); }, 1800);
  } else {
    intentionEl.value = '';
    refreshBeginButton();
    beginBtn.textContent = 'Begin focus';
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !beginBtn.disabled) {
    beginBtn.click();
  }
});

// ── Extend button ──
$('#extend').addEventListener('click', async () => {
  await ortus.dispatch('focus:extend', { minutes: 15 });
});

// ── Emergency end (in Settings) ──
const emergencyBtn = $('#emergency');
emergencyBtn.addEventListener('click', async () => {
  if (!state?.isInFocus) {
    emergencyBtn.textContent = 'No active focus';
    setTimeout(() => { emergencyBtn.textContent = 'End focus now'; }, 1600);
    return;
  }
  const res = await ortus.dispatch('focus:emergencyEnd');
  if (!res?.ok) {
    emergencyBtn.textContent = res?.error || 'Not available';
    emergencyBtn.disabled = true;
    setTimeout(() => {
      emergencyBtn.textContent = 'End focus now';
      emergencyBtn.disabled = false;
    }, 2400);
  }
});

// ── Settings toggles ──
const relaunchToggle = $('#relaunchToggle');
const devToggle = $('#devToggle');
relaunchToggle.addEventListener('change', () => {
  ortus.dispatch('settings:set', { relaunchSlackOnEnd: relaunchToggle.checked });
});
devToggle.addEventListener('change', () => {
  ortus.dispatch('settings:set', { developerMode: devToggle.checked });
});

// ── Tagline easter egg ──
$('#about-tagline').addEventListener('click', () => {
  taglineIndex = (taglineIndex + 1) % TAGLINES.length;
  $('#about-tagline').textContent = TAGLINES[taglineIndex];
});

// ── Ledger ──
async function loadLedger() {
  const records = await ortus.dispatch('intentions:list', { limit: 24 });
  const list = $('#ledger-list');
  $('#ledger-count').textContent = String(records?.length || 0);
  if (!records || records.length === 0) {
    list.innerHTML = '<div class="ledger-empty muted tiny">No intentions yet. Start a focus session.</div>';
    return;
  }
  list.innerHTML = records.map((r) => {
    const date = new Date(r.startedAt);
    const dateStr = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    const timeStr = date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    const o = OUTCOMES[r.reflection?.outcome];
    const outcomeHtml = o
      ? `<span class="ledger-outcome ${o.cls}">${o.label}</span>`
      : `<span class="ledger-outcome out-pending">${r.endedAt ? '—' : 'Active'}</span>`;
    return `<div class="ledger-entry">
      <div class="ledger-date">${dateStr}<br>${timeStr}</div>
      <div class="ledger-intent">${escapeHtml(r.intention)}</div>
      ${outcomeHtml}
    </div>`;
  }).join('');
}
function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

// ── Active focus rendering ──
const idleState = $('.idle-state');
const activeState = $('.active-state');
const activeIntent = $('#active-intent');
const timerText = $('#timer-text');
const timerProgress = $('#timer-progress');
const CIRC = 2 * Math.PI * 93; // r=93

function fmtTimer(ms) {
  if (ms < 0) ms = 0;
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function renderActive() {
  if (!state?.isInFocus) return;
  activeIntent.textContent = state.currentIntention || '—';
  tickActiveTimer();
}

function tickActiveTimer() {
  if (!state?.isInFocus || !state.focusEndsAt || !state.focusStartedAt) return;
  const now = Date.now();
  const total = state.focusEndsAt - state.focusStartedAt;
  const left = Math.max(0, state.focusEndsAt - now);
  const pct = Math.max(0, Math.min(1, left / total));
  timerText.textContent = fmtTimer(left);
  timerProgress.setAttribute('stroke-dashoffset', String(CIRC * (1 - pct)));
}
setInterval(() => { if (state?.isInFocus) tickActiveTimer(); }, 1000);

// ── State subscription ──
function applyState(s) {
  state = s;
  if (s.isInFocus) {
    idleState.classList.add('hidden');
    activeState.classList.remove('hidden');
    renderActive();
  } else {
    activeState.classList.add('hidden');
    idleState.classList.remove('hidden');
  }
  relaunchToggle.checked = !!s.relaunchSlackOnEnd;
  devToggle.checked = !!s.developerMode;
  if (currentTab === 'settings') loadLedger();
}

ortus.onState(applyState);
ortus.getState().then((s) => {
  applyState(s);
  // Initial slider render
  renderSlider(Number(durationInput.value));
  refreshBeginButton();
});
