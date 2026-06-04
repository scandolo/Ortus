// Focus state machine. Mediates between intention lifecycle, Slack control,
// state store, and window manager. All transitions flow through here so the
// rest of the app can stay declarative on state changes.

const store = require('./state');
const slack = require('./slack');
const intentions = require('./intentions');

let focusTimer = null;

function activeIntentionId() {
  return store.get('lastReflectionId');
}

async function start({ intention, durationMin }) {
  if (store.get('isInFocus')) return;

  const id = intentions.open({ intention, durationMin });
  const focusStartedAt = Date.now();
  const focusEndsAt = focusStartedAt + durationMin * 60_000;

  store.set({
    isInFocus: true,
    focusStartedAt,
    focusEndsAt,
    currentIntention: intention,
    lastReflectionId: id,
  });

  await slack.pkillSlack();
  slack.startMonitoring();

  scheduleAutoEnd(focusEndsAt);
}

function scheduleAutoEnd(endsAt) {
  if (focusTimer) clearTimeout(focusTimer);
  const delay = Math.max(0, endsAt - Date.now());
  focusTimer = setTimeout(() => {
    endNaturally();
  }, delay);
}

async function endNaturally() {
  if (!store.get('isInFocus')) return;
  slack.stopMonitoring();
  if (focusTimer) {
    clearTimeout(focusTimer);
    focusTimer = null;
  }
  const id = store.get('lastReflectionId');
  store.set({
    isInFocus: false,
    focusEndsAt: null,
  });
  if (store.get('relaunchSlackOnEnd')) {
    await slack.relaunchSlack();
  }
  return id;
}

async function emergencyEnd() {
  if (!store.get('isInFocus')) return;
  const history = store.get('emergencyEndsThisWeek') || [];
  const weekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const recent = history.filter((t) => t > weekAgo);
  if (recent.length >= 1) {
    throw new Error('Emergency end already used this week.');
  }
  const id = await endNaturally();
  store.set({
    emergencyEndsThisWeek: [...recent, Date.now()],
  });
  return id;
}

function elapsedMinutes() {
  const start = store.get('focusStartedAt');
  if (!start) return 0;
  return (Date.now() - start) / 60_000;
}

function remainingMinutes() {
  const end = store.get('focusEndsAt');
  if (!end) return 0;
  return Math.max(0, (end - Date.now()) / 60_000);
}

module.exports = { start, endNaturally, emergencyEnd, elapsedMinutes, remainingMinutes, activeIntentionId };
