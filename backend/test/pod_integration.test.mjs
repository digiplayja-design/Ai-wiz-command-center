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
const create=async(overrides={})=>(await store.create(owner,{requestId:randomUUID(),input:{...input,...overrides},limits})).episode;
const next=(episode,requestId=randomUUID())=>runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'next'});
const prepare=(episode,requestId=randomUUID())=>runtime.run({user:{id:owner},id:episode.id,version:episode.version,requestId,kind:'prepare'});
const playPrepared=(episode,requestId)=>runtime.playPrepared({user:{id:owner},id:episode.id,version:episode.version,requestId});
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
 const preparedMigration=(await readdir(dir)).find(n=>n.endsWith('_pod_prepared_turn_buffer.sql'));assert(preparedMigration,'prepared-turn migration is required');
 await db.exec(await readFile(new URL(preparedMigration,dir),'utf8'));
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
async function offlineSdk({sourceUrl,researchStatus=200,researchTransportError=false,requiresCurrentSources=false,currentSourcesAvailable=true,evergreenSports=false,
 musicComparison=false,comparisonBackground=null}={}) {
 const {default:OpenAI}=await import('openai');
 const retrievedUrl=musicComparison?'https://www.grammy.com/artists/shaggy':evergreenSports?'https://www.olympics.com/ioc/olympic-values':'https://www.nasa.gov/missions/';
 sourceUrl??=retrievedUrl;
 const sourceTitle=musicComparison?'Dated music-profile fixture':evergreenSports?'Teamwork source fixture':'NASA missions';
 const briefText=musicComparison?'UNVERIFIED_CURRENT_SENTINEL: This main research branch cannot establish a verified winner right now.':
  evergreenSports?'Verified historical fixture: a dated coaching resource describes cooperation and complementary team roles. '+
  'This is an evergreen discussion of teamwork, not an update on any current team, season, player record or game.':
  `## Research notes\n**Verified context:** [NASA missions](${retrievedUrl}) describes a range of missions.\n`+
  'Discussion note: compare the purpose of a mission with the needs of its community, and distinguish evidence from opinion.\n'.repeat(24)+
  'Final caveat: this brief does not verify any new mission, score, quotation or breaking event.';
 if(!evergreenSports&&!musicComparison)assert(briefText.length>2200&&briefText.length<6000);
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
   if(researching&&researchTransportError)throw new TypeError('Offline connection lost after dispatch');
   if(researching&&researchStatus!==200)return new Response(JSON.stringify({error:{message:'Offline upstream failure',type:'server_error'}}),
    {status:researchStatus,headers:{'content-type':'application/json','x-request-id':'req_research_failure'}});
   const value=researching?{text:briefText,requiresCurrentSources,currentSourcesAvailable,sources:[{url:sourceUrl}],comparisonBackground,
    opening:{text:musicComparison?'UNVERIFIED_CURRENT_SENTINEL: I cannot establish a current winner.':
     evergreenSports?'Cooperation is one way to think about team roles. How should a team balance individual strengths with working together?':
     'NASA describes a range of missions. What priorities should guide their contribution to communities?',sourceUrls:[sourceUrl]}}:
    {text:musicComparison?'Those are different measures of reach. Which historical measure matters most to you?':
     'That raises a useful tradeoff: how would we decide which community needs should come first?',sourceIds:['source-1']};
   const usage=researching?{input_tokens:101,output_tokens:38,total_tokens:139,output_tokens_details:{reasoning_tokens:20}}:
    {input_tokens:31,output_tokens:13,total_tokens:44,output_tokens_details:{reasoning_tokens:4}};
   const output=[...(researching?[{type:'web_search_call',id:'ws_fixture',status:'completed',action:{type:'search',sources:[{url:retrievedUrl,title:sourceTitle}]}}]:[]),
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

test('real SDK, providers and SQL continue an evergreen sports pod beyond the welcome without live-news freshness',async()=>{
 const {sent}=await offlineSdk({requiresCurrentSources:false,currentSourcesAvailable:false,evergreenSports:true});
 const first=await next(await create({category:'sports',topic:'What makes a great team beyond individual talent?'}));
 const second=await next(first.episode),third=await next(second.episode);
 assert.deepEqual([first,second,third].map(result=>result.turn.speaker),['host','analyst','challenger']);
 assert.equal(third.episode.state,'active');assert.equal(third.episode.error,null);
 assert.equal(third.episode.deadlineAt,first.episode.deadlineAt);
 for(const result of [first,second,third])assert.equal(validatePodWav(Buffer.from(result.audio.base64,'base64')).durationSeconds,1);
 const persisted=(await store.get(owner,first.episode.id)).brief;
 assert.match(persisted.text,/evergreen discussion of teamwork/);
 assert.deepEqual(persisted.sources,[{id:'source-1',title:'Teamwork source fixture',url:'https://www.olympics.com/ioc/olympic-values'}]);
 assert.deepEqual(JSON.parse(sent[3].payload.input).brief,persisted);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses','/v1/audio/speech','/v1/responses','/v1/audio/speech']);
 assert.deepEqual(sent.filter(call=>call.path==='/v1/audio/speech').map(call=>call.payload.voice),['marin','cedar','coral']);
 const receipts=(await db.query('select call_key,evidence from korlix_pod_usage_receipts where episode_id=$1',[first.episode.id])).rows;
 assert.equal(receipts.length,5);assert.equal(receipts.filter(receipt=>receipt.call_key==='research').length,1);
 assert.equal(receipts.find(receipt=>receipt.call_key==='research').evidence.totalTokens,139);
 assert.equal((await monthly()).total_tokens,183);assert.equal((await monthly()).response_count,2);
});

test('real SDK, providers and SQL stop live sports with unverified freshness and retain precise private diagnostics',async()=>{
 const {sent}=await offlineSdk({requiresCurrentSources:false,currentSourcesAvailable:false,evergreenSports:true});
 const first=await next(await create({category:'sports',topic:'What are the live scores today?'})),requestId=randomUUID();
 await assert.rejects(next(first.episode,requestId),error=>error.code==='POD_SOURCES_UNAVAILABLE');
 const saved=await store.get(owner,first.episode.id);
 assert.equal(saved.episode.state,'failed');assert.equal(saved.episode.turns.length,1);
 assert.deepEqual(saved.brief,{});assert.deepEqual(saved.episode.sources,[]);
 const receipt=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[first.episode.id])).rows[0];
 assert.equal(receipt.evidence.status,'failed');assert.equal(receipt.evidence.totalTokens,139);
 assert.equal(receipt.evidence.diagnostic.reason,'current_information_unverified');
 assert.equal(receipt.evidence.diagnostic.requiresCurrentSources,true);
 assert.equal(receipt.evidence.diagnostic.currentSourcesAvailable,false);
 assert.doesNotMatch(JSON.stringify(receipt.evidence.diagnostic),/https?:|live scores|olympics/);
 const replay=await next(first.episode,requestId);assert(replay.replayed);assert.equal(replay.audio,null);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses']);
 assert.equal((await monthly()).total_tokens,139);
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

test('real SDK, providers and SQL prepare one panelist privately, charge actual usage, and consume the cached speech exactly once',async()=>{
 const {sent}=await offlineSdk();
 const welcome=await next(await create()),requestId=randomUUID();
 const staged=await prepare(welcome.episode,requestId);
 assert.equal(staged.prepared,true);assert.equal(staged.preparedId,requestId);
 assert.equal(staged.audio,undefined);assert.equal(staged.turn,undefined);
 assert.equal(staged.episode.state,'active');assert.equal(staged.episode.turns.length,1);
 assert.equal(staged.episode.preparedId,requestId);assert.equal(staged.episode.deadlineAt,welcome.episode.deadlineAt);
 const saved=await store.get(owner,welcome.episode.id);
 assert.deepEqual(saved.brief,{});assert.deepEqual(saved.episode.sources,[]);
 assert.equal(saved.episode.turns[0].speaker,'host','an unheard panelist is absent from the transcript');
 assert.equal((await monthly()).total_tokens,139);assert.equal((await monthly()).response_count,1);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses','/v1/audio/speech']);
 const replay=await prepare(staged.episode,requestId);
 assert(replay.replayed);assert.equal(replay.preparedId,requestId);assert.equal(replay.audioUnavailable,false);
 await assert.rejects(prepare(staged.episode),error=>error.status===409);
 await assert.rejects(next(staged.episode),error=>error.status===409);
 assert.equal(sent.length,3,'another request cannot bypass the one-prepared-turn limit');
 const playing=await playPrepared(staged.episode,requestId);
 assert.equal(playing.turn.speaker,'analyst');assert.equal(playing.turn.seq,2);
 assert.equal(playing.episode.turns.length,2);assert.equal(playing.episode.preparedId,null);
 assert.equal(validatePodWav(Buffer.from(playing.audio.base64,'base64')).pcm[0],2);
 const replayPlaying=await playPrepared(playing.episode,requestId);
 assert(replayPlaying.replayed);assert.equal(replayPlaying.turn.seq,2);assert.equal(replayPlaying.episode.turns.length,2);
 assert.equal(replayPlaying.audio.base64,playing.audio.base64);assert.equal(sent.length,3);
 const thirdId=randomUUID(),thirdPrepared=await prepare(playing.episode,thirdId);
 assert.equal(thirdPrepared.episode.turns.length,2);
 const third=await playPrepared(thirdPrepared.episode,thirdId);
 assert.equal(third.turn.speaker,'challenger');assert.equal(third.turn.seq,3);
 assert.equal(validatePodWav(Buffer.from(third.audio.base64,'base64')).pcm[0],3);
 assert.equal(third.episode.deadlineAt,welcome.episode.deadlineAt);
 const persisted=(await store.get(owner,welcome.episode.id)).brief;
 assert.deepEqual(JSON.parse(sent[3].payload.input).brief,persisted,'the prepared next voice consumes the durable, verified brief');
 assert.deepEqual(sent.filter(call=>call.path==='/v1/audio/speech').map(call=>call.payload.voice),['marin','cedar','coral']);
 const receipts=(await db.query('select call_key,evidence from korlix_pod_usage_receipts where episode_id=$1',[welcome.episode.id])).rows;
 assert.equal(receipts.length,5);assert.equal(receipts.filter(receipt=>receipt.call_key==='speak').length,3);
 assert.equal((await monthly()).total_tokens,183);assert.equal((await monthly()).response_count,2);
});

test('prepared speech survives an ordinary pause and resumes with the current version without another SDK call',async()=>{
 const {sent}=await offlineSdk();
 const welcome=await next(await create()),requestId=randomUUID(),staged=await prepare(welcome.episode,requestId);
 let episode=(await store.control(owner,welcome.episode.id,'pause')).episode;
 runtime.abort(owner,episode.id,'Episode playback changed.',{preservePrepared:true});
 assert.equal(episode.state,'paused');assert.equal(episode.preparedId,requestId);
 await assert.rejects(playPrepared(episode,requestId),error=>error.status===409);
 episode=(await store.control(owner,episode.id,'resume')).episode;
 assert.notEqual(episode.version,staged.episode.version);
 await assert.rejects(playPrepared(staged.episode,requestId),error=>error.status===409);
 const playing=await playPrepared(episode,requestId);
 assert.equal(playing.turn.seq,2);assert.equal(playing.turn.speaker,'analyst');
 assert.equal(playing.episode.deadlineAt,welcome.episode.deadlineAt);
 assert.equal(validatePodWav(Buffer.from(playing.audio.base64,'base64')).pcm[0],2);
 assert.equal(sent.length,3);assert.equal((await monthly()).total_tokens,139);
});

test('another owner cannot consume prepared speech, and process cache loss cannot commit unheard text or repeat paid generation',async()=>{
 const {sent}=await offlineSdk();
 const welcome=await next(await create()),requestId=randomUUID(),staged=await prepare(welcome.episode,requestId);
 const otherOwner=randomUUID();
 await assert.rejects(runtime.playPrepared({user:{id:otherOwner},id:welcome.episode.id,version:staged.episode.version,requestId}));
 await assert.rejects(store.playPrepared(otherOwner,welcome.episode.id,{version:staged.episode.version,requestId}),error=>error.status===404);
 assert.equal((await store.get(owner,welcome.episode.id)).episode.turns.length,1);
 runtime.stop();runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
 const replay=await prepare(staged.episode,requestId);
 assert(replay.replayed);assert.equal(replay.audioUnavailable,true);
 await assert.rejects(playPrepared(staged.episode,requestId),error=>error.code==='pod_prepared_audio_unavailable');
 await assert.rejects(prepare(staged.episode,requestId),error=>error.code==='pod_preparation_unavailable');
 await assert.rejects(prepare(staged.episode),error=>error.status===409);
 const saved=await store.get(owner,welcome.episode.id);
 assert.equal(saved.episode.turns.length,1);assert.equal(saved.episode.preparedId,null);
 assert.match(saved.episode.preparationError,/audio expired/);
 assert.deepEqual(saved.brief,{});assert.equal(sent.length,3);
 assert.equal((await monthly()).total_tokens,139,'already incurred research usage remains accounted after cache loss');
});

test('chiming in discards the prepared reply and supplies the contribution to the next sourced response',async()=>{
 const {sent}=await offlineSdk();
 const welcome=await next(await create()),oldId=randomUUID();await prepare(welcome.episode,oldId);
 let episode=(await store.control(owner,welcome.episode.id,'interrupt')).episode;runtime.abort(owner,episode.id);
 assert.equal(episode.preparedId,null);assert.equal(episode.turns.length,1);
 const contribution='How can a mission serve communities with limited internet access?';
 episode=(await store.contribute(owner,episode.id,{requestId:randomUUID(),text:contribution})).episode;runtime.abort(owner,episode.id);
 episode=(await store.control(owner,episode.id,'resume')).episode;
 await assert.rejects(playPrepared(episode,oldId),error=>error.status===409);
 const newId=randomUUID(),staged=await prepare(episode,newId);
 assert.deepEqual(JSON.parse(sent[3].payload.input).contributions,[contribution]);
 assert.equal(staged.episode.turns.length,2);assert.equal(staged.episode.turns.at(-1).speaker,'user');
 const playing=await playPrepared(staged.episode,newId);
 assert.deepEqual(playing.episode.turns.map(turn=>turn.speaker),['host','user','analyst']);
 assert.equal(validatePodWav(Buffer.from(playing.audio.base64,'base64')).pcm[0],3,'only the new prepared speech can be delivered');
 assert.equal((await monthly()).total_tokens,278,'discarded, actually generated research still counts');
 assert.equal((await monthly()).response_count,2);
 assert.equal(sent.length,5);
});

test('a sourced preparation failure leaves the current panelist intact and durably blocks automatic paid retries',async()=>{
 const {sent}=await offlineSdk({sourceUrl:'https://www.nasa.gov/not-retrieved'});
 const welcomeId=randomUUID(),welcome=await next(await create(),welcomeId),requestId=randomUUID();
 await assert.rejects(prepare(welcome.episode,requestId),error=>error.code==='POD_SOURCES_UNAVAILABLE');
 let episode=(await store.get(owner,welcome.episode.id)).episode;
 assert.equal(episode.state,'active');assert.equal(episode.version,welcome.episode.version);
 assert.equal(episode.turns.length,1);assert.equal(episode.preparedId,null);
 assert.match(episode.preparationError,/could not be verified/);
 assert.equal(episode.deadlineAt,welcome.episode.deadlineAt);
 await assert.rejects(prepare(episode,requestId),error=>error.code==='pod_preparation_unavailable');
 await assert.rejects(prepare(episode),error=>error.status===409);
 await assert.rejects(next(episode),error=>error.status===409);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses']);
 const replayWelcome=await next(episode,welcomeId);
 assert(replayWelcome.replayed);assert.equal(replayWelcome.audio.base64,welcome.audio.base64);
 assert.equal(sent.length,2,'the current committed speech can replay without another dispatch');
 const receipt=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[episode.id])).rows[0];
 assert.equal(receipt.evidence.totalTokens,139);assert.equal(receipt.evidence.status,'failed');
 assert.equal((await monthly()).total_tokens,139);
 episode=(await store.control(owner,episode.id,'pause')).episode;runtime.abort(owner,episode.id,'Episode playback changed.',{preservePrepared:true});
 episode=(await store.control(owner,episode.id,'resume')).episode;
 assert.equal(episode.preparationError,null);
 await assert.rejects(prepare(episode),error=>error.code==='POD_SOURCES_UNAVAILABLE');
 assert.equal(sent.length,3,'only explicit pause/resume recovery permits a fresh paid attempt');
 assert.equal((await monthly()).total_tokens,278);
});

test('uncertain transport usage during preparation cannot be retried by resume or a fresh request',async()=>{
 const {sent}=await offlineSdk({researchTransportError:true});
 const welcome=await next(await create()),requestId=randomUUID();
 await assert.rejects(prepare(welcome.episode,requestId),error=>error.code==='POD_PROVIDER_FAILED');
 let episode=(await store.get(owner,welcome.episode.id)).episode;
 assert.equal(episode.turns.length,1);assert(episode.preparationError);
 await assert.rejects(prepare(episode),error=>error.status===409);
 episode=(await store.control(owner,episode.id,'pause')).episode;runtime.abort(owner,episode.id,'Episode playback changed.',{preservePrepared:true});
 await assert.rejects(store.control(owner,episode.id,'resume'));
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses']);
 const receipt=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[episode.id])).rows[0];
 assert.equal(receipt.evidence.usageKnown,false);assert.equal(receipt.evidence.totalTokens,null);assert.equal(receipt.evidence.status,'uncertain');
 assert.equal((await monthly()).total_tokens,0,'unknown usage is never replaced with an invented estimate');
});

test('a late preparation response after pause is receipted but cannot append or cache stale speech',async()=>{
 const welcome=await next(await create()),opening=await next(welcome.episode);
 let release,started;const entered=new Promise(resolve=>{started=resolve;});
 const originalTurn=providers.turn;
 providers.turn=async args=>{const value=await originalTurn(args);started();await new Promise(resolve=>{release=resolve;});return value;};
 const requestId=randomUUID(),preparing=prepare(opening.episode,requestId);
 await entered;
 let episode=(await store.control(owner,opening.episode.id,'pause')).episode;
 runtime.abort(owner,episode.id,'Episode playback changed.',{preservePrepared:true});release();
 await assert.rejects(preparing);
 const saved=await store.get(owner,episode.id);
 assert.equal(saved.episode.state,'paused');assert.equal(saved.episode.turns.length,2);assert.equal(saved.episode.preparedId,null);
 assert.deepEqual(calls,{research:1,turn:1,speak:2,transcribe:0});
 const receipt=(await db.query("select usage,evidence from korlix_pod_usage_receipts where episode_id=$1 and request_id=$2 and call_key='turn'",[episode.id,requestId])).rows[0];
 assert.equal(receipt.usage.totalTokens,65);assert.equal((await monthly()).total_tokens,95);
 await assert.rejects(playPrepared(saved.episode,requestId),error=>error.status===409);
});

test('real HTTP prepare exposes only safe metadata and play-prepared delivers the matching cached WAV once',async()=>{
 const {sent}=await offlineSdk(),created=await create();
 const app=express();app.use(express.json());
 const api=registerPod(app,{store,providers,access,requireUser:async()=>({id:owner}),logger:{warn(){}},startSweep:false});
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
 const baseUrl=`http://127.0.0.1:${server.address().port}/api/pod/episodes/${created.id}`;
 const request=async(path,body)=>{
  const response=await fetch(`${baseUrl}${path}`,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const value=await response.json();assert.equal(response.status,200,JSON.stringify(value));
  assert.equal(response.headers.get('cache-control'),'no-store');return value;
 };
 try {
  const welcome=await request('/next',{requestId:randomUUID(),version:created.version});
  const preparedId=randomUUID(),prepared=await request('/prepare',{requestId:preparedId,version:welcome.episode.version});
  assert.deepEqual(Object.keys(prepared).sort(),['episode','prepared','preparedId']);
  assert.equal(prepared.preparedId,preparedId);assert.equal(prepared.episode.preparedId,preparedId);
  assert.equal(prepared.episode.turns.length,1);assert.deepEqual(prepared.episode.sources,[]);
  assert.doesNotMatch(JSON.stringify(prepared),/research notes|Final caveat|NASA describes a range|providerRequestId|resp_research/);
  const read=await request('');assert.equal(read.episode.turns.length,1);assert.equal(read.episode.brief,undefined);
  const played=await request('/play-prepared',{requestId:preparedId,version:prepared.episode.version});
  assert.equal(played.turn.speaker,'analyst');assert.equal(played.turn.seq,2);assert.equal(played.episode.preparedId,null);
  assert.equal(validatePodWav(Buffer.from(played.audio.base64,'base64')).pcm[0],2);
  const replay=await request('/play-prepared',{requestId:preparedId,version:played.episode.version});
  assert.equal(replay.replayed,true);assert.equal(replay.audio.base64,played.audio.base64);
  assert.equal(replay.episode.turns.length,2);assert.equal(sent.length,3);
  assert.equal((await monthly()).total_tokens,139);
 }finally{api.stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});

test('real HTTP paused heartbeats preserve in-flight transcription and the reviewed contribution reaches the resumed panelist',async()=>{
 const created=await create();let release,started,transcriptionSignal;
 const entered=new Promise(resolve=>{started=resolve;}),finishTranscription=new Promise(resolve=>{release=resolve;});
 const originalTranscribe=providers.transcribe;
 providers.transcribe=async args=>{
  transcriptionSignal=args.signal;started();await finishTranscription;
  args.signal.throwIfAborted();return originalTranscribe(args);
 };
 const app=express();app.use(express.json());
 const api=registerPod(app,{store,providers,access,requireUser:async()=>({id:owner}),logger:{warn(){}},startSweep:false});
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
 const baseUrl=`http://127.0.0.1:${server.address().port}/api/pod/episodes/${created.id}`;
 const request=async(path,body)=>{
  const response=await fetch(`${baseUrl}${path}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const value=await response.json();assert.equal(response.status,200,JSON.stringify(value));return value;
 };
 try {
  const welcome=await request('/next',{requestId:randomUUID(),version:created.version});
  const opening=await request('/next',{requestId:randomUUID(),version:welcome.episode.version});
  const paused=await request('/control',{action:'interrupt'}),requestId=randomUUID();
  const pending=request('/transcribe',{requestId,audioBase64:wav().toString('base64')})
   .then(value=>({value}),error=>({error}));
  await entered;assert.equal(api.runtime.activeCount,1);
  const heartbeat=await request('/control',{action:'heartbeat'});
  assert.equal(heartbeat.episode.state,'paused');assert.equal(heartbeat.episode.version,paused.episode.version);
  const secondHeartbeat=await request('/control',{action:'heartbeat'});
  assert.equal(secondHeartbeat.episode.version,paused.episode.version);
  const wasAborted=transcriptionSignal.aborted;release();
  const transcribed=await pending;
  assert.equal(wasAborted,false,'a routine heartbeat must not cancel transcription in an already-paused pod');
  if(transcribed.error)throw transcribed.error;
  assert.equal(transcribed.value.text,'I think community access matters.');
  assert.equal(transcribed.value.episode.state,'paused');assert.equal(transcribed.value.episode.turns.length,2);
  const replay=await request('/transcribe',{requestId,audioBase64:wav().toString('base64')});
  assert(replay.replayed);assert.equal(replay.text,transcribed.value.text);assert.equal(calls.transcribe,1);
  const contribution='I think affordable community access matters most.',contributionId=randomUUID();
  const contributed=await request('/contributions',{requestId:contributionId,text:contribution});
  assert.equal(contributed.episode.turns.at(-1).speaker,'user');assert.equal(contributed.episode.turns.at(-1).text,contribution);
  const resumed=await request('/control',{action:'resume'});
  const panelist=await request('/next',{requestId:randomUUID(),version:resumed.episode.version});
  assert.equal(turnInputs.at(-1).episode.turns.at(-1).text,contribution);
  assert.deepEqual(panelist.episode.turns.map(turn=>turn.speaker),['host','analyst','user','host']);
  assert.equal(panelist.episode.deadlineAt,opening.episode.deadlineAt);assert(panelist.audio);
  assert.deepEqual(calls,{research:1,turn:1,speak:3,transcribe:1});
  const receipts=(await db.query("select usage,evidence from korlix_pod_usage_receipts where episode_id=$1 and request_id=$2 and call_key='transcribe'",[created.id,requestId])).rows;
  assert.equal(receipts.length,1);assert.equal(receipts[0].usage.transcriptionTokens,11);
  assert.equal((await monthly()).total_tokens,95);assert.equal((await monthly()).transcription_tokens,11);
 }finally{release();api.stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});

const datedComparisonFixture=()=>({
 text:'A fixture music profile published in 2001 describes international crossover as distinct from regional scene influence. '+
  'This is dated background, not current reach or a current ranking.',
 sources:[{url:'https://www.grammy.com/artists/shaggy'}],
 opening:{text:'A dated profile describes international crossover. That is a different measure from influence within a music scene.',
  sourceUrls:['https://www.grammy.com/artists/shaggy']},
});

test('real SDK and prepared pipeline carry a disclosed dated comparison through durable storage, restart and listener input without a second research charge',async()=>{
 const background=datedComparisonFixture();
 const {sent}=await offlineSdk({musicComparison:true,sourceUrl:'https://www.grammy.com/unverified-current-data',
  requiresCurrentSources:true,currentSourcesAvailable:false,comparisonBackground:background});
 const welcome=await next(await create({category:'trending',topic:'Kartel or Shaggy who is bigger right now?'}));
 const preparedId=randomUUID(),staged=await prepare(welcome.episode,preparedId);
 assert.equal(staged.prepared,true);assert.equal(staged.episode.turns.length,1);
 assert.equal(staged.turn,undefined);assert.equal(staged.audio,undefined);
 assert.doesNotMatch(JSON.stringify(staged),/dated profile describes|UNVERIFIED_CURRENT_SENTINEL/);
 assert.deepEqual((await store.get(owner,welcome.episode.id)).brief,{},'unheard dated context stays out of the committed brief');
 const replayStaged=await prepare(staged.episode,preparedId);assert(replayStaged.replayed);assert.equal(sent.length,3);
 const first=await playPrepared(staged.episode,preparedId);
 assert.equal(first.turn.speaker,'analyst');
 assert.equal(first.turn.text,'I couldn’t verify a current ranking. Let’s compare the verified background, without calling a winner right now. '+background.opening.text);
 assert.equal(sent[2].payload.input,first.turn.text,'the disclosure reaches actual speech synthesis');
 assert.doesNotMatch(first.turn.text,/UNVERIFIED_CURRENT_SENTINEL/);
 assert.equal(first.episode.deadlineAt,welcome.episode.deadlineAt);
 const persisted=(await store.get(owner,welcome.episode.id)).brief;
 assert.equal(persisted.evidenceMode,'comparison_background');
 assert(persisted.text.includes(background.text));assert.doesNotMatch(JSON.stringify(persisted),/UNVERIFIED_CURRENT_SENTINEL|unverified-current-data/);
 const replayPlaying=await playPrepared(first.episode,preparedId);
 assert(replayPlaying.replayed);assert.equal(replayPlaying.audio.base64,first.audio.base64);assert.equal(sent.length,3);
 runtime.stop();runtime=createPodRuntime({store,providers,access,logger:{warn(){}}});
 let episode=(await store.control(owner,first.episode.id,'interrupt')).episode;runtime.abort(owner,episode.id);
 const contribution='Please say who is more popular today, even if you have to estimate.';
 episode=(await store.contribute(owner,episode.id,{requestId:randomUUID(),text:contribution})).episode;
 episode=(await store.control(owner,episode.id,'resume')).episode;
 const nextId=randomUUID(),nextStaged=await prepare(episode,nextId);
 assert.equal(nextStaged.episode.turns.length,3);assert.equal(nextStaged.episode.turns.at(-1).speaker,'user');
 const followupInput=JSON.parse(sent[3].payload.input);
 assert.deepEqual(followupInput.brief,persisted,'a new runtime reads and preserves the durable restriction');
 assert.equal(followupInput.brief.evidenceMode,'comparison_background');
 assert.equal(followupInput.transcript.at(-1).text,contribution);
 assert.match(sent[3].payload.instructions,/comparison_background/);
 const followup=await playPrepared(nextStaged.episode,nextId);
 assert.equal(followup.turn.speaker,'challenger');assert.equal(followup.episode.turns.length,4);
 assert.equal(followup.episode.deadlineAt,welcome.episode.deadlineAt);
 assert.equal((await store.get(owner,episode.id)).brief.evidenceMode,'comparison_background');
 for(const [index,result] of [welcome,first,followup].entries())assert.equal(validatePodWav(Buffer.from(result.audio.base64,'base64')).pcm[0],index+1);
 assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses','/v1/audio/speech','/v1/responses','/v1/audio/speech']);
 assert.equal(sent.filter(call=>call.payload.text?.format.name==='pod_research').length,1);
 const receipts=(await db.query('select call_key,usage from korlix_pod_usage_receipts where episode_id=$1',[episode.id])).rows;
 assert.equal(receipts.length,5);assert.equal(receipts.filter(receipt=>receipt.call_key==='research').length,1);
 assert.equal((await monthly()).total_tokens,183);assert.equal((await monthly()).response_count,2);
});

test('real SDK and SQL reject missing or unverified comparison background and never use it to answer a live factual request',async()=>{
 const comparisonTopic='Kartel or Shaggy who is bigger right now?';
 const cases=[
  {label:'missing background',background:null,topic:comparisonTopic},
  {label:'unsafe background source',background:{...datedComparisonFixture(),sources:[{url:'https://127.0.0.1/private'}]},topic:comparisonTopic},
  {label:'unretrieved background source',background:{...datedComparisonFixture(),sources:[{url:'https://www.grammy.com/not-retrieved'}]},topic:comparisonTopic},
  {label:'opening cites an unselected source',background:{...datedComparisonFixture(),opening:{...datedComparisonFixture().opening,
   sourceUrls:['https://www.grammy.com/not-retrieved']}},topic:comparisonTopic},
  {label:'current factual streaming counts',background:datedComparisonFixture(),topic:'Artist A or Artist B who is bigger right now by streaming counts?'},
 ];
 for(const [index,fixture] of cases.entries()) {
  const {sent}=await offlineSdk({musicComparison:true,requiresCurrentSources:true,currentSourcesAvailable:false,comparisonBackground:fixture.background});
  const welcome=await next(await create({category:'trending',topic:fixture.topic})),requestId=randomUUID();
  await assert.rejects(prepare(welcome.episode,requestId),error=>error.name==='PodProviderError',fixture.label);
  const saved=await store.get(owner,welcome.episode.id);
  assert.equal(saved.episode.state,'active',fixture.label);assert.equal(saved.episode.turns.length,1,fixture.label);
  assert(saved.episode.preparationError,fixture.label);assert.equal(saved.episode.preparedId,null,fixture.label);
  assert.deepEqual(saved.brief,{},fixture.label);assert.deepEqual(saved.episode.sources,[],fixture.label);
  await assert.rejects(prepare(saved.episode),error=>error.status===409,fixture.label);
  assert.deepEqual(sent.map(call=>call.path),['/v1/audio/speech','/v1/responses'],fixture.label);
  const receipt=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='research'",[welcome.episode.id])).rows[0];
  assert.equal(receipt.evidence.status,'failed',fixture.label);assert.equal(receipt.evidence.totalTokens,139,fixture.label);
  assert.equal((await monthly()).total_tokens,139*(index+1),fixture.label);
  await store.control(owner,welcome.episode.id,'end');runtime.abort(owner,welcome.episode.id);
 }
});
