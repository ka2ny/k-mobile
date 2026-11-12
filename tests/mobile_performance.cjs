#!/usr/bin/env node
// Deterministic browser fixtures; timings are diagnostic, structural budgets are assertions.
// Run with the same Playwright setup as mobile_design_test.js.
'use strict';
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
if (process.env.MOBILE_PERF_BASELINE) throw new Error('OS git-history baselines are not available in this clean extraction.');
const baseline = null;
(async () => {
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({viewport:{width:390,height:844}, serviceWorkers:'block'});
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('http://mobile.test/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname.includes('/api/')) return route.fulfill({json:{name:'Test computer', phone:null, app:true}});
      const shared = ['/switch.js','/switch.css','/mobile-sans.woff2','/mobile-mono.woff2'];
      const file = shared.includes(url.pathname) ? path.join(root,'public',url.pathname) :
        path.join(root,'public/beam',url.pathname.replace(/^\/beam\//,'') || 'index.html');
      if (!fs.existsSync(file)) return route.fulfill({status:404,body:''});
      const type = {'.js':'text/javascript','.css':'text/css','.html':'text/html','.woff2':'font/woff2'}[path.extname(file)];
      const body = baseline && ['switch.js','app.js'].includes(path.basename(file)) ?
        execFileSync('git',['show',`${baseline}:${path.relative(root,file)}`],{cwd:root}) : fs.readFileSync(file);
      return route.fulfill({body, contentType:type || 'application/octet-stream'});
    });
    await page.goto('http://mobile.test/beam/');
    await page.waitForFunction(()=>!!window.kholeSwitch && !!S.me);
    const result = await page.evaluate(() => {
      show('home'); folderView.on = true; syncFileView();
      folderView.files = Array.from({length:500},(_,i)=>({name:`File ${(i*137)%500}.txt`,size:1024+i,at:1700000000+i,type:'text/plain'}));
      document.querySelector('#files-sort').value = 'name';
      renderFolder();
      const box = document.querySelector('#shared-files');
      const first = box.firstElementChild;
      const observer = new MutationObserver(()=>{});
      observer.observe(box,{childList:true});
      const samples = [];
      for(let i=0;i<20;i++) {
        // Fresh objects model an unchanged network response.
        folderView.files = folderView.files.map(f=>({...f}));
        const start=performance.now(); renderFolder(); void box.offsetHeight;
        samples.push(performance.now()-start);
      }
      const removed = observer.takeRecords().reduce((n,r)=>n+r.removedNodes.length,0);
      observer.disconnect();
      samples.sort((a,b)=>a-b);
      return {medianMs:samples[10],p95Ms:samples[19],removed,retained:first===box.firstElementChild};
    });
    console.log('Files: 500 entries, 60 visible, 20 unchanged refreshes:', JSON.stringify(result));
    if(!baseline) { assert.equal(result.removed,0); assert.equal(result.retained,true); }
    if(!baseline) {
      const files = await page.evaluate(() => {
        const box=document.querySelector('#shared-files');
        const original=box.firstElementChild;
        const button=original.querySelector('.file-save'); button.focus();
        folderView.files=folderView.files.map(f=>f.name===original.dataset.fileKey ? {...f,size:7654321,type:'image/png'} : f);
        renderFolder();
        const focused=document.activeElement===button;
        const updated=original.querySelector('.size').textContent.includes('7.7 MB') && original.dataset.kind==='image';
        original.querySelector('.file-open').click();
        const detail=document.querySelector('#file-detail-meta').textContent;
        dismissFileDetails(true);
        folderView.grid=true; renderFolder();
        const retained=box.firstElementChild===original;
        folderView.files=folderView.files.filter(f=>f.name!==original.dataset.fileKey); renderFolder();
        return {focused,updated,detail,retained,removed:!original.isConnected};
      });
      assert.ok(files.focused && files.updated && files.retained && files.removed, JSON.stringify(files));
      assert.match(files.detail,/7.7 MB/); assert.match(files.detail,/image\/png/);
      console.log('ok   reused files preserve focus, update details and disappear when deleted');
      const memory = await page.evaluate(async () => {
        const original=window.fetch;
        let started=0, aborted=0;
        window.fetch=(_url,opts)=>new Promise((_resolve,reject)=>{
          started++;
          opts.signal.addEventListener('abort',()=>{aborted++;reject(new DOMException('Cancelled','AbortError'));});
        });
        try {
          for(let i=0;i<10;i++) prefetch({id:`budget-${i}`,files:[{id:'f',name:'large.bin',size:16*1024*1024}]});
          const result={cached:S.blobs.size,started};
          const waiting=Promise.all([...S.blobs.values()]);
          prunePrefetch([]);
          result.cancelled=(await waiting).every(f=>f===null);
          await new Promise(r=>setTimeout(r,0));
          result.aborted=aborted; result.remaining=S.blobs.size;
          return result;
        } finally { window.fetch=original; }
      });
      assert.equal(memory.cached,4,'64 MiB is shared across inbox items');
      assert.equal(memory.started,3,'at most three speculative downloads');
      assert.equal(memory.aborted,3); assert.equal(memory.remaining,0); assert.ok(memory.cancelled);
      const delivery=await page.evaluate(async()=>{
        const original=window.fetch;
        try {
          window.fetch=async()=>new Response(new Uint8Array(1024),{headers:{'Content-Type':'text/plain'}});
          prefetch({id:'delivery',files:[{id:'file',name:'test.txt',size:1024}]});
          const file=await S.blobs.get('delivery/file');
          const valid=file instanceof File && file.size===1024 && file.name==='test.txt';
          prunePrefetch([]);
          prefetch({id:'oversized',files:[{id:'file',name:'test.txt',size:100}]});
          const rejected=await S.blobs.get('oversized/file');
          return {valid,rejected,remaining:S.blobs.size};
        } finally { prunePrefetch([]);window.fetch=original; }
      });
      assert.ok(delivery.valid); assert.equal(delivery.rejected,null); assert.equal(delivery.remaining,0);
      console.log('ok   prefetch shares its memory budget, bounds concurrency, cancels stale work and rejects oversized data');
      const stale=await page.evaluate(async()=>{
        const original=window.fetch, previous=S.me;
        let answer;
        try {
          window.fetch=()=>new Promise(resolve=>{answer=resolve;});
          S.me={...previous,phone:{trusted:true}};
          const pending=loadInbox(); unpaired();
          answer(new Response(JSON.stringify({items:[{id:'late',text:null,files:[{id:'f',name:'late.txt',size:1}]}]}),{headers:{'Content-Type':'application/json'}}));
          await pending;
          return {items:S.items.length,cached:S.blobs.size,rows:document.querySelector('#items').children.length};
        } finally {window.fetch=original;S.me=previous;show('home');}
      });
      assert.deepEqual(stale,{items:0,cached:0,rows:0});
      console.log('ok   a late inbox response cannot restore cleared data after unpairing');
    }
    await page.waitForTimeout(250);
    const scans = await page.evaluate(async () => {
      const original = document.querySelectorAll;
      let scans=0;
      document.querySelectorAll = function(selector) {
        if(selector.includes('data-khole-switch')) scans++;
        return original.call(this,selector);
      };
      const host=document.createElement('div'); document.body.append(host);
      for(let i=0;i<5;i++) {
        host.replaceChildren(document.createElement('span'));
        await new Promise(r=>setTimeout(r,120));
      }
      document.querySelectorAll=original; host.remove(); return scans;
    });
    console.log('Navigation: document-wide scans during unrelated updates:', scans);
    if(!baseline) assert.equal(scans,0);
    await page.evaluate(()=>{
      const host=document.createElement('div'); host.id='late-header';
      host.innerHTML='<button data-shell-apps>Apps</button><div id="bar-tools"></div>';
      document.body.append(host);
    });
    await page.waitForFunction(()=>document.querySelector('#late-header button').dataset.kholeSwitchWired==='1' && document.querySelector('#kh-remote-apps'));
    assert.equal(await page.locator('#kh-remote-apps').count(),1);
    assert.deepEqual(errors,[]);
    console.log('ok   late headers still receive working navigation controls');
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
