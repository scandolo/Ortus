// Fits the window mock-ups to their box, and moves the hero through its beats
// as you scroll the pinned section: 0 = clutter, 1 = lock in, 2 = clarity.
// Each beat plays on its own once its scroll threshold is crossed (CSS does the
// motion), and the thresholds going back are lower than going forward, so the
// hero never flickers between beats around one scroll position.
(() => {
  const box = document.querySelector('.scene-box');
  const phone = matchMedia('(max-width: 719px)');
  const fit = () => box.style.setProperty('--s', box.clientWidth / (phone.matches ? 366 : 1344));
  new ResizeObserver(fit).observe(box);
  fit();

  const hero = document.querySelector('.hero');
  const stage = document.querySelector('.stage');
  const FORWARD = [0.06, 0.38]; // share of a screen scrolled into the pin to start beat 1, beat 2
  const BACK = [0.03, 0.28];    // ...and to return from it
  const GAP = 900;              // ms beat 1 gets before beat 2 may start
  let beat = 0, beat1At = 0, timer = 0;

  const set = (next) => {
    if (next === beat) return;
    if (next === 2 && beat === 1 && performance.now() - beat1At < GAP) {
      clearTimeout(timer);
      timer = setTimeout(update, GAP - (performance.now() - beat1At));
      return;
    }
    if (next === 2 && beat === 0) { set(1); return void (timer = setTimeout(update, GAP)); }
    clearTimeout(timer);
    if (next === 1 && beat === 0) beat1At = performance.now();
    beat = next;
    stage.dataset.beat = String(beat);
  };

  function update() {
    const y = -hero.getBoundingClientRect().top / innerHeight;
    let next = beat;
    if (next < 1 && y >= FORWARD[0]) next = 1;
    if (next >= 1 && y >= FORWARD[1]) next = 2;
    if (next === 2 && y < BACK[1]) next = 1;
    if (next >= 1 && y < BACK[0]) next = 0;
    set(next);
  }

  stage.dataset.beat = '0';
  addEventListener('scroll', update, { passive: true });
  addEventListener('resize', update);
  update();
})();
