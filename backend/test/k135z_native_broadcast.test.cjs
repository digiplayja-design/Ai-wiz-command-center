'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const loaded = import('../k135z_zoom/audio_probe/native_session.mjs');
function deferred() { let resolve, reject; const promise = new Promise((a,b) => {resolve=a;reject=b;}); return {promise,resolve,reject}; }
async function fixture() {
  const {NativeBroadcastTest}=await loaded, pending=[],calls=[];
  const player={play(){calls.push('play');const d=deferred();pending.push(d);return d.promise;},stop(){calls.push('stop');}};
  return {p:new NativeBroadcastTest({player}),pending,calls};
}
test('requires broadcast acknowledgement and explicit Play; never starts automatically',async()=>{
  const {p,calls}=await fixture();await p.play();p.confirm(true);assert.deepEqual(calls,[]);assert.equal(p.result,null);
  p.setReady(true);assert.deepEqual(calls,[]);assert.equal(p.ready,true);assert.equal(p.finished,false);
});
test('starts local playback synchronously and accepts results only after completion',async()=>{
  const {p,pending,calls}=await fixture();p.setReady(true);const playing=p.play();assert.deepEqual(calls,['play']);
  p.confirm(true);assert.equal(p.result,null);await p.play();assert.equal(calls.length,1);
  pending[0].resolve();await playing;assert.equal(p.finished,true);assert.equal(p.result,null);
  p.confirm('yes');assert.equal(p.result,null);p.confirm(false);assert.equal(p.result,false);
  p.confirm(true);assert.equal(p.result,true);assert.match(p.message,/You confirmed/);
});
test('Stop immediately cancels playback and late completion cannot confirm delivery',async()=>{
  const {p,pending,calls}=await fixture();p.setReady(true);const playing=p.play();p.stop();
  assert.deepEqual(calls,['play','stop']);assert.equal(p.ready,false);assert.equal(p.playing,false);
  pending[0].resolve();await playing;p.confirm(true);await p.play();
  assert.equal(p.finished,false);assert.equal(p.result,null);assert.deepEqual(calls,['play','stop']);
  assert.match(p.message,/Stop Share in Zoom/);
});
test('late completion from a stopped test cannot alter a newer playback',async()=>{
  const {p,pending}=await fixture();p.setReady(true);const old=p.play();p.stop();p.setReady(true);const current=p.play();
  pending[0].resolve();await old;assert.equal(p.playing,true);assert.equal(p.finished,false);
  pending[1].resolve();await current;assert.equal(p.playing,false);assert.equal(p.finished,true);
});
test('hiding the page silences audio and retains only a previously reported result',async()=>{
  const {p,pending,calls}=await fixture();p.setReady(true);const playing=p.play();pending[0].resolve();await playing;p.confirm(false);
  p.stop('hidden');assert.equal(calls.at(-1),'stop');assert.equal(p.ready,false);assert.equal(p.finished,false);assert.equal(p.result,false);
  assert.match(p.message,/page was hidden/);p.confirm(true);assert.equal(p.result,false);
  p.setReady(true);assert.equal(p.result,null);assert.equal(calls.filter(x=>x==='play').length,1);
});
test('a failed replay clears earlier success and does not expose raw errors',async()=>{
  const {p,pending}=await fixture();p.setReady(true);const first=p.play();pending[0].resolve();await first;p.confirm(true);
  const replay=p.play();assert.equal(p.result,null);pending[1].reject(Error('private-browser-detail'));await replay;
  assert.equal(p.finished,false);p.confirm(true);assert.equal(p.result,null);assert.equal(p.playing,false);
  assert.match(p.message,/Playback failed/);assert.ok(!p.message.includes('private-browser-detail'));
});
test('unchecking the broadcast confirmation silences playback; rechecking remains silent',async()=>{
  const {p,pending,calls}=await fixture();p.setReady(true);const playing=p.play();p.setReady(false);
  assert.equal(calls.at(-1),'stop');assert.equal(p.ready,false);p.setReady(true);
  pending[0].reject(Error('STOPPED'));await playing;assert.equal(p.playing,false);assert.equal(p.finished,false);
  assert.deepEqual(calls,['play','stop']);assert.match(p.message,/Ready to play/);
});
