// QA harness — loads every renderer in a hidden BrowserWindow, captures all
// console output, uncaught errors, preload failures, DOM presence, IPC
// round-trips, and writes a verdict. Exits 0 on clean, 1 on any failure.
//
// Run: npx electron . --qa
// Output: /tmp/ortus-next-qa.md, /tmp/ortus-next-qa.json, /tmp/ortus-next-qa-screenshots/*.png

const path = require('node:path');
const fs = require('node:fs');
const { BrowserWindow, app, screen } = require('electron');

const OUT_MD = '/tmp/ortus-next-qa.md';
const OUT_JSON = '/tmp/ortus-next-qa.json';
const SHOTS_DIR = '/tmp/ortus-next-qa-screenshots';

const RENDERERS = [
  {
    name: 'tray',
    file: 'renderer/tray/index.html',
    width: 420,
    height: 560,
    requiredSelectors: [
      '.tabbar', '.tab[data-tab="focus"]', '.tab[data-tab="settings"]',
      '.focus-pane', '.settings-pane',
      '.sunrise-icon', '.hero-title',
      '.intention-card', '#intention', '.badge-new', '.intention-hint',
      '.duration-card', '#duration', '#sunrise-slider', '#trackFillRect', '#thumb', '#chipPath',
      '#begin',
      // Active state DOM exists even when hidden:
      '.active-state', '.timer-disc', '#timer-text', '#timer-progress', '#extend',
      // Settings:
      '#relaunchToggle', '#devToggle', '#emergency', '#ledger-list', '.about-brand',
    ],
    // Extra screenshot variants: switch to settings tab + simulate active focus
    variants: [
      {
        name: 'tray-settings',
        setup: `
          document.querySelector('.tab[data-tab="settings"]').click();
        `,
      },
      {
        name: 'tray-active',
        setup: `
          // Back to focus tab
          document.querySelector('.tab[data-tab="focus"]').click();
          // Fake state into active mode by tripping the same code paths the IPC would.
          document.querySelector('.idle-state').classList.add('hidden');
          document.querySelector('.active-state').classList.remove('hidden');
          document.querySelector('#active-intent').textContent = 'Ship the bug-fix for the onboarding flow';
          document.querySelector('#timer-text').textContent = '42:18';
          const c = 2 * Math.PI * 93;
          document.querySelector('#timer-progress').setAttribute('stroke-dashoffset', String(c * 0.30));
        `,
      },
    ],
  },
  {
    name: 'now',
    file: 'renderer/now/index.html',
    width: 280,
    height: 76,
    requiredSelectors: ['#totem', '#time', '#intention', '#ring'],
  },
  {
    name: 'reflection',
    file: 'renderer/reflection/index.html',
    width: 460,
    height: 360,
    requiredSelectors: ['#intent-recall', '#note', '#save', '#skip', '.outcome-btn'],
  },
];

const SEVERITIES = { 0: 'verbose', 1: 'info', 2: 'warning', 3: 'error' };

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function probeRenderer(spec) {
  return new Promise((resolve) => {
    const result = {
      name: spec.name,
      file: spec.file,
      passed: false,
      errors: [],
      warnings: [],
      console: [],
      load: { startedAt: Date.now(), finishedAt: null, durationMs: null },
      dom: {},
      crash: null,
      screenshot: null,
    };

    // QA windows: solid OG canvas backdrop so screenshots match production.
    const win = new BrowserWindow({
      width: spec.width,
      height: spec.height,
      show: false,
      frame: false,
      transparent: false,
      backgroundColor: '#1a1a1c',
      webPreferences: {
        preload: path.join(__dirname, 'preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
      },
    });

    let settled = false;
    const settle = (passed, extraErr) => {
      if (settled) return;
      settled = true;
      if (extraErr) result.errors.push(extraErr);
      result.passed = passed && result.errors.length === 0;
      try { if (!win.isDestroyed()) win.destroy(); } catch (_e) {}
      resolve(result);
    };

    win.webContents.on('console-message', (_event, level, message, line, sourceId) => {
      const entry = {
        level: SEVERITIES[level] || `lvl${level}`,
        message,
        line,
        sourceId: sourceId ? path.basename(sourceId) : null,
      };
      result.console.push(entry);
      if (level === 3) result.errors.push(`console.error: ${message} (${entry.sourceId}:${line})`);
      else if (level === 2 && !/Insecure Content-Security-Policy|DevTools/.test(message)) {
        result.warnings.push(`console.warn: ${message} (${entry.sourceId}:${line})`);
      }
    });

    win.webContents.on('preload-error', (_event, preloadPath, err) => {
      result.errors.push(`preload-error: ${err?.stack || err?.message || String(err)}`);
    });

    win.webContents.on('render-process-gone', (_event, details) => {
      result.crash = details;
      result.errors.push(`render-process-gone: ${JSON.stringify(details)}`);
      settle(false);
    });

    win.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL) => {
      result.errors.push(`did-fail-load ${errorCode}: ${errorDescription} (${validatedURL})`);
    });

    win.webContents.on('did-finish-load', async () => {
      result.load.finishedAt = Date.now();
      result.load.durationMs = result.load.finishedAt - result.load.startedAt;

      // Give JS a moment to settle.
      await new Promise((r) => setTimeout(r, 350));

      try {
        const probe = await win.webContents.executeJavaScript(`(() => {
          const out = {};
          const required = ${JSON.stringify(spec.requiredSelectors || [])};
          for (const sel of required) {
            const el = document.querySelector(sel);
            out[sel] = !!el;
          }
          const expected = ${JSON.stringify(spec.expectedText || {})};
          out.__text = {};
          for (const sel of Object.keys(expected)) {
            const el = document.querySelector(sel);
            out.__text[sel] = el ? el.textContent.trim() : null;
          }
          out.__hasOrtus = typeof ortus !== 'undefined' ? true : false;
          out.__bodyChildren = document.body ? document.body.children.length : -1;
          out.__readyState = document.readyState;
          return out;
        })()`);
        result.dom = probe;

        // Verify required selectors all present
        const missing = (spec.requiredSelectors || []).filter((s) => !probe[s]);
        if (missing.length) {
          result.errors.push(`missing DOM: ${missing.join(', ')}`);
        }
        // Verify expected text
        for (const [sel, val] of Object.entries(spec.expectedText || {})) {
          if (probe.__text[sel] !== val) {
            result.errors.push(`text mismatch on ${sel}: expected "${val}", got "${probe.__text[sel]}"`);
          }
        }
        // Verify the contextBridge worked
        if (!probe.__hasOrtus) {
          result.errors.push(`window.ortus not exposed by preload — IPC will be broken`);
        }

        // IPC round-trip: call state:get from this renderer
        const ipcOk = await win.webContents.executeJavaScript(`(async () => {
          try {
            const s = await ortus.getState();
            return { ok: true, hasIsInFocus: 'isInFocus' in s };
          } catch (e) {
            return { ok: false, error: String(e) };
          }
        })()`);
        result.dom.__ipc = ipcOk;
        if (!ipcOk?.ok) {
          result.errors.push(`IPC state:get failed: ${ipcOk?.error}`);
        }

        // Screenshot — default state
        try {
          win.show();
          await new Promise((r) => setTimeout(r, 200));
          const img = await win.webContents.capturePage();
          const shotPath = path.join(SHOTS_DIR, `${spec.name}.png`);
          fs.writeFileSync(shotPath, img.toPNG());
          result.screenshot = shotPath;
        } catch (shotErr) {
          result.warnings.push(`screenshot failed: ${shotErr.message}`);
        }

        // Variant screenshots — run setup JS, then capture again
        result.variantScreenshots = [];
        for (const variant of spec.variants || []) {
          try {
            await win.webContents.executeJavaScript(`(() => { ${variant.setup} })()`);
            await new Promise((r) => setTimeout(r, 220));
            const img = await win.webContents.capturePage();
            const shotPath = path.join(SHOTS_DIR, `${variant.name}.png`);
            fs.writeFileSync(shotPath, img.toPNG());
            result.variantScreenshots.push(shotPath);
          } catch (varErr) {
            result.warnings.push(`variant ${variant.name} failed: ${varErr.message}`);
          }
        }

        settle(true);
      } catch (err) {
        settle(false, `probe threw: ${err.stack || err.message}`);
      }
    });

    win.loadFile(path.join(__dirname, spec.file)).catch((err) => {
      settle(false, `loadFile failed: ${err.message}`);
    });

    setTimeout(() => settle(false, 'timeout after 10s'), 10_000);
  });
}

async function probeIPCFlow() {
  // Exercise the main-process IPC dispatcher end-to-end:
  // simulate a tray click → focus:commitStart → focus state transitions → focus:end.
  // We don't actually kill Slack in QA — we monkey-patch the slack module.
  // We also snapshot intentions.json + state.json and restore them after,
  // so QA never pollutes the user's real ledger.
  const result = { name: '__ipc_flow__', passed: false, errors: [], warnings: [], console: [], steps: [] };

  const userDataDir = app.getPath('userData');
  const intentionsPath = path.join(userDataDir, 'intentions.json');
  const statePath = path.join(userDataDir, 'state.json');
  const intentionsBackup = fs.existsSync(intentionsPath) ? fs.readFileSync(intentionsPath, 'utf8') : null;
  const stateBackup = fs.existsSync(statePath) ? fs.readFileSync(statePath, 'utf8') : null;

  // Monkey-patch slack so we don't kill the user's Slack
  const slackModule = require('./lib/slack');
  const original = { ...slackModule };
  slackModule.pkillSlack = async () => {
    result.steps.push('pkillSlack stubbed');
  };
  slackModule.relaunchSlack = async () => {
    result.steps.push('relaunchSlack stubbed');
  };
  slackModule.startMonitoring = () => {
    result.steps.push('startMonitoring stubbed');
  };
  slackModule.stopMonitoring = () => {
    result.steps.push('stopMonitoring stubbed');
  };
  slackModule.isSlackRunning = async () => false;

  try {
    const focus = require('./lib/focus');
    const store = require('./lib/state');
    const intentions = require('./lib/intentions');

    // Snapshot before
    const before = store.get();
    if (before.isInFocus) {
      // Reset
      store.set({ isInFocus: false, focusStartedAt: null, focusEndsAt: null, currentIntention: null });
    }

    // Start focus
    await focus.start({ intention: 'QA test intention', durationMin: 25 });
    if (!store.get('isInFocus')) result.errors.push('focus.start did not flip isInFocus');
    if (store.get('currentIntention') !== 'QA test intention') {
      result.errors.push(`currentIntention mismatch: ${store.get('currentIntention')}`);
    }
    result.steps.push(`after start: isInFocus=${store.get('isInFocus')}, intention=${store.get('currentIntention')}`);

    const id = store.get('lastReflectionId');
    if (!id) result.errors.push('no reflection id created');
    const opened = intentions.get(id);
    if (!opened) result.errors.push('intentions.get returned null for new session');
    if (opened?.intention !== 'QA test intention') result.errors.push('intentions log intention mismatch');

    // End focus
    const endedId = await focus.endNaturally();
    if (store.get('isInFocus')) result.errors.push('focus did not end');
    if (endedId !== id) result.errors.push('endNaturally returned different id');

    // Save reflection
    intentions.close(id, { reflection: { outcome: 'shipped', note: 'QA close' } });
    const closed = intentions.get(id);
    if (closed?.reflection?.outcome !== 'shipped') result.errors.push('reflection not saved');
    result.steps.push(`after end: reflection.outcome=${closed?.reflection?.outcome}`);

    result.passed = result.errors.length === 0;
  } catch (err) {
    result.errors.push(`ipc flow threw: ${err.stack || err.message}`);
  } finally {
    // Restore slack
    Object.assign(slackModule, original);
    // Restore user data so QA doesn't pollute the ledger
    try {
      if (intentionsBackup !== null) fs.writeFileSync(intentionsPath, intentionsBackup);
      else if (fs.existsSync(intentionsPath)) fs.unlinkSync(intentionsPath);
      if (stateBackup !== null) fs.writeFileSync(statePath, stateBackup);
      else if (fs.existsSync(statePath)) fs.unlinkSync(statePath);
      result.steps.push('user data restored');
    } catch (restoreErr) {
      result.errors.push(`failed to restore user data: ${restoreErr.message}`);
    }
  }
  return result;
}

async function run() {
  ensureDir(SHOTS_DIR);
  // Clear previous shots
  for (const f of fs.readdirSync(SHOTS_DIR)) fs.unlinkSync(path.join(SHOTS_DIR, f));

  const results = [];
  for (const spec of RENDERERS) {
    const r = await probeRenderer(spec);
    results.push(r);
  }
  const ipcResult = await probeIPCFlow();
  results.push(ipcResult);

  const passed = results.filter((r) => r.passed).length;
  const failed = results.filter((r) => !r.passed);

  // Write JSON
  fs.writeFileSync(OUT_JSON, JSON.stringify(results, null, 2));

  // Write markdown report
  const md = [];
  md.push(`# Ortus Next QA Report`);
  md.push(`Run at ${new Date().toISOString()}`);
  md.push(``);
  md.push(`**${passed}/${results.length} passed.** ${failed.length === 0 ? '✅' : '❌'}`);
  md.push(``);
  for (const r of results) {
    md.push(`## ${r.name} ${r.passed ? '✅' : '❌'}`);
    if (r.file) md.push(`- file: \`${r.file}\``);
    if (r.load?.durationMs != null) md.push(`- load: ${r.load.durationMs}ms`);
    if (r.screenshot) md.push(`- screenshot: \`${r.screenshot}\``);
    if (r.dom?.__hasOrtus !== undefined) md.push(`- contextBridge ortus exposed: ${r.dom.__hasOrtus}`);
    if (r.dom?.__ipc) md.push(`- IPC state:get ok: ${r.dom.__ipc.ok}`);
    if (r.steps?.length) {
      md.push(`- steps:`);
      r.steps.forEach((s) => md.push(`  - ${s}`));
    }
    if (r.errors.length) {
      md.push(`- **errors (${r.errors.length}):**`);
      r.errors.forEach((e) => md.push(`  - ${e}`));
    }
    if (r.warnings.length) {
      md.push(`- warnings (${r.warnings.length}):`);
      r.warnings.forEach((w) => md.push(`  - ${w}`));
    }
    const realConsole = (r.console || []).filter((c) =>
      c.level === 'error' || (c.level === 'warning' && !/Insecure Content-Security-Policy|DevTools/.test(c.message))
    );
    if (realConsole.length) {
      md.push(`- console (${realConsole.length}):`);
      realConsole.forEach((c) => md.push(`  - [${c.level}] ${c.message} — ${c.sourceId}:${c.line}`));
    }
    md.push(``);
  }
  fs.writeFileSync(OUT_MD, md.join('\n'));

  // Summary to stderr (visible without log capture quirks)
  process.stderr.write(`\n=== QA SUMMARY ===\n${passed}/${results.length} passed\n`);
  for (const r of failed) {
    process.stderr.write(`FAIL ${r.name}: ${r.errors.join(' | ')}\n`);
  }
  process.stderr.write(`Report: ${OUT_MD}\nJSON:   ${OUT_JSON}\nShots:  ${SHOTS_DIR}\n`);

  // Force-exit so unreferenced setIntervals in main.js don't keep us hanging.
  process.exit(failed.length === 0 ? 0 : 1);
}

module.exports = { run };
