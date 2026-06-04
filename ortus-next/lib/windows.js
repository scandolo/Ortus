// Window manager — Loom's "treat each surface as its own window" pattern.
// Three surfaces in this version:
//   1. The tray popover (the whole app — tabs inside)
//   2. The floating "Now" totem (always-on-top reminder during focus)
//   3. The reflection window (appears once at focus end)
//
// We dropped the intention-overlay full-screen window and the main settings
// window: intentions now live inline in the tray popover, settings is a tab,
// and the ledger is a section within settings — matching OG Ortus's single
// MenuBarExtra popover model.

const path = require('node:path');
const { BrowserWindow, screen, Tray, nativeImage } = require('electron');
const store = require('./state');

const windows = {
  tray: null,
  now: null,
  reflection: null,
};

let trayInstance = null;
let trayBounds = null;

function rendererPath(folder, file = 'index.html') {
  return path.join(__dirname, '..', 'renderer', folder, file);
}

function preloadPath() {
  return path.join(__dirname, '..', 'preload.js');
}

function baseWebPreferences() {
  return {
    preload: preloadPath(),
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: false,
  };
}

// ── Tray popover: 420 × 560, matches OG ContentView dimensions ──
function createTrayWindow() {
  const w = new BrowserWindow({
    width: 420,
    height: 560,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    transparent: true,
    hasShadow: true,
    webPreferences: baseWebPreferences(),
  });
  w.loadFile(rendererPath('tray'));
  w.on('blur', () => {
    if (!w.webContents.isDevToolsOpened()) w.hide();
  });
  windows.tray = w;
  return w;
}

function toggleTrayWindow() {
  const w = windows.tray || createTrayWindow();
  if (w.isVisible()) { w.hide(); return; }
  positionTrayWindow(w);
  w.show();
  w.focus();
}

function positionTrayWindow(w) {
  if (!trayBounds) return;
  const winBounds = w.getBounds();
  const display = screen.getDisplayMatching(trayBounds);
  const x = Math.round(
    Math.min(
      Math.max(trayBounds.x + trayBounds.width / 2 - winBounds.width / 2, display.workArea.x + 6),
      display.workArea.x + display.workArea.width - winBounds.width - 6,
    ),
  );
  const y = Math.round(trayBounds.y + trayBounds.height + 4);
  w.setPosition(x, y, false);
}

// ── Floating Now totem ──
function showNowWidget() {
  if (windows.now) { windows.now.show(); return windows.now; }
  const display = screen.getPrimaryDisplay();
  const width = 280;
  const height = 76;
  const margin = 24;
  const w = new BrowserWindow({
    width, height,
    x: display.workArea.x + display.workArea.width - width - margin,
    y: display.workArea.y + display.workArea.height - height - margin,
    frame: false,
    transparent: true,
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    hasShadow: false,
    focusable: false,
    webPreferences: baseWebPreferences(),
  });
  w.setAlwaysOnTop(true, 'floating');
  w.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  w.loadFile(rendererPath('now'));
  w.once('ready-to-show', () => w.showInactive());
  w.on('closed', () => (windows.now = null));
  windows.now = w;
  return w;
}

function closeNowWidget() {
  if (windows.now) {
    windows.now.destroy();
    windows.now = null;
  }
}

// ── Reflection window ──
function showReflectionWindow(reflectionId) {
  if (windows.reflection) {
    windows.reflection.show();
    windows.reflection.focus();
    return windows.reflection;
  }
  const display = screen.getPrimaryDisplay();
  const width = 460;
  const height = 360;
  const w = new BrowserWindow({
    width, height,
    x: Math.round(display.workArea.x + display.workArea.width / 2 - width / 2),
    y: Math.round(display.workArea.y + display.workArea.height / 2 - height / 2),
    frame: false,
    transparent: true,
    resizable: false,
    skipTaskbar: true,
    hasShadow: true,
    alwaysOnTop: true,
    webPreferences: baseWebPreferences(),
  });
  w.loadFile(rendererPath('reflection'));
  w.once('ready-to-show', () => {
    w.show();
    w.focus();
    w.webContents.send('reflection:hydrate', { reflectionId });
  });
  w.on('closed', () => (windows.reflection = null));
  windows.reflection = w;
  return w;
}

function broadcastState() {
  const snapshot = store.get();
  Object.values(windows).forEach((w) => {
    if (w && !w.isDestroyed()) {
      w.webContents.send('state:update', snapshot);
    }
  });
}

function setupTray(iconPath, onClick) {
  const image = nativeImage.createFromPath(iconPath);
  image.setTemplateImage(true);
  trayInstance = new Tray(image);
  trayInstance.setToolTip('Ortus Next');
  trayInstance.on('click', (_e, bounds) => { trayBounds = bounds; onClick(); });
  trayInstance.on('right-click', (_e, bounds) => { trayBounds = bounds; onClick(); });
  return trayInstance;
}

module.exports = {
  windows,
  setupTray,
  toggleTrayWindow,
  showNowWidget,
  closeNowWidget,
  showReflectionWindow,
  broadcastState,
};
