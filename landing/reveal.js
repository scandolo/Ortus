// Fades sections in as they enter the screen, once. CSS does the motion (transform and
// opacity only); this only adds the "in" class. Reduced motion or no observer: show at once.
(() => {
  const els = document.querySelectorAll('.reveal');
  const show = (el) => el.classList.add('in');
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) {
    els.forEach(show);
    return;
  }
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { show(e.target); io.unobserve(e.target); }
  }, { rootMargin: '0px 0px -12% 0px' });
  els.forEach((el) => io.observe(el));
})();
