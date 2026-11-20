/* ==========================================================================
   Ortus landing. Content is visible without this file.
   HERO_HEADLINE lives in index.html. This script only writes it into the h1.
   ========================================================================== */
(function () {
  "use strict";

  var prefersReduced =
    window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Headline. Last line is the amber punch when there is more than one. */
  var title = document.getElementById("hero-title");
  if (title && typeof HERO_HEADLINE === "string" && HERO_HEADLINE.length) {
    var lines = HERO_HEADLINE.split("\n").filter(function (line) { return line.length; });
    title.replaceChildren();
    lines.forEach(function (line, i) {
      var span = document.createElement("span");
      span.className = "hero__line" + (lines.length > 1 && i === lines.length - 1 ? " hero__line--hit" : "");
      span.textContent = line;
      title.appendChild(span);
    });
  }

  /* Session clock in the hero illustration. 9:41, 2:19:00 left, ends at 12:00. */
  var remainEl = document.querySelector("[data-remain]");
  var clockEl = document.querySelector("[data-clock]");
  var untilEl = document.querySelector("[data-until]");
  if (remainEl && clockEl && !prefersReduced) {
    var started = Date.now();
    var remain0 = (2 * 3600 + 19 * 60) * 1000;
    var clock0 = 9 * 3600 + 41 * 60;
    var pad = function (n) { return String(n).padStart(2, "0"); };
    var paint = function () {
      var elapsed = Date.now() - started;
      var remain = Math.max(0, remain0 - elapsed);
      var total = Math.floor(remain / 1000);
      var h = Math.floor(total / 3600);
      var m = Math.floor((total % 3600) / 60);
      var s = total % 60;
      remainEl.textContent = h + ":" + pad(m) + ":" + pad(s);
      var clock = clock0 + Math.floor(elapsed / 1000);
      clockEl.textContent = Math.floor(clock / 3600) + ":" + pad(Math.floor((clock % 3600) / 60));
      if (untilEl && remain === 0) untilEl.textContent = "Session ended";
    };
    paint();
    var timer = setInterval(function () {
      if (document.hidden) return;
      paint();
      if (Date.now() - started >= remain0) clearInterval(timer);
    }, 1000);
  }

  /* Mode tabs. */
  document.querySelectorAll("[data-tabs]").forEach(function (root) {
    var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
    var panels = Array.prototype.slice.call(root.querySelectorAll('[role="tabpanel"]'));
    if (!tabs.length) return;
    var select = function (tab) {
      tabs.forEach(function (t) {
        var on = t === tab;
        t.setAttribute("aria-selected", on ? "true" : "false");
        t.tabIndex = on ? 0 : -1;
      });
      panels.forEach(function (panel) {
        panel.hidden = panel.id !== tab.getAttribute("aria-controls");
      });
    };
    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () { select(tab); });
      tab.addEventListener("keydown", function (e) {
        var next = null;
        if (e.key === "ArrowRight" || e.key === "ArrowDown") next = tabs[(index + 1) % tabs.length];
        else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = tabs[(index - 1 + tabs.length) % tabs.length];
        else if (e.key === "Home") next = tabs[0];
        else if (e.key === "End") next = tabs[tabs.length - 1];
        if (!next) return;
        e.preventDefault();
        select(next);
        next.focus();
      });
    });
  });

  var nav = document.getElementById("nav");
  if (nav) {
    var onScroll = function () {
      if (window.scrollY > 8) nav.classList.add("is-scrolled");
      else nav.classList.remove("is-scrolled");
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

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
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    reveals.forEach(function (el) { io.observe(el); });
  }

  var navH = nav ? nav.offsetHeight : 0;
  document.querySelectorAll('a[href^="#"]').forEach(function (link) {
    link.addEventListener("click", function (e) {
      var id = link.getAttribute("href");
      if (!id || id.length < 2) return;
      var target = document.querySelector(id);
      if (!target || target.tagName === "DIALOG") return;
      e.preventDefault();
      var top = target.getBoundingClientRect().top + window.scrollY - navH - 12;
      window.scrollTo({ top: top, behavior: prefersReduced ? "auto" : "smooth" });
    });
  });

  document.querySelectorAll(".install__copy").forEach(function (btn) {
    var resetTimer = null;
    var label = btn.querySelector(".install__copy-label");
    var originalText = label ? label.textContent : "";
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy") || "";
      if (!text || !navigator.clipboard || !navigator.clipboard.writeText) return;
      navigator.clipboard.writeText(text).then(function () {
        btn.classList.add("is-copied");
        if (label) label.textContent = "Copied";
        if (resetTimer) clearTimeout(resetTimer);
        resetTimer = setTimeout(function () {
          btn.classList.remove("is-copied");
          if (label) label.textContent = originalText;
        }, 1600);
      }, function () {});
    });
  });

  var dl = document.getElementById("download");
  if (dl && typeof dl.showModal === "function") {
    var dlTitle = dl.querySelector(".dl__title");
    var dlAgain = dl.querySelector(".dl__again");
    var openDownload = function (started) {
      var state = started ? "data-started" : "data-idle";
      if (dlTitle) dlTitle.textContent = dlTitle.getAttribute(state);
      if (dlAgain) dlAgain.textContent = dlAgain.getAttribute(state);
      if (!dl.open) dl.showModal();
    };
    document.querySelectorAll("[data-download]").forEach(function (link) {
      link.addEventListener("click", function () { openDownload(true); });
    });
    var openFromHash = function () { if (location.hash === "#download") openDownload(false); };
    window.addEventListener("hashchange", openFromHash);
    openFromHash();
    dl.addEventListener("click", function (e) { if (e.target === dl) dl.close(); });
    dl.addEventListener("close", function () {
      if (location.hash === "#download") history.replaceState(null, "", location.pathname + location.search);
    });
  }
})();
