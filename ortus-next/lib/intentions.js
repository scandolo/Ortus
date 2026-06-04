// Intention log: append-only JSON log of intentions + reflections.
// Lives at ~/Library/Application Support/Ortus Next/intentions.json.
// Format: array of { id, startedAt, endedAt, durationMin, intention, reflection }.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { app } = require('electron');

const FILE = path.join(app.getPath('userData'), 'intentions.json');

function load() {
  try {
    if (!fs.existsSync(FILE)) return [];
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch (err) {
    console.error('[intentions] load failed', err);
    return [];
  }
}

function save(records) {
  try {
    fs.writeFileSync(FILE, JSON.stringify(records, null, 2));
  } catch (err) {
    console.error('[intentions] save failed', err);
  }
}

function open({ intention, durationMin }) {
  const id = crypto.randomUUID();
  const records = load();
  records.push({
    id,
    startedAt: new Date().toISOString(),
    endedAt: null,
    durationMin,
    intention,
    reflection: null,
  });
  save(records);
  return id;
}

function close(id, { reflection, endedAt = new Date().toISOString() }) {
  const records = load();
  const idx = records.findIndex((r) => r.id === id);
  if (idx === -1) return null;
  records[idx] = { ...records[idx], endedAt, reflection };
  save(records);
  return records[idx];
}

function get(id) {
  return load().find((r) => r.id === id) || null;
}

function recent(n = 30) {
  const records = load();
  return records.slice(-n).reverse();
}

module.exports = { open, close, get, recent, load };
