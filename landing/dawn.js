(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const sun = `<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M16 5v4M7.5 9.2l2.4 2.6M24.5 9.2l-2.4 2.6M5 16h3.2M23.8 16H27M6 24h20"/><path fill="currentColor" d="M10 24a6 6 0 0 1 12 0H10z"/></svg>`;

  document.querySelectorAll("[data-sun]").forEach((el) => {
    el.innerHTML = sun;
  });

  setupSky();
  setupRotator();
  setupSlams();
  setupBar();
  setupDemo();
  setupAgent();
  setupCopy();

  function setupSky() {
    const canvas = document.getElementById("sky");
    if (!canvas) return;
    const gl = canvas.getContext("webgl", { antialias: false, alpha: false, powerPreference: "low-power" });
    if (!gl) {
      canvas.remove();
      return;
    }

    const vsSource = "attribute vec2 a;void main(){gl_Position=vec4(a,0.,1.);}";
    const fsSource = `
      precision mediump float;
      uniform vec2 u_res;
      uniform float u_time;
      uniform float u_px;
      void main() {
        vec2 uv = gl_FragCoord.xy / u_res;
        float y = uv.y;
        vec3 top = vec3(0.055, 0.042, 0.034);
        vec3 mid = vec3(0.16, 0.07, 0.035);
        vec3 hor = vec3(0.62, 0.22, 0.06);
        vec3 col = mix(hor, mid, smoothstep(0.0, 0.28, y));
        col = mix(col, top, smoothstep(0.16, 0.78, y));
        float breathe = sin(u_time * 0.7) * 0.012;
        vec2 sun = vec2(0.5 + (u_px - 0.5) * 0.08, 0.02 + breathe);
        vec2 p = uv - sun;
        p.x *= u_res.x / u_res.y;
        float d = length(p);
        float glow = exp(-d * 3.1);
        col += vec3(1.0, 0.52, 0.16) * glow * 0.72;
        float disc = smoothstep(0.145, 0.08, d);
        col = mix(col, vec3(1.0, 0.78, 0.48), disc);
        float horizon = exp(-pow(y * 5.5, 2.0));
        col += vec3(0.95, 0.42, 0.12) * horizon * 0.22;
        float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233)) + u_time) * 43758.5453);
        col += (n - 0.5) * 0.028;
        gl_FragColor = vec4(col, 1.0);
      }
    `;

    function shader(type, source) {
      const s = gl.createShader(type);
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        canvas.remove();
        return null;
      }
      return s;
    }

    const vs = shader(gl.VERTEX_SHADER, vsSource);
    const fs = shader(gl.FRAGMENT_SHADER, fsSource);
    if (!vs || !fs) return;
    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      canvas.remove();
      return;
    }
    gl.useProgram(program);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program, "a");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    const uRes = gl.getUniformLocation(program, "u_res");
    const uTime = gl.getUniformLocation(program, "u_time");
    const uPx = gl.getUniformLocation(program, "u_px");
    let px = 0.5;
    let target = 0.5;
    let running = true;

    function resize() {
      const dpr = Math.min(window.devicePixelRatio || 1, canvas.clientWidth < 800 ? 1.25 : 1.5);
      const w = Math.max(1, canvas.clientWidth);
      const h = Math.max(1, canvas.clientHeight);
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
      gl.viewport(0, 0, canvas.width, canvas.height);
    }

    function draw(now) {
      if (!running) return;
      px += (target - px) * 0.06;
      gl.uniform2f(uRes, canvas.width, canvas.height);
      gl.uniform1f(uTime, reduce ? 0 : now * 0.001);
      gl.uniform1f(uPx, px);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      if (!reduce) requestAnimationFrame(draw);
    }

    resize();
    requestAnimationFrame(draw);
    window.addEventListener("resize", () => {
      resize();
      if (reduce) requestAnimationFrame(draw);
    });
    window.addEventListener("pointermove", (event) => {
      if (event.pointerType !== "mouse") return;
      target = event.clientX / window.innerWidth;
    }, { passive: true });

    const hero = document.querySelector(".hero");
    if (hero && !reduce) {
      const watcher = new IntersectionObserver(([entry]) => {
        const on = entry.isIntersecting;
        if (on && !running) {
          running = true;
          requestAnimationFrame(draw);
        }
        running = on;
      });
      watcher.observe(hero);
    }
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) running = false;
      else if (!reduce) {
        running = true;
        requestAnimationFrame(draw);
      }
    });
  }

  function setupRotator() {
    const el = document.getElementById("rot");
    if (!el || reduce) return;
    const words = ["Slack", "X", "Gmail", "LinkedIn", "Instagram", "YouTube"];
    let index = 0;
    window.setInterval(() => {
      el.classList.add("is-out");
      window.setTimeout(() => {
        index = (index + 1) % words.length;
        el.textContent = words[index];
        el.classList.remove("is-out");
      }, 220);
    }, 2400);
  }

  function setupSlams() {
    const windows = document.querySelectorAll("[data-slam]");
    if (!windows.length) return;
    if (reduce) {
      windows.forEach((el) => el.classList.add("is-shut"));
      return;
    }
    const watcher = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-shut");
        watcher.unobserve(entry.target);
      });
    }, { threshold: 0.55 });
    windows.forEach((el) => watcher.observe(el));
  }

  function setupBar() {
    const bar = document.getElementById("bar");
    const refuse = document.getElementById("refuse");
    const quit = document.getElementById("quit-bar");
    const heroCta = document.getElementById("hero-cta");
    if (!bar || !refuse) return;

    let timer = 0;
    function say(message) {
      refuse.textContent = message;
      refuse.classList.add("is-on");
      bar.classList.remove("is-shaking");
      void bar.offsetWidth;
      bar.classList.add("is-shaking");
      window.clearTimeout(timer);
      timer = window.setTimeout(() => refuse.classList.remove("is-on"), 3400);
    }

    function message() {
      const state = document.body.dataset.session || "idle";
      if (state === "locked" || state === "grace") return "Quitting is blocked while a session is running.";
      if (state === "done") return "The session already ended. The apps it closed stay closed.";
      if (state === "emergency") return "You already used the early end. Quitting is open again.";
      return "Nothing is running yet. Start a session and quit stops working.";
    }

    quit?.addEventListener("click", () => say(message()));
    document.addEventListener("keydown", (event) => {
      const key = event.key.toLowerCase();
      if ((event.metaKey || event.ctrlKey) && key === "q") {
        event.preventDefault();
        say(message());
      }
    });

    if (heroCta) {
      const watcher = new IntersectionObserver(([entry]) => {
        document.body.classList.toggle("show-download", !entry.isIntersecting);
      }, { threshold: 0.15 });
      watcher.observe(heroCta);
    }

    window.ortusSay = say;
  }

  function setupDemo() {
    const panel = document.getElementById("panel");
    if (!panel) return;

    const modes = {
      socials: {
        name: "Socials",
        items: ["LinkedIn", "X", "Instagram", "Facebook", "Reddit", "TikTok"],
        detail: "Websites, including their subdomains."
      },
      messages: {
        name: "Messages",
        items: ["Gmail", "Slack", "WhatsApp"],
        detail: "Gmail is the mail sites only. Slack and WhatsApp are the Mac app and the website."
      },
      everything: {
        name: "Everything",
        items: ["LinkedIn", "X", "Instagram", "Facebook", "Reddit", "TikTok", "Gmail", "Slack", "WhatsApp"],
        detail: "Socials and Messages together."
      }
    };

    let mode = "socials";
    let minutes = 90;
    let state = "idle";
    let endsAt = 0;
    let totalMs = 0;
    let graceEnds = 0;
    let graceTimer = 0;
    let tickTimer = 0;
    const usedKey = "ortus-demo-early-end";

    const slider = document.getElementById("length");
    const minuteEl = document.getElementById("minutes");
    const start = document.getElementById("start");
    const status = document.getElementById("pstatus");
    const barStatus = document.getElementById("bar-status");
    const tags = document.getElementById("tags");
    const detail = document.getElementById("detail");
    const introLine = document.getElementById("intro-line");
    const introTags = document.getElementById("intro-tags");
    const graceNum = document.getElementById("grace-num");
    const graceRing = document.getElementById("grace-ring");
    const lockNum = document.getElementById("lock-num");
    const lockRing = document.getElementById("lock-ring");
    const lockName = document.getElementById("lock-name");
    const lockTags = document.getElementById("lock-tags");
    const earlyBox = document.getElementById("early-confirm");
    const earlyUsed = document.getElementById("early-used");

    function label(value) {
      if (value >= 180) return "Enter monk mode";
      if (value >= 90) return "Go all in";
      if (value >= 60) return "Go deep";
      return "Start focus";
    }

    function paintTags(node, items) {
      node.replaceChildren(...items.map((name) => {
        const span = document.createElement("span");
        span.textContent = name;
        return span;
      }));
    }

    function percent(value) {
      return ((value - 15) / (240 - 15)) * 100;
    }

    function setLength(value) {
      minutes = value;
      minuteEl.textContent = String(value);
      start.textContent = label(value);
      slider.style.setProperty("--p", `${percent(value)}%`);
      slider.value = String(value);
    }

    function setMode(next) {
      mode = next;
      panel.querySelectorAll("[data-mode]").forEach((button) => {
        button.setAttribute("aria-checked", button.dataset.mode === next ? "true" : "false");
      });
      paintTags(tags, modes[next].items);
      detail.textContent = modes[next].detail;
    }

    function clock(date) {
      let hours = date.getHours();
      const mins = String(date.getMinutes()).padStart(2, "0");
      const suffix = hours >= 12 ? "pm" : "am";
      hours = hours % 12 || 12;
      return `${hours}:${mins} ${suffix}`;
    }

    function format(ms) {
      const seconds = Math.max(0, Math.ceil(ms / 1000));
      const h = Math.floor(seconds / 3600);
      const m = Math.floor((seconds % 3600) / 60);
      const s = seconds % 60;
      if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
      return `${m}:${String(s).padStart(2, "0")}`;
    }

    function ring(el, progress) {
      const offset = 540.35 * (1 - Math.max(0, Math.min(1, progress)));
      el.style.strokeDashoffset = String(offset);
    }

    function clearTimers() {
      window.clearInterval(graceTimer);
      window.clearInterval(tickTimer);
    }

    function show(next) {
      state = next;
      document.body.dataset.session = next;
      panel.querySelectorAll("[data-state]").forEach((view) => {
        view.hidden = view.dataset.state !== next;
      });
      const names = {
        idle: "Ready",
        intro: "Confirm",
        grace: "Starting",
        locked: "Locked",
        done: "Ended",
        emergency: "Unlocked"
      };
      status.textContent = names[next];
      if (next !== "locked" && next !== "grace") barStatus.textContent = names[next] === "Ready" ? "No session" : names[next];
    }

    function lockIn() {
      clearTimers();
      show("locked");
      totalMs = minutes * 60 * 1000;
      endsAt = Date.now() + totalMs;
      lockName.textContent = modes[mode].name;
      paintTags(lockTags, modes[mode].items);
      earlyBox.hidden = true;
      earlyUsed.hidden = true;
      tick();
      tickTimer = window.setInterval(tick, 250);
    }

    function tick() {
      const left = endsAt - Date.now();
      if (left <= 0) {
        clearTimers();
        show("done");
        barStatus.textContent = "Ended";
        return;
      }
      const text = format(left);
      lockNum.textContent = text;
      barStatus.textContent = text;
      ring(lockRing, left / totalMs);
    }

    function startGrace() {
      show("grace");
      graceEnds = Date.now() + 30000;
      const paint = () => {
        const left = graceEnds - Date.now();
        if (left <= 0) {
          window.clearInterval(graceTimer);
          lockIn();
          return;
        }
        const seconds = Math.ceil(left / 1000);
        graceNum.textContent = String(seconds);
        barStatus.textContent = `${seconds}s`;
        ring(graceRing, left / 30000);
      };
      paint();
      graceTimer = window.setInterval(paint, 100);
    }

    slider.addEventListener("input", () => setLength(Number(slider.value)));
    panel.querySelectorAll("[data-mode]").forEach((button) => {
      button.addEventListener("click", () => setMode(button.dataset.mode));
    });

    start.addEventListener("click", () => {
      clearTimers();
      const until = new Date(Date.now() + minutes * 60 * 1000);
      introLine.textContent = `30 seconds to undo, then locked for ${minutes} minutes, until ${clock(until)}.`;
      paintTags(introTags, modes[mode].items);
      show("intro");
    });

    document.getElementById("intro-back").addEventListener("click", () => {
      show("idle");
    });
    document.getElementById("understood").addEventListener("click", startGrace);
    document.getElementById("nevermind").addEventListener("click", () => {
      clearTimers();
      show("idle");
      barStatus.textContent = "No session";
    });
    document.getElementById("skip").addEventListener("click", lockIn);
    document.getElementById("add15").addEventListener("click", () => {
      if (state !== "locked") return;
      endsAt += 15 * 60 * 1000;
      totalMs += 15 * 60 * 1000;
      tick();
    });
    document.getElementById("quit-session").addEventListener("click", () => {
      window.ortusSay?.("Quitting is blocked while a session is running.");
    });
    document.getElementById("early").addEventListener("click", () => {
      if (sessionStorage.getItem(usedKey) === "1") {
        earlyBox.hidden = true;
        earlyUsed.hidden = false;
        return;
      }
      earlyUsed.hidden = true;
      earlyBox.hidden = false;
    });
    document.getElementById("early-cancel").addEventListener("click", () => {
      earlyBox.hidden = true;
    });
    document.getElementById("early-yes").addEventListener("click", () => {
      clearTimers();
      sessionStorage.setItem(usedKey, "1");
      show("emergency");
      barStatus.textContent = "Unlocked";
    });
    document.querySelectorAll("[data-again]").forEach((button) => {
      button.addEventListener("click", () => {
        clearTimers();
        show("idle");
        barStatus.textContent = "No session";
      });
    });

    setLength(90);
    setMode("socials");
    show("idle");
  }

  function setupAgent() {
    const log = document.getElementById("chat-log");
    const buttons = document.querySelectorAll("[data-ask]");
    if (!log || !buttons.length) return;
    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        buttons.forEach((other) => other.setAttribute("aria-pressed", other === button ? "true" : "false"));
        log.replaceChildren();
        const ask = document.createElement("p");
        ask.className = "ask";
        ask.textContent = button.dataset.ask;
        const ans = document.createElement("p");
        ans.className = "ans";
        const ex = document.createElement("span");
        ex.className = "ex";
        ex.textContent = "Example";
        ans.append(ex, document.createTextNode(` ${button.dataset.answer}`));
        log.append(ask, ans);
      });
    });
  }

  function setupCopy() {
    document.querySelectorAll("[data-copy]").forEach((button) => {
      button.addEventListener("click", async () => {
        const text = button.dataset.copy;
        try {
          await navigator.clipboard.writeText(text);
        } catch {
          const area = document.createElement("textarea");
          area.value = text;
          area.setAttribute("readonly", "");
          area.style.position = "fixed";
          area.style.left = "-999px";
          document.body.append(area);
          area.select();
          document.execCommand("copy");
          area.remove();
        }
        const previous = button.textContent;
        button.textContent = "Copied";
        window.setTimeout(() => {
          button.textContent = previous;
        }, 1600);
      });
    });
  }
})();
