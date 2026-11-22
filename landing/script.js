(function () {
  var el = document.querySelector("[data-rotate]");
  if (!el) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  var words = ["Slack", "X", "Gmail"];
  var i = 0;
  window.setInterval(function () {
    i = (i + 1) % words.length;
    el.textContent = words[i];
  }, 2200);
})();
