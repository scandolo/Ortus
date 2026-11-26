// PostHog, EU cloud. One first-party cookie holds a random visitor ID, so a return visit counts as
// the same visitor. /?notrack turns tracking off in that browser, /?track turns it back on.
// Empty key = no tracking and no network calls at all.
(() => {
  const KEY = 'phc_AJfuPPimgTTkTBAq4piciZ5HpmfViM3jCRE98R7pUEqa';                              // PostHog project API key (public by design), EU cloud
  const HOST = 'https://eu.i.posthog.com';
  const queue = [];
  const track = (event, props) => (window.posthog && window.posthog.__loaded ? window.posthog.capture(event, props) : queue.push([event, props]));

  // Download clicks: count which button was used, and show one toast with the install steps.
  const toast = document.getElementById('download-toast');
  let hideTimer = 0;
  const hideToast = () => { toast.classList.remove('show'); setTimeout(() => { toast.hidden = true; }, 450); };
  toast.querySelector('.toast-close').addEventListener('click', hideToast);
  document.querySelectorAll('[data-download]').forEach((a) => a.addEventListener('click', () => {
    track('download_clicked', { location: a.dataset.download });
    clearTimeout(hideTimer);
    toast.hidden = false;
    requestAnimationFrame(() => toast.classList.add('show'));
    hideTimer = setTimeout(hideToast, 9000);
  }));

  // A per-browser off switch, for our own visits and for anyone who'd rather not be counted.
  let off = false;
  try {
    const q = new URLSearchParams(location.search);
    if (q.has('track')) localStorage.removeItem('ortus-notrack');
    if (q.has('notrack')) { localStorage.setItem('ortus-notrack', '1'); alert('Done: visits from this browser won’t be counted.'); }
    off = localStorage.getItem('ortus-notrack') === '1';
  } catch (_) {}
  if (!KEY || off) return;

  // How far people get: each section once, and scroll depth in quarters.
  const io = new IntersectionObserver((entries) => entries.forEach((e) => {
    if (e.isIntersecting) { track('section_reached', { section: e.target.getAttribute('aria-labelledby') || 'hero' }); io.unobserve(e.target); }
  }), { threshold: 0.4 });
  document.querySelectorAll('main > section').forEach((s) => io.observe(s));
  const marks = [25, 50, 75, 100]; let next = 0;
  addEventListener('scroll', () => {
    const depth = (scrollY + innerHeight) / document.documentElement.scrollHeight * 100;
    while (next < marks.length && depth >= marks[next]) track('scroll_depth', { percent: marks[next++] });
  }, { passive: true });

  const s = document.createElement('script');
  s.src = 'https://eu-assets.i.posthog.com/static/array.js';
  s.async = true;
  s.onload = () => {
    window.posthog.init(KEY, {
      api_host: HOST, persistence: 'cookie', autocapture: false, capture_pageview: true, capture_pageleave: true,
      // Only what the privacy page lists: no recordings, heatmaps, performance data, dead clicks or surveys,
      // even if they're switched on in the PostHog project.
      disable_session_recording: true, capture_heatmaps: false, capture_performance: false, capture_dead_clicks: false, disable_surveys: true,
    });
    queue.splice(0).forEach(([e, p]) => window.posthog.capture(e, p));
  };
  document.head.appendChild(s);
})();
