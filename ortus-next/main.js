// Electron main process. Owns the app lifecycle, the tray, the IPC dispatcher,
// and orchestrates window surfaces in response to state changes.

const path = require('node:path');
const { app, ipcMain, dialog } = require('electron');
const store = require('./lib/state');
const focus = require('./lib/focus');
const slack = require('./lib/slack');
const intentions = require('./lib/intentions');
const wm = require('./lib/windows');

const QA_MODE = process.argv.includes('--qa');

// In QA mode, don't take the single-instance lock (so QA can run while a
// foreground instance is up) and don't register the tray.
if (!QA_MODE) {
  const gotLock = app.requestSingleInstanceLock();
  if (!gotLock) {
    app.quit();
    process.exit(0);
  }
}

// LSUIElement: no dock icon. Equivalent to the Info.plist setting in old Ortus.
if (app.dock) app.dock.hide();

let quitBlockedNotified = 0;

// Block quit while focus is active. The Loom-style equivalent of old Ortus's
// applicationShouldTerminate cancel.
app.on('before-quit', (e) => {
  if (store.get('isInFocus')) {
    e.preventDefault();
    const now = Date.now();
    if (now - quitBlockedNotified > 2000) {
      quitBlockedNotified = now;
      dialog.showMessageBox({
        type: 'info',
        title: 'Focus is active',
        message: 'Ortus Next is keeping you focused.',
        detail: 'You cannot quit while a focus session is running. Use Emergency end from the menu bar if you must.',
        buttons: ['OK'],
        defaultId: 0,
      });
    }
  }
});

function dispatch(action, payload) {
  switch (action) {
    case 'focus:start':
      return commitFocusStart(payload);
    case 'focus:extend':
      return extendFocus(payload?.minutes || 15);
    case 'focus:emergencyEnd':
      return commitEmergencyEnd();
    case 'focus:end':
      return focus.endNaturally().then((id) => {
        wm.closeNowWidget();
        wm.broadcastState();
        if (id) wm.showReflectionWindow(id);
        return { ok: true };
      });
    case 'reflection:save':
      return saveReflection(payload);
    case 'tray:toggle':
      wm.toggleTrayWindow();
      return { ok: true };
    case 'tray:hide':
      if (wm.windows.tray) wm.windows.tray.hide();
      return { ok: true };
    case 'intentions:list':
      return intentions.recent(payload?.limit || 30);
    case 'intentions:get':
      return intentions.get(payload?.id);
    case 'focus:remaining':
      return { remaining: focus.remainingMinutes(), elapsed: focus.elapsedMinutes() };
    case 'settings:set':
      store.set(payload || {});
      return { ok: true };
    case 'app:quit':
      if (store.get('isInFocus')) return { ok: false, error: 'focus active' };
      app.quit();
      return { ok: true };
    default:
      return { ok: false, error: `unknown action ${action}` };
  }
}

function extendFocus(minutes) {
  if (!store.get('isInFocus')) return { ok: false, error: 'not in focus' };
  const newEnd = (store.get('focusEndsAt') || Date.now()) + minutes * 60_000;
  store.set({ focusEndsAt: newEnd });
  return { ok: true, focusEndsAt: newEnd };
}

async function commitFocusStart({ intention, durationMin }) {
  const cleanIntention = (intention || '').trim();
  if (!cleanIntention) return { ok: false, error: 'intention required' };
  const minutes = Math.max(15, Math.min(240, Number(durationMin) || 60));
  await focus.start({ intention: cleanIntention, durationMin: minutes });
  wm.showNowWidget();
  wm.broadcastState();
  // Hide the tray popover so the user goes straight into focus
  if (wm.windows.tray) wm.windows.tray.hide();
  return { ok: true };
}

async function commitEmergencyEnd() {
  try {
    const id = await focus.emergencyEnd();
    wm.closeNowWidget();
    wm.broadcastState();
    if (id) wm.showReflectionWindow(id);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

function saveReflection({ id, outcome, note }) {
  const closed = intentions.close(id, {
    reflection: { outcome, note: (note || '').trim() || null },
  });
  if (wm.windows.reflection) wm.windows.reflection.close();
  wm.broadcastState();
  return { ok: true, record: closed };
}

// Wire IPC
ipcMain.handle('state:get', () => store.get());
ipcMain.handle('action', async (_e, action, payload) => {
  try {
    return await dispatch(action, payload);
  } catch (err) {
    console.error('[dispatch]', action, err);
    return { ok: false, error: err.message };
  }
});

// Background timers: only register in production. QA mode skips them so the
// event loop can exit cleanly when the QA report is written.
function startBackgroundTimers() {
  setInterval(() => {
    if (store.get('isInFocus')) {
      if (wm.windows.now && !wm.windows.now.isDestroyed()) {
        wm.windows.now.webContents.send('focus:tick', {
          remaining: focus.remainingMinutes(),
          elapsed: focus.elapsedMinutes(),
          intention: store.get('currentIntention'),
        });
      }
    }
  }, 1000);

  setInterval(async () => {
    const endsAt = store.get('focusEndsAt');
    if (store.get('isInFocus') && endsAt && Date.now() >= endsAt) {
      const id = await focus.endNaturally();
      wm.closeNowWidget();
      wm.broadcastState();
      if (id) wm.showReflectionWindow(id);
    }
  }, 5000);
}

// Broadcast state on every change to all open windows.
store.on('change', () => wm.broadcastState());

app.whenReady().then(async () => {
  if (QA_MODE) {
    const qa = require('./qa');
    await qa.run();
    return;
  }
  startBackgroundTimers();
  const iconPath = path.join(__dirname, 'assets', 'tray-iconTemplate.png');
  try {
    wm.setupTray(iconPath, () => wm.toggleTrayWindow());
    require('node:fs').appendFileSync('/tmp/ortus-next-boot.log',
      `[${new Date().toISOString()}] tray ok at ${iconPath}\n`);
  } catch (err) {
    require('node:fs').appendFileSync('/tmp/ortus-next-boot.log',
      `[${new Date().toISOString()}] tray FAILED: ${err.stack}\n`);
  }
});

app.on('window-all-closed', (e) => {
  // Menu bar app — never quit on last window close.
  e.preventDefault?.();
});
