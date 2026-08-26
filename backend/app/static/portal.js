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
      swapTheme(currentTheme() === "dark" ? "light" : "dark");
    });
  });

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

    // Auto-dismiss after 3s, with a short leave animation.
    var life = setTimeout(function () { dismiss(); }, 3000);
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

  /* --- 1c. imagery skeletons -------------------------------------------------------- */
  // The lesion photo and Grad-CAM overlay are lazy-loaded from the API after
  // first paint. CSS holds a shimmering placeholder until the image decodes;
  // marking the figure .is-loaded retires it and cross-fades the shot in.
  document.querySelectorAll(".imagery-display .shot-full").forEach(function (fig) {
    var img = fig.querySelector("img");
    if (!img) { fig.classList.add("is-loaded"); return; }
    function done() { fig.classList.add("is-loaded"); }
    // Cache hits may already be complete before this runs.
    if (img.complete && img.naturalWidth > 0) { done(); return; }
    img.addEventListener("load", done);
    // The inline onerror swaps in an empty-state panel; clear the skeleton too
    // so the placeholder never outlives the image it was standing in for.
    img.addEventListener("error", done);
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
          // Authentication failed: render subtle glossy ruby cross in background of logo
          delete loginForm.dataset.going;
          var msg = (result.data && result.data.error) ? result.data.error : "Email or password is incorrect.";
          
          if (btn) {
            btn.disabled = false;
            btn.innerHTML = originalBtnText;
          }
          if (card) {
            card.classList.remove("is-auth-success");
            card.classList.add("is-auth-error");
            setTimeout(function () {
              card.classList.remove("is-auth-error");
            }, 1800);
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

        // Authentication succeeded: render sleek blurry glossy emerald tick in the background of the logo
        if (card) {
          card.classList.remove("is-auth-error");
          card.classList.add("is-auth-success");
        }

        setTimeout(function () {
          var target = (result.data && result.data.redirect) ? result.data.redirect : "/portal/patients";
          window.location.href = target;
        }, 1150);
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
    var nameEl = dial.querySelector("[data-patient-dial-name]");

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
        // A single click opens the patient immediately — no second confirm
        // step. The wheel snaps to the clicked chip first (so the movement
        // is legible) before we navigate away.
        chip.addEventListener("click", function () {
          if (activeIndex === i) { go(); return; }
          setActive(i);
          setTimeout(go, 200);
        });
        track.appendChild(chip);
      });
      setActive(0);
    }

    /* Position chips along the top-half arc. Coordinates are pixel-exact so
       the wheel never drifts off centre no matter how many times it rotates.
       The active chip is placed at angle 0 (12 o'clock, under the marker);
       neighbours fan out symmetrically at ±ARC_STEP radians. */
    function layout() {
      if (!wheel || !track || !patients.length) return;
      var size = wheel.offsetWidth || 620;                   // matches --arc-size
      var radius = parseFloat(getComputedStyle(dial).getPropertyValue("--arc-radius")) || (size * 0.4);
      var centerX = size / 2;                                // wheel's horizontal centre
      // Anchor the arc's pivot below the marker at the top of the wheel so
      // the visible chips fan out along the upper half.
      var anchorY = radius + 40;
      var ARC_STEP = Math.PI / 6;                            // 30° between chips
      track.querySelectorAll(".patient-arc-chip").forEach(function (chip, i) {
        var offset = i - activeIndex;
        var halfN = patients.length / 2;
        if (offset > halfN) offset -= patients.length;
        else if (offset < -halfN) offset += patients.length;
        var angle = offset * ARC_STEP;                       // 0 = top-centre
        var visibleSpan = 3;                                 // 7 chips fit the arc nicely
        var absOffset = Math.abs(offset);
        var visible = absOffset <= visibleSpan;
        var x = centerX + radius * Math.sin(angle);
        var y = anchorY - radius * Math.cos(angle);
        chip.style.left = x + "px";
        chip.style.top = y + "px";
        var scale = visible ? Math.max(.7, 1 - absOffset * 0.10) : 0.6;
        chip.style.setProperty("--chip-scale", scale);
        var opacity = visible ? Math.max(.2, 1 - absOffset * 0.28) : 0;
        chip.style.setProperty("--chip-opacity", opacity);
        chip.style.pointerEvents = visible ? "auto" : "none";
        chip.style.zIndex = String(10 - Math.floor(absOffset));
      });
    }

    function setActive(i) {
      if (!patients.length) return;
      activeIndex = ((i % patients.length) + patients.length) % patients.length;
      track.querySelectorAll(".patient-arc-chip").forEach(function (c, idx) {
        c.classList.toggle("is-active", idx === activeIndex);
      });
      var p = patients[activeIndex];
      if (nameEl) nameEl.textContent = p.name;
      layout();
    }
    function go() {
      var p = patients[activeIndex];
      if (!p) return;
      close();
      window.location.href = p.href;
    }
    function show() {
      dial.hidden = false;
      dial.setAttribute("aria-hidden", "false");
      dial.classList.remove("is-ready");
      document.body.style.overflow = "hidden";
      // Two-frame handshake:
      //   1. Frame A — render chips (they get inserted with no positions).
      //   2. Frame B — measure the wheel, position chips, then flip .is-ready
      //      which turns on the transitions. Without this the first render
      //      would animate every chip from (0, 0) to its slot, which the user
      //      described as "crashes/stutters".
      requestAnimationFrame(function () {
        render();
        requestAnimationFrame(function () {
          layout();
          dial.classList.add("is-ready");
        });
      });
      document.addEventListener("keydown", onKey);
      window.addEventListener("resize", layout);
      dial.addEventListener("wheel", onWheel, { passive: false });
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
    function close() {
      dial.hidden = true;
      dial.setAttribute("aria-hidden", "true");
      document.body.style.overflow = "";
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("resize", layout);
      dial.removeEventListener("wheel", onWheel);
    }
    function onKey(e) {
      if (e.key === "Escape") { e.preventDefault(); close(); return; }
      // Arrow left/right rotate the wheel like a real dial. Down/right = next
      // patient (wheel spins clockwise), up/left = previous.
      if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); setActive(activeIndex + 1); return; }
      if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); setActive(activeIndex - 1); return; }
      if (e.key === "Enter") { e.preventDefault(); go(); }
    }
    var wheelCooldown = 0;
    function onWheel(e) {
      e.preventDefault();
      var now = Date.now();
      if (now - wheelCooldown < 120) return;                 // ~8 steps/sec cap
      var delta = e.deltaY || e.deltaX;
      if (Math.abs(delta) < 4) return;
      wheelCooldown = now;
      setActive(activeIndex + (delta > 0 ? 1 : -1));
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
  function drawBulkLines() {
    if (!bulkLines || !reportsShell || !bulkBar) return;
    while (bulkLines.firstChild) bulkLines.removeChild(bulkLines.firstChild);
    if (bulkBar.hidden) return;
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
            ? '<div class="compare-image"><img loading="lazy" alt="Lesion photo" src="' + imageSrc + '" onerror="this.parentNode.classList.add(\'compare-image--placeholder\');this.remove();"><span class="compare-image-label">Lesion</span></div>'
            : '<div class="compare-image compare-image--placeholder">No lesion image</div>') +
          (camSrc
            ? '<div class="compare-image"><img loading="lazy" alt="Grad-CAM heatmap" src="' + camSrc + '" onerror="this.parentNode.classList.add(\'compare-image--placeholder\');this.remove();"><span class="compare-image-label">Grad-CAM</span></div>'
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
      compareGrid.appendChild(col);
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
    // Expand toggle — swells the modal so long chat threads and Grad-CAM
    // panels have room to breathe. Mirrors the report-chat expand button.
    var compareExpand = compareDlg.querySelector("[data-compare-expand]");
    if (compareExpand) {
      compareExpand.addEventListener("click", function () {
        var next = !compareDlg.classList.contains("is-expanded");
        compareDlg.classList.toggle("is-expanded", next);
        compareExpand.setAttribute("aria-pressed", next ? "true" : "false");
        compareExpand.title = next ? "Collapse chat panel" : "Expand chat panel";
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
})();
