import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodSmallTalk,POD_SMALL_TALK} from '../pod/small_talk.mjs';

const wav=()=>{const b=Buffer.alloc(48044);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(24000,24);b.writeUInt32LE(48000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(48000,40);return b;};
test('fixed small-talk clips share synthesis across listeners and bound concurrency to two',async()=>{
 let calls=0,active=0,peak=0;
 const service=createPodSmallTalk({logger:{},providers:{speak:async input=>{
  calls++;peak=Math.max(peak,++active);assert(Object.values(POD_SMALL_TALK).some(c=>c.text===input.text&&c.speaker===input.speaker));
  await new Promise(r=>setTimeout(r,2));active--;return {wav:wav()};
 }}});
 try {
  const ids=Object.keys(POD_SMALL_TALK),clips=await Promise.all([...ids,...ids,...ids].map(id=>service.audio(id)));
  assert.equal(calls,9);assert.equal(peak,2);assert.equal(clips.length,27);
  assert.equal(clips[0],clips[9]);assert.equal(clips[0].audio.durationSeconds,1);
  assert.equal(clips[0].audio.mime,'audio/wav');
 }finally{service.stop();}
});
test('invalid asset IDs and failures cannot cause open-ended synthesis or paid retries',async()=>{
 let calls=0;const service=createPodSmallTalk({logger:{},providers:{speak:async()=>{calls++;throw new Error('provider down');}}});
 for(const id of ['arbitrary','__proto__','constructor','toString'])assert.throws(()=>service.audio(id));
 for(let i=0;i<3;i++)await assert.rejects(service.audio('host-0'));
 assert.equal(calls,1);service.stop();assert.throws(()=>service.audio('host-1'));
});
test('malformed or overlong assets are never returned as playable audio',async()=>{
 const service=createPodSmallTalk({logger:{},providers:{speak:async()=>({wav:Buffer.alloc(480045)})}});
 await assert.rejects(service.audio('host-0'));service.stop();
});
