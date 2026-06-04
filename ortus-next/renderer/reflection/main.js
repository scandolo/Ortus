// `ortus` is exposed as a global via contextBridge in preload.js.
let reflectionId = null;
let outcome = null;

const intentRecall = document.getElementById('intent-recall');
const noteEl = document.getElementById('note');
const saveBtn = document.getElementById('save');
const skipBtn = document.getElementById('skip');

ortus.onChannel('reflection:hydrate', async ({ reflectionId: id }) => {
  reflectionId = id;
  const record = await ortus.dispatch('intentions:get', { id });
  if (record?.intention) {
    intentRecall.textContent = record.intention;
  }
});

document.querySelectorAll('.outcome-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.outcome-btn').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    outcome = btn.dataset.outcome;
    saveBtn.disabled = false;
  });
});

saveBtn.addEventListener('click', async () => {
  if (!reflectionId || !outcome) return;
  await ortus.dispatch('reflection:save', {
    id: reflectionId,
    outcome,
    note: noteEl.value,
  });
});

skipBtn.addEventListener('click', () => window.close());

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.close();
});
