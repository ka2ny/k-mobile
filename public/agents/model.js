// The phone remote's logic, apart from drawing (tests/khole/remote-model.test.mjs runs it in Node).
// The same words and order as the desktop (configs/quickshell/views/AgentsModel.js and
// scripts/khole-agents): Needs you, Your turn, Working, Earlier, Can't reach.

export const NEEDS = new Set(['awaiting-permission', 'awaiting-input', 'needs-native-input']);
export const WORKING = new Set(['running', 'busy', 'connecting', 'stopping', 'live-busy', 'live-queued', 'live-transition', 'dispatching']);
export const ORDER = ['needs', 'turn', 'working', 'earlier', 'unreachable'];
export const TITLES = {needs: 'Needs you', turn: 'Your turn', working: 'Working', earlier: 'Earlier', unreachable: "Can't reach"};
export const ENGINES = {'claude-code': 'Claude Code', codex: 'Codex', omp: 'OMP', dsh: 'DeepSeek Harness', opencode: 'OpenCode', gemini: 'Gemini', qwen: 'Qwen', cursor: 'Cursor', kimi: 'Kimi Code', copilot: 'GitHub Copilot', goose: 'Goose', aider: 'Aider'};

export function stateOf(s) {
  const status = s.status || '';
  if (NEEDS.has(status)) return 'needs';
  if (['live-unavailable', 'disconnected', 'unavailable'].includes(status)) return 'unreachable';
  if (WORKING.has(status)) return 'working';
  if (s.controllable || s.ompControl) return 'turn';
  return 'earlier';
}

export const baseName = p => String(p || '').split('/').filter(Boolean).pop() || '';

// a session from /api/sessions as the remote shows it
export function row(s, seen = {}) {
  const state = stateOf(s), engine = s.engine || 'claude-code', updatedAt = Number(s.updatedAt) || 0;
  return {
    id: s.id, name: s.name || baseName(s.cwd) || 'Agent', cwd: s.cwd || '', project: baseName(s.cwd),
    engine, engineLabel: ENGINES[engine] || engine, state, status: s.status || '',
    controllable: !!s.controllable, controls: s.controls, peer: !!s.peerControl, resume: !!s.resumeAvailable, updatedAt, generation: s.generation ?? null,
    readOnly: engine === 'omp', codexJoin: engine === 'codex' && !s.controllable,
    unseen: state === 'turn' && updatedAt > (Number(seen[s.id]) || 0),
    decision: null, question: s.question || null, configuration: s.configuration || null, tail: ''
  };
}

// what a decision is about: the command, the file, else the input (as khole-agents describe_permission)
export function describePermission(p) {
  if (!p) return null;
  const tool = String(p.tool || 'Tool'), raw = p.input;
  if (tool === 'apply_patch' && raw && Array.isArray(raw.changes)) return {id:p.id,tool,summary:raw.changes.map(c=>String(c.path || '')).join('\n'),detail:JSON.stringify(raw,null,2),generation:p.generation ?? null,complete:true};
  if (raw && typeof raw.command === 'string' && (tool === 'exec_command' || raw.command.length > 4000)) return {id:p.id,tool,summary:raw.command,detail:JSON.stringify(raw,null,2),generation:p.generation ?? null,complete:true};
  let summary = '', detail = '';
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    if (typeof raw.command === 'string') { summary = raw.command; if (typeof raw.description === 'string') detail = raw.description; }
    else if (typeof raw.file_path === 'string') { summary = raw.file_path; const body = raw.new_string || raw.content || ''; if (typeof body === 'string') detail = body; }
    else if (typeof raw.url === 'string') summary = raw.url;
    else if (typeof raw.pattern === 'string') summary = raw.pattern;
  }
  if (!summary) summary = typeof raw === 'string' ? raw : JSON.stringify(raw, null, 2);
  return {id: p.id, tool, summary: String(summary).slice(0, 4000), detail: String(detail).slice(0, 4000), generation: p.generation ?? null};
}

export function unavailable(r) {
  return {...r, state: 'unreachable', status: 'live-unavailable', controllable: false,
    generation: null, decision: null, question: null, configuration: null, codexJoin: false, resume: false, controls: {}};
}

// A listing supplies connection authority; retain readable content, but retain a
// pending decision only while that exact connection generation is still current.
export function mergeSummary(previous, summary, seen = {}) {
  const next = row(summary, seen);
  if (!previous) return next;
  next.tail = previous.tail; next.messages = previous.messages;
  if (next.controllable && next.generation && next.generation === previous.generation && next.state === 'needs')
    { next.decision = previous.decision; next.question = 'question' in summary ? summary.question : previous.question; }
  if (next.controllable && next.generation && next.generation === previous.generation && next.controls?.configure === true) next.configuration = 'configuration' in summary ? summary.configuration : previous.configuration;
  return next;
}

// A live card from /api/activity-stream over the session's row. False and null
// are state changes. Never resurrect a permission after loss of its source.
export function applyCard(r, c) {
  if (!r || !c) return r;
  if (c.available === false) return unavailable(r);
  if (c.control === null) r = {...r, controllable: false, generation: null, decision: null, question: null, configuration: null, controls: {}, codexJoin: r.engine === 'codex'};
  const control = c.control || {}, status = c.status || control.status || r.status;
  const out = {...r, status, state: stateOf({...r, ...control, status})};
  if (c.text !== undefined) out.tail = String(c.text || '').slice(-6000);
  if ('controllable' in control) {
    out.controllable = !!control.controllable;
    out.codexJoin = out.engine === 'codex' && !out.controllable;
  }
  if ('controls' in control) out.controls = control.controls;
  else if (control.controllable === true && (!r.controllable || ('generation' in control && control.generation !== r.generation))) out.controls = undefined;
  if ('resumeAvailable' in control) out.resume = !!control.resumeAvailable;
  if ('peerControl' in control) out.peer = !!control.peerControl;
  if ('generation' in control) {
    out.generation = control.generation;
    if (out.generation !== r.generation) { out.decision = null; out.question = null; out.configuration = null; }
  }
  if ('configuration' in control) out.configuration = control.configuration;
  if ('question' in control) out.question = control.question;
  if ('permission' in control) out.decision = describePermission(control.permission);
  if (!out.controllable || out.generation === null || out.readOnly) { out.decision = null; out.question = null; out.configuration = null; }
  if (out.decision) out.state = 'needs';
  if (Array.isArray(control.messages) && control.messages.length) out.messages = control.messages;
  return out;
}

export function sortRows(rows) {
  return rows.slice().sort((a, b) => ORDER.indexOf(a.state) - ORDER.indexOf(b.state) || b.updatedAt - a.updatedAt);
}

export function groups(rows) {
  const sorted = sortRows(rows);
  return ORDER.map(key => ({key, title: TITLES[key], rows: sorted.filter(r => r.state === key)})).filter(g => g.rows.length);
}

export function counts(rows) {
  const c = {needs: 0, turn: 0, working: 0, earlier: 0, unreachable: 0};
  for (const r of rows) c[r.state]++;
  return c;
}

export function summary(c) {
  const parts = [];
  if (c.needs) parts.push(c.needs + (c.needs === 1 ? ' needs you' : ' need you'));
  if (c.working) parts.push(c.working + ' working');
  if (c.turn) parts.push(c.turn + ' waiting for you');
  return parts.join(' · ') || 'Nothing is running.';
}

export function stateWords(r) {
  if (r.state === 'needs') return 'Needs you';
  if (r.state === 'working') return r.status === 'connecting' ? 'Starting' : r.status === 'stopping' ? 'Stopping' : 'Working';
  if (r.state === 'turn') return 'Your turn';
  if (r.state === 'unreachable') return "Can't reach";
  return r.resume ? 'Saved · can continue' : 'Saved';
}

export function decisionVerb(tool) {
  const t = String(tool || '');
  if (['Bash', 'shell', 'exec_command', 'local_shell'].includes(t)) return 'wants to run';
  if (/^(Edit|Write|MultiEdit|NotebookEdit|apply_patch)$/.test(t)) return 'wants to change a file';
  if (t === 'Read') return 'wants to read a file';
  if (t === 'WebFetch' || t === 'WebSearch') return 'wants to look on the web';
  return 'wants to use ' + t;
}

export function age(ms, now = Date.now()) {
  if (!ms) return '';
  const s = Math.max(0, Math.round((now - ms) / 1000));
  if (s < 45) return 'just now';
  if (s < 3600) return Math.max(1, Math.round(s / 60)) + ' min';
  if (s < 86400) return Math.round(s / 3600) + ' h';
  if (s < 172800) return 'yesterday';
  return Math.round(s / 86400) + ' days';
}

// the live tail as lines (role markers out)
export function tailLines(tail, n = 8) {
  const lines = String(tail || '').split('\n').filter(l => !/^(USER|ASSISTANT|TOOL)$/.test(l.trim()));
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
  return lines.slice(-n);
}

export function lastWords(r) {
  const msgs = r.messages || [];
  for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i].role === 'assistant' && String(msgs[i].text || '').trim()) return clip(msgs[i].text, 200);
  const lines = tailLines(r.tail, 50).filter(l => l.trim());
  return lines.length ? clip(lines[lines.length - 1], 200) : '';
}

export function clip(s, n) {
  s = String(s || '').replace(/\s+/g, ' ').trim();
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// the conversation: your words, the agent's words, tool steps folded to one line
export function items(messages) {
  const out = [];
  for (const [i, m] of (messages || []).entries()) {
    const text = String(m.text || '');
    if (m.role === 'tool') {
      const [head, ...rest] = text.split('\n');
      out.push({key: m.id || 't' + i, kind: 'tool', title: clip(head, 120), body: rest.join('\n').trim()});
    } else if (text.trim()) out.push({key: m.id || 'm' + i, kind: m.role === 'user' ? 'you' : 'agent', body: text});
  }
  return out;
}

export function can(r, what) {
  if (!r || r.readOnly) return false;
  const action = what === 'decide' ? 'permission' : what;
  if (['send', 'stop', 'decide', 'terminal', 'question', 'rename', 'configure'].includes(what) && r.controls !== undefined && (!r.controls || r.controls[action] !== true)) return false;
  if (what === 'configure') return configurationKey(r) !== '';
  if (what === 'question') return questionKey(r) !== '';
  if (what === 'rename') return !!r.controllable && !!r.generation && r.controls?.rename === true;
  if (what === 'terminal') return !!r.controllable && r.controls?.terminal === true && r.state === 'turn';
  if (what === 'send') return !!r.controllable && (r.state === 'turn' || r.state === 'working');
  if (what === 'stop') return !!r.controllable && !r.peer && (r.state === 'working' || r.state === 'needs');
  if (what === 'resume') return r.state === 'earlier' && r.resume;
  if (what === 'codex') return r.codexJoin && r.state !== 'working';
  if (what === 'decide') return !!r.controllable && r.state === 'needs' && !!r.decision;
  return false;
}

export function validReplies(list) {
  return Array.isArray(list) && list.length <= 12 && list.every(r => r && typeof r.label === 'string' && typeof r.text === 'string'
    && r.label.trim() && r.label.trim().length <= 24 && r.text.trim() && r.text.length <= 2000);
}

// the engine's codes, in words (the same sentences as khole-agents)
export const WORDS = {
  WORKSPACE_GIT_FAILED: 'Git could not finish. Check the repository, new branch name and Git authentication on the computer.',
  INVALID_REPOSITORY_URL: 'Use an HTTPS or SSH repository address without embedded tokens or query parameters.',
  INVALID_WORKSPACE_BRANCH: 'Choose a valid new Git branch name.',
  WORKSPACE_JOBS_BUSY: 'Two workspace preparations are running. Wait or cancel one.',
  WORKSPACE_JOB_NOT_FOUND: 'This preparation is not available to this device.',

  WORKPLACE_PATH_REJECTED: 'Choose a folder inside registered project roots, with an existing parent folder.',
  WORKPLACE_EXISTS: 'That folder already exists. Choose Add existing to register it.',
  WORKPLACE_CREATE_FAILED: 'The folder could not be created. Check its parent folder and permissions.',
  WORKPLACE_REGISTRATION_FAILED: 'The folder was created but could not be registered. Choose Add existing; your files were kept.',

  PAIR_REQUIRED: 'This phone isn’t paired. Pair it from your computer: Agents, then Use it from your phone.',
  REVOKED: 'This phone was disconnected. Pair it again from your computer.',
  PAIR_EXPIRED: 'That code expired. Make a new one on your computer.',
  PAIR_INVALID: 'That code was already used or isn’t valid. Make a new one on your computer.',
  PAIR_RATE_LIMIT: 'Too many tries. Wait five minutes.',
  EMPTY_OR_LONG_MESSAGE: 'Write something first (at most 16,000 characters).',
  STALE_TARGET: 'The agent moved on meanwhile. Try again.',
  ACP_AUTH_REQUIRED: 'Sign in to this coding tool on your computer, then start or resume it again.',
  ACP_NATIVE_REJECTED: 'The coding tool refused this action. Check its native account and workspace policy.',
  ACP_DISCONNECTED: 'The coding tool disconnected. Its unfinished actions have not been replayed.',
  OPENCODE_DISCONNECTED: 'The OpenCode server is disconnected. Check its connection on your computer.',
  STALE_CONFIGURATION: 'The session settings changed. Refresh and choose again.',
  INVALID_CONFIGURATION: 'Choose a setting offered by this agent.',
  ACP_SESSION_IN_USE: 'This conversation is already open in another native process.',
  ACP_OWNERSHIP_LOST: 'The native agent lost exclusive access. Reconnect explicitly.',
  ACP_WORKSPACE_UNTRUSTED: 'Review project trust in the native tool on your computer, then start or resume here.',
  ACP_CONFIG_UNAVAILABLE: 'Session settings are not available right now.',
  STALE_QUESTION: 'This question was replaced or already answered.',
  INVALID_ANSWER: 'Complete the current question using its available choices.',
  ENGINE_CREATE_UNAVAILABLE: 'This coding tool has no configured launcher. Check Agents setup on your computer.',
  STALE_PERMISSION: 'That decision was already answered.',
  INVALID_PERMISSION: 'There’s no decision waiting.',
  OUTCOME_UNKNOWN: 'Sent, but the agent didn’t confirm. Check the conversation before sending again.',
  RUNTIME_LIMIT: 'Eight agents are already running. Stop one first.',
  WORKSPACE_REJECTED: 'That folder isn’t in your projects.',
  SESSION_ALREADY_RUNNING: 'It’s already running.',
  SESSION_NOT_FOUND: 'That agent isn’t there any more.',
  RESUME_UNAVAILABLE: 'This session cannot resume here right now. Check its connection, native resume support and workspace configuration.',
  LAUNCH_FAILED: 'Claude Code didn’t start on the computer.',
  DSH_DISCONNECTED: 'dsh is disconnected. Check its Web host and reconnect from Agents on your computer.',
  DSH_NATIVE_REJECTED: 'dsh refused this operation. Check its workspace trust and native tool policy.',
  DSH_CONNECTION_INVALID: 'Reconnect dsh from Agents on your computer using its current local launch link.',
  OMP_VIEW_ONLY: 'Use the native OMP connection controls for this session.',
  OMP_LIVE_UNAVAILABLE: 'Native OMP observation is unavailable. Enable its identity extension on the computer.',
  OMP_CONTROLS_DISABLED: 'Enable the native OMP admission extension and connector control configuration first.',
  OMP_OBSERVATION_REQUIRED: 'Connect live OMP status before enabling sending.',
  OMP_CONNECTION_CHANGED: 'The native OMP connection changed. Reconnect explicitly.',
  OMP_OUTCOME_UNKNOWN: 'No confirmed native receipt. Your draft and request ID are retained; check the receipt.',
  OMP_PENDING_RECEIPT: 'Check the saved native receipt before sending another request.',
  OMP_SEND_UNAVAILABLE: 'Wait for this native session to be idle and its previous receipt to settle.',
  OMP_TEXT_INVALID: 'OMP accepts plain text up to 16 KiB here; slash commands and @ references stay native.',
  OMP_STATE_UNSAFE: 'Local receipt storage is unavailable or invalid. Sending is disabled.',
  OMP_STORAGE_LOCK_UNAVAILABLE: 'This browser cannot protect native command receipts across tabs. Use a browser with Web Locks.',
  OMP_INTERRUPT_UNAVAILABLE: 'Only a turn started here can be stopped through this connection.',
  OMP_DISCONNECT_PENDING: 'Disconnected locally; native confirmation is pending.',
  OMP_RECEIPT_NOT_FOUND: 'No saved receipt is available for this native operation.',
  NATIVE_OFFER_EXPIRED: 'Refresh the saved conversations and select it again.',
  NATIVE_DISCOVERY_UNAVAILABLE: 'This tool does not offer qualified saved-session discovery here.',

  CODEX_JOIN_UNAVAILABLE: 'Codex can be taken over only while it’s idle.',
  CHANGES_NOT_GIT: 'This project isn’t a Git repository.',
  CHANGES_BUSY: 'Two reviews are already running. Try again shortly.',
  INVALID_REPLIES: 'Each quick reply needs a name (24 characters) and its words.',
  BUSY: 'The computer is busy. Try again in a moment.',
  CONNECTOR_STOPPING: 'Agents is restarting on the computer.',
  HOST_UNAVAILABLE: 'That computer isn’t answering.',
  HOST_ACCESS_CHANGED: 'That computer’s access changed. Try again.',
  WRONG_CONNECTOR: 'That went to the wrong computer. Try again.',
  HOST_PAIR_INVALID: 'That isn’t a pairing link. Make one on the other computer: Agents, Use it from your phone.',
  ACTIVITY_STREAM_LIMIT: 'Too many live views are open on this phone.',
  OFFLINE: 'Can’t reach your computer. Is Tailscale on?'
};
export const words = code => WORDS[code] || String(code || 'Something went wrong').replace(/_/g, ' ').toLowerCase().replace(/^./, c => c.toUpperCase()) + '.';

export const INTENTS = [
  {label: 'Pick up where I left off', text: 'Look at the project’s current state and recent changes, then continue the work in progress. Tell me what you’re doing first.'},
  {label: 'Fix the failing tests', text: 'Run the tests, find what fails and fix it. Show me what you changed.'},
  {label: 'Review my last changes', text: 'Review the changes since the last commit and point out bugs, risks and anything unfinished.'}
];

// git diff text → files with hunks (the same shape as khole-agents parse_diff)
export function parseDiff(text, limitFiles = 300) {
  const files = []; let cur = null, hunk = null;
  for (const line of String(text || '').split('\n')) {
    if (line.startsWith('diff --git ')) {
      const m = /^diff --git a\/(.*) b\/(.*)$/.exec(line);
      cur = {path: m ? m[2] : line.slice(11), status: 'modified', added: 0, removed: 0, hunks: [], binary: false};
      files.push(cur); hunk = null;
      if (files.length > limitFiles) break;
    } else if (!cur) continue;
    else if (line.startsWith('new file')) cur.status = 'added';
    else if (line.startsWith('deleted file')) cur.status = 'deleted';
    else if (line.startsWith('rename from') || line.startsWith('similarity index')) cur.status = 'renamed';
    else if (line.startsWith('Binary files')) cur.binary = true;
    else if (line.startsWith('@@')) { hunk = {header: line, lines: []}; cur.hunks.push(hunk); }
    else if (hunk && '+- \\'.includes(line[0] || '#')) {
      if (line[0] === '+' && !line.startsWith('+++')) cur.added++;
      else if (line[0] === '-' && !line.startsWith('---')) cur.removed++;
      if (hunk.lines.length < 2000) hunk.lines.push({t: line[0], text: line.slice(1)});
    }
  }
  return files;
}

// the connector's untracked capture: 'Untracked file "<name>"' then the file's text
export function parseUntracked(text) {
  const files = []; let cur = null;
  for (const line of String(text || '').split('\n')) {
    if (line.startsWith('Untracked file ')) {
      const raw = line.slice(15); let name = raw;
      try { name = JSON.parse(raw); } catch { /* a plain name */ }
      cur = {path: name, status: 'added', added: 0, removed: 0, binary: false, hunks: [{header: 'new file', lines: []}]};
      files.push(cur);
    } else if (cur) {
      cur.added++;
      if (cur.hunks[0].lines.length < 2000) cur.hunks[0].lines.push({t: '+', text: line});
    }
  }
  for (const f of files) { const l = f.hunks[0].lines; while (l.length && !l[l.length - 1].text) { l.pop(); f.added--; } }
  return files;
}

// one sentence for the Changes sheet
export function changeSummary(files) {
  if (!files.length) return 'Nothing here.';
  const a = files.reduce((n, f) => n + f.added, 0), d = files.reduce((n, f) => n + f.removed, 0);
  return files.length + (files.length === 1 ? ' file' : ' files') + ' · +' + a + ' −' + d;
}

// the cards the list stream follows: everything not finished, newest first, at most 16
export function streamIds(rows) {
  return sortRows(rows.filter(r => r.state !== 'earlier' && !r.readOnly)).slice(0, 16).map(r => r.id).sort();
}

// a short name for a new agent from what you asked
export function agentName(text, project) {
  const t = clip(text, 48);
  return t || (project ? 'Work on ' + project : 'New agent');
}

export function engineLabel(engine) {
    return ({"claude-code":"Claude Code",codex:"Codex",omp:"OMP",dsh:"DeepSeek Harness",opencode:"OpenCode",gemini:"Gemini",qwen:"Qwen",cursor:"Cursor",kimi:"Kimi Code",copilot:"GitHub Copilot",goose:"Goose",aider:"Aider"})[engine] || engine || "Agent"
}
export function createEngines(project) {
    if (!project) return []
    if (Array.isArray(project.createEngines)) return project.createEngines.filter(function(e,i,a){ return typeof e === "string" && e !== "" && a.indexOf(e) === i })
    return project.canCreateClaude === false ? [] : ["claude-code"]
}
export function questionKey(row) {
    var q = row && row.question
    return row && row.controllable && row.generation && q && (!q.expiresAt || q.expiresAt > Date.now()) && q.generation === row.generation && row.controls && row.controls.question === true ? row.id + "/" + row.generation + "/" + q.id : ""
}
export function questionAnswers(question, draft) {
    if (!question || !Array.isArray(question.questions) || !question.questions.length) return null
    var out = []
    for (var q of question.questions) {
        var a = (draft || {})[q.id] || {}, selected = Array.isArray(a.selected) ? a.selected : [], custom = typeof a.custom === "string" ? a.custom.trim() : ""
        if (selected.some(function(v,i){return typeof v !== "string" || selected.indexOf(v) !== i || !q.options.some(function(o){return o.label === v})}) || custom.length > 12000 || custom && !q.allowCustom || (!q.multiple && selected.length + (custom ? 1 : 0) > 1) || (!selected.length && !custom)) return null
        out.push(Object.assign({id:q.id,selected:selected.slice()},custom ? {custom:custom} : {}))
    }
    return out
}

export function configurationKey(row) {
    var c = row && row.configuration
    return row && !row.readOnly && row.controllable && row.generation && row.controls && row.controls.configure === true && c && c.available && c.generation === row.generation && Number.isSafeInteger(c.revision) && Array.isArray(c.options) && c.options.length ? row.id + "/" + row.generation + "/" + c.revision : ""
}
