'use strict';
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'../public');
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);
const files=walk(root);let checked=0;
for(const file of files.filter(f=>f.endsWith('.js'))) {
  execFileSync(process.execPath,['--input-type=module','--check'],{input:fs.readFileSync(file)});checked++;
}
let cached=0;
for(const [scope,list] of [['/','FILES'],['/remote/','SHELL'],['/beam/','FILES'],['/agents/','SHELL']]) {
  const base='http://127.0.0.1:4173'+scope;
  const context=vm.createContext({URL,self:{registration:{scope:base},addEventListener(){}}});
  vm.runInContext(fs.readFileSync(path.join(root,scope,'sw.js'),'utf8'),context);
  for(const item of vm.runInContext(list,context)) {
    const url=new URL(item,base);let target=path.join(root,decodeURIComponent(url.pathname));
    if(url.pathname.endsWith('/')) target=path.join(target,'index.html');
    assert.ok(fs.existsSync(target),`Missing worker cache asset: ${url.pathname}`);cached++;
    assert.ok(!url.pathname.includes('/api/'),'API data must not be in the shell cache');
  }
}
console.log(`Passed: ${checked} JavaScript syntax checks; ${cached} worker cache references resolve.`);
