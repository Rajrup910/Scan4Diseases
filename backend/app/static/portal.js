/* Scan4Disease portal — hand-written vanilla JS, no libraries, no build step.
   Jobs: (1) theme toggle, (2) a shared morph() using the View Transitions API with a FLIP
   fallback, (3) the R4 info-tab controller, (4) the R6 dropdown niceties (Esc / click-away).
   Everything degrades: with JS off, <details> menus and the tab panels still work. */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* --- 1. theme toggle ------------------------------------------------------------- */
  var root = document.documentElement;
  function currentTheme() {
    return root.getAttribute("data-theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  }
  document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("s4d-theme", next); } catch (e) {}
    });
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
          if (iconExpand) iconExpand.style.display = "none";
          if (iconCollapse) iconCollapse.style.display = "";
          if (label) label.textContent = "Restore";
          expandBtn.title = "Restore chat workspace";
        } else {
          root.classList.remove("is-expanded");
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

    function scroll() { log.scrollTop = log.scrollHeight; }
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
        btn.innerHTML = '<span class="login-btn-loading">Authenticating…</span>';
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
        if (!result.ok) {
          // Authentication failed: trigger the same circular animation in RED for 2200ms
          delete loginForm.dataset.going;
          var msg = (result.data && result.data.error) ? result.data.error : "Email or password is incorrect.";
          
          var errOver = createOrbsContainer(true);
          document.body.appendChild(errOver);
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              document.body.classList.add("is-transitioning");
              errOver.classList.add("is-active");
            });
          });

          setTimeout(function () {
            errOver.classList.add("is-fading-out");
            setTimeout(function () {
              errOver.remove();
              document.body.classList.remove("is-transitioning");
              if (btn) {
                btn.disabled = false;
                btn.innerHTML = originalBtnText;
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
            }, 350);
          }, 1300);
          return;
        }

        // Authentication succeeded: trigger lush takeover with green circles, particles, and verified sign
        try { sessionStorage.setItem("s4d_login_wash", "1"); } catch (err) {}
        var over = createOrbsContainer(false);
        document.body.appendChild(over);
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            document.body.classList.add("is-transitioning");
            over.classList.add("is-active");
          });
        });

        // Lasts 1300ms so the blooming circles, glowing checkmark sign, and particle sparks
        // feel sleek, snappy, and flow smoothly into the clinician homepage
        setTimeout(function () {
          var target = (result.data && result.data.redirect) ? result.data.redirect : "/portal/patients";
          window.location.href = target;
        }, 1300);
      })
      .catch(function () {
        // Network or execution fallback
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
})();
