// Slack process control — kill on focus start, poll-and-kill while focus is active.
// Loom's architecture uses a Swift sidecar for OS-process visibility; we use
// Node's child_process + `pgrep`/`pkill` polling, which is sufficient for Slack's
// process tree (the macOS Slack app + its helper renderers).

const { execFile, exec } = require('node:child_process');

let monitorTimer = null;

function pkillSlack() {
  return new Promise((resolve) => {
    // Soft quit first via osascript so Slack saves state, then hard pkill for stragglers.
    exec(`osascript -e 'tell application "Slack" to quit'`, () => {
      execFile('pkill', ['-x', 'Slack'], () => {
        execFile('pkill', ['-f', 'Slack Helper'], () => {
          resolve();
        });
      });
    });
  });
}

function isSlackRunning() {
  return new Promise((resolve) => {
    execFile('pgrep', ['-x', 'Slack'], (err, stdout) => {
      resolve(!err && stdout.trim().length > 0);
    });
  });
}

function relaunchSlack() {
  return new Promise((resolve) => {
    execFile('open', ['-a', 'Slack'], () => resolve());
  });
}

function startMonitoring(intervalMs = 1500) {
  stopMonitoring();
  monitorTimer = setInterval(async () => {
    if (await isSlackRunning()) {
      await pkillSlack();
    }
  }, intervalMs);
}

function stopMonitoring() {
  if (monitorTimer) {
    clearInterval(monitorTimer);
    monitorTimer = null;
  }
}

module.exports = { pkillSlack, isSlackRunning, relaunchSlack, startMonitoring, stopMonitoring };
