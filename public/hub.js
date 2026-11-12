// The k-hole phone app's hub: one Home Screen icon for Remote, k-beam and Agents. The phone
// pairs once, in Remote: that pairing (khole-web's app cookie) lets it into k-beam and Agents
// too. Each part keeps its own page and service worker under its own path; this page says which
// ones the computer has on, whether this phone is paired, and opens them. Opened from the Home
// Screen, it goes straight to the part used last (unless you turned that off, or came here on
// purpose).
"use strict";
(() => {
  const SECTIONS = ["remote", "beam", "agents"];
  const PAIR = "Pair this phone in Remote first.";
  const FULL = "Needs full control: in Remote, More, Full control.";
  const OFF = { remote: "Off on the computer: Settings, Remote, Browser.",
                beam: "Off on the computer: Settings, k-beam.",
                agents: "Off on the computer: Agents, Phone remote." };
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) {} },
  };
  const $ = (id) => document.getElementById(id);
  const standalone = () => matchMedia("(display-mode: standalone)").matches
    || matchMedia("(display-mode: fullscreen)").matches || navigator.standalone === true;
  const q = new URLSearchParams(location.search);
  // another computer's ticket rides in the fragment, never the query: a fragment isn't sent in
  // the request line, logged by a server or used as a service worker's cache key
  const hashTicket = /^#ticket=/.test(location.hash) ? location.hash.slice(8) : "";

  // another computer's k-stream asks to watch this one: that's Remote's page
  if (/^#tv=/.test(location.hash)) { location.replace("/remote/" + location.hash); return; }

  const last = store.get("khole-app-last");
  const remember = store.get("khole-app-remember") !== "off";
  let left = false;
  // only a launch (no ?hub, a plain open of /) goes on by itself, and only to a part that's on
  const autoOpen = standalone() && remember && !q.has("hub") && !hashTicket && SECTIONS.includes(last);

  // what keeps a part from opening right now ("" = it opens)
  function blocked(st, s) {
    if (!st[s]) return OFF[s];
    if (s === "remote") return "";
    if (!st.paired) return PAIR;
    if (s === "agents" && st.control !== "full") return FULL;
    return "";
  }

  function paint(st) {
    $("stopped").hidden = !st.stopped;
    $("away").hidden = true;
    $("retry").hidden = true;
    $("connection-state").textContent = st.stopped ? "Paused on your computer" : st.paired ? "Phone paired" : "Ready to pair";
    $("connection-state").className = st.stopped ? "away" : "on";
    $("pair-first").hidden = !(q.has("pair") || (!st.paired && (st.beam || st.agents)));
    $("full-first").hidden = !(q.has("control") && st.paired && st.control !== "full");
    $("go-files").href = st.beam && !st.paired ? "/remote/" : "/beam/#folder";
    // the Assistant lives on this origin and needs Remote's full control
    const asWhy = st.stopped ? "Paused" : !st.paired ? "Pair first" : st.control !== "full" ? "Needs control" : "";
    $("assistant-hint").textContent = asWhy ? asWhy : "Have the computer do a job for you";
    $("go-assistant").classList.toggle("off", !!asWhy);
    $("go-assistant").setAttribute("href", !st.paired ? "/remote/" : "/assistant/");
    for (const s of SECTIONS) {
      const why = blocked(st, s);
      const el = document.querySelector(`[data-state="${s}"]`);
      el.textContent = why || "On";
      el.className = "state " + (why ? "off" : "on");
      const a = $("go-" + s);
      a.classList.toggle("off", !!why);
      document.querySelector(`[data-hint="${s}"]`).textContent = st.stopped ? "Paused" : !st[s] ? "Off" : why === PAIR ? "Pair first" : why === FULL ? "Needs control" : "Ready";
      a.title = why || "Open " + s[0].toUpperCase() + s.slice(1);
      // not paired yet: k-beam and Agents lead to Remote, where the phone pairs
      a.setAttribute("href", st[s] && why === PAIR ? "/remote/" : "/" + s + "/");
    }
  }

  // Remote's pairing lives in its page's storage; the parts behind the proxy need it as the app's
  // cookie, which /api/hello hands out (a phone paired before the app had one gets it here)
  async function vouch() {
    let token = null;
    try { token = JSON.parse(localStorage.getItem("khole.token")); } catch (e) {}
    if (typeof token !== "string" || !token) return false;
    try {
      const r = await fetch("/api/hello", { cache: "no-store", credentials: "same-origin",
                                            headers: { Authorization: "Bearer " + token } });
      return r.ok;
    } catch (e) { return false; }
  }

  async function status() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      const r = await fetch("/app/status", { cache: "no-store", credentials: "same-origin", signal: controller.signal });
      if (!r.ok) throw new Error(String(r.status));
      return await r.json();
    } catch (e) { return null; } finally { clearTimeout(timeout); }
  }

  async function workers(st) {
    if (!("serviceWorker" in navigator) || !isSecureContext) return;
    navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {});
    // each part's own worker (k-beam's and Agents' notifications need theirs registered)
    const own = { remote: "/remote/", beam: "/beam/", agents: "/agents/" };
    for (const s of SECTIONS) {
      if (st && st[s]) navigator.serviceWorker.register(own[s] + "sw.js", { scope: own[s] }).catch(() => {});
    }
  }

  function wire() {
    $("add-computer").addEventListener("click", addComputer);
    $("add-computer-open").addEventListener("click", openDevices);
    for (const a of document.querySelectorAll("a.section")) {
      a.addEventListener("click", () => store.set("khole-app-last",
        a.getAttribute("href") === "/remote/" ? "remote" : a.dataset.section));
    }
  }

  let refreshing = false;
  async function refresh(launch = false) {
    if (refreshing) return;
    refreshing = true;
    $("retry").disabled = true;
    $("connection-state").textContent = "Checking connection…";
    $("connection-state").className = "";
    try {
      let st = await status();
      if (!st) {
        $("away").hidden = false;
        $("retry").hidden = false;
        $("connection-state").textContent = "Computer unavailable";
        $("connection-state").className = "away";
        for (const el of document.querySelectorAll("[data-state]")) { el.textContent = "Status unavailable"; el.className = "state off"; }
        for (const el of document.querySelectorAll("[data-hint]")) el.textContent = "Unavailable";
        workers(null); return;
      }
      if (!st.paired && await vouch()) st = (await status()) || st;
      paint(st);
      workers(st);
      computers(st);
      if (launch && autoOpen && !blocked(st, last) && !left && !q.has("pair") && !q.has("control")) {
        left = true; location.replace("/" + last + "/");
      }
    }
    finally { refreshing = false; $("retry").disabled = false; }
  }
  // your other k-hole computers that let this one's phones in (their k-hole link): a tap gets a
  // one-use ticket from that computer and opens its app, which pairs this phone without a PIN
  const LAPTOP = '<svg class="hub-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 16V7q0-2 2-2h10q2 0 2 2v9"/><path d="M3 19h18" data-accent="true"/></svg>';
  function computerRow(name, what, current) {
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button"; b.className = "computer";
    if (current) { b.setAttribute("aria-current", "true"); b.disabled = true; }
    b.innerHTML = LAPTOP;
    const w = document.createElement("span"); w.className = "words";
    const n = document.createElement("span"); n.className = "name"; n.textContent = name;
    const d = document.createElement("span"); d.className = "what"; d.textContent = what;
    w.append(n, d); b.append(w); li.append(b);
    return { li, b, d };
  }
  // Home always shows where the other computers are: the ones this phone can open, the paired
  // ones that keep phones out (and where to change that), and how to add one (pairing happens on
  // the computers' own screens; the phone can open Your devices there)
  async function computers(st) {
    const box = $("computers");
    if (!st || !st.paired || st.stopped) { box.hidden = true; return; }
    let list = null;
    try {
      const r = await fetch("/app/computers", { cache: "no-store", credentials: "same-origin" });
      if (r.ok) list = await r.json();
    } catch (e) {}
    const rows = list && Array.isArray(list.computers) ? list.computers : [];
    const others = list && Array.isArray(list.others) ? list.others : [];
    me = (list && list.me) || "this computer";
    box.hidden = false;
    const ul = $("computer-list");
    ul.textContent = "";
    ul.append(computerRow((list && list.me) || "This computer", "You're here", true).li);
    for (const c of rows) {
      const row = computerRow(String(c.name || "Your other computer"), "Open", false);
      row.b.addEventListener("click", () => go(c, row));
      ul.append(row.li);
    }
    for (const c of others) {
      const name = String(c.name || "Your other computer");
      const row = computerRow(name, "Paired. On " + name + ", turn on Your phones in Settings → Your devices", true);
      row.b.removeAttribute("aria-current");
      row.b.classList.add("closed");
      ul.append(row.li);
    }
    $("add-computer-me").textContent = me;
  }
  let me = "this computer";
  function addComputer() {
    const b = $("add-computer"), help = $("add-computer-help");
    const open = help.hidden;
    help.hidden = !open;
    b.setAttribute("aria-expanded", String(open));
    if (open) $("add-computer-open").focus();
  }
  async function openDevices() {
    const b = $("add-computer-open"), say = $("add-computer-result");
    b.disabled = true; b.setAttribute("aria-busy", "true");
    say.hidden = false; say.className = "note add-result"; say.textContent = "Opening Your devices on " + me + "…";
    try {
      const r = await fetch("/app/computers/add", { method: "POST", cache: "no-store", credentials: "same-origin",
        headers: { "Content-Type": "application/json" }, body: "{}" });
      const a = await r.json().catch(() => ({}));
      if (!r.ok || !a.ok) throw new Error(a.error || "It didn't answer.");
      say.textContent = "Your devices is open on " + me + ". Pick the other computer there and check the six words on both screens.";
      say.className = "note add-result ok";
    } catch (e) {
      say.textContent = "Couldn't open it: " + e.message;
      say.className = "note add-result away";
    } finally { b.disabled = false; b.removeAttribute("aria-busy"); }
  }
  async function go(c, row) {
    $("computer-error").hidden = true;
    row.b.setAttribute("aria-busy", "true");
    row.d.textContent = "Asking " + (c.name || "it") + "…";
    try {
      const r = await fetch("/app/computers/ticket", { method: "POST", cache: "no-store", credentials: "same-origin",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: c.id }) });
      const a = await r.json().catch(() => ({}));
      if (!r.ok || typeof a.url !== "string" || !/^https:\/\//.test(a.url)) throw new Error(a.error || "It didn't answer.");
      location.href = a.url;
    } catch (e) {
      row.b.removeAttribute("aria-busy");
      row.d.textContent = "Open";
      $("computer-error").textContent = "Couldn't open " + (c.name || "it") + ": " + e.message;
      $("computer-error").hidden = false;
    }
  }

  // opened from another of your computers with its ticket: pair here once (Remote's token, as if
  // the PIN had been typed), then drop the ticket from the address
  async function redeem() {
    const ticket = hashTicket;
    if (!ticket) return;
    history.replaceState(null, "", "/" + location.search);
    if (!/^[A-Za-z0-9_-]{43}$/.test(ticket)) return;
    let have = null;
    try { have = JSON.parse(localStorage.getItem("khole.token")); } catch (e) {}
    if (typeof have === "string" && have && await vouch()) return;
    try {
      const r = await fetch("/api/pair", { method: "POST", cache: "no-store", credentials: "same-origin",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ticket }) });
      const a = await r.json().catch(() => ({}));
      if (r.ok && typeof a.token === "string") {
        try { localStorage.setItem("khole.token", JSON.stringify(a.token)); } catch (e) {}
      } else {
        $("computer-error").textContent = a.error || "This phone couldn't be paired here.";
        $("computer-error").hidden = false;
      }
    } catch (e) {}
  }

  function recent() {
    const id = store.get("khole-app-last");
    $("home-recent").hidden = !SECTIONS.includes(id);
    if (SECTIONS.includes(id)) {
      $("home-recent").href = "/" + id + "/";
      $("recent-name").textContent = {remote:"Remote", beam:"Beam", agents:"Agents"}[id];
    }
  }
  function main() {
    wire();
    recent();
    $("retry").addEventListener("click", () => refresh());
    const arrived = !!hashTicket;
    redeem().then(() => refresh(!arrived));
  }
  // Refresh on return, without navigating away from a deliberately opened hub.
  addEventListener("pageshow", (e) => { if (e.persisted) { recent(); refresh(); } });
  document.readyState === "loading" ? addEventListener("DOMContentLoaded", main) : main();
})();
