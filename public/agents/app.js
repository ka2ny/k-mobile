// Agents on the phone: a remote for your coding agents. Answer what needs you with a hold, steer
// with quick replies, start one from a project and a sentence, stop one with a hold. The engine is
// the k-hole Agents connector on your computer (same origin; a paired-device cookie).
import * as M from './model.js';
import {OmpActions} from './omp.js';

const $ = id => document.getElementById(id);
const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };
const setText = (n, t) => { t = String(t ?? ''); if (n.textContent !== t) n.textContent = t; };
const store = {
  get(k, d) { try { const v = localStorage.getItem('agents.' + k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('agents.' + k, JSON.stringify(v)); } catch { /* private mode: not kept */ } }
};
const HOLD_MS = 600, UNDO_MS = 3000;

const S = {
  status: null,           // /api/status of this computer
  hostId: store.get('host', ''),  // '' = this computer, else a host relayed through it
  hosts: [],
  rows: new Map(),        // id -> row (model.row + cards)
  replies: M.validReplies(store.get('replies', null)) ? store.get('replies') : [],
  projects: null,
  view: 'now', agent: null, detail: null,
  online: true, timer: 0, listStream: null, listKey: '', detailStream: null, detailKey: '', detailTimer: 0,
  busy: new Map(),        // id -> verb
  known: new Set(),       // decision ids already told about
  changes: {view: 'unstaged', files: [], open: -1},
  pending: null           // a quick reply inside its undo time
};
const ompContext = () => ({host:S.hostId,connector:S.hostId ? S.relay?.connector : S.status?.connector,deviceId:S.hostId ? S.relay?.deviceId : S.status?.deviceId,relayAccess:S.hostId ? S.relay?.access : undefined,online:S.online,permit:S.view === 'agent' && S.detail?.engine === 'omp' && S.detail.id === S.agent});
const omp = new OmpActions({api,context:ompContext,storage:{getItem:key=>localStorage.getItem(key),setItem:(key,value)=>localStorage.setItem(key,value)}});
let ompDraftKey = '', ompReceiptAt = 0;
function paintOmp(detail) {
  const panel = $('omp-panel');panel.hidden = !detail;
  const state = omp.bind(detail);
  if (!detail) { ompDraftKey='';return; }
  const key = JSON.stringify([S.hostId || '',ompContext().connector,ompContext().deviceId,detail.id]);
  if (key !== ompDraftKey) { ompDraftKey = key; $('omp-text').value = store.get('omp-draft.'+key,''); ompReceiptAt = 0; }
  const busy = S.busy.has(detail.id) || omp.busy;
  setText($('omp-status'),state.storageError ? 'Local receipt storage is unavailable. Sending is disabled.' : state.disconnectPending ? 'Disconnected here. Native confirmation is pending.' : state.stopping ? 'Checking your Stop request.' : state.pending ? 'A send has a saved receipt. It will not be submitted again.' : state.connected ? 'Connected to native OMP. Tool permissions stay in OMP.' : 'Connect to an opted-in OMP session to send messages here.');
  for (const [name,show] of [['observe',state.canObserve],['connect',state.canConnect],['disconnect',state.canDisconnect],['receipt',!!state.pending],['stop-receipt',!!state.stopping],['stop',state.canInterrupt]]) { $('omp-'+name).hidden=!show;$('omp-'+name).disabled=busy; }
  $('omp-form').hidden = !state.connected;
  $('omp-send').disabled = busy || !state.canSend || !$('omp-text').value.trim();
  $('omp-text').disabled = busy;
}
async function ompAction(action,text) {
  const id=S.agent,key=ompDraftKey,host=S.hostId;
  if (!id || S.busy.has(id)) return;
  await busyWith(id,'omp-'+action,async()=>{
    const result=action==='stopReceipt' ? await omp.receipt(true) : await omp[action](text);
    if (host !== S.hostId || S.agent !== id || key !== ompDraftKey) return;
    if (result.clearDraft && $('omp-text').value === result.submittedText) { $('omp-text').value='';store.set('omp-draft.'+key,''); }
    if (result.receipt) toast('OMP: '+result.receipt.state+(result.clearDraft ? '' : '. Your draft is retained.'));
    if (result.interrupt) toast('OMP Stop: '+result.interrupt.state);
    await loadDetail(id);
  });
}
async function pollOmpReceipt() {
  const state=omp.state(),id=S.agent,key=ompDraftKey,host=S.hostId;
  if (!id || (!state.pending && !state.stopping) || omp.busy || S.busy.has(id) || Date.now()-ompReceiptAt<2500) return;
  ompReceiptAt=Date.now();
  try { const result=await omp.receipt(!!state.stopping);if (S.hostId!==host||S.agent!==id||ompDraftKey!==key)return;
    if (result.clearDraft && $('omp-text').value===result.submittedText) { $('omp-text').value='';store.set('omp-draft.'+key,''); }
  } catch { /* Keep the durable ID; a receipt read never submits the command again. */ }
  if (S.hostId===host&&S.agent===id) paintOmp(S.detail);
}
for (const [id,action] of [['observe','observe'],['connect','connect'],['disconnect','disconnect'],['receipt','receipt'],['stop-receipt','stopReceipt']]) $('omp-'+id).addEventListener('click',()=>ompAction(action));
$('omp-text').addEventListener('input',()=>{store.set('omp-draft.'+ompDraftKey,$('omp-text').value);$('omp-send').disabled=!omp.state().canSend||!$('omp-text').value.trim();});
$('omp-form').addEventListener('submit',event=>{event.preventDefault();if (omp.state().canSend) ompAction('send',$('omp-text').value);});
armHold($('omp-stop'),()=>ompAction('interrupt'));

const seenKey = () => 'seen.' + (S.hostId || S.status?.connector || 'here');

// ---------------------------------------------------------------- the engine
// served by the k-hole app (khole-web's /agents/): one pairing, made in Remote, covers this page
const IN_APP = location.pathname.startsWith('/agents/');

async function api(path, {method = 'GET', body, here = false, timeout = 12000} = {}) {
  const prefix = !here && S.hostId ? 'hosts/' + encodeURIComponent(S.hostId) + '/proxy/' : '';
  let r;
  try {
    r = await fetch('api/' + prefix + path, {method, cache: 'no-store', credentials: 'same-origin',
      headers: body === undefined ? {} : {'Content-Type': 'application/json'},
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeout)});
  } catch { throw Object.assign(new Error(M.WORDS.OFFLINE), {code: 'OFFLINE'}); }
  let data = {};
  try { data = await r.json(); } catch { /* an empty answer */ }
  if (!r.ok) {
    // inside the k-hole app the phone's Remote pairing lets it in: send it to the app to pair there
    if (IN_APP && data.pair === true) { location.replace('/?hub=1&pair=1'); }
    if (IN_APP && data.control === true) { location.replace('/?hub=1&control=1'); }
    const code = data.error || (r.status === 502 || r.status === 504 ? 'HOST_UNAVAILABLE' : 'HTTP_' + r.status);
    throw Object.assign(new Error(M.words(code)), {code, status: r.status});
  }
  return data;
}

function generationOf(id) {
  // applyDetail also updates the row. A newer listing/card may have revoked
  // that connection since the detail was read; its null must win.
  return S.rows.get(id)?.generation || '';
}

// POSTs that name a project, and every POST relayed to another computer, carry that connector's
// id; relayed commands also carry the relay's access revision (from its /status)
async function stamp(body) {
  if (!S.hostId) return {...body, connector: S.status.connector};
  if (!S.relay) { const host = S.hostId, st = await api('status'); if (S.hostId !== host) throw Object.assign(Error(M.words('HOST_ACCESS_CHANGED')),{code:'HOST_ACCESS_CHANGED'}); S.relay = {connector: st.connector, access: st.relayAccess, deviceId: st.deviceId}; }
  return {...body, connector: S.relay.connector, relayAccess: S.relay.access};
}

async function command(kind, id, payload = {}, generation) {
  const host = S.hostId;
  const body = await stamp({id: crypto.randomUUID(), kind, session: id, generation: generation ?? generationOf(id) ?? '', payload});
  if (S.hostId !== host) throw Object.assign(Error(M.words('HOST_ACCESS_CHANGED')),{code:'HOST_ACCESS_CHANGED'});
  let r;
  try { r = await api('commands', {method: 'POST', body, timeout: 30000}); }
  catch (e) {
    if (e.code === 'HOST_ACCESS_CHANGED' || e.code === 'WRONG_CONNECTOR') S.relay = null;
    if(kind==='resume' && S.hostId===host && ['OFFLINE','OUTCOME_UNKNOWN','HOST_COMMAND_OUTCOME_UNKNOWN','HOST_UNAVAILABLE'].includes(e.code)){
      try{const receipt=await api('intents/'+body.id);if(S.hostId===host && receipt.intent?.id===body.id)r=receipt.intent;}catch{}
    }
    if(!r)throw e;
  }
  if (r.state === 'unknown') throw Object.assign(new Error(M.WORDS.OUTCOME_UNKNOWN), {code: 'OUTCOME_UNKNOWN'});
  if (r.state === 'failed') throw Object.assign(new Error('The agent didn’t accept it. Try again.'), {code: 'FAILED'});
  return r;
}

async function busyWith(id, verb, fn) {
  if (S.busy.has(id)) return;
  S.busy.set(id, verb); paint();
  try { await fn(); }
  catch (e) {
    toast(e.message, true);
    if (e.code === 'PAIR_REQUIRED' || e.code === 'REVOKED') unpaired(e.code);
  } finally { S.busy.delete(id); paint(); refresh(); }
}

// ---------------------------------------------------------------- start up
let pairToken = null;
async function boot() {
  const hash = new URLSearchParams(location.hash.slice(1));
  pairToken = hash.get('pair');
  const wanted = hash.get('agent');
  if (location.hash) history.replaceState(null, '', location.pathname);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  if (pairToken) { showPair(true); return; }
  try {
    S.status = await api('status', {here: true});
  } catch (e) {
    if (e.code === 'PAIR_REQUIRED' || e.code === 'REVOKED') { showPair(false, e.code); return; }
    setText($('boot').querySelector('p'), e.message);
    setTimeout(boot, 4000);
    return;
  }
  start(wanted);
}

function showPair(withForm, code) {
  if (IN_APP) { location.replace('/?hub=1&pair=1'); return; }
  $('boot').hidden = true; $('app').hidden = true; $('pair').hidden = false;
  $('pair-form').hidden = !withForm;
  setText($('pair-text'), withForm ? 'Approve, deny, steer and stop your coding agents from here. Name this phone, then connect.'
    : M.words(code || 'PAIR_REQUIRED'));
  if (withForm) { const ua = navigator.userAgent; $('pair-name').value = /iPad/.test(ua) ? 'iPad' : /iPhone/.test(ua) ? 'iPhone' : /Android/.test(ua) ? 'Android phone' : 'Phone'; }
}

$('pair-form').addEventListener('submit', async e => {
  e.preventDefault();
  const button = e.submitter || $('pair-form').querySelector('button');
  button.disabled = true; $('pair-error').hidden = true;
  try {
    await api('enroll', {method: 'POST', here: true, body: {pair: pairToken, name: $('pair-name').value.trim() || 'Phone'}});
    pairToken = null;
    S.status = await api('status', {here: true});
    start();
  } catch (err) {
    setText($('pair-error'), err.message); $('pair-error').hidden = false;
  } finally { button.disabled = false; }
});

function unpaired(code) {
  stopStreams(); clearTimeout(S.timer);
  S.rows.clear(); S.status = null;
  showPair(false, code);
}

async function start(wanted) {
  $('boot').hidden = true; $('pair').hidden = true; $('app').hidden = false;
  appearance();
  loadReplies();
  loadHosts();
  await refresh();
  if (wanted && /^[a-f0-9-]{36}$/i.test(wanted)) openAgent(wanted);
  else go(S.view);
  setupPushRow();
}

async function appearance() {
  try {
    const a = await api('appearance', {here: true});
    const root = document.documentElement;
    if (a.preset && a.preset !== 'custom') root.dataset.preset = a.preset;
    if (Number.isFinite(a.hue)) root.style.setProperty('--q-hue', String(a.hue));
    if (a.accent) {
      const [h, s, l] = hsl(a.accent);
      root.style.setProperty('--q-accent-h', String(h));
      root.style.setProperty('--q-accent-s', s + '%');
      root.style.setProperty('--q-accent-l', l + '%');
      root.style.setProperty('--q-accent', a.accent);
    }
    if (a.inkOnAccent) root.style.setProperty('--q-on-accent', a.inkOnAccent);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = getComputedStyle(document.body).backgroundColor || meta.content;
  } catch { /* the default look */ }
}

function hsl(hex) {
  const n = parseInt(hex.slice(1), 16), r = (n >> 16) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  let h = 0, s = 0;
  if (max !== min) {
    const d = max - min; s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4; h *= 60;
  }
  return [Math.round(h), Math.round(s * 100), Math.round(l * 100)];
}

// ---------------------------------------------------------------- the list
let refreshing = false;
async function refresh() {
  clearTimeout(S.timer);
  if (refreshing || !S.status) return;
  refreshing = true;
  const host = S.hostId;
  try {
    const r = await api('sessions');
    if (S.hostId !== host) return;
    const seen = store.get(seenKey(), {});
    const next = new Map();
    for (const s of r.sessions || []) {
      const row = M.mergeSummary(S.rows.get(s.id), s, seen);
      next.set(s.id, row);
    }
    S.rows = next;
    online(true);
    if (S.hostId) await relayedDecisions();
    syncListStream();
  } catch (e) {
    if (S.hostId !== host) return;
    if (e.code === 'PAIR_REQUIRED' || e.code === 'REVOKED') { unpaired(e.code); return; }
    online(false, e.message);
  } finally {
    refreshing = false;
    paint();
    // the live stream carries the changes on this computer; the list itself moves slowly
    S.timer = setTimeout(refresh, document.hidden ? 30000 : S.hostId ? 2500 : S.online ? 5000 : 4000);
  }
}

// another computer: no stream through the relay, so read the details of the ones that might ask
async function relayedDecisions() {
  const host = S.hostId;
  const ids = [...S.rows.values()].filter(r => r.state === 'working' || r.status === 'awaiting-permission').slice(0, 6).map(r => r.id);
  await Promise.all(ids.map(async id => {
    try { const d = await api('sessions/' + id); if (S.hostId !== host) return; const r = S.rows.get(id); if (r) S.rows.set(id, M.applyCard(r, {control: d, status: d.status})); } catch { /* next round */ }
  }));
}

function online(ok, why) {
  S.online = ok;
  $('offline').hidden = ok;
  if (!ok) setText($('offline'), why || M.WORDS.OFFLINE);
}

function syncListStream() {
  const ids = S.hostId || document.hidden ? [] : M.streamIds([...S.rows.values()].filter(r=>r.engine !== 'omp'));
  const key = ids.join(',');
  if (key === S.listKey && S.listStream) return;
  S.listStream?.close(); S.listStream = null; S.listKey = key;
  if (!ids.length) return;
  const source = new EventSource('api/activity-stream?ids=' + encodeURIComponent(key));
  S.listStream = source;
  source.onmessage = e => {
    if (S.listStream !== source) return;
    try {
      const data = JSON.parse(e.data);
      if (data.schemaVersion !== 1 || !Array.isArray(data.cards)) return;
      for (const c of data.cards) { const r = S.rows.get(c.id); if (r) S.rows.set(c.id, M.applyCard(r, c)); }
      online(true); paint();
    } catch { /* a broken message: the next one replaces it */ }
  };
  source.addEventListener('revoked', () => unpaired('REVOKED'));
}

function stopStreams() {
  S.listStream?.close(); S.listStream = null; S.listKey = '';
  S.detailStream?.close(); S.detailStream = null; S.detailKey = '';
  clearTimeout(S.detailTimer);
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { flushPending(); stopStreams(); }
  else if (S.status) { refresh(); if (S.agent) syncDetail(); }
});
window.addEventListener('pagehide', flushPending);

// ---------------------------------------------------------------- drawing
const cardNodes = new Map();
function paint() {
  if (!S.status) return;
  const rows = [...S.rows.values()];
  const c = M.counts(rows);
  setText($('summary'), S.online ? M.summary(c) : 'Offline');
  setText($('host-name'), hostName());
  $('tab-badge').hidden = !c.needs; setText($('tab-badge'), c.needs);
  document.title = c.needs ? '(' + c.needs + ') Agents' : 'Agents';
  try { if (c.needs) navigator.setAppBadge?.(c.needs); else navigator.clearAppBadge?.(); } catch { /* no badge */ }
  tell(rows);
  paintNow(rows);
  if (S.agent) paintAgent();
}

function hostName() {
  if (!S.hostId) return S.status?.host || 'This computer';
  return S.hosts.find(h => h.id === S.hostId)?.name || 'Another computer';
}

// a decision that came in while you look elsewhere: a toast you can tap
function tell(rows) {
  for (const r of rows) {
    if (!r.decision || S.known.has(r.decision.id)) continue;
    S.known.add(r.decision.id);
    if (S.agent === r.id && S.view === 'agent') continue;
    toast(r.name + ' ' + M.decisionVerb(r.decision.tool) + (r.decision.summary ? ': ' + M.clip(r.decision.summary, 60) : ''), false, () => openAgent(r.id));
    try { navigator.vibrate?.(30); } catch { /* none */ }
  }
}

function paintNow(rows) {
  const active = M.sortRows(rows.filter(r => r.state !== 'earlier'));
  const earlier = M.sortRows(rows.filter(r => r.state === 'earlier'));
  const box = $('cards');
  const want = [];
  let lastGroup = '';
  for (const r of active) {
    if (r.state !== lastGroup) { lastGroup = r.state; want.push(heading(r.state)); }
    want.push(card(r));
  }
  // place in order, reusing nodes (focus and a half-held button survive)
  want.forEach((n, i) => { if (box.children[i] !== n) box.insertBefore(n, box.children[i] || null); });
  while (box.children.length > want.length) box.lastChild.remove();
  for (const [id] of cardNodes) if (!S.rows.has(id)) cardNodes.delete(id);

  $('earlier').hidden = !earlier.length;
  setText($('earlier-count'), earlier.length || '');
  const list = $('earlier-list');
  const items = earlier.slice(0, 40).map(earlierRow);
  items.forEach((n, i) => { if (list.children[i] !== n) list.insertBefore(n, list.children[i] || null); });
  while (list.children.length > items.length) list.lastChild.remove();
  // nothing running: a calm line and the way to start; earlier ones open below it
  $('empty').hidden = active.length > 0 || !S.online;
  setText($('empty').querySelector('h2'), rows.length ? 'Nothing is running' : 'No agents yet');
  setText($('empty').querySelector('p'), rows.length ? 'Start one, or continue one from Earlier.' : 'Start one: pick a project and say what to do. It runs on your computer.');
  if (!active.length && earlier.length && !$('earlier').dataset.touched) $('earlier').open = true;
}

const headings = {};
function heading(state) {
  if (!headings[state]) headings[state] = el('h2', 'group-title', M.TITLES[state]);
  return headings[state];
}

function card(r) {
  let n = cardNodes.get(r.id);
  if (!n) {
    n = {root: el('article', 'card'), open: el('button', 'open'), head: el('div', 'card-head'), name: el('span', 'card-name'),
      pill: el('span', 'pill'), meta: el('p', 'card-meta'), words: el('p', 'card-words'), ask: el('div', 'ask'), act: el('div', 'act'), sig: ''};
    n.open.type = 'button';
    n.open.addEventListener('click', () => openAgent(r.id));
    n.head.append(n.name, n.pill);
    n.root.append(n.open, n.head, n.meta, n.words, n.ask, n.act);
    cardNodes.set(r.id, n);
  }
  n.root.className = 'card ' + r.state;
  setText(n.name, r.name);
  n.pill.className = 'pill ' + r.state; setText(n.pill, M.stateWords(r));
  const meta = [r.project, r.engineLabel, M.age(r.updatedAt)].filter(Boolean).join(' · ');
  n.meta.replaceChildren(...(r.unseen ? [el('span', 'dot')] : []), document.createTextNode(meta));
  const b = S.busy.get(r.id) || '';
  n.open.setAttribute('aria-label', 'Open ' + r.name + ', ' + M.stateWords(r));
  // what this agent needs, right on the card
  let words = '', mono = false, ask = '';
  if (r.state === 'needs' && r.decision) { words = r.engineLabel + ' ' + M.decisionVerb(r.decision.tool); ask = r.decision.summary; }
  else if (r.state === 'needs') words = 'It’s asking something on the computer.';
  else if (r.state === 'working') { const t = M.tailLines(r.tail, 1)[0] || ''; words = t ? M.clip(t, 140) : 'Working…'; mono = !!t; }
  else if (r.state === 'unreachable') words = 'Can’t reach it right now.';
  else words = M.lastWords(r) || 'Waiting for you.';
  if (r.readOnly) words = 'View only. ' + words;
  setText(n.words, words); n.words.className = 'card-words' + (mono ? ' mono' : '');
  setText(n.ask, ask); n.ask.hidden = !ask;
  const sig = [r.state, r.decision?.id || '', b, M.can(r, 'send') ? S.replies.map(x => x.label).join('|') : ''].join('/');
  if (sig !== n.sig) {
    n.sig = sig;
    const acts = [];
    if (M.can(r, 'decide')) {
      const deny = el('button', 'big', b === 'deny' ? 'Denying…' : 'Deny');
      deny.type = 'button'; deny.disabled = !!b; deny.setAttribute('aria-label', 'Deny: ' + r.decision.summary);
      deny.addEventListener('click', () => decide(r.id, false));
      const allow = holdButton('big primary', b === 'allow' ? 'Allowing…' : 'Hold to allow', () => decide(r.id, true));
      allow.disabled = !!b; allow.setAttribute('aria-label', 'Hold to allow: ' + r.decision.summary);
      acts.push(deny, allow);
    } else if (M.can(r, 'send') && r.state === 'turn') {
      for (const rep of S.replies.slice(0, 3)) {
        const chip = el('button', 'chip', rep.label);
        chip.type = 'button'; chip.disabled = !!b; chip.title = rep.text;
        chip.setAttribute('aria-label', rep.label + ': sends “' + M.clip(rep.text, 80) + '” to ' + r.name);
        chip.addEventListener('click', () => queueSend(r.id, rep.text, rep.label));
        acts.push(chip);
      }
    }
    n.act.replaceChildren(...acts);
    n.act.hidden = !acts.length;
  }
  return n.root;
}

const earlierNodes = new Map();
function earlierRow(r) {
  let n = earlierNodes.get(r.id);
  if (!n) {
    n = {li: el('li'), open: el('button', 'row-open'), name: el('span'), meta: el('span', 'muted small'), go: el('button', '', 'Continue')};
    n.open.type = 'button'; n.go.type = 'button';
    n.open.append(n.name, n.meta);
    n.open.addEventListener('click', () => openAgent(r.id));
    n.go.addEventListener('click', () => resume(r.id));
    n.li.append(n.open, n.go);
    earlierNodes.set(r.id, n);
  }
  setText(n.name, r.name);
  setText(n.meta, [r.project, r.engineLabel, M.age(r.updatedAt)].filter(Boolean).join(' · '));
  n.go.hidden = !M.can(r, 'resume');
  n.go.disabled = S.busy.has(r.id);
  n.go.setAttribute('aria-label', 'Continue ' + r.name);
  return n.li;
}

// ---------------------------------------------------------------- hold to confirm
function holdButton(cls, label, done) {
  const b = el('button', cls + ' hold');
  b.type = 'button';
  b.append(el('span', 'fill'), el('span', 'label', label));
  b.dataset.idle = label;
  armHold(b, done);
  return b;
}

// a press that must last HOLD_MS; letting go early, or sliding off, does nothing.
// Keyboard and screen readers: a click (Enter/Space or a double tap) asks once more in words.
function armHold(b, done) {
  let timer = 0, armed = false, pointer = false;
  const cancel = () => { clearTimeout(timer); b.classList.remove('holding'); armed = false; };
  b.style.setProperty('--hold-ms', HOLD_MS + 'ms');
  b.addEventListener('pointerdown', e => {
    if (b.disabled || e.button > 0) return;
    pointer = true; armed = true; b.classList.add('holding');
    try { b.setPointerCapture(e.pointerId); } catch { /* fine */ }
    timer = setTimeout(() => {
      if (!armed) return;
      b.classList.remove('holding'); b.classList.add('done');
      try { navigator.vibrate?.(15); } catch { /* none */ }
      setTimeout(() => b.classList.remove('done'), 300);
      armed = false; done();
    }, HOLD_MS);
  });
  b.addEventListener('pointerup', cancel);
  b.addEventListener('pointercancel', cancel);
  b.addEventListener('pointerleave', e => { if (e.pointerType !== 'touch') cancel(); });
  b.addEventListener('contextmenu', e => e.preventDefault());
  b.addEventListener('click', e => {
    if (pointer) { pointer = false; e.preventDefault(); return; }
    // not a pointer: a keyboard or an assistive press
    const label = b.querySelector('.label');
    if (b.dataset.confirm === '1') { b.dataset.confirm = ''; setText(label, b.dataset.idle); done(); return; }
    b.dataset.confirm = '1'; setText(label, 'Press again to confirm');
    setTimeout(() => { if (b.dataset.confirm === '1') { b.dataset.confirm = ''; setText(label, b.dataset.idle); } }, 4000);
  });
}

// ---------------------------------------------------------------- actions
function decide(id, allow) {
  const r = S.rows.get(id), d = r?.decision;
  if (!d) return;
  busyWith(id, allow ? 'allow' : 'deny', async () => {
    await command('permission', id, {allow, permission: d.id}, d.generation || generationOf(id));
    const now = S.rows.get(id);
    if (now && now.decision?.id === d.id) S.rows.set(id, {...now, decision: null, state: 'working', status: 'running'});
    toast(allow ? 'Allowed once.' : 'Denied.');
  });
}

function send(id, text) {
  return busyWith(id, 'send', async () => {
    await command('send', id, {text});
    if (store.get('draft.' + id,'') === text) store.set('draft.' + id,'');
    const r = S.rows.get(id);
    if (r) S.rows.set(id, {...r, state: 'working', status: 'running', unseen: false});
  });
}

// a quick reply waits UNDO_MS before it goes, so a slip of the thumb can be taken back
function queueSend(id, text, label) {
  flushPending();
  const r = S.rows.get(id);
  if (!r) return;
  const p = {id, text, timer: setTimeout(() => { if (S.pending === p) { S.pending = null; $('undo').hidden = true; send(id, text); } }, UNDO_MS)};
  S.pending = p;
  setText($('undo-text'), 'Sending “' + (label || M.clip(text, 30)) + '” to ' + r.name);
  const bar = $('undo').querySelector('.bar'); bar.style.setProperty('--undo-ms', UNDO_MS + 'ms');
  bar.remove(); $('undo').append(bar);   // restart the drain
  $('toast').hidden = true; clearTimeout(toastTimer);
  $('undo').hidden = false;
}

function flushPending() {
  const p = S.pending;
  if (!p) return;
  clearTimeout(p.timer); S.pending = null; $('undo').hidden = true;
  send(p.id, p.text);
}

$('undo-button').addEventListener('click', () => {
  if (!S.pending) return;
  clearTimeout(S.pending.timer); S.pending = null; $('undo').hidden = true;
  toast('Not sent.');
});

function stopAgent(id) { busyWith(id, 'stop', async () => { await command('stop', id); toast('Stopped.'); }); }
function resume(id) {
  const r = S.rows.get(id);
  busyWith(id, 'resume', async () => {
    const result=r?.codexJoin ? await command('join-codex', id, {}, '') : await command('resume', id);
    toast(result.state==='completed'?'Session connected.':'Reconnecting to the saved conversation…');
  });
}

// ---------------------------------------------------------------- one agent
function openAgent(id) {
  if (S.agent !== id) { S.detail = null; S.agentScrolled = false; $('stream').replaceChildren(); streamNodes.clear(); }
  S.agent = id;
  const seen = store.get(seenKey(), {}); seen[id] = Date.now();
  const keys = Object.keys(seen); if (keys.length > 300) for (const k of keys.sort((a, b) => seen[a] - seen[b]).slice(0, keys.length - 300)) delete seen[k];
  store.set(seenKey(), seen);
  const r = S.rows.get(id); if (r) r.unseen = false;
  go('agent');
  loadDetail(id);
}

async function loadDetail(id) {
  const host = S.hostId;
  try {
    if (host && !S.relay) await stamp({});
    const d = await api('sessions/' + id);
    if (S.agent !== id || S.hostId !== host) return;
    applyDetail(id, d);
  } catch (e) {
    if (S.agent !== id || S.hostId !== host) return;
    if (e.code === 'SESSION_NOT_FOUND') { toast(e.message, true); go('now'); return; }
    if (S.detail?.id === id && S.detail.engine === 'omp') { S.detail={...S.detail,ompLive:null,ompControl:null};paintOmp(S.detail); }
    toast(e.message, true);
  }
  syncDetail();
}

function applyDetail(id, d) {
  S.detail = {...d, id};
  const r = S.rows.get(id);
  if (r) S.rows.set(id, M.applyCard(r, {control: d, status: d.status}));
  paint();
  if (d.engine === 'omp') void pollOmpReceipt();
}

// the open agent: a detail stream on this computer while it runs, else a slow read
function syncDetail() {
  clearTimeout(S.detailTimer);
  const id = S.agent, r = id && S.rows.get(id);
  const live = !!(r && r.engine !== 'omp' && !S.hostId && !document.hidden && S.view === 'agent' && r.controllable);
  const key = live ? id + ':' + (r.generation || '') : '';
  if (key !== S.detailKey || !live) { S.detailStream?.close(); S.detailStream = null; S.detailKey = ''; }
  if (live && !S.detailStream) {
    S.detailKey = key;
    const source = new EventSource('api/activity-stream?ids=' + encodeURIComponent(id) + '&detail=1');
    S.detailStream = source;
    source.onmessage = e => {
      if (S.detailStream !== source) return;
      try {
        const c = JSON.parse(e.data).cards?.find(x => x.id === id);
        if (c?.control) applyDetail(id, c.control);
        else if (c) { const row = S.rows.get(id); if (row) { S.rows.set(id, M.applyCard(row, c)); paint(); } }
      } catch { /* the next one */ }
    };
    source.addEventListener('revoked', () => unpaired('REVOKED'));
  }
  if (!live && id && S.view === 'agent' && !document.hidden) {
    const slow = r && (r.engine === 'omp' || r.state === 'working' || r.state === 'needs') ? 2500 : 8000;
    const host = S.hostId;
    S.detailTimer = setTimeout(async () => { if (S.hostId === host && S.agent === id && S.view === 'agent') { try { const detail = await api('sessions/' + id); if (S.hostId === host && S.agent === id) applyDetail(id, detail); } catch { if (S.hostId === host && S.agent === id && S.detail?.engine === 'omp') { S.detail={...S.detail,ompLive:null,ompControl:null};paintOmp(S.detail); } } syncDetail(); } }, slow);
  }
}

let configurationFormKey = '';
function paintConfiguration(row, busy) {
  const panel = $('session-configuration'), container = $('configuration-options'), config = row?.configuration;
  panel.hidden = !config?.options?.length;
  const key = config ? [S.hostId || '',row.id,row.generation,config.revision].join('/') : '';
  if (configurationFormKey !== key) {
    configurationFormKey = key; container.replaceChildren();
    for (const option of config?.options || []) {
      const label = el('label','configuration-option'), caption = el('span','',option.label), select = el('select');
      select.setAttribute('aria-label',option.label);
      for (const choice of option.choices) { const node = el('option','',choice.label); node.value = choice.value; select.append(node); }
      select.value = option.value; label.append(caption,select);
      if (option.description) label.append(el('small','muted',option.description));
      container.append(label);
      const snapshot = {id:row.id,host:S.hostId,generation:row.generation,revision:config.revision,option:option.id};
      select.addEventListener('change',async()=>{
        const value = select.value, current = S.rows.get(snapshot.id);
        if (S.hostId !== snapshot.host || S.agent !== snapshot.id || !M.can(current,'configure') || current.generation !== snapshot.generation || current.configuration.revision !== snapshot.revision || value === option.value || S.busy.has(snapshot.id)) { select.value = option.value; return; }
        await busyWith(snapshot.id,'configure',async()=>{
          if (S.hostId !== snapshot.host) return;
          await command('configure',snapshot.id,{option:snapshot.option,value,revision:snapshot.revision},snapshot.generation);
          if (S.hostId === snapshot.host && S.agent === snapshot.id) await loadDetail(snapshot.id);
        });
        if (configurationFormKey === key) select.value = option.value;
      });
    }
  }
  for (const select of container.querySelectorAll('select')) select.disabled = !!busy || !M.can(row,'configure');
}

let questionFormKey = '', questionDraft = {}, questionSnapshot = null;
function paintQuestions(row, busy) {
  const form = $('questions'), key = M.questionKey(row);
  if (key !== questionFormKey) {
    questionFormKey = key; questionDraft = {}; questionSnapshot = key ? row.question : null; form.replaceChildren();
    if (questionSnapshot) {
      form.append(el('h2', 'eyebrow', 'Your input'));
      if (questionSnapshot.expiresAt) form.append(el('p','muted small','Answer before ' + new Date(questionSnapshot.expiresAt).toLocaleTimeString()));
      for (const q of questionSnapshot.questions) {
        const group = el('fieldset', 'question-group'); group.append(el('legend', '', q.prompt));
        if (q.detail) group.append(el('p', 'question-detail', q.detail));
        for (const option of q.options) {
          const label = el('label', 'question-option'), input = el('input'); input.type = q.multiple ? 'checkbox' : 'radio'; input.name = q.id; input.value = option.label;
          const words = el('span', '', option.label); if (option.description) words.append(el('small', 'muted', option.description)); label.append(input, words); group.append(label);
          input.addEventListener('change', () => {
            if (questionFormKey !== key) return;
            const old = questionDraft[q.id] || {}, selected = q.multiple ? [...group.querySelectorAll('input[type=checkbox]:checked')].map(n => n.value) : [option.label];
            questionDraft[q.id] = {selected, custom: q.multiple ? old.custom || '' : ''};
            if (!q.multiple) { const custom = group.querySelector('textarea'); if (custom) custom.value = ''; }
            updateQuestionButton();
          });
        }
        if (q.allowCustom) {
          const custom = el('textarea'); custom.rows = 2; custom.maxLength = 12000; custom.placeholder = q.options.length ? 'Another answer…' : 'Your answer…'; custom.setAttribute('aria-label', q.prompt);
          custom.addEventListener('input', () => { if (questionFormKey !== key) return; const old = questionDraft[q.id] || {}; questionDraft[q.id] = {selected: q.multiple || !custom.value.trim() ? old.selected || [] : [], custom: custom.value}; if (!q.multiple && custom.value.trim()) for (const input of group.querySelectorAll('input')) input.checked = false; updateQuestionButton(); }); group.append(custom);
        }
        form.append(group);
      }
      const submit = el('button', 'primary big', 'Send answers'); submit.id = 'send-question-answers'; submit.type = 'submit'; form.append(submit);
    }
  }
  form.hidden = !key;
  for (const control of form.querySelectorAll('input,textarea,button')) control.disabled = !!busy;
  updateQuestionButton();
}
function updateQuestionButton() {
  const button = $('send-question-answers'); if (!button) return;
  button.disabled = !questionFormKey || !!S.busy.get(S.agent) || !M.questionAnswers(questionSnapshot, questionDraft);
}
$('questions').addEventListener('submit', async event => {
  event.preventDefault(); const id = S.agent, row = S.rows.get(id), question = questionSnapshot, answers = M.questionAnswers(question, questionDraft);
  if (!question || !answers || !questionFormKey || questionFormKey !== M.questionKey(row) || S.busy.has(id)) return;
  await busyWith(id, 'answer', async () => { if (M.questionKey(S.rows.get(id)) !== questionFormKey) return; await command('answer', id, {question: question.id, answers}, question.generation); const latest = S.rows.get(id); if (latest) S.rows.set(id, {...latest, question:null}); if (S.detail?.id === id) S.detail.question = null; questionFormKey = ''; questionDraft = {}; questionSnapshot = null; $('questions').replaceChildren(); $('questions').hidden = true; await loadDetail(id); });
});
let renameTarget = null;
$('rename-agent').addEventListener('click', () => { const row = S.rows.get(S.agent); if (!M.can(row, 'rename')) return; renameTarget = {id:row.id,generation:row.generation}; $('rename-name').value = row.name; $('rename-session').showModal(); $('rename-name').focus(); });
$('rename-cancel').addEventListener('click', () => { renameTarget = null; $('rename-session').close(); });
$('rename-form').addEventListener('submit', async event => {
  event.preventDefault(); const target = renameTarget, row = target && S.rows.get(target.id), name = $('rename-name').value.trim();
  if (!target || !name || !M.can(row, 'rename') || row.generation !== target.generation) { $('rename-session').close(); return; }
  $('rename-session').close(); renameTarget = null; await busyWith(target.id, 'rename', async () => { await command('rename', target.id, {name}, target.generation); await loadDetail(target.id); });
});
const streamNodes = new Map();
function paintAgent() {
  const id = S.agent, r = S.rows.get(id);
  if (!r) { paintOmp(null); paintConfiguration(null, false); paintQuestions(null, false); $('rename-agent').hidden = true; return; }
  const d = S.detail?.id === id ? S.detail : null;
  setText($('agent-name'), r.name);
  setText($('agent-meta'), [r.project || M.baseName(r.cwd), r.engineLabel].filter(Boolean).join(' · '));
  $('agent-state').className = 'pill ' + r.state; setText($('agent-state'), M.stateWords(r));

  // the conversation, appended in place
  const box = $('stream');
  const nearEnd = box.getBoundingClientRect().bottom - window.innerHeight < 160 || !S.agentScrolled;
  const its = M.items(d?.messages || r.messages || []).slice(-200);
  const want = [];
  if(d?.historyWarning){
    let warning=streamNodes.get(' recovery');if(!warning){warning=el('p','quiet');warning.setAttribute('role','status');warning.dataset.recovery='true';streamNodes.set(' recovery',warning);}
    setText(warning,d.historyWarning);want.push(warning);
  }
  for (const it of its) {
    let n = streamNodes.get(it.key);
    if (!n) {
      if (it.kind === 'tool') {
        n = el('div', 'step'); const det = el('details'), sum = el('summary'), pre = el('pre');
        det.append(sum, pre); n.append(det); n._sum = sum; n._pre = pre;
      } else n = el('div', 'msg ' + it.kind);
      streamNodes.set(it.key, n);
    }
    if (it.kind === 'tool') { setText(n._sum, it.title); setText(n._pre, it.body || '(no output)'); }
    else setText(n, it.body);
    want.push(n);
  }
  if (!its.length) {
    let q = streamNodes.get(' quiet'); if (!q) { q = el('p', 'quiet'); streamNodes.set(' quiet', q); }
    setText(q, d ? (r.state === 'earlier' ? r.resume?'A saved conversation. Continue it to talk to it.':'No conversation history is available here.' : 'Nothing said yet.') : 'Loading…');
    want.push(q);
  }
  if (r.state === 'working') {
    let w = streamNodes.get(' working'); if (!w) { w = el('p', 'quiet'); streamNodes.set(' working', w); }
    setText(w, r.status === 'connecting' ? 'Starting…' : 'Working…'); want.push(w);
  }
  want.forEach((n, i) => { if (box.children[i] !== n) box.insertBefore(n, box.children[i] || null); });
  while (box.children.length > want.length) box.lastChild.remove();
  if (nearEnd) { requestAnimationFrame(() => window.scrollTo({top: document.body.scrollHeight})); S.agentScrolled = true; $('latest').hidden = true; }
  else if (its.length) $('latest').hidden = false;

  // the pad: what it needs now
  const b = S.busy.get(id) || '';
  const decision = M.can(r, 'decide') ? r.decision : null;
  $('decision').hidden = !decision;
  if (decision) {
    setText($('decision-title'), r.engineLabel + ' ' + M.decisionVerb(decision.tool));
    setText($('decision-what'), decision.summary);
    setText($('decision-why'), decision.detail || '');
    $('decision-detail').hidden = !decision.detail;
    if ($('decision-detail').dataset.request !== decision.id) { $('decision-detail').open = !!decision.complete; $('decision-detail').dataset.request = decision.id; }
    $('deny').disabled = !!b; $('allow').disabled = !!b;
    setText($('deny'), b === 'deny' ? 'Denying…' : 'Deny');
    setText($('allow').querySelector('.label'), b === 'allow' ? 'Allowing…' : 'Hold to allow');
  }
  paintOmp(d?.engine === 'omp' ? d : null);
  paintQuestions(r, b);
  paintConfiguration(r, b);
  $('rename-agent').hidden = !M.can(r, 'rename'); $('rename-agent').disabled = !!b;
  const canSend = M.can(r, 'send');
  const rep = $('replies');
  rep.hidden = !canSend || !!decision || !S.replies.length;
  const repSig = S.replies.map(x => x.label + '\n' + x.text).join('\n\n') + '/' + b;
  if (rep.dataset.sig !== repSig) {
    rep.dataset.sig = repSig;
    rep.replaceChildren(...S.replies.map(x => {
      const c = el('button', 'chip chip-touch', x.label);
      c.type = 'button'; c.disabled = !!b;
      c.setAttribute('aria-label', x.label + ': sends “' + M.clip(x.text, 80) + '”');
      c.addEventListener('click', () => queueSend(S.agent, x.text, x.label));
      return c;
    }));
  }
  const canResume = M.can(r, 'resume') || M.can(r, 'codex');
  $('saved').hidden = !canResume;
  if (canResume) {
    setText($('saved-text'), r.codexJoin ? 'Codex is running this on the computer. Take it over to steer it from here.' : 'This conversation is saved. Continue it here and it picks up where it left off.');
    setText($('continue'), b === 'resume' ? 'Continuing…' : r.codexJoin ? 'Take over' : 'Continue here');
    $('continue').disabled = !!b;
  }
  $('say').hidden = r.readOnly || !canSend;
  $('say').disabled = !!b;
  $('changes-button').hidden = r.readOnly || !r.cwd;
  $('stop').hidden = !M.can(r, 'stop');
  $('stop').disabled = b === 'stop';
  setText($('stop').querySelector('.label'), b === 'stop' ? 'Stopping…' : 'Hold to stop');
  requestAnimationFrame(() => document.documentElement.style.setProperty('--pad-h', $('pad').offsetHeight + 'px'));
}

window.addEventListener('scroll', () => {
  if (S.view !== 'agent') return;
  const atEnd = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
  if (atEnd) $('latest').hidden = true;
}, {passive: true});
$('latest').addEventListener('click', () => { window.scrollTo({top: document.body.scrollHeight, behavior: 'smooth'}); $('latest').hidden = true; });
$('back').addEventListener('click', () => go('now'));
$('deny').addEventListener('click', () => decide(S.agent, false));
armHold($('allow'), () => decide(S.agent, true));
$('allow').dataset.idle = 'Hold to allow';
armHold($('stop'), () => stopAgent(S.agent));
$('stop').dataset.idle = 'Hold to stop';
$('continue').addEventListener('click', () => resume(S.agent));

// ---------------------------------------------------------------- say something
let recognition = null;
const Speech = window.SpeechRecognition || window.webkitSpeechRecognition;
$('compose-mic').hidden = !Speech;
$('say').addEventListener('click', () => {
  $('compose-text').value = store.get('draft.' + S.agent, '');
  $('compose').showModal();
  $('compose-text').focus();
});
$('compose-text').addEventListener('input', () => store.set('draft.' + S.agent, $('compose-text').value));
$('compose-mic').addEventListener('click', () => {
  if (recognition) { recognition.stop(); return; }
  recognition = new Speech();
  recognition.interimResults = true; recognition.continuous = true;
  recognition.lang = navigator.language || 'en-US';
  const before = $('compose-text').value.trim();
  recognition.onresult = e => {
    let said = '';
    for (const res of e.results) said += res[0].transcript;
    $('compose-text').value = (before ? before + ' ' : '') + said.trim();
  };
  recognition.onend = () => { recognition = null; setText($('compose-mic').lastChild, 'Dictate'); store.set('draft.' + S.agent, $('compose-text').value); };
  recognition.onerror = () => { toast('Dictation isn’t available here. Use the keyboard’s microphone.', true); };
  recognition.start();
  setText($('compose-mic').lastChild, 'Stop dictating');
});
$('compose').addEventListener('close', () => {
  recognition?.stop();
  if ($('compose').returnValue !== 'send') return;
  const text = $('compose-text').value;
  if (!text.trim()) return;
  if (text.length > 16000) { toast(M.WORDS.EMPTY_OR_LONG_MESSAGE, true); return; }
  send(S.agent, text);
});
$('compose-text').addEventListener('keydown', e => {
  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); $('compose-send').click(); }
});

// ---------------------------------------------------------------- changes
$('changes-button').addEventListener('click', () => { S.changes.view = 'unstaged'; $('changes').showModal(); loadChanges(); });
$('changes-close').addEventListener('click', () => $('changes').close());
for (const t of document.querySelectorAll('#changes .segmented button')) {
  t.addEventListener('click', () => { S.changes.view = t.dataset.view; loadChanges(); });
}
async function loadChanges() {
  const id = S.agent, view = S.changes.view;
  for (const t of document.querySelectorAll('#changes .segmented button')) t.setAttribute('aria-selected', String(t.dataset.view === view));
  setText($('changes-summary'), 'Reading…');
  const pre = $('change-lines'); pre.hidden = true; $('change-files').after(pre); // home, before the rows go
  $('change-files').replaceChildren(); S.changes.open = -1;
  try {
    const c = await api('changes/' + id + '?view=' + view, {timeout: 30000});
    if (S.agent !== id || S.changes.view !== view) return;
    const files = view === 'untracked' ? M.parseUntracked(c.diff) : M.parseDiff(c.diff);
    S.changes.files = files;
    setText($('changes-summary'), M.changeSummary(files) + (c.partial ? ' · only part of it' : ''));
    $('change-files').replaceChildren(...files.map((f, i) => {
      const li = el('li'), b = el('button', 'row-open'), dir = f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '';
      b.type = 'button'; b.append(el('span', '', M.baseName(f.path)), ...(dir ? [el('span', 'muted small', dir)] : []));
      b.setAttribute('aria-label', f.path + ', ' + f.added + ' added, ' + f.removed + ' removed');
      b.addEventListener('click', () => showFile(i));
      const stat = el('span', 'stat');
      stat.append(el('span', 'add', '+' + f.added), document.createTextNode(' '), el('span', 'del', '−' + f.removed));
      li.append(b, stat);
      return li;
    }));
  } catch (e) { setText($('changes-summary'), e.message); }
}
function showFile(i) {
  const f = S.changes.files[i], pre = $('change-lines');
  if (S.changes.open === i) { S.changes.open = -1; pre.hidden = true; $('change-files').after(pre); return; }
  S.changes.open = i;
  const spans = [];
  if (f.binary) spans.push(el('span', 'h', 'A binary file.'));
  for (const h of f.hunks) {
    spans.push(el('span', 'h', h.header));
    for (const l of h.lines.slice(0, 600)) spans.push(el('span', l.t === '+' ? 'a' : l.t === '-' ? 'd' : '', (l.t === '\\' ? '\\' : l.t) + l.text));
  }
  pre.replaceChildren(...spans);
  // The lines open under the file that was tapped, not under the whole list.
  const li = $('change-files').children[i];
  if (li) li.append(pre);
  pre.hidden = false;
  pre.scrollTop = 0;
  li?.scrollIntoView?.({block: 'nearest'});
}
$('changes-explain').addEventListener('click', () => { $('changes').close(); queueSend(S.agent, 'Explain the current changes in plain words: what changed, why, and anything unfinished.', 'Explain these'); });
$('changes-commit').addEventListener('click', () => { $('changes').close(); queueSend(S.agent, 'Commit the current changes with a clear message.', 'Commit'); });

// ---------------------------------------------------------------- start an agent
let startProject = '', startEngine = '', startIntent = -1, nativeSelection = '', nativeCursor = '', nativeBrowsing = false;
const nativeSelectionKey = () => [S.hostId || '',startProject,startEngine].join('/');
async function loadProjects() {
  const host = S.hostId;
  try {
    let items = [], after = '';
    for (let i = 0; i < 5; i++) {
      const page = await api('workplaces' + (after ? '?after=' + encodeURIComponent(after) : ''));
      if (S.hostId !== host) return;
      items = items.concat(page.items || []);
      after = page.next || ''; if (!after) break;
    }
    S.projects = items;
  } catch (e) { if (S.hostId !== host) return; S.projects = S.projects || []; toast(e.message, true); }
  paintStart();
  if (!workspaceJob) await recoverWorkspaceJob();
}
let workspaceBusy = false, workspaceRequest = null;
// The answer sits under the buttons that asked: Add existing / New folder, or Prepare Git workspace.
function workspaceSay(text, git) {
  const p = $('workspace-status');
  (git ? $('workspace-job-cancel') : $('workspace-buttons')).after(p);
  setText(p, text);
}
async function prepareWorkspace(create) {
  if (workspaceBusy) return;
  const path = $('workspace-path').value.trim(), host = S.hostId;
  if (!path.startsWith('/')) { workspaceSay('Enter an absolute folder path on the selected computer.'); return; }
  const key = JSON.stringify([host,create,path]);
  if (workspaceRequest?.key !== key) workspaceRequest = {key,id:crypto.randomUUID()};
  const request = workspaceRequest;
  workspaceBusy = true; $('workspace-add').disabled = true; $('workspace-create').disabled = true; $('start-go').disabled = true;
  workspaceSay('Preparing workspace…');
  try {
    const body = await stamp({id:request.id,path,name:M.baseName(path),...(create?{create:true}:{})});
    if (S.hostId !== host) return;
    const result = await api('workplaces',{method:'POST',body});
    if (S.hostId !== host) return;
    if (!result.workplace?.id) throw Error('The workspace response was incomplete. Refresh before retrying.');
    S.projects = [result.workplace,...(S.projects || []).filter(p=>p.id!==result.workplace.id)];
    startProject = result.workplace.id; store.set('project.'+(host || 'here'), startProject);
    if ($('workspace-path').value.trim() === path) $('workspace-path').value = '';
    workspaceRequest = null; workspaceSay(create?'Workspace created.':'Workspace added.');paintStart();
  } catch(e) { if (S.hostId === host) workspaceSay(e.message); }
  finally { workspaceBusy = false; $('workspace-add').disabled = false; $('workspace-create').disabled = false; if (S.hostId !== host) workspaceSay('', false); paintIntents(); }
}
$('workspace-add').addEventListener('click',()=>prepareWorkspace(false));
$('workspace-create').addEventListener('click',()=>prepareWorkspace(true));

let workspaceJob = null, workspaceJobHost = '', workspaceJobTimer = null;
const jobRunning = job => job && ['queued','running'].includes(job.state);
function showWorkspaceJob(job, host) {
  if (S.hostId !== host) return;
  workspaceJob=job; workspaceJobHost=host; workspaceBusy=!!jobRunning(job);
  for(const id of ['workspace-add','workspace-create','workspace-git-start']) $(id).disabled=workspaceBusy;
  $('workspace-job-cancel').hidden=!workspaceBusy;
  workspaceSay((job.phase || 'Preparing workspace…')+(job.state==='failed'&&job.error?' '+M.words(job.error):''),true);
  if(job.state==='completed' && job.workspace){
    S.projects=[job.workspace,...(S.projects || []).filter(p=>p.id!==job.workspace.id)];startProject=job.workspace.id;
    store.set('project.'+(host || 'here'),startProject);
    if($('workspace-path').value.trim()===job.path) $('workspace-path').value='';
    paintStart();
  }
  if(!workspaceBusy)store.set('workspace.pending.'+(host || 'here'),'');
  paintIntents();clearTimeout(workspaceJobTimer);
  if(workspaceBusy) workspaceJobTimer=setTimeout(pollWorkspaceJob,1000);
}
async function pollWorkspaceJob(){
  const job=workspaceJob,host=workspaceJobHost;if(!job || S.hostId!==host || document.hidden)return;
  try{const result=await api('workspace-jobs/'+job.id);if(S.hostId===host && workspaceJob?.id===job.id)showWorkspaceJob(result.job,host);}
  catch(e){if(S.hostId!==host)return;workspaceSay(e.message+' Checking progress again…',true);workspaceJobTimer=setTimeout(pollWorkspaceJob,3000);}
}
document.addEventListener('visibilitychange',()=>{if(!document.hidden && jobRunning(workspaceJob))pollWorkspaceJob();});
async function recoverWorkspaceJob(){
  const host=S.hostId;
  try{const pending=store.get('workspace.pending.'+(host || 'here'),'');const result=await api(pending?'workspace-jobs/'+pending:'workspace-jobs');if(S.hostId!==host)return;const job=result.job || (result.jobs || []).find(jobRunning);if(job)showWorkspaceJob(job,host);}
  catch(e){if(S.hostId===host && e.code==='WORKSPACE_JOB_NOT_FOUND')store.set('workspace.pending.'+(host || 'here'),''); /* Older connectors may not offer jobs. */}
}
$('workspace-git-start').addEventListener('click',async()=>{
  if(workspaceBusy)return;
  const host=S.hostId,kind=$('workspace-git-kind').value,path=$('workspace-path').value.trim(),source=kind==='clone'?$('workspace-source').value.trim():startProject;
  if(!path.startsWith('/') || !source){workspaceSay('Choose a source and an absolute destination folder.',true);return;}
  workspaceBusy=true;for(const id of ['workspace-add','workspace-create','workspace-git-start','start-go'])$(id).disabled=true;
  workspaceSay('Starting preparation…',true);
  try{
    const body=await stamp({id:crypto.randomUUID(),kind,source,path,name:M.baseName(path),...(kind==='worktree'?{branch:$('workspace-branch').value.trim()}:{})});
    if(S.hostId!==host)return;
    store.set('workspace.pending.'+(host || 'here'),body.id);
    const result=await api('workspace-jobs',{method:'POST',body});if(S.hostId!==host)return;showWorkspaceJob(result.job,host);
  }catch(e){if(S.hostId===host){workspaceBusy=false;for(const id of ['workspace-add','workspace-create','workspace-git-start'])$(id).disabled=false;workspaceSay(e.message+' Check preparations before starting again.',true);paintIntents();await recoverWorkspaceJob();}}
  finally{if(S.hostId!==host){workspaceBusy=false;for(const id of ['workspace-add','workspace-create','workspace-git-start'])$(id).disabled=false;paintIntents();}}
});
$('workspace-job-cancel').addEventListener('click',async()=>{
  const job=workspaceJob,host=S.hostId;if(!jobRunning(job) || workspaceJobHost!==host)return;
  try{const body=await stamp({});if(S.hostId!==host)return;const result=await api('workspace-jobs/'+job.id+'/cancel',{method:'POST',body});if(S.hostId===host)showWorkspaceJob(result.job,host);}
  catch(e){if(S.hostId===host)workspaceSay(e.message,true);}
});

function paintStart() {
  if(workspaceJob && workspaceJobHost!==S.hostId){clearTimeout(workspaceJobTimer);workspaceJob=null;workspaceBusy=false;$('workspace-job-cancel').hidden=true;for(const id of ['workspace-add','workspace-create','workspace-git-start'])$(id).disabled=false;workspaceSay('',false);}
  const box = $('projects'), list = (S.projects || []).filter(p => M.createEngines(p).length);
  if (!list.some(p => p.id === startProject)) startProject = store.get('project.' + (S.hostId || 'here'), '');
  if (!list.some(p => p.id === startProject)) startProject = list[0]?.id || '';
  box.replaceChildren(...list.map(p => {
    const b = el('button', '', p.name);
    b.type = 'button'; b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', String(p.id === startProject));
    b.title = p.path || '';
    b.addEventListener('click', () => { startProject = p.id; store.set('project.' + (S.hostId || 'here'), p.id); paintStart(); });
    return b;
  }));
  if (!list.length) box.replaceChildren(el('p', 'muted', S.projects ? 'No configured coding tools can start in these projects. Enable a tool on your computer first.' : 'Reading your projects…'));
  const engines = M.createEngines(list.find(p => p.id === startProject));
  if (!engines.includes(startEngine)) startEngine = engines[0] || '';
  $('create-engines').replaceChildren(...engines.map(engine => {
    const button = el('button', '', M.engineLabel(engine)); button.type = 'button'; button.setAttribute('role', 'radio'); button.setAttribute('aria-checked', String(startEngine === engine));
    button.addEventListener('click', () => { startEngine = engine; paintStart(); }); return button;
  }));
  const selection = nativeSelectionKey();
  if (selection !== nativeSelection) { nativeSelection = selection; nativeCursor = ''; $('native-options').replaceChildren(); setText($('native-status'),''); $('native-more').hidden = true; }
  $('native-sessions').hidden = startEngine !== 'qwen';
  const tiles = $('intents');
  if (!tiles.children.length) {
    tiles.replaceChildren(...M.INTENTS.map((it, i) => {
      const b = el('button', '', it.label);
      b.type = 'button';
      b.addEventListener('click', () => {
        startIntent = startIntent === i ? -1 : i;
        $('start-text').value = startIntent >= 0 ? it.text : '';
        paintIntents();
      });
      return b;
    }));
  }
  paintIntents();
}
function paintIntents() {
  [...$('intents').children].forEach((b, i) => b.setAttribute('aria-pressed', String(i === startIntent)));
  $('start-go').disabled = workspaceBusy || !startProject || !startEngine;
}
async function browseNative(cursor = '') {
  const project = (S.projects || []).find(p => p.id === startProject), key = nativeSelectionKey();
  if (startEngine !== 'qwen' || !project?.path || nativeBrowsing) return;
  nativeBrowsing = true; $('browse-native').disabled = true; $('native-more').disabled = true; setText($('native-status'),'Reading saved conversations…');
  try {
    const page = await api('native-sessions?engine=qwen&cwd=' + encodeURIComponent(project.path) + (cursor ? '&cursor=' + encodeURIComponent(cursor) : ''),{timeout:30000});
    if (nativeSelectionKey() !== key || S.view !== 'start') return;
    nativeCursor = page.next || ''; $('native-more').hidden = !nativeCursor;
    $('native-options').replaceChildren(...(page.items || []).map(item => {
      const button = el('button','native-session big');button.type='button';button.append(el('span','',item.name || 'Saved conversation'),el('small','muted',item.updatedAt ? new Date(item.updatedAt).toLocaleString() : item.nativeId));
      button.addEventListener('click',async()=>{
        if (nativeSelectionKey() !== key || S.view !== 'start' || button.disabled) return;
        if (item.expiresAt <= Date.now()) { toast('Refresh the saved conversations before importing.',true); return; }
        button.disabled=true;
        try {
          const created=await command('import',crypto.randomUUID(),{engine:'qwen',offer:item.offer},'');
          if (nativeSelectionKey() !== key || S.view !== 'start') return;
          const id=created.session;
          if (!id) throw Error('The native session did not return its identity.');
          if (!S.rows.has(id)) S.rows.set(id,M.row({id,engine:'qwen',name:item.name,cwd:item.cwd,status:'connecting',updatedAt:Date.now()}));
          openAgent(id);
        } catch(e) { if (nativeSelectionKey() === key) toast(e.message,true); }
        finally { button.disabled=false; }
      });return button;
    }));
    setText($('native-status'),page.items?.length ? 'Select a conversation to continue here. Qwen will refuse one that another process is writing.' : 'No saved Qwen conversations in this project.');
  } catch(e) { if (nativeSelectionKey() === key) setText($('native-status'),e.message); }
  finally { nativeBrowsing=false;$('browse-native').disabled=false;$('native-more').disabled=false; }
}
$('browse-native').addEventListener('click',()=>browseNative());
$('native-more').addEventListener('click',()=>browseNative(nativeCursor));
$('start-text').addEventListener('input', () => { if (startIntent >= 0 && $('start-text').value !== M.INTENTS[startIntent].text) { startIntent = -1; paintIntents(); } });
$('start-go').addEventListener('click', async () => {
  const project = (S.projects || []).find(p => p.id === startProject);
  if (!project || !M.createEngines(project).includes(startEngine)) return;
  const text = $('start-text').value.trim(), id = crypto.randomUUID(), host = S.hostId;
  $('start-go').disabled = true; setText($('start-go'), 'Starting…');
  try {
    const engine = startEngine;
    const created = await command('create', id, {workplaceId: project.id, engine, name: M.agentName(startIntent >= 0 ? M.INTENTS[startIntent].label : text, project.name)}, '');
    if (S.hostId !== host) return;
    const actualId = created.session || id;
    S.rows.set(actualId, {...M.row({id: actualId, engine, name: M.agentName(text, project.name), cwd: project.path, status: 'connecting', updatedAt: Date.now()}), state: 'working'});
    $('start-text').value = ''; startIntent = -1; paintIntents();
    openAgent(actualId);
    if (text) firstMessage(actualId, text);
  } catch (e) { toast(e.message, true); }
  finally { setText($('start-go'), 'Start'); $('start-go').disabled = workspaceBusy || !startProject || !startEngine; }
});
// the first words go once it's ready for them (up to 30 s)
async function firstMessage(id, text) {
  const until = Date.now() + 30000, host = S.hostId;
  store.set('draft.' + id, text);
  while (Date.now() < until) {
    if (S.agent !== id || S.view !== 'agent' || S.hostId !== host || store.get('draft.' + id, '') !== text) return;
    try {
      const d = await api('sessions/' + id);
      if (S.agent !== id || S.view !== 'agent' || S.hostId !== host || store.get('draft.' + id, '') !== text) return;
      if (d.generation && d.controllable && !M.WORKING.has(d.status)) {
        applyDetail(id, d);
        if (!M.can(S.rows.get(id), 'send')) return;
        await busyWith(id, 'send', async () => { await command('send', id, {text}, d.generation); store.set('draft.' + id, ''); });
        return;
      }
    } catch { /* Keep the first instruction as a draft; never recreate the agent. */ }
    await new Promise(r => setTimeout(r, 600));
  }
  toast('The session is still starting. Your first instruction is saved in Say something.', true);
}

// ---------------------------------------------------------------- more
async function loadReplies() {
  try { const r = await api('replies', {here: true}); if (M.validReplies(r.replies)) { S.replies = r.replies; store.set('replies', r.replies); } }
  catch { /* the last ones known */ }
  paintReplies(); paint();
}
function paintReplies() {
  $('reply-list').replaceChildren(...S.replies.map((r, i) => {
    const li = el('li'), label = el('input'), text = el('textarea'), rm = el('button', 'ghost', 'Remove');
    label.value = r.label; label.maxLength = 24; label.setAttribute('aria-label', 'Name of quick reply ' + (i + 1));
    text.value = r.text; text.rows = 2; text.maxLength = 2000; text.setAttribute('aria-label', 'Words of quick reply ' + (i + 1));
    rm.type = 'button'; rm.setAttribute('aria-label', 'Remove ' + r.label);
    const save = () => saveReplies(S.replies.map((x, j) => j === i ? {label: label.value.trim(), text: text.value.trim()} : x));
    label.addEventListener('change', save); text.addEventListener('change', save);
    rm.addEventListener('click', () => saveReplies(S.replies.filter((_, j) => j !== i)));
    li.append(label, rm, text);
    return li;
  }));
  $('reply-add').disabled = S.replies.length >= 12;
}
async function saveReplies(list, reset = false) {
  if (!reset && !M.validReplies(list)) { toast(M.WORDS.INVALID_REPLIES, true); paintReplies(); return; }
  try {
    const r = await api('replies', {method: 'POST', here: true, body: reset ? {reset: true} : {replies: list}});
    S.replies = r.replies || list; store.set('replies', S.replies);
  } catch (e) { toast(e.message, true); }
  paintReplies(); paint();
}
$('reply-add').addEventListener('click', () => {
  const label = 'Reply ' + (S.replies.length + 1);
  saveReplies([...S.replies, {label, text: 'Tell me what you’ll do next.'}]).then(() => $('reply-list').lastChild?.querySelector('input')?.select());
});
$('reply-reset').addEventListener('click', () => saveReplies(null, true));

async function loadHosts() {
  try { const r = await api('hosts', {here: true}); S.hosts = r.items || []; } catch { S.hosts = []; }
  if (S.hostId && !S.hosts.some(h => h.id === S.hostId)) { S.hostId = ''; store.set('host', ''); }
  paintHosts();
}
function paintHosts() {
  const mk = (id, name, sub) => {
    const li = el('li'), b = el('button', 'row-open');
    b.type = 'button'; b.append(el('span', '', name), el('span', 'muted small', sub));
    b.setAttribute('aria-current', String(id === S.hostId));
    b.addEventListener('click', () => switchHost(id));
    li.append(b);
    if (id === S.hostId) li.append(el('span', 'tag', 'Showing'));
    return li;
  };
  const all = [mk('', S.status?.host || 'This computer', 'The computer this phone is paired with'), ...S.hosts.map(h => mk(h.id, h.name, h.origin))];
  $('host-pick').replaceChildren(...all);
  $('host-list').replaceChildren(...all.map(n => n.cloneNode(true)));
  [...$('host-list').querySelectorAll('button')].forEach((b, i) => b.addEventListener('click', () => switchHost(i ? S.hosts[i - 1].id : '')));
  $('host-button').hidden = false;
}
function switchHost(id) {
  if (id === S.hostId) { $('hosts').close(); return; }
  flushPending(); stopStreams();
  S.hostId = id; store.set('host', id); S.relay = null;
  S.rows.clear(); cardNodes.clear(); earlierNodes.clear(); S.projects = null; S.agent = null; S.detail = null;
  $('hosts').close();
  paintHosts(); go('now'); refresh(); loadReplies();
}
$('earlier').addEventListener('toggle', () => { $('earlier').dataset.touched = '1'; });
$('host-button').addEventListener('click', () => { paintHosts(); $('hosts').showModal(); });
$('hosts').querySelector('[data-close]').addEventListener('click', () => $('hosts').close());
$('host-form').addEventListener('submit', async e => {
  e.preventDefault();
  const link = $('host-link').value.trim();
  if (!link) return;
  try {
    let name = 'Computer';
    try { name = new URL(link).hostname.split('.')[0] || name; } catch { /* the engine says why */ }
    await api('hosts', {method: 'POST', here: true, body: {id: crypto.randomUUID(), name, link, connector: S.status.connector}, timeout: 30000});
    $('host-link').value = '';
    toast('Added.'); loadHosts();
  } catch (err) { toast(err.message, true); }
});

async function loadDevice() {
  try {
    const r = await api('devices', {here: true});
    const me = (r.devices || []).find(d => d.current);
    setText($('device-name'), me?.name || 'This phone');
    setText($('device-host'), r.host || S.status?.host || 'your computer');
  } catch { /* stays as it was */ }
}
if (IN_APP) $('disconnect').hidden = true;  // unpair in Settings > Remote: it takes every part with it
$('disconnect').addEventListener('click', async () => {
  if (!confirm('Disconnect this phone? You’ll need a new code from your computer to use it again.')) return;
  try { await api('logout', {method: 'POST', here: true, body: {}}); } catch { /* already gone */ }
  unpaired('REVOKED');
});

// notifications: only when the engine offers them (web push needs the Home Screen app on iPhone)
async function setupPushRow() {
  let key = null;
  try { key = (await api('push/key', {here: true})).key; } catch { /* not offered */ }
  const row = $('push-toggle').closest('.group');
  const can = !!key && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  row.hidden = !key;
  if (!key) return;
  const reg = await navigator.serviceWorker.ready.catch(() => null);
  const sub = await reg?.pushManager.getSubscription().catch(() => null);
  $('push-toggle').setAttribute('aria-checked', String(!!sub));
  $('push-toggle').disabled = !can;
  if (!can) setText($('push-note'), navigator.standalone === false || /iPhone|iPad/.test(navigator.userAgent)
    ? 'Add Agents to your Home Screen (Share, Add to Home Screen), open it from there, then turn this on.'
    : 'This browser can’t show notifications from here.');
  $('push-toggle').onclick = async () => {
    const on = $('push-toggle').getAttribute('aria-checked') !== 'true';
    try {
      if (on) {
        if (await Notification.requestPermission() !== 'granted') { toast('Notifications are off for Agents in Settings.', true); return; }
        const s = await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: b64url(key)});
        await api('push/subscribe', {method: 'POST', here: true, body: s.toJSON()});
      } else {
        const s = await reg.pushManager.getSubscription();
        if (s) { await api('push/unsubscribe', {method: 'POST', here: true, body: {endpoint: s.endpoint}}).catch(() => {}); await s.unsubscribe(); }
      }
      $('push-toggle').setAttribute('aria-checked', String(on));
      toast(on ? 'You’ll get a notification when an agent needs you.' : 'Notifications off.');
    } catch (e) { toast(e.message, true); }
  };
}
function b64url(s) {
  const raw = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

// ---------------------------------------------------------------- navigation
function go(view) {
  if (view !== 'agent') { S.agent = null; omp.bind(null); }
  S.view = view;
  for (const v of ['now', 'agent', 'start', 'more']) $(v).hidden = v !== view;
  document.body.classList.toggle('in-agent', view === 'agent');
  for (const t of document.querySelectorAll('.tabs button')) {
    const on = t.dataset.go === view || (view === 'agent' && t.dataset.go === 'now');
    if (on) t.setAttribute('aria-current', 'page'); else t.removeAttribute('aria-current');
  }
  if (view !== 'agent') { S.detailStream?.close(); S.detailStream = null; S.detailKey = ''; clearTimeout(S.detailTimer); $('latest').hidden = true; window.scrollTo({top: 0}); }
  if (view === 'start') loadProjects();
  if (view === 'more') { paintReplies(); paintHosts(); loadDevice(); }
  if (view === 'agent') syncDetail();
  paint();
}
for (const b of document.querySelectorAll('[data-go]')) b.addEventListener('click', () => go(b.dataset.go));

// ---------------------------------------------------------------- toast
let toastTimer = 0, toastAction = null;
function toast(text, fail = false, action = null) {
  const t = $('toast');
  if (!$('undo').hidden && !fail) return;   // the undo strip has the place; failures still say why
  setText(t, text); t.className = 'toast' + (fail ? ' fail' : ''); t.hidden = false;
  toastAction = action; t.style.cursor = action ? 'pointer' : '';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; toastAction = null; }, action ? 6000 : fail ? 5000 : 2500);
}
$('toast').addEventListener('click', () => { const a = toastAction; $('toast').hidden = true; toastAction = null; a?.(); });

// messages from the service worker (a notification was tapped while the app was open)
navigator.serviceWorker?.addEventListener('message', e => { if (e.data?.agent && /^[a-f0-9-]{36}$/i.test(e.data.agent)) openAgent(e.data.agent); });

boot();
