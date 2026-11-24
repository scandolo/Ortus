// PostHog, cookieless: events stay in memory, nothing is stored on the visitor's device,
// so no cookie banner is needed. Empty key = no tracking and no network calls at all.
(() => {
  const KEY = '';                              // PostHog project API key (phc_…), EU cloud
  const HOST = 'https://eu.i.posthog.com';
  const queue = [];
  const track = (event, props) => (window.posthog && window.posthog.__loaded ? window.posthog.capture(event, props) : queue.push([event, props]));

  // Download clicks: show where the file went, and count which button was used.
  const HINT = 'Downloading. Open Ortus.dmg and drag Ortus to Applications.';
  document.querySelectorAll('[data-download]').forEach((a) => a.addEventListener('click', () => {
    track('download_clicked', { location: a.dataset.download });
    document.querySelectorAll('.install-hint').forEach((h) => { h.textContent = HINT; });
  }));

  if (!KEY) return;

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
    window.posthog.init(KEY, { api_host: HOST, persistence: 'memory', autocapture: false, capture_pageview: true, capture_pageleave: true, disable_session_recording: true });
    queue.splice(0).forEach(([e, p]) => window.posthog.capture(e, p));
  };
  document.head.appendChild(s);
})();
