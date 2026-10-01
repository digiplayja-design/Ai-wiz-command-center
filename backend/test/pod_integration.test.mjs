import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {createPodStore} from '../pod/store.mjs';
import {createPodRuntime} from '../pod/runtime.mjs';
import {registerPod} from '../pod/routes.mjs';

let db,store,runtime,owner,calls,turnInputs,providers;
const limits={tier:'ultra',monthlySessions:20,monthlySeconds:10800,monthlyTokens:4000000,maxSessionSeconds:900,maxResponses:37};
const input={category:'technology',topic:'How can technology help a community?',durationSeconds:900,hostCount:3,style:'balanced'};
const access=async()=>({allowed:true,limits});
const create=async()=>(await store.create(owner,{requestId:randomUUID(),input,limits})).episode;
const next=(episode,requestId=randomUUID())=>runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'next'});
const monthly=async()=>(await db.query('select * from korlix_live_convo_monthly_usage where user_id=$1',[owner])).rows[0];
const wav=()=>{
 const b=Buffer.alloc(48044);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);
 b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(24000,24);
 b.writeUInt32LE(48000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(48000,40);return b;
};
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);');
 const dir=new URL('../../supabase/migrations/',import.meta.url);
 await db.exec(await readFile(new URL('202607120001_live_convo_limits_build129.sql',dir),'utf8'));
 const name=(await readdir(dir)).find(n=>n.endsWith('_pod_personal_beta.sql'));await db.exec(await readFile(new URL(name,dir),'utf8'));
 store=createPodStore({database:{rpc:async(_name,p)=>{
  try{return {data:(await db.query('select public.korlix_pod_v1($1,$2,$3,$4) r',[p.p_actor,p.p_action,p.p_id,p.p_data])).rows[0].r};}
  catch(error){return {error};}
 }},logger:{warn(){}}});
});
test.beforeEach(async()=>{
 await db.exec('reset role');owner=randomUUID();await db.query('insert into auth.users values($1)',[owner]);await db.exec('set role service_role');
 calls={research:0,turn:0,speak:0,transcribe:0};turnInputs=[];
 providers={
  research:async()=>{calls.research++;return {brief:{text:'Fixture research brief.',sources:[{id:'s1',title:'Fixture source',url:'https://www.nasa.gov/'}],checkedAt:new Date().toISOString()},usage:{kind:'research',status:'completed',usageKnown:true,inputTokens:20,outputTokens:10,totalTokens:30}};},
  turn:async(args)=>{calls.turn++;turnInputs.push(args);return {speaker:calls.turn%2?'host':'analyst',text:args.closing?'Thanks for joining. Here is our concluding thought.':`Host thought ${calls.turn}.`,sourceIds:['s1'],usage:{kind:'turn',status:'completed',usageKnown:true,inputTokens:50,outputTokens:15,totalTokens:65}};},
  speak:async({text})=>{calls.speak++;return {wav:wav(),mime:'audio/wav',durationSeconds:1,usage:{kind:'speak',status:'completed',usageKnown:false,characters:text.length,audioSeconds:1}};},
  transcribe:async()=>{calls.transcribe++;return {text:'I think community access matters.',usage:{kind:'transcribe',status:'completed',usageKnown:true,totalTokens:11,inputAudioTokens:9}};},
 };
 runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
});
test.afterEach(()=>runtime.stop());
test.after(async()=>db.close());

test('actual runtime commits research, turn and speech receipts, then reuses its durable brief and replayed audio',async()=>{
 const episode=await create(),requestId=randomUUID(),first=await next(episode,requestId);
 assert.equal(first.episode.state,'active');assert.equal(first.turn.speaker,'host');assert.equal(first.turn.seq,1);
 assert.equal(first.audio.mime,'audio/wav');assert.deepEqual(Buffer.from(first.audio.base64,'base64'),wav());
 assert.equal(first.episode.sources[0].id,'s1');assert.equal((await store.get(owner,episode.id)).brief.text,'Fixture research brief.');
 assert.deepEqual(calls,{research:1,turn:1,speak:1,transcribe:0});assert.equal((await monthly()).total_tokens,95);
 const receipts=(await db.query('select call_key,evidence from korlix_pod_usage_receipts where episode_id=$1 order by call_key',[episode.id])).rows;
 assert.deepEqual(receipts.map(r=>r.call_key),['research','speak','turn']);assert.equal(receipts.find(r=>r.call_key==='speak').evidence.usageKnown,false);
 const replay=await next(first.episode,requestId);assert(replay.replayed);assert.equal(replay.audio.base64,first.audio.base64);assert.equal(calls.turn,1);
 const second=await next(first.episode);assert.equal(second.turn.seq,2);assert.equal(second.episode.deadlineAt,first.episode.deadlineAt);
 assert.deepEqual(calls,{research:1,turn:2,speak:2,transcribe:0});assert.equal(turnInputs[1].brief.text,'Fixture research brief.');assert.equal((await monthly()).total_tokens,160);
 runtime.stop();runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
 const lostAudio=await next(second.episode,requestId);assert(lostAudio.replayed);assert.equal(lostAudio.audio,null);assert.equal(lostAudio.audioUnavailable,true);assert.equal(calls.turn,2);
});

test('actual paused voice input is receipted once, reviewed, contributed and included in the resumed discussion',async()=>{
 let result=await next(await create()),episode=result.episode;
 episode=(await store.control(owner,episode.id,'pause')).episode;runtime.abort(owner,episode.id);
 const requestId=randomUUID();result=await runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'transcribe',wav:wav()});
 assert.equal(result.text,'I think community access matters.');assert.equal(result.episode.state,'paused');assert.equal(result.episode.turns.length,1);
 const replay=await runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'transcribe',wav:wav()});assert(replay.replayed);assert.equal(calls.transcribe,1);
 const m=await monthly();assert.equal(m.total_tokens,95);assert.equal(m.transcription_tokens,11);assert.equal(m.input_audio_tokens,9);
 episode=(await store.contribute(owner,episode.id,{requestId:randomUUID(),text:'I think affordable community access matters.'})).episode;
 assert.equal(episode.turns.at(-1).speaker,'user');assert.equal(calls.turn,1);
 episode=(await store.control(owner,episode.id,'resume')).episode;result=await next(episode);
 assert.equal(turnInputs.at(-1).episode.turns.at(-1).text,'I think affordable community access matters.');
 assert.equal(result.episode.turns.length,3);assert.equal(result.episode.turns.at(-1).speaker,'analyst');assert.equal(calls.research,1);
 assert.equal((await monthly()).total_tokens,160);assert.equal((await monthly()).transcription_tokens,11);
});

test('the 36th host turn can commit its closing audio under maxResponses 37, then HTTP next ends without another provider call',async()=>{
 let episode=await create(),last;
 for(let i=0;i<36;i++){last=await next(episode);episode=last.episode;}
 assert.equal(episode.turns.length,36);assert.equal(episode.state,'active');assert(last.audio);
 assert.equal(episode.summary,'Thanks for joining. Here is our concluding thought.');assert.equal(turnInputs.at(-1).closing,true);
 assert.equal(turnInputs.slice(0,35).some(t=>t.closing),false);assert.deepEqual(calls,{research:1,turn:36,speak:36,transcribe:0});
 const m=await monthly();assert.equal(m.response_count,36);assert.equal(m.total_tokens,30+36*65);
 // Use the real route for its post-playback closing rule, with the same durable store.
 const app=express();app.use(express.json());const api=registerPod(app,{store,providers,access,requireUser:async()=>({id:owner}),logger:{warn(){}},startSweep:false});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 try{
  const response=await fetch(`http://127.0.0.1:${server.address().port}/api/pod/episodes/${episode.id}/next`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestId:randomUUID(),version:episode.version})});
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));assert.equal(body.episode.state,'ended');assert.equal(body.turn,null);assert.equal(body.audio,null);
  assert.deepEqual(calls,{research:1,turn:36,speak:36,transcribe:0});assert.equal((await monthly()).session_count,1);
 }finally{api.stop();server.closeAllConnections();await new Promise(r=>server.close(r));}
});
