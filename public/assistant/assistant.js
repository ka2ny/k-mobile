// The Assistant in the k-hole phone app: the same task the computer's Assistant window shows,
// asked of khole-web's /app/assistant (the shell's own view of it). Start a job, stop it, refuse
// the step it asks about, answer it, tell it something. Every card is answered
// by its id, so a tap on one that already went answers nothing. Allow and Keep going are never
// sent from here: they are presses in the Assistant's window, which this page opens in Remote.
// You pick which of your assistants does a job, see your chats grouped by assistant, open one and
// send a follow-up that goes on in it (khole-voice keeps the chat; only its words come here).
// What each assistant remembers is listed here to read; it is changed only in the window.
// Conversations between your assistants are read here, and you can write in one; going on,
// muting and starting a task an assistant proposes are the window's.
// Needs the phone paired in Remote with full control; nothing runs while the page is hidden.
"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const EVERY = 2000;
  let now = null;          // the last answer's task
  let timer = null;
  let busy = false;
  let lastSummary = "";    // the task id whose summary the history was last read for
  let lastGoal = "";
  let helpers = [];        // your assistants: {id, name, about, hue, builtin}
  let who = "";            // the one the next job goes to
  let chats = [];          // your recent chats
  let chat = null;         // the chat open now: {id, title, assistant, assistant_name, turns}
  let finding = "";        // the words in Search chats ("" = your recent chats)
  let findTimer = null;
  const ASSISTANT_RE = /^[a-z0-9][a-z0-9-]{0,23}$/;
  const CHAT_RE = /^t[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$/;
  const openId = () => { const m = /^#chat=(.+)$/.exec(location.hash); return m && CHAT_RE.test(m[1]) ? m[1] : ""; };
  const THREAD_RE = /^h[0-9a-f]{10}$/;
  const threadId = () => { const m = /^#thread=(.+)$/.exec(location.hash); return m && THREAD_RE.test(m[1]) ? m[1] : ""; };
  let talks = [];          // conversations between your assistants (summaries)
  let talk = null;         // the conversation open now
  const memoryId = () => { const m = /^#memory=(.+)$/.exec(location.hash); return m && ASSISTANT_RE.test(m[1]) ? m[1] : ""; };
  const KIND_WORDS = { you: "About you", computer: "About this computer", choice: "A choice you made", project: "About a project" };
  function remember(id) { try { localStorage.setItem("khole-assistant-who", id); } catch (e) { /* private mode */ } }
  function remembered() { try { return localStorage.getItem("khole-assistant-who") || ""; } catch (e) { return ""; } }
  const nameOf = (id) => (helpers.find((h) => h.id === id) || {}).name || "";
  function when(t) {
    if (!t) return "";
    const d = new Date(t * 1000), today = new Date();
    return d.toDateString() === today.toDateString()
      ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      : d.toLocaleDateString([], { weekday: "short", day: "numeric", month: "short" });
  }

  function show(el, on) { el.hidden = !on; }
  function say(id, text, kind) {
    const el = $(id);
    el.textContent = text || "";
    el.hidden = !text;
    el.className = "note as-result" + (kind ? " " + kind : "");
  }
  const money = (v) => (typeof v === "number" && v > 0) ? "$" + v.toFixed(v < 0.1 ? 3 : 2) : "";
  function meta(steps, cost) {
    const parts = [];
    if (steps) parts.push(steps === 1 ? "1 step" : steps + " steps");
    const m = money(cost);
    if (m) parts.push(m);
    return parts.join(" · ");
  }
  function limitWords(p) {
    if (p.limit === "steps") return "It took " + p.steps + " steps, the most it may take for one job. Let it go on?";
    if (p.limit === "usd") return "It spent " + money(p.cost_usd) + ", the most it may spend on one job. Let it go on?";
    if (p.limit === "time") return "It worked for " + p.minutes + " minutes, the longest it may take. Let it go on?";
    return "It reached one of its limits. Let it go on?";
  }
  const REASONS = { finished: "Done", gave_up: "It couldn't do it", stopped: "Stopped", paused: "Paused",
                    interrupted: "Stopped", refused: "Not done", local_only: "Nothing was sent", error: "Something went wrong",
                    budget: "Stopped at its limit", limit: "Stopped at its limit" };

  async function call(path, body) {
    const opts = { cache: "no-store", credentials: "same-origin" };
    if (body) {
      opts.method = "POST";
      opts.headers = { "Content-Type": "application/json" };
      opts.body = JSON.stringify(body);
    }
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 9000);
    opts.signal = ctl.signal;
    try {
      const r = await fetch(path, opts);
      const a = await r.json().catch(() => ({}));
      return { status: r.status, ok: r.ok, a };
    } catch (e) {
      return { status: 0, ok: false, a: { error: "The computer isn't answering. It may be asleep or off the tailnet." } };
    } finally { clearTimeout(t); }
  }

  function blocked(r) {
    const pair = r.status === 401;
    $("as-blocked").textContent = pair ? "Pair this phone in Remote first: enter the PIN from Settings → Remote on your computer."
      : (r.a.error || "The computer didn't answer.");
    show($("as-blocked"), true);
    show($("as-pair"), pair || /full control/i.test(r.a.error || ""));
    $("as-pair").textContent = pair ? "Open Remote" : "Open Remote to ask for full control";
    for (const id of ["as-start", "as-now", "as-done", "as-chat"]) show($(id), false);
    $("as-line").textContent = r.status === 0 ? "Computer unavailable" : pair ? "Not paired" : "Not available right now";
  }

  function list(ol, rows, cls) {
    ol.textContent = "";
    for (const row of rows) {
      const li = document.createElement("li");
      li.className = cls(row);
      const t = document.createElement("span");
      t.textContent = row.text || row.label || "";
      li.append(t);
      if (row.detail) {
        const d = document.createElement("small");
        d.textContent = row.detail;
        li.append(d);
      }
      ol.append(li);
    }
    show(ol, rows.length > 0);
  }

  // messages kept for when this turn ends: each with its remove button
  function paintQueue(items) {
    const ul = $("as-queue");
    ul.textContent = "";
    for (const q of items) {
      if (!q || !/^q[0-9]{1,9}$/.test(q.id || "")) continue;
      const li = document.createElement("li");
      const t = document.createElement("span");
      t.textContent = (q.by ? (q.new ? "From " + q.by + ", in a new chat: " : "From " + q.by + ": ")
                            : (q.new ? "Next, in a new chat: " : "Next: ")) + (q.text || "");
      const b = document.createElement("button");
      b.type = "button"; b.className = "as-safe"; b.textContent = "Remove";
      b.setAttribute("aria-label", "Remove: " + (q.text || ""));
      b.addEventListener("click", () => act({ action: "unqueue", id: q.id }, "as-steer-note", b, "Removing it…"));
      li.append(t, b);
      ul.append(li);
    }
    show(ul, ul.childElementCount > 0);
  }

  // a step that asked another assistant, handed it a task or taught it: "Asked Writer"
  function teamWords(h) {
    if (!h || !h.name) return "";
    if (h.kind === "ask") return "Asked " + h.name;
    if (h.kind === "teach") return "Taught " + h.name;
    return h.queued ? "Handed to " + h.name + ", waiting its turn" : "Handed to " + h.name;
  }

  // the agent a task handed work to: "Claude Code (fix tests) in shop is working"
  const AGENT_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,95}$/;
  function handoffWords(h) {
    const e = h.engine || "", nm = h.name || "";
    let who = e && nm && nm.toLowerCase() !== e.toLowerCase() ? e + " (" + nm + ")" : (e || nm || "The agent");
    if (h.project) who += " in " + h.project;
    return who + ({ needs: " waits for your yes on the computer", question: " asked a question", done: " finished",
                    stopped: " stopped", timeout: " is still working; the task went on without it" }[h.state] || " is working");
  }

  function paint(n) {
    now = n;
    show($("as-blocked"), false);
    show($("as-pair"), false);
    const running = n.running === true;
    const ended = !running && n.summary;
    const inChat = !!openId();
    const inMemory = !!memoryId() || !!threadId();
    $("as-line").textContent = running ? (n.confirm || n.question || n.paused ? "Waiting for you" : "Working on it")
      : "Ready";
    show($("as-start"), !running && !inChat && !inMemory);
    show($("as-now"), running);
    show($("as-done"), !!ended && !inChat && !inMemory);
    show($("as-chat"), inChat);
    show($("as-memory"), !!memoryId());
    show($("as-thread"), !!threadId());
    show($("as-talks"), talks.length > 0 && !running && !inChat && !inMemory);
    if (inChat) followState();
    if (n.note && n.note.text && !running) say("as-go-note", n.note.text, n.note.fail ? "away" : "");

    if (running) {
      $("as-now-title").textContent = n.goal || "";
      $("as-now-state").textContent = n.confirm || n.question || n.paused ? "Waiting for you"
        : n.handoff && (n.handoff.state === "working" || n.handoff.state === "needs") ? "Waiting on an agent" : "Working";
      const by = n.assistant && n.assistant !== "assistant" ? (n.assistant_name || nameOf(n.assistant)) : "";
      $("as-now-meta").textContent = [by, n.by ? "asked by " + n.by : "", meta(n.steps, n.cost_usd)].filter(Boolean).join(" · ");
      const c = n.confirm, q = n.question, p = n.paused;
      const h = n.handoff;
      show($("as-handoff"), !!h);
      if (h) {
        $("as-handoff-words").textContent = handoffWords(h);
        $("as-handoff-line").textContent = h.line || "";
        show($("as-handoff-line"), !!h.line);
        const id = AGENT_RE.test(h.agent || "") ? h.agent : "";
        $("as-handoff-open").href = id ? "/agents/#agent=" + encodeURIComponent(id) : "/agents/";
      }
      show($("as-confirm"), !!c);
      if (c) {
        if ($("as-confirm").dataset.id !== c.id) { say("as-confirm-note", ""); $("as-confirm").dataset.id = c.id; }
        $("as-confirm-label").textContent = c.label;
        $("as-confirm-why").textContent = c.why || "";
        show($("as-confirm-why"), !!c.why);
      }
      show($("as-question"), !!q);
      if (q) {
        if ($("as-question").dataset.id !== q.id) {
          $("as-question").dataset.id = q.id;
          say("as-question-note", "");
          $("as-answer").value = "";
          const box = $("as-choices");
          box.textContent = "";
          for (const choice of q.choices || []) {
            const b = document.createElement("button");
            b.type = "button"; b.className = "as-safe"; b.textContent = choice;
            b.addEventListener("click", () => answer(choice));
            box.append(b);
          }
          show(box, (q.choices || []).length > 0);
        }
        $("as-question-text").textContent = q.question;
      }
      show($("as-paused"), !!p);
      if (p) {
        if ($("as-paused").dataset.id !== p.id) { say("as-paused-note", ""); $("as-paused").dataset.id = p.id; }
        $("as-paused-words").textContent = limitWords(p);
      }
      list($("as-plan"), n.plan || [], (r) => "as-plan-row " + (r.status || "todo"));
      list($("as-steps"), (n.done || []).slice(-6).map((r) => ({ label: r.label, status: r.status,
        detail: [teamWords(r.team), r.detail || ""].filter(Boolean).join(" · ") })), (r) => "as-step " + (r.status || ""));
      paintQueue(n.queue || []);
      $("as-reply").textContent = n.reply || n.error || "";
      show($("as-reply"), !!(n.reply || n.error));
    }
    if (ended) {
      const s = n.summary;
      $("as-done-state").textContent = s.ok ? "Done" : (REASONS[s.reason] || "Not finished");
      $("as-done-state").className = "eyebrow " + (s.ok ? "ok" : "away");
      $("as-done-title").textContent = n.goal || "";
      $("as-done-words").textContent = s.summary || "";
      show($("as-done-words"), !!s.summary);
      $("as-done-meta").textContent = meta(s.steps, s.cost_usd);
      lastGoal = n.goal || "";
      show($("as-again"), !!lastGoal);
      $("as-go-on").dataset.id = CHAT_RE.test(n.id || "") ? n.id : "";
      show($("as-go-on"), !!$("as-go-on").dataset.id);
      if (n.id && n.id !== lastSummary) { lastSummary = n.id; refresh(true); }
    }
  }

  // who does the next job: one radio per assistant, shown only when you have more than one
  function pickers(list, dflt) {
    helpers = (list || []).filter((h) => h && ASSISTANT_RE.test(h.id));
    const kept = remembered();
    if (!helpers.some((h) => h.id === who)) who = helpers.some((h) => h.id === kept) ? kept : (dflt || (helpers[0] || {}).id || "");
    const box = $("as-who-list");
    box.textContent = "";
    for (const h of helpers) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "as-chip"; b.setAttribute("role", "radio");
      b.dataset.id = h.id;
      if (h.hue >= 0) b.style.setProperty("--who-hue", String(h.hue));
      else b.classList.add("plain");
      const dot = document.createElement("span"); dot.className = "as-dot"; dot.setAttribute("aria-hidden", "true");
      const t = document.createElement("span"); t.textContent = h.name;
      b.append(dot, t);
      if (h.about) b.title = h.about;
      b.addEventListener("click", () => choose(h.id, true));
      b.addEventListener("keydown", (e) => {
        const i = helpers.findIndex((x) => x.id === h.id);
        const step = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : e.key === "ArrowLeft" || e.key === "ArrowUp" ? -1 : 0;
        if (!step) return;
        e.preventDefault();
        const next = helpers[(i + step + helpers.length) % helpers.length];
        choose(next.id, true);
        box.querySelector('[data-id="' + next.id + '"]').focus();
      });
      box.append(b);
    }
    choose(who, false);
    show($("as-who"), helpers.length > 1);
  }
  function choose(id, mine) {
    if (!helpers.some((h) => h.id === id)) return;
    who = id;
    if (mine) remember(id);
    for (const b of $("as-who-list").children) {
      const on = b.dataset.id === id;
      b.setAttribute("aria-checked", on ? "true" : "false");
      b.tabIndex = on ? 0 : -1;
    }
    $("as-go").textContent = helpers.length > 1 ? "Ask " + nameOf(id) : "Do it";
    $("as-memory-open").textContent = helpers.length > 1 ? "What " + nameOf(id) + " remembers" : "What it remembers";
  }

  // your chats, each assistant's together, newest first; a tap opens one
  function history(items, unseen) {
    say("as-away-note", unseen === 1 ? "1 chat finished while you were away." :
                        unseen > 1 ? unseen + " chats finished while you were away." : "");
    chats = (items || []).filter((t) => t && CHAT_RE.test(t.id));
    const box = $("as-history");
    box.textContent = "";
    const order = helpers.map((h) => h.id);
    for (const t of chats) if (!order.includes(t.assistant)) order.push(t.assistant);
    for (const aid of order) {
      const mine = chats.filter((t) => t.assistant === aid);
      if (!mine.length) continue;
      const head = document.createElement("div"); head.className = "as-group";
      const h = document.createElement("h3"); h.textContent = nameOf(aid) || mine[0].assistant_name || "Assistant";
      head.append(h);
      if (helpers.some((x) => x.id === aid)) {
        const nb = document.createElement("button");
        nb.type = "button"; nb.className = "as-link"; nb.textContent = "New chat";
        nb.setAttribute("aria-label", "New chat with " + h.textContent);
        nb.addEventListener("click", () => { choose(aid, true); $("as-goal").focus(); $("as-start").scrollIntoView({ block: "start" }); });
        head.append(nb);
      }
      const ul = document.createElement("ul"); ul.className = "computer-list";
      for (const t of mine) {
        const li = document.createElement("li");
        const b = document.createElement("button");
        b.type = "button"; b.className = "computer";
        const w = document.createElement("span"); w.className = "words";
        const g = document.createElement("span"); g.className = "name"; g.textContent = t.title || t.goal;
        if (t.seen === false) {
          // ended while nobody looked: a dot before its title until it's opened
          const dot = document.createElement("span"); dot.className = "as-new"; dot.setAttribute("aria-hidden", "true");
          g.prepend(dot);
        }
        const d = document.createElement("span"); d.className = "what";
        d.textContent = [t.seen === false ? "New" : "", t.ok ? "Done" : (REASONS[t.reason] || "Not finished"), t.by ? "asked by " + t.by : "",
                         t.turns > 1 ? t.turns + " turns" : "", when(t.ended)].filter(Boolean).join(" · ");
        w.append(g);
        if (t.match) { const m = document.createElement("span"); m.className = "as-match"; m.textContent = t.match; w.append(m); }
        w.append(d); b.append(w); li.append(b);
        b.setAttribute("aria-label", "Open “" + (t.title || t.goal) + "”");
        b.addEventListener("click", () => { location.hash = "chat=" + t.id; });
        ul.append(li);
      }
      box.append(head, ul);
    }
    show($("as-earlier"), (chats.length > 0 || finding !== "") && !(now && now.running) && !openId() && !memoryId());
    if (finding !== "") say("as-find-note", chats.length ? (chats.length === 1 ? "1 chat" : chats.length + " chats")
                                                     : "No chat matches “" + finding + "”.");
    else say("as-find-note", "");
  }

  // one chat: what you asked and how each turn ended, then a follow-up that goes on in it
  function paintChat(c) {
    chat = c;
    $("as-chat-who").textContent = c.assistant_name || nameOf(c.assistant) || "Assistant";
    $("as-chat-title").textContent = c.title || "";
    const ol = $("as-turns");
    ol.textContent = "";
    for (const t of c.turns || []) {
      const li = document.createElement("li"); li.className = "as-turn";
      const you = document.createElement("p"); you.className = "as-you"; you.textContent = t.goal;
      const it = document.createElement("div"); it.className = "as-it";
      const state = document.createElement("p"); state.className = "eyebrow " + (t.ok ? "ok" : "away");
      state.textContent = [t.ok ? "Done" : (REASONS[t.reason] || "Not finished"), meta(t.steps, 0), when(t.ended)]
        .filter(Boolean).join(" · ");
      it.append(state);
      if (t.summary) { const s2 = document.createElement("p"); s2.textContent = t.summary; it.append(s2); }
      li.append(you, it);
      ol.append(li);
    }
    followState();
  }
  function followState() {
    const busyNow = !!(now && now.running);
    $("as-follow-go").disabled = busyNow || !chat;
    if (busyNow) say("as-follow-note", "It's working on something now: wait for it, or stop it, then send this.", "away");
    else if ($("as-follow-note").classList.contains("away") && /working on something/.test($("as-follow-note").textContent)) say("as-follow-note", "");
  }
  // what one assistant remembers, read only: Pin, Lock and Forget are the window's
  async function loadMemory() {
    const id = memoryId();
    show($("as-memory"), true);
    for (const x of ["as-start", "as-done", "as-earlier", "as-chat"]) show($(x), false);
    $("as-memory-who").textContent = nameOf(id) || "Assistant";
    const ul = $("as-facts");
    if (ul.dataset.id !== id) { ul.textContent = ""; ul.dataset.id = ""; }
    say("as-memory-note", "Reading what it remembers…");
    const r = await call("/app/assistant?memory=" + encodeURIComponent(id));
    if (memoryId() !== id) return;
    if (r.status === 401 || r.status === 403 || r.status === 0) { blocked(r); return; }
    if (!r.ok || !r.a.memory) { say("as-memory-note", r.a.error || "That didn't open.", "away"); return; }
    if (r.a.now) paint(r.a.now);
    const facts = (r.a.memory.facts || []).filter((f) => f && typeof f.text === "string");
    ul.textContent = ""; ul.dataset.id = id;
    for (const f of facts) {
      const li = document.createElement("li");
      const t = document.createElement("span"); t.textContent = f.text;
      const d = document.createElement("small");
      d.textContent = [KIND_WORDS[f.kind] || KIND_WORDS.you, f.pinned ? "Pinned" : "", f.locked ? "Locked" : "", when(f.at)]
        .filter(Boolean).join(" · ");
      li.append(t, d);
      ul.append(li);
    }
    show(ul, facts.length > 0);
    const notes = (r.a.memory.notes || []).filter((n) => n && typeof n.title === "string");
    for (const [kind, list, head] of [["howto", "as-howto", "as-howto-title"], ["lesson", "as-lessons", "as-lessons-title"]]) {
      const box = $(list); box.textContent = "";
      const mine = notes.filter((n) => n.kind === kind);
      for (const n of mine) {
        const li = document.createElement("li");
        const t = document.createElement("strong"); t.textContent = n.title;
        const b = document.createElement("span"); b.textContent = n.body || "";
        const d = document.createElement("small");
        const uses = n.used === 1 ? "Used once" : n.used > 1 ? "Used " + n.used + " times" : "Not used yet";
        d.textContent = [uses, when(n.at)].filter(Boolean).join(" · ");
        li.append(t, b, d);
        box.append(li);
      }
      show(box, mine.length > 0); show($(head), mine.length > 0);
    }
    say("as-memory-note", facts.length || notes.length ? "" : "It doesn't remember anything yet. What it learns from your jobs shows here.");
  }
  const STATE_WORDS = { talking: "Talking", waiting: "Waits for you", idle: "Quiet" };
  function talksList(items) {
    talks = (items || []).filter((t) => t && THREAD_RE.test(t.id));
    const ul = $("as-talks-list");
    ul.textContent = "";
    for (const t of talks) {
      const li = document.createElement("li");
      const b = document.createElement("button");
      b.type = "button"; b.className = "computer";
      const w = document.createElement("span"); w.className = "words";
      const g = document.createElement("span"); g.className = "name"; g.textContent = t.title || (t.names || []).join(" and ");
      const d = document.createElement("span"); d.className = "what";
      d.textContent = [(t.names || []).join(", "), t.muted ? "Muted" : (STATE_WORDS[t.state] || ""),
                       t.unread === 1 ? "1 new" : t.unread > 1 ? t.unread + " new" : "", when(t.updated)].filter(Boolean).join(" · ");
      w.append(g);
      if (t.last && t.last.text) {
        const m = document.createElement("span"); m.className = "as-match";
        m.textContent = (t.last.you ? "You" : t.last.name) + ": " + t.last.text; w.append(m);
      }
      w.append(d); b.append(w); li.append(b);
      b.setAttribute("aria-label", "Open the conversation “" + (t.title || "") + "”" + (t.unread ? ", " + t.unread + " new" : ""));
      b.addEventListener("click", () => { location.hash = "thread=" + t.id; });
      ul.append(li);
    }
    show($("as-talks"), talks.length > 0 && !(now && now.running) && !openId() && !memoryId() && !threadId());
  }
  // one conversation between assistants: read it, write in it
  async function loadThread() {
    const id = threadId();
    show($("as-thread"), true);
    for (const x of ["as-start", "as-done", "as-earlier", "as-chat", "as-memory", "as-talks"]) show($(x), false);
    const ol = $("as-thread-messages");
    if (!talk || talk.id !== id) { ol.textContent = ""; $("as-thread-title").textContent = ""; say("as-thread-note", "Opening the conversation…"); }
    say("as-thread-send-note", "");
    const r = await call("/app/assistant?thread=" + encodeURIComponent(id));
    if (threadId() !== id) return;
    if (r.status === 401 || r.status === 403 || r.status === 0) { blocked(r); return; }
    if (!r.ok || !r.a.thread) { say("as-thread-note", r.a.error || "That conversation didn't open.", "away"); talk = null; return; }
    say("as-thread-note", "");
    talk = r.a.thread;
    $("as-thread-who").textContent = (talk.names || []).join(" and ");
    $("as-thread-title").textContent = talk.title || "";
    $("as-thread-why").textContent = talk.state === "waiting" ? (talk.why || "It waits for you: say go on in the window, or write in it.") : "";
    show($("as-thread-why"), talk.state === "waiting");
    ol.textContent = "";
    for (const m of talk.messages || []) {
      const li = document.createElement("li"); li.className = "as-turn";
      if (m.you) {
        const p = document.createElement("p"); p.className = "as-you"; p.textContent = m.text; li.append(p);
      } else {
        const box = document.createElement("div"); box.className = "as-it";
        const e = document.createElement("p"); e.className = "eyebrow";
        e.textContent = m.name + (m.kind === "suggest" ? (m.started ? " · proposed a task (started)" : " · proposes a task") : m.kind === "note" ? " · a note" : "");
        const p = document.createElement("p"); p.textContent = m.text;
        box.append(e, p); li.append(box);
      }
      ol.append(li);
    }
    if (!(talk.messages || []).length) say("as-thread-note", "Nothing in it yet.");
  }
  function route() { return threadId() ? loadThread() : memoryId() ? loadMemory() : loadChat(); }

  async function loadChat() {
    const id = openId();
    if (!id) {
      chat = null; show($("as-chat"), false);
      if (now) paint(now);
      return refresh(true);
    }
    show($("as-chat"), true);
    for (const x of ["as-start", "as-done", "as-earlier"]) show($(x), false);
    if (!chat || chat.id !== id) { $("as-turns").textContent = ""; $("as-chat-title").textContent = ""; say("as-chat-note", "Opening the chat…"); }
    say("as-follow-note", "");
    const r = await call("/app/assistant?chat=" + encodeURIComponent(id));
    if (openId() !== id) return;
    if (r.status === 401 || r.status === 403 || r.status === 0) { blocked(r); return; }
    if (!r.ok || !r.a.chat) { say("as-chat-note", r.a.error || "That chat didn't open.", "away"); chat = null; followState(); return; }
    say("as-chat-note", "");
    if (r.a.now) paint(r.a.now);
    paintChat(r.a.chat);
  }

  async function refresh(withHistory) {
    if (busy && !withHistory) return;
    busy = true;
    try {
      const asked = finding;
      const r = await call("/app/assistant" + (withHistory ? "?history=1&threads=1" + (asked ? "&q=" + encodeURIComponent(asked) : "") : ""));
      if (!r.ok || !r.a.now) { blocked(r); show($("as-earlier"), false); return; }
      if (withHistory) { pickers(r.a.assistants, r.a.default); talksList(r.a.threads); }
      paint(r.a.now);
      if (withHistory && asked === finding) history(r.a.history, r.a.unseen | 0);
      else if (now && now.running) show($("as-earlier"), false);
    } finally { busy = false; }
  }

  // one tap: the answer goes under the control that sent it
  async function act(body, noteId, button, working) {
    if (button) { button.disabled = true; button.setAttribute("aria-busy", "true"); }
    say(noteId, working);
    const r = await call("/app/assistant/do", body);
    if (button) { button.disabled = false; button.removeAttribute("aria-busy"); }
    if (!r.ok || !r.a.ok) {
      say(noteId, r.a.note || r.a.error || "It didn't go through.", "away");
      if (r.status === 401 || r.status === 403) await refresh(false);
      return false;
    }
    say(noteId, r.a.note || "", r.a.note ? "" : "ok");
    await refresh(false);
    return true;
  }

  async function inWindow(noteId, button) {
    if (await act({ action: "show" }, noteId, button, "Opening the Assistant on the computer…")) {
      say(noteId, "Press it in the Assistant's window.", "ok");
      location.href = "/remote/";
    }
  }

  // files for the next job: sent to the computer as they're picked, kept there until the job
  // starts (or for an hour), each with × to take it back
  let attached = [];          // {id, name, size, kind}
  let uploading = 0;
  const FILES_MAX = 4;
  function sizeWords(n) {
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return Math.round(n / 1024) + " KB";
    return (n / 1048576).toFixed(1) + " MB";
  }
  function paintFiles() {
    const ul = $("as-attached");
    ul.textContent = "";
    for (const f of attached) {
      const li = document.createElement("li");
      const n = document.createElement("span"); n.className = "name"; n.textContent = f.name;
      const z = document.createElement("span"); z.className = "size"; z.textContent = sizeWords(f.size || 0);
      const x = document.createElement("button"); x.type = "button"; x.textContent = "×";
      x.setAttribute("aria-label", "Take off “" + f.name + "”");
      x.addEventListener("click", () => unattach(f, li));
      li.append(n, z, x);
      ul.append(li);
    }
    show(ul, attached.length > 0);
    $("as-file-label").textContent = attached.length ? "Add another" : "Add a photo or file";
    show($("as-file-label"), attached.length < FILES_MAX);
  }
  async function upload(file) {
    const opts = { method: "POST", cache: "no-store", credentials: "same-origin",
                   headers: { "Content-Type": "application/octet-stream" }, body: file };
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 120000);
    opts.signal = ctl.signal;
    try {
      const r = await fetch("/app/assistant/attach?name=" + encodeURIComponent(file.name || "file"), opts);
      const a = await r.json().catch(() => ({}));
      return { status: r.status, ok: r.ok, a };
    } catch (e) {
      return { status: 0, ok: false, a: { error: "The computer isn't answering. It may be asleep or off the tailnet." } };
    } finally { clearTimeout(t); }
  }
  async function pick(files) {
    files = Array.from(files || []);
    if (!files.length) return;
    const room = FILES_MAX - attached.length - uploading;
    if (room <= 0) { say("as-file-note", "Four files at a time: take one off first.", "away"); return; }
    if (files.length > room) say("as-file-note", "Only " + room + " more fit: four files at a time.", "away");
    const go = files.slice(0, room);
    uploading += go.length;
    say("as-file-note", go.length === 1 ? "Sending “" + go[0].name + "” to your computer…" : "Sending " + go.length + " files to your computer…");
    let failed = "";
    for (const f of go) {
      if (f.size > 20 * 1048576) { failed = "“" + f.name + "” is too big: the files may be 20 MB together."; uploading--; continue; }
      const r = await upload(f);
      uploading--;
      if (r.ok && r.a.ok && r.a.id) attached.push({ id: r.a.id, name: r.a.name || f.name, size: r.a.size || f.size, kind: r.a.kind || "" });
      else failed = (r.a.error || "It didn't reach the computer.") + (go.length > 1 ? " (“" + f.name + "”)" : "");
      paintFiles();
    }
    say("as-file-note", failed, failed ? "away" : "");
  }
  async function unattach(f, li) {
    li.setAttribute("aria-busy", "true");
    const r = await call("/app/assistant/unattach", { id: f.id });
    if (!r.ok && r.status !== 404) {
      li.removeAttribute("aria-busy");
      say("as-file-note", r.a.error || "It didn't go through.", "away");
      return;
    }
    attached = attached.filter((x) => x.id !== f.id);
    paintFiles();
    say("as-file-note", "");
    $("as-file-label").focus();
  }

  async function start(goal, noteId, button) {
    goal = (goal || "").trim();
    if (!goal) { say(noteId, "Say what you want done first.", "away"); $("as-goal").focus(); return; }
    if (uploading > 0) { say(noteId, "Wait a moment: a file is still on its way.", "away"); return; }
    const body = { action: "start", text: goal };
    if (who) body.assistant = who;
    const files = noteId === "as-go-note" ? attached.map((f) => f.id) : [];
    if (files.length) body.attach = files;
    if (await act(body, noteId, button, files.length ? "Starting on your computer with your files…" : "Starting on your computer…")) {
      say(noteId, "");
      $("as-goal").value = "";
      if (files.length) { attached = []; paintFiles(); say("as-file-note", ""); }
    } else if (files.length && /isn't waiting|no longer/.test($(noteId).textContent)) {
      attached = []; paintFiles();
    }
  }
  function answer(text) {
    const q = now && now.question;
    if (!q || !text.trim()) return;
    act({ action: "answer", id: q.id, text: text.trim() }, "as-question-note", null, "Sending your answer…")
      .then((ok) => { if (ok) $("as-answer").value = ""; });
  }

  function wire() {
    $("as-form").addEventListener("submit", (e) => { e.preventDefault(); start($("as-goal").value, "as-go-note", $("as-go")); });
    $("as-file").addEventListener("change", (e) => { const fl = e.target.files; pick(fl).finally(() => { e.target.value = ""; }); });
    $("as-goal").addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); $("as-form").requestSubmit(); }
    });
    // Allow and Keep going are only presses in the window itself: bring it forward, then go
    // there in Remote, where the press is yours on the computer's own screen
    $("as-allow").addEventListener("click", () => now && now.confirm &&
      inWindow("as-confirm-note", $("as-allow")));
    $("as-deny").addEventListener("click", () => now && now.confirm &&
      act({ action: "deny", id: now.confirm.id }, "as-confirm-note", $("as-deny"), "Telling it no…"));
    $("as-continue").addEventListener("click", () => now && now.paused &&
      inWindow("as-paused-note", $("as-continue")));
    // Search chats: what was asked, said and done; a pause in typing asks the computer once
    const findNow = () => { clearTimeout(findTimer); findTimer = null; refresh(true); };
    $("as-find").addEventListener("input", () => {
      const w = $("as-find").value.replace(/\s+/g, " ").trim().replace(/^-+/, "").slice(0, 100);
      if (w === finding) return;
      finding = w;
      if (w) say("as-find-note", "Looking…");
      clearTimeout(findTimer);
      findTimer = setTimeout(findNow, 300);
    });
    $("as-find-form").addEventListener("submit", (e) => { e.preventDefault(); $("as-find").blur(); findNow(); });
    $("as-answer-form").addEventListener("submit", (e) => { e.preventDefault(); answer($("as-answer").value); });
    $("as-steer-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const text = $("as-steer").value.trim();
      if (!text) { say("as-steer-note", "Type something first.", "away"); return; }
      if (await act({ action: "steer", text }, "as-steer-note", null, "Telling it…")) {
        $("as-steer").value = "";
        say("as-steer-note", "Told it: " + text, "ok");
      }
    });
    $("as-next-turn").addEventListener("click", async () => {
      const text = $("as-steer").value.trim();
      if (!text) { say("as-steer-note", "Type something first.", "away"); $("as-steer").focus(); return; }
      if (await act({ action: "queue", text }, "as-steer-note", $("as-next-turn"), "Keeping it for later…")) $("as-steer").value = "";
    });
    $("as-stop").addEventListener("click", () =>
      act({ action: "stop" }, "as-stop-note", $("as-stop"), "Stopping it…"));
    $("as-again").addEventListener("click", () => start(lastGoal, "as-again-note", $("as-again")));
    $("as-go-on").addEventListener("click", () => { const id = $("as-go-on").dataset.id; if (id) location.hash = "chat=" + id; });
    $("as-chat-back").addEventListener("click", () => { location.hash = ""; });
    $("as-memory-back").addEventListener("click", () => { location.hash = ""; });
    $("as-thread-back").addEventListener("click", () => { location.hash = ""; });
    $("as-thread-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const text = $("as-thread-reply").value.trim();
      if (!talk) return;
      if (!text) { say("as-thread-send-note", "Type something first.", "away"); $("as-thread-reply").focus(); return; }
      if (await act({ action: "thread-reply", id: talk.id, text }, "as-thread-send-note", $("as-thread-send"), "Sending it to the computer…")) {
        $("as-thread-reply").value = "";
        say("as-thread-send-note", "Sent: they read it on their next turn.", "ok");
        setTimeout(() => { if (threadId() === talk.id) loadThread(); }, 1500);
      }
    });
    $("as-memory-open").addEventListener("click", () => { if (who) location.hash = "memory=" + who; });
    $("as-follow-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const text = $("as-follow").value.trim();
      if (!chat) return;
      if (!text) { say("as-follow-note", "Say what it should do next.", "away"); $("as-follow").focus(); return; }
      const body = { action: "start", text, follow: chat.id };
      if (ASSISTANT_RE.test(chat.assistant || "")) body.assistant = chat.assistant;
      if (await act(body, "as-follow-note", $("as-follow-go"), "Sending it to the computer…")) {
        $("as-follow").value = "";
        location.hash = "";          // the running card shows what it does now
      }
    });
    $("as-follow").addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); $("as-follow-form").requestSubmit(); }
    });
    addEventListener("hashchange", route);
  }

  function poll() {
    clearInterval(timer); timer = null;
    if (document.hidden) return;
    timer = setInterval(() => refresh(false), EVERY);
  }
  function main() {
    wire();
    refresh(true).then(() => { if (openId() || memoryId() || threadId()) route(); poll(); });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(false); poll(); });
    addEventListener("pageshow", (e) => { if (e.persisted) { refresh(true); poll(); } });
  }
  document.readyState === "loading" ? addEventListener("DOMContentLoaded", main) : main();
})();
