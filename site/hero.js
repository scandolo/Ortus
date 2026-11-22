// Fits the window mock-ups to their box, and drives the hero motion from the
// scroll position in browsers without CSS scroll-driven animations.
(() => {
  const box = document.querySelector('.scene-box');
  const phone = matchMedia('(max-width: 719px)');
  const fit = () => box.style.setProperty('--s', box.clientWidth / (phone.matches ? 366 : 1344));
  new ResizeObserver(fit).observe(box);
  fit();

  if (CSS.supports('animation-timeline: view()')) return;
  const hero = document.querySelector('.hero');
  const update = () => {
    const r = hero.getBoundingClientRect();
    const p = Math.min(1, Math.max(0, -r.top / (r.height - innerHeight)));
    document.documentElement.style.setProperty('--p', p.toFixed(4));
  };
  addEventListener('scroll', update, { passive: true });
  addEventListener('resize', update);
  update();
})();
