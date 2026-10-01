import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {createPodStore} from '../pod/store.mjs';
import {createPodRuntime} from '../pod/runtime.mjs';
import {createPodProviders,validatePodWav} from '../pod/providers.mjs';
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
 const welcomeMigration=(await readdir(dir)).find(n=>n.endsWith('_pod_prompt_welcome_audio.sql'));await db.exec(await readFile(new URL(welcomeMigration,dir),'utf8'));
 store=createPodStore({database:{rpc:async(_name,p)=>{
  try{return {data:(await db.query('select public.korlix_pod_v1($1,$2,$3,$4) r',[p.p_actor,p.p_action,p.p_id,p.p_data])).rows[0].r};}
  catch(error){return {error};}
 }},logger:{warn(){}}});
});
test.beforeEach(async()=>{
 await db.exec('reset role');owner=randomUUID();await db.query('insert into auth.users values($1)',[owner]);await db.exec('set role service_role');
 calls={research:0,turn:0,speak:0,transcribe:0};turnInputs=[];
 providers={
  research:async()=>{calls.research++;return {brief:{text:'Fixture research brief.',sources:[{id:'s1',title:'Fixture source',url:'https://www.nasa.gov/'}],checkedAt:new Date().toISOString()},initialTurn:{speaker:'analyst',text:'The first sourced thought.',sourceIds:['s1']},usage:{kind:'research',status:'completed',usageKnown:true,inputTokens:20,outputTokens:10,totalTokens:30}};},
  turn:async(args)=>{calls.turn++;turnInputs.push(args);return {speaker:calls.turn%2?'host':'analyst',text:args.closing?'Thanks for joining. Here is our concluding thought.':`Host thought ${calls.turn}.`,sourceIds:['s1'],usage:{kind:'turn',status:'completed',usageKnown:true,inputTokens:50,outputTokens:15,totalTokens:65}};},
  speak:async({text})=>{calls.speak++;return {wav:wav(),mime:'audio/wav',durationSeconds:1,usage:{kind:'speak',status:'completed',usageKnown:false,characters:text.length,audioSeconds:1}};},
  transcribe:async()=>{calls.transcribe++;return {text:'I think community access matters.',usage:{kind:'transcribe',status:'completed',usageKnown:true,totalTokens:11,inputAudioTokens:9}};},
 };
 runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
});
test.afterEach(()=>runtime.stop());
test.after(async()=>db.close());

test('actual runtime speaks the fixed welcome first, then commits one sourced research opening and reuses its brief',async()=>{
 const episode=await create(),requestId=randomUUID(),first=await next(episode,requestId);
 assert.equal(first.episode.state,'active');assert.equal(first.turn.speaker,'host');assert.equal(first.turn.seq,1);
 assert.equal(first.audio.mime,'audio/wav');assert.deepEqual(Buffer.from(first.audio.base64,'base64'),wav());
 assert.deepEqual(first.episode.sources,[]);assert.deepEqual((await store.get(owner,episode.id)).brief,{});assert.equal(first.episode.checkedAt,null);
 assert.match(first.turn.text,/Next, we’ll check sources/);
 assert.deepEqual(calls,{research:0,turn:0,speak:1,transcribe:0});assert.equal((await monthly()).total_tokens,0);assert.equal((await monthly()).response_count,0);
 const receipts=(await db.query('select call_key,evidence from korlix_pod_usage_receipts where episode_id=$1 order by call_key',[episode.id])).rows;
 assert.deepEqual(receipts.map(r=>r.call_key),['speak']);assert.equal(receipts[0].evidence.usageKnown,false);
 const replay=await next(first.episode,requestId);assert(replay.replayed);assert.equal(replay.audio.base64,first.audio.base64);assert.equal(calls.turn,0);
 const second=await next(first.episode);assert.equal(second.turn.seq,2);assert.equal(second.episode.deadlineAt,first.episode.deadlineAt);
 assert.equal(second.turn.speaker,'analyst');assert.equal(second.turn.text,'The first sourced thought.');assert.equal(second.episode.sources[0].id,'s1');
 assert.deepEqual(calls,{research:1,turn:0,speak:2,transcribe:0});assert.equal((await monthly()).total_tokens,30);assert.equal((await monthly()).response_count,1);
 const third=await next(second.episode);assert.equal(third.turn.seq,3);assert.equal(third.episode.deadlineAt,first.episode.deadlineAt);
 assert.deepEqual(calls,{research:1,turn:1,speak:3,transcribe:0});assert.equal(turnInputs[0].brief.text,'Fixture research brief.');assert.equal((await monthly()).total_tokens,95);
 runtime.stop();runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
 const lostAudio=await next(third.episode,requestId);assert(lostAudio.replayed);assert.equal(lostAudio.audio,null);assert.equal(lostAudio.audioUnavailable,true);assert.equal(calls.turn,1);
});

test('actual paused voice input is receipted once, reviewed, contributed and included in the resumed discussion',async()=>{
 const welcome=await next(await create());let result=await next(welcome.episode),episode=result.episode;
 episode=(await store.control(owner,episode.id,'pause')).episode;runtime.abort(owner,episode.id);
 const requestId=randomUUID();result=await runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'transcribe',wav:wav()});
 assert.equal(result.text,'I think community access matters.');assert.equal(result.episode.state,'paused');assert.equal(result.episode.turns.length,2);
 const replay=await runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'transcribe',wav:wav()});assert(replay.replayed);assert.equal(calls.transcribe,1);
 const m=await monthly();assert.equal(m.total_tokens,30);assert.equal(m.transcription_tokens,11);assert.equal(m.input_audio_tokens,9);
 episode=(await store.contribute(owner,episode.id,{requestId:randomUUID(),text:'I think affordable community access matters.'})).episode;
 assert.equal(episode.turns.at(-1).speaker,'user');assert.equal(calls.turn,0);
 episode=(await store.control(owner,episode.id,'resume')).episode;result=await next(episode);
 assert.equal(turnInputs.at(-1).episode.turns.at(-1).text,'I think affordable community access matters.');
 assert.equal(result.episode.turns.length,4);assert.equal(result.episode.turns.at(-1).speaker,'host');assert.equal(calls.research,1);
 assert.equal((await monthly()).total_tokens,95);assert.equal((await monthly()).transcription_tokens,11);
});

test('the 36th host turn can commit its closing audio under maxResponses 37, then HTTP next ends without another provider call',async()=>{
 let episode=await create(),last;
 for(let i=0;i<36;i++){last=await next(episode);episode=last.episode;}
 assert.equal(episode.turns.length,36);assert.equal(episode.state,'active');assert(last.audio);
 assert.equal(episode.summary,'Thanks for joining. Here is our concluding thought.');assert.equal(turnInputs.at(-1).closing,true);
 assert.equal(turnInputs.slice(0,-1).some(t=>t.closing),false);assert.deepEqual(calls,{research:1,turn:34,speak:36,transcribe:0});
 const m=await monthly();assert.equal(m.response_count,35);assert.equal(m.total_tokens,30+34*65);
 // Use the real route for its post-playback closing rule, with the same durable store.
 const app=express();app.use(express.json());const api=registerPod(app,{store,providers,access,requireUser:async()=>({id:owner}),logger:{warn(){}},startSweep:false});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 try{
  const response=await fetch(`http://127.0.0.1:${server.address().port}/api/pod/episodes/${episode.id}/next`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestId:randomUUID(),version:episode.version})});
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));assert.equal(body.episode.state,'ended');assert.equal(body.turn,null);assert.equal(body.audio,null);
  assert.deepEqual(calls,{research:1,turn:34,speak:36,transcribe:0});assert.equal((await monthly()).session_count,1);
 }finally{api.stop();server.closeAllConnections();await new Promise(r=>server.close(r));}
});

// Exercise SDK response decoding and provider validation before the runtime and
// durable SQL transaction. Mocking already-parsed providers misses format errors.
async function offlineSdk({sourceUrl='https://www.nasa.gov/missions/',researchStatus=200}={}) {
 const {default:OpenAI}=await import('openai');
 const retrievedUrl='https://www.nasa.gov/missions/';
 const briefText=`## Research notes\n**Verified context:** [NASA missions](${retrievedUrl}) describes a range of missions.\n`+
  'Discussion note: compare the purpose of a mission with the needs of its community, and distinguish evidence from opinion.\n'.repeat(24)+
  'Final caveat: this brief does not verify any new mission, score, quotation or breaking event.';
 assert(briefText.length>2200&&briefText.length<6000);
 const sent=[];
 const client=new OpenAI({apiKey:'pod-offline-integration-fixture-not-a-real-key',
  // Intentionally retain the SDK retry default; provider per-call options must
  // disable it, including when the transport returns a retryable server error.
  fetch:async(url,options)=>{
   const path=new URL(String(url)).pathname,payload=JSON.parse(options.body);
   sent.push({path,payload});
   if(path==='/v1/audio/speech') {
    const speechNumber=sent.filter(call=>call.path==='/v1/audio/speech').length;
    return new Response(Buffer.alloc(48000,speechNumber),{headers:{'content-type':'audio/pcm','x-request-id':`req_speech_${speechNumber}`}});
   }
   assert.equal(path,'/v1/responses','the offline transport never fetches a source URL');
   const researching=payload.text.format.name==='pod_research';
   if(researching&&researchStatus!==200)return new Response(JSON.stringify({error:{message:'Offline upstream failure',type:'server_error'}}),
    {status:researchStatus,headers:{'content-type':'application/json','x-request-id':'req_research_failure'}});
   const value=researching?{text:briefText,currentSourcesAvailable:true,sources:[{url:sourceUrl}],
    opening:{text:'NASA describes a range of missions. What priorities should guide their contribution to communities?',sourceUrls:[sourceUrl]}}:
    {text:'That raises a useful tradeoff: how would we decide which community needs should come first?',sourceIds:['source-1']};
   const usage=researching?{input_tokens:101,output_tokens:38,total_tokens:139,output_tokens_details:{reasoning_tokens:20}}:
    {input_tokens:31,output_tokens:13,total_tokens:44,output_tokens_details:{reasoning_tokens:4}};
   const output=[...(researching?[{type:'web_search_call',id:'ws_fixture',status:'completed',action:{type:'search',sources:[{url:retrievedUrl,title:'NASA missions'}]}}]:[]),
    {type:'message',id:'msg_fixture',status:'completed',role:'assistant',content:[{type:'output_text',text:JSON.stringify(value),annotations:[]}]}];
   return new Response(JSON.stringify({id:researching?'resp_research':'resp_turn',object:'response',status:'completed',output,usage}),
    {headers:{'content-type':'application/json','x-request-id':researching?'req_research':'req_turn'}});
  }});
 runtime.stop();providers=createPodProviders({client});runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
 return {sent,briefText};
}

test('real SDK and providers persist a longer Markdown research brief and deliver three successive voiced turns without research retries',async()=>{
 const {sent}=await offlineSdk();
 const first=await next(await create());
 assert.equal(first.turn.speaker,'host');assert.equal(first.episode.turns.length,1);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech']);
 const secondRequest=randomUUID(),second=await next(first.episode,secondRequest);
 assert.equal(second.turn.speaker,'analyst');assert.equal(second.episode.state,'active');
 const persisted=(await store.get(owner,first.episode.id)).brief;
 assert(persisted.text.length>2200);assert.doesNotMatch(persisted.text,/##|\*\*|\]\(/);
 assert.match(persisted.text,/Final caveat: this brief does not verify any new mission, score, quotation or breaking event\.$/);
 assert.deepEqual(persisted.sources,[{id:'source-1',title:'NASA missions',url:'https://www.nasa.gov/missions/'}]);
 const replay=await next(first.episode,secondRequest);
 assert(replay.replayed);assert.equal(replay.audio.base64,second.audio.base64);assert.equal(sent.length,3);
 const third=await next(second.episode);
 assert.equal(third.turn.speaker,'challenger');assert.equal(third.episode.turns.length,3);assert.equal(third.episode.state,'active');
 assert.equal(third.episode.error,null);assert.equal(third.episode.deadlineAt,first.episode.deadlineAt);
 for(const [index,result] of [first,second,third].entries()) {
  const parsed=validatePodWav(Buffer.from(result.audio.base64,'base64'));
  assert.equal(parsed.durationSeconds,1);assert.equal(parsed.pcm[0],index+1,'each committed turn returns its own decoded audio');
 }
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses','/v1/audio/speech','/v1/responses','/v1/audio/speech']);
 assert.deepEqual(sent.filter(call=>call.path==='/v1/audio/speech').map(call=>call.payload.voice),['marin','cedar','coral']);
 assert.deepEqual(JSON.parse(sent[3].payload.input).brief,persisted,'the next host consumes the complete normalized durable brief');
 const receipts=(await db.query('select call_key,usage,evidence from korlix_pod_usage_receipts where episode_id=$1',[first.episode.id])).rows;
 assert.equal(receipts.length,5);assert.equal(receipts.filter(receipt=>receipt.call_key==='speak').length,3);
 for(const [kind,tokens,request] of [['research',139,'req_research'],['turn',44,'req_turn']]) {
  const receipt=receipts.find(receipt=>receipt.call_key===kind);
  assert.equal(receipt.usage.totalTokens,tokens);assert.equal(receipt.evidence.totalTokens,tokens);
  assert.equal(receipt.evidence.providerRequestId,request);assert.equal(receipt.evidence.status,'completed');
 }
 assert.equal((await monthly()).total_tokens,183);assert.equal((await monthly()).response_count,2);
});

test('real provider validation rejects an invented source after the welcome, persists actual paid usage and never speaks a fallback or retries',async()=>{
 const {sent}=await offlineSdk({sourceUrl:'https://www.nasa.gov/not-retrieved'});
 const first=await next(await create()),requestId=randomUUID();
 await assert.rejects(next(first.episode,requestId),error=>error.code==='POD_SOURCES_UNAVAILABLE');
 const saved=await store.get(owner,first.episode.id);
 assert.equal(saved.episode.state,'failed');assert.equal(saved.episode.turns.length,1);
 assert.match(saved.episode.error,/could not be verified/);assert.deepEqual(saved.brief,{});assert.deepEqual(saved.episode.sources,[]);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses']);
 const receipt=(await db.query("select usage,evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[first.episode.id])).rows[0];
 assert.equal(receipt.usage.totalTokens,139);assert.equal(receipt.evidence.status,'failed');assert.equal(receipt.evidence.usageKnown,true);
 assert.equal((await monthly()).total_tokens,139);
 const replay=await next(first.episode,requestId);
 assert(replay.replayed);assert.equal(replay.audio,null);assert.equal(replay.turn,null);
 await assert.rejects(next(saved.episode),/This pod has ended/);
 assert.equal(sent.length,2,'neither replay nor a new request can repeat failed paid research');
});

test('a retryable research transport failure makes exactly one SDK request and ends the episode visibly',async()=>{
 const {sent}=await offlineSdk({researchStatus:503});
 const first=await next(await create());
 await assert.rejects(next(first.episode),error=>error.code==='POD_PROVIDER_FAILED');
 const saved=await store.get(owner,first.episode.id);
 assert.equal(saved.episode.state,'failed');assert.match(saved.episode.error,/could not complete/);assert.equal(saved.episode.turns.length,1);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses']);
 const receipt=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[first.episode.id])).rows[0];
 assert.equal(receipt.evidence.status,'failed');assert.equal(receipt.evidence.usageKnown,false);assert.equal(receipt.evidence.totalTokens,null);
 assert.equal((await monthly()).total_tokens,0,'unknown tokens must not be invented');
});
