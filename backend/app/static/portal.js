/* Scan4Disease portal — hand-written vanilla JS, no libraries, no build step.
   Jobs: (1) theme toggle, (2) a shared morph() using the View Transitions API with a FLIP
   fallback, (3) the R4 info-tab controller, (4) the R6 dropdown niceties (Esc / click-away).
   Everything degrades: with JS off, <details> menus and the tab panels still work. */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* --- 0. platform kbd hint --------------------------------------------------------- */
  // On non-Mac we show "Ctrl" instead of "⌘" in the header search kbd badge. The
  // keyboard binding accepts both (Meta on Mac, Ctrl on Windows/Linux).
  (function () {
    var isMac = /Mac|iP(hone|ad|od)/.test(navigator.platform || "");
    if (isMac) return;
    document.querySelectorAll("[data-cmdk-mod]").forEach(function (el) {
      el.textContent = "Ctrl";
      el.style.fontSize = ".68rem";
    });
  })();

  /* --- 0b. sound theme ------------------------------------------------------------
     A cohesive, DELIBERATELY SUBTLE audio layer, synthesised live with the Web
     Audio API — no sample files to ship, and every cue is a soft, short, low-gain
     tone so it reads as tactile feedback, never a jingle. One shared, lazily
     created AudioContext (browsers require a user gesture before audio, so it is
     unlocked on the first pointer/key event). Muteable via the header speaker
     toggle; the choice persists in localStorage and is mirrored on <html> as
     data-sound so the icon reflects state even before this script runs.
     The same palette is mirrored in the Flutter app's SoundService so web and
     app feel like one product. */
  var Sound = (function () {
    var KEY = "s4d-sound";
    var enabled = true;
    try { enabled = localStorage.getItem(KEY) !== "off"; } catch (e) {}
    document.documentElement.setAttribute("data-sound", enabled ? "on" : "off");

    var ctx = null, master = null;
    function ensureCtx() {
      if (ctx) return ctx;
      var AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      try {
        ctx = new AC();
        master = ctx.createGain();
        master.gain.value = 0.85;   // per-cue gains stay low; this is a safety ceiling
        master.connect(ctx.destination);
      } catch (e) { ctx = null; }
      return ctx;
    }
    function resume() {
      var c = ensureCtx();
      if (c && c.state === "suspended") c.resume().catch(function () {});
    }
    // Unlock the context on the first gesture (autoplay policy).
    ["pointerdown", "keydown", "touchstart"].forEach(function (ev) {
      window.addEventListener(ev, resume, { passive: true });
    });

    // One shaped voice: an oscillator with an optional pitch glide, a soft
    // gain envelope, and an optional lowpass so nothing is ever harsh.
    function voice(o) {
      var c = ensureCtx();
      if (!c) return;
      if (c.state === "suspended") c.resume().catch(function () {});
      var t0 = c.currentTime + (o.delay || 0);
      var dur = o.dur || 0.12;
      var osc = c.createOscillator();
      var gain = c.createGain();
      osc.type = o.type || "sine";
      osc.frequency.setValueAtTime(o.freq, t0);
      if (o.to) {
        var glide = o.glide === "linear" ? "linearRampToValueAtTime" : "exponentialRampToValueAtTime";
        osc.frequency[glide](Math.max(1, o.to), t0 + dur);
      }
      if (o.detune) osc.detune.setValueAtTime(o.detune, t0);
      var peak = o.gain == null ? 0.05 : o.gain;
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(peak, t0 + (o.attack || 0.006));
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      var tail = osc;
      if (o.cutoff) {
        var lp = c.createBiquadFilter();
        lp.type = "lowpass";
        lp.frequency.value = o.cutoff;
        osc.connect(lp); lp.connect(gain);
      } else {
        osc.connect(gain);
      }
      gain.connect(master);
      osc.start(t0);
      osc.stop(t0 + dur + 0.03);
    }
    function seq(notes) { if (enabled) notes.forEach(voice); }

    var api = {
      isOn: function () { return enabled; },
      set: function (on) {
        enabled = !!on;
        try { localStorage.setItem(KEY, enabled ? "on" : "off"); } catch (e) {}
        document.documentElement.setAttribute("data-sound", enabled ? "on" : "off");
      },
      toggle: function () { api.set(!enabled); return enabled; },

      // Soft muted click — the workhorse for buttons, links, chips.
      tap: function () { seq([{ freq: 320, to: 190, type: "triangle", gain: 0.035, dur: 0.055, cutoff: 1800 }]); },
      // Barely-there hover tick.
      hover: function () { seq([{ freq: 660, type: "sine", gain: 0.014, dur: 0.04, cutoff: 2600 }]); },
      // Two-note affirm for a state flip (theme / sound / motion).
      toggleTick: function () { seq([
        { freq: 520, type: "sine", gain: 0.04, dur: 0.07 },
        { freq: 780, type: "sine", gain: 0.04, dur: 0.09, delay: 0.06 }
      ]); },
      // Crisp per-notch tick as the patient dial rotates one step — brighter and
      // shorter than `tap` so a fast spin reads as a row of ticks, not taps.
      dialTick: function () { seq([{ freq: 880, to: 720, type: "triangle", gain: 0.03, dur: 0.035, cutoff: 3200 }]); },
      // Distinct rising two-note lock-in when a patient is finally selected —
      // clearly different from the rotation tick so "landed" is unmistakable.
      select: function () { seq([
        { freq: 600, type: "sine", gain: 0.045, dur: 0.08 },
        { freq: 900, to: 1050, type: "sine", gain: 0.05, dur: 0.16, delay: 0.07 }
      ]); },
      // Panels rising / settling.
      open: function () { seq([
        { freq: 440, to: 660, type: "sine", gain: 0.035, dur: 0.13, cutoff: 2600 },
        { freq: 880, type: "sine", gain: 0.02, dur: 0.10, delay: 0.05 }
      ]); },
      close: function () { seq([{ freq: 620, to: 380, type: "sine", gain: 0.03, dur: 0.12, cutoff: 2200 }]); },
      // Refresh whoosh — quick upward triangle sweep.
      refresh: function () { seq([{ freq: 300, to: 900, type: "triangle", gain: 0.03, dur: 0.22, cutoff: 3200 }]); },
      // Outgoing message blip.
      send: function () { seq([{ freq: 540, to: 820, type: "sine", gain: 0.03, dur: 0.10 }]); },
      // Warm major arpeggio — E5 · G#5 · B5 · E6 — quiet and brief.
      success: function () { seq([
        { freq: 659.25, type: "sine", gain: 0.05, dur: 0.16 },
        { freq: 830.61, type: "sine", gain: 0.05, dur: 0.16, delay: 0.075 },
        { freq: 987.77, type: "sine", gain: 0.05, dur: 0.18, delay: 0.15 },
        { freq: 1318.5, type: "sine", gain: 0.045, dur: 0.30, delay: 0.225 }
      ]); },
      // Gentle two-note descent for a failed action — soft, not a buzzer.
      error: function () { seq([
        { freq: 300, type: "triangle", gain: 0.045, dur: 0.16, cutoff: 1400 },
        { freq: 220, type: "triangle", gain: 0.05, dur: 0.26, cutoff: 1200, delay: 0.12, detune: -8 }
      ]); }
    };
    return api;
  })();
  window.s4dSound = Sound;

  /* --- 1. theme toggle ------------------------------------------------------------- */
  var root = document.documentElement;
  function currentTheme() {
    return root.getAttribute("data-theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  }
  // Smooth theme swap: paint a short cross-fade over the colour change by
  // enabling a global transition only for the duration of the switch. Gated so
  // it never runs on first paint (which would flash every element on load).
  var themeAnimTimer = null;
  function swapTheme(next) {
    // Set the attribute synchronously so currentTheme() is never stale (rapid
    // toggles stay in sync). The .theme-animating class supplies the smooth
    // 420ms colour cross-fade via CSS transitions — no async View Transition,
    // which would race the attribute read.
    if (!reduce) {
      root.classList.add("theme-animating");
      clearTimeout(themeAnimTimer);
      themeAnimTimer = setTimeout(function () {
        root.classList.remove("theme-animating");
      }, 480);
    }
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("s4d-theme", next); } catch (e) {}
  }
  document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      Sound.toggleTick();
      swapTheme(currentTheme() === "dark" ? "light" : "dark");
    });
  });

  // Sound on/off — persists via the Sound module. Play a confirming tick when
  // switching ON so the user hears that audio is live (silence would be
  // ambiguous); switching OFF is silent by definition.
  document.querySelectorAll("[data-sound-toggle]").forEach(function (btn) {
    btn.setAttribute("aria-pressed", Sound.isOn() ? "true" : "false");
    btn.addEventListener("click", function () {
      var on = Sound.toggle();
      btn.setAttribute("aria-pressed", on ? "true" : "false");
      if (on) Sound.toggleTick();
    });
  });

  /* --- 1c. ambient interaction sounds ---------------------------------------------
     A soft tap on the *meaningful* actions only — primary buttons, opening a
     report, dock navigation, and picking an item from the command palette or the
     patient dial. Minor, high-frequency controls (plain/ghost buttons, list
     tabs, segmented filters, menu items, the account trigger) stay SILENT so the
     UI does not click on every single press. Panels, sends, refreshes and
     success/error states already carry their own dedicated cue, so nothing here
     doubles up. Capture phase so the tap is scheduled before a link navigates
     away. */
  (function () {
    var TAP_SEL = ".btn-primary, .btn-open, .dock-item, .cmdk-item";
    var SKIP_SEL = "[data-theme-toggle],[data-sound-toggle],[data-dock-refresh],[data-cmdk-open],[data-dock-picker],[data-patient-dial-close]";
    document.addEventListener("click", function (e) {
      var t = e.target;
      if (!t || !t.closest) return;
      if (t.closest(SKIP_SEL)) return;
      if (t.closest("[data-login-form]") && t.closest("button[type='submit']")) return;
      var el = t.closest(TAP_SEL);
      if (!el || el.disabled || el.classList.contains("is-disabled")) return;
      Sound.tap();
    }, true);

    // A whisper-quiet tick when the pointer first lands on a dock pill — the dock
    // is a small, discrete set of targets, so this stays tasteful rather than
    // chattering the way a hover sound on every link would.
    document.addEventListener("pointerover", function (e) {
      if (!e.target || !e.target.closest) return;
      var el = e.target.closest(".dock-item:not(.is-disabled)");
      if (!el) return;
      if (e.relatedTarget && el.contains(e.relatedTarget)) return;   // still inside
      Sound.hover();
    }, true);
  })();

  /* --- 1b. toasts ------------------------------------------------------------------ */
  // Completion feedback for actions that POST and redirect. Because the page
  // reloads, the toast is stashed in sessionStorage on submit and drained on
  // the next load. showToast() can also be called directly for same-page
  // actions (e.g. a failed fetch in the chat).
  var TOAST_KEY = "s4d-pending-toast";
  var toastLayer = null;

  function ensureToastLayer() {
    if (toastLayer && document.body.contains(toastLayer)) return toastLayer;
    toastLayer = document.createElement("div");
    toastLayer.className = "toast-layer";
    // Announce politely: these are confirmations, never interruptions.
    toastLayer.setAttribute("role", "status");
    toastLayer.setAttribute("aria-live", "polite");
    document.body.appendChild(toastLayer);
    return toastLayer;
  }

  function showToast(title, sub, isError) {
    var layer = ensureToastLayer();
    var el = document.createElement("div");
    el.className = "toast" + (isError ? " is-error" : "");

    var disc = document.createElement("span");
    disc.className = "toast-disc";
    disc.setAttribute("aria-hidden", "true");
    disc.innerHTML = isError
      ? '<svg viewBox="0 0 52 52"><path class="toast-tick" d="M17 17l18 18M35 17L17 35"/></svg>'
      : '<svg viewBox="0 0 52 52"><path class="toast-tick" d="M14.5 27.5l7.5 7.5 16-16"/></svg>';

    var body = document.createElement("div");
    body.className = "toast-body";
    var t = document.createElement("div");
    t.className = "toast-title";
    t.textContent = title;
    body.appendChild(t);
    if (sub) {
      var s = document.createElement("div");
      s.className = "toast-sub";
      s.textContent = sub;
      body.appendChild(s);
    }

    el.appendChild(disc);
    el.appendChild(body);
    layer.appendChild(el);
    // A toast is the visual confirmation of a completed action — pair it with
    // the matching audio cue so success/failure is felt as well as seen.
    if (isError) Sound.error(); else Sound.success();

    // Auto-dismiss after ~3.8s (enough to read a two-line toast), short leave anim.
    var life = setTimeout(function () { dismiss(); }, 3800);
    function dismiss() {
      clearTimeout(life);
      if (!el.parentNode) return;
      el.classList.add("is-leaving");
      if (reduce) { el.remove(); return; }
      setTimeout(function () { if (el.parentNode) el.remove(); }, 220);
    }
    // Click to dismiss early.
    el.addEventListener("click", dismiss);
    return el;
  }

  // Queue a toast to appear after the next navigation/redirect.
  function queueToast(title, sub, isError) {
    try {
      sessionStorage.setItem(TOAST_KEY, JSON.stringify({ title: title, sub: sub, error: !!isError }));
    } catch (e) {}
  }

  // Drain any queued toast on load.
  (function drainToast() {
    var raw = null;
    try {
      raw = sessionStorage.getItem(TOAST_KEY);
      if (raw) sessionStorage.removeItem(TOAST_KEY);
    } catch (e) { return; }
    if (!raw) return;
    try {
      var d = JSON.parse(raw);
      if (d && d.title) showToast(d.title, d.sub, d.error);
    } catch (e) {}
  })();

  // Wire the redirecting forms. Each queues its toast at submit time; the
  // server redirect then reloads the page and drainToast() renders it.
  document.querySelectorAll("form.status-form").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      // The status value lives on the clicked submit button.
      var btn = e.submitter;
      var label = btn ? (btn.querySelector(".menu-item-label") || {}).textContent : null;
      queueToast("Review status updated", label ? ("Set to " + label.trim()) : null, false);
    });
  });
  document.querySelectorAll("form.note-form").forEach(function (form) {
    form.addEventListener("submit", function () {
      queueToast("Note added", "Saved to this report", false);
    });
  });

  // Expose for other blocks in this file (and for inline callers).
  window.s4dToast = showToast;

  /* --- 1b. persistent image cache (IndexedDB) --------------------------------------
     Lesion photos and Grad-CAM overlays are streamed decrypted from the API. To
     let a doctor re-open a report — or run a comparison days later — WITHOUT
     re-hitting the server each time, we persist each blob in IndexedDB keyed by
     report id + kind. The FIRST fetch of an image still goes to the server (and
     is audit-logged there); every later view is served from the device.
     This is a deliberate trade of the endpoint's no-store posture for offline
     recall. Everything fails soft: any IDB or fetch problem falls back to a plain
     network `src`, so images always load even where IndexedDB is unavailable. */
  var ImgCache = (function () {
    var DB = "s4d-img-cache", STORE = "blobs", VER = 1;
    var TTL_MS = 30 * 24 * 60 * 60 * 1000;   // keep for ~30 days
    var MAX_ENTRIES = 80;                    // cap store size; evict oldest first
    var dbp = null;
    function open() {
      if (dbp) return dbp;
      dbp = new Promise(function (resolve, reject) {
        if (!("indexedDB" in window)) { reject(new Error("no-idb")); return; }
        var req = indexedDB.open(DB, VER);
        req.onupgradeneeded = function () {
          var db = req.result;
          if (!db.objectStoreNames.contains(STORE)) {
            db.createObjectStore(STORE, { keyPath: "key" }).createIndex("ts", "ts");
          }
        };
        req.onsuccess = function () { resolve(req.result); };
        req.onerror = function () { reject(req.error || new Error("idb-open")); };
      }).catch(function (e) { dbp = null; throw e; });
      return dbp;
    }
    function store(mode) {
      return open().then(function (db) { return db.transaction(STORE, mode).objectStore(STORE); });
    }
    function get(key) {
      return store("readonly").then(function (os) {
        return new Promise(function (resolve) {
          var r = os.get(key);
          r.onsuccess = function () {
            var rec = r.result;
            if (!rec || Date.now() - rec.ts > TTL_MS) return resolve(null);  // miss / stale
            resolve(rec.blob || null);
          };
          r.onerror = function () { resolve(null); };
        });
      }).catch(function () { return null; });
    }
    function put(key, blob) {
      return store("readwrite").then(function (os) {
        os.put({ key: key, blob: blob, ts: Date.now() });
        var countReq = os.count();
        countReq.onsuccess = function () {
          var over = countReq.result - MAX_ENTRIES;
          if (over <= 0) return;
          var cur = os.index("ts").openCursor();   // oldest first
          cur.onsuccess = function () {
            var c = cur.result;
            if (c && over > 0) { c.delete(); over--; c.continue(); }
          };
        };
      }).catch(function () {});
    }
    // Resolve an <img> from cache-or-network. On a hit the blob becomes an object
    // URL; on a miss we fetch, cache, then show it. Any failure sets the raw URL
    // so the element's own onload/onerror still run.
    function load(img, url, key) {
      if (!img || !url) return;
      get(key).then(function (blob) {
        if (blob) { img.src = URL.createObjectURL(blob); return; }
        fetch(url, { credentials: "same-origin" })
          .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.blob(); })
          .then(function (b) { put(key, b); img.src = URL.createObjectURL(b); })
          .catch(function () { img.src = url; });
      });
    }
    function clear() {
      return store("readwrite").then(function (os) { os.clear(); }).catch(function () {});
    }
    return { load: load, get: get, put: put, clear: clear };
  })();
  window.__s4dImgCache = ImgCache;

  /* --- 1c. imagery skeletons -------------------------------------------------------- */
  // The lesion photo and Grad-CAM overlay are lazy-loaded from the API after
  // first paint. CSS holds a shimmering placeholder until the image decodes;
  // marking the figure .is-loaded retires it and cross-fades the shot in.
  document.querySelectorAll(".imagery-display .shot-full").forEach(function (fig) {
    var img = fig.querySelector("img");
    if (!img) { fig.classList.add("is-loaded"); return; }
    function done() { fig.classList.add("is-loaded"); }
    img.addEventListener("load", done);
    // The inline onerror swaps in an empty-state panel; clear the skeleton too
    // so the placeholder never outlives the image it was standing in for.
    img.addEventListener("error", done);
    // Route through the persistent cache when the template opted in (data-cache-
    // url instead of a hard src); otherwise honour whatever src is already set.
    var cacheUrl = img.getAttribute("data-cache-url");
    if (cacheUrl) {
      ImgCache.load(img, cacheUrl, img.getAttribute("data-cache-key") || cacheUrl);
    } else if (img.complete && img.naturalWidth > 0) {
      done();   // a hard-src cache hit may already be complete before this runs
    }
  });

  /* --- 2. shared morph primitive (R5) ---------------------------------------------- */
  // Runs mutate(), animating the size change of `el`. Every in-place swap uses this, so
  // all "switching" in the app shares one timing — that consistency is the point.
  function morph(el, mutate) {
    if (reduce) { mutate(); return; }
    if (document.startViewTransition) {
      try {
        document.startViewTransition(mutate);
        return;
      } catch (e) {}
    }
    // FLIP fallback: measure height, mutate, animate old -> new.
    var first = el ? el.offsetHeight : 0;
    mutate();
    var last = el ? el.offsetHeight : 0;
    if (!el || first === last) return;
    try {
      el.animate(
        [{ height: first + "px" }, { height: last + "px" }],
        { duration: 320, easing: "cubic-bezier(.34,1.3,.5,1)" }
      );
    } catch (e) {}
  }
  window.__s4dMorph = morph;

  /* --- 3. info-tab controller (R4) ------------------------------------------------- */
  document.querySelectorAll("[data-tabs]").forEach(function (root) {
    var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
    var panels = root.querySelector("[data-tabpanels]");
    var thumb = root.querySelector(".tab-thumb");
    if (!tabs.length || !panels) return;

    function moveThumb(tab) {
      if (!thumb) return;
      thumb.style.width = tab.offsetWidth + "px";
      thumb.style.transform = "translateX(" + tab.offsetLeft + "px)";
    }
    function select(tab, focus) {
      if (tab.getAttribute("aria-selected") === "true") return;
      morph(panels, function () {
        tabs.forEach(function (t) {
          var on = t === tab;
          t.setAttribute("aria-selected", on ? "true" : "false");
          t.tabIndex = on ? 0 : -1;
          document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
        });
      });
      moveThumb(tab);
      if (focus) tab.focus();
    }

    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () { select(tab, false); });
      tab.addEventListener("keydown", function (e) {
        var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        select(tabs[(i + d + tabs.length) % tabs.length], true);
      });
    });

    var active = root.querySelector('[role="tab"][aria-selected="true"]') || tabs[0];
    // Position the thumb once layout is ready (fonts can shift widths).
    requestAnimationFrame(function () { moveThumb(active); });
    window.addEventListener("resize", function () {
      moveThumb(root.querySelector('[role="tab"][aria-selected="true"]') || tabs[0]);
    });
  });

  /* --- 4. dropdown menus (R6) ------------------------------------------------------ */
  // Progressive niceties for <details data-menu>: Esc closes, an outside click closes,
  // and focus lands on the first item when opened by keyboard.
  document.querySelectorAll("details[data-menu]").forEach(function (d) {
    var summary = d.querySelector("summary");
    d.addEventListener("toggle", function () {
      if (d.open) {
        var first = d.querySelector('[role="menuitem"], .menu-item, a, button:not(summary)');
        if (first && document.activeElement === summary) { /* keep summary focus for mouse */ }
      }
    });
    d.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && d.open) { d.open = false; summary.focus(); }
    });
    document.addEventListener("click", function (e) {
      if (d.open && !d.contains(e.target)) d.open = false;
    });
  });

  /* --- 5. segmented control (R3) --------------------------------------------------- */
  document.querySelectorAll("[data-segmented]").forEach(function (seg) {
    var btns = Array.prototype.slice.call(seg.querySelectorAll(".seg"));
    var thumb = seg.querySelector(".seg-thumb");
    var target = seg.getAttribute("data-filter-target");
    var body = target ? document.querySelector(target) : null;

    function moveThumb(btn) {
      if (!thumb) return;
      thumb.style.width = btn.offsetWidth + "px";
      thumb.style.transform = "translateX(" + btn.offsetLeft + "px)";
    }
    function apply(btn) {
      btns.forEach(function (b) { b.setAttribute("aria-pressed", b === btn ? "true" : "false"); });
      moveThumb(btn);
      if (!body) return;
      var want = btn.getAttribute("data-filter");
      var shown = 0;
      body.querySelectorAll("tr[data-status]").forEach(function (row) {
        var on = want === "all" || row.getAttribute("data-status") === want;
        row.hidden = !on;
        if (on) shown++;
      });
      var none = body.querySelector(".no-match");
      if (none) none.hidden = shown !== 0;
    }

    btns.forEach(function (btn) { btn.addEventListener("click", function () { apply(btn); }); });
    var active = seg.querySelector('.seg[aria-pressed="true"]') || btns[0];
    requestAnimationFrame(function () { moveThumb(active); });
    window.addEventListener("resize", function () {
      moveThumb(seg.querySelector('.seg[aria-pressed="true"]') || btns[0]);
    });
  });

  /* --- 6. ambient background parallax --------------------------------------------- */
  var bgVideo = document.querySelector("[data-bg-video]");
  if (bgVideo) {
    bgVideo.style.transform = "scale(1.08)";
    if (!reduce) {
      window.addEventListener("pointermove", function (e) {
        var x = e.clientX / window.innerWidth - 0.5;
        var y = e.clientY / window.innerHeight - 0.5;
        bgVideo.style.transform = "scale(1.08) translate(" + (-x * 16) + "px," + (-y * 16) + "px)";
      }, { passive: true });
    }
  }

  /* --- 7. word-pop: words lift under the cursor, but ONLY inside clickable text ----
     (links, text buttons, tab/segment/menu items) — never on plain body copy. Chips
     and icon glyphs are skipped so a hop only ever lands on something you can click. */
  var SKIP_POP = ".brand-mark, .avatar, .badge, .pill, .tab-count, .meter-val";
  function wrapWords(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (!n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        var p = n.parentNode;
        if (!p) return NodeFilter.FILTER_REJECT;
        var tag = p.nodeName;
        if (tag === "SCRIPT" || tag === "STYLE" || tag === "TEXTAREA") return NodeFilter.FILTER_REJECT;
        if (p.classList && p.classList.contains("w")) return NodeFilter.FILTER_REJECT;
        if (p.closest && (p.closest("svg") || p.closest(SKIP_POP))) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(function (n) {
      var frag = document.createDocumentFragment();
      n.nodeValue.split(/(\s+)/).forEach(function (part) {
        if (part.trim()) {
          var s = document.createElement("span");
          s.className = "w";
          s.textContent = part;
          frag.appendChild(s);
        } else if (part) {
          frag.appendChild(document.createTextNode(part));
        }
      });
      n.parentNode.replaceChild(frag, n);
    });
  }
  // Only clickable elements get word-wrapped. Filled/outlined buttons (.btn) keep their
  // own press/lift affordance and are left out so their labels don't hop.
  // Word-pop is OPT-IN, not opt-out. A label made of words that carry a shared
  // meaning — "Scan4Disease Clinician Portal", a patient's full name in a
  // breadcrumb, "Sign out", "New screening" — must rise as ONE unit; splitting
  // them per-word breaks the meaning apart. So the default lift is whole-element
  // (handled in CSS), and only elements that explicitly ask for word-pop via a
  // `data-word-pop` attribute get their labels wrapped word-by-word.
  document.querySelectorAll('[data-word-pop]').forEach(function (el) {
    if (el.closest("svg")) return;
    wrapWords(el);
  });

  /* --- 7a. Markdown parser (tables, lists, headers, bold, italics) --- */
  function renderMarkdown(md) {
    if (!md) return "";
    var lines = md.replace(/\r\n/g, "\n").split("\n");
    var html = [];
    var inTable = false;
    var tableRows = [];
    var inList = false;
    var listType = "";
    var para = [];

    function escapeHtml(str) {
      return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function formatInline(str) {
      var s = escapeHtml(str);
      s = s.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
      s = s.replace(/__(.+?)__/g, "<strong>$1</strong>");
      s = s.replace(/\*([^\*]+?)\*/g, "<em>$1</em>");
      s = s.replace(/_([^_]+?)_/g, "<em>$1</em>");
      s = s.replace(/`([^`]+?)`/g, "<code>$1</code>");
      return s;
    }

    function flushPara() {
      if (para.length > 0) {
        html.push("<p>" + para.map(formatInline).join("<br>") + "</p>");
        para = [];
      }
    }

    function flushList() {
      if (inList) {
        html.push("</" + listType + ">");
        inList = false;
        listType = "";
      }
    }

    function flushTable() {
      if (inTable && tableRows.length > 0) {
        var tHtml = '<div class="table-responsive-wrapper"><table>';
        tableRows.forEach(function (row, idx) {
          if (idx === 0) {
            tHtml += "<thead><tr>";
            row.forEach(function (cell) {
              tHtml += "<th>" + formatInline(cell) + "</th>";
            });
            tHtml += "</tr></thead><tbody>";
          } else {
            tHtml += "<tr>";
            row.forEach(function (cell) {
              tHtml += "<td>" + formatInline(cell) + "</td>";
            });
            tHtml += "</tr>";
          }
        });
        tHtml += "</tbody></table></div>";
        html.push(tHtml);
        inTable = false;
        tableRows = [];
      }
    }

    for (var i = 0; i < lines.length; i++) {
      var raw = lines[i];
      var trimmed = raw.trim();

      if (trimmed.startsWith("|") && trimmed.endsWith("|")) {
        flushPara();
        flushList();
        if (/^\|(\s*[-:]+[-|\s:]*)\|$/.test(trimmed)) {
          continue;
        }
        var cells = trimmed
          .slice(1, -1)
          .split("|")
          .map(function (c) { return c.trim(); });
        tableRows.push(cells);
        inTable = true;
        continue;
      } else if (inTable) {
        flushTable();
      }

      // Handle horizontal rule lines (---, --, ***, ___) by omitting clutter
      if (/^[-*_]{2,}$/.test(trimmed)) {
        flushPara();
        flushList();
        continue;
      }

      // Check Heading: #, ##, ###
      var hMatch = trimmed.match(/^(#{1,6})\s+(.*)$/);
      if (hMatch) {
        flushPara();
        flushList();
        var level = hMatch[1].length;
        var tag = level <= 2 ? "h3" : "h4";
        html.push("<" + tag + ">" + formatInline(hMatch[2]) + "</" + tag + ">");
        continue;
      }

      // Check standalone bold headers: **Header Text**
      if (trimmed.startsWith("**") && trimmed.endsWith("**") && !trimmed.slice(2, -2).includes("**")) {
        flushPara();
        flushList();
        var headerText = trimmed.slice(2, -2).trim();
        html.push("<h4>" + formatInline(headerText) + "</h4>");
        continue;
      }

      var ulMatch = trimmed.match(/^[-*]\s+(.*)$/);
      if (ulMatch) {
        flushPara();
        if (!inList || listType !== "ul") {
          flushList();
          html.push("<ul>");
          inList = true;
          listType = "ul";
        }
        html.push("<li>" + formatInline(ulMatch[1]) + "</li>");
        continue;
      }

      var olMatch = trimmed.match(/^(\d+)\.\s+(.*)$/);
      if (olMatch) {
        flushPara();
        if (!inList || listType !== "ol") {
          flushList();
          html.push("<ol>");
          inList = true;
          listType = "ol";
        }
        html.push("<li>" + formatInline(olMatch[2]) + "</li>");
        continue;
      }

      if (inList) {
        flushList();
      }

      if (trimmed === "") {
        flushPara();
      } else {
        para.push(trimmed);
      }
    }

    flushPara();
    flushList();
    flushTable();

    return html.join("\n");
  }

  // Format any server-rendered data-markdown blocks on page load
  document.querySelectorAll("[data-markdown]").forEach(function (el) {
    el.innerHTML = renderMarkdown(el.textContent.trim());
  });

  /* --- 7b. report AI assistant chat ------------------------------------------------ */
  // Talks to POST /portal/reports/{id}/chat (JSON). Keeps a short local history and
  // renders user/assistant bubbles; degrades to a readable error if the model is offline.
  document.querySelectorAll("[data-ai-chat]").forEach(function (root) {
    var log = root.querySelector("[data-ai-log]");
    var form = root.querySelector("[data-ai-form]");
    var input = root.querySelector("[data-ai-input]");
    var send = root.querySelector("[data-ai-send]");
    var reportId = root.getAttribute("data-report-id");
    if (!log || !form || !input) return;
    var history = [];
    var busy = false;

    var expandBtn = root.querySelector("[data-ai-expand]");
    if (expandBtn) {
      var iconExpand = expandBtn.querySelector(".icon-expand");
      var iconCollapse = expandBtn.querySelector(".icon-collapse");
      var label = expandBtn.querySelector(".expand-btn-text");

      function setExpanded(on) {
        if (on) {
          root.classList.add("is-expanded");
          document.body.classList.add("has-expanded-chat");
          if (iconExpand) iconExpand.style.display = "none";
          if (iconCollapse) iconCollapse.style.display = "";
          if (label) label.textContent = "Restore";
          expandBtn.title = "Restore chat workspace";
        } else {
          root.classList.remove("is-expanded");
          document.body.classList.remove("has-expanded-chat");
          if (iconExpand) iconExpand.style.display = "";
          if (iconCollapse) iconCollapse.style.display = "none";
          if (label) label.textContent = "Expand";
          expandBtn.title = "Expand chat workspace";
        }
        scroll();
      }


      expandBtn.addEventListener("click", function () {
        setExpanded(!root.classList.contains("is-expanded"));
      });

      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && root.classList.contains("is-expanded")) {
          setExpanded(false);
        }
      });
    }

    function scroll() {
      // Smooth-scroll the transcript to bottom on every append. On the first
      // paint (log height ≈ scrollTop) the smoothing degrades to instant
      // naturally, so no special case needed. Falls back to instant when the
      // viewer prefers reduced motion.
      if (reduce) { log.scrollTop = log.scrollHeight; return; }
      log.scrollTo({ top: log.scrollHeight, behavior: "smooth" });
    }
    function bubble(role, text, isError) {
      var wrap = document.createElement("div");
      wrap.className = "ai-msg " + (role === "user" ? "ai-msg-user" : "ai-msg-bot");
      var b = document.createElement("div");
      b.className = "ai-bubble" + (isError ? " is-error" : "");
      if (role === "bot" && !isError) {
        b.innerHTML = renderMarkdown(text);
      } else {
        b.textContent = text;
      }
      wrap.appendChild(b);
      log.appendChild(wrap);
      scroll();
      return wrap;
    }
    function typing() {
      var wrap = document.createElement("div");
      wrap.className = "ai-msg ai-msg-bot";
      // "Analyzing Results" loader — nine tiny cells in a 3×3 grid; three of
      // them are lit and travel through the grid like a snake, six stay empty.
      // Pure CSS, no video, no images. Reduced-motion shows a static grid.
      var cells = '';
      for (var i = 0; i < 9; i++) cells += '<span class="ai-snake-cell"></span>';
      wrap.innerHTML =
        '<div class="ai-bubble ai-analyzing">' +
          '<div class="ai-analyzing-frame" aria-hidden="true">' +
            '<div class="ai-snake' + (reduce ? ' is-static' : '') + '">' + cells + '</div>' +
          '</div>' +
          '<span class="ai-analyzing-label">Analyzing Results…</span>' +
        '</div>';
      log.appendChild(wrap);
      scroll();
      return wrap;
    }

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var msg = input.value.trim();
      if (!msg || busy) return;
      busy = true;
      if (send) send.disabled = true;
      input.value = "";
      bubble("user", msg);
      history.push({ role: "user", content: msg });
      var t = typing();

      fetch("/portal/reports/" + reportId + "/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ message: msg, history: history.slice(0, -1) })
      }).then(function (r) {
        return r.json().then(function (data) { return { ok: r.ok, data: data }; });
      }).then(function (res) {
        t.remove();
        var data = res.data || {};
        if (res.ok && data.available && data.response) {
          bubble("bot", data.response);
          history.push({ role: "assistant", content: data.response });
        } else {
          bubble("bot", data.response || "The assistant is unavailable right now. Please try again later.", true);
        }
      }).catch(function () {
        t.remove();
        bubble("bot", "Couldn’t reach the assistant. Check your connection and try again.", true);
        // Same-page failure, so show the toast directly rather than queueing.
        showToast("Assistant unreachable", "Check your connection", true);
      }).finally(function () {
        busy = false;
        if (send) send.disabled = false;
        input.focus();
      });
    });
  });

  /* --- 8. login success / failure takeover ----------------------------------------- */
  // Expanding circular orbs (green for success, red for failure), concentric reticle rings,
  // particle sparks, and central verified/denied sign matching equal 2200ms duration.
  function createOrbsContainer(isError) {
    var over = document.createElement("div");
    over.className = "flow-takeover" + (isError ? " is-error" : "");
    over.setAttribute("role", "status");
    over.setAttribute("aria-live", "polite");

    var iconHtml = isError
      ? '<svg class="success-check-svg failure-cross-svg" viewBox="0 0 52 52" aria-hidden="true">' +
          '<circle class="success-check-circle" cx="26" cy="26" r="23" fill="none"/>' +
          '<path class="failure-cross-line-1" fill="none" d="M17 17l18 18"/>' +
          '<path class="failure-cross-line-2" fill="none" d="M35 17L17 35"/>' +
        '</svg>'
      : '<svg class="success-check-svg" viewBox="0 0 52 52" aria-hidden="true">' +
          '<circle class="success-check-circle" cx="26" cy="26" r="23" fill="none"/>' +
          '<path class="success-check-tick" fill="none" d="M14.5 27.5l7.5 7.5 16-16"/>' +
        '</svg>';

    over.innerHTML =
      '<div class="orb-backdrop" aria-hidden="true">' +
        '<div class="orb orb-1"></div>' +
        '<div class="orb orb-2"></div>' +
        '<div class="orb orb-3"></div>' +
        '<div class="orb orb-4"></div>' +
        '<div class="orb-ring ring-1"></div>' +
        '<div class="orb-ring ring-2"></div>' +
        '<div class="orb-ring ring-3"></div>' +
        '<div class="orb-particles">' +
          '<span class="particle p-1"></span>' +
          '<span class="particle p-2"></span>' +
          '<span class="particle p-3"></span>' +
          '<span class="particle p-4"></span>' +
          '<span class="particle p-5"></span>' +
          '<span class="particle p-6"></span>' +
          '<span class="particle p-7"></span>' +
          '<span class="particle p-8"></span>' +
        '</div>' +
      '</div>' +
      '<div class="flow-success-sign">' +
        '<div class="success-emblem-wrap">' +
          '<div class="success-halo"></div>' +
          '<div class="success-disc">' +
            iconHtml +
          '</div>' +
          '<div class="success-pulse-ring"></div>' +
        '</div>' +
      '</div>';
    return over;
  }

  var loginForm = document.querySelector("[data-login-form]");
  if (loginForm) {
    loginForm.addEventListener("submit", function (e) {
      if (reduce) return;   // Normal submit under reduced motion
      e.preventDefault();
      if (loginForm.dataset.going) return;
      loginForm.dataset.going = "1";

      var btn = loginForm.querySelector("button[type='submit']");
      var originalBtnText = btn ? btn.innerHTML : "Sign in";
      if (btn) {
        btn.disabled = true;
        btn.innerHTML =
          '<span class="login-btn-loading">' +
            '<span class="login-btn-spinner" aria-hidden="true"></span>' +
            '<span class="login-btn-word">Authenticating</span>' +
            '<span class="login-btn-dots" aria-hidden="true">' +
              '<span></span><span></span><span></span>' +
            '</span>' +
          '</span>';
      }

      var existingAlert = loginForm.parentNode.querySelector(".alert-error");
      if (existingAlert) existingAlert.remove();

      var formData = new FormData(loginForm);
      fetch("/portal/login", {
        method: "POST",
        body: formData,
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      .then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (data) {
          return { ok: res.ok, status: res.status, data: data };
        });
      })
      .then(function (result) {
        var card = document.querySelector(".login-card");
        if (!result.ok) {
          // Authentication failed: the ruby disc pops and the cross draws first;
          // the soft error tone follows once the mark has landed (~0.56s), so the
          // sequence reads authenticate → animation → sound, never sound-first.
          delete loginForm.dataset.going;
          var msg = (result.data && result.data.error) ? result.data.error : "Email or password is incorrect.";

          if (btn) {
            btn.disabled = false;
            btn.innerHTML = originalBtnText;
          }
          if (card) {
            card.classList.remove("is-auth-success");
            card.classList.add("is-auth-error");
            setTimeout(function () { Sound.error(); }, 520);
            setTimeout(function () {
              card.classList.remove("is-auth-error");
            }, 1800);
          } else {
            Sound.error();
          }

          var errEl = document.createElement("p");
          errEl.className = "alert alert-error alert-shake";
          errEl.setAttribute("role", "alert");
          errEl.textContent = msg;
          loginForm.parentNode.insertBefore(errEl, loginForm);
          var pwd = loginForm.querySelector("input[name='password']");
          if (pwd) {
            pwd.value = "";
            pwd.focus();
          }
          return;
        }

        // Authentication succeeded: play the emerald disc-pop + checkmark draw
        // FIRST, then sound the success cue as the tick lands (~0.56s) so audio
        // follows the animation. The redirect waits for the arpeggio to breathe.
        if (card) {
          card.classList.remove("is-auth-error");
          card.classList.add("is-auth-success");
        }
        setTimeout(function () { Sound.success(); }, 560);

        setTimeout(function () {
          var target = (result.data && result.data.redirect) ? result.data.redirect : "/portal/patients";
          window.location.href = target;
        }, 1450);
      })
      .catch(function () {
        // Fallback standard submit
        loginForm.submit();
      });
    });

    window.addEventListener("pageshow", function () {
      delete loginForm.dataset.going;
      var btn = loginForm.querySelector("button[type='submit']");
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = "Sign in";
      }
      document.body.classList.remove("is-transitioning");
      document.querySelectorAll(".flow-takeover").forEach(function (el) { el.remove(); });
    });
  }

  /* --- 8b. login success reveal on destination/homepage --------------------------- */
  try {
    if (sessionStorage.getItem("s4d_login_wash") === "1") {
      sessionStorage.removeItem("s4d_login_wash");
      if (!reduce) {
        var wash = createOrbsContainer(false);
        wash.classList.add("flow-takeover-reveal");
        document.body.appendChild(wash);
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            wash.classList.add("is-unveiling");
            setTimeout(function () {
              wash.remove();
            }, 600);
          });
        });
      }
    }
  } catch (err) {}

  /* --- 9. command palette (⌘K / Ctrl+K) -------------------------------------------- */
  var cmdk = document.querySelector("[data-cmdk]");
  var cmdkInput = document.querySelector("[data-cmdk-input]");
  var cmdkList = document.querySelector("[data-cmdk-list]");
  var cmdkEmpty = document.querySelector("[data-cmdk-empty]");
  var cmdkOpenBtns = document.querySelectorAll("[data-cmdk-open]");

  if (cmdk && cmdkInput && cmdkList) {
    var staticActions = [
      {
        id: "act-theme",
        title: "Toggle Theme",
        subtitle: "Switch between Dark and Light mode",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>',
        group: "Actions",
        run: function () {
          var btn = document.querySelector("[data-theme-toggle]");
          if (btn) btn.click();
        }
      },
      {
        id: "act-worklist",
        title: "Go to Worklist",
        subtitle: "View clinical dashboard & shared caseload",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
        group: "Navigation",
        url: "/portal/patients"
      },
      {
        id: "act-reports",
        title: "All Shared Reports",
        subtitle: "Scroll to full shared reports table",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
        group: "Navigation",
        run: function () {
          var el = document.getElementById("worklist-tables");
          if (el) el.scrollIntoView({ behavior: "smooth" });
          else window.location.href = "/portal/patients#worklist-tables";
        }
      },
      {
        id: "act-refresh",
        title: "Refresh Caseload",
        subtitle: "Sync all incoming patient data",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>',
        group: "Actions",
        run: function () {
          var btn = document.querySelector("[data-dock-refresh]");
          if (btn) btn.click();
        }
      },
      {
        id: "act-motion",
        title: "Reduce Ambient Motion",
        subtitle: "Pause the background video and one-shot effects",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M4 12h16"/><path d="M4 6l16 12"/></svg>',
        group: "Preferences",
        run: function () { if (window.__s4dToggleMotion) window.__s4dToggleMotion(); }
      },
      {
        id: "act-kbd",
        title: "Keyboard Shortcuts",
        subtitle: "See every hotkey",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8"/></svg>',
        group: "Help",
        run: function () { if (window.__s4dOpenKbd) window.__s4dOpenKbd(); }
      },
      {
        id: "act-signout",
        title: "Sign Out",
        subtitle: "End clinician session securely",
        icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>',
        group: "Account",
        run: function () {
          var form = document.querySelector('form[action="/portal/logout"]');
          if (form) form.submit();
        }
      }
    ];

    var currentItems = [];
    var selectedIndex = 0;
    var searchTimer = null;

    function openCmdk() {
      Sound.open();
      if (typeof cmdk.showModal === "function") {
        cmdk.showModal();
      } else {
        cmdk.setAttribute("open", "true");
      }
      cmdkInput.value = "";
      renderResults("");
      setTimeout(function () { cmdkInput.focus(); }, 50);
    }

    function closeCmdk() {
      if (typeof cmdk.close === "function") {
        cmdk.close();
      } else {
        cmdk.removeAttribute("open");
      }
    }

    cmdkOpenBtns.forEach(function (b) {
      b.addEventListener("click", openCmdk);
    });

    document.addEventListener("keydown", function (e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        if (cmdk.open) closeCmdk();
        else openCmdk();
      }
    });

    cmdk.addEventListener("click", function (e) {
      if (e.target === cmdk) closeCmdk();
    });

    function renderResults(q) {
      var query = (q || "").trim().toLowerCase();
      var groups = {};
      currentItems = [];

      // 1. Match static actions
      staticActions.forEach(function (act) {
        if (!query || act.title.toLowerCase().indexOf(query) !== -1 || act.subtitle.toLowerCase().indexOf(query) !== -1) {
          if (!groups[act.group]) groups[act.group] = [];
          groups[act.group].push(act);
          currentItems.push(act);
        }
      });

      // 2. Extract in-page patients & reports if present
      document.querySelectorAll("table.reports-data-table tbody tr[data-status]").forEach(function (row) {
        var pLink = row.querySelector(".patient-link");
        var cName = row.querySelector(".condition-name");
        var openBtn = row.querySelector(".btn-open");
        var badge = row.querySelector(".badge");
        if (cName && openBtn) {
          var title = cName.textContent.trim();
          var pText = pLink ? pLink.textContent.trim() : "";
          var badgeText = badge ? badge.textContent.trim() : "";
          var matchText = (title + " " + pText + " " + badgeText).toLowerCase();
          if (!query || matchText.indexOf(query) !== -1) {
            var item = {
              id: "rep-" + openBtn.getAttribute("href"),
              title: title + (pText ? " — " + pText : ""),
              subtitle: badgeText ? "Status: " + badgeText : "Shared report",
              icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
              group: "Reports",
              url: openBtn.getAttribute("href")
            };
            if (!groups["Reports"]) groups["Reports"] = [];
            if (groups["Reports"].length < 8) {
              groups["Reports"].push(item);
              currentItems.push(item);
            }
          }
        }
      });

      // Render HTML
      cmdkList.innerHTML = "";
      var groupKeys = Object.keys(groups);
      if (groupKeys.length === 0) {
        if (cmdkEmpty) cmdkEmpty.hidden = false;
        return;
      }
      if (cmdkEmpty) cmdkEmpty.hidden = true;

      var flatIdx = 0;
      groupKeys.forEach(function (grp) {
        var gTitle = document.createElement("li");
        gTitle.className = "cmdk-group-title";
        gTitle.textContent = grp;
        cmdkList.appendChild(gTitle);

        groups[grp].forEach(function (item) {
          var li = document.createElement("li");
          li.className = "cmdk-item" + (flatIdx === selectedIndex ? " is-selected" : "");
          li.dataset.index = flatIdx;
          li.innerHTML =
            '<div class="cmdk-item-left">' +
              '<div class="cmdk-item-icon">' + item.icon + '</div>' +
              '<div class="cmdk-item-text">' +
                '<span class="cmdk-item-primary">' + item.title + '</span>' +
                '<span class="cmdk-item-secondary">' + item.subtitle + '</span>' +
              '</div>' +
            '</div>' +
            '<div class="cmdk-item-meta">' +
              '<span class="cmdk-kbd"><span class="cmdk-kbd-mod">↵</span></span>' +
            '</div>';

          li.addEventListener("click", function () { executeItem(item); });
          li.addEventListener("mousemove", function () {
            selectedIndex = parseInt(li.dataset.index, 10);
            updateSelection();
          });
          cmdkList.appendChild(li);
          flatIdx++;
        });
      });
      if (selectedIndex >= currentItems.length) selectedIndex = 0;
      updateSelection();
    }

    function updateSelection() {
      var all = cmdkList.querySelectorAll(".cmdk-item");
      all.forEach(function (el, idx) {
        el.classList.toggle("is-selected", idx === selectedIndex);
        if (idx === selectedIndex) {
          el.scrollIntoView({ block: "nearest" });
        }
      });
    }

    function executeItem(item) {
      closeCmdk();
      if (!item) return;
      if (item.url) {
        window.location.href = item.url;
      } else if (typeof item.run === "function") {
        item.run();
      }
    }

    cmdkInput.addEventListener("input", function () {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () {
        var val = cmdkInput.value;
        selectedIndex = 0;
        renderResults(val);
        if (val.trim().length > 1) {
          fetch("/portal/search?q=" + encodeURIComponent(val.trim()))
            .then(function (r) { return r.json(); })
            .then(function (data) {
              if (!data) return;
              var apiPatients = data.patients || [];
              var apiReports = data.reports || [];
              if (apiPatients.length || apiReports.length) {
                apiPatients.forEach(function (p) {
                  var exists = currentItems.some(function (x) { return x.url === p.url; });
                  if (!exists) {
                    currentItems.push({
                      id: "pat-" + p.id,
                      title: p.name,
                      subtitle: p.email,
                      icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>',
                      group: "Patients",
                      url: p.url
                    });
                  }
                });
                apiReports.forEach(function (r) {
                  var exists = currentItems.some(function (x) { return x.url === r.url; });
                  if (!exists) {
                    currentItems.push({
                      id: "rep-" + r.id,
                      title: r.condition + " (" + r.patient + ")",
                      subtitle: (r.triage || "") + " · " + (r.status || ""),
                      icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
                      group: "Reports",
                      url: r.url
                    });
                  }
                });
              }
            })
            .catch(function () {});
        }
      }, 100);
    });

    cmdkInput.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (currentItems.length > 0) {
          selectedIndex = (selectedIndex + 1) % currentItems.length;
          updateSelection();
        }
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        if (currentItems.length > 0) {
          selectedIndex = (selectedIndex - 1 + currentItems.length) % currentItems.length;
          updateSelection();
        }
      } else if (e.key === "Enter") {
        e.preventDefault();
        if (currentItems[selectedIndex]) {
          executeItem(currentItems[selectedIndex]);
        }
      } else if (e.key === "Escape") {
        closeCmdk();
      }
    });
  }

  /* --- 10. quickfilter & table live filter ------------------------------------------ */
  var qf = document.querySelector("[data-quickfilter]");
  var qfInput = document.querySelector("[data-quickfilter-input]");
  var qfClear = document.querySelector("[data-quickfilter-clear]");
  var tableSearchInput = document.querySelector("[data-table-filter]");

  var tables = document.querySelectorAll("table.reports-data-table");
  if (tables.length > 0 && qf) {
    qf.hidden = false;
  }

  function applyFilterText(text) {
    var q = (text || "").trim().toLowerCase();
    if (qfClear) qfClear.hidden = !q;
    
    if (qfInput && qfInput.value !== text) qfInput.value = text;
    if (tableSearchInput && tableSearchInput.value !== text) tableSearchInput.value = text;

    tables.forEach(function (table) {
      var rows = table.querySelectorAll("tbody tr[data-status]");
      var shown = 0;
      var activeFilterSeg = document.querySelector('[data-segmented] .seg[aria-pressed="true"]');
      var activeFilter = activeFilterSeg ? activeFilterSeg.getAttribute("data-filter") : "all";

      rows.forEach(function (row) {
        var status = row.getAttribute("data-status");
        var statusMatch = activeFilter === "all" || status === activeFilter;
        var searchMatch = !q || (row.textContent || "").toLowerCase().indexOf(q) !== -1;
        var on = statusMatch && searchMatch;
        row.hidden = !on;
        if (on) shown++;
      });
      var noMatch = table.querySelector(".no-match");
      if (noMatch) noMatch.hidden = shown !== 0;
    });
  }

  if (qfInput) {
    qfInput.addEventListener("input", function () { applyFilterText(qfInput.value); });
  }
  if (tableSearchInput) {
    tableSearchInput.addEventListener("input", function () { applyFilterText(tableSearchInput.value); });
  }
  if (qfClear) {
    qfClear.addEventListener("click", function () {
      applyFilterText("");
      if (qfInput) qfInput.focus();
    });
  }

  /* --- 11. floating bottom dock & refresh action ----------------------------------- */
  // Refresh actually reloads — a "reload to see a new report" affordance
  // that also serves as an escape hatch for stale data. Queues the toast so
  // it appears after the reload finishes.
  var dockRefresh = document.querySelector("[data-dock-refresh]");
  if (dockRefresh) {
    dockRefresh.addEventListener("click", function () {
      Sound.refresh();
      dockRefresh.classList.add("is-spinning");
      try {
        sessionStorage.setItem(TOAST_KEY, JSON.stringify({
          title: "Worklist refreshed",
          sub: "Latest shared reports loaded",
          error: false
        }));
      } catch (e) {}
      setTimeout(function () { window.location.reload(); }, 380);
    });
  }

  // --- last-viewed report / patient memory ---------------------------------
  // When a report or patient page is open, its dock pill carries the id; stash
  // it so the Report/Patient pills on OTHER pages (e.g. the worklist homepage)
  // can jump straight back to the last one the doctor looked at.
  var LAST_REPORT = "s4d-last-report";
  var LAST_PATIENT = "s4d-last-patient";
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  (function stashCurrent() {
    var rc = document.querySelector("[data-dock-report-current]");
    if (rc) lsSet(LAST_REPORT, rc.getAttribute("data-dock-report-current"));
    var pc = document.querySelector("[data-dock-patient-current]");
    if (pc) {
      lsSet(LAST_PATIENT, pc.getAttribute("data-dock-patient-current"));
      lsSet(LAST_PATIENT + "-name", pc.getAttribute("data-dock-patient-name") || "Patient");
    }
  })();

  function openPalette(kind) {
    var opener = document.querySelector("[data-cmdk-open]");
    if (opener) opener.click();
    var input = document.querySelector("[data-cmdk-input]");
    if (input) {
      setTimeout(function () {
        input.value = "";
        input.placeholder = kind === "patient"
          ? "Search patients…"
          : "Search reports (name, condition, #id)…";
        input.focus();
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }, 60);
    }
  }

  // Enhance each picker pill.
  // - Report: if there's a remembered target, jump straight to it; else open
  //   the palette (numbered ids don't spin nicely on a dial).
  // - Patient: ALWAYS open the radial dial so the doctor can pick from every
  //   consented patient, not just the last one — the dial is now the primary
  //   way to change patient from anywhere in the portal.
  document.querySelectorAll("[data-dock-picker]").forEach(function (btn) {
    var kind = btn.getAttribute("data-dock-picker");
    var lastId = kind === "report" ? lsGet(LAST_REPORT) : lsGet(LAST_PATIENT);

    if (kind === "report" && lastId) {
      var tag = btn.querySelector("[data-dock-report-id]");
      if (tag) { tag.textContent = "#" + lastId; tag.hidden = false; }
      btn.title = "Open last report (#" + lastId + ")";
      btn.addEventListener("click", function () { window.location.href = "/portal/reports/" + lastId; });
      return;
    }
    if (kind === "patient") {
      btn.title = "Spin the patient dial to pick who to open";
      btn.addEventListener("click", function () {
        if (window.__s4dOpenPatientDial) window.__s4dOpenPatientDial();
        else openPalette("patient");
      });
      return;
    }
    btn.addEventListener("click", function () { openPalette(kind); });
  });

  /* --- radial patient dial ---------------------------------------------------------- */
  (function () {
    var dial = document.querySelector("[data-patient-dial]");
    if (!dial) return;
    var track = dial.querySelector("[data-patient-dial-track]");
    var wheel = dial.querySelector(".patient-arc-wheel");
    // The highlighted patient's name is written into the Patient dock pill —
    // no separate caption. Cache the label span and its default text so we
    // can restore on close.
    var patientPill = document.querySelector(".dock [data-dock-picker='patient']");
    var patientPillLabel = patientPill ? patientPill.querySelector("span:not(.dock-report-id)") : null;
    var patientPillDefault = patientPillLabel ? patientPillLabel.textContent : "Patient";

    var patients = [];
    var activeIndex = 0;

    function collectPatients() {
      var seen = Object.create(null);
      var list = [];
      document.querySelectorAll(".patient-link").forEach(function (a) {
        var href = a.getAttribute("href") || "";
        var m = href.match(/\/portal\/patients\/(\d+)/);
        if (!m) return;
        var id = m[1];
        if (seen[id]) return;
        seen[id] = true;
        list.push({ id: id, name: (a.textContent || "").trim() || "Patient #" + id, href: href });
      });
      return list;
    }

    function initials(name) {
      return name.split(/\s+/).map(function (w) { return w.charAt(0); }).join("").slice(0, 2).toUpperCase() || "??";
    }

    function render() {
      if (!track) return;
      track.innerHTML = "";
      var n = patients.length;
      if (!n) return;
      patients.forEach(function (p, i) {
        var chip = document.createElement("button");
        chip.type = "button";
        chip.className = "patient-arc-chip";
        chip.setAttribute("role", "option");
        chip.setAttribute("data-index", String(i));
        chip.innerHTML = '<span class="initials">' + initials(p.name) + '</span><span class="name">' + p.name + '</span>';
        // A single click opens the patient immediately — the wheel snaps the
        // clicked chip to the marker first, plays the lock-in flash, then
        // navigates (same confirmation beat as the scroll-settle path).
        chip.addEventListener("click", function () {
          cancelSettle();
          setActive(i);
          var activeChip = track.querySelector(".patient-arc-chip.is-active");
          if (activeChip) activeChip.classList.add("is-landing");
          if (patientPill) patientPill.classList.add("is-arc-locking");
          Sound.select();   // distinct lock-in cue, synced with the landing flash
          setTimeout(go, activeIndex === i ? 180 : 300);
        });
        track.appendChild(chip);
      });
      setActive(0);
    }

    /* Position chips on a fan that PIVOTS ON THE PATIENT DOCK PILL. The pivot
       is the live viewport position of the Patient pill, so the selected chip
       (offset 0) sits directly above the pill — it reads as the name itself
       lifting out of the dock — and every other chip rotates around that same
       origin instead of orbiting a point stranded in the middle of the screen.
       Coordinates are viewport pixels (the wheel/track fill the viewport), so
       the fan never drifts no matter how far it rotates.
       The wider radius + 40° step give adjacent chips enough vertical stagger
       that names no longer collide. */
    function layout() {
      if (!wheel || !track || !patients.length) return;
      var pill = patientPill ? patientPill.getBoundingClientRect() : null;
      // Pivot = centre-top of the Patient pill. Fall back to the dock's
      // nominal spot if the pill isn't measurable for some reason.
      var pivotX = pill ? pill.left + pill.width / 2 : window.innerWidth / 2;
      var pivotY = pill ? pill.top : window.innerHeight - 64;
      var radius = parseFloat(getComputedStyle(dial).getPropertyValue("--arc-radius")) || 146;
      var ARC_STEP = 60 * Math.PI / 180;                     // 60° between chips
      track.querySelectorAll(".patient-arc-chip").forEach(function (chip, i) {
        var offset = i - activeIndex;
        var halfN = patients.length / 2;
        if (offset > halfN) offset -= patients.length;
        else if (offset < -halfN) offset += patients.length;
        var absOffset = Math.abs(offset);
        // Show the selected name + one either side, ALL the same size (a clean,
        // uniform 3-up fan — no shrunken "1st/5th" chips). Spinning cycles the
        // rest in. The selected chip is distinguished by its highlight, not size.
        var visible = absOffset <= 1;
        var angle = offset * ARC_STEP;                       // 0 = straight up from pill
        var x = pivotX + radius * Math.sin(angle);
        var y = pivotY - radius * Math.cos(angle);
        chip.style.left = x + "px";
        chip.style.top = y + "px";
        chip.style.setProperty("--chip-scale", visible ? 1 : 0.9);
        chip.style.setProperty("--chip-opacity", visible ? (offset === 0 ? 1 : 0.85) : 0);
        chip.style.pointerEvents = visible ? "auto" : "none";
        chip.style.zIndex = String(offset === 0 ? 4 : 2);
      });
    }

    function setActive(i) {
      if (!patients.length) return;
      activeIndex = ((i % patients.length) + patients.length) % patients.length;
      track.querySelectorAll(".patient-arc-chip").forEach(function (c, idx) {
        c.classList.toggle("is-active", idx === activeIndex);
      });
      var p = patients[activeIndex];
      if (patientPillLabel) patientPillLabel.textContent = p.name;
      layout();
    }
    var navigating = false;
    var openedAt = 0;
    function go() {
      if (navigating) return;              // guard against settle + click race
      var p = patients[activeIndex];
      if (!p) return;
      navigating = true;
      cancelSettle();
      // Let the lock-in flash play, then navigate.
      window.location.href = p.href;
    }
    function show() {
      Sound.open();
      dial.hidden = false;
      dial.setAttribute("aria-hidden", "false");
      dial.classList.remove("is-ready");
      openedAt = Date.now();
      document.body.style.overflow = "hidden";
      if (patientPill) patientPill.classList.add("is-arc-active");
      // Two-frame handshake so the first render doesn't animate every chip
      // from (0, 0). Frame A creates chips; Frame B measures + positions +
      // flips .is-ready to enable transitions.
      requestAnimationFrame(function () {
        render();
        requestAnimationFrame(function () {
          layout();
          dial.classList.add("is-ready");
        });
      });
      // Wheel handler MUST live on document (not just on `dial`), because
      // the browser fires wheel events on whatever DOM element sits under
      // the pointer — if that's the page background (not the arc scrim)
      // the arc's own listener never fires and the page scrolls instead.
      // Binding on document, with capture, guarantees we intercept every
      // wheel while the arc is open.
      document.addEventListener("keydown", onKey);
      window.addEventListener("resize", layout);
      document.addEventListener("wheel", onWheel, { passive: false, capture: true });
      // Also block touchmove so mobile browsers don't scroll the page
      // beneath the arc.
      document.addEventListener("touchmove", blockScroll, { passive: false, capture: true });
    }
    function open() {
      patients = collectPatients();
      if (patients.length) { show(); return; }
      // No .patient-link on this page (e.g. viewing a single report). Fetch
      // the roster from /portal/search so the dial still works from any
      // page. Do NOT show the dial until we have data — a half-open dial
      // with no chips felt broken; a brief delay is fine.
      fetch("/portal/search?q=")
        .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)); })
        .then(function (data) {
          var api = (data && data.patients) || [];
          patients = api.map(function (p) {
            return {
              id: String(p.id),
              name: p.name || ("Patient #" + p.id),
              href: p.url || ("/portal/patients/" + p.id),
            };
          });
          if (!patients.length) {
            openPalette("patient");
            return;
          }
          show();
        })
        .catch(function () { openPalette("patient"); });
    }
    // Wheel must sit quiet this long before the landed name auto-selects. Kept
    // deliberately unhurried: the previous ~650ms felt like the dial grabbed
    // you mid-scroll, and on a slow first paint a stray wheel tick could commit
    // and navigate before you'd even read the fan. Enter or a click still
    // commit instantly for anyone who wants speed.
    var SETTLE_IDLE_MS = 1150;
    var SETTLE_LAND_MS = 260;
    var settleTimer = null;
    function armSettle() {
      // Slot-machine behaviour: after the wheel goes quiet, the name that has
      // landed at the Patient pill is auto-selected — no Enter needed. A short
      // "landing" flash on the active chip + pill precedes the navigation so
      // the user sees which one locked in.
      if (settleTimer) clearTimeout(settleTimer);
      // Extra breathing room right after opening so an accidental scroll during
      // the entrance (or while the page is still settling) can't trap you into
      // a patient before the dial has even finished appearing.
      var grace = Math.max(0, 500 - (Date.now() - openedAt));
      settleTimer = setTimeout(function () {
        settleTimer = null;
        var activeChip = track.querySelector(".patient-arc-chip.is-active");
        if (activeChip) activeChip.classList.add("is-landing");
        if (patientPill) patientPill.classList.add("is-arc-locking");
        Sound.select();   // distinct lock-in cue, synced with the landing flash
        setTimeout(go, SETTLE_LAND_MS);
      }, SETTLE_IDLE_MS + grace);
    }
    function cancelSettle() {
      if (settleTimer) { clearTimeout(settleTimer); settleTimer = null; }
    }
    function close() {
      cancelSettle();
      if (!dial.hidden) Sound.close();
      dial.hidden = true;
      dial.setAttribute("aria-hidden", "true");
      document.body.style.overflow = "";
      if (patientPill) patientPill.classList.remove("is-arc-active", "is-arc-locking");
      if (patientPillLabel) patientPillLabel.textContent = patientPillDefault;
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("resize", layout);
      document.removeEventListener("wheel", onWheel, true);
      document.removeEventListener("touchmove", blockScroll, true);
    }
    function blockScroll(e) { e.preventDefault(); }
    function onKey(e) {
      // Escape closes; Enter selects immediately (skips the settle wait).
      // The wheel is the primary rotator and auto-selects on settle.
      if (e.key === "Escape") { e.preventDefault(); cancelSettle(); close(); return; }
      if (e.key === "Enter") { e.preventDefault(); cancelSettle(); go(); }
    }
    var wheelCooldown = 0;
    function onWheel(e) {
      e.preventDefault();
      // Every wheel tick cancels the pending auto-select and re-arms it, so
      // the selection only fires once the user stops scrolling.
      cancelSettle();
      var now = Date.now();
      if (now - wheelCooldown < 110) { armSettle(); return; }   // rate cap
      var delta = e.deltaY || e.deltaX;
      if (Math.abs(delta) < 4) { armSettle(); return; }
      wheelCooldown = now;
      setActive(activeIndex + (delta > 0 ? 1 : -1));
      // A crisp tick on each meaningful step (rate-capped above, so a fast spin
      // ticks per notch rather than firing on every raw wheel event).
      Sound.dialTick();
      armSettle();
    }
    dial.querySelectorAll("[data-patient-dial-close]").forEach(function (b) {
      b.addEventListener("click", close);
    });
    window.__s4dOpenPatientDial = open;
  })();

  /* --- 12. table selection & bulk action bar --------------------------------------- */
  var bulkBar = document.querySelector("[data-bulk-bar]");
  var bulkCount = document.querySelector("[data-bulk-count]");
  var reportsShell = document.querySelector("[data-reports-shell]");
  var bulkLines = document.querySelector("[data-bulk-lines]");

  function selectedRows() {
    return Array.prototype.slice.call(
      document.querySelectorAll("table.reports-data-table .row-cb:checked")
    );
  }
  // Slide the rail so its vertical centre lines up with the FIRST selected
  // row, then leave it there. Only applies in the wide "overhang" layout where
  // the rail is absolutely positioned to the left of the table; in the narrow
  // (<=1200px) layout the rail is docked in normal flow, so we leave its top
  // alone. The position is clamped to the shell so a selection near the very
  // top or bottom can't push the rail off the table.
  function positionBulkBar() {
    if (!bulkBar || !reportsShell || bulkBar.hidden) return;
    if (getComputedStyle(bulkBar).position !== "absolute") {
      bulkBar.style.top = "";               // docked layout — CSS owns it
      return;
    }
    var rows = selectedRows();
    if (!rows.length) return;
    var firstTr = rows[0].closest("tr");
    if (!firstTr) return;
    var shellRect = reportsShell.getBoundingClientRect();
    var rowRect = firstTr.getBoundingClientRect();
    var barH = bulkBar.offsetHeight || 0;
    var rowMidInShell = rowRect.top + rowRect.height / 2 - shellRect.top;
    var top = rowMidInShell - barH / 2;
    // Keep the whole rail within the shell's height.
    var maxTop = Math.max(0, reportsShell.offsetHeight - barH - 4);
    top = Math.max(4, Math.min(top, maxTop));
    bulkBar.style.top = top + "px";
  }

  function drawBulkLines() {
    if (!bulkLines || !reportsShell || !bulkBar) return;
    while (bulkLines.firstChild) bulkLines.removeChild(bulkLines.firstChild);
    if (bulkBar.hidden) return;
    positionBulkBar();
    // The SVG's own bounding rect includes the 124px overhang to the left of
    // the shell — use it as the origin for coordinate math so lines sit
    // pixel-perfectly against the rail and rows regardless of where the shell
    // ends up in the viewport.
    var svgRect = bulkLines.getBoundingClientRect();
    var barRect = bulkBar.getBoundingClientRect();
    var railRight = barRect.right - svgRect.left;
    var rows = selectedRows();
    var w = Math.max(svgRect.width, 1);
    var h = Math.max(svgRect.height, 1);
    bulkLines.setAttribute("width", w);
    bulkLines.setAttribute("height", h);
    bulkLines.setAttribute("viewBox", "0 0 " + w + " " + h);
    // First: the vertical spine on the rail's right edge, spanning from the
    // TOPMOST action button in the rail (so the wire actually reads as
    // leaving the panel) down to the last selected row. Each action button
    // (Compare, Patient, Archive) then gets a short horizontal "tap" out to
    // the spine so the wiring reads as: buttons → bus → rows.
    var actionBtns = bulkBar.querySelectorAll(".bulk-btn[data-bulk-action]:not([data-bulk-action='clear'])");
    if (rows.length >= 1) {
      var ys = rows.map(function (cb) {
        var tr = cb.closest("tr");
        if (!tr) return null;
        var rect = tr.getBoundingClientRect();
        return rect.top + rect.height / 2 - svgRect.top;
      }).filter(function (y) { return y !== null; });
      var minY = Math.min.apply(null, ys.length ? ys : [0]);
      var maxY = Math.max.apply(null, ys.length ? ys : [0]);
      // Extend the spine up to the first action button so it visually leaves
      // the panel from the top action, not from row 1.
      if (actionBtns.length) {
        var firstBtnRect = actionBtns[0].getBoundingClientRect();
        var topBtnY = firstBtnRect.top + firstBtnRect.height / 2 - svgRect.top;
        minY = Math.min(minY, topBtnY);
      }
      if (maxY - minY > 2) {
        var spine = document.createElementNS("http://www.w3.org/2000/svg", "path");
        spine.setAttribute("d", "M" + railRight + "," + minY + " L" + railRight + "," + maxY);
        spine.style.setProperty("--len", Math.abs(maxY - minY) + 4);
        bulkLines.appendChild(spine);
      }
      // Tap from each action button to the spine.
      actionBtns.forEach(function (btn) {
        var bRect = btn.getBoundingClientRect();
        var btnRight = bRect.right - svgRect.left;
        var btnY = bRect.top + bRect.height / 2 - svgRect.top;
        var tap = document.createElementNS("http://www.w3.org/2000/svg", "path");
        tap.setAttribute("d", "M" + btnRight + "," + btnY + " L" + railRight + "," + btnY);
        tap.setAttribute("class", "bulk-line-tap");
        tap.style.setProperty("--len", Math.max(Math.abs(railRight - btnRight) + 2, 2));
        bulkLines.appendChild(tap);
      });
    }
    rows.forEach(function (cb) {
      var tr = cb.closest("tr");
      if (!tr) return;
      var rowRect = tr.getBoundingClientRect();
      var endX = rowRect.left - svgRect.left + 6;
      var endY = rowRect.top + rowRect.height / 2 - svgRect.top;
      // Straight horizontal branch from the spine out to the row's left edge.
      var d = "M" + railRight + "," + endY + " L" + endX + "," + endY;
      var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      var approxLen = Math.abs(endX - railRight) + 4;
      path.style.setProperty("--len", approxLen);
      bulkLines.appendChild(path);
      // Landing dot on the row's left edge.
      var dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      dot.setAttribute("cx", endX);
      dot.setAttribute("cy", endY);
      dot.setAttribute("r", 4);
      dot.setAttribute("fill", "currentColor");
      dot.style.color = "var(--brand)";
      dot.style.opacity = ".9";
      bulkLines.appendChild(dot);
      // Tap dot where the branch meets the spine so the join is legible.
      var joint = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      joint.setAttribute("cx", railRight);
      joint.setAttribute("cy", endY);
      joint.setAttribute("r", 3);
      joint.setAttribute("fill", "currentColor");
      joint.style.color = "var(--brand)";
      joint.style.opacity = ".85";
      bulkLines.appendChild(joint);
    });
  }
  function refreshBulkBar() {
    if (!bulkBar) return;
    var rows = selectedRows();
    var n = rows.length;
    if (bulkCount) bulkCount.textContent = String(n);
    if (reportsShell) reportsShell.classList.toggle("has-selection", n > 0);
    if (n > 0) {
      bulkBar.hidden = false;
      // Restart the slide-in animation each time the bar re-appears from zero.
      bulkBar.style.animation = "none";
      // eslint-disable-next-line no-unused-expressions
      bulkBar.offsetHeight;
      bulkBar.style.animation = "";
    } else {
      bulkBar.hidden = true;
    }
    // The rail sizing needs a paint before we can measure it, so defer the
    // draw to the next frame — otherwise the first row lands at 0,0.
    requestAnimationFrame(drawBulkLines);
  }
  window.addEventListener("resize", function () { requestAnimationFrame(drawBulkLines); });
  window.addEventListener("scroll", function () { requestAnimationFrame(drawBulkLines); }, { passive: true });

  document.querySelectorAll("[data-select-all]").forEach(function (masterCb) {
    var table = masterCb.closest("table");
    if (!table) return;
    masterCb.addEventListener("change", function () {
      var isChecked = masterCb.checked;
      table.querySelectorAll(".row-cb").forEach(function (cb) {
        if (cb.closest("tr").hidden) return;   // don't select rows filtered out
        cb.checked = isChecked;
        var tr = cb.closest("tr");
        if (tr) tr.classList.toggle("is-selected", isChecked);
      });
      refreshBulkBar();
    });

    table.querySelectorAll(".row-cb").forEach(function (cb) {
      cb.addEventListener("change", function () {
        var tr = cb.closest("tr");
        if (tr) tr.classList.toggle("is-selected", cb.checked);
        var visible = Array.prototype.filter.call(
          table.querySelectorAll(".row-cb"),
          function (c) { return !c.closest("tr").hidden; }
        );
        var allChecked = visible.length > 0 && visible.every(function (c) { return c.checked; });
        masterCb.checked = allChecked;
        refreshBulkBar();
      });
    });
  });

  // Bulk action handlers. Archive is a client-side hide (the backend has no
  // archive endpoint yet) with a toast so the doctor sees the action land;
  // Open patient jumps to the first selected report's patient.
  if (bulkBar) {
    bulkBar.addEventListener("click", function (e) {
      var btn = e.target.closest("[data-bulk-action]");
      if (!btn) return;
      var action = btn.getAttribute("data-bulk-action");
      var rows = selectedRows();
      if (action === "clear") {
        rows.forEach(function (cb) {
          cb.checked = false;
          var tr = cb.closest("tr");
          if (tr) tr.classList.remove("is-selected");
        });
        document.querySelectorAll("[data-select-all]").forEach(function (m) { m.checked = false; });
        refreshBulkBar();
        return;
      }
      if (action === "archive") {
        if (!rows.length) return;
        var count = rows.length;
        rows.forEach(function (cb) {
          var tr = cb.closest("tr");
          if (!tr) return;
          tr.classList.add("is-archiving");
          setTimeout(function () {
            tr.remove();
          }, reduce ? 0 : 420);
        });
        if (window.s4dToast) {
          window.s4dToast(
            count === 1 ? "Report archived" : count + " reports archived",
            "Hidden from this worklist view",
            false
          );
        }
        setTimeout(refreshBulkBar, reduce ? 0 : 440);
        return;
      }
      if (action === "open-patient") {
        var first = rows[0];
        if (!first) return;
        var tr = first.closest("tr");
        var link = tr && tr.querySelector(".patient-link");
        if (link && link.href) {
          window.location.href = link.href;
        }
        return;
      }
      if (action === "compare") {
        if (rows.length < 2) {
          if (window.s4dToast) window.s4dToast("Select at least two reports", "Tick two or more rows to compare", true);
          return;
        }
        openCompare(rows);
      }
    });
  }

  // --- compare modal: build a side-by-side view from the selected rows -------
  // Each column pulls the row's report id (via the checkbox's data-row-id) so it
  // can lazy-load /portal/reports/<id>/image + /gradcam. The delta strip is
  // computed from the first two columns; the chat panel forwards questions plus
  // both reports' snapshots to /portal/compare/chat.
  var compareDlg = document.querySelector("[data-compare]");
  var compareGrid = document.querySelector("[data-compare-grid]");
  var compareN = document.querySelector("[data-compare-n]");
  var compareDelta = document.querySelector("[data-compare-delta]");
  var compareChatLog = document.querySelector("[data-compare-chat-log]");
  var compareChatForm = document.querySelector("[data-compare-chat-form]");
  var compareChatInput = document.querySelector("[data-compare-chat-input]");
  var compareChatSuggest = document.querySelector("[data-compare-chat-suggest]");
  var compareSession = { reports: [], history: [] };
  var COL_LABELS = ["A", "B", "C", "D"];

  function cellText(tr, sel) {
    var el = tr.querySelector(sel);
    return el ? el.textContent.trim() : "—";
  }
  function escapeHtml(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function triageTone(text) {
    var t = (text || "").toLowerCase();
    if (/urgent|escalat/.test(t)) return "urgent";
    if (/prompt|soon|watch/.test(t)) return "soon";
    return "routine";
  }
  function openCompare(rows) {
    if (!compareDlg || !compareGrid) return;
    compareGrid.innerHTML = "";
    compareSession = { reports: [], history: [] };
    if (compareChatLog) compareChatLog.innerHTML = "";

    rows.forEach(function (cb, idx) {
      var tr = cb.closest("tr");
      if (!tr) return;
      var reportId = cb.getAttribute("data-row-id") || "";
      var cond = cellText(tr, ".condition-name");
      var patient = cellText(tr, ".patient-link");
      var date = cellText(tr, ".date-cell");
      var conf = cellText(tr, ".conf-pct");
      var triageEl = tr.querySelector("td:nth-child(6) .badge");
      var statusEl = tr.querySelector("td:nth-child(7) .badge");
      var openLink = tr.querySelector(".btn-open, a.btn");
      var href = openLink ? openLink.getAttribute("href") : "#";
      var confNum = parseInt((conf || "").replace(/[^0-9]/g, ""), 10);
      var triageText = triageEl ? triageEl.textContent.trim() : "—";
      var statusText = statusEl ? statusEl.textContent.trim() : "—";
      var label = COL_LABELS[idx] || String(idx + 1);

      compareSession.reports.push({
        id: reportId, label: label, condition: cond, patient: patient,
        date: date, confidence: isFinite(confNum) ? confNum : null,
        triage: triageText, status: statusText,
      });

      var imageSrc = reportId ? "/portal/reports/" + reportId + "/image" : "";
      var camSrc = reportId ? "/portal/reports/" + reportId + "/gradcam" : "";

      var col = document.createElement("div");
      col.className = "compare-col";
      col.innerHTML =
        '<span class="compare-col-label">Report ' + label + (reportId ? " · #" + escapeHtml(reportId) : "") + '</span>' +
        '<div class="compare-col-head">' +
          '<span class="compare-cond">' + escapeHtml(cond) + '</span>' +
          (patient && patient !== "—" ? '<span class="compare-patient">' + escapeHtml(patient) + ' · ' + escapeHtml(date) + '</span>' : '') +
        '</div>' +
        '<div class="compare-images">' +
          (imageSrc
            ? '<div class="compare-image"><img loading="lazy" alt="Lesion photo" data-cache-url="' + imageSrc + '" data-cache-key="report-' + escapeHtml(reportId) + '-image" onerror="this.parentNode.classList.add(\'compare-image--placeholder\');this.remove();"><span class="compare-image-label">Lesion</span></div>'
            : '<div class="compare-image compare-image--placeholder">No lesion image</div>') +
          (camSrc
            ? '<div class="compare-image"><img loading="lazy" alt="Grad-CAM heatmap" data-cache-url="' + camSrc + '" data-cache-key="report-' + escapeHtml(reportId) + '-gradcam" onerror="this.parentNode.classList.add(\'compare-image--placeholder\');this.remove();"><span class="compare-image-label">Grad-CAM</span></div>'
            : '<div class="compare-image compare-image--placeholder">No heatmap</div>') +
        '</div>' +
        '<div class="compare-row"><span class="compare-k">Confidence</span>' +
          (isFinite(confNum)
            ? '<div class="compare-meter-track"><div class="compare-meter-fill" style="width:' + confNum + '%"></div></div><span class="compare-v mono">' + escapeHtml(conf) + '</span>'
            : '<span class="compare-v">' + escapeHtml(conf) + '</span>') +
        '</div>' +
        '<div class="compare-row"><span class="compare-k">Triage</span><span class="compare-v">' + (triageEl ? triageEl.outerHTML : "—") + '</span></div>' +
        '<div class="compare-row"><span class="compare-k">Status</span><span class="compare-v">' + (statusEl ? statusEl.outerHTML : "—") + '</span></div>' +
        '<a class="btn btn-small" href="' + escapeHtml(href) + '">Open report ' +
          '<svg class="icon icon-sm" aria-hidden="true"><use href="/portal/static/vendor/icons/sprite.svg#arrow-right"/></svg></a>';
      // Stagger the column entrance so the panels cascade in rather than
      // popping in all at once.
      col.style.animationDelay = (idx * 70) + "ms";
      compareGrid.appendChild(col);
      // Resolve the two images from the persistent cache (or network on first
      // view). Done after insertion so the <img> elements exist in the DOM.
      col.querySelectorAll("img[data-cache-url]").forEach(function (img) {
        ImgCache.load(img, img.getAttribute("data-cache-url"), img.getAttribute("data-cache-key"));
      });
    });

    renderCompareDelta();

    if (compareN) compareN.textContent = rows.length + " selected";
    if (typeof compareDlg.showModal === "function") compareDlg.showModal();
    else compareDlg.setAttribute("open", "true");
  }

  function renderCompareDelta() {
    if (!compareDelta) return;
    var a = compareSession.reports[0];
    var b = compareSession.reports[1];
    if (!a || !b) { compareDelta.hidden = true; return; }
    var confDelta = (a.confidence != null && b.confidence != null) ? (b.confidence - a.confidence) : null;
    var confCls = confDelta == null ? "" : (confDelta > 0 ? "up" : (confDelta < 0 ? "down" : ""));
    var confTxt = confDelta == null ? "—" : ((confDelta > 0 ? "+" : "") + confDelta + " pts");
    var samePatient = a.patient === b.patient && a.patient !== "—";
    var sameCondition = a.condition.toLowerCase() === b.condition.toLowerCase();
    var triageAgree = triageTone(a.triage) === triageTone(b.triage);
    compareDelta.hidden = false;
    compareDelta.innerHTML =
      '<div class="compare-delta-item"><span class="compare-delta-k">Confidence Δ (B − A)</span><span class="compare-delta-v ' + confCls + '">' + confTxt + '</span></div>' +
      '<div class="compare-delta-item"><span class="compare-delta-k">Same patient</span><span class="compare-delta-v ' + (samePatient ? "up" : "") + '">' + (samePatient ? "Yes · " + escapeHtml(a.patient) : "No") + '</span></div>' +
      '<div class="compare-delta-item"><span class="compare-delta-k">Same condition</span><span class="compare-delta-v ' + (sameCondition ? "up" : "down") + '">' + (sameCondition ? "Yes" : escapeHtml(a.condition) + " → " + escapeHtml(b.condition)) + '</span></div>' +
      '<div class="compare-delta-item"><span class="compare-delta-k">Triage agreement</span><span class="compare-delta-v ' + (triageAgree ? "up" : "down") + '">' + (triageAgree ? "Aligned" : "Divergent") + '</span></div>';
  }

  // Rich chat renderer for the Compare panel: assistant replies flow through
  // renderMarkdown so tables / bold / headings land properly, and the
  // "Analyzing Results" snake loader matches the report chat's language so
  // the two chat surfaces feel like one component.
  function appendChat(role, text, extraClass) {
    if (!compareChatLog) return null;
    var li = document.createElement("li");
    li.className = "compare-chat-msg " + role + (extraClass ? " " + extraClass : "");
    if (role === "assistant" && !/error|thinking/.test(extraClass || "")) {
      li.innerHTML = '<div class="compare-chat-md">' + renderMarkdown(text) + '</div>';
    } else {
      li.textContent = text;
    }
    compareChatLog.appendChild(li);
    compareChatLog.scrollTop = compareChatLog.scrollHeight;
    return li;
  }
  function appendChatAnalyzing() {
    if (!compareChatLog) return null;
    var li = document.createElement("li");
    li.className = "compare-chat-msg assistant analyzing";
    var cells = "";
    for (var i = 0; i < 9; i++) cells += '<span class="ai-snake-cell"></span>';
    li.innerHTML =
      '<div class="ai-analyzing">' +
        '<div class="ai-analyzing-frame" aria-hidden="true">' +
          '<div class="ai-snake">' + cells + '</div>' +
        '</div>' +
        '<span class="ai-analyzing-label">Analyzing comparison…</span>' +
      '</div>';
    compareChatLog.appendChild(li);
    compareChatLog.scrollTop = compareChatLog.scrollHeight;
    return li;
  }

  if (compareChatForm && compareChatInput) {
    compareChatInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        compareChatForm.requestSubmit();
      }
    });
    compareChatForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var msg = (compareChatInput.value || "").trim();
      if (!msg) return;
      if (!compareSession.reports.length) return;
      Sound.send();
      appendChat("user", msg);
      compareChatInput.value = "";
      compareChatInput.style.height = "";
      compareSession.history.push({ role: "user", content: msg });
      var loading = appendChatAnalyzing();
      var send = compareChatForm.querySelector(".compare-chat-send");
      if (send) send.disabled = true;
      fetch("/portal/compare/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: msg,
          report_ids: compareSession.reports.map(function (r) { return parseInt(r.id, 10); }).filter(Boolean),
          history: compareSession.history.slice(-10),
        }),
      })
        .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)); })
        .then(function (data) {
          if (loading) loading.remove();
          var reply = (data && data.response) || "The assistant is unavailable right now. Please rely on the delta strip above for the numbers.";
          appendChat("assistant", reply);
          compareSession.history.push({ role: "assistant", content: reply });
        })
        .catch(function () {
          if (loading) loading.remove();
          appendChat("assistant", "I couldn't reach the assistant. The delta strip above still holds the raw numbers you can rely on.", "error");
        })
        .finally(function () { if (send) send.disabled = false; });
    });
  }
  if (compareChatSuggest) {
    compareChatSuggest.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-suggest]");
      if (!b || !compareChatInput || !compareChatForm) return;
      compareChatInput.value = b.getAttribute("data-suggest") || "";
      compareChatInput.focus();
      compareChatForm.requestSubmit();
    });
  }

  if (compareDlg) {
    compareDlg.querySelectorAll("[data-compare-close]").forEach(function (b) {
      b.addEventListener("click", function () {
        if (typeof compareDlg.close === "function") compareDlg.close();
        else compareDlg.removeAttribute("open");
      });
    });
    compareDlg.addEventListener("click", function (e) {
      if (e.target === compareDlg) {
        if (typeof compareDlg.close === "function") compareDlg.close();
        else compareDlg.removeAttribute("open");
      }
    });
    // Expand toggle docked inside the chat header — only grows the chat log
    // height, leaving the images grid and delta strip intact.
    var compareExpand = compareDlg.querySelector("[data-compare-expand]");
    if (compareExpand) {
      compareExpand.addEventListener("click", function () {
        var next = !compareDlg.classList.contains("is-expanded");
        compareDlg.classList.toggle("is-expanded", next);
        compareExpand.classList.toggle("is-expanded", next);
        compareExpand.setAttribute("aria-pressed", next ? "true" : "false");
        compareExpand.title = next ? "Collapse chat" : "Expand chat";
      });
    }
  }

  /* --- 13. ambient-motion toggle --------------------------------------------------- */
  // Adds .no-motion to <html>, persisted in localStorage. Kills the ambient
  // video + one-shot animations without touching the OS-level preference.
  (function () {
    var MKEY = "s4d-motion";
    function motionReduced() {
      try { return localStorage.getItem(MKEY) === "reduce"; } catch (e) { return false; }
    }
    function applyMotion(reduced) {
      root.classList.toggle("no-motion", reduced);
      document.querySelectorAll("[data-motion-toggle]").forEach(function (b) {
        b.setAttribute("aria-pressed", reduced ? "true" : "false");
      });
    }
    applyMotion(motionReduced());
    function toggleMotion() {
      var next = !motionReduced();
      try { localStorage.setItem(MKEY, next ? "reduce" : "full"); } catch (e) {}
      applyMotion(next);
      if (window.s4dToast) {
        window.s4dToast(next ? "Ambient motion reduced" : "Ambient motion on",
                        next ? "Background video paused" : "Background video resumed", false);
      }
    }
    // The header no longer carries a motion button; the toggle stays reachable
    // from the command palette and the ⌘/Ctrl+M hotkey.
    document.querySelectorAll("[data-motion-toggle]").forEach(function (btn) {
      btn.addEventListener("click", toggleMotion);
    });
    window.__s4dToggleMotion = toggleMotion;
  })();

  /* --- 14. keyboard-shortcuts modal ------------------------------------------------- */
  (function () {
    var kbd = document.querySelector("[data-kbd]");
    if (!kbd) return;
    function openKbd() {
      if (typeof kbd.showModal === "function") kbd.showModal();
      else kbd.setAttribute("open", "true");
    }
    function closeKbd() {
      if (typeof kbd.close === "function") kbd.close();
      else kbd.removeAttribute("open");
    }
    window.__s4dOpenKbd = openKbd;
    document.querySelectorAll("[data-open-kbd]").forEach(function (b) {
      b.addEventListener("click", function () {
        // Close the account menu that hosts this item, then open the modal.
        var menu = b.closest("details[data-menu]");
        if (menu) menu.open = false;
        openKbd();
      });
    });
    kbd.querySelectorAll("[data-kbd-close]").forEach(function (b) {
      b.addEventListener("click", closeKbd);
    });
    kbd.addEventListener("click", function (e) { if (e.target === kbd) closeKbd(); });
  })();

  /* --- 15. global hotkeys (?, Cmd/Ctrl+J theme, Cmd/Ctrl+M motion) ------------------ */
  document.addEventListener("keydown", function (e) {
    var tag = (e.target && e.target.tagName) || "";
    var typing = tag === "INPUT" || tag === "TEXTAREA" || (e.target && e.target.isContentEditable);
    // "?" opens the shortcuts modal (Shift+/ on most layouts).
    if (!typing && (e.key === "?" || (e.key === "/" && e.shiftKey))) {
      e.preventDefault();
      if (window.__s4dOpenKbd) window.__s4dOpenKbd();
      return;
    }
    if (e.metaKey || e.ctrlKey) {
      var k = e.key.toLowerCase();
      if (k === "j") {   // theme
        e.preventDefault();
        var t = document.querySelector("[data-theme-toggle]");
        if (t) t.click();
      } else if (k === "m") {   // motion
        e.preventDefault();
        if (window.__s4dToggleMotion) window.__s4dToggleMotion();
      } else if (k === "r" && !e.shiftKey) {
        // Refresh caseload: run the dock's spin-then-reload path so the doctor
        // gets the same "Worklist refreshed" toast as clicking the dock button,
        // instead of a raw browser reload with no feedback.
        var r = document.querySelector("[data-dock-refresh]");
        if (r) {
          e.preventDefault();
          r.click();
        }
      }
    }
  });

  // Extend the platform kbd-hint swap to the modal's ⌘ glyphs too.
  (function () {
    var isMac = /Mac|iP(hone|ad|od)/.test(navigator.platform || "");
    if (isMac) return;
    document.querySelectorAll("[data-kbd-mod-2]").forEach(function (el) {
      el.textContent = "Ctrl";
      el.style.fontSize = ".62rem";
    });
  })();

  /* --- appointment calendar (the /portal/appointments page) -----------------------
     A month grid built entirely client-side from the appointments embedded as JSON,
     with a slide-in summary widget on the right that fetches one appointment's full
     case picture on demand. Doctor actions (approve / decline / cancel) are real
     form POSTs that redirect with a ?flash= so the reload shows a toast; the
     "Recommend a visit" dialog is a plain POST too. Everything degrades: with JS
     off, the server-rendered agenda list is still there (only the calendar and the
     slide-in widget need scripting). */
  (function () {
    var page = document.querySelector("[data-appt-page]");
    if (!page) return;

    function esc(s) {
      return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
      });
    }
    function buzz(ms) { try { if (navigator.vibrate) navigator.vibrate(ms); } catch (e) {} }

    // --- data ---
    var appts = [];
    var jsonEl = page.querySelector("[data-appt-json]");
    try { appts = JSON.parse((jsonEl && jsonEl.textContent) || "[]"); } catch (e) { appts = []; }
    var byDate = {};
    appts.forEach(function (a) { (byDate[a.date_key] = byDate[a.date_key] || []).push(a); });
    Object.keys(byDate).forEach(function (k) {
      byDate[k].sort(function (x, y) { return x.time_label < y.time_label ? -1 : 1; });
    });

    var grid = page.querySelector("[data-appt-grid]");
    var monthLabel = page.querySelector("[data-appt-month]");
    var rail = page.querySelector("[data-appt-rail]");
    var agenda = page.querySelector("[data-appt-agenda]");
    var summary = page.querySelector("[data-appt-summary]");
    var todayKey = page.getAttribute("data-today") || "";
    var activeFilter = null; // "awaiting" | "upcoming" | "cancelled" | null

    var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
      "August", "September", "October", "November", "December"];
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function keyOf(y, m, d) { return y + "-" + pad(m + 1) + "-" + pad(d); }

    var tp = (todayKey.split("-"));
    var today = { y: +tp[0], m: (+tp[1]) - 1, d: +tp[2] };
    var viewY = today.y, viewM = today.m;

    function matchesFilter(a, filter) {
      if (!filter) return true;
      if (filter === "awaiting") return a.status === "requested";
      if (filter === "upcoming") return a.status === "confirmed" && !a.is_past;
      if (filter === "cancelled") return a.status === "cancelled" || a.status === "declined";
      return true;
    }

    function renderAgenda(filter) {
      if (!agenda) return;
      var headTitle = agenda.querySelector(".appt-agenda-head h3");
      var headCount = agenda.querySelector(".appt-agenda-count");
      var listEl = agenda.querySelector(".appt-agenda-list");
      var emptyEl = agenda.querySelector(".appt-agenda-empty");

      var filtered = appts.filter(function (a) {
        if (!filter) {
          return a.status === "requested" || (a.status === "confirmed" && !a.is_past);
        }
        return matchesFilter(a, filter);
      });

      if (filter === "awaiting") {
        if (headTitle) headTitle.textContent = "Awaiting approval";
      } else if (filter === "upcoming") {
        if (headTitle) headTitle.textContent = "Upcoming visits";
      } else if (filter === "cancelled") {
        if (headTitle) headTitle.textContent = "Cancelled & declined";
      } else {
        if (headTitle) headTitle.textContent = "Needs attention";
      }

      if (headCount) headCount.textContent = filtered.length;

      if (filtered.length) {
        var html = "";
        filtered.forEach(function (a) {
          html += '<li>'
            + '<button class="appt-agenda-item" type="button" data-appt-open="' + a.id + '">'
            + '<span class="appt-agenda-date">'
            + '<span class="appt-agenda-day">' + esc(a.day_label) + '</span>'
            + '<span class="appt-agenda-time">' + esc(a.time_label) + '</span>'
            + '</span>'
            + '<span class="appt-agenda-body">'
            + '<span class="appt-agenda-name">' + esc(a.patient_name) + '</span>'
            + '<span class="appt-agenda-meta">' + esc(a.condition || a.reason || 'General consultation') + '</span>'
            + '</span>'
            + '<span class="appt-badge tone-' + esc(a.tone) + '">' + esc(a.status_label) + '</span>'
            + '</button>'
            + '</li>';
        });
        if (!listEl) {
          listEl = document.createElement("ul");
          listEl.className = "appt-agenda-list";
          agenda.appendChild(listEl);
        }
        listEl.innerHTML = html;
        listEl.hidden = false;
        if (emptyEl) emptyEl.hidden = true;
      } else {
        if (listEl) listEl.hidden = true;
        if (!emptyEl) {
          emptyEl = document.createElement("div");
          emptyEl.className = "appt-agenda-empty";
          agenda.appendChild(emptyEl);
        }
        var msg = filter === "cancelled" ? "No cancelled or declined visits."
          : filter === "awaiting" ? "No requests awaiting approval."
          : filter === "upcoming" ? "No upcoming confirmed visits."
          : "You're all caught up — no pending requests or upcoming visits.";
        emptyEl.innerHTML = '<svg class="icon" aria-hidden="true"><use href="/portal/static/vendor/icons/sprite.svg#check-circle"/></svg><p>' + esc(msg) + '</p>';
        emptyEl.hidden = false;
      }
    }

    // --- month grid ---
    function dayCell(y, m, d, outside) {
      var dt = new Date(y, m, d);              // normalises month overflow
      var key = keyOf(dt.getFullYear(), dt.getMonth(), dt.getDate());
      var cell = document.createElement("div");
      cell.className = "appt-cell" + (outside ? " is-outside" : "") + (key === todayKey ? " is-today" : "");
      cell.setAttribute("role", "gridcell");
      var num = document.createElement("span");
      num.className = "appt-cell-num";
      num.textContent = dt.getDate();
      cell.appendChild(num);

      var rawItems = byDate[key] || [];
      var items = rawItems.filter(function (a) {
        return matchesFilter(a, activeFilter);
      });
      if (items.length) {
        if (items.some(function (a) { return a.status === "requested"; })) cell.classList.add("has-pending");
        var list = document.createElement("div");
        list.className = "appt-cell-items";
        // Two chips fit cleanly inside the fixed cell height; anything more
        // collapses into a "+N more" opener so cells never overflow their row.
        var shown = 2;
        items.slice(0, shown).forEach(function (a) {
          var chip = document.createElement("button");
          chip.type = "button";
          chip.className = "appt-chip tone-" + a.tone +
            (a.status === "cancelled" || a.status === "declined" ? " is-closed" : "");
          chip.setAttribute("data-appt-open", a.id);
          var time = document.createElement("span"); time.className = "appt-chip-time"; time.textContent = a.time_label;
          var nm = document.createElement("span"); nm.className = "appt-chip-name"; nm.textContent = a.patient_name;
          chip.appendChild(time); chip.appendChild(nm);
          list.appendChild(chip);
        });
        if (items.length > shown) {
          var more = document.createElement("button");
          more.type = "button"; more.className = "appt-chip-more";
          more.textContent = "+" + (items.length - shown) + " more";
          more.setAttribute("data-appt-open", items[shown].id);
          list.appendChild(more);
        }
        cell.appendChild(list);
      }
      return cell;
    }

    function buildGrid(dir) {
      monthLabel.textContent = MONTHS[viewM] + " " + viewY;
      var first = new Date(viewY, viewM, 1);
      var startDow = (first.getDay() + 6) % 7;               // Monday-start
      var daysInMonth = new Date(viewY, viewM + 1, 0).getDate();
      var frag = document.createDocumentFragment();
      var i;
      for (i = 0; i < startDow; i++) frag.appendChild(dayCell(viewY, viewM, i - startDow + 1, true));
      for (i = 1; i <= daysInMonth; i++) frag.appendChild(dayCell(viewY, viewM, i, false));
      var total = startDow + daysInMonth;
      var trailing = (7 - (total % 7)) % 7;
      for (i = 1; i <= trailing; i++) frag.appendChild(dayCell(viewY, viewM + 1, i, true));

      grid.innerHTML = "";
      grid.appendChild(frag);
      if (!reduce && dir) {
        var cls = dir > 0 ? "is-slide-next" : "is-slide-prev";
        grid.classList.remove("is-slide-next", "is-slide-prev");
        void grid.offsetWidth;
        grid.classList.add(cls);
        setTimeout(function () { grid.classList.remove(cls); }, 380);
      }
    }

    var prev = page.querySelector("[data-appt-prev]");
    var next = page.querySelector("[data-appt-next]");
    var todayBtn = page.querySelector("[data-appt-today]");
    if (prev) prev.addEventListener("click", function () { Sound.tap(); viewM--; if (viewM < 0) { viewM = 11; viewY--; } buildGrid(-1); });
    if (next) next.addEventListener("click", function () { Sound.tap(); viewM++; if (viewM > 11) { viewM = 0; viewY++; } buildGrid(1); });
    if (todayBtn) todayBtn.addEventListener("click", function () { Sound.tap(); viewY = today.y; viewM = today.m; buildGrid(0); });

    // --- summary widget ---
    function reveal() {
      if (agenda) agenda.hidden = true;
      summary.hidden = false;
      summary.classList.remove("is-in");
      void summary.offsetWidth;
      summary.classList.add("is-in");
    }
    function closeSummary() {
      Sound.close();
      summary.classList.remove("is-in");
      summary.hidden = true;
      if (agenda) agenda.hidden = false;
      page.querySelectorAll(".is-selected").forEach(function (el) { el.classList.remove("is-selected"); });
    }

    function actionForm(id, action, label, confirmLabel, placeholder) {
      return '<form method="post" action="/portal/appointments/' + id + '/' + action + '" class="appt-act-form appt-act-danger">'
        + '<button class="btn btn-ghost appt-act-trigger" type="button">' + esc(label) + '</button>'
        + '<div class="appt-reason" hidden>'
        + '<textarea name="reason" rows="2" maxlength="1000" placeholder="' + esc(placeholder) + '"></textarea>'
        + '<button class="btn btn-danger appt-act-go" type="submit">' + esc(confirmLabel) + '</button>'
        + '</div></form>';
    }

    // Cancelling a confirmed visit is the one irreversible, patient-facing action
    // here, so it gets a deliberate two-gate flow: a slide-to-confirm handle, then
    // a second "are you sure" step, both themed and subtly animated. The reason is
    // carried through in a hidden field and posted only on the final confirmation.
    function cancelForm(id) {
      return '<form method="post" action="/portal/appointments/' + id + '/cancel" class="appt-act-form appt-cancel" data-appt-cancel novalidate>'
        + '<button class="btn btn-ghost appt-act-trigger" type="button">'
          + '<svg class="icon icon-sm" aria-hidden="true"><use href="/portal/static/vendor/icons/sprite.svg#x"/></svg>'
          + 'Cancel visit</button>'
        + '<div class="appt-cancel-body" hidden>'
          + '<textarea name="reason" rows="2" maxlength="1000" placeholder="Why is this being cancelled? (the patient sees this)"></textarea>'
          // Gate 1 — slide to confirm.
          + '<div class="appt-slide" data-appt-slide>'
            + '<div class="appt-slide-track">'
              + '<span class="appt-slide-label">Slide to cancel visit</span>'
              + '<button class="appt-slide-thumb" type="button" aria-label="Slide to cancel visit">'
                + '<svg class="icon icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg>'
              + '</button>'
            + '</div>'
          + '</div>'
          // Gate 2 — native dialog modal overlay that is centered over the full screen.
          + '<dialog class="appt-confirm2-dialog" data-appt-cancel-dialog aria-label="Confirm cancellation">'
            + '<div class="appt-confirm2-panel" role="alertdialog" aria-modal="true">'
              + '<span class="appt-confirm2-ic" aria-hidden="true">'
                + '<svg class="icon" aria-hidden="true"><use href="/portal/static/vendor/icons/sprite.svg#alert-triangle"/></svg>'
              + '</span>'
              + '<h4 class="appt-confirm2-title">Cancel this visit?</h4>'
              + '<p class="appt-confirm2-msg">This cancels the visit and notifies the patient. This can’t be undone.</p>'
              + '<div class="appt-confirm2-row">'
                + '<button class="btn btn-ghost appt-confirm2-keep" type="button">Keep visit</button>'
                + '<button class="btn btn-danger btn-danger-gloss appt-act-go" type="submit">Confirm cancel and notify patient</button>'
              + '</div>'
            + '</div>'
          + '</dialog>'
        + '</div></form>';
    }

    function iconUse(id, cls) {
      return '<svg class="icon ' + (cls || "") + '" aria-hidden="true"><use href="/portal/static/vendor/icons/sprite.svg#' + id + '"/></svg>';
    }

    function renderSummary(data) {
      var ap = data.appointment, p = data.patient, cases = data.cases || [];
      var h = "";
      h += '<div class="appt-sum-topbar">';
      h += '<button class="appt-sum-back" type="button" data-appt-sum-close aria-label="Back to agenda">'
        + '<svg class="icon icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg><span>Back</span></button>';
      h += '<span class="appt-badge tone-' + esc(ap.tone) + '">' + esc(ap.status_label) + '</span>';
      h += '</div>';

      h += '<div class="appt-sum-patient">';
      h += '<div class="appt-sum-avatar">' + esc((p.name || "?").charAt(0).toUpperCase()) + '</div>';
      h += '<div class="appt-sum-pinfo"><div class="appt-sum-pname">' + esc(p.name) + '</div>'
        + '<div class="appt-sum-pmail mono">' + esc(p.email) + '</div></div>';
      h += '</div>';

      h += '<div class="appt-sum-pchips">';
      h += '<span class="appt-chipstat"><b>' + p.report_count + '</b> case' + (p.report_count === 1 ? "" : "s") + '</span>';
      if (p.escalated) h += '<span class="appt-chipstat is-esc"><b>' + p.escalated + '</b> escalated</span>';
      h += '<a class="appt-chipstat appt-chip-link" href="' + esc(p.url) + '">Open patient →</a>';
      h += '</div>';

      h += '<div class="appt-sum-when">' + '<div class="appt-sum-when-ic">' + iconUse("clock", "") + '</div>'
        + '<div><div class="appt-sum-date">' + esc(ap.date_label) + '</div>'
        + '<div class="appt-sum-time">' + esc(ap.time_label) + ' · ' + ap.duration + ' min · '
        + (ap.created_by === "doctor" ? "Recommended by you" : "Requested by patient")
        + (ap.is_past ? ' · past' : '') + '</div></div></div>';

      if (ap.reason) h += '<div class="appt-sum-reason"><span class="appt-sum-label">Reason for visit</span><p>' + esc(ap.reason) + '</p></div>';

      if (ap.cancel_reason && (ap.status === "cancelled" || ap.status === "declined")) {
        h += '<div class="appt-sum-cancelnote">' + iconUse("alert-triangle", "icon-sm")
          + '<div><b>' + (ap.status === "declined" ? "Declined" : "Cancelled") + '</b> — ' + esc(ap.cancel_reason) + '</div></div>';
      }

      h += '<div class="appt-sum-cases"><div class="appt-sum-label">Cases linked to this patient</div>';
      if (cases.length) {
        h += '<ul class="appt-caselist">';
        cases.forEach(function (c) {
          h += '<li class="appt-case' + (c.linked ? " is-linked" : "") + '">'
            + '<a href="' + esc(c.url) + '" class="appt-case-link">'
            + '<span class="appt-case-tone tone-' + esc(c.tone) + '"></span>'
            + '<span class="appt-case-main"><span class="appt-case-cond">' + esc(c.condition)
            + (c.linked ? ' <em class="appt-case-tag">This visit</em>' : '') + '</span>'
            + '<span class="appt-case-meta">' + esc(c.triage) + ' · ' + esc(c.status)
            + (c.confidence != null ? ' · ' + c.confidence + '%' : '') + ' · ' + esc(c.date) + '</span></span>'
            + iconUse("arrow-right", "icon-sm appt-case-arrow") + '</a></li>';
        });
        h += '</ul>';
      } else {
        h += '<div class="appt-sum-nocase">No shared cases for this patient yet.</div>';
      }
      h += '</div>';

      var acts = "";
      if (ap.can_approve) {
        acts += '<form method="post" action="/portal/appointments/' + ap.id + '/approve" class="appt-act-form">'
          + '<button class="btn btn-primary appt-act-approve" type="submit">' + iconUse("check-circle", "icon-sm") + 'Approve request</button></form>';
      }
      if (ap.can_decline) acts += actionForm(ap.id, "decline", "Decline", "Confirm decline", "Optional note to the patient…");
      if (ap.can_cancel) acts += cancelForm(ap.id);
      if (acts) h += '<div class="appt-sum-actions">' + acts + '</div>';

      summary.innerHTML = h;
    }

    function openSummary(id) {
      Sound.open();
      buzz(10);
      page.querySelectorAll(".appt-chip.is-selected,.appt-agenda-item.is-selected,.appt-chip-more.is-selected")
        .forEach(function (el) { el.classList.remove("is-selected"); });
      page.querySelectorAll('[data-appt-open="' + id + '"]').forEach(function (el) { el.classList.add("is-selected"); });
      summary.innerHTML = '<div class="appt-sum-loading">Loading case…</div>';
      reveal();
      fetch("/portal/appointments/" + id + "/summary", { headers: { "Accept": "application/json" }, credentials: "same-origin" })
        .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
        .then(function (data) { renderSummary(data); })
        .catch(function () { summary.innerHTML = '<div class="appt-sum-empty"><p>Could not load this appointment.</p><button class="btn btn-ghost" type="button" data-appt-sum-close>Back</button></div>'; });
    }

    // Delegated interactions across the calendar + rail.
    page.addEventListener("click", function (e) {
      var filterBtn = e.target.closest("[data-appt-filter]");
      if (filterBtn) {
        e.preventDefault();
        var f = filterBtn.getAttribute("data-appt-filter");
        activeFilter = (activeFilter === f) ? null : f;
        page.querySelectorAll("[data-appt-filter]").forEach(function (b) {
          b.classList.toggle("is-active", b.getAttribute("data-appt-filter") === activeFilter);
        });
        Sound.tap();
        buzz(10);
        renderAgenda(activeFilter);
        buildGrid(0);
        return;
      }
      var opener = e.target.closest("[data-appt-open]");
      if (opener) { e.preventDefault(); openSummary(opener.getAttribute("data-appt-open")); return; }
      if (e.target.closest("[data-appt-sum-close]")) { e.preventDefault(); closeSummary(); return; }
      var trig = e.target.closest(".appt-act-trigger");
      if (trig) {
        var form = trig.closest("form");
        var reveal = form.querySelector(".appt-reason, .appt-cancel-body");
        if (reveal) reveal.hidden = false;
        trig.hidden = true;
        var ta = form.querySelector("textarea");
        if (ta) ta.focus();
        Sound.tap(); buzz(12);
        return;
      }
      // "Keep visit" (or tapping the popup backdrop) — step back from the
      // confirmation popup and reset the slider.
      var keep = e.target.closest(".appt-confirm2-keep");
      if (keep) {
        var kform = keep.closest("[data-appt-cancel]");
        if (kform) resetCancel(kform);
        Sound.tap();
        return;
      }
      var cancelDlg = e.target.closest("[data-appt-cancel-dialog]");
      if (cancelDlg && e.target === cancelDlg) {
        var cform = cancelDlg.closest("[data-appt-cancel]");
        if (cform) resetCancel(cform);
        Sound.tap();
        return;
      }
    });

    // Escape closes the confirmation popup, like any modal.
    page.addEventListener("keydown", function (e) {
      if (e.key !== "Escape") return;
      var openDialog = page.querySelector("[data-appt-cancel] [data-appt-cancel-dialog][open]");
      if (openDialog) {
        e.preventDefault();
        resetCancel(openDialog.closest("[data-appt-cancel]"));
        Sound.tap();
      }
    });

    // Slide-to-confirm: pointer drag on the thumb; completing the slide reveals
    // the second confirmation gate. Keyboard users can advance it with the
    // arrow/enter keys on the focused thumb.
    function resetCancel(form) {
      if (!form) return;
      var slide = form.querySelector("[data-appt-slide]");
      var dlg = form.querySelector("[data-appt-cancel-dialog]");
      if (slide) { slide.hidden = false; slide.classList.remove("is-armed"); var th = slide.querySelector(".appt-slide-thumb"); if (th) th.style.left = ""; }
      if (dlg) {
        if (dlg.close) { try { dlg.close(); } catch (err) { dlg.removeAttribute("open"); } }
        else dlg.removeAttribute("open");
      }
    }
    function completeSlide(form) {
      if (!form) return;
      var slide = form.querySelector("[data-appt-slide]");
      var dlg = form.querySelector("[data-appt-cancel-dialog]");
      if (slide) slide.classList.add("is-armed");
      Sound.tap(); buzz([12, 24, 12]);
      // Let the fill finish, then open the centered modal dialog.
      setTimeout(function () {
        if (slide) slide.hidden = true;
        if (dlg) {
          if (dlg.showModal) {
            try { dlg.showModal(); } catch (err) { dlg.setAttribute("open", ""); }
          } else {
            dlg.setAttribute("open", "");
          }
        }
      }, 240);
    }
    function initSlide(thumb) {
      var track = thumb.parentNode;
      var slide = thumb.closest("[data-appt-slide]");
      var form = thumb.closest("[data-appt-cancel]");
      if (!track || !slide || !form) return;
      var dragging = false, startX = 0, max = 0;
      function maxTravel() { return track.clientWidth - thumb.offsetWidth - 8; }
      function down(e) {
        dragging = true; slide.classList.add("is-dragging");
        startX = (e.touches ? e.touches[0].clientX : e.clientX) - thumb.offsetLeft;
        max = maxTravel();
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
      }
      function move(e) {
        if (!dragging) return;
        var x = (e.clientX != null ? e.clientX : startX) - startX;
        x = Math.max(0, Math.min(max, x));
        thumb.style.left = x + "px";
        slide.style.setProperty("--slide-pct", (max ? x / max : 0));
        if (x >= max - 1) { finish(); }
      }
      function up() {
        if (!dragging) return;
        dragging = false; slide.classList.remove("is-dragging");
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
        // Snap back if not completed.
        if (!slide.classList.contains("is-armed")) { thumb.style.left = ""; slide.style.setProperty("--slide-pct", 0); }
      }
      function finish() {
        dragging = false; slide.classList.remove("is-dragging");
        thumb.style.left = maxTravel() + "px"; slide.style.setProperty("--slide-pct", 1);
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
        completeSlide(form);
      }
      thumb.addEventListener("pointerdown", down);
      // Keyboard / tap fallback: Enter or Space or ArrowRight completes it.
      thumb.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " " || e.key === "ArrowRight") { e.preventDefault(); finish(); }
      });
    }
    // Delegate slide-thumb init lazily whenever a summary renders.
    var _slideObserver = new MutationObserver(function () {
      page.querySelectorAll(".appt-slide-thumb:not([data-slide-ready])").forEach(function (t) {
        t.setAttribute("data-slide-ready", "1"); initSlide(t);
      });
    });
    if (summary) _slideObserver.observe(summary, { childList: true, subtree: true });

    // A firmer buzz when a destructive/confirming action is actually submitted.
    page.addEventListener("submit", function (e) {
      if (e.target && e.target.matches && e.target.matches(".appt-act-form")) { buzz([14, 30, 14]); }
    });

    // First paint.
    buildGrid(0);
  })();

  // --- Global recommend-a-visit dialog and flash toast listener (works on all pages) ---
  (function () {
    var recoDialog = document.querySelector("[data-appt-reco]");
    var recoOpenBtns = document.querySelectorAll("[data-appt-reco-open]");
    function setRecoMin() {
      if (!recoDialog) return;
      var input = recoDialog.querySelector("[data-appt-when]");
      if (!input) return;
      function pad2(n) { return String(n).padStart(2, "0"); }
      function isoLocal(dt) {
        return dt.getFullYear() + "-" + pad2(dt.getMonth() + 1) + "-" + pad2(dt.getDate())
          + "T" + pad2(dt.getHours()) + ":" + pad2(dt.getMinutes());
      }
      var now = new Date();
      input.min = isoLocal(now);
      if (!input.value) {
        var def = new Date(now.getTime() + 3600000);
        def.setMinutes(0, 0, 0);
        input.value = isoLocal(def);
      }
    }
    if (recoDialog && recoOpenBtns.length) {
      recoOpenBtns.forEach(function (btn) {
        btn.addEventListener("click", function () {
          Sound.open();
          setRecoMin();
          if (recoDialog.showModal) { try { recoDialog.showModal(); } catch (e) { recoDialog.setAttribute("open", ""); } }
          else recoDialog.setAttribute("open", "");
        });
      });
      recoDialog.querySelectorAll("[data-appt-reco-close]").forEach(function (btn) {
        btn.addEventListener("click", function () {
          Sound.close();
          if (recoDialog.close) { try { recoDialog.close(); } catch (e) { recoDialog.removeAttribute("open"); } }
          else recoDialog.removeAttribute("open");
        });
      });
      recoDialog.addEventListener("click", function (e) {
        if (e.target === recoDialog) { Sound.close(); try { recoDialog.close(); } catch (err) {} }
      });
    }

    // Flash toast listener
    var params = new URLSearchParams(location.search);
    var flash = params.get("flash");
    var hl = params.get("hl");
    var MSG = {
      approved: ["Appointment approved", "The patient has been notified.", false],
      declined: ["Request declined", "The patient has been notified.", true],
      cancelled: ["Appointment cancelled", "The patient has been notified.", true],
      recommended: ["Recommendation sent", "It's now in the patient's app.", false]
    };
    if (flash && MSG[flash] && typeof showToast === "function") {
      showToast(MSG[flash][0], MSG[flash][1], MSG[flash][2]);
    }
    if (flash || hl) { try { history.replaceState(null, "", location.pathname); } catch (e) {} }
  })();
})();
