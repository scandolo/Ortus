// Centralized state with disk persistence + change subscriptions.
// Mirrors Loom's middleware pattern: callers dispatch actions; windows
// react to state changes rather than mutating each other directly.

const fs = require('node:fs');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { app } = require('electron');

const STATE_DIR = path.join(app.getPath('userData'));
const STATE_FILE = path.join(STATE_DIR, 'state.json');

const DEFAULT_STATE = {
  isInFocus: false,
  focusStartedAt: null,
  focusEndsAt: null,
  currentIntention: null,
  relaunchSlackOnEnd: true,
  developerMode: false,
  emergencyEndsThisWeek: [],
  lastReflectionId: null,
};

class Store extends EventEmitter {
  constructor() {
    super();
    this.state = this.#load();
  }

  #load() {
    try {
      if (!fs.existsSync(STATE_DIR)) fs.mkdirSync(STATE_DIR, { recursive: true });
      if (!fs.existsSync(STATE_FILE)) return { ...DEFAULT_STATE };
      const raw = fs.readFileSync(STATE_FILE, 'utf8');
      return { ...DEFAULT_STATE, ...JSON.parse(raw) };
    } catch (err) {
      console.error('[state] load failed, using defaults', err);
      return { ...DEFAULT_STATE };
    }
  }

  #persist() {
    try {
      fs.writeFileSync(STATE_FILE, JSON.stringify(this.state, null, 2));
    } catch (err) {
      console.error('[state] persist failed', err);
    }
  }

  get(key) {
    return key ? this.state[key] : { ...this.state };
  }

  set(patch) {
    const prev = { ...this.state };
    this.state = { ...this.state, ...patch };
    this.#persist();
    this.emit('change', this.state, prev);
  }
}

module.exports = new Store();
