// k-hole in the browser: the client of remote/web/khole-web.
//
// Pair once with the PIN (the token stays in this app's storage), then Connect:
// POST /api/session gives the server's WebRTC offer, we answer, video and sound
// arrive as tracks, and every touch, pointer move and key goes back on the "input"
// data channel as a small JSON message (see InputRouter in khole-web).
//
// Controls follow Microsoft's Windows App: Touch mode sends real multi-touch;
// Mouse pointer mode is a trackpad (one finger moves, tap clicks, two-finger tap
// right-clicks, two-finger drag scrolls, pinch zooms the picture here, press and
// hold then drag to drag). A floating bar holds the rest.
"use strict";

(() => {
  const $ = (id) => document.getElementById(id);
  const store = {
    get(k, d) { try { const v = localStorage.getItem("khole." + k); return v === null ? d : JSON.parse(v); } catch (_) { return d; } },
    set(k, v) { try { localStorage.setItem("khole." + k, JSON.stringify(v)); } catch (_) { /* private mode */ } },
    del(k) { try { localStorage.removeItem("khole." + k); } catch (_) { /* private mode */ } },
  };

  // the computer took its desktop back (its Take it back): no automatic reconnect
  const TAKEN_BACK = "The computer took its desktop back. Tap Connect to use it again.";
  const S = {
    token: store.get("token", ""),
    mode: store.get("mode", "touch"),          // touch | mouse
    q: store.get("quality", { fps: 60, res: "native", kbps: "auto" }),
    sound: store.get("sound", true),
    pc: null, dc: null, session: null,
    kbps: 12000,                                 // what auto currently asks for
    zoom: { z: 1, tx: 0, ty: 0 },
    cursor: { x: 0.5, y: 0.5 },
    mods: {},                                    // name -> "once" | "lock"
    rightArmed: false,
    dragLock: false,
    streamSize: [0, 0],
    pingSent: new Map(), inputRtt: 0,
    statsTimer: 0, lastStats: null, statsOn: false,
    server: null, encoder: "", lastPicture: 0, lastAsk: 0, asks: 0,
    wake: null, reconnects: 0, userClosed: false,
    // want: the person is streaming (Connect worked, no Disconnect since): a dropped or
    // half-dead connection is taken up again by itself, also after the phone comes back
    want: false, connecting: false, retryTimer: 0, healthTimer: 0, discTimer: 0, lastFix: 0, shownAt: 0,
    rot: [0, 90, 270].includes(store.get("rotate", 0)) ? store.get("rotate", 0) : 0,   // the picture turned (portrait only)
    // "phone": the computer makes a screen of its own for this phone, shaped like it and
    // turning with it; "computer": this computer's own screen. phoneScreen: what we got
    screen: store.get("screen", "phone") === "computer" ? "computer" : "phone",
    phoneScreen: false,
  };
  window.khole = S;                              // for the tests and for debugging
  const RETRY_SLOW_MS = Math.max(200, Number(new URLSearchParams(location.search).get("retry_ms")) || 10000);   // tests shorten it

  // ------------------------------------------------------------------ API
  async function api(path, body, method) {
    const opts = { method: method || (body ? "POST" : "GET"), headers: {}, cache: "no-store" };
    if (S.token) opts.headers.Authorization = "Bearer " + S.token;
    if (body) { opts.headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(body); }
    const r = await fetch(path, opts);
    let j = {};
    try { j = await r.json(); } catch (_) { /* empty */ }
    if (!r.ok) { const e = new Error(j.error || ("HTTP " + r.status)); e.status = r.status; e.retry = j.retry_after; e.scope = j.scope; e.screen = j.screen; e.why = j.why; throw e; }
    return j;
  }

  // who this phone is to the computer: its name and the letters Settings > Remote shows beside it
  const LEVELS = { view: "can watch", pointer: "can point and tap", full: "has full control" };
  function setControl(c) {
    S.control = c;
    $("ask-btn").hidden = c === "full";
    $("btn-ask-full").hidden = c === "full";
  }
  function pairedLine(d) {
    d = d || {};
    setControl(d.control || "full");
    S.approve = d.approve === true;
    $("drafts-btn").hidden = !S.approve;
    let s = "Paired as " + (d.name || "this phone");
    if (d.fp) s += " · " + d.fp;
    s += ".";
    if (d.control && d.control !== "full") s += " This phone " + LEVELS[d.control] + ".";
    return s;
  }

  // ------------------------------------------------------------------ screens
  function show(which) {
    for (const id of ["pair", "connect", "login", "stream", "drafts", "tv"]) $(id).hidden = id !== which;
    lockZoom(which === "stream");
    if (which === "pair") setTimeout(() => $("pin").focus(), 50);
    if (which === "login" && !$("login-pw").disabled) setTimeout(() => $("login-pw").focus(), 50);
  }
  // The pairing and sign-in screens can be zoomed (their words, for people who need them
  // larger); the stream can't: a pinch or a double tap there is the desktop's, and a page
  // zoomed by the browser would move the frame the picture and the touches are mapped in.
  const ZOOM = "width=device-width, initial-scale=1, viewport-fit=cover";
  function lockZoom(on) {
    const m = document.querySelector('meta[name="viewport"]');
    const want = on ? ZOOM + ", maximum-scale=1, user-scalable=no" : ZOOM;
    if (m && m.content !== want) { m.content = want; S.frame = null; }
  }
  const standalone = () => matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;

  // ------------------------------------------------------------------ a TV asks (k-stream)
  // k-stream on another computer opens this page as <origin>#tv=<its address>&nonce=<64 hex>;
  // Allow asks the computer for a one-use, view-only ticket for that k-stream and goes back to
  // it with the ticket in the address's fragment (never sent to any server).
  function tvAsk() {
    const h = new URLSearchParams(location.hash.slice(1));
    if (!h.has("tv")) return null;
    history.replaceState(null, "", location.pathname + location.search);
    const nonce = h.get("nonce") || "";
    let cb;
    try { cb = new URL(h.get("tv") || ""); } catch (_) { return null; }
    if (!/^[a-f0-9]{64}$/.test(nonce) || !/^https?:$/.test(cb.protocol) || cb.pathname !== "/local/"
        || cb.username || cb.password || cb.search || cb.hash) return null;
    return { callback: cb.href, nonce, host: cb.host };
  }
  S.tv = tvAsk();
  function tvScreen() {
    $("tv-who").textContent = "k-stream at " + S.tv.host + " asks to watch this computer's screen.";
    $("tv-error").textContent = "";
    show("tv");
    setTimeout(() => $("tv-allow").focus(), 50);
  }
  $("tv-allow").addEventListener("click", async () => {
    if (!S.tv) return;
    $("tv-allow").disabled = true;
    $("tv-error").textContent = "";
    try {
      const r = await api("/api/delegate", { callback: S.tv.callback, nonce: S.tv.nonce });
      const back = r.callback + "#" + new URLSearchParams({ ticket: r.ticket, host: r.host, nonce: r.nonce });
      S.tv = null;
      location.assign(back);
    } catch (e) {
      $("tv-error").textContent = e.status === 401 ? "Pair this phone again first." : e.message;
    } finally { $("tv-allow").disabled = false; }
  });
  $("tv-no").addEventListener("click", () => { S.tv = null; start(); });
  // the page already open when the TV's link arrives: same document, so only the fragment changes
  addEventListener("hashchange", () => {
    const t = tvAsk();
    if (t && $("stream").hidden) { S.tv = t; start(); }
  });

  async function start() {
    if ("serviceWorker" in navigator && isSecureContext) navigator.serviceWorker.register("sw.js").catch(() => {});
    $("a2hs").hidden = standalone() || !/iPhone|iPad|iPod/.test(navigator.userAgent);
    if (!S.token) return show("pair");
    try {
      const hello = await api("/api/hello");
      if (hello.screen === "login") return atLogin(hello);
      if (S.tv) return tvScreen();
      $("connect-status").textContent = pairedLine(hello.device);
      show("connect");
      refreshDraftCount();
    } catch (e) {
      if (e.status === 401) { S.token = ""; store.del("token"); return show("pair"); }
      $("connect-status").textContent = "The computer didn't answer: " + e.message;
      show("connect");
    }
  }

  $("pair-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const pin = $("pin").value.trim();
    $("pair-error").textContent = "";
    if (!/^[0-9]{6}$/.test(pin)) { $("pair-error").textContent = "The PIN is 6 digits."; return; }
    try {
      const r = await api("/api/pair", { pin, name: $("devname").value.trim() || guessName() });
      S.token = r.token; store.set("token", r.token);
      $("pin").value = "";
      $("connect-status").textContent = pairedLine(r.device) + (r.device.fp ? " The computer shows the same letters beside it." : "");
      if (S.tv) return tvScreen();
      show("connect");
    } catch (e) {
      $("pair-error").textContent = e.message;
    }
  });
  // Safari and the Home Screen app keep their own pairing: name each so Settings > Remote
  // (and the computer's question) can tell them apart
  function guessName() {
    const ua = navigator.userAgent;
    const base = /iPad/.test(ua) ? "iPad" : /iPhone/.test(ua) ? "iPhone" : "Browser";
    if (base === "Browser") return base;
    return base + (standalone() ? " (Home Screen)" : " (Safari)");
  }
  $("devname").placeholder = guessName();

  $("ask-btn").addEventListener("click", async () => {
    try {
      await api("/api/ask-control", { level: "full" });
      $("connect-status").textContent = "Asked: the computer shows a notification. Connect again once it says yes.";
    } catch (e) { $("connect-status").textContent = e.message; }
  });

  $("unpair-btn").addEventListener("click", async () => {
    try { await api("/api/unpair", {}); } catch (_) { /* gone anyway */ }
    S.token = ""; store.del("token"); show("pair");
  });

  // ------------------------------------------------------------------ the login screen
  // After a restart or a log out the computer answers with its sign-in page only
  // (khole-web --login). A full-control phone types the password; the login screen
  // starts the session locked, and once the desktop's own browser view answers, the
  // stream starts and the person unlocks it like any locked screen.
  let loginWait = 0, loginUntil = 0;
  function atLogin(hello) {
    teardown();
    const who = hello.name || hello.user || "";
    $("login-who").textContent = "The computer is at its login screen" + (who ? ": sign in as " + who + "." : ".");
    const can = hello.can === true;
    $("login-pw").disabled = !can;
    $("login-btn").disabled = !can;
    $("login-error").textContent = can ? "" : (typeof hello.why === "string" && hello.why) ? hello.why :
      "This phone can't sign in: on the computer, give it Full control in Settings, Remote.";
    if (!loginWait) $("login-status").textContent = "";
    show("login");
  }
  async function loginCheck() {
    try {
      const hello = await api("/api/hello");
      if (hello.screen === "login") { atLogin(hello); return "login"; }
      clearTimeout(loginWait); loginWait = 0;
      $("login-status").textContent = "";
      $("connect-status").textContent = pairedLine(hello.device);
      show("connect");
      if (S.want || S.signedIn) { S.signedIn = false; S.want = true; S.reconnects = 0; connect(true); }
      return "desktop";
    } catch (e) {
      if (e.status === 401) { S.want = false; S.token = ""; store.del("token"); show("pair"); return "pair"; }
      return "gone";                 // between the login page and the desktop's own server
    }
  }
  function waitForDesktop() {
    clearTimeout(loginWait);
    loginWait = setTimeout(async () => {
      loginWait = 0;
      const where = await loginCheck();
      if (where === "desktop" || where === "pair") return;
      if (performance.now() > loginUntil) {
        $("login-status").textContent = "The desktop hasn't answered yet. Tap Check again in a moment.";
        S.signedIn = false;
        return;
      }
      waitForDesktop();
    }, 2000);
  }
  $("login-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const pw = $("login-pw").value;
    $("login-error").textContent = "";
    if (!pw) { $("login-error").textContent = "Type the password."; return; }
    $("login-btn").disabled = true;
    $("login-status").textContent = "Signing in…";
    try {
      await api("/api/login", { password: pw });
      $("login-pw").value = "";
      S.signedIn = true;
      $("login-status").textContent = "Signed in. The computer's screen is locked: unlock it here once the picture shows.";
      loginUntil = performance.now() + 90000;
      waitForDesktop();
    } catch (e) {
      $("login-pw").value = "";
      $("login-status").textContent = "";
      if (e.status === 503 && e.screen === "login") $("login-error").textContent = "Couldn't sign in: try again.";
      else if (e.status === 429) $("login-error").textContent = e.message + (e.retry ? " (" + Math.ceil(e.retry / 60) + " min)" : "");
      else if (e.status === 401 && e.why !== "wrong") { S.token = ""; store.del("token"); show("pair"); return; }
      else $("login-error").textContent = e.message;
      if (e.status === 503 && !e.screen) loginCheck();
    } finally {
      $("login-btn").disabled = $("login-pw").disabled;
      if (!$("login").hidden && !$("login-pw").disabled) $("login-pw").focus();
    }
  });
  $("login-check").addEventListener("click", () => { $("login-status").textContent = "Checking…"; loginCheck().then((w) => { if (w === "gone") $("login-status").textContent = "The computer didn't answer."; else if (w === "login" && !loginWait) $("login-status").textContent = ""; }); });

  $("connect-btn").addEventListener("click", () => {
    // inside the tap: unlock sound on iOS (a play() the user started lets later ones through)
    const a = $("audio");
    a.muted = !S.sound;
    a.play().catch(() => {});
    S.reconnects = 0;
    connect();
  });

  // ------------------------------------------------------------------ drafts
  // What the computer's workflows and loops want to send, waiting for a yes. Only a
  // phone given the right to approve (Settings > Remote on the computer) sees them.
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; };
  const btn = (cls, text) => { const b = el("button", cls, text); b.type = "button"; return b; };

  $("drafts-btn").addEventListener("click", () => { show("drafts"); loadDrafts(); });
  $("drafts-back").addEventListener("click", () => { show("connect"); refreshDraftCount(); });
  $("drafts-refresh").addEventListener("click", loadDrafts);

  async function refreshDraftCount() {
    if (!S.approve) return;
    try {
      const r = await api("/api/drafts");
      const n = r.drafts.filter((d) => d.state === "waiting" && !d.test).length;
      $("drafts-btn").textContent = n ? `Drafts (${n} waiting)` : "Drafts";
    } catch (_) { $("drafts-btn").textContent = "Drafts"; }
  }

  async function loadDrafts() {
    const st = $("drafts-status");
    st.textContent = "Loading…";
    try {
      const r = await api("/api/drafts");
      renderDrafts(r.drafts || []);
      const n = (r.drafts || []).filter((d) => d.state === "waiting" && !d.test).length;
      st.textContent = n ? `${n} waiting for you.` : "Nothing waits for you.";
    } catch (e) {
      if (e.status === 401) { S.token = ""; store.del("token"); show("pair"); return; }
      if (e.status === 403) { S.approve = false; $("drafts-btn").hidden = true; }
      st.textContent = e.message;
      $("drafts-list").replaceChildren();
    }
  }

  function renderDrafts(list) {
    const box = $("drafts-list");
    box.replaceChildren();
    if (!list.length) { box.append(el("p", "empty", "No drafts. When a workflow or loop wants to send something, it waits here.")); return; }
    const groups = new Map();
    for (const d of list) { const k = d.task_name || d.task || "Workflow"; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(d); }
    for (const [name, items] of groups) {
      const g = el("section", "group");
      g.setAttribute("aria-label", name);
      g.append(el("h2", "", `${name} · ${items.length}`));
      for (const d of items) g.append(draftCard(d));
      box.append(g);
    }
  }

  function draftCard(d) {
    const card = el("article", "draft");
    card.dataset.id = d.id;
    const chips = el("div", "chips");
    if (d.to) chips.append(el("span", "chip", "To " + d.to));
    if (d.at) chips.append(el("span", "chip", "At " + String(d.at).replace("T", " ").slice(0, 16)));
    if (d.cloud) chips.append(el("span", "chip", "Cloud runner"));
    if (d.test) chips.append(el("span", "chip test", "Test run: never sent"));
    if (d.state !== "waiting") chips.append(el("span", "chip", d.state === "approved" ? "Approved, waiting for its time" : "Sending"));
    if (chips.childElementCount) card.append(chips);
    card.append(el("h3", "", d.title || d.action || "Draft"));
    if (d.body) {
      const b = el("p", "body", d.body);
      b.addEventListener("click", () => b.classList.toggle("open"));
      card.append(b);
    }
    if (d.quote) card.append(el("blockquote", "", d.quote));
    for (const a of d.attachments || []) card.append(el("p", "meta", "Attached: " + a));
    const outcome = el("p", "outcome");
    outcome.setAttribute("role", "status");
    outcome.hidden = true;
    if (d.state === "waiting") {
      const row = el("div", "row");
      const skip = btn("ghost", "Skip");
      const edit = btn("ghost", "Edit");
      const ok = btn("primary", "Approve");
      ok.disabled = !!d.test;
      edit.hidden = !!d.test || !(d.fields || []).length;
      row.append(skip, edit, ok);
      card.append(row);
      const form = editForm(d, card, outcome, row);
      card.append(form);
      skip.addEventListener("click", () => act(d, "skip", null, card, outcome, row));
      ok.addEventListener("click", () => act(d, "approve", null, card, outcome, row));
      edit.addEventListener("click", () => { form.hidden = false; row.hidden = true; const f = form.querySelector("textarea, input"); if (f) f.focus(); });
    }
    card.append(outcome);
    return card;
  }

  function editForm(d, card, outcome, row) {
    const form = el("form");
    form.hidden = true;
    form.setAttribute("aria-label", "Edit " + (d.title || "draft"));
    const inputs = [];
    for (const f of d.fields || []) {
      const id = `f-${d.id}-${f.name}`;
      const lab = el("label", "", f.label);
      lab.htmlFor = id;
      const inp = f.long ? el("textarea") : el("input");
      inp.id = id; inp.value = f.value; inp.dataset.name = f.name;
      if (!f.long) inp.autocomplete = "off";
      form.append(lab, inp);
      inputs.push([f, inp]);
    }
    const r = el("div", "row");
    const cancel = btn("ghost", "Cancel");
    const go = el("button", "primary", "Approve with changes");
    go.type = "submit";
    r.append(cancel, go);
    form.append(r);
    cancel.addEventListener("click", () => { form.hidden = true; row.hidden = false; });
    form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      const edit = {};
      for (const [f, inp] of inputs) if (inp.value !== f.value) edit[f.name] = inp.value;
      act(d, "approve", Object.keys(edit).length ? edit : null, card, outcome, row, form);
    });
    return form;
  }

  async function act(d, verb, edit, card, outcome, row, form) {
    const buttons = card.querySelectorAll("button");
    buttons.forEach((b) => { b.disabled = true; });
    outcome.hidden = false; outcome.className = "outcome"; outcome.textContent = verb === "approve" ? "Sending…" : "Skipping…";
    try {
      const r = await api(`/api/drafts/${encodeURIComponent(d.id)}/${verb}`, edit ? { edit } : {});
      outcome.textContent = r.words || (verb === "approve" ? "Approved." : "Skipped.");
      card.classList.add("done");
      row.hidden = true; if (form) form.hidden = true;
    } catch (e) {
      outcome.className = "outcome bad";
      outcome.textContent = e.message;
      buttons.forEach((b) => { b.disabled = false; });
      if (d.test) row.querySelector(".primary").disabled = true;
    }
  }

  // ------------------------------------------------------------------ WebRTC
  function viewportPx() {
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    const even = (n) => Math.max(2, Math.round(n * dpr / 2) * 2);
    return [even(viewW()), even(viewH())];
  }

  // auto: a try of the phone's own (a retry, back from away), which never takes the
  // picture from another device; a tap on Connect does
  async function connect(auto) {
    if (S.connecting) return;
    S.connecting = true;
    S.userClosed = false;
    clearTimeout(S.retryTimer);
    $("connect-btn").disabled = true;
    $("connect-status").textContent = "Connecting…";
    teardown();
    const [w, h] = viewportPx();
    try {
      const pc = new RTCPeerConnection({ iceServers: [], bundlePolicy: "max-bundle" });
      S.pc = pc;
      pc.ontrack = (e) => {
        try { e.receiver.jitterBufferTarget = 0; } catch (_) { /* Safari before it had it */ }
        if ("playoutDelayHint" in e.receiver) e.receiver.playoutDelayHint = 0;
        if (e.track.kind === "video") {
          const v = $("video");
          v.srcObject = new MediaStream([e.track]);
          v.play().catch(() => {});
        } else {
          const a = $("audio");
          a.srcObject = new MediaStream([e.track]);
          a.muted = !S.sound;
          a.play().catch(() => {});
        }
      };
      pc.ondatachannel = (e) => setupChannel(e.channel);
      pc.onconnectionstatechange = () => {
        const st = pc.connectionState;
        if (st === "connected") { S.reconnects = 0; clearTimeout(S.discTimer); wakeLock(); }
        if ((st === "failed" || st === "closed") && S.pc === pc) lost("The connection dropped.");
        // "disconnected" can heal by itself; if it hasn't in a few seconds, start over
        // (Safari leaves a connection there for good after the app was away)
        if (st === "disconnected" && S.pc === pc) {
          clearTimeout(S.discTimer);
          S.discTimer = setTimeout(() => {
            if (S.pc === pc && pc.connectionState !== "connected" && document.visibilityState === "visible") reconnect("The connection stalled: reconnecting…");
          }, 4000);
        }
      };
      const kbps = S.q.kbps === "auto" ? S.kbps : S.q.kbps;
      const r = await api("/api/session", { w, h, fps: S.q.fps, res: S.q.res, kbps, screen: S.screen, auto: auto === true });
      S.session = r.id;
      if (LEVELS[r.control]) setControl(r.control);     // changed while away: no reload needed
      setHeld(false);
      const was = S.phoneScreen;
      S.phoneScreen = r.screen === "phone";
      if (S.screen === "phone" && !S.phoneScreen && r.why) toast("Showing the computer's screen: " + r.why + ".");
      else if (S.phoneScreen && !was) toast("A screen of its own, shaped like this phone.");
      await pc.setRemoteDescription({ type: "offer", sdp: r.sdp });
      const ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      await gathered(pc, 1500);
      await api("/api/answer", { id: r.id, sdp: pc.localDescription.sdp });
      S.want = true;
      show("stream");
      applyMode(); applyEdge(); applyRotate(); applyZoom();
      startStats();
    } catch (e) {
      teardown();
      show("connect");
      $("connect-status").textContent = e.status === 401 ? "This phone isn't paired any more." : "Couldn't connect: " + e.message;
      if (e.status === 401) { S.want = false; S.token = ""; store.del("token"); show("pair"); }
      else if (e.status === 409 && e.scope === "taken-back") { S.want = false; $("connect-status").textContent = TAKEN_BACK; }
      else if (e.status === 409 && e.scope === "busy") { S.want = false; $("connect-status").textContent = "Another device is using the computer now. Tap Connect to take over."; }
      else if (e.status === 503 && e.screen === "login") loginCheck();
      else setTimeout(() => retry($("connect-status").textContent));
    } finally {
      S.connecting = false;
      $("connect-btn").disabled = false;
    }
  }

  function gathered(pc, ms) {
    if (pc.iceGatheringState === "complete") return Promise.resolve();
    return new Promise((res) => {
      const t = setTimeout(res, ms);
      pc.addEventListener("icegatheringstatechange", () => { if (pc.iceGatheringState === "complete") { clearTimeout(t); res(); } });
    });
  }

  function setupChannel(ch) {
    S.dc = ch;
    ch.onmessage = (e) => {
      let m; try { m = JSON.parse(e.data); } catch (_) { return; }
      if (m.t === "size" || m.t === "hello") { if (m.w && m.h) S.streamSize = [m.w, m.h]; if (m.encoder) S.encoder = m.encoder; }
      else if (m.t === "stats") S.server = m;
      else if (m.t === "pong") { const t0 = S.pingSent.get(m.n); if (t0) { S.inputRtt = performance.now() - t0; S.pingSent.delete(m.n); } }
      else if (m.t === "clip") { const cb = clipWaiters.get(m.n); if (cb) { clipWaiters.delete(m.n); cb(m); } }
      else if (m.t === "restart") { toast(m.reason === "stall" ? "The picture stopped: reconnecting…" : m.reason === "turn" ? "The screen turned with the phone…" : "The view changed: reconnecting…"); setTimeout(() => connect(true), 300); }
      else if (m.t === "control") {
        const was = S.control;
        setControl(m.control);
        if (m.denied === "keys") { needFullToType(); }
        else if (m.denied === "pointer") toast("This phone can only watch: tap More, then Full control, and allow it at the computer.");
        else if (m.asked === "no") toast("The computer said not now: this phone " + (LEVELS[m.control] || "keeps what it had") + ".");
        else if (m.control !== was) toast("This phone " + (LEVELS[m.control] || "has new permissions") + " now.");
      }
      else if (m.t === "held") setHeld(m.on === true);
      else if (m.t === "bye" && m.unpaired) { S.userClosed = true; S.want = false; teardown(); releaseWake(); S.token = ""; store.del("token"); show("pair"); $("pair-error").textContent = "This phone was unpaired on the computer."; }
      else if (m.t === "bye" && m.taken_back) { S.want = false; lost(TAKEN_BACK); }
      else if (m.t === "bye") {
        if (/closed by the phone/.test(m.reason || "")) return;
        if (/taken over/.test(m.reason || "")) S.want = false;   // another phone has it now: don't take it back
        lost(m.reason ? "Disconnected: " + m.reason + "." : "Disconnected.");
      }
    };
    ch.onopen = () => { send({ t: "resize", w: viewportPx()[0], h: viewportPx()[1] }); };
  }

  function setHeld(on) {
    if (S.held === on) return;
    S.held = on;
    $("held").hidden = !on;
    if (!on && S.heldSeen) toast("Answered: this phone can use the computer again.");
    S.heldSeen = on;
  }

  // what a tap or a key does while the channel is down: nothing reaches the computer, so say it
  // (once in a few seconds), never fail silently
  const QUIET = { resize: 1, release: 1, ping: 1, keyframe: 1, quality: 1 };
  let unsentAt = 0;
  function send(obj) {
    const ch = S.dc;
    if (ch && ch.readyState === "open") { ch.send(JSON.stringify(obj)); return true; }
    if (!QUIET[obj.t] && S.want && performance.now() - unsentAt > 3000) {
      unsentAt = performance.now();
      toast(S.connecting ? "Still connecting: that didn't reach the computer." : "Not connected: that didn't reach the computer.");
    }
    return false;
  }

  function teardown() {
    stopStats();
    clearTimeout(S.discTimer); clearTimeout(S.healthTimer);
    if (S.dc) { try { S.dc.close(); } catch (_) { /* closed */ } }
    if (S.pc) { try { S.pc.close(); } catch (_) { /* closed */ } }
    S.dc = null; S.pc = null;
    $("video").srcObject = null;
  }

  function lost(why) {
    if (!S.pc) return;
    teardown();
    releaseWake();
    show("connect");
    $("connect-status").textContent = why;
    retry(why);
  }

  // the connection went while streaming: try again a few times; with the phone away
  // (locked, another app) wait until it's back (resume)
  function retry(why) {
    if (!S.want || S.userClosed || !S.token || document.visibilityState !== "visible") return;
    clearTimeout(S.retryTimer);
    S.reconnects++;
    // four quick tries, then every 10 s while this page is shown (the computer restarting,
    // the network changing): the phone comes back by itself, and Connect tries at once
    if (S.reconnects > 4) {
      $("connect-status").textContent = why + " The computer isn't answering yet: trying again every few seconds.";
      S.retryTimer = setTimeout(() => connect(true), RETRY_SLOW_MS);
      return;
    }
    S.retryTimer = setTimeout(() => connect(true), 600 * S.reconnects);
  }

  // start over at once, keeping the stream screen (the last picture goes, a new one comes)
  function reconnect(why) {
    if (S.connecting) return;
    S.lastFix = performance.now();
    toast(why);
    connect(true);
  }

  // the phone is back (unlocked, back from another app, the tab shown again): the
  // connection may be gone, half dead, or fine with a paused picture. Safari pauses
  // the video while away and often leaves the connection "connected" with nothing
  // coming, so look: play again, ask for a keyframe, and start over when no new
  // picture is decoded within 3 s
  async function resume() {
    S.shownAt = performance.now();
    if (document.visibilityState !== "visible" || !S.want || S.userClosed || !S.token || S.connecting) return;
    S.reconnects = 0;
    if (!S.pc) { connect(true); return; }
    const pc = S.pc;
    if (pc.connectionState !== "connected" || !S.dc || S.dc.readyState !== "open") { reconnect("Reconnecting…"); return; }
    wakeLock();
    S.lastPicture = performance.now();
    $("video").play().catch(() => {});
    if (S.sound) $("audio").play().catch(() => {});
    send({ t: "keyframe" });
    const f0 = await decoded(pc);
    clearTimeout(S.healthTimer);
    S.healthTimer = setTimeout(async () => {
      if (S.pc !== pc || document.visibilityState !== "visible" || S.connecting) return;
      if (await decoded(pc) <= f0) reconnect("The picture didn't come back: reconnecting…");
    }, 3000);
  }
  async function decoded(pc) {
    let n = 0;
    try { (await pc.getStats()).forEach((r) => { if (r.type === "inbound-rtp" && r.kind === "video") n = r.framesDecoded || 0; }); } catch (_) { /* closed */ }
    return n;
  }

  async function disconnect() {
    S.userClosed = true;
    S.want = false;
    send({ t: "release" });
    const id = S.session;
    teardown(); releaseWake();
    show("connect");
    $("connect-status").textContent = "Disconnected.";
    try { await api("/api/close", { id }); } catch (_) { /* gone anyway */ }
  }

  // keep the screen on while streaming
  async function wakeLock() {
    try { if ("wakeLock" in navigator && !S.wake) { S.wake = await navigator.wakeLock.request("screen"); S.wake.addEventListener("release", () => { S.wake = null; }); } } catch (_) { /* not allowed */ }
  }
  function releaseWake() { if (S.wake) { S.wake.release().catch(() => {}); S.wake = null; } }
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") resume();
    else { send({ t: "release" }); clearTimeout(S.healthTimer); }   // let go of held keys and fingers
  });
  window.addEventListener("pageshow", (e) => { if (e.persisted) resume(); });   // back from the page cache
  window.addEventListener("online", () => resume());
  // Wi-Fi to cellular and back: the old path is gone even when the page never hid
  if (navigator.connection && navigator.connection.addEventListener) navigator.connection.addEventListener("change", () => resume());

  // ------------------------------------------------------------------ geometry
  // Turned: the whole stream view (picture, bar, sheets) is rotated a quarter turn so a
  // 16:9 desktop fills a phone held sideways while the phone stays in portrait (Safari's
  // rotation lock, or just a browser that doesn't turn). Only while the window is
  // portrait. Everything below works in the view's own frame: toView() takes a point on
  // the glass to it, dView() a movement.
  // (never with a phone screen: that one turns with the phone itself)
  // The frame: the part of the glass the picture uses, from under the status bar to the
  // very bottom (viewport-fit=cover). A Home Screen app with a black-translucent status bar
  // is drawn from the screen's top, under the clock, where iOS keeps taps for itself; and
  // some iOS versions report its window short by the status bar's height (innerHeight =
  // screen - top inset) while the page still starts at the screen's top, so a picture sized
  // to the window sat under the clock and left that much of the bottom unused. The frame
  // starts at the top inset and, in such a short window, runs on to the screen's bottom.
  function measureFrame() {
    const W = window.innerWidth, ih = window.innerHeight;
    const t = Math.max(0, parseFloat(getComputedStyle($("safe-probe")).paddingTop) || 0);
    let bottom = ih;
    if (t > 0 && standalone()) {
      const sw = screen.width || 0, sh = screen.height || 0;
      const tall = ih >= W ? Math.max(sw, sh) : Math.min(sw, sh);
      if (Math.abs(ih + t - tall) <= 2) bottom = tall;       // the short window: the screen goes on
    }
    return { x: 0, y: t, w: W, h: Math.max(2, bottom - t) };
  }
  function frame() { return S.frame || (S.frame = measureFrame()); }

  // Turned: the whole stream view (picture, bar, sheets) is rotated a quarter turn so a
  // 16:9 desktop fills a phone held sideways while the phone stays in portrait (Safari's
  // rotation lock, or just a browser that doesn't turn). Only while the window is
  // portrait. Everything below works in the view's own frame: toView() takes a point on
  // the glass to it, dView() a movement.
  // (never with a phone screen: that one turns with the phone itself)
  function rotNow() { const f = frame(); return S.rot && !S.phoneScreen && f.h > f.w ? S.rot : 0; }
  function viewW() { const f = frame(); return rotNow() ? f.h : f.w; }
  function viewH() { const f = frame(); return rotNow() ? f.w : f.h; }
  function toView(x, y) {
    const r = rotNow(), f = frame();
    x -= f.x; y -= f.y;
    if (r === 90) return [y, f.w - x];     // the picture's top on the phone's right
    if (r === 270) return [f.h - y, x];    // its top on the phone's left
    return [x, y];
  }
  function dView(dx, dy) {
    const r = rotNow();
    return r === 90 ? [dy, -dx] : r === 270 ? [-dy, dx] : [dx, dy];
  }
  function applyRotate() {
    S.frame = measureFrame();
    const f = S.frame, r = rotNow(), el = $("stream"), W = f.w, H = f.h;
    el.classList.toggle("turned", !!r);
    el.style.top = f.y + "px";
    if (!r) { el.style.width = ""; el.style.height = H + "px"; el.style.transform = ""; }
    else {
      el.style.width = H + "px"; el.style.height = W + "px";
      el.style.transform = r === 90 ? `translate(${W}px, 0) rotate(90deg)` : `translate(0, ${H}px) rotate(-90deg)`;
    }
    el.dataset.rot = String(r);
    press($("btn-rotate"), !!S.rot);
    $("btn-rotate").hidden = S.phoneScreen;
    press($("btn-screen"), S.screen === "phone");
    placeBar();
  }

  // the picture's box in the view (object-fit: contain, then the local zoom)
  function contentBox() {
    const W = viewW(), H = viewH();
    const v = $("video");
    const vw = v.videoWidth || S.streamSize[0] || W, vh = v.videoHeight || S.streamSize[1] || H;
    const k = Math.min(W / vw, H / vh);
    const bw = vw * k, bh = vh * k, bx = (W - bw) / 2, by = (H - bh) / 2;
    const z = S.zoom;
    return { x: bx * z.z + z.tx, y: by * z.z + z.ty, w: bw * z.z, h: bh * z.z, base: { x: bx, y: by, w: bw, h: bh } };
  }
  function toNorm(sx, sy) {                       // a point on the glass
    const [cx, cy] = toView(sx, sy);
    const b = contentBox();
    return [(cx - b.x) / b.w, (cy - b.y) / b.h];
  }
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  const inside = (n) => n[0] >= 0 && n[0] <= 1 && n[1] >= 0 && n[1] <= 1;

  function applyZoom() {
    const z = S.zoom;
    // keep the picture covering the screen where it can
    const W = viewW(), H = viewH();
    z.z = Math.max(1, Math.min(4, z.z));
    if (z.z === 1) { z.tx = 0; z.ty = 0; }
    else {
      z.tx = Math.min(0, Math.max(W - W * z.z, z.tx));
      z.ty = Math.min(0, Math.max(H - H * z.z, z.ty));
    }
    $("video").style.transform = z.z === 1 ? "" : `translate(${z.tx}px, ${z.ty}px) scale(${z.z})`;
    press($("btn-zoom"), z.z > 1);
  }
  function zoomAt(cx, cy, factor) {
    const z = S.zoom;
    const nz = Math.max(1, Math.min(4, z.z * factor));
    // the point under (cx, cy) stays put
    z.tx = cx - (cx - z.tx) * (nz / z.z);
    z.ty = cy - (cy - z.ty) * (nz / z.z);
    z.z = nz;
    applyZoom();
  }
  // the pointer stays in view while zoomed (Windows App pans the same way)
  function followCursor() {
    if (S.zoom.z === 1) return;
    const b = contentBox();
    const px = b.x + S.cursor.x * b.w, py = b.y + S.cursor.y * b.h;
    const W = viewW(), H = viewH(), m = 48;
    let dx = 0, dy = 0;
    if (px < m) dx = m - px; else if (px > W - m) dx = W - m - px;
    if (py < m) dy = m - py; else if (py > H - m) dy = H - m - py;
    if (dx || dy) { S.zoom.tx += dx; S.zoom.ty += dy; applyZoom(); }
  }

  // ------------------------------------------------------------------ touch input
  const surface = $("surface");
  const T = {                                    // gesture state
    pts: new Map(),                              // id -> {x, y, x0, y0, t0}
    remote: new Set(),                           // ids sent to the remote as touches (touch mode)
    gesture: null,                               // mouse mode: null | move | drag | scroll | pinch | armed
    lastTapEnd: 0, lastTapPos: null,
    holdTimer: 0, maxPts: 0, startT: 0, moved: 0,
    pinch0: 0, mid0: null, zoom0: null,
    lastMove: 0,
  };
  const TAP_MS = 250, TAP_PX = 10, HOLD_MS = 500, DOUBLE_MS = 300;
  // touch mode: a lone finger waits this long before it reaches the computer, so a second
  // one landing makes a two-finger tap (a right-click) instead of a tap; a tap that ends
  // sooner still arrives whole, held TAP_HOLD_MS like a real one
  const HOLDBACK_MS = 90, TAP_HOLD_MS = 40;
  T.wait = null;                                 // {ids: [first, second?], t0, timer}

  surface.addEventListener("touchstart", onTouchStart, { passive: false });
  surface.addEventListener("touchmove", onTouchMove, { passive: false });
  surface.addEventListener("touchend", onTouchEnd, { passive: false });
  surface.addEventListener("touchcancel", onTouchEnd, { passive: false });
  // Safari's page pinch
  document.addEventListener("gesturestart", (e) => e.preventDefault());
  document.addEventListener("gesturechange", (e) => e.preventDefault());
  document.addEventListener("dblclick", (e) => e.preventDefault());

  function closeSheets() {
    if (!$("sheet").hidden) { $("sheet").hidden = true; $("btn-more").setAttribute("aria-expanded", "false"); return true; }
    if (!$("bar").classList.contains("collapsed")) { $("bar-handle").click(); return true; }   // the open tools
    return false;
  }

  function onTouchStart(e) {
    e.preventDefault();
    if (closeSheets() && e.touches.length === 1) { T.swallow = true; return; }
    T.swallow = false;
    const now = performance.now();
    for (const t of e.changedTouches) T.pts.set(t.identifier, { x: t.clientX, y: t.clientY, x0: t.clientX, y0: t.clientY, t0: now });
    if (S.mode === "touch" && !S.rightArmed) return touchStartHeld(e, now);
    if (S.mode === "touch") return;              // right-click armed: the tap's end decides
    mouseStart(e, now);
  }
  function onTouchMove(e) {
    e.preventDefault();
    if (T.swallow) return;
    const prev = new Map();
    for (const t of e.changedTouches) {
      const p = T.pts.get(t.identifier);
      if (!p) continue;
      prev.set(t.identifier, { x: p.x, y: p.y });
      p.x = t.clientX; p.y = t.clientY;
      T.moved = Math.max(T.moved, Math.hypot(p.x - p.x0, p.y - p.y0));
    }
    if (S.mode === "touch" && !S.rightArmed) {
      if (T.wait && T.moved >= (T.wait.ids.length > 1 ? TAP_PX * 2 : TAP_PX)) flushWait();
      if (T.wait) return;
      return touchModeSend(e.changedTouches, "m");
    }
    if (S.mode === "mouse") mouseMove(e, prev);
  }
  function onTouchEnd(e) {
    e.preventDefault();
    if (T.swallow) { for (const t of e.changedTouches) T.pts.delete(t.identifier); if (!e.touches.length) T.swallow = false; return; }
    if (S.mode === "touch" && !S.rightArmed) {
      if (T.wait) return touchEndHeld(e);
      touchModeSend(e.changedTouches, e.type === "touchcancel" ? "c" : "u");
      for (const t of e.changedTouches) T.pts.delete(t.identifier);
      return;
    }
    if (S.mode === "touch" && S.rightArmed) {       // the armed right-click lands where the finger lifted
      const t = e.changedTouches[0];
      const n = toNorm(t.clientX, t.clientY);
      if (inside(n)) { send({ t: "move", x: clamp01(n[0]), y: clamp01(n[1]) }); send({ t: "click", b: "right", n: 1 }); }
      setRight(false);
      for (const t2 of e.changedTouches) T.pts.delete(t2.identifier);
      return;
    }
    mouseEnd(e);
  }

  // Touch mode: every finger is a finger on the remote screen, after a short wait for a
  // second one (a two-finger tap right-clicks where the first finger is)
  function touchStartHeld(e, now) {
    const fresh = [...e.changedTouches];
    if (!T.remote.size && !T.wait && fresh.length === 1 && T.pts.size === 1) {
      T.moved = 0;
      const f = fresh[0];
      T.wait = { ids: [f.identifier], at: [f.clientX, f.clientY], t0: now, timer: setTimeout(flushWait, HOLDBACK_MS) };
      return;
    }
    if (T.wait && T.wait.ids.length === 1 && fresh.length === 1 && now - T.wait.t0 < HOLDBACK_MS) {
      clearTimeout(T.wait.timer);
      T.wait.ids.push(fresh[0].identifier);      // two fingers: a right-click if they lift soon
      T.wait.timer = setTimeout(flushWait, TAP_MS + 100);   // still down: they're fingers after all
      return;
    }
    if (T.wait) flushWait();
    touchModeSend(e.changedTouches, "d");
  }
  function pointOf(id) {
    const p = T.pts.get(id);
    return p ? { identifier: id, clientX: p.x, clientY: p.y } : null;
  }
  // the fingers that waited reach the computer: where they landed, then where they are
  function flushWait() {
    const w = T.wait;
    if (!w) return;
    clearTimeout(w.timer);
    T.wait = null;
    const down = [], now = [];
    for (const id of w.ids) {
      const p = T.pts.get(id);
      if (!p) continue;
      down.push({ identifier: id, clientX: p.x0, clientY: p.y0 });
      if (p.x !== p.x0 || p.y !== p.y0) now.push(pointOf(id));
    }
    if (down.length) touchModeSend(down, "d");
    if (now.length) touchModeSend(now, "m");
  }
  function touchEndHeld(e) {
    const w = T.wait;
    const ended = [...e.changedTouches].map((t) => ({ identifier: t.identifier, clientX: t.clientX, clientY: t.clientY }));
    if (w.ids.length > 1) {
      // fingers lift one touchend at a time: the first finger may be gone already
      for (const t of ended) T.pts.delete(t.identifier);
      if (T.pts.size) return;                    // wait for the last finger
      clearTimeout(w.timer);
      T.wait = null;
      const quick = performance.now() - w.t0 < TAP_MS + 100;
      if (quick && T.moved < TAP_PX * 2 && e.type !== "touchcancel") {
        const n = toNorm(w.at[0], w.at[1]);
        if (inside(n)) { send({ t: "move", x: clamp01(n[0]), y: clamp01(n[1]) }); send({ t: "click", b: "right", n: 1 }); }
      }
      return;
    }
    // one finger lifted before the wait was over: a whole tap, held like a finger holds it
    flushWait();
    if (e.type === "touchcancel") touchModeSend(ended, "c");
    else setTimeout(() => touchModeSend(ended, "u"), TAP_HOLD_MS);
    for (const t of ended) T.pts.delete(t.identifier);
  }

  function touchModeSend(list, phase) {
    const p = [];
    for (const t of list) {
      const n = toNorm(t.clientX, t.clientY);
      if (phase === "d") {
        if (!inside(n)) continue;               // letterbox: not on the picture
        T.remote.add(t.identifier);
      } else if (!T.remote.has(t.identifier)) continue;
      if (phase === "u" || phase === "c") T.remote.delete(t.identifier);
      p.push([t.identifier, phase, +clamp01(n[0]).toFixed(5), +clamp01(n[1]).toFixed(5)]);
    }
    if (p.length) send({ t: "touch", p });
  }

  // Mouse pointer mode: a trackpad
  function mouseStart(e, now) {
    const n = T.pts.size;
    T.maxPts = Math.max(T.maxPts, n);
    if (n === 1) {
      T.startT = now; T.moved = 0; T.maxPts = 1;
      // a second tap that stays down: drag (tap, then press and move)
      const p = [...T.pts.values()][0];
      if (now - T.lastTapEnd < DOUBLE_MS && T.lastTapPos && Math.hypot(p.x - T.lastTapPos[0], p.y - T.lastTapPos[1]) < 40) {
        T.gesture = "tapdrag";
      } else {
        T.gesture = "move";
        clearTimeout(T.holdTimer);
        T.holdTimer = setTimeout(() => {
          if (T.gesture === "move" && T.moved < TAP_PX && T.pts.size === 1) { T.gesture = "armed"; ring(true, p.x, p.y); }
        }, HOLD_MS);
      }
    } else if (n === 2) {
      clearTimeout(T.holdTimer); ring(false);
      if (T.gesture === "drag" || T.gesture === "tapdrag-down") { send({ t: "btn", b: "left", d: false }); }
      T.gesture = "two";
      const [a, b] = [...T.pts.values()];
      T.pinch0 = Math.hypot(a.x - b.x, a.y - b.y);
      T.mid0 = toView((a.x + b.x) / 2, (a.y + b.y) / 2);
      T.zoom0 = { ...S.zoom };
    } else {
      clearTimeout(T.holdTimer); ring(false);
      T.gesture = "three";
    }
  }

  function mouseMove(e, prev) {
    const now = performance.now();
    if (T.gesture === "move" || T.gesture === "drag" || T.gesture === "armed" || T.gesture === "tapdrag" || T.gesture === "tapdrag-down") {
      if (T.gesture === "armed") { T.gesture = "drag"; ring(false); send({ t: "btn", b: "left", d: true }); }
      if (T.gesture === "tapdrag") { T.gesture = "tapdrag-down"; send({ t: "btn", b: "left", d: true }); }
      const t = e.changedTouches[0];
      const pv = prev.get(t.identifier);
      if (!pv) return;
      const [dx, dy] = dView(t.clientX - pv.x, t.clientY - pv.y);
      if (T.gesture === "move" && T.moved < TAP_PX) return;   // still maybe a tap
      clearTimeout(T.holdTimer);
      const dt = Math.max(1, now - (T.lastMove || now - 16));
      T.lastMove = now;
      const speed = Math.hypot(dx, dy) / dt;                  // px per ms
      const gain = 1.1 + 1.6 * Math.min(1, speed / 1.2);      // pointer acceleration
      const b = contentBox();
      S.cursor.x = clamp01(S.cursor.x + dx * gain / b.w);
      S.cursor.y = clamp01(S.cursor.y + dy * gain / b.h);
      send({ t: "move", x: +S.cursor.x.toFixed(5), y: +S.cursor.y.toFixed(5) });
      followCursor();
      return;
    }
    if (T.gesture === "two" || T.gesture === "scroll" || T.gesture === "pinch") {
      const pts = [...T.pts.values()];
      if (pts.length < 2) return;
      const [a, b] = pts;
      const dist = Math.hypot(a.x - b.x, a.y - b.y);
      const mid = toView((a.x + b.x) / 2, (a.y + b.y) / 2);
      if (T.gesture === "two") {
        const dz = Math.abs(dist - T.pinch0), dm = Math.hypot(mid[0] - T.mid0[0], mid[1] - T.mid0[1]);
        if (dz > 24 && dz > dm) T.gesture = "pinch";
        else if (dm > 8) { T.gesture = "scroll"; T.lastMid = T.mid0; }
        else return;
      }
      if (T.gesture === "pinch") {
        const z0 = T.zoom0, nz = Math.max(1, Math.min(4, z0.z * dist / T.pinch0));
        // zoom about the first midpoint and follow the fingers
        S.zoom.z = nz;
        S.zoom.tx = mid[0] - (T.mid0[0] - z0.tx) * (nz / z0.z);
        S.zoom.ty = mid[1] - (T.mid0[1] - z0.ty) * (nz / z0.z);
        applyZoom();
      } else {
        const dx = mid[0] - T.lastMid[0], dy = mid[1] - T.lastMid[1];
        T.lastMid = mid;
        // natural scrolling: the content follows the fingers
        if (dx || dy) send({ t: "scroll", dx: +(-dx).toFixed(1), dy: +(-dy).toFixed(1) });
      }
    }
  }

  function mouseEnd(e) {
    const now = performance.now();
    for (const t of e.changedTouches) T.pts.delete(t.identifier);
    if (T.pts.size) return;                       // wait for the last finger
    clearTimeout(T.holdTimer);
    const quick = now - T.startT < TAP_MS + (T.maxPts > 1 ? 100 : 0);
    const g = T.gesture;
    T.gesture = null; T.lastMove = 0;
    ring(false);
    if (g === "drag" || g === "tapdrag-down") { if (!S.dragLock) send({ t: "btn", b: "left", d: false }); }
    else if (g === "armed") send({ t: "click", b: "right", n: 1 });          // press and hold, no drag
    else if (g === "tapdrag") send({ t: "click", b: "left", n: 1 });          // the second tap of a double tap
    else if (g === "two" && quick && T.moved < TAP_PX * 2) send({ t: "click", b: "right", n: 1 });
    else if (g === "three" && quick) toggleKeyboard();
    else if (g === "move" && quick && T.moved < TAP_PX) {
      if (S.rightArmed) { send({ t: "click", b: "right", n: 1 }); setRight(false); }
      else send({ t: "click", b: "left", n: 1 });
      T.lastTapEnd = now;
      T.lastTapPos = [e.changedTouches[0].clientX, e.changedTouches[0].clientY];
      return;
    }
    T.lastTapEnd = 0; T.maxPts = 0; T.moved = 0;
  }

  function ring(on, x, y) {
    const r = $("ring");
    if (on) { const [vx, vy] = toView(x, y); r.style.left = vx + "px"; r.style.top = vy + "px"; }
    r.classList.toggle("on", !!on);
  }

  // a mouse or a trackpad on an iPad or a computer: straight through
  surface.addEventListener("pointerdown", (e) => { if (e.pointerType !== "mouse") return; mouseAbs(e); send({ t: "btn", b: ["left", "middle", "right"][e.button] || "left", d: true }); });
  surface.addEventListener("pointermove", (e) => { if (e.pointerType === "mouse") mouseAbs(e); });
  surface.addEventListener("pointerup", (e) => { if (e.pointerType !== "mouse") return; send({ t: "btn", b: ["left", "middle", "right"][e.button] || "left", d: false }); });
  surface.addEventListener("contextmenu", (e) => e.preventDefault());
  surface.addEventListener("wheel", (e) => { e.preventDefault(); const [dx, dy] = dView(e.deltaX, e.deltaY); send({ t: "scroll", dx, dy }); }, { passive: false });
  function mouseAbs(e) {
    const n = toNorm(e.clientX, e.clientY);
    if (!inside(n)) return;
    S.cursor.x = n[0]; S.cursor.y = n[1];
    send({ t: "move", x: +n[0].toFixed(5), y: +n[1].toFixed(5) });
  }

  // ------------------------------------------------------------------ keyboard
  const kbd = $("kbd");
  const CHAR_CODE = {};
  "abcdefghijklmnopqrstuvwxyz".split("").forEach((c) => { CHAR_CODE[c] = "Key" + c.toUpperCase(); });
  "0123456789".split("").forEach((c) => { CHAR_CODE[c] = "Digit" + c; });
  Object.assign(CHAR_CODE, { " ": "Space", "-": "Minus", "=": "Equal", "[": "BracketLeft", "]": "BracketRight", ";": "Semicolon",
    "'": "Quote", "`": "Backquote", "\\": "Backslash", ",": "Comma", ".": "Period", "/": "Slash" });

  function activeMods() { return Object.keys(S.mods).filter((m) => S.mods[m]); }
  function consumeMods() {
    let changed = false;
    for (const m of Object.keys(S.mods)) if (S.mods[m] === "once") { delete S.mods[m]; changed = true; }
    if (changed) paintMods();
  }
  function paintMods() {
    document.querySelectorAll("[data-mod]").forEach((b) => {
      const st = S.mods[b.dataset.mod];
      b.setAttribute("aria-pressed", st ? "true" : "false");
      b.dataset.locked = st === "lock" ? "true" : "false";
    });
  }
  // typing, keys and the clipboard need full control; a phone paired at "point and tap"
  // would otherwise open its keyboard and type into nothing (the computer drops the keys)
  function needFullToType() {
    if (S.control === "full") return true;
    if (kbdOpen()) kbd.blur();
    toast("Typing needs full control: tap More, then Full control, and allow it at the computer.");
    return false;
  }
  function sendKey(code) {
    if (!needFullToType()) return;
    send({ t: "combo", m: activeMods(), c: code });
    consumeMods();
  }
  function kbdOpen() { return document.activeElement === kbd; }
  function toggleKeyboard() {
    if (kbdOpen()) { kbd.blur(); return; }
    if (!needFullToType()) return;
    kbd.value = " ";                              // a character to delete, so Backspace always fires
    kbd.focus();                                  // must run inside the tap for iOS to show the keyboard
    kbd.setSelectionRange(1, 1);
  }
  kbd.addEventListener("focus", () => { press($("btn-keyboard"), true); $("keys").hidden = false; press($("btn-keys"), true); });
  kbd.addEventListener("blur", () => { press($("btn-keyboard"), false); if (!S.keysPinned) { $("keys").hidden = true; press($("btn-keys"), false); } });
  kbd.addEventListener("beforeinput", (e) => {
    e.preventDefault();
    const ty = e.inputType;
    if (ty === "insertText" || ty === "insertReplacementText" || ty === "insertCompositionText") {
      const s = e.data || (e.dataTransfer && e.dataTransfer.getData("text/plain")) || "";
      if (!s || !needFullToType()) return;
      const mods = activeMods();
      if (mods.length && s.length === 1 && CHAR_CODE[s.toLowerCase()]) {
        if (s !== s.toLowerCase() && !mods.includes("shift")) mods.push("shift");
        send({ t: "combo", m: mods, c: CHAR_CODE[s.toLowerCase()] });
        consumeMods();
      } else {
        send({ t: "text", s });
        consumeMods();
      }
    } else if (ty === "deleteContentBackward" || ty === "deleteWordBackward") sendKey("Backspace");
    else if (ty === "deleteContentForward") sendKey("Delete");
    else if (ty === "insertLineBreak" || ty === "insertParagraph") sendKey("Enter");
    kbd.value = " "; kbd.setSelectionRange(1, 1);
  });
  // a hardware keyboard (iPad, Bluetooth): keys that aren't plain text go straight through
  const HELD = new Set();
  kbd.addEventListener("keydown", (e) => {
    const plain = e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey;
    if (plain || e.key === "Unidentified" || e.isComposing) return;   // text comes through beforeinput
    if (["Backspace", "Enter"].includes(e.code) && !e.ctrlKey && !e.metaKey && !e.altKey && !activeMods().length) return;
    if (e.metaKey && !e.ctrlKey && !e.altKey && e.code === "KeyV") return;        // the paste event below
    if (e.metaKey && !e.ctrlKey && !e.altKey && e.code === "KeyC") { e.preventDefault(); copyFromPC(); return; }
    e.preventDefault();
    if (!e.code || !needFullToType()) return;
    HELD.add(e.code);
    send({ t: "key", c: e.code, d: true });
  });
  kbd.addEventListener("keyup", (e) => {
    if (!HELD.has(e.code)) return;
    e.preventDefault();
    HELD.delete(e.code);
    send({ t: "key", c: e.code, d: false });
  });

  // the key row
  let lastModTap = { name: "", t: 0 };
  document.querySelectorAll("#keys button").forEach((b) => {
    // keep the soft keyboard up while tapping the row
    b.addEventListener("pointerdown", (e) => e.preventDefault());
    b.addEventListener("mousedown", (e) => e.preventDefault());
  });
  document.querySelectorAll("[data-mod]").forEach((b) => b.addEventListener("click", () => {
    const m = b.dataset.mod, now = performance.now();
    if (S.mods[m] === "lock") delete S.mods[m];
    else if (S.mods[m] === "once" && lastModTap.name === m && now - lastModTap.t < 400) S.mods[m] = "lock";
    else if (S.mods[m] === "once") delete S.mods[m];
    else S.mods[m] = "once";
    lastModTap = { name: m, t: now };
    paintMods();
  }));
  document.querySelectorAll("[data-key]").forEach((b) => b.addEventListener("click", () => sendKey(b.dataset.key)));
  $("btn-fn").addEventListener("click", () => { const row = $("keyrow-fn"); row.hidden = !row.hidden; press($("btn-fn"), !row.hidden); });

  // lift the key row and the bar above the soft keyboard
  function onViewport() {
    const vv = window.visualViewport;
    const kb = vv ? Math.max(0, window.innerHeight - vv.height - vv.offsetTop) : 0;
    document.documentElement.style.setProperty("--kb", Math.round(kb) + "px");
    placeBar();                                  // the button stays above the keyboard
  }
  if (window.visualViewport) { visualViewport.addEventListener("resize", onViewport); visualViewport.addEventListener("scroll", onViewport); }

  // ------------------------------------------------------------------ the bar
  function press(btn, on) { if (btn) btn.setAttribute("aria-pressed", on ? "true" : "false"); }
  function applyMode() {
    document.querySelectorAll("[data-mode]").forEach((b) => b.setAttribute("aria-checked", b.dataset.mode === S.mode ? "true" : "false"));
    surface.dataset.mode = S.mode;
  }
  function setMode(m) {
    if (m === S.mode) return;
    // let go of whatever the other mode held
    if (T.remote.size) { touchModeSend([...T.remote].map((id) => ({ identifier: id, clientX: 0, clientY: 0 })), "c"); }
    S.mode = m; store.set("mode", m);
    if (T.wait) { clearTimeout(T.wait.timer); T.wait = null; }
    T.pts.clear(); T.gesture = null;
    applyMode();
    toast(m === "touch" ? "Touch: your finger is the finger." : "Mouse pointer: drag to move, tap to click.");
  }
  document.querySelectorAll("[data-mode]").forEach((b) => b.addEventListener("click", () => setMode(b.dataset.mode)));
  function setRight(on) { S.rightArmed = on; press($("btn-right"), on); }
  $("btn-right").addEventListener("click", () => {
    if (S.mode === "mouse") { send({ t: "click", b: "right", n: 1 }); return; }
    setRight(!S.rightArmed);
    if (S.rightArmed) toast("Tap where you want to right-click.");
  });
  $("btn-keyboard").addEventListener("pointerdown", (e) => e.preventDefault());
  $("btn-keyboard").addEventListener("click", toggleKeyboard);
  $("btn-zoom").addEventListener("click", () => {
    if (S.zoom.z > 1) { S.zoom.z = 1; applyZoom(); return; }
    const b = contentBox();
    const tap = T.lastTapPos ? toView(T.lastTapPos[0], T.lastTapPos[1]) : [viewW() / 2, viewH() / 2];
    const cx = S.mode === "mouse" ? b.x + S.cursor.x * b.w : tap[0];
    const cy = S.mode === "mouse" ? b.y + S.cursor.y * b.h : tap[1];
    zoomAt(cx, cy, 2);
  });
  $("btn-more").addEventListener("click", () => {
    const sh = $("sheet");
    sh.hidden = !sh.hidden;
    $("btn-more").setAttribute("aria-expanded", sh.hidden ? "false" : "true");
    if (!sh.hidden) sh.querySelector("button").focus({ preventScroll: true });
  });
  // Turn: upright, its top to the left, its top to the right, upright again
  const TURNS = { 0: 270, 270: 90, 90: 0 };
  $("btn-rotate").addEventListener("click", () => {
    S.rot = TURNS[S.rot]; store.set("rotate", S.rot);
    S.zoom.z = 1;
    applyRotate(); applyZoom();
    if (window.innerWidth > window.innerHeight) toast("Turning works while the phone shows portrait.");
    else toast(S.rot === 270 ? "Turned: hold the phone with its left side up." : S.rot === 90 ? "Turned the other way: right side up." : "Upright again.");
    sendSize();
  });

  // ------------------------------------------------------------------ the floating button
  // k-hole's mark on glass at a side of the screen (K, update ten: the bar at the top covered
  // the desktop's own header; update eighteen: AssistiveTouch was the idea, not the look).
  // Drag it anywhere; let go and it settles on the nearer side, where it stays (stored). A tap
  // opens the tools beside it, toward the middle: the glass unfurls, the ring's light runs
  // round once and the tools rise in one after another; picking a tool, a tap on the picture
  // or the mark again closes them. Untouched for a few seconds it steps back. Everything in
  // the view's own frame, so it works on a turned picture too.
  const FAB = { side: store.get("fab-side", "right") === "left" ? "left" : "right",
                y: Math.min(1, Math.max(0, Number(store.get("fab-y", 0.62)) || 0.62)),
                open: false, drag: null, moved: false, idleTimer: 0 };
  const FAB_MARGIN = 8, FAB_SLOP = 8, FAB_IDLE_MS = 3000;
  function insets() {
    const c = getComputedStyle($("safe-probe"));
    const v = (k) => parseFloat(c[k]) || 0;
    const t = v("paddingTop"), r = v("paddingRight"), b = v("paddingBottom"), l = v("paddingLeft");
    const kb = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--kb")) || 0;
    // the frame already starts below the top inset
    const top = Math.max(0, t - frame().y);
    if (rotNow()) { const m = Math.max(top, r, b, l); return { t: m, r: m, b: m, l: m }; }
    return { t: top, r, b: b + kb, l };
  }
  // where the bar's box may go: the view less the margins and the phone's own edges
  function fabRoom(w, h) {
    const i = insets(), W = viewW(), H = viewH();
    return { x0: FAB_MARGIN + i.l, x1: Math.max(FAB_MARGIN + i.l, W - FAB_MARGIN - i.r - w),
             y0: FAB_MARGIN + i.t, y1: Math.max(FAB_MARGIN + i.t, H - FAB_MARGIN - i.b - h) };
  }
  function placeBar() {
    const bar = $("bar");
    bar.dataset.side = FAB.side;
    if (FAB.drag) return;
    bar.style.left = "0px";        // measure at full width: an absolute box shrinks to the room right of it
    const w = bar.offsetWidth, h = bar.offsetHeight, room = fabRoom(w, h);
    const x = FAB.side === "left" ? room.x0 : room.x1;
    const y = room.y0 + FAB.y * (room.y1 - room.y0);
    bar.style.left = Math.round(x) + "px"; bar.style.top = Math.round(y) + "px";
    // More opens on the half away from the button
    $("sheet").classList.toggle("bottom", y + h / 2 > viewH() / 2);
  }
  function applyEdge() { placeBar(); }
  function fabIdle() {
    clearTimeout(FAB.idleTimer);
    $("bar").classList.remove("idle");
    if (!FAB.open) FAB.idleTimer = setTimeout(() => { if (!FAB.open && !FAB.drag) $("bar").classList.add("idle"); }, FAB_IDLE_MS);
  }
  function setBarOpen(open) {
    FAB.open = !!open;
    const bar = $("bar"), h = $("bar-handle");
    bar.classList.toggle("collapsed", !FAB.open);
    h.setAttribute("aria-expanded", FAB.open ? "true" : "false");
    h.setAttribute("aria-label", FAB.open ? "Hide controls" : "Show controls");
    if (FAB.open) {
      [...$("bar-tools").children].forEach((el, i) => el.style.setProperty("--i", String(i)));
      runLight();
    }
    placeBar(); fabIdle();
  }
  // the light on the mark's ring goes round once (the ring's own ellipse), then rests in front
  const still = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  function runLight() {
    const light = $("bar-light");
    if (!light || still.matches || !window.requestAnimationFrame) return;
    cancelAnimationFrame(FAB.lightFrame || 0);
    const t0 = performance.now(), ms = 620;
    const step = (t) => {
      const k = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - k, 3);
      const a = Math.PI / 2 + e * 2 * Math.PI;      // from the front, all the way round
      light.setAttribute("cx", (24 + 17.5 * Math.cos(a)).toFixed(2));
      light.setAttribute("cy", (24 + 4.9 * Math.sin(a)).toFixed(2));
      // behind the hole on the far half
      light.style.opacity = Math.sin(a) < 0 && Math.abs(Math.cos(a)) < 0.47 ? "0" : "1";
      FAB.lightFrame = k < 1 ? requestAnimationFrame(step) : 0;
    };
    FAB.lightFrame = requestAnimationFrame(step);
  }
  const handle = $("bar-handle");
  handle.addEventListener("pointerdown", (e) => {
    const bar = $("bar");
    FAB.drag = { id: e.pointerId, x0: e.clientX, y0: e.clientY, left: bar.offsetLeft, top: bar.offsetTop };
    FAB.moved = false;
    handle.setPointerCapture(e.pointerId);
    fabIdle();
  });
  handle.addEventListener("pointermove", (e) => {
    const d = FAB.drag;
    if (!d || d.id !== e.pointerId) return;
    const [dx, dy] = dView(e.clientX - d.x0, e.clientY - d.y0);
    if (!FAB.moved && Math.hypot(dx, dy) < FAB_SLOP) return;
    if (!FAB.moved) { FAB.moved = true; $("bar").classList.add("dragging"); }
    e.preventDefault();
    const bar = $("bar"), room = fabRoom(bar.offsetWidth, bar.offsetHeight);
    // a little past the margins while carried, the way a finger expects
    bar.style.left = Math.round(Math.min(room.x1 + FAB_MARGIN, Math.max(room.x0 - FAB_MARGIN, d.left + dx))) + "px";
    bar.style.top = Math.round(Math.min(room.y1, Math.max(room.y0, d.top + dy))) + "px";
  });
  function fabRelease(e) {
    const d = FAB.drag;
    if (!d || d.id !== e.pointerId) return;
    FAB.drag = null;
    $("bar").classList.remove("dragging");
    if (!FAB.moved) return;                      // a tap: the click below
    const bar = $("bar"), room = fabRoom(bar.offsetWidth, bar.offsetHeight);
    const mid = bar.offsetLeft + bar.offsetWidth / 2;
    FAB.side = mid < viewW() / 2 ? "left" : "right";
    FAB.y = room.y1 > room.y0 ? Math.min(1, Math.max(0, (bar.offsetTop - room.y0) / (room.y1 - room.y0))) : 0;
    store.set("fab-side", FAB.side); store.set("fab-y", Math.round(FAB.y * 1000) / 1000);
    placeBar(); fabIdle();
  }
  handle.addEventListener("pointerup", fabRelease);
  handle.addEventListener("pointercancel", fabRelease);
  handle.addEventListener("click", (e) => {
    if (FAB.moved) { FAB.moved = false; e.preventDefault(); return; }   // the end of a drag
    setBarOpen(!FAB.open);
    if (!FAB.open) closeSheets();
  });
  // picking a tool closes them, as AssistiveTouch does (More's sheet stays up on its own)
  $("bar-tools").addEventListener("click", (e) => {
    if (e.target.closest("button")) setBarOpen(false);   // the tool's own handler already ran
  });
  window.kholeBar = { open: () => setBarOpen(true), close: () => setBarOpen(false), state: () => ({ ...FAB, drag: !!FAB.drag }) };

  const shortcut = (k) => () => { send({ t: "shortcut", k }); closeSheets(); };
  $("btn-home").addEventListener("click", shortcut("home"));
  $("btn-search").addEventListener("click", shortcut("search"));
  $("btn-spaces").addEventListener("click", shortcut("spaces"));
  $("btn-drag").addEventListener("click", () => {
    S.dragLock = !S.dragLock;
    press($("btn-drag"), S.dragLock);
    send({ t: "btn", b: "left", d: S.dragLock });
    toast(S.dragLock ? "The left button is held: move, then tap Drag lock again." : "Released.");
  });
  $("btn-keys").addEventListener("click", () => {
    const k = $("keys");
    k.hidden = !k.hidden;
    S.keysPinned = !k.hidden;
    press($("btn-keys"), !k.hidden);
    closeSheets();
  });
  $("btn-sound").addEventListener("click", () => {
    S.sound = !S.sound; store.set("sound", S.sound);
    const a = $("audio"); a.muted = !S.sound; if (S.sound) a.play().catch(() => {});
    press($("btn-sound"), S.sound);
  });
  press($("btn-sound"), S.sound);
  $("btn-disconnect").addEventListener("click", () => { closeSheets(); disconnect(); });
  // a screen of its own for this phone, or the computer's own: the next session decides
  $("btn-screen").addEventListener("click", () => {
    S.screen = S.screen === "phone" ? "computer" : "phone"; store.set("screen", S.screen);
    press($("btn-screen"), S.screen === "phone");
    closeSheets();
    if (S.want) reconnect(S.screen === "phone" ? "Making a screen shaped like this phone…" : "Showing the computer's screen…");
  });

  // clipboard, both ways. Safari lets a tap read (it shows a Paste button) and write
  // with a promise. Paste on PC: this phone's clipboard becomes the computer's, then the
  // focused app's own paste key (Ctrl+Shift+V in a terminal). Type on PC: the words typed
  // out, for a field that refuses a paste (a password prompt, a VM). Copy from PC: the
  // focused app's own copy key first, so what's selected there lands here.
  const clipWaiters = new Map();
  let clipN = 0;
  const TYPE_MAX = 4096;
  async function readPhoneClip() {
    try { return await navigator.clipboard.readText(); } catch (_) { toast("This phone's clipboard wasn't readable."); return ""; }
  }
  function pasteOnPC(s) {
    if (!needFullToType()) return;
    if (!s) { toast("This phone's clipboard is empty."); return; }
    send({ t: "clip", s, paste: true });
    toast("Pasted on the computer.");
  }
  function typeOnPC(s) {
    if (!needFullToType()) return;
    if (!s) { toast("This phone's clipboard is empty."); return; }
    if (s.length > TYPE_MAX) { toast("Too long to type: use Paste on PC."); return; }
    send({ t: "text", s });
    toast("Typed on the computer.");
  }
  function copyFromPC() {
    if (!needFullToType()) return;
    const n = ++clipN;
    const answer = new Promise((res) => { clipWaiters.set(n, res); setTimeout(() => { if (clipWaiters.delete(n)) res(null); }, 4000); });
    send({ t: "clipget", n, copy: true });
    const text = answer.then((m) => {
      if (!m || !m.s) throw new Error(m ? "empty" : "timeout");
      return m;
    });
    const done = (m) => toast(m.cut ? "Copied the start: it was too long for one go." :
      m.src === "selection" ? "Copied what's highlighted on the computer." : "Copied from the computer.");
    const failed = (e) => toast(e && e.message === "empty" ? "Nothing is selected or copied on the computer." :
      e && e.message === "timeout" ? "The computer didn't answer." : "Couldn't write this phone's clipboard.");
    try {
      if (window.ClipboardItem && navigator.clipboard.write) {
        // the item is made inside the tap, its text arrives later (Safari keeps the permission)
        const item = new ClipboardItem({ "text/plain": text.then((m) => new Blob([m.s], { type: "text/plain" })) });
        navigator.clipboard.write([item]).then(() => text.then(done), () => text.then((m) =>
          navigator.clipboard.writeText(m.s).then(() => done(m))).catch(failed));
      } else text.then((m) => navigator.clipboard.writeText(m.s).then(() => done(m))).catch(failed);
    } catch (_) { text.then(() => toast("Couldn't write this phone's clipboard."), failed); }
  }
  $("btn-ask-full").addEventListener("click", async () => {
    closeSheets();
    try {
      await api("/api/ask-control", { level: "full" });
      toast("Asked: allow it at the computer. Typing works once it says yes.");
    } catch (e) { toast(e.message); }
  });
  $("btn-clip-send").addEventListener("click", async () => { closeSheets(); if (!needFullToType()) return; pasteOnPC(await readPhoneClip()); });
  $("btn-clip-type").addEventListener("click", async () => { closeSheets(); if (!needFullToType()) return; typeOnPC(await readPhoneClip()); });
  $("btn-clip-get").addEventListener("click", () => { closeSheets(); copyFromPC(); });
  document.querySelectorAll("[data-clip]").forEach((b) => b.addEventListener("click", async () => {
    if (b.dataset.clip === "copy") copyFromPC();
    else if (needFullToType()) pasteOnPC(await readPhoneClip());
  }));
  // a hardware keyboard's Cmd+V and the soft keyboard's Paste: this phone's clipboard
  // comes with the event (no prompt); Cmd+C copies what's selected on the computer
  kbd.addEventListener("paste", (e) => {
    e.preventDefault();
    pasteOnPC((e.clipboardData && e.clipboardData.getData("text/plain")) || "");
    kbd.value = " "; kbd.setSelectionRange(1, 1);
  });

  // files, both ways (full control): Send file uploads into the computer's Downloads;
  // Get file lists what's copied in Files there and the newest files, a tap fetches one,
  // a second tap saves it (Safari's share sheet needs a fresh tap after the download)
  function fileSize(n) {
    if (n < 1000) return n + " bytes";
    const u = ["KB", "MB", "GB"];
    let i = -1;
    do { n /= 1000; i++; } while (n >= 1000 && i < 2);
    return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + " " + u[i];
  }
  function needFull() {
    if (S.control === "full") return true;
    toast("Files need full control: tap More, then Full control, and allow it at the computer.");
    return false;
  }
  $("btn-file-send").addEventListener("click", () => { if (needFull()) $("file-pick").click(); });
  $("file-pick").addEventListener("change", async () => {
    const list = [...$("file-pick").files];
    $("file-pick").value = "";
    for (const f of list) {
      try {
        const j = await upload(f, (p) => toast(`Sending ${f.name}: ${p}%`));
        toast(`Sent ${j.name} to ${j.folder}.`);
      } catch (e) { toast(`${f.name}: ${e.message}`); return; }
    }
  });
  function upload(f, progress) {
    return new Promise((res, rej) => {
      const x = new XMLHttpRequest();
      x.open("POST", "/api/files?name=" + encodeURIComponent(f.name));
      x.setRequestHeader("Authorization", "Bearer " + S.token);
      x.setRequestHeader("Content-Type", "application/octet-stream");
      let last = -1;
      x.upload.onprogress = (e) => {
        if (!e.lengthComputable) return;
        const p = Math.floor(e.loaded * 100 / e.total);
        if (p >= last + 10) { last = p; progress(p); }
      };
      x.onload = () => {
        let j = {};
        try { j = JSON.parse(x.responseText); } catch (_) { /* empty */ }
        if (x.status >= 200 && x.status < 300) res(j); else rej(new Error(j.error || ("HTTP " + x.status)));
      };
      x.onerror = () => rej(new Error("the computer didn't answer."));
      x.send(f);
    });
  }
  $("btn-file-get").addEventListener("click", () => {
    const box = $("files");
    box.hidden = !box.hidden;
    $("btn-file-get").setAttribute("aria-expanded", box.hidden ? "false" : "true");
    if (!box.hidden) listFiles();
  });
  async function listFiles() {
    const st = $("files-status"), ul = $("files-list");
    ul.textContent = "";
    if (S.control !== "full") { st.textContent = "Files need full control."; return; }
    st.textContent = "Looking…";
    let j;
    try { j = await api("/api/files"); } catch (e) { st.textContent = e.message; return; }
    const files = j.files || [];
    st.textContent = files.length ? "" : "Nothing copied, and nothing new in Downloads, the desktop, Screenshots or Recordings.";
    for (const f of files) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "file"; b.setAttribute("role", "listitem");
      const name = document.createElement("span"); name.textContent = f.name;
      const meta = document.createElement("span"); meta.className = "meta";
      meta.textContent = fileSize(f.size) + " · " + (f.from === "copied" ? "copied" : f.folder);
      b.append(name, meta);
      b.setAttribute("aria-label", `${f.name}, ${fileSize(f.size)}, ${f.from === "copied" ? "copied on the computer" : "in " + f.folder}`);
      if (f.too_big) { b.disabled = true; meta.textContent = fileSize(f.size) + " · too big"; }
      b.addEventListener("click", () => takeFile(f, b, name));
      ul.append(b);
    }
  }
  async function takeFile(f, b, label) {
    if (b._file) return saveFile(b._file);
    b.disabled = true;
    label.textContent = "Getting " + f.name + "…";
    try {
      const r = await fetch("/api/files/" + encodeURIComponent(f.id), { headers: { Authorization: "Bearer " + S.token }, cache: "no-store" });
      if (!r.ok) { let j = {}; try { j = await r.json(); } catch (_) { /* empty */ } throw new Error(j.error || ("HTTP " + r.status)); }
      const blob = await r.blob();
      b._file = new File([blob], f.name, { type: blob.type || "application/octet-stream" });
      label.textContent = "Save " + f.name;
      b.dataset.ready = "true";
      b.setAttribute("aria-label", "Save " + f.name);
      toast("Ready: tap it again to save.");
    } catch (e) {
      label.textContent = f.name;
      toast(e.message);
    } finally { b.disabled = false; }
  }
  function saveFile(file) {
    if (navigator.canShare && navigator.share && navigator.canShare({ files: [file] })) {
      navigator.share({ files: [file] }).catch((e) => { if (e && e.name !== "AbortError") download(file); });
      return;
    }
    download(file);
  }
  function download(file) {
    const url = URL.createObjectURL(file);
    const a = document.createElement("a");
    a.href = url; a.download = file.name; a.hidden = true;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  }

  // quality
  function paintQuality() {
    document.querySelectorAll("[data-q]").forEach((b) => b.setAttribute("aria-checked", String(S.q[b.dataset.q]) === b.dataset.v ? "true" : "false"));
  }
  document.querySelectorAll("[data-q]").forEach((b) => b.addEventListener("click", () => {
    const k = b.dataset.q, v = b.dataset.v;
    S.q[k] = k === "fps" ? +v : k === "kbps" && v !== "auto" ? +v : v;
    store.set("quality", S.q);
    paintQuality();
    const msg = { t: "quality" };
    if (k === "fps") msg.fps = S.q.fps;
    if (k === "res") msg.res = S.q.res;
    if (k === "kbps") msg.kbps = v === "auto" ? S.kbps : S.q.kbps;
    send(msg);
  }));
  $("btn-quality").addEventListener("click", () => {
    const q = $("quality"); q.hidden = !q.hidden;
    $("btn-quality").setAttribute("aria-expanded", q.hidden ? "false" : "true");
  });
  paintQuality();

  // ------------------------------------------------------------------ stats, auto bitrate
  // The numbers are read once a second for the whole session (auto bitrate and the
  // stuck-decoder check need them); the Stats button only shows them.
  $("btn-stats").addEventListener("click", () => {
    S.statsOn = !S.statsOn; press($("btn-stats"), S.statsOn);
    $("stats").hidden = !S.statsOn;
    if (S.statsOn && S.pc && !S.statsTimer) startStats();
  });
  function startStats() {
    stopStats();
    $("stats").hidden = !S.statsOn;
    S.lastStats = null; S.lastPicture = performance.now(); S.server = null;
    S.statsTimer = setInterval(pollStats, 1000);
    S.autoTimer = setInterval(autoBitrate, 2000);
  }
  function stopStats() { clearInterval(S.statsTimer); clearInterval(S.autoTimer); S.statsTimer = 0; S.autoTimer = 0; }
  let pingN = 0;
  async function pollStats() {
    if (!S.pc) return;
    const n = ++pingN; S.pingSent.set(n, performance.now()); send({ t: "ping", n });
    const st = await S.pc.getStats();
    let v = null, pair = null;
    st.forEach((r) => {
      if (r.type === "inbound-rtp" && r.kind === "video") v = r;
      if (r.type === "candidate-pair" && (r.nominated || r.selected) && r.state === "succeeded") pair = r;
    });
    if (!v) return;
    const now = performance.now(), last = S.lastStats;
    S.lastStats = { t: now, frames: v.framesDecoded || 0, recvd: v.framesReceived || 0, bytes: v.bytesReceived || 0,
      lost: v.packetsLost || 0, recv: v.packetsReceived || 0,
      jbd: v.jitterBufferDelay || 0, jbe: v.jitterBufferEmittedCount || 0, dec: v.totalDecodeTime || 0 };
    if (!last) return;
    const cur = S.lastStats;
    const dt = (now - last.t) / 1000;
    const fps = (cur.frames - last.frames) / dt;
    const rfps = (cur.recvd - last.recvd) / dt;
    const mbps = (cur.bytes - last.bytes) * 8 / dt / 1e6;
    const lost = cur.lost - last.lost, recv = cur.recv - last.recv;
    const loss = recv + lost > 0 ? 100 * lost / (recv + lost) : 0;
    const jb = cur.jbe > last.jbe ? 1000 * (cur.jbd - last.jbd) / (cur.jbe - last.jbe) : 0;
    const dec = cur.frames > last.frames ? 1000 * (cur.dec - last.dec) / (cur.frames - last.frames) : 0;
    const rtt = pair && pair.currentRoundTripTime ? pair.currentRoundTripTime * 1000 : 0;
    if (cur.frames > last.frames) S.lastPicture = now;
    // data arrives but nothing decodes: the decoder lost a packet and waits for a
    // keyframe; ask the computer for one (at most one a second)
    else if (cur.bytes > last.bytes && now - S.lastAsk > 1000) { S.lastAsk = now; S.asks++; send({ t: "keyframe" }); }
    const stuck = (now - S.lastPicture) / 1000;
    S.metrics = { fps, mbps, loss, jb, dec, rtt, input: S.inputRtt, stuck };
    // a still screen still gets a picture a second: none for 6 s while the phone is in
    // use means the stream is gone, whatever the connection says
    if (stuck >= 6 && document.visibilityState === "visible" && now - S.shownAt > 4000 && now - S.lastFix > 15000) {
      reconnect("The picture stopped: reconnecting…");
      return;
    }
    if (!S.statsOn) return;
    const vid = $("video"), pc = S.server;
    const lines = [
      `${vid.videoWidth}×${vid.videoHeight}  ${fps.toFixed(0)} fps (${rfps.toFixed(0)} in)`,
      `${mbps < 1 ? (mbps * 1000).toFixed(0) + " kbit/s" : mbps.toFixed(1) + " Mbit/s"}  loss ${loss.toFixed(1)} %`,
      `rtt ${rtt.toFixed(0)} ms  input ${S.inputRtt.toFixed(0)} ms`,
      `buffer ${jb.toFixed(0)} ms  decode ${dec.toFixed(1)} ms`,
      `keyframes ${v.keyFramesDecoded || 0}  pli ${v.pliCount || 0}  asked ${S.asks}`,
    ];
    // the computer's side: frames from the screen and from the encoder (per second)
    if (pc) lines.push(`pc ${Math.round(pc.in)} new + ${Math.round(pc.repeat)} repeat, ${Math.round(pc.enc)} enc` +
      (S.encoder ? `  ${S.encoder}` : "") +
      // a still screen costs bytes only when something changes: say what it costs now
      (pc.still ? `\nstill: ${Math.round(pc.kbps || 0)} kbit/s (${pc.idle.toFixed(0)} s)`
                : pc.idle >= 1 ? `\nscreen still ${pc.idle.toFixed(0)} s` : ""));
    if (stuck >= 2) lines.push(`no new picture for ${stuck.toFixed(0)} s`);
    if (S.q.kbps === "auto") lines.push(`auto ${(S.kbps / 1000).toFixed(1)} Mbit/s`);
    $("stats").textContent = lines.join("\n");
  }
  let lossHist = [];
  async function autoBitrate() {
    if (!S.pc || S.q.kbps !== "auto") return;
    const m = S.metrics;
    if (!m) return;
    lossHist = lossHist.concat([m.loss]).slice(-3);
    const worst = Math.max(...lossHist);
    let next = S.kbps;
    if (m.loss > 2 || m.jb > 80) next = Math.max(2000, Math.round(S.kbps * 0.75));
    else if (worst < 0.5 && m.jb < 40) next = Math.min(40000, Math.round(S.kbps * 1.1));
    if (Math.abs(next - S.kbps) >= 250) { S.kbps = next; send({ t: "quality", kbps: next }); }
  }

  // ------------------------------------------------------------------ toast, resize
  let toastTimer = 0;
  function toast(text) {
    const el = $("toast");
    el.textContent = text; el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 2200);
  }
  let resizeTimer = 0, lastSize = viewportPx();
  // a turn of the picture: the phone screen on the computer takes the new shape
  function sendSize() {
    const [w, h] = viewportPx();
    if (w === lastSize[0] && h === lastSize[1]) return;
    lastSize = [w, h];
    send({ t: "resize", w, h });
  }
  window.addEventListener("resize", () => {
    onViewport();
    applyRotate();
    applyZoom();
    clearTimeout(resizeTimer);
    // turning the phone: the phone screen on the computer turns with it (a keyboard
    // that shrinks the window doesn't count)
    resizeTimer = setTimeout(() => {
      const [w, h] = viewportPx();
      const turned = (w > h) !== (lastSize[0] > lastSize[1]);
      if (!turned && (kbdOpen() || w === lastSize[0])) return;
      lastSize = [w, h];
      send({ t: "resize", w, h });
    }, 400);
  });

  applyMode(); applyEdge(); applyRotate();
  start();
})();
