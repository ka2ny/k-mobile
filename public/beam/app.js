// k-beam: the phone side of khole-share. Over Tailscale (HTTPS) it's an app: paired once, an inbox
// of what the computer sends (live while open, a notification while closed), saving to Photos through the
// share sheet, copy, send photos, files, text and the clipboard, and Android's share menu. On the home
// network over plain http (or not paired) it's the plain page: send, or open a share link.
"use strict";

const $ = (id) => document.getElementById(id);
const S = {
  me: null, items: [], blobs: new Map(), es: null, job: null, install: null,
  // the app (HTTPS on the tailnet); the plain page is http on the home network
  secure: window.isSecureContext && location.protocol === "https:", standalone: matchMedia("(display-mode: standalone)").matches || navigator.standalone === true,
};
const PREFETCH = 64 << 20;                   // total inbox prefetch budget, including queued requests
const PAIRED = "kbeam-paired";               // this browser was paired (its own storage: Safari's, or the Home Screen app's)
const ios = () => /iPhone|iPad/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const device = () => (/iPad/.test(navigator.userAgent) ? "iPad" : /iPhone|Android/.test(navigator.userAgent) ? "phone" : "device");
const computer = () => (S.me && S.me.name) || "the computer";

// Waits that end early when the phone wakes or its network comes back (a retry then starts at once)
const wakers = new Set();
function nap(ms) {
  return new Promise((r) => {
    const t = setTimeout(go, ms);
    function go() { clearTimeout(t); wakers.delete(go); r(); }
    wakers.add(go);
  });
}
function wakeNaps() { for (const w of [...wakers]) w(); }
// why the computer can't be reached, in words: this phone's network, or the way to the computer
function reachWords() {
  if (navigator.onLine === false) return `This ${device()} is offline.`;
  return S.secure ? `Can't reach ${computer()}: check it's on, and Tailscale is on here and there.`
    : `Can't reach ${computer()}: check it's on, and this ${device()} is on the same Wi-Fi.`;
}

// ------------------------------------------------------------------ small things
function human(n) {
  if (n < 1000) return `${n} B`;
  const u = ["KB", "MB", "GB", "TB"];
  let i = -1;
  do { n /= 1000; i++; } while (n >= 1000 && i < u.length - 1);
  return `${n < 10 ? n.toFixed(1) : Math.round(n)} ${u[i]}`;
}
function when(t) {
  const d = new Date(t * 1000);
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
// "Just now", "4 min ago", then the time of day (yesterday's and older: the date too)
function ago(t) {
  const m = Math.floor((Date.now() / 1000 - t) / 60);
  if (m < 1) return "Just now";
  if (m < 60) return `${m} min ago`;
  const d = new Date(t * 1000);
  return d.toDateString() === new Date().toDateString() ? when(t)
    : d.toLocaleDateString([], { day: "numeric", month: "short" });
}
function kindOf(f) {
  const t = f.type || "", n = f.name || "";
  if (/^image\//.test(t) || (!t && /\.(jpe?g|png|gif|webp|heic|heif|avif)$/i.test(n))) return "image";
  if (/^video\//.test(t) || (!t && /\.(mp4|mov|m4v|webm|mkv)$/i.test(n))) return "video";
  if (/^audio\//.test(t) || (!t && /\.(mp3|m4a|aac|flac|ogg|opus|wav)$/i.test(n))) return "audio";
  return "doc";
}
const KIND_GLYPH = { image: "gallery", video: "video", audio: "music", doc: "doc" };
function isLink(text) { return /^https?:\/\/\S+$/i.test(String(text || "").trim()); }
function hostOf(text) {
  try { return new URL(String(text).trim()).hostname; } catch (e) { return ""; }
}
// what arrived, said by kind (the names are in the list below it, never twice)
function headline(item) {
  if (item.text !== null) return isLink(item.text) ? "A link" : "Text";
  const kinds = item.files.map(kindOf), n = kinds.length;
  const all = (k) => n > 0 && kinds.every((x) => x === k);
  if (all("image")) return n === 1 ? "A photo" : `${n} photos`;
  if (all("video")) return n === 1 ? "A video" : `${n} videos`;
  if (all("audio")) return n === 1 ? "A song" : `${n} songs`;
  return n === 1 ? "A file" : `${n} files`;
}
function itemGlyph(item) {
  if (item.text !== null) return isLink(item.text) ? "link" : "doc";
  const kinds = new Set(item.files.map(kindOf));
  return kinds.size === 1 ? KIND_GLYPH[[...kinds][0]] : "files";
}
function disc(name, cls = "") {
  const d = el("span", "disc" + (cls ? " " + cls : ""));
  d.append(glyph(name));
  return d;
}
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}
function glyph(name) {
  const t = document.querySelector(`template#g-${name}`);
  return t ? t.content.firstElementChild.cloneNode(true) : el("span");
}
function buzz(ms) {
  // a tap's small answer; never before the person touched the page (Chrome refuses and says so)
  if (navigator.vibrate && (!navigator.userActivation || navigator.userActivation.hasBeenActive)) navigator.vibrate(ms);
}
function show(id) {
  for (const s of ["boot", "pair", "home", "guest", "link"]) $(s).hidden = s !== id;
}

let toastTimer = 0;
function toast(words, kind = "", { progress = null, cancel = null, stay = false, action = null } = {}) {
  const t = $("toast");
  clearTimeout(toastTimer);
  t.hidden = !words;
  t.className = "toast " + kind;
  $("toast-words").textContent = words || "";
  $("toast-progress").hidden = progress === null;
  if (progress === null) $("toast-bytes").hidden = true;
  if (progress !== null) $("toast-bar").style.width = `${Math.round(progress * 100)}%`;
  $("toast-cancel").hidden = !cancel;
  $("toast-cancel").onclick = cancel;
  // one thing to do about it ("Send again"): the toast stays until it's done or replaced
  $("toast-action").hidden = !action;
  $("toast-action").textContent = action ? action.label : "";
  $("toast-action").onclick = action ? () => { t.hidden = true; action.run(); } : null;
  if (words && !stay && !action && kind !== "busy") toastTimer = setTimeout(() => { t.hidden = true; }, kind === "fail" ? 6000 : 3000);
}

async function api(path, { method = "GET", body, headers = {}, raw = false } = {}) {
  const opts = { method, headers: { ...headers }, credentials: "same-origin", cache: "no-store" };
  if (body !== undefined) {
    opts.body = JSON.stringify(body);
    opts.headers["Content-Type"] = "application/json";
  }
  let r;
  try {
    r = await fetch(path, opts);
  } catch (e) {
    // the request never got an answer: this phone's network, or the way to the computer
    throw Object.assign(new Error(reachWords()), { status: 0, code: "offline" });
  }
  if (raw) return r;
  let j = {};
  try { j = await r.json(); } catch (e) { j = {}; }
  if (!r.ok || j.ok === false) {
    const err = new Error(j.message || `The computer answered ${r.status}.`);
    err.status = r.status;
    err.code = j.error;
    // inside the k-hole app the phone's pairing is Remote's: without it the hub says to pair there
    if (r.status === 401 && j.pair === true && linked()) { location.replace("/?hub=1&pair=1"); }
    // the pairing is gone (unpaired on the computer, or this browser's data was cleared)
    else if (r.status === 401 && j.error === "paired" && S.me && S.me.phone) unpaired();
    throw err;
  }
  return j;
}

// ------------------------------------------------------------------ sending (both kinds of page)
// A share: ask the computer (it may wait for a person there), then upload each file. Nothing here
// waits on one connection: the answer is asked for again after the phone slept or changed network,
// an upload that broke goes on from the byte the computer has, and Stop clears the computer's card.
const BACKOFF = [1000, 2000, 4000, 8000, 15000];
const stoppedErr = () => Object.assign(new Error("Stopped."), { stopped: true });

function cancelRemote(job) {
  const q = new URLSearchParams();
  if (job.ask) q.set("ask", job.ask);
  if (job.session) q.set("session", job.session);
  if (q.toString()) fetch(`api/cancel?${q}`, { method: "POST", credentials: "same-origin", keepalive: true }).catch(() => {});
}

function cancelSend() {
  const job = S.job;
  S.job = null;
  if (job) {
    job.stopped = true;
    if (job.xhr) job.xhr.abort();
    cancelRemote(job);
    wakeNaps();
  }
  toast("Stopped.", "warn");
}

function upload(job, sess, f, file, offset, onProgress) {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest();
    job.xhr = x;
    x.open("POST", `api/upload?session=${encodeURIComponent(sess)}&file=${encodeURIComponent(f.id)}&token=${encodeURIComponent(f.token)}`
      + (offset ? `&offset=${offset}` : ""));
    x.withCredentials = true;
    x.upload.onprogress = (e) => onProgress(offset + e.loaded);
    x.onload = () => {
      job.xhr = null;
      if (x.status === 200) return resolve();
      let j = {};
      try { j = JSON.parse(x.responseText); } catch (e) { j = {}; }
      reject(Object.assign(new Error(j.message || `The computer answered ${x.status}.`), { status: x.status, code: j.error }));
    };
    x.onerror = () => { job.xhr = null; reject(Object.assign(new Error(reachWords()), { status: 0, code: "offline" })); };
    x.ontimeout = x.onerror;
    x.onabort = () => { job.xhr = null; reject(stoppedErr()); };
    x.send(offset ? file.slice(offset) : file);
  });
}

// the request itself, again while the computer is busy with someone else's share or can't be reached
async function ask(job, body, headers) {
  const until = Date.now() + 120000;
  for (let n = 0; ; n++) {
    if (job.stopped) throw stoppedErr();
    try {
      return await api("api/prepare", { method: "POST", body: { ...body, wait: false }, headers });
    } catch (e) {
      if (job.stopped) throw stoppedErr();
      if ((e.code !== "busy" && e.code !== "offline") || Date.now() > until) throw e;
      toast(e.code === "busy" ? `${computer()} is taking another share: yours goes as soon as it's free.`
        : `${e.message} Trying again…`, "busy", { cancel: cancelSend, stay: true });
      await nap(e.code === "busy" ? 3000 : BACKOFF[Math.min(n, BACKOFF.length - 1)]);
    }
  }
}

// the computer's answer, asked for until it comes (a phone that slept asks again: the answer waits for it)
async function answer(job, id, seconds) {
  const until = Date.now() + (seconds + 60) * 1000;
  for (let n = 0; ; ) {
    if (job.stopped) throw stoppedErr();
    try {
      const a = await api(`api/ask?id=${encodeURIComponent(id)}&wait=25`);
      n = 0;
      if (a.state !== "waiting") return a;
      toast(`Waiting for ${computer()} to accept…`, "busy", { cancel: cancelSend, stay: true });
    } catch (e) {
      if (job.stopped) throw stoppedErr();
      if (e.code === "ask") throw Object.assign(new Error(`${computer()} restarted before it answered: send it again.`), { code: "gone" });
      if (e.code !== "offline" || Date.now() > until) throw e;
      toast(`Lost the connection while ${computer()} decides. ${e.message} Trying again…`, "busy", { cancel: cancelSend, stay: true });
      await nap(BACKOFF[Math.min(n++, BACKOFF.length - 1)]);
    }
  }
}

// one file, going on from where the computer stopped hearing it
async function uploadAll(job, sess, f, file, onProgress, words) {
  let offset = 0;
  for (let n = 0; ; n++) {
    try {
      await upload(job, sess, f, file, offset, onProgress);
      return;
    } catch (e) {
      if (e.stopped || job.stopped) throw stoppedErr();
      // the share is over on the computer (it restarted, or waited too long for this phone)
      if (e.code === "session" || (e.code === "token" && e.status === 403)) {
        throw Object.assign(new Error(`${computer()} ended this share before it was all there: send it again.`), { code: "gone" });
      }
      if (!["offline", "partial", "offset", "busy"].includes(e.code) && e.status !== 0) throw e;
      if (n >= 12) throw Object.assign(new Error(`The connection kept dropping: ${human(offset)} of ${file.name} got there.`), { code: "gone" });
      toast(`${e.code === "offline" ? e.message : "The connection dropped."} ${words} goes on from ${human(offset)} when it's back…`,
        "busy", { progress: null, cancel: cancelSend, stay: true });
      await nap(BACKOFF[Math.min(n, BACKOFF.length - 1)]);
      if (job.stopped) throw stoppedErr();
      try {
        const st = await api(`api/upload?session=${encodeURIComponent(sess)}&file=${encodeURIComponent(f.id)}&token=${encodeURIComponent(f.token)}`);
        if (st.done) return;
        offset = st.have;
      } catch (e2) {
        if (e2.status === 403 || e2.status === 409) {
          throw Object.assign(new Error(`${computer()} ended this share before it was all there: send it again.`), { code: "gone" });
        }
      }
    }
  }
}

async function send(args) {
  const { files = [], text = null, pin = "", to = "" } = args;
  if (S.job) cancelSend();
  const job = { stopped: false, ask: "", session: "", xhr: null };
  S.job = job;
  const trusted = S.me && S.me.phone && S.me.phone.trusted;
  toast(trusted ? "Sending…" : `Waiting for ${computer()} to accept…`, "busy", { cancel: cancelSend, stay: true });
  const headers = pin ? { "X-Share-Pin": pin } : {};
  try {
    const body = text !== null ? { text } : { files: files.map((f) => ({ name: f.name, size: f.size, type: f.type || "" })) };
    if (to) body.to = to;
    let ans = await ask(job, body, headers);
    // Cancel can precede the prepare response. Remember the returned identifiers
    // and cancel that exact request, even if another send has since started.
    job.ask = ans.ask || "";
    job.session = ans.session || "";
    if (job.stopped) { cancelRemote(job); throw stoppedErr(); }
    if (ans.ask) {
      ans = await answer(job, ans.ask, ans.seconds || 90);
      job.session = ans.session || "";
      if (job.stopped) { cancelRemote(job); throw stoppedErr(); }
      job.ask = "";
    }
    if (ans.done) {
      if (S.job === job) S.job = null;
      toast("Sent: it's on the computer's clipboard.", "ok");
      return true;
    }
    job.session = ans.session;
    const total = files.reduce((a, f) => a + f.size, 0);
    const started = performance.now();
    let done = 0;
    // "12 MB of 40 MB · 6 s left": the rate since the first byte, once there's enough to judge by
    const bytes = (sent) => {
      const secs = (performance.now() - started) / 1000;
      const left = secs > 0.8 && sent > 0 ? Math.max(1, Math.round((total - sent) / (sent / secs))) : 0;
      const b = $("toast-bytes");
      b.hidden = total < 1000000;
      b.textContent = `${human(Math.round(sent))} of ${human(total)}` + (left ? ` · ${left < 60 ? `${left} s` : `${Math.round(left / 60)} min`} left` : "");
    };
    for (let i = 0; i < files.length; i++) {
      const words = files.length > 1 ? `Sending ${i + 1} of ${files.length}` : `Sending ${files[i].name}`;
      const head = () => toast(`${words}…`, "busy", { progress: done / Math.max(total, 1), cancel: cancelSend, stay: true });
      head();
      bytes(done);
      await uploadAll(job, ans.session, ans.files[i], files[i], (got) => {
        if ($("toast-progress").hidden) head();             // back from "the connection dropped"
        $("toast-bar").style.width = `${Math.round(((done + got) / Math.max(total, 1)) * 100)}%`;
        bytes(done + got);
      }, words.replace("Sending", "It"));
      done += files[i].size;
    }
    if (S.job === job) S.job = null;
    buzz(12);
    toast(to === "folder" ? (files.length > 1 ? `Added ${files.length} files to the shared folder.` : `Added ${files[0].name} to the shared folder.`)
      : files.length > 1 ? `Sent ${files.length} files (${human(total)}).` : `Sent ${files[0].name}.`, "ok");
    return true;
  } catch (e) {
    if (S.job === job) S.job = null;
    if (e.stopped || job.stopped) return false;
    if (e.code === "pin") { $("pin-row").hidden = false; $("guest-pin").focus(); }
    if (e.code === "paired") return false;                       // unpaired() took the screen
    // what can be tried again offers it; a no from the computer doesn't
    const again = ["gone", "offline", "busy", "partial", "rate"].includes(e.code)
      ? { label: "Send again", run: () => send(args) } : null;
    toast(e.message, e.code === "declined" || e.code === "busy" ? "warn" : "fail", { action: again });
    return false;
  }
}

// ------------------------------------------------------------------ the app: inbox
const prefetchJobs = new Map();
let prefetchBytes = 0, prefetchActive = 0;
function releasePrefetch(key) {
  const job = prefetchJobs.get(key);
  if (!job) return;
  prefetchJobs.delete(key); S.blobs.delete(key);
  prefetchBytes -= job.bytes;
  job.controller.abort(); job.resolve(null);
}
function prunePrefetch(items) {
  const wanted = new Set(items.flatMap(item => item.files.map(f => `${item.id}/${f.id}`)));
  for (const key of prefetchJobs.keys()) if (!wanted.has(key)) releasePrefetch(key);
}
async function readPrefetch(response, limit) {
  if (!response.ok || Number(response.headers.get("Content-Length")) > limit) {
    await response.body?.cancel(); return null;
  }
  const reader = response.body?.getReader();
  if (!reader) return null;
  const chunks = [];
  let bytes = 0;
  try {
    for (;;) {
      const {done, value} = await reader.read();
      if (done) return new Blob(chunks, {type:response.headers.get("Content-Type") || ""});
      bytes += value.byteLength;
      if (bytes > limit) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
}
function pumpPrefetch() {
  if (document.hidden) return;
  for (const [key, job] of prefetchJobs) {
    if (prefetchActive >= 3) break;
    if (job.started) continue;
    job.started = true; prefetchActive++;
    fetch(`api/inbox/${key}?peek=1`, {credentials:"same-origin", signal:job.controller.signal})
      .then(r => readPrefetch(r, job.bytes))
      .then(blob => {
        if (prefetchJobs.get(key) !== job) return;
        // A file can change between listing and fetch; never retain an over-budget response.
        if (!blob || blob.size > job.bytes) { releasePrefetch(key); return; }
        prefetchBytes -= job.bytes - blob.size; job.bytes = blob.size;
        job.resolve(new File([blob], job.name, {type:job.type || blob.type}));
      })
      .catch(() => { if (prefetchJobs.get(key) === job) releasePrefetch(key); })
      .finally(() => { prefetchActive--; pumpPrefetch(); });
  }
}
function prefetch(item) {
  if (document.hidden) return;
  for (const f of item.files) {
    const key = `${item.id}/${f.id}`;
    if (prefetchJobs.has(key) || prefetchJobs.size >= 128 || !Number.isFinite(f.size) || f.size < 0 || f.size > PREFETCH-prefetchBytes) continue;
    const job = {bytes:f.size, name:f.name.split("/").pop(), type:f.type, controller:new AbortController(), started:false};
    const ready = new Promise(resolve => { job.resolve = resolve; });
    prefetchJobs.set(key, job); S.blobs.set(key, ready); prefetchBytes += f.size;
  }
  pumpPrefetch();
}
document.addEventListener("visibilitychange", () => { if (!document.hidden) pumpPrefetch(); });

async function save(item, button) {
  const ready = await Promise.all(item.files.map((f) => S.blobs.get(`${item.id}/${f.id}`) || Promise.resolve(null)));
  const files = ready.filter(Boolean);
  if (files.length === item.files.length && navigator.canShare && navigator.canShare({ files })) {
    try {
      await navigator.share({ files });
      await done(item);
      return;
    } catch (e) {
      if (e.name === "AbortError") return;
    }
  }
  if (navigator.onLine === false && files.length < item.files.length) {
    return toast(`${reachWords()} What ${computer()} sent stays here: save it once the network is back.`, "warn");
  }
  // Downloads: the browser saves each file (Files on iOS, Downloads on Android).
  for (const f of item.files) {
    const a = el("a");
    a.href = `api/inbox/${item.id}/${f.id}`;
    a.download = f.name.split("/").pop();
    document.body.append(a);
    a.click();
    a.remove();
  }
  button.textContent = "Saved";
  setTimeout(() => done(item), 1500);
}

async function done(item) {
  // the card slides away first (at once with reduced motion), then the inbox is read again
  const li = document.querySelector(`.item[data-id="${CSS.escape(String(item.id))}"]`);
  if (li && !reduced()) { li.classList.add("leaving"); await sleep(180); }
  try {
    await api(`api/inbox/${item.id}/done`, { method: "POST" });
  } catch (e) {
    if (li) li.classList.remove("leaving");
    if (e.code === "offline") return toast(`${e.message} It leaves the list once the computer hears this.`, "warn");
  }
  for (const f of item.files) releasePrefetch(`${item.id}/${f.id}`);
  loadInbox();
}

async function copyText(item) {
  try {
    await navigator.clipboard.writeText(item.text);
    toast("Copied.", "ok");
    buzz(12);
  } catch (e) {
    toast("The phone didn't allow copying: press and hold the text instead.", "warn");
  }
}

function renderItem(item) {
  const fresh = Date.now() / 1000 - item.at < 120;
  const li = el("li", "item" + (item.state === "seen" && fresh ? " new" : ""));
  li.dataset.id = item.id;
  const link = item.text !== null && isLink(item.text);
  const head = el("div", "item-head");
  const what = el("div", "what");
  const total = item.text !== null ? 0 : item.total || item.files.reduce((a, f) => a + f.size, 0);
  // one file: its type here, its size on its row; several: what they come to
  const ext = item.text === null && item.files.length === 1 ? (/\.([a-z0-9]{1,5})$/i.exec(item.files[0].name) || [])[1] : "";
  const sub = item.text !== null ? (link ? hostOf(item.text) : `${item.text.length} characters`)
    : ext ? `${ext.toUpperCase()} · ${human(total)}` : human(total);
  what.append(el("strong", "", headline(item)), el("span", "sub", sub));
  const at = el("span", "when", ago(item.at));
  at.dataset.at = item.at;
  at.title = when(item.at);
  head.append(disc(itemGlyph(item)), what, at);
  li.append(head);
  const row = el("div", "row");
  if (item.text !== null) {
    li.append(el("p", "item-text" + (link ? " url" : ""), item.text));
    if (link) {
      const open = el("button", "primary", "Open");
      open.type = "button";
      open.onclick = () => { buzz(8); window.open(item.text.trim(), "_blank", "noopener"); done(item); };
      row.append(open);
    }
    const copy = el("button", link ? "quiet" : "primary", "Copy");
    copy.type = "button";
    copy.onclick = () => copyText(item).then(() => done(item));
    row.append(copy);
  } else {
    const pics = item.files.filter((f) => /^image\//.test(f.type));
    if (pics.length) {
      const grid = el("div", "thumbs");
      for (const f of pics.slice(0, 8)) {
        const img = el("img");
        img.alt = f.name.split("/").pop();
        img.loading = "lazy";
        img.decoding = "async";
        img.src = `api/inbox/${item.id}/${f.id}?view=1&peek=1`;
        grid.append(img);
      }
      li.append(grid);
    }
    const others = item.files.filter((x) => !/^image\//.test(x.type));
    if (others.length) {
      const list = el("div", "files");
      for (const f of others.slice(0, 6)) {
        const line = el("div", "file");
        line.append(glyph(KIND_GLYPH[kindOf(f)]), el("span", "name", f.name), el("span", "size", human(f.size)));
        list.append(line);
      }
      if (others.length > 6) list.append(el("div", "file meta", `and ${others.length - 6} more`));
      li.append(list);
    }
    const saveB = el("button", item.state === "saved" ? "quiet" : "primary",
      item.state === "saved" ? "Save again" : pics.length === item.files.length ? "Save to Photos" : "Save");
    saveB.type = "button";
    saveB.onclick = () => { buzz(8); save(item, saveB); };
    row.append(saveB);
    prefetch(item);
  }
  const dismiss = el("button", "quiet", "Done");
  dismiss.type = "button";
  dismiss.onclick = () => done(item);
  row.append(dismiss);
  li.append(row);
  return li;
}

let inboxRequest = 0;
async function loadInbox() {
  const request = ++inboxRequest;
  try {
    const ans = await api("api/inbox");
    if (request !== inboxRequest) return;
    S.items = ans.items;
  } catch (e) {
    // what was shown stays; the live line says why it isn't new
    if (e.code === "offline") awayLine("");
    return;
  }
  prunePrefetch(S.items);
  const ul = $("items");
  ul.replaceChildren(...S.items.map(renderItem));
  $("empty").hidden = S.items.length > 0;
  $("count").textContent = S.items.length > 1 ? `${S.items.length} waiting` : "";
  if (navigator.setAppBadge) {
    (S.items.length ? navigator.setAppBadge(S.items.length) : navigator.clearAppBadge()).catch(() => {});
  }
}

// ------------------------------------------------------------------ the app: the shared folder (~/k-beam on the computer)
const fileNameOrder = new Intl.Collator(undefined, {numeric: true});
const fileTieOrder = new Intl.Collator();
const folderView = {files: [], filter: "all", limit: 60, grid: false, request: 0, on: false};
try { folderView.grid = localStorage.getItem("kbeam-files-layout") === "grid"; } catch {}
const fileMode = () => location.hash === "#folder";
function syncFileView() {
  document.body.classList.toggle("files-mode", fileMode());
  $("home-title").textContent = fileMode() ? "Files" : computer();
  $("files-location").textContent = `${computer()} / k-beam`;
  for (const [id, current] of [["files-view", fileMode()], ["beam-view", !fileMode()]]) {
    if (current) $(id).setAttribute("aria-current", "page"); else $(id).removeAttribute("aria-current");
  }
  $("shared").hidden = !folderView.on && !fileMode();
}
const filesMotionMedia = matchMedia("(prefers-reduced-motion: reduce)");
const fileAnimations = new Set();
const filesMotionAllowed = () => !document.hidden && !filesMotionMedia.matches && !["off", "reduced"].includes(document.documentElement.dataset.mobileMotion);
function settleFilesMotion() {
  for (const animation of fileAnimations) animation.cancel();
  fileAnimations.clear();
  if (!filesMotionAllowed() && fileDismissAnimation) dismissFileDetails(true);
}
filesMotionMedia.addEventListener("change", settleFilesMotion);
addEventListener("khole-motion-change", settleFilesMotion);
document.addEventListener("visibilitychange", () => { if (document.hidden) settleFilesMotion(); });
function filePositions(box) {
  const positions = new Map();
  for (const node of box.children) {
    const rect = node.getBoundingClientRect();
    if (rect.top > innerHeight) break;
    if (rect.bottom >= 0 && rect.top <= innerHeight) positions.set(node.dataset.fileKey, rect);
    if (positions.size >= 24) break;
  }
  return positions;
}
function renderFolder(moving = false) {
  settleFilesMotion();
  const oldPositions = moving && filesMotionAllowed() ? filePositions($("shared-files")) : null;
  $("files-layout").textContent = folderView.grid ? "List view" : "Grid view";
  $("files-layout").setAttribute("aria-pressed", String(folderView.grid));
  const query = $("files-search").value.trim().toLocaleLowerCase();
  const sort = $("files-sort").value;
  const files = folderView.files.filter(f => {
    const kind = kindOf(f);
    return f.name.toLocaleLowerCase().includes(query) && (folderView.filter === "all" ||
      (folderView.filter === "image" && kind === "image") ||
      (folderView.filter === "media" && ["audio", "video"].includes(kind)) ||
      (folderView.filter === "document" && !["image", "audio", "video"].includes(kind)));
  }).sort((a,b) => sort === "name" ? fileNameOrder.compare(a.name, b.name) :
    (sort === "size" ? b.size-a.size : b.at-a.at) || fileTieOrder.compare(a.name, b.name));
  const box = $("shared-files"), focused = box.contains(document.activeElement) ? document.activeElement : null;
  box.classList.toggle("file-grid", folderView.grid);
  const existing = new Map([...box.children].map(node => [node.dataset.fileKey, node]));
  const visible = files.slice(0, folderView.limit);
  const wanted = new Set(visible.map(f => f.name));
  for (const [name, node] of existing) if (!wanted.has(name)) node.remove();
  let cursor = box.firstElementChild;
  for (const f of visible) {
    let line = existing.get(f.name);
    if (!line) line = makeFileRow(f);
    line.file = f; // Reused controls always act on the latest server metadata.
    const kind = kindOf(f);
    if (line.dataset.kind !== kind) {
      line.dataset.kind = kind;
      line.querySelector(".file-symbol svg").replaceWith(glyph(KIND_GLYPH[kind]));
    }
    const size = line.querySelector(".size"), label = `${human(f.size)} · ${ago(f.at)}`;
    if (size.textContent !== label) size.textContent = label;
    if (line !== cursor) box.insertBefore(line, cursor);
    cursor = line.nextElementSibling;
  }
  if (oldPositions && box.animate) {
    const nextPositions = filePositions(box);
    for (const node of box.children) {
      const next = nextPositions.get(node.dataset.fileKey), old = oldPositions.get(node.dataset.fileKey);
      if (!next) continue;
      const x = old ? Math.max(-48,Math.min(48,old.left-next.left)) : 0;
      const y = old ? Math.max(-48,Math.min(48,old.top-next.top)) : 8;
      if (old && Math.abs(x)<1 && Math.abs(y)<1) continue;
      const animation = node.animate([{transform:`translate(${x}px,${y}px)`,opacity:old ? 0.8 : 0},{transform:"translate(0,0)",opacity:1}], {duration:220,easing:"cubic-bezier(.22,.8,.24,1)"});
      fileAnimations.add(animation);
      animation.finished.then(()=>fileAnimations.delete(animation),()=>fileAnimations.delete(animation));
    }
  }
  if (focused?.isConnected && document.activeElement !== focused) focused.focus({preventScroll:true});
  $("shared-empty").hidden = files.length > 0 || !folderView.on;
  $("shared-empty").textContent = query || folderView.filter !== "all" ? "No matching files. Try another name or file type." : "No shared files yet. Add files here or place them in k-beam on your computer.";
  $("shared-count").textContent = `${files.length} ${files.length === 1 ? "file" : "files"}` + (files.length !== folderView.files.length ? ` / ${folderView.files.length}` : "");
  $("files-more").hidden = files.length <= folderView.limit;
}
function makeFileRow(f) {
  const line = el("div", "file"); line.dataset.kind = kindOf(f); line.dataset.fileKey = f.name;
  const open = el("button", "file-open"); open.type = "button"; open.dataset.file = f.name;
  open.setAttribute("aria-label", `Details for ${f.name}`);
  const symbol = el("span", "file-symbol"); symbol.append(glyph(KIND_GLYPH[kindOf(f)]));
  const format = f.name.includes(".") ? f.name.split(".").pop().slice(0,8).toUpperCase() : "FILE";
  symbol.append(el("span", "file-format", format));
  const words = el("span", "file-words"); words.append(el("span", "name", f.name), el("span", "size"));
  open.append(symbol, words); open.onclick = () => showFile(line.file, open);
  const save = el("button", "quiet file-save"); save.type = "button";
  save.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12m-4-4 4 4 4-4M4 16v4h16v-4"/></svg><span>Save</span>';
  save.setAttribute("aria-label", `Save ${f.name}`); save.onclick = () => { buzz(8); saveShared(line.file, save); };
  line.append(open, save); return line;
}
async function loadFolder() {
  const request = ++folderView.request;
  folderView.on = !!S.me?.folder; syncFileView();
  $("files-controls").hidden = !folderView.on;
  $("shared-add").disabled = !folderView.on;
  if (!folderView.on) {
    $("files-refresh").disabled = false; folderView.files = []; renderFolder();
    $("files-status").hidden = false; $("files-status").textContent = "Shared folder is off. Turn it on in k-beam on the computer.";
    return;
  }
  $("files-refresh").disabled = true;
  try {
    const ans = await api("api/folder");
    if (request !== folderView.request) return;
    folderView.on = !!ans.on; folderView.files = ans.on && Array.isArray(ans.files) ? ans.files : [];
    syncFileView(); $("files-controls").hidden = !folderView.on; $("shared-add").disabled = !folderView.on;
    $("files-status").hidden = folderView.on;
    $("files-status").textContent = "Shared folder is off. Turn it on in k-beam on the computer.";
    renderFolder();
  } catch (e) {
    if (request !== folderView.request) return;
    $("files-status").hidden = false;
    $("files-status").textContent = folderView.files.length ? "Couldn’t refresh. Showing the last loaded files. Try Refresh." : "Couldn’t load files. Check the connection and try Refresh.";
    if (e.code === "offline") awayLine("");
  } finally { if (request === folderView.request) $("files-refresh").disabled = false; }
}
let fileDismissAnimation = null, fileDetailOpener = null, fileDetailName = "";
function dismissFileDetails(immediate = false) {
  const sheet = $("file-details");
  if (!sheet.open) { fileDismissAnimation?.cancel(); fileDismissAnimation = null; delete sheet.dataset.closing; return; }
  if (immediate || !filesMotionAllowed() || !sheet.animate) {
    fileDismissAnimation?.cancel(); fileDismissAnimation = null;
    sheet.close(); delete sheet.dataset.closing; return;
  }
  if (fileDismissAnimation) return;
  sheet.dataset.closing = "true";
  const start = getComputedStyle(sheet);
  fileDismissAnimation = sheet.animate([{opacity:start.opacity,transform:start.transform},{opacity:0,transform:"translateY(12px)"}], {duration:140,easing:"cubic-bezier(.4,0,1,1)",fill:"forwards"});
  const animation = fileDismissAnimation;
  animation.finished.then(()=> { if (fileDismissAnimation === animation) dismissFileDetails(true); }).catch(()=>{});
}
$("file-details").addEventListener("close", () => {
  // A native close event can arrive after a new file has already opened.
  if ($("file-details").open) return;
  $("file-preview").replaceChildren();
  (fileDetailOpener?.isConnected ? fileDetailOpener : [...$("shared-files").querySelectorAll("[data-file]")].find(b=>b.dataset.file===fileDetailName))?.focus();
});
$("file-details").addEventListener("cancel", event=> { event.preventDefault(); dismissFileDetails(); });
$("file-details").addEventListener("keydown", event=> { if (fileDismissAnimation) { event.preventDefault(); event.stopPropagation(); } }, true);
function showFile(f, opener) {
  if (fileDismissAnimation) dismissFileDetails(true);
  const sheet = $("file-details"), preview = $("file-preview");
  $("file-detail-name").textContent = f.name;
  $("file-detail-meta").replaceChildren(...[["Size", human(f.size)], ["Format", f.type || "File"], ["Modified", new Date(f.at*1000).toLocaleString()]].map(([key,value]) => {
    const row = el("div"); row.append(el("dt", "", key), el("dd", "", value)); return row;
  }));
  preview.replaceChildren();
  if (/^image\/(png|jpeg|webp|avif|gif)$/.test(f.type || "") && f.size <= 10*1024*1024) {
    const img = document.createElement("img"); img.alt = f.name; img.decoding = "async";
    const loading = el("p", "file-preview-loading", "Loading preview…"); loading.setAttribute("role", "status");
    img.onload = () => loading.remove();
    img.src = `api/folder/file?name=${encodeURIComponent(f.name)}`;
    img.onerror = () => { if (img.isConnected) preview.replaceChildren(el("p", "meta", "Preview unavailable. You can still save the file.")); };
    preview.append(img, loading);
  } else preview.append(glyph(KIND_GLYPH[kindOf(f)]));
  $("file-detail-save").onclick = () => saveShared(f, $("file-detail-save"));
  $("file-detail-close").onclick = () => dismissFileDetails();
  fileDetailOpener = opener; fileDetailName = f.name;
  sheet.showModal(); $("file-detail-name").focus({preventScroll:true}); sheet.scrollTop = 0;
}
$("files-search").addEventListener("input", () => { folderView.limit = 60; renderFolder(true); });
$("files-sort").addEventListener("change", () => { folderView.limit = 60; renderFolder(true); });
$("files-layout").onclick = () => {
  folderView.grid = !folderView.grid;
  try { localStorage.setItem("kbeam-files-layout", folderView.grid ? "grid" : "list"); } catch {}
  $("files-layout").setAttribute("aria-pressed", String(folderView.grid));
  $("files-layout").textContent = folderView.grid ? "List view" : "Grid view"; renderFolder(true);
};
for (const b of document.querySelectorAll('[data-file-filter]')) b.onclick = () => {
  folderView.filter = b.dataset.fileFilter; folderView.limit = 60;
  for (const option of document.querySelectorAll('[data-file-filter]')) option.setAttribute("aria-pressed", String(option === b));
  renderFolder(true);
};
$("files-more").onclick = () => { folderView.limit += 60; renderFolder(true); };
$("files-refresh").onclick = loadFolder;
$("files-view").onclick = () => { location.hash = "folder"; };
$("beam-view").onclick = () => { history.pushState(null, "", location.pathname + location.search); syncFileView(); };
addEventListener("hashchange", () => { syncFileView(); if (fileMode()) loadFolder(); });
syncFileView();

async function saveShared(f, button) {
  const url = `api/folder/file?name=${encodeURIComponent(f.name)}`;
  // the share sheet (Photos, Files, another app) when the phone has one and the file is small enough to hold
  if (navigator.canShare && f.size <= PREFETCH) {
    try {
      const r = await fetch(url, { credentials: "same-origin" });
      if (r.ok) {
        const file = new File([await r.blob()], f.name, { type: f.type || "" });
        if (navigator.canShare({ files: [file] })) {
          await navigator.share({ files: [file] });
          return;
        }
      }
    } catch (e) {
      if (e.name === "AbortError") return;
      if (navigator.onLine === false) return toast(`${reachWords()} Save it once the network is back.`, "warn");
    }
  }
  const a = el("a");
  a.href = url;
  a.download = f.name;
  document.body.append(a);
  a.click();
  a.remove();
  button.textContent = "Saved";
}

async function refreshMe() {
  try {
    const me = await api("api/me");
    if (!me.phone) return unpaired();
    const had = S.me && S.me.folder;
    S.me = me;
    if (had !== me.folder) loadFolder();
    $("get-clip").setAttribute("aria-disabled", me.phone.trusted ? "false" : "true");
  } catch (e) { /* away: the live line says so */ }
}

// The live line: an EventSource the browser keeps up by itself, and k-hole on top of it: a line the
// browser gave up on (the computer restarted, an error answer) is tried again with a growing wait; one
// that went quiet (a network change the phone didn't notice; a ping comes every 15 s) is made again;
// waking, a network coming back or the app coming to the front reconnects at once and reads what
// changed meanwhile.
const LIVE = { last: 0, backoff: 1000, timer: 0, away: false, quiet: 0 };
// away: offline says so in its own words (the browser's own errors come right after the offline event)
function awayLine(more) {
  if (navigator.onLine === false) return liveLine("away", `Offline: this ${device()} has no network. It reconnects by itself.`);
  liveLine("away", `Away: ${reachWords()} ${more}`);
}
function liveLine(kind, words) {
  $("live").className = "live " + kind;
  $("live-words").textContent = words;
}
function catchUp() {
  clearTimeout(LIVE.quiet);
  LIVE.quiet = setTimeout(() => { refreshMe(); loadInbox(); loadFolder(); }, 150);
}
function live() {
  clearTimeout(LIVE.timer);
  if (S.es) { S.es.close(); S.es = null; }
  if (!(S.me && S.me.phone)) return;
  if (navigator.onLine === false) { LIVE.away = true; liveLine("away", `Offline: this ${device()} has no network. It reconnects by itself.`); return; }
  const es = new EventSource("api/events", { withCredentials: true });
  S.es = es;
  LIVE.last = Date.now();
  const heard = () => { LIVE.last = Date.now(); };
  es.onopen = () => {
    heard();
    LIVE.backoff = 1000;
    liveLine("on", "Connected");
    if (LIVE.away) { LIVE.away = false; catchUp(); }
  };
  es.addEventListener("ping", heard);
  // what waits changed, or this phone did (trusted, renamed): read both again
  es.addEventListener("inbox", () => { heard(); loadInbox(); loadFolder(); refreshMe(); });
  es.addEventListener("unpaired", () => unpaired());
  es.onerror = () => {
    if (S.es !== es) return;
    LIVE.away = true;
    if (es.readyState === EventSource.CLOSED) { es.close(); S.es = null; again(); return; }
    awayLine("Trying again…");
  };
}
// the browser stopped trying: k-beam asks who it is first (a pairing that's gone says so), then reconnects
function again() {
  clearTimeout(LIVE.timer);
  const ms = LIVE.backoff;
  LIVE.backoff = Math.min(30000, ms * 2);
  awayLine(`Trying again in ${Math.round(ms / 1000)} s.`);
  LIVE.timer = setTimeout(async () => {
    try {
      const me = await api("api/me");
      if (!me.phone) return unpaired();
      S.me = me;
    } catch (e) {
      if (e.code === "offline") return again();
    }
    live();
  }, ms);
}
// back to the front, awake, or online again: now, not at the next try
function wake() {
  wakeNaps();
  if (!(S.me && S.me.phone) || $("home").hidden) return;
  const open = S.es && S.es.readyState === EventSource.OPEN && Date.now() - LIVE.last < 20000;
  if (!open) { LIVE.backoff = 1000; LIVE.away = true; live(); }
  else { LIVE.away = false; liveLine("on", "Connected"); }   // the line held through it: say so again
  catchUp();
}
function watchLine() {
  addEventListener("online", wake);
  addEventListener("offline", () => { wakeNaps(); if (!$("home").hidden) liveLine("away", `Offline: this ${device()} has no network. It reconnects by itself.`); });
  addEventListener("pageshow", (e) => { if (e.persisted) wake(); });
  addEventListener("focus", () => { if (Date.now() - LIVE.last > 20000) wake(); });
  document.addEventListener("visibilitychange", () => { if (!document.hidden) wake(); });
  // a line that's quiet past two pings is gone without a word (a network change): make it again
  setInterval(() => {
    if (document.hidden || !S.es || S.es.readyState !== EventSource.OPEN) return;
    if (Date.now() - LIVE.last > 40000) { LIVE.away = true; live(); }
  }, 10000);
}

// ------------------------------------------------------------------ the app: sending
function picked(input) {
  const files = [...input.files];
  input.value = "";
  if (files.length) send({ files });
}

async function sendClipboard() {
  try {
    const text = await navigator.clipboard.readText();
    if (!text.trim()) return toast("This phone's clipboard has no text.", "warn");
    send({ text });
  } catch (e) {
    toast("The phone didn't allow reading its clipboard.", "warn");
  }
}

async function getClipboard() {
  if (!(S.me.phone && S.me.phone.trusted)) {
    return toast("Trust this phone on the computer (Settings > k-beam, Trust this phone) to read its clipboard.", "warn");
  }
  const fetchText = () => api("api/clipboard").then((j) => j.text);
  try {
    if (window.ClipboardItem && navigator.clipboard.write) {
      // Safari keeps the tap's permission only when the write starts now, with the text still on its way.
      await navigator.clipboard.write([new ClipboardItem({ "text/plain": fetchText().then((t) => new Blob([t], { type: "text/plain" })) })]);
    } else {
      await navigator.clipboard.writeText(await fetchText());
    }
    toast("The computer's clipboard is on this phone.", "ok");
  } catch (e) {
    toast(e.message && e.status ? e.message : "The phone didn't allow copying.", "warn");
  }
}

// ------------------------------------------------------------------ the app: notifications, install, settings
function b64(s) {
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  const raw = atob((s + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

async function pushState() {
  const row = $("notify-row");
  const reg = await navigator.serviceWorker?.getRegistration?.();
  if (!S.me.push || !reg || !("PushManager" in window)) {
    $("notify-words").textContent = S.standalone || !/iPhone|iPad/.test(navigator.userAgent)
      ? "This browser can't get notifications from the computer." : "Add k-beam to your Home Screen first.";
    $("notify-go").hidden = true;
    return;
  }
  const sub = await reg.pushManager.getSubscription();
  row.dataset.on = sub ? "1" : "";
  $("notify-go").hidden = false;
  $("notify-go").textContent = sub ? "Turn off" : "Turn on";
  $("notify-words").textContent = sub ? "On: you hear about what the computer sends while the app is closed."
    : Notification.permission === "denied" ? "Blocked in this phone's settings for this app."
      : "When the computer sends something while the app is closed.";
}

async function togglePush() {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  try {
    if (sub) {
      await sub.unsubscribe();
      await api("api/push", { method: "POST", body: { subscription: null } });
    } else {
      if ((await Notification.requestPermission()) !== "granted") return pushState();
      const { key } = await api("api/push/key");
      const fresh = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64(key) });
      await api("api/push", { method: "POST", body: { subscription: fresh.toJSON() } });
    }
  } catch (e) {
    toast(e.message || "Notifications didn't turn on.", "fail");
  }
  pushState();
}

function settings() {
  const p = S.me.phone;
  $("settings-who").textContent = `Paired with ${S.me.name} as ${p.name}.` + (p.linked
    ? " The pairing is Remote's: unpair this phone in Settings, Remote on the computer and k-beam goes with it."
    : ios() ? (S.standalone
    ? " This Home Screen app has its own pairing, apart from Safari." : " This pairing is Safari's: k-beam on your Home Screen pairs on its own.") : "");
  $("trust-words").textContent = p.trusted ? "What you send goes in without asking, and you can read its clipboard."
    : "The computer asks before taking what you send. To skip that, trust this phone on the computer: Accept and trust on its card, or Settings > k-beam. Only the computer can trust a phone.";
  $("install-row").hidden = S.standalone;
  $("install-go").hidden = !S.install;
  if (S.install) $("install-words").textContent = "An app of its own, opened from your home screen.";
  if (p.linked && !S.install) $("install-words").textContent = "Tap Share, then Add to Home Screen: the k-hole app has Remote, k-beam, Agents and the Assistant in one icon.";
  pushState();
  $("settings-sheet").showModal();
}

// ------------------------------------------------------------------ Android's share menu (the service worker keeps them)
async function sharedIn() {
  if (!new URLSearchParams(location.search).has("shared")) return;
  history.replaceState(null, "", "./");
  const cache = await caches.open("khole-share-in");
  const meta = await cache.match("shared/meta");
  if (!meta) return;
  const m = await meta.json();
  const files = [];
  for (let i = 0; i < m.count; i++) {
    const r = await cache.match(`shared/${i}`);
    if (r) files.push(new File([await r.blob()], decodeURIComponent(r.headers.get("X-Name") || `file-${i}`), { type: r.headers.get("Content-Type") || "" }));
  }
  for (const k of await cache.keys()) await cache.delete(k);
  const text = [m.title, m.text, m.url].filter(Boolean).join("\n");
  if (!files.length && !text) return;
  // Any web page on this phone can POST a form to /share-target, so nothing goes before you tap Send.
  await confirmSend(files, text);
}

// what goes, shown first: Android's share menu, a paste or a drop on the app. Send sends it, Cancel drops it.
async function confirmSend(files, text) {
  const list = $("shared-items");
  list.replaceChildren();
  for (const f of files.slice(0, 8)) {
    const li = el("li");
    li.append(glyph(KIND_GLYPH[kindOf(f)]), el("span", "name", f.name), el("span", "size", human(f.size)));
    list.append(li);
  }
  if (files.length > 8) list.append(el("li", "meta", `and ${files.length - 8} more`));
  if (!files.length) list.append(el("li", "words", text.length > 300 ? text.slice(0, 300) + "…" : text));
  const total = files.reduce((a, f) => a + f.size, 0);
  $("shared-meta").textContent = files.length ? `${files.length === 1 ? "1 file" : `${files.length} files`} · ${human(total)}`
    : isLink(text) ? `A link to ${hostOf(text)}` : "Text";
  const sheet = $("shared-sheet");
  const go = await new Promise((resolve) => {
    $("shared-cancel").onclick = () => { sheet.close(); resolve(false); };
    sheet.onclose = () => resolve(sheet.returnValue === "send");
    sheet.returnValue = "";
    sheet.showModal();
    $("shared-send").focus();
  });
  sheet.onclose = null;
  if (!go) return;
  buzz(8);
  if (files.length) await send({ files });
  else await send({ text });
}

// the app takes a paste (outside a field) and a drop anywhere: both ask first
function takeDrops() {
  const veil = $("veil");
  let depth = 0;
  const open = () => !$("home").hidden && !document.querySelector("dialog[open]");
  addEventListener("dragenter", (e) => {
    if (!open() || !e.dataTransfer || ![...e.dataTransfer.types].includes("Files")) return;
    e.preventDefault();
    depth++;
    veil.hidden = false;
  });
  addEventListener("dragover", (e) => { if (!veil.hidden) e.preventDefault(); });
  addEventListener("dragleave", () => { if (--depth <= 0) { depth = 0; veil.hidden = true; } });
  addEventListener("drop", (e) => {
    if (veil.hidden) return;
    e.preventDefault();
    depth = 0;
    veil.hidden = true;
    const files = [...(e.dataTransfer.files || [])];
    if (files.length) confirmSend(files, "");
  });
  addEventListener("paste", (e) => {
    const t = e.target;
    if (!open() || (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable))) return;
    const files = [...((e.clipboardData && e.clipboardData.files) || [])];
    const text = e.clipboardData ? e.clipboardData.getData("text/plain") : "";
    if (!files.length && !text.trim()) return;
    e.preventDefault();
    confirmSend(files, files.length ? "" : text);
  });
}

// ------------------------------------------------------------------ pairing
// Safari and an app on the Home Screen keep their own storage on iOS, so each pairs on its own;
// on Android an installed app shares its browser's pairing. The pair screen says which one this is.
// inside the k-hole app (khole-web's proxy) k-beam has no pairing of its own: Remote's covers it
function linked() {
  return !!(S.me && S.me.linked) || /^\/beam\//.test(location.pathname);
}
function pairWhere() {
  if (linked()) return "";
  if (!ios()) return "";
  return S.standalone ? "This is k-beam on your Home Screen: it pairs on its own, apart from Safari. Type a new code from the computer once."
    : "This pairs Safari. Added to your Home Screen, k-beam pairs once more there, with a new code.";
}
function showPair(words = "", kind = "warn") {
  show("pair");
  $("pair-status").className = "status" + (words ? " " + kind : "");
  $("pair-status").textContent = words;
  $("pair-where").textContent = pairWhere();
  $("pair-where").hidden = !pairWhere();
  $("pair-guest").hidden = !(S.me && S.me.guests) || linked();
  $("pair-form").hidden = linked();
  if (linked()) {
    $("pair-hint").textContent = "This phone pairs once, in Remote: open Remote in the k-hole app and type the PIN "
      + "shown in Settings, Remote on the computer. k-beam then works here too.";
    $("pair-status").textContent = words;
    return;
  }
  $("pair-guest").onclick = guestPage;
  $("phone-name").placeholder = /iPad/.test(navigator.userAgent) ? "iPad" : /iPhone/.test(navigator.userAgent) ? "iPhone"
    : /Android/.test(navigator.userAgent) ? "Android phone" : "This device";
  $("pair-form").onsubmit = (e) => {
    e.preventDefault();
    const code = $("code").value.replace(/\D/g, "");
    if (code.length !== 6) { $("pair-status").className = "status warn"; $("pair-status").textContent = "The code has 6 digits."; return; }
    pair({ code });
  };
  $("code").focus();
}
function gone() {
  if (linked()) return `This ${device()} isn't paired with ${computer()} any more: it was unpaired in Remote there. `
    + "Pair it again in Remote; k-beam comes back with it.";
  return `This ${device()} isn't paired with ${computer()} any more: it was unpaired there, or this browser's data was cleared. `
    + "Pair it again with a new code from k-beam on the computer.";
}
// the computer forgot this phone while the app was open: back to pairing, saying so, never a dead screen
function unpaired() {
  if (S.me && S.me.phone === null && !$("pair").hidden) return;
  clearTimeout(LIVE.timer);
  inboxRequest++;
  S.items = []; $("items").replaceChildren();
  prunePrefetch([]);
  if (S.es) { S.es.close(); S.es = null; }
  if (S.job) { S.job.stopped = true; if (S.job.xhr) S.job.xhr.abort(); S.job = null; }
  // the flag stays until it pairs again (startApp sets it), so reopening says the same
  if (S.me) S.me = { ...S.me, phone: null };
  for (const d of document.querySelectorAll("dialog[open]")) d.close();
  toast("");
  if (navigator.clearAppBadge) navigator.clearAppBadge().catch(() => {});
  document.title = `k-beam · ${computer()}`;
  showPair(gone());
}

async function pair(body) {
  $("pair-status").className = "status busy";
  $("pair-status").textContent = "Pairing…";
  try {
    S.me = await api("api/pair", { method: "POST", body: { ...body, name: $("phone-name").value.trim() } });
    history.replaceState(null, "", "./");
    buzz(20);
    return startApp();
  } catch (e) {
    $("pair-status").className = "status fail";
    $("pair-status").textContent = e.code === "offline" ? `${e.message} The code still works for a few minutes.` : e.message;
    show("pair");
    $("code").select();
  }
}

// ------------------------------------------------------------------ the plain page
function guestPage() {
  show("guest");
  $("guest-app-hint").hidden = S.secure;
  $("pin-row").hidden = !(S.me && S.me.pin);
  const input = $("guest-files");
  const update = () => {
    const n = input.files.length;
    $("drop-title").textContent = n ? (n === 1 ? input.files[0].name : `${n} files`) : "Choose files";
    $("drop-meta").textContent = n ? human([...input.files].reduce((a, f) => a + f.size, 0)) : "or drop them here";
    $("guest-send").disabled = !n && !$("guest-text").value.trim();
  };
  input.onchange = update;
  $("guest-text").oninput = update;
  const drop = $("drop");
  drop.ondragover = (e) => { e.preventDefault(); drop.classList.add("over"); };
  drop.ondragleave = () => drop.classList.remove("over");
  drop.ondrop = (e) => { e.preventDefault(); drop.classList.remove("over"); input.files = e.dataTransfer.files; update(); };
  $("guest-send").onclick = async () => {
    const files = [...input.files];
    const text = $("guest-text").value;
    $("guest-send").disabled = true;
    const ok = files.length ? await send({ files, pin: $("guest-pin").value })
      : await send({ text, pin: $("guest-pin").value });
    if (ok) { input.value = ""; $("guest-text").value = ""; }
    update();
  };
}

// ------------------------------------------------------------------ a share link
async function linkPage(k) {
  show("link");
  try {
    const o = await api(`api/link?k=${encodeURIComponent(k)}`);
    const mins = Math.max(1, Math.round((o.until - Date.now() / 1000) / 60));
    $("link-meta").textContent = `This link works for ${mins} more minute${mins === 1 ? "" : "s"}.`;
    const ul = $("link-items");
    ul.replaceChildren();
    if (o.text !== null) {
      const li = el("li", "item");
      li.append(el("p", "item-text", o.text));
      if (S.secure && navigator.clipboard) {
        const b = el("button", "primary", "Copy");
        b.type = "button";
        b.onclick = () => navigator.clipboard.writeText(o.text).then(() => toast("Copied.", "ok"), () => toast("Press and hold the text to copy it.", "warn"));
        li.append(b);
      }
      ul.append(li);
    }
    for (const f of o.files) {
      const li = el("li", "item");
      const line = el("div", "file");
      line.append(el("span", "name", f.name), el("span", "size", human(f.size)));
      const a = el("a", "primary button", "Save");
      a.href = `api/link/file?k=${encodeURIComponent(k)}&f=${encodeURIComponent(f.id)}`;
      a.download = f.name.split("/").pop();
      li.append(line, a);
      ul.append(li);
    }
  } catch (e) {
    $("link-status").className = "status fail";
    $("link-status").textContent = e.message;
  }
}

// ------------------------------------------------------------------ start
function startApp() {
  show("home");
  $("get-clip").setAttribute("aria-disabled", S.me.phone.trusted ? "false" : "true");
  for (const id of ["pick-photos", "pick-camera", "pick-files"]) $(id).onchange = (e) => picked(e.target);
  $("open-text").onclick = () => { $("text-sheet").showModal(); $("text").focus(); };
  $("text-cancel").onclick = () => $("text-sheet").close();
  $("text-form").onsubmit = (e) => {
    e.preventDefault();
    const t = $("text").value;
    if (!t.trim()) return;
    $("text-sheet").close();
    send({ text: t }).then((ok) => { if (ok) $("text").value = ""; });
  };
  $("send-clip").onclick = sendClipboard;
  $("get-clip").onclick = getClipboard;
  $("open-settings").onclick = settings;
  $("settings-close").onclick = () => $("settings-sheet").close();
  $("notify-go").onclick = togglePush;
  $("install-go").onclick = async () => { if (S.install) { S.install.prompt(); S.install = null; $("install-go").hidden = true; } };
  // a phone paired through Remote unpairs there (it takes Remote, k-beam and Agents together)
  $("unpair").hidden = !!S.me.phone.linked;
  $("unpair").onclick = async () => {
    if (!confirm(`Unpair from ${S.me.name}? You'd need a new pairing code to use the app again.`)) return;
    try { await api("api/unpair", { method: "POST" }); } catch (e) { /* already */ }
    try { localStorage.removeItem(PAIRED); } catch (e) { /* private mode */ }   // your own choice: no "it was unpaired there"
    location.reload();
  };
  for (const t of document.querySelectorAll("#home .tile")) t.addEventListener("pointerdown", () => buzz(6));
  if (!S.wired) {               // once: pairing again after the computer forgot this phone comes back here
    S.wired = true;
    takeDrops();
    // "4 min ago" moves on by itself
    setInterval(() => { if (!document.hidden) for (const w of document.querySelectorAll(".when[data-at]")) w.textContent = ago(+w.dataset.at); }, 30000);
  }
  $("shared-add").onchange = (e) => {
    const files = [...e.target.files];
    e.target.value = "";
    if (files.length) send({ files, to: "folder" }).then((ok) => { if (ok) loadFolder(); });
  };
  try { localStorage.setItem(PAIRED, S.me.name); } catch (e) { /* private mode */ }
  loadInbox();
  loadFolder();
  live();
  sharedIn();
}

async function start() {
  if (!S.watching) {
    if (S.secure && "serviceWorker" in navigator) navigator.serviceWorker.register("sw.js", { scope: "./" }).catch(() => {});
    window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); S.install = e; });
  }
  const hash = new URLSearchParams(location.hash.slice(1));
  if (!S.watching) { S.watching = true; watchLine(); }
  try {
    S.me = await api("api/me");
  } catch (e) {
    return unreachable(e);
  }
  $("boot-note").hidden = true;
  document.title = S.me.phone ? `k-beam · ${S.me.name}` : `Beam to ${S.me.name}`;
  if (hash.get("k")) return linkPage(hash.get("k"));
  if (S.me.phone) return startApp();
  if (S.me.app && hash.get("pair")) return pair({ token: hash.get("pair") });
  if (S.me.app) {
    let was = null;
    try { was = localStorage.getItem(PAIRED); } catch (e) { was = null; }
    // paired before and not now: say so, rather than a pairing screen out of nowhere
    return showPair(was ? gone() : "");
  }
  if (!S.me.guests) {
    show("guest");
    $("guest-send").disabled = true;
    toast("This computer takes shares only from paired phones.", "warn", { stay: true });
    return;
  }
  guestPage();
}

// the computer didn't answer at the start (asleep, off, the network): say why, and try again by itself
let startTry = 0;
function unreachable(e) {
  show("boot");
  const name = (() => { try { return localStorage.getItem(PAIRED); } catch (x) { return null; } })();
  if (name && !S.me) S.me = { name };
  $("boot-note").hidden = false;
  $("boot-words").className = "status warn";
  $("boot-words").textContent = e.code === "offline" ? `${reachWords()} k-beam tries again by itself.` : e.message;
  const ms = Math.min(30000, 2000 * 2 ** startTry++);
  let t = 0;
  const retry = () => {
    clearTimeout(t);
    removeEventListener("online", retry);
    document.removeEventListener("visibilitychange", seen);
    $("boot-words").className = "status busy";
    $("boot-words").textContent = "Trying again…";
    start();
  };
  const seen = () => { if (!document.hidden) retry(); };
  t = setTimeout(retry, ms);
  $("boot-retry").onclick = () => { startTry = 0; retry(); };
  addEventListener("online", retry);
  document.addEventListener("visibilitychange", seen);
}

start();
