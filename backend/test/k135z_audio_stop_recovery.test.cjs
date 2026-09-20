'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const loaded = import('../k135z_zoom/audio_probe/probe.mjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
const fault = code => Object.assign(Error('private-token'), {code,requestId:'private-request'});
const deferred = () => { let resolve; const promise=new Promise(r=>{resolve=r;}); return {promise,resolve}; };
async function fixture() {
  const {AudioProbe}=await loaded;
  const calls=[];
  const sdk={config:async()=>({runningContext:'inMeeting',unsupportedApis:[]}),
    getSupportedJsApis:async()=>({supportedApis:['getRunningContext','shareApp','shareComputerAudio']}),
    getRunningContext:async()=>({context:'inMeeting'}),
    shareApp:async o=>{calls.push(o.action);},shareComputerAudio:async o=>{calls.push(o.action);}};
  const p=new AudioProbe({sdk,timeoutMs:20,player:{stop(){},play:async()=>{calls.push('play');}}});
  await p.check(); return {p,sdk,calls};
}
for(const [mode,code] of [['shareApp',10025],['shareComputerAudio','10130']]) {
  test(`${mode} not-started stop allows a fresh check without playing or restarting`,async()=>{
    const {p,sdk,calls}=await fixture(); await p.share(mode);
    sdk[mode]=async()=>{throw fault(code);}; await p.stop();
    assert.equal(p.mode,null); assert.equal(p.ready,false); assert.equal(p.heard,false);
    assert.match(p.message,/share is inactive/); assert.match(p.stopDetail,new RegExp(String(code)));
    await p.play(); assert.deepEqual(calls,['start']); await p.check(); assert.equal(p.ready,true);
  });
}
test('a start failure remains visible after the inactive stop response',async()=>{
  const {p,sdk,calls}=await fixture();
  sdk.shareApp=async o=>{throw fault(o.action==='start'?10023:10025);};
  await p.share('shareApp'); await p.stop(); await p.play(); p.confirm(true);
  assert.match(p.shareDetail,/10023/); assert.match(p.shareDetail,/disabled/);
  assert.match(p.stopDetail,/10025/); assert.doesNotMatch(p.shareDetail+p.stopDetail,/private/);
  assert.equal(p.heard,false); assert.equal(p.result,''); assert.deepEqual(calls,[]);
});
test('unknown or wrong-method stop errors keep recovery locked and redact arbitrary fields',async()=>{
  for(const code of [10130,10018,'private-code']) {
    const {p,sdk}=await fixture(); await p.share('shareApp');
    sdk.shareApp=async()=>{throw fault(code);}; await p.stop(); await p.check();
    assert.equal(p.mode,'shareApp'); assert.equal(p.ready,false); assert.match(p.message,/unconfirmed/);
    assert.doesNotMatch(p.stopDetail,/private/);
    if(typeof code==='number') assert.match(p.stopDetail,new RegExp(String(code)));
    else assert.doesNotMatch(p.stopDetail,/Zoom code/);
  }
});
test('a stop timeout retains the sharing state and reports its stage',async()=>{
  const {p,sdk}=await fixture(); await p.share('shareApp');
  sdk.shareApp=()=>new Promise(()=>{}); await p.stop();
  assert.equal(p.mode,'shareApp'); assert.equal(p.ready,false); assert.equal(p.busy,false);
  assert.match(p.stopDetail,/App sharing stop timed out/);
});
test('a pending start still blocks a new test after a not-started stop',async()=>{
  const d=deferred(),{p,sdk,calls}=await fixture(); let stops=0;
  sdk.shareApp=async o=>{if(o.action==='start')await d.promise;else {stops++;throw fault(10025);}};
  const sharing=p.share('shareApp'); await tick(); await p.stop(); await p.check();
  assert.equal(p.pendingStart,true); assert.equal(p.ready,false);
  d.resolve(); await sharing; await tick();
  assert.equal(stops,2); assert.equal(p.pendingStart,false); assert.equal(p.mode,null);
  assert.equal(p.ready,false); assert.deepEqual(calls,[]);
});
test('a delayed start while Stop is pending triggers a second stop after the first settles',async()=>{
  const start=deferred(),stop=deferred(),{p,sdk,calls}=await fixture(); let stops=0;
  sdk.shareApp=async o=>{if(o.action==='start')await start.promise;else {
    stops++; if(stops===1) {await stop.promise;throw fault(10025);}
  }};
  const sharing=p.share('shareApp'); await tick(); const stopping=p.stop(); await tick();
  start.resolve(); await sharing; await tick(); assert.equal(p.cleanupPending,true);
  await p.check(); assert.equal(p.ready,false);
  stop.resolve(); await stopping; await tick();
  assert.equal(stops,2); assert.equal(p.cleanupPending,false); assert.equal(p.mode,null);
  assert.equal(p.ready,false); assert.deepEqual(calls,[]);
});
test('leaving the page records the stop reason and retains the user-reported result',async()=>{
  const {p}=await fixture(); await p.share('shareApp'); await p.play(); p.confirm(true);
  await p.stop('hidden'); assert.match(p.stopDetail,/page was hidden/);
  assert.match(p.result,/you confirmed another participant/); assert.equal(p.ready,false);
  await p.check(); assert.equal(p.result,''); assert.equal(p.stopDetail,'');
});
test('a failed replay cannot retain a previous positive result',async()=>{
  const {p}=await fixture(); await p.share('shareApp'); await p.play(); p.confirm(true);
  p.player.play=async()=>{throw Error('playback');}; await p.play(); await p.stop();
  assert.equal(p.result,''); assert.equal(p.heard,false); assert.equal(p.played,false);
});
