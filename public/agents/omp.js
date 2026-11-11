// OMP uses its native admission protocol, separate from generic agent commands.
// A retained operation is inspected by receipt only; it is never sent again.
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const SEND = new Set(['preparing','committing','admitted','dispatched','completed','failed','rejected','unknown']);
const STOP = new Set(['submitting','requested','settled','rejected','unknown']);
const fail = code => Object.assign(new Error(code), {code});
const clone = value => JSON.parse(JSON.stringify(value));
const scopeOf = context => JSON.stringify([context.host || '',context.connector,context.deviceId,context.relayAccess || '']);

export function ompState(detail, saved = {}, context = {}) {
  const live = detail?.ompLive || {}, control = detail?.ompControl || {}, target = control.target || {};
  const same = detail?.engine === 'omp' && live.connection === 'connected' && control.observation === live.version &&
    control.target && UUID.test(target.runtime || '') && target.leaf === live.leaf;
  const connected = !!(same && control.state === 'connected' && UUID.test(control.connection || ''));
  const online = context.online !== false && context.permit !== false;
  const blocked = !!(saved.off || saved.invalid), own = saved.send?.command;
  const canInterrupt = connected && !!control.interrupt && !!own && target.runtime === own.target?.runtime &&
    Number.isSafeInteger(target.epoch) && Number.isSafeInteger(own.target?.epoch) && target.epoch > own.target.epoch;
  return {
    connected, readOnly: !connected, pending: saved.send || null, stopping: saved.interrupt || null,
    disconnectPending: !!saved.off, storageError: !!saved.invalid,
    canObserve: online && !blocked && ['available','ended'].includes(live.connection) && UUID.test(live.version || '') && UUID.test(live.runtime || '') && Number.isSafeInteger(live.revision),
    canConnect: online && !blocked && !!same && control.state === 'available',
    canDisconnect: online && (saved.off || UUID.test(live.version || '') && ['connected','unavailable'].includes(live.connection)) ? true : false,
    canSend: online && connected && !blocked && !saved.send && !saved.interrupt && live.activity === 'idle',
    canInterrupt: online && canInterrupt && !blocked && !saved.interrupt
  };
}

/**
 * api(path,{method,body}) uses the phone's JSON API helper. context() must return
 * the selected host's {connector,deviceId,relayAccess?,host?,online,permit}.
 * storage is the native getItem/setItem storage interface: writes must succeed.
 * bind the selected detail on every poll; bind(null) when leaving its surface.
 */
export class OmpActions {
  constructor({api,context,storage = globalThis.localStorage,locks = globalThis.navigator?.locks}) {
    Object.assign(this,{api,context,storage,locks,detail:null,busy:false});
  }
  key(id,context = this.context()) {
    if (!UUID.test(id || '') || !context.connector || !context.deviceId) throw fail('OMP_CONNECTION_CHANGED');
    return 'agents.omp.' + encodeURIComponent(scopeOf(context)) + '.' + id;
  }
  read(key) {
    try {
      const raw = this.storage.getItem(key);
      if (raw === null) return {};
      if (raw.length > 131072) throw Error();
      const data = JSON.parse(raw);
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw Error();
      for (const kind of ['send','interrupt']) {
        if (data[kind] === undefined) continue;
        const command = data[kind]?.command;
        if (!command || !UUID.test(command.id || '')) throw Error();
        if (kind === 'send' && (!UUID.test(command.target?.runtime || '') || !Number.isSafeInteger(command.target?.epoch) || typeof command.text !== 'string')) throw Error();
        if (kind === 'interrupt' && (!UUID.test(command.operationId || '') || !UUID.test(command.runtime || '') || !Number.isSafeInteger(command.epoch))) throw Error();
      }
      if (data.off !== undefined && !UUID.test(data.off?.version || '')) throw Error();
      return data;
    } catch { throw fail('OMP_STATE_UNSAFE'); }
  }
  write(key,data) {
    try {
      const raw = JSON.stringify(data);
      this.storage.setItem(key,raw);
      if (this.storage.getItem(key) !== raw) throw Error();
    } catch { throw fail('OMP_STATE_UNSAFE'); }
  }
  bind(detail) {
    this.detail = detail?.engine === 'omp' ? clone(detail) : null;
    return this.state();
  }
  state() {
    const context = this.context();
    let saved = {};
    if (this.detail) try { saved = this.read(this.key(this.detail.id,context)); } catch { saved = {invalid:true}; }
    const state = ompState(this.detail,saved,context);
    if (this.busy) for (const key of ['canObserve','canConnect','canDisconnect','canSend','canInterrupt']) state[key] = false;
    return state;
  }
  capture() {
    const context = {...this.context()}, detail = this.detail;
    if (!detail || context.online === false || context.permit === false || this.busy) throw fail('OMP_CONNECTION_CHANGED');
    const key = this.key(detail.id,context);
    return {context,scope:scopeOf(context),detail:clone(detail),key,saved:this.read(key)};
  }
  assertCurrent(snapshot) {
    if (scopeOf(this.context()) !== snapshot.scope || this.detail?.id !== snapshot.detail.id || this.context().online === false || this.context().permit === false)
      throw fail('OMP_CONNECTION_CHANGED');
  }
  body(snapshot,action,extra = {}) {
    return {connector:snapshot.context.connector,...(snapshot.context.relayAccess ? {relayAccess:snapshot.context.relayAccess} : {}),action,...extra};
  }
  async post(snapshot,action,extra = {},observation = false) {
    this.assertCurrent(snapshot);
    return this.api((observation ? 'omp-observation/' : 'omp-control/') + snapshot.detail.id,
      {method:'POST',body:this.body(snapshot,action,extra)});
  }
  async locked(run) {
    const snapshot = this.capture();
    if (!this.locks?.request) throw fail('OMP_STORAGE_LOCK_UNAVAILABLE');
    return this.locks.request(snapshot.key,{mode:'exclusive',ifAvailable:true},lock => {
      if (!lock) throw fail('OMP_BUSY');
      this.assertCurrent(snapshot);
      if (JSON.stringify(this.detail.ompControl) !== JSON.stringify(snapshot.detail.ompControl) || JSON.stringify(this.detail.ompLive) !== JSON.stringify(snapshot.detail.ompLive)) throw fail('OMP_CONNECTION_CHANGED');
      return run();
    });
  }
  observe() { return this.locked(() => this._observe()); }
  connect() { return this.locked(() => this._connect()); }
  disconnect() { return this.locked(() => this._disconnect()); }
  send(text) { return this.locked(() => this._send(text)); }
  interrupt() { return this.locked(() => this._interrupt()); }
  receipt(interrupt = false) { return this.locked(() => this._receipt(interrupt)); }
  async _observe() {
    const s = this.capture(); if (!ompState(s.detail,s.saved,s.context).canObserve) throw fail('OMP_LIVE_UNAVAILABLE');
    const v = s.detail.ompLive; this.busy = true;
    try { const result = await this.post(s,'connect',{version:v.version,runtime:v.runtime,revision:v.revision},true); this.assertCurrent(s); return result; }
    finally { this.busy = false; }
  }
  async _connect() {
    const s = this.capture(); if (!ompState(s.detail,s.saved,s.context).canConnect) throw fail('OMP_OBSERVATION_REQUIRED');
    const recovery = s.saved.send?.command?.id || s.saved.interrupt?.command?.operationId; this.busy = true;
    try { const result = await this.post(s,'connect',{offer:s.detail.ompControl,...(recovery ? {recovery} : {})}); this.assertCurrent(s); return result; }
    finally { this.busy = false; }
  }
  async _disconnect() {
    const s = this.capture(); if (!ompState(s.detail,s.saved,s.context).canDisconnect) throw fail('OMP_LIVE_UNAVAILABLE');
    if (!s.saved.off) { s.saved.off = {version:s.detail.ompLive.version}; this.write(s.key,s.saved); }
    this.busy = true;
    try {
      const result = await this.post(s,'disconnect',s.saved.off,true);
      if (result.disconnected !== true) throw fail('OMP_DISCONNECT_PENDING');
      delete s.saved.off; this.write(s.key,s.saved); this.assertCurrent(s); return result;
    } finally { this.busy = false; }
  }
  applySend(snapshot,receipt) {
    if (!receipt || receipt.id !== snapshot.saved.send?.command?.id || !SEND.has(receipt.state) || !['preserve','clear-if-unchanged'].includes(receipt.draft)) throw fail('OMP_ADMISSION_REPLY_INVALID');
    const submittedText = snapshot.saved.send.command.text;
    snapshot.saved.send.receipt = receipt;
    if (['completed','failed','rejected'].includes(receipt.state)) delete snapshot.saved.send;
    this.write(snapshot.key,snapshot.saved);
    return {receipt,submittedText,clearDraft:receipt.draft === 'clear-if-unchanged'};
  }
  async _send(text) {
    if (typeof text !== 'string' || !text.trim() || new TextEncoder().encode(text).length > 16384 || /[\u0000\uD800-\uDFFF]/u.test(text) || /^\s*\//.test(text) || text.includes('@')) throw fail('OMP_TEXT_INVALID');
    const s = this.capture(); if (!ompState(s.detail,s.saved,s.context).canSend) throw fail('OMP_SEND_UNAVAILABLE');
    const command = {id:crypto.randomUUID(),target:s.detail.ompControl.target,text,queue:'reject'};
    s.saved.send = {command,connection:s.detail.ompControl.connection}; this.write(s.key,s.saved); this.busy = true;
    try {
      const result = await this.post(s,'send',{connection:s.detail.ompControl.connection,command});
      const answer = this.applySend(s,result.receipt); this.assertCurrent(s); return answer;
    } catch (error) { if (error.code === 'OMP_CONNECTION_CHANGED') throw error; throw fail('OMP_OUTCOME_UNKNOWN'); }
    finally { this.busy = false; }
  }
  applyInterrupt(snapshot,receipt) {
    const command = snapshot.saved.interrupt?.command;
    if (!command || !receipt || ['id','operationId','runtime'].some(key => receipt[key] !== command[key]) || !STOP.has(receipt.state)) throw fail('OMP_INTERRUPT_REPLY_INVALID');
    snapshot.saved.interrupt.receipt = receipt;
    if (['settled','rejected'].includes(receipt.state)) delete snapshot.saved.interrupt;
    this.write(snapshot.key,snapshot.saved); return {interrupt:receipt};
  }
  async _interrupt() {
    const s = this.capture(); if (!ompState(s.detail,s.saved,s.context).canInterrupt) throw fail('OMP_INTERRUPT_UNAVAILABLE');
    const target = s.detail.ompControl.target;
    const command = {id:crypto.randomUUID(),operationId:s.saved.send.command.id,runtime:target.runtime,epoch:target.epoch};
    s.saved.interrupt = {command}; this.write(s.key,s.saved); this.busy = true;
    try {
      const result = await this.post(s,'interrupt',{connection:s.detail.ompControl.connection,command});
      const answer = this.applyInterrupt(s,result.interrupt); this.assertCurrent(s); return answer;
    } catch (error) { if (error.code === 'OMP_CONNECTION_CHANGED') throw error; throw fail('OMP_OUTCOME_UNKNOWN'); }
    finally { this.busy = false; }
  }
  async _receipt(interrupt = false) {
    const s = this.capture(), pending = s.saved[interrupt ? 'interrupt' : 'send'];
    if (!pending) throw fail('OMP_RECEIPT_NOT_FOUND'); this.busy = true;
    try {
      const result = await this.api('omp-control/' + s.detail.id + '?' + (interrupt ? 'interruptReceipt' : 'receipt') + '=' + pending.command.id);
      const answer = interrupt ? this.applyInterrupt(s,result.interrupt) : this.applySend(s,result.receipt);
      this.assertCurrent(s); return answer;
    } finally { this.busy = false; }
  }
}
