// The hero in three moves: the page scrolls normally until the desktop window fills the
// screen, then the stage sticks and two beats play as you keep scrolling:
// 0 = clutter, 1 = lock in (the page goes dark, the windows go), 2 = clarity (the work rises).
// Each beat plays on its own once its threshold is crossed (CSS does the motion), and the
// thresholds going back are lower than going forward, so it never flickers between beats.
(() => {
  const hero = document.querySelector('.hero');
  const stage = document.querySelector('.stage');
  const box = document.querySelector('.scene-box');
  const phone = matchMedia('(max-width: 719px)');
  let pin = 0;

  // Size the window to the screen and centre the desktop in it. Once pinned, the window sits
  // in the middle of the screen with the same margin above and below.
  // Notifications stay in the window's top-right corner, like on a real Mac (index.html offsets
  // them by --scene-top).
  function fit() {
    const gap = phone.matches ? 16 : 28;
    const [w, h] = phone.matches ? [366, 460] : [1344, 560];
    const s = box.clientWidth / w;
    const natural = h * s;
    const room = innerHeight - gap * 2;
    const boxH = Math.round(phone.matches ? Math.min(room, natural + 64) : Math.max(natural + 48, room));
    box.style.setProperty('--s', s);
    stage.style.setProperty('--box-h', boxH + 'px');
    box.style.setProperty('--scene-top', Math.round((boxH - natural) / 2) + 'px');
    pin = Math.max(0, Math.round(box.offsetTop - Math.max(gap, (innerHeight - boxH) / 2)));
    stage.style.setProperty('--pin', pin + 'px');
  }

  const FORWARD = [0.06, 0.38]; // share of a screen scrolled after the pin starts, to start beat 1, beat 2
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
    const y = (-hero.getBoundingClientRect().top - pin) / innerHeight;
    let next = beat;
    if (next < 1 && y >= FORWARD[0]) next = 1;
    if (next >= 1 && y >= FORWARD[1]) next = 2;
    if (next === 2 && y < BACK[1]) next = 1;
    if (next >= 1 && y < BACK[0]) next = 0;
    set(next);
  }

  fit();
  stage.dataset.beat = '0';
  addEventListener('scroll', update, { passive: true });
  addEventListener('resize', () => { fit(); update(); });
  phone.addEventListener('change', () => { fit(); update(); });
  update();
})();
