'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const loaded = import('../k135z_zoom/audio_probe/probe.mjs');
async function probe(overrides = {}) {
  const {AudioProbe} = await loaded;
  return new AudioProbe({timeoutMs:20,player:{stop(){},play(){throw Error('must not play');}},sdk:{
    config:async()=>({runningContext:'inMeeting',unsupportedApis:[]}),
    getSupportedJsApis:async()=>({supportedApis:['getRunningContext','shareApp']}),...overrides}});
}
for (const method of ['config','getSupportedJsApis']) {
  test(`${method} failure reports its stage and numeric code without exposing payload`,async()=>{
    const p=await probe({[method]:async()=>{throw Object.assign(Error('secret-token-private'),{code:10011,requestId:'secret-request'});}});
    await p.check();
    assert.match(p.message,method==='config'?/Zoom app authorization failed/:/Zoom API availability check failed/);
    assert.match(p.message,/Zoom code 10011/);assert.doesNotMatch(p.message,/secret/);
    assert.equal(p.ready,false);assert.equal(p.busy,false);assert.equal(p.supported.size,0);assert.equal(p.mode,null);
  });
}
test('unexpected error fields never get reflected to the page',async()=>{
  const p=await probe({config:async()=>{throw {code:'secret-token',message:'secret-message'};}});
  await p.check();assert.doesNotMatch(p.message,/secret|Zoom code/);assert.equal(p.ready,false);
});
test('authorization timeout has a distinct recovery instruction',async()=>{
  const p=await probe({config:()=>new Promise(()=>{})});await p.check();
  assert.match(p.message,/Zoom app authorization timed out/);assert.equal(p.ready,false);assert.equal(p.busy,false);
});
test('invalid config and API responses stay disabled and identify the failing stage',async()=>{
  for(const [method,pattern] of [['config',/Zoom app authorization returned an unexpected response/],['getSupportedJsApis',/Zoom API availability check returned an unexpected response/]]){
    const p=await probe({[method]:async()=>null});await p.check();assert.match(p.message,pattern);assert.equal(p.ready,false);
  }
});
test('a main-client context instructs opening in the active meeting without querying sharing',async()=>{
  const p=await probe({config:async()=>({runningContext:'inMainClient',unsupportedApis:[]}),getSupportedJsApis:()=>{throw Error('must not query');}});
  await p.check();assert.match(p.message,/outside a meeting/);assert.equal(p.ready,false);
});
test('Stop during authorization prevents later API lookup or readiness',async()=>{
  let resolve,queries=0;const pending=new Promise(r=>{resolve=r;});
  const p=await probe({config:()=>pending,getSupportedJsApis:async()=>{queries++;return {supportedApis:['getRunningContext','shareApp']};}});
  const check=p.check();await p.stop();resolve({runningContext:'inMeeting',unsupportedApis:[]});await check;
  assert.equal(queries,0);assert.equal(p.ready,false);assert.match(p.message,/Test stopped/);
});
