/* ==========================================================================
   Ortus landing - progressive enhancement only.
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

  /* ----- 4. Copy-to-clipboard for install command blocks ----- */
  document.querySelectorAll(".install__copy").forEach(function (btn) {
    var resetTimer = null;
    var label = btn.querySelector(".install__copy-label");
    var originalText = label ? label.textContent : "";

    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy") || "";
      if (!text || !navigator.clipboard || !navigator.clipboard.writeText) {
        return;
      }

      navigator.clipboard.writeText(text).then(
        function () {
          btn.classList.add("is-copied");
          if (label) label.textContent = "Copied!";
          if (resetTimer) clearTimeout(resetTimer);
          resetTimer = setTimeout(function () {
            btn.classList.remove("is-copied");
            if (label) label.textContent = originalText;
          }, 1600);
        },
        function () {
          /* clipboard write failed - leave button unchanged */
        }
      );
    });
  });
  /* ----- 5. Interactive mockup tabs (Focus / Schedule / Chat / Settings) ----- */
  document.querySelectorAll(".popover").forEach(function (pop) {
    var tabs = pop.querySelectorAll(".tab");
    var panels = pop.querySelectorAll(".panel");
    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        var name = tab.getAttribute("data-panel");
        tabs.forEach(function (t) {
          t.classList.toggle("tab--active", t === tab);
          t.setAttribute("aria-selected", t === tab ? "true" : "false");
        });
        panels.forEach(function (p) {
          var match = p.getAttribute("data-panel") === name;
          p.hidden = !match;
          p.classList.toggle("panel--active", match);
        });
      });
    });
  });
})();
