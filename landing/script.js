/* ==========================================================================
   Ortus landing — progressive enhancement only.
   Content is fully visible without JS; this file just adds polish.
   ========================================================================== */
(function () {
  "use strict";

  var prefersReduced =
    window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ----- 1. Nav: hairline border + bg on scroll ----- */
  var nav = document.getElementById("nav");
  if (nav) {
    var onScroll = function () {
      if (window.scrollY > 8) nav.classList.add("is-scrolled");
      else nav.classList.remove("is-scrolled");
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* ----- 2. Scroll-reveal via IntersectionObserver -----
     Mark <html> so CSS hides .reveal elements only when JS is active.
     If motion is reduced or IO is unavailable, leave everything visible. */
  var reveals = document.querySelectorAll(".reveal");

  if (!prefersReduced && "IntersectionObserver" in window && reveals.length) {
    document.documentElement.classList.add("reveal-ready");

    var io = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            obs.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -10% 0px", threshold: 0.1 }
    );

    reveals.forEach(function (el) {
      io.observe(el);
    });
  }

  /* ----- 3. Smooth-scroll for in-page anchors (offset for sticky nav) ----- */
  var navH = nav ? nav.offsetHeight : 0;
  document.querySelectorAll('a[href^="#"]').forEach(function (link) {
    link.addEventListener("click", function (e) {
      var id = link.getAttribute("href");
      if (id === "#" || id.length < 2) return;
      var target = document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      var top =
        target.getBoundingClientRect().top + window.scrollY - navH - 12;
      window.scrollTo({
        top: top,
        behavior: prefersReduced ? "auto" : "smooth"
      });
    });
  });
})();
