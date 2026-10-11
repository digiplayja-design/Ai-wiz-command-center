import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodSmallTalk,POD_SMALL_TALK,POD_SMALL_TALK_VERSION,POD_SMALL_TALK_EXCHANGES} from '../pod/small_talk.mjs';

const wav=(seconds=1)=>{const b=Buffer.alloc(44+48000*seconds);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(24000,24);b.writeUInt32LE(48000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(b.length-44,40);return b;};
test('conversation bank provides full, unique thoughts for both panel sizes without changing old clips',()=>{
 assert.equal(POD_SMALL_TALK_VERSION,2);
 assert.equal(POD_SMALL_TALK_EXCHANGES,32);
 const modern=Object.values(POD_SMALL_TALK).filter(c=>c.id.includes('-chat-'));
 assert.equal(modern.length,96);assert.equal(new Set(modern.map(c=>c.text)).size,96);
 for(let i=0;i<POD_SMALL_TALK_EXCHANGES;i++)for(const speaker of ['host','analyst','challenger']){
  const clip=POD_SMALL_TALK[`${speaker}-chat-${i}`];
  assert.equal(clip.speaker,speaker);
  assert(clip.text.split(/\s+/).length>=35,'Each voice has a full thought, not a short filler phrase.');
  assert(clip.text.length<=480,'Fits the existing speech provider contract.');
 }
 assert.equal(POD_SMALL_TALK['host-0'].text,"Let's give that a little room. There are a few ways to look at it.");
 const legacy=Object.values(POD_SMALL_TALK).filter(c=>!c.id.includes('-chat-'));
 assert.equal(legacy.length,9);assert(legacy.every(c=>c.text.length<=180));
});
test('studio clips share synthesis across listeners and bound concurrency to two',async()=>{
 let calls=0,active=0,peak=0;
 const service=createPodSmallTalk({logger:{},providers:{speak:async input=>{
  calls++;peak=Math.max(peak,++active);assert.equal(input.text,POD_SMALL_TALK[input.id].text);
  await new Promise(r=>setTimeout(r,2));active--;return {wav:wav()};
 }}});
 try {
  const ids=Object.keys(POD_SMALL_TALK),clips=await Promise.all([...ids,...ids,...ids].map(id=>service.audio(id)));
  assert.equal(calls,105);assert.equal(peak,2);assert.equal(clips.length,315);
  assert.equal(clips[0],clips[ids.length]);assert.equal(clips[0].audio.durationSeconds,1);
  assert.equal(clips[0].audio.mime,'audio/wav');
 }finally{service.stop();}
});
test('invalid asset IDs and failures cannot cause open-ended synthesis or paid retries',async()=>{
 let calls=0;const service=createPodSmallTalk({logger:{},providers:{speak:async()=>{calls++;throw new Error('provider down');}}});
 for(const id of ['arbitrary','__proto__','constructor','toString','host-chat-32','host-chat--1'])assert.throws(()=>service.audio(id));
 for(const id of ['host-0','host-chat-0'])for(let i=0;i<3;i++)await assert.rejects(service.audio(id));
 assert.equal(calls,2);service.stop();assert.throws(()=>service.audio('host-chat-1'));
});
test('longer exchanges allow natural 18-second turns while legacy audio remains capped at ten',async()=>{
 const service=createPodSmallTalk({logger:{},providers:{speak:async()=>({wav:wav(18)})}});
 try {
  assert.equal((await service.audio('host-chat-0')).audio.durationSeconds,18);
  await assert.rejects(service.audio('host-0'));
 }finally{service.stop();}
});
test('malformed or overlong assets are never returned as playable audio',async()=>{
 for(const bytes of [Buffer.alloc(500),wav(31)]){
  const service=createPodSmallTalk({logger:{},providers:{speak:async()=>({wav:bytes})}});
  await assert.rejects(service.audio('host-chat-0'));service.stop();
 }
});
test('stopping the studio aborts active synthesis and never starts queued synthesis',async()=>{
 let calls=0;const signals=[];
 const service=createPodSmallTalk({logger:{},providers:{speak:async({signal})=>{
  calls++;signals.push(signal);
  await new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(signal.reason),{once:true}));
 }}});
 const pending=['host-chat-0','analyst-chat-0','host-chat-1'].map(id=>service.audio(id));
 const results=Promise.allSettled(pending);
 await new Promise(r=>setImmediate(r));service.stop();
 assert((await results).every(r=>r.status==='rejected'));
 assert.equal(calls,2);assert(signals.every(s=>s.aborted));
});
