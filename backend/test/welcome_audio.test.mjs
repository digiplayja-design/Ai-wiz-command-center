import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createWelcomeAudio, registerWelcomeAudio, WELCOME_TEXT} from '../welcome/audio.mjs';

const pcm = () => new Response(Buffer.alloc(96000, 1), {headers:{'content-type':'application/octet-stream'}});
test('one fixed Rici clip is coalesced, cached and returned as a valid bounded WAV', async () => {
  let calls = 0, request;
  const audio = createWelcomeAudio({speak: async (payload, options) => {calls++; request={payload,options}; return pcm();}});
  const [a,b] = await Promise.all([audio.get(), audio.get()]);
  assert.equal(calls,1); assert.equal(a,b); assert.equal(await audio.get(),a); assert.equal(calls,1);
  assert.equal(a.toString('ascii',0,4),'RIFF'); assert.equal(a.readUInt32LE(24),24000); assert.equal(a.readUInt32LE(40),96000);
  assert.equal(request.payload.input,WELCOME_TEXT); assert.equal(request.payload.voice,'marin'); assert.equal(request.options.maxRetries,0);
  assert.equal(audio.status().version,2); assert.equal(audio.status().assistant,'Rici'); assert.match(request.payload.instructions,/Rici as Ree-see/); assert(!WELCOME_TEXT.includes('K-Nova')); assert.equal(audio.status().ready,true); assert.equal(audio.status().metered,false);
});
test('provider failures and malformed or oversized audio back off instead of generating on every request', async () => {
  for(const response of [()=>{throw new Error('secret provider error');},()=>new Response('bad',{headers:{'content-type':'text/plain'}}),()=>new Response(Buffer.alloc(1920002)),()=>new Response(Buffer.alloc(48001))]) {
    let now=1000,calls=0;
    const audio=createWelcomeAudio({now:()=>now,speak:async()=>{calls++;return response();}});
    await assert.rejects(audio.get(),e=>!e.message.includes('secret'));
    await assert.rejects(audio.get()); assert.equal(calls,1);
    now+=300001; await assert.rejects(audio.get()); assert.equal(calls,2);
  }
});
test('the public route exposes only the fixed greeting with safe cache headers, never arbitrary speech', async t => {
  const app=express();const calls=[];
  registerWelcomeAudio(app,{speak:async(p)=>{calls.push(p);return pcm();}});
  const server=app.listen(0,'127.0.0.1'); await new Promise(r=>server.once('listening',r));
  t.after(()=>new Promise(r=>server.close(r)));
  const response=await fetch(`http://127.0.0.1:${server.address().port}/api/welcome/rici-v2.wav?input=malicious&voice=other`);
  assert.equal(response.status,200);assert.match(response.headers.get('content-type'),/audio\/wav/);assert.match(response.headers.get('cache-control'),/public/);
  const legacy=await fetch(`http://127.0.0.1:${server.address().port}/api/welcome/knova-v1.wav`); assert.equal(legacy.status,200);
  assert.equal((await response.arrayBuffer()).byteLength,96044);assert.equal(calls.length,1);assert.equal(calls[0].input,WELCOME_TEXT);
});
