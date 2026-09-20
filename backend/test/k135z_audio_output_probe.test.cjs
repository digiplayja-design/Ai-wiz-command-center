'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {registerAudioProbe,PREFIX} = require('../k135z_zoom/audio_probe_routes.cjs');
const loaded = import('../k135z_zoom/audio_probe/probe.mjs');
const deferred = () => {let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};};
async function fixture(overrides = {}) {
  const calls = [], config = {runningContext:'inMeeting',unsupportedApis:[]};
  const supportedApis = ['getRunningContext','shareApp','shareComputerAudio'];
  const sdk = {config:async()=>config,getSupportedJsApis:async()=>({supportedApis}),
    getRunningContext:async()=>({context:'inMeeting'}),
    shareApp:async options=>{calls.push(['app',options]);},
    shareComputerAudio:async options=>{calls.push(['audio',options]);},...overrides};
  const player = {play:async()=>{calls.push(['play']);},stop:()=>{calls.push(['silence']);}};
  const {AudioProbe} = await loaded;
  return {p:new AudioProbe({sdk,player,timeoutMs:30}),sdk,player,calls,config,supportedApis};
}
test('page and scripts use exact public paths, required Zoom headers, and no request reflection',()=>{
  const routes=new Map();registerAudioProbe({get:(path,fn)=>routes.set(path,fn)});
  assert.equal(routes.size,8);
  for(const [path,handler] of routes){
    const headers={},r={setHeader:(k,v)=>{headers[k]=v;},status(n){assert.equal(n,200);return this;},end(b){this.body=b.toString();}};
    handler({query:{token:'private-marker'},headers:{'x-zoom-app-context':'private-marker'}},r);
    for(const h of ['Strict-Transport-Security','X-Content-Type-Options','Content-Security-Policy','Referrer-Policy'])assert.ok(headers[h]);
    assert.equal(headers['Cache-Control'],'no-store');assert.ok(!r.body.includes('private-marker'));
    assert.ok(path.startsWith(PREFIX));
  }
  assert.ok(!routes.has(PREFIX+'../zoom_routes.cjs'));
});
test('checking capabilities never starts sharing or audio',async()=>{
  const {p,calls}=await fixture();await p.check();assert.equal(p.ready,true);assert.deepEqual(calls,[]);
  await p.play();assert.deepEqual(calls,[]);assert.equal(p.heard,false);
});
test('rejects missing Zoom SDK and opening outside a meeting',async()=>{
  const {p,config}=await fixture();config.runningContext='inMainClient';await p.check();assert.equal(p.ready,false);
  p.sdk=null;await p.check();assert.equal(p.ready,false);assert.match(p.message,/Zoom SDK did not load/);
});
test('capability intersection blocks unsupported audio method',async()=>{
  const {p,config,calls}=await fixture();config.unsupportedApis=['shareComputerAudio'];await p.check();
  await p.share('shareComputerAudio');assert.deepEqual(calls,[]);
  await p.share('shareApp');assert.deepEqual(calls,[['app',{action:'start',withSound:true}]]);
});
test('computer audio uses explicit action; remote confirmation requires completed playback',async()=>{
  const {p,calls}=await fixture();await p.check();await p.share('shareComputerAudio');
  assert.deepEqual(calls,[['audio',{action:'start',mode:'mono'}]]);
  p.confirm(true);assert.equal(p.heard,false);await p.play();assert.equal(p.heard,false);
  p.confirm(true);assert.equal(p.heard,true);assert.match(p.message,/You confirmed/);
  await p.stop();assert.equal(p.heard,false);assert.equal(p.ready,false);assert.equal(p.mode,null);
  assert.deepEqual(calls.at(-1),['audio',{action:'stop'}]);
});
test('changed meeting context prevents sharing',async()=>{
  const {p,sdk,calls}=await fixture();await p.check();sdk.getRunningContext=async()=>({context:'inMainClient'});
  await p.share('shareApp');assert.deepEqual(calls,[]);assert.equal(p.ready,false);
});
test('denied sharing never enables tone playback',async()=>{
  const {p,calls}=await fixture({shareApp:async()=>{throw Error('DENIED');}});
  await p.check();await p.share('shareApp');await p.play();assert.equal(p.ready,false);assert.deepEqual(calls,[]);
});
test('stop immediately silences audio even when SDK stop fails and supports retry',async()=>{
  const {p,sdk,calls}=await fixture();await p.check();await p.share('shareApp');
  sdk.shareApp=async()=>{throw Error('NETWORK');};await p.stop();
  assert.deepEqual(calls.at(-1),['silence']);assert.equal(p.mode,'shareApp');assert.match(p.message,/unconfirmed/);
  sdk.shareApp=async()=>{};await p.stop();assert.equal(p.mode,null);
});
test('a start completing after Stop is cleaned up and does not enable playback',async()=>{
  const d=deferred(), {p,sdk,calls}=await fixture();
  sdk.shareApp=async o=>{calls.push(['app',o]);if(o.action==='start')await d.promise;};
  await p.check();const start=p.share('shareApp');await new Promise(r=>setImmediate(r));
  await p.stop();d.resolve();await start;await new Promise(r=>setImmediate(r));
  assert.equal(p.ready,false);assert.equal(p.mode,null);assert.equal(p.heard,false);
  assert.equal(calls.filter(x=>x[0]==='app'&&x[1].action==='stop').length,2);
});
test('timed-out start cannot play audio and cleans up a later success',async()=>{
  const d=deferred(), {p,sdk}=await fixture();sdk.shareApp=async o=>{if(o.action==='start')await d.promise;};
  await p.check();await p.share('shareApp');assert.equal(p.ready,false);assert.equal(p.busy,false);
  d.resolve();await new Promise(r=>setImmediate(r));assert.equal(p.mode,null);
});
test('stop during capability lookup prevents a late ready state',async()=>{
  const d=deferred(), {p,sdk}=await fixture();sdk.getSupportedJsApis=()=>d.promise;
  const check=p.check();await new Promise(r=>setImmediate(r));await p.stop();
  d.resolve({supportedApis:['getRunningContext','shareApp']});await check;assert.equal(p.ready,false);
});
test('tone canceled while AudioContext resumes cannot create sound',async()=>{
  const {TonePlayer}=await loaded,d=deferred();let oscillators=0,closed=0;
  const p=new TonePlayer(()=>({resume:()=>d.promise,state:'suspended',close:async()=>{closed++;},
    createOscillator(){oscillators++;}}));
  const played=p.play();p.stop();d.resolve();await assert.rejects(played,/STOPPED/);
  assert.equal(oscillators,0);assert.equal(closed,1);
});
test('Stop before any sharing does not prevent later stop requests',async()=>{
  const {p,calls}=await fixture();await p.stop();assert.equal(p.stopping,null);
  await p.check();await p.share('shareApp');await p.stop();
  assert.equal(p.mode,null);assert.deepEqual(calls.at(-1),['app',{action:'stop'}]);
});
test('failed replay clears previous playback evidence',async()=>{
  const {p,player}=await fixture();await p.check();await p.share('shareApp');await p.play();
  p.confirm(true);assert.equal(p.heard,true);
  player.play=async()=>{throw Error('PLAYBACK');};await p.play();p.confirm(true);
  assert.equal(p.played,false);assert.equal(p.heard,false);
});
test('a timed-out start must settle before a new test can start',async()=>{
  const d=deferred(),{p,sdk}=await fixture();
  sdk.shareApp=async o=>{if(o.action==='start')await d.promise;};
  await p.check();await p.share('shareApp');await p.stop();await p.check();
  assert.equal(p.pendingStart,true);assert.equal(p.ready,false);
  d.resolve();await new Promise(r=>setImmediate(r));
  assert.equal(p.pendingStart,false);assert.equal(p.mode,null);
  await p.check();assert.equal(p.ready,true);
});
