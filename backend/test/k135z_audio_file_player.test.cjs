'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const loaded = import('../k135z_zoom/audio_probe/media_player.mjs');
const deferred = () => {let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};};
async function fixture(play = () => Promise.resolve(), timeoutMs = 1000) {
  const {MediaTonePlayer} = await loaded, audios = [], revoked = [];
  const player = new MediaTonePlayer({timeoutMs,createUrl:()=>'blob:synthetic-test',revokeUrl:url=>revoked.push(url),createAudio:()=>{
    const listeners = new Map();
    const a = {ended:false,paused:true,removed:false,playCalls:0,
      setAttribute(){},removeAttribute(name){delete this[name];},
      addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name),
      play(){this.playCalls++;this.paused=false;return play();},pause(){this.paused=true;},load(){this.loaded=true;},remove(){this.removed=true;},
      emit(name){if(name==='ended')this.ended=true;listeners.get(name)?.();}};
    audios.push(a);return a;
  }});
  return {player,audios,revoked};
}
test('WAV has valid PCM headers, three audible pulses and silent gaps',async()=>{
  const {makeToneWav}=await loaded,b=makeToneWav(),v=new DataView(b.buffer);
  assert.equal(Buffer.from(b.subarray(0,4)).toString(),'RIFF');
  assert.equal(Buffer.from(b.subarray(8,12)).toString(),'WAVE');
  assert.equal(v.getUint32(4,true),b.length-8);assert.equal(v.getUint16(20,true),1);
  assert.equal(v.getUint16(22,true),1);assert.equal(v.getUint32(24,true),24000);
  assert.equal(v.getUint16(34,true),16);assert.equal(v.getUint32(40,true),b.length-44);
  assert.equal((b.length-44)/2/24000,1.8);
  const values=(from,to)=>Array.from({length:Math.floor((to-from)*24000)},(_,i)=>v.getInt16(44+2*(Math.floor(from*24000)+i),true));
  for(const start of [0,.65,1.3])assert.ok(values(start+.05,start+.25).some(x=>Math.abs(x)>2000));
  for(const start of [.36,1.01,1.66])assert.ok(values(start,start+.1).every(x=>x===0));
});
test('construction is silent; completion waits for ended, not play promise',async()=>{
  const {player,audios,revoked}=await fixture();assert.equal(audios.length,0);
  let complete=false;const played=player.play().then(()=>{complete=true;});
  assert.equal(audios[0].playCalls,1);assert.equal(audios[0].autoplay,false);assert.equal(audios[0].loop,false);
  await new Promise(r=>setImmediate(r));assert.equal(complete,false);
  audios[0].emit('ended');await played;assert.equal(audios[0].paused,true);
  assert.equal(audios[0].src,undefined);assert.equal(audios[0].removed,true);assert.equal(revoked.length,1);
});
test('Stop immediately silences media and late play acknowledgement cannot revive it',async()=>{
  const d=deferred(),{player,audios,revoked}=await fixture(()=>d.promise);
  const played=player.play(),rejected=assert.rejects(played,/STOPPED/);
  player.stop();assert.equal(audios[0].paused,true);assert.equal(audios[0].src,undefined);
  audios[0].paused=false;d.resolve();await rejected;await new Promise(r=>setImmediate(r));
  assert.equal(audios[0].paused,true);assert.equal(revoked.length,1);assert.equal(player.current,null);
});
test('starting a new play cancels the prior element and ignores its late events',async()=>{
  const d=deferred(),{player,audios}=await fixture(()=>d.promise);
  const first=assert.rejects(player.play(),/STOPPED/),second=player.play();
  audios[0].emit('ended');d.resolve();await first;await new Promise(r=>setImmediate(r));
  assert.equal(audios[1].paused,false);audios[1].emit('ended');await second;
});
test('media rejection and decoding errors release the source',async()=>{
  const f=await fixture(()=>Promise.reject(Error('private browser detail')));
  await assert.rejects(f.player.play(),/^Error: MEDIA_PLAYBACK_FAILED$/);
  assert.equal(f.audios[0].paused,true);assert.equal(f.revoked.length,1);
  const g=await fixture(),playing=g.player.play();g.audios[0].emit('error');
  await assert.rejects(playing,/MEDIA_PLAYBACK_FAILED/);assert.equal(g.audios[0].removed,true);
});
test('stalled playback times out and cannot remain audible',async()=>{
  const {player,audios,revoked}=await fixture(()=>new Promise(()=>{}),20);
  await assert.rejects(player.play(),/MEDIA_PLAYBACK_TIMEOUT/);
  assert.equal(audios[0].paused,true);assert.equal(audios[0].src,undefined);assert.equal(revoked.length,1);
});
test('probe grants confirmation only after media completion; Stop cancels evidence',async()=>{
  const {AudioProbe}=await import('../k135z_zoom/audio_probe/probe.mjs'),{player,audios}=await fixture();
  const p=new AudioProbe({player,sdk:{config:async()=>({runningContext:'inMeeting',product:'mobile',clientVersion:'6.6.0.12345'}),
    getSupportedJsApis:async()=>({supportedApis:['getRunningContext','shareApp']}),
    getRunningContext:async()=>({context:'inMeeting'}),shareApp:async()=>{}}});
  await p.check();assert.equal(p.clientInfo,'Zoom mobile 6.6.0.12345. Audio-file test v4.');
  await p.share('shareApp');const playing=p.play();p.confirm(true);assert.equal(p.heard,false);
  audios[0].emit('ended');await playing;assert.equal(p.played,true);assert.equal(p.heard,false);
  p.confirm(true);assert.equal(p.heard,true);
  const replay=p.play();await p.stop('hidden');await replay;
  assert.equal(p.played,false);assert.equal(p.heard,false);assert.equal(audios[1].paused,true);
  assert.match(p.stopDetail,/hidden/);
});
test('client diagnostic includes only allowlisted product and numeric version',async()=>{
  const {AudioProbe}=await import('../k135z_zoom/audio_probe/probe.mjs');
  const p=new AudioProbe({player:{stop(){}},sdk:{config:async()=>({runningContext:'inMeeting',product:'private-name',clientVersion:'private-token'}),
    getSupportedJsApis:async()=>({supportedApis:[]})}});
  await p.check();assert.equal(p.clientInfo,'Zoom client. Audio-file test v4.');
});
