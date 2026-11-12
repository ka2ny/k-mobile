// Shared mobile shell: Home navigation, searchable apps and phone preferences.
// Standalone app servers remove this script; only the unified PWA mounts the shell.
"use strict";
(() => {
  const m = /^\/(remote|beam|agents|assistant)\//.exec(location.pathname);
  if (!m && !["/", "/index.html"].includes(location.pathname)) return;
  const here = m ? m[1] : "home";
  document.documentElement.dataset.mobileShell = here;
  const PARTS = [["remote", "Remote", "See and use the desktop"],
                 ["beam", "Beam", "Send files and text both ways"],
                 ["agents", "Agents", "Answer and steer your agents"],
                 ["assistant", "Assistant", "Have the computer do a job for you"]];
  if (m) { try { localStorage.setItem("khole-app-last", here); } catch (e) {} }
  // K's Vector set (configs/icons/vector): a 24 grid, one hairline weight, one accent detail per glyph.
  const ICONS = {
    remote: ['M3 9V7q0-2 2-2h14q2 0 2 2v10q0 2-2 2h-5', 'M3 19h.01', 'M3 15.5q3.5 0 3.5 3.5', '*M3 12q7 0 7 7'],
    beam: ['M12 20.5V10', 'M8 14l4-4 4 4', '*M6.2 7.2q5.8-5 11.6 0', '*M8.8 9.6q3.2-2.6 6.4 0'],
    agents: ['M7 4.5h10q3.5 0 3.5 3.5v6q0 3.5-3.5 3.5h-6l-4 3v-3q-3.5 0-3.5-3.5V8Q3.5 4.5 7 4.5Z', 'M7.5 8.5 10 11l-2.5 2.5', '*M14 13.5h3'],
    assistant: ['M4.5 3.5 16 9l-5 1.7-1.8 5.1Z', 'M11 10.7l4.2 4.2', '*M18 13.5l.9 2.3 2.3.9-2.3.9-.9 2.3-.9-2.3-2.3-.9 2.3-.9Z'],
    files: ['M3.4 9V8q0-3 3-3h1.9q1.1 0 1.9.9l1.6 1.8h5.8q3.2 0 3.2 3.2v4.6q0 3.5-3.5 3.5H6.9q-3.5 0-3.5-3.5Z', '*M6.4 10.4h13.7'],
    home: ['M4 11.2 12 4.5l8 6.7V18q0 2-2 2H6q-2 0-2-2Z', '*M10 20v-4.6q0-1 1-1h2q1 0 1 1V20'],
    apps: ['M5.6 3.75h2.5q1.9 0 1.9 1.9v2.5q0 1.9-1.9 1.9H5.6q-1.9 0-1.9-1.9V5.6q0-1.85 1.9-1.85Z', 'M15.9 3.75h2.5q1.9 0 1.9 1.9v2.5q0 1.9-1.9 1.9h-2.5q-1.9 0-1.9-1.9V5.6q0-1.85 1.9-1.85Z', 'M5.6 14h2.5q1.9 0 1.9 1.9v2.5q0 1.9-1.9 1.9H5.6q-1.9 0-1.9-1.9v-2.5Q3.75 14 5.6 14Z', '*M15.9 14h2.5q1.9 0 1.9 1.9v2.5q0 1.9-1.9 1.9h-2.5q-1.9 0-1.9-1.9v-2.5Q14 14 15.9 14Z'],
    settings: ['M5.8 4.5v2.2', 'M5.8 12v7.5', 'M5.4 7.9h.8q1.3 0 1.3 1.3v.4q0 1.3-1.3 1.3h-.8q-1.3 0-1.3-1.3v-.4q0-1.3 1.3-1.3Z', 'M12 4.5v7.7', 'M12 17.4v2.1', 'M18.2 4.5v.6', 'M18.2 10.3v9.2', 'M17.8 6.2h.8q1.3 0 1.3 1.3v.4q0 1.3-1.3 1.3h-.8q-1.3 0-1.3-1.3v-.4q0-1.3 1.3-1.3Z', '*M11.6 13.3h.8q1.3 0 1.3 1.3v.4q0 1.3-1.3 1.3h-.8q-1.3 0-1.3-1.3v-.4q0-1.3 1.3-1.3Z'],
    close: ['M7 7l10 10', 'M17 7 7 17'],
  };
  function iconSvg(name, cls) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("aria-hidden", "true");
    if (cls) svg.setAttribute("class", cls);
    for (const d of ICONS[name]) {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d.replace(/^\*/, ""));
      if (d[0] === "*") path.setAttribute("data-accent", "true");
      svg.append(path);
    }
    return svg;
  }

  const palettes = {sage: "#b7d7c2", ice: "#a8d6ef", lilac: "#cabdf0", rose: "#e8bbc7", amber: "#e4c38b"};
  const defaults = {accent: "sage", motion: "system", connection: true, recent: true};
  let preferences = {...defaults}, saved = true;
  function readPreferences() {
    try {
      const value = JSON.parse(localStorage.getItem("khole-mobile-preferences") || "{}");
      preferences = {...defaults};
      if (value && typeof value === "object") {
        if (Object.hasOwn(palettes, value.accent)) preferences.accent = value.accent;
        if (["system", "reduced", "off"].includes(value.motion)) preferences.motion = value.motion;
        for (const key of ["connection", "recent"]) if (typeof value[key] === "boolean") preferences[key] = value[key];
      }
    } catch { preferences = {...defaults}; }
    applyPreferences();
  }
  function applyPreferences() {
    const root = document.documentElement, accent = palettes[preferences.accent];
    for (const name of ["--accent", "--q-accent", "--focus", "--q-focus"]) root.style.setProperty(name, accent);
    for (const name of ["--accent-tint", "--q-accent-tint"]) root.style.setProperty(name, accent + "18");
    root.dataset.mobileMotion = preferences.motion;
    window.dispatchEvent(new Event("khole-motion-change"));
    for (const key of ["connection", "recent"]) root.dataset["home" + key[0].toUpperCase() + key.slice(1)] = preferences[key] ? "on" : "off";
  }
  function savePreferences() {
    applyPreferences();
    try { localStorage.setItem("khole-mobile-preferences", JSON.stringify(preferences)); saved = true; } catch { saved = false; }
    const note = document.querySelector("#kh-settings-saved");
    if (note) note.textContent = saved ? "Saved on this phone" : "Storage unavailable · changes apply for this visit";
  }
  readPreferences();
  addEventListener("storage", e => { if (e.key === "khole-mobile-preferences" || e.key === null) readPreferences(); });
  addEventListener("pageshow", e => { if (e.persisted) readPreferences(); });
  const motionMedia = matchMedia("(prefers-reduced-motion: reduce)");
  const motionAllowed = () => preferences.motion === "system" && !motionMedia.matches && !document.hidden;
  let sheet = null, opener = null, statusRequest = null, exitAnimation = null;
  const settleMotion = () => { if (!motionAllowed() && exitAnimation) close(); };
  motionMedia.addEventListener("change", settleMotion);
  addEventListener("khole-motion-change", settleMotion);
  document.addEventListener("visibilitychange", settleMotion);
  function dismiss() {
    if (!sheet || exitAnimation) return;
    const target = sheet, card = target.querySelector(".kh-switch-card");
    if (!motionAllowed() || !card.animate) return close();
    if (statusRequest) { statusRequest.abort(); statusRequest = null; }
    target.dataset.closing = "true";
    const start = getComputedStyle(card);
    exitAnimation = card.animate([{opacity:start.opacity,transform:start.transform},{opacity:0,transform:"translateY(12px)"}], {duration:140,easing:"cubic-bezier(.4,0,1,1)",fill:"forwards"});
    exitAnimation.finished.then(() => { if (sheet === target) close(); }).catch(() => {});
  }
  function onKey(e) {
    if (!sheet) return;
    if (e.key === "Escape") { e.stopPropagation(); e.preventDefault(); dismiss(); return; }
    if (exitAnimation) { e.preventDefault(); e.stopPropagation(); return; }
    if (e.key === "Tab") {
      const controls = [...sheet.querySelectorAll('a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled)')];
      const first = controls[0], last = controls[controls.length - 1];
      const current = document.activeElement;
      if (first && ((!e.shiftKey && current === last) || (e.shiftKey && current === first) || !controls.includes(current))) {
        e.preventDefault(); (e.shiftKey ? last : first).focus();
      }
      e.stopPropagation();
    }
  }
  function close() {
    if (!sheet) return;
    if (statusRequest) { statusRequest.abort(); statusRequest = null; }
    if (exitAnimation) { exitAnimation.cancel(); exitAnimation = null; }
    sheet.close(); sheet.remove(); sheet = null;
    document.removeEventListener("keydown", onKey, true);
    if (opener && opener.focus) opener.focus();
  }
  function row(id, name, what, on) {
    const a = document.createElement(id === here ? "div" : "a");
    a.className = "kh-switch-row" + (id === here ? " here" : "") + (on === false ? " off" : "");
    if (id !== here) a.href = "/" + id + "/";
    a.dataset.part = id;
    const n = document.createElement("span"); n.className = "kh-switch-name"; n.textContent = name;
    const w = document.createElement("span"); w.className = "kh-switch-what";
    w.textContent = id === here ? "You're here" : on === false ? "Off on the computer" : what;
    const icon = iconSvg(id, "kh-app-icon");
    const copy = document.createElement("span"); copy.className = "kh-app-copy"; copy.append(n, w);
    a.append(icon, copy);
    if (id === here) a.setAttribute("aria-current", "page");
    return a;
  }
  async function open(from, mode = "apps", swapping = false) {
    if (sheet) return close();
    opener = from;
    sheet = document.createElement("dialog");
    const openedSheet = sheet;
    sheet.className = "kh-switch" + (swapping ? " kh-switch-swap" : "");
    sheet.setAttribute("role", "dialog");
    sheet.setAttribute("aria-modal", "true");
    sheet.setAttribute("aria-label", mode === "settings" ? "Mobile settings" : "Apps");
    const card = document.createElement("div"); card.className = "kh-switch-card";
    const heading = document.createElement("h2"); heading.className = "kh-switch-heading"; heading.tabIndex = -1; heading.textContent = mode === "settings" ? "Settings" : "Apps";
    const list = document.createElement("nav"); list.className = "kh-switch-list";
    let status = null;
    const search = document.createElement("input"); search.type = "search"; search.placeholder = "Find an app";
    search.className = "kh-app-search"; search.setAttribute("aria-label", "Find an app");
    const empty = document.createElement("p"); empty.className = "kh-empty"; empty.textContent = "No matching apps"; empty.hidden = true;
    const draw = (st) => {
      status = st;
      const query = search.value.trim().toLowerCase();
      // the row that had the focus keeps it when the rows are drawn again with the computer's answer
      const had = list.contains(document.activeElement) ? document.activeElement.dataset.part : null;
      list.replaceChildren(...PARTS.filter(part => part.join(" ").toLowerCase().includes(query)).map(([id, name, what]) => row(id, name, what, st ? !!st[id] : undefined)));
      empty.hidden = list.childElementCount !== 0;
      if (had) { const again = list.querySelector(`a[data-part="${had}"]`); if (again) again.focus(); }
    };
    draw(null);
    search.addEventListener("input", () => draw(status));
    const all = document.createElement("a"); all.className = "kh-switch-all"; all.href = "/?hub=1"; all.textContent = "Back to Home";
    const done = document.createElement("button"); done.type = "button"; done.className = "kh-switch-done kh-switch-x";
    done.setAttribute("aria-label", "Close"); done.title = "Close"; done.append(iconSvg("close"));
    done.addEventListener("click", dismiss);
    const settings = document.createElement("button"); settings.type = "button"; settings.className = "kh-switch-settings"; settings.textContent = "Settings";
    settings.addEventListener("click", () => { const from = opener; close(); open(from, "settings", true); });
    const files = document.createElement("a"); files.className = "kh-switch-files"; files.href = "/beam/#folder"; files.textContent = "Shared files";
    const head = document.createElement("div"); head.className = "kh-switch-head"; head.append(heading, done);
    if (mode === "settings") card.append(head, settingsContent(), all);
    else card.append(head, search, list, empty, files, settings, all);
    sheet.append(card);
    sheet.addEventListener("click", (e) => { if (e.target === sheet) dismiss(); });
    // Escape closes it wherever the focus is (the part's own keys never see it)
    document.addEventListener("keydown", onKey, true);
    (document.fullscreenElement || document.body).append(sheet);
    sheet.addEventListener("cancel", (e) => { e.preventDefault(); dismiss(); });
    sheet.showModal();
    heading.focus();
    if (mode === "settings") return;
    const request = new AbortController(); statusRequest = request;
    const timeout = setTimeout(() => request.abort(), 8000);
    try {
      const r = await fetch("/app/status", { signal: request.signal, cache: "no-store", credentials: "same-origin" });
      if (r.ok) { const st = await r.json(); if (sheet === openedSheet && !sheet.dataset.closing) draw(st); }
    } catch (e) {} finally { clearTimeout(timeout); if (statusRequest === request) statusRequest = null; }
  }
  function settingsContent() {
    const content = document.createElement("div"); content.className = "kh-settings";
    function field(title, detail, control) {
      const label = document.createElement("label"), words = document.createElement("span"), name = document.createElement("strong"), description = document.createElement("small");
      label.className = "kh-setting"; name.textContent = title; description.textContent = detail;
      words.append(name, description); label.append(words, control); content.append(label);
    }
    function select(key, choices, title, detail) {
      const el = document.createElement("select"); el.name = key;
      for (const [value, text] of choices) { const option = document.createElement("option"); option.value = value; option.textContent = text; el.append(option); }
      el.value = preferences[key]; el.addEventListener("change", () => { preferences[key] = el.value; savePreferences(); }); field(title, detail, el);
    }
    const palette = document.createElement("fieldset"); palette.className = "kh-palettes";
    const legend = document.createElement("legend"); legend.textContent = "Accent"; palette.append(legend);
    const choices = document.createElement("div"); choices.className = "kh-palette-choices";
    for (const [key, color] of Object.entries(palettes)) {
      const button = document.createElement("button"); button.type = "button"; button.dataset.accent = key;
      button.setAttribute("aria-pressed", String(preferences.accent === key));
      const swatch = document.createElement("span"); swatch.className = "kh-swatch"; swatch.setAttribute("aria-hidden", "true"); swatch.style.setProperty("--swatch", color);
      const label = document.createElement("span"); label.textContent = key[0].toUpperCase() + key.slice(1);
      button.append(swatch, label); button.addEventListener("click", () => {
        preferences.accent = key; savePreferences();
        for (const choice of choices.children) choice.setAttribute("aria-pressed", String(choice === button));
      }); choices.append(button);
    }
    palette.append(choices); content.append(palette);
    select("motion", [["system", "System"], ["reduced", "Reduced"], ["off", "Off"]], "Motion", "System follows your phone’s preference");
    const heading = document.createElement("h3"); heading.textContent = "On your Home"; content.append(heading);
    for (const [key, title, detail] of [["connection", "Connection", "Pairing and computer availability"], ["recent", "Last opened", "A shortcut back to your recent app"]]) {
      const control = document.createElement("input"); control.type = "checkbox"; control.name = key; control.checked = preferences[key];
      control.addEventListener("change", () => { preferences[key] = control.checked; savePreferences(); }); field(title, detail, control);
    }
    const remember = document.createElement("input"); remember.type = "checkbox"; remember.id = "remember";
    try { remember.checked = localStorage.getItem("khole-app-remember") !== "off"; } catch { remember.checked = true; }
    remember.addEventListener("change", () => {
      try { localStorage.setItem("khole-app-remember", remember.checked ? "on" : "off"); saved = true; } catch { saved = false; }
      note.textContent = saved ? "Saved on this phone" : "Storage unavailable · preference could not be saved";
    });
    field("Resume last app", "Open it when launching the installed app", remember);
    // What the phone gives the app: a window shorter than the screen means a band iOS keeps for itself
    const fit = document.createElement("h3"); fit.textContent = "This screen"; content.append(fit);
    const probe = document.createElement("div"); probe.className = "kh-safe-probe"; document.body.append(probe);
    const inset = getComputedStyle(probe); const top = parseFloat(inset.paddingTop) || 0, bottom = parseFloat(inset.paddingBottom) || 0; probe.remove();
    const standalone = matchMedia("(display-mode: standalone), (display-mode: fullscreen)").matches || navigator.standalone === true;
    const whole = Math.abs(innerHeight - screen.height) <= 1 || Math.abs(innerHeight - screen.width) <= 1;
    const facts = document.createElement("dl"); facts.className = "kh-screen-facts";
    for (const [k, v] of [["Window", `${innerWidth} × ${innerHeight}`], ["Screen", `${screen.width} × ${screen.height} at ${Math.round(devicePixelRatio * 100) / 100}×`],
                          ["Safe areas", `${Math.round(top)} top · ${Math.round(bottom)} bottom`], ["Opened as", standalone ? "Home Screen app" : "Browser tab"],
                          ["Fit", !standalone || whole ? "Fills the screen" : "Shorter than the screen"]]) {
      const dt = document.createElement("dt"), dd = document.createElement("dd"); dt.textContent = k; dd.textContent = v; facts.append(dt, dd);
    }
    content.append(facts);
    const note = document.createElement("p"); note.id = "kh-settings-saved"; note.setAttribute("role", "status"); note.textContent = "Preferences stay on this phone"; content.append(note);
    return content;
  }
  function wire(el) {
    if (el.dataset.kholeSwitchWired) return;
    el.dataset.kholeSwitchWired = "1";
    el.hidden = false;
    if (!/^(BUTTON|A)$/.test(el.tagName)) {
      el.setAttribute("role", "button");
      el.tabIndex = 0;
      el.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); open(el); } });
    }
    if (!el.getAttribute("aria-label")) el.setAttribute("aria-label", "Other parts of k-hole");
    el.classList.add("kh-switch-on");
    el.setAttribute("aria-haspopup", "dialog");
    el.title = "Open apps";
    el.addEventListener("click", (e) => { e.preventDefault(); e.stopPropagation(); open(el); });
  }
  const triggers = "[data-khole-switch], [data-shell-apps]";
  const scan = (root) => {
    if (root.matches?.(triggers)) wire(root);
    root.querySelectorAll(triggers).forEach(wire);
    const tools = root.id === "bar-tools" ? root : root.querySelector("#bar-tools");
    if (tools && !document.querySelector("#kh-remote-apps")) {
      const button = document.createElement("button"); button.id = "kh-remote-apps"; button.type = "button"; button.textContent = "Apps"; button.setAttribute("data-khole-switch", ""); tools.append(button); wire(button);
    }
  };
  function mount() {
    const nav = document.createElement("nav"); nav.className = "kh-mobile-nav"; nav.setAttribute("aria-label", "Mobile navigation");
    const items = [["home", "Home"], ["apps", "Apps"], ["settings", "Settings"]];
    for (const [id, name] of items) {
      const el = document.createElement(id === "home" ? "a" : "button");
      const words = document.createElement("span"); words.textContent = name;
      el.append(iconSvg(id, "kh-nav-icon"), words);
      if (id === "home") { el.href = "/?hub=1"; if (here === "home") el.setAttribute("aria-current", "page"); }
      else { el.type = "button"; el.dataset.shell = id; el.setAttribute("aria-haspopup", "dialog"); el.addEventListener("click", () => open(el, id)); }
      nav.append(el);
    }
    document.body.append(nav); scan(document);
  }
  // A Home Screen app is drawn from the screen's top, yet iOS may report its window
  // short by the status bar (innerHeight = screen - top inset) on a page that doesn't
  // scroll, and paints nothing below it. --kh-short is that gap (0 when the window is whole):
  // the bar then needs no room for the home indicator (switch.css --kh-foot), and the page
  // gets room to scroll, which is what gave Beam its whole window (K's recording, update 21).
  let probe = null;
  function measureShort() {
    let gap = 0;
    const standalone = matchMedia("(display-mode: standalone), (display-mode: fullscreen)").matches || navigator.standalone === true;
    if (standalone && document.body) {
      if (!probe) { probe = document.createElement("div"); probe.className = "kh-safe-probe"; probe.setAttribute("aria-hidden", "true"); }
      if (!probe.isConnected) document.body.append(probe);
      const t = parseFloat(getComputedStyle(probe).paddingTop) || 0;
      const ih = innerHeight, sw = screen.width || 0, sh = screen.height || 0;
      const tall = ih >= innerWidth ? Math.max(sw, sh) : Math.min(sw, sh);
      if (t > 0 && Math.abs(ih + t - tall) <= 2) gap = Math.max(0, Math.round(tall - ih));
    }
    if (gap) document.documentElement.classList.add("kh-short-seen");   // stays: never back and forth
    const value = gap + "px";
    if (document.documentElement.style.getPropertyValue("--kh-short") !== value) document.documentElement.style.setProperty("--kh-short", value);
  }
  for (const ev of ["resize", "orientationchange", "pageshow", "focus"]) addEventListener(ev, measureShort);
  visualViewport?.addEventListener("resize", measureShort);
  document.addEventListener("visibilitychange", measureShort);
  document.readyState === "loading" ? addEventListener("DOMContentLoaded", () => { mount(); measureShort(); }) : (mount(), measureShort());
  // Inspect only newly inserted subtrees. Chat tokens, status text and file refreshes
  // must not repeatedly traverse the entire app to find an already-wired header.
  new MutationObserver(records => {
    const roots = new Set();
    for (const record of records) for (const node of record.addedNodes) {
      if (node.nodeType === Node.ELEMENT_NODE && node.isConnected) roots.add(node);
    }
    for (const node of roots) {
      let nested = false;
      for (let parent = node.parentElement; parent; parent = parent.parentElement) {
        if (roots.has(parent)) { nested = true; break; }
      }
      if (!nested) scan(node);
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
  window.kholeSwitch = { open: () => open(null), close, here, icon: iconSvg, measure: measureShort };
})();
