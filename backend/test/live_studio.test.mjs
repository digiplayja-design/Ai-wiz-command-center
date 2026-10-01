import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,writeFile,readdir,mkdtemp,rm} from 'node:fs/promises';
import {EventEmitter} from 'node:events';
import {PassThrough,Writable} from 'node:stream';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {createLiveStore} from '../live_studio/store.mjs';
import {showInput,queueInput,publicShow} from '../live_studio/core.mjs';
import {musicWav,renderSegment,makeReplay,sceneSvg,broadcastSink} from '../live_studio/media.mjs';
import {createLiveRuntime} from '../live_studio/runtime.mjs';
import {createYouTube} from '../live_studio/youtube.mjs';
import {registerLiveStudio} from '../live_studio/routes.mjs';

let db,store,owner,other;
const config={title:'Community & technology',topic:'How can technology help communities?',category:'technology',durationSeconds:900,hostCount:2};
const raw=async(actor,action,id=null,data={})=>(await db.query('select public.korlix_live_studio_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const save=async(actor=owner,id=randomUUID())=>store.call(actor,'save',id,{config});
const queue=async(show,extra={})=>store.call(show.owner_id,'queue',show.id,{mode:'rehearsal',scheduledAt:null,requestId:randomUUID(),...extra});
const claim=async()=>store.call(null,'claim',null,{token:randomUUID(),mode:'rehearsal'});
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key);create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);');
 const dir=new URL('../../supabase/migrations/',import.meta.url),file=(await readdir(dir)).find(n=>n.endsWith('_live_studio_pilot.sql'));
 await db.exec(await readFile(new URL(file,dir),'utf8'));
 store=createLiveStore({rpc:async(_name,p)=>{try{return {data:await raw(p.p_actor,p.p_action,p.p_id,p.p_data)};}catch(error){return {error};}}});
});
test.beforeEach(async()=>{
 await db.exec('reset role;truncate korlix_live_studio_shows cascade;truncate korlix_live_studio_runs,korlix_live_studio_workers;');
 owner=randomUUID();other=randomUUID();await db.query('insert into auth.users values($1),($2)',[owner,other]);await db.exec('set role service_role');
});
test.after(async()=>db.close());

test('validated show inputs and schedules reject invalid durations, hidden modes and ambiguous confirmation',()=>{
 assert.deepEqual(showInput(config),config);
 for(const change of [{durationSeconds:86400},{hostCount:9},{title:'a\ncommand'},{category:'private-data'}])assert.throws(()=>showInput({...config,...change}));
 assert.throws(()=>queueInput({mode:'youtube',consent:true,requestId:randomUUID()}));
 assert.throws(()=>queueInput({mode:'youtube',consent:true,confirmed:true,requestId:randomUUID(),scheduledAt:'2020-01-01'}));
 assert.equal(queueInput({mode:'youtube',consent:true,confirmed:true,requestId:randomUUID(),connectionId:randomUUID(),connectionRevision:1}).mode,'youtube');
 assert.throws(()=>queueInput({mode:'youtube',consent:true,confirmed:true,requestId:randomUUID()}));
});
test('save retry, list and get are owner scoped; public projection removes leases and storage paths',async()=>{
 const s=await save();assert.equal((await save(owner,s.id)).id,s.id);
 assert.equal((await store.call(other,'list')).shows.length,0);
 await assert.rejects(store.call(other,'get',s.id),e=>e.status===404);
 await assert.rejects(store.call(other,'save',s.id,{config}),e=>e.status===404);
 assert(!('owner_id' in publicShow(s)));assert(!('worker_token' in publicShow(s)));assert(!('replay_path' in publicShow(s)));
 await assert.rejects(store.call(owner,'save',s.id,{config:{...config,title:'Changed'}}),e=>e.status===409);
});
test('client roles cannot read tables, mutate state, or invoke the privileged RPC',async()=>{
 const s=await save();
 for(const role of ['anon','authenticated']){
  await db.exec('reset role;set role '+role);
  await assert.rejects(db.query('select * from korlix_live_studio_shows'));
  await assert.rejects(raw(owner,'get',s.id));
  await assert.rejects(db.query('select * from korlix_live_studio_runs'));
  await db.exec('reset role;set role service_role');
 }
});
test('queue retries reserve one run, different payload conflicts, one global job and one worker claim',async()=>{
 const s=await save(),requestId=randomUUID(),data={mode:'rehearsal',scheduledAt:null,requestId};
 await store.call(owner,'queue',s.id,data);await store.call(owner,'queue',s.id,data);
 assert.equal((await db.query('select count(*)::int n from korlix_live_studio_runs')).rows[0].n,1);
 await assert.rejects(store.call(owner,'queue',s.id,{...data,mode:'youtube'}),e=>e.status===409);
 const another=await save(other);await assert.rejects(queue(another),e=>e.status===409);
 const a=await claim();assert.equal(a.id,s.id);assert.deepEqual(await claim(),{});
 await assert.rejects(store.call(owner,'heartbeat',s.id,{token:randomUUID()}),e=>e.status===409);
});
test('scheduled jobs wait, owner-specific YouTube workers cannot claim another account',async()=>{
 const s=await save();await queue(s,{mode:'youtube',scheduledAt:new Date(Date.now()+120000).toISOString()});
 assert.deepEqual(await store.call(owner,'claim',null,{mode:'youtube',token:randomUUID()}),{});
 await db.query('update korlix_live_studio_shows set scheduled_at=now()-interval \'1 second\' where id=$1',[s.id]);
 assert.deepEqual(await store.call(other,'claim',null,{mode:'youtube',token:randomUUID()}),{});
 assert.equal((await store.call(owner,'claim',null,{mode:'youtube',token:randomUUID()})).id,s.id);
});
test('worker readiness expires and is only visible as ready to the configured owner',async()=>{
 await store.call(owner,'announce');assert.equal((await store.call(owner,'worker_status')).youtubeReady,true);
 assert.equal((await store.call(other,'worker_status')).youtubeReady,false);
 await db.exec("update korlix_live_studio_workers set ready_until=now()-interval '1 second'");
 assert.equal((await store.call(owner,'worker_status')).youtubeReady,false);
});
test('cancel and control retry are durable; ended work cannot dispatch or resurrect',async()=>{
 let s=await queue(await save());s=await claim();
 await store.call(owner,'progress',s.id,{token:s.worker_token,started:true,progress:{seconds:1}});
 const data={action:'end',requestId:randomUUID()};
 assert.equal((await store.call(owner,'control',s.id,data)).state,'cancelled');
 assert.equal((await store.call(owner,'control',s.id,data)).state,'cancelled');
 await assert.rejects(store.call(owner,'event',s.id,{token:s.worker_token,eventId:randomUUID(),kind:'dispatch',data:{}}),e=>e.status===409);
 assert.equal((await store.call(owner,'finish',s.id,{token:s.worker_token})).state,'cancelled');
});
test('expired lease fails closed and the old worker cannot write or re-dispatch',async()=>{
 await queue(await save());const s=await claim();
 await db.query("update korlix_live_studio_shows set lease_until=now()-interval '1 second' where id=$1",[s.id]);
 await assert.rejects(store.call(owner,'heartbeat',s.id,{token:s.worker_token}),e=>e.status===409);
 await store.call(null,'sweep');assert.equal((await store.call(owner,'get',s.id)).state,'failed');
 assert.deepEqual(await claim(),{});
});
test('late questions remain visible and emergency stop works after the control allowance',async()=>{
 await queue(await save());const s=await claim();
 await store.call(owner,'progress',s.id,{token:s.worker_token,started:true,progress:{}});
 for(let i=0;i<100;i++)await store.call(owner,'control',s.id,{action:'skip',requestId:randomUUID()});
 await assert.rejects(store.call(owner,'control',s.id,{action:'pause',requestId:randomUUID()}),e=>e.status===429);
 // Simulate a long show with many earlier receipts, then append a current event.
 await db.query("insert into korlix_live_studio_events(id,show_id,run_id,kind,data,created_at) select gen_random_uuid(),$1,$2,'receipt','{}',now()-interval '1 minute' from generate_series(1,280)",[s.id,s.run_id]);
 assert.equal((await store.call(owner,'control',s.id,{action:'end',requestId:randomUUID()})).state,'cancelled');
 const events=(await store.call(owner,'events',s.id)).events;
 assert.equal(events.length,250);assert(events.some(e=>e.kind==='control'&&e.data.action==='end'));
});
test('a failed replacement preserves the previously saved private rehearsal',async()=>{
 const saved=await save(),oldPath=owner+'/'+saved.id+'/previous.mp4';
 await db.query('update korlix_live_studio_shows set replay_path=$1,has_replay=true where id=$2',[oldPath,saved.id]);
 await queue(saved);const s=await claim();
 const done=await store.call(owner,'finish',s.id,{token:s.worker_token,error:'Fixture provider unavailable',replayPath:null});
 assert.equal(done.state,'failed');assert.equal(done.replay_path,oldPath);assert.equal(done.has_replay,true);
});
test('deleting a show does not reset the three-start daily cap',async()=>{
 for(let i=0;i<3;i++){
  const s=await queue(await save());await store.call(owner,'control',s.id,{action:'end',requestId:randomUUID()});await store.call(owner,'delete',s.id);
 }
 await assert.rejects(queue(await save()),e=>e.status===429);
});
test('a full rehearsal persists usage, three segments and a private video without client heartbeats',async()=>{
 let s=await queue(await save());s=await claim();let uploaded;
 const providers={moderate:async()=>true,research:async()=>({brief:{text:'A verified fixture.',sources:[{id:'s1',title:'Fixture',url:'https://www.nasa.gov/'}],checkedAt:new Date().toISOString()},initialTurn:{speaker:'analyst',text:'A useful point.',sourceIds:['s1']}}),
  speak:async()=>({wav:musicWav(1),durationSeconds:1}),turn:async()=>({speaker:'host',text:'Thanks for listening.',sourceIds:['s1']})};
 const storage={from:()=>({upload:async(key,bytes)=>{uploaded={key,bytes};return {};},remove:async()=>({})})};
 const runtime=createLiveRuntime({store,providers,storage,logger:{warn(){}}});await runtime.run(s);
 const saved=await store.call(owner,'get',s.id);assert.equal(saved.state,'completed');assert.equal(saved.has_replay,true);
 assert(uploaded.key.startsWith(owner+'/'+s.id+'/'));assert(uploaded.bytes.length>1000);
 const events=(await store.call(owner,'events',s.id)).events;
 assert.equal(events.filter(e=>e.kind==='segment').length,3);assert.equal(events.filter(e=>e.kind==='dispatch').length,5);
 assert.equal(events.filter(e=>e.kind==='receipt').length,5);runtime.stop();
});
test('uncertain provider failure is recorded once, never automatically reissued',async()=>{
 await queue(await save());let count=0;
 const runtime=createLiveRuntime({store,providers:{research:async()=>{count++;throw new Error('untrusted provider secret');}},storage:{from:()=>({remove:async()=>({})})},logger:{warn(){}}});
 await runtime.tick();await runtime.tick();assert.equal(count,1);
 const show=(await store.call(owner,'list')).shows[0];assert.equal(show.state,'failed');assert(!show.error.includes('secret'));
});
test('HTTP auth and unconfigured YouTube gates run before dispatch',async()=>{
 const app=express();app.use(express.json());
 const modernStore={call:(actor,action,id,data)=>action==='workspace'?Promise.resolve({entitlement:{enabled:true,maxDailyStarts:3},usage:{dailyStarts:0},workerReady:false}):store.call(actor,action,id,data)};
 registerLiveStudio(app,{store:modernStore,requireUser:async q=>q.headers.authorization?{id:owner}:null,
  access:async()=>({allowed:false}),connections:{registerPublic(){},summary:async()=>({connectionConfigured:false,connection:null,pendingConnections:[]})},startWorker:false,providers:null,storage:null});
 const server=app.listen(0);await new Promise(r=>server.once('listening',r));const base='http://127.0.0.1:'+server.address().port+'/api/live-studio';
 try{
  assert.equal((await fetch(base)).status,401);
  const s=await save();
  const response=await fetch(base+'/shows/'+s.id+'/start',{method:'POST',headers:{authorization:'fixture','content-type':'application/json'},body:JSON.stringify({mode:'youtube',consent:true,confirmed:true,requestId:randomUUID(),connectionId:randomUUID(),connectionRevision:1})});
  assert.equal(response.status,409);assert.equal((await store.call(owner,'get',s.id)).state,'draft');
  const status=await(await fetch(base,{headers:{authorization:'fixture'}})).json();assert.equal(status.access.youtubeReady,false);
 }finally{await new Promise(r=>server.close(r));}
});
test('actual FFmpeg output has H264 video, AAC audio and a continuous multi-segment timeline',async()=>{
 const dir=await mkdtemp(path.join(tmpdir(),'live-studio-test-'));
 try{
  const first=await renderSegment({dir,index:0,show:{config},turn:{text:'First segment',speaker:'host'},wav:musicWav(1.3),width:640});
  const second=await renderSegment({dir,index:1,show:{config},turn:{text:'Second segment',speaker:'analyst'},wav:musicWav(1.7),offset:first.duration,width:640});
  const output=path.join(dir,'test.mp4');await makeReplay([first.file,second.file],output);
  const info=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',output],{encoding:'utf8'}));
  assert(info.streams.some(s=>s.codec_name==='h264'));assert(info.streams.some(s=>s.codec_name==='aac'));
  assert(Number(info.format.duration)>2.9&&Number(info.format.duration)<3.3);
  const audio=execFileSync('ffmpeg',['-v','error','-i',output,'-f','s16le','-ac','1','-ar','8000','pipe:1']);
  assert(audio.some(v=>v!==0),'replay contains audible fixture audio');
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('rendering escapes untrusted markup and rejects arbitrary stream destinations before spawning',()=>{
 const svg=sceneSvg({title:'<script>x</script>',text:'A & B',speaker:'host'});assert(!svg.includes('<script>'));assert(svg.includes('&amp;'));
 for(const url of ['file:///etc/passwd','rtmps://localhost/live2/key','rtmp://a.rtmps.youtube.com/live2/key'])assert.throws(()=>broadcastSink(url));
});
test('stream backpressure releases temporary listeners across many segments',async()=>{
 const dir=await mkdtemp(path.join(tmpdir(),'live-studio-sink-'));
 try{
  const file=path.join(dir,'fixture.ts');await writeFile(file,Buffer.alloc(2048));
  const child=new EventEmitter();child.exitCode=null;child.stderr=new PassThrough();
  child.stdin=new Writable({highWaterMark:1,write(_chunk,_encoding,done){setImmediate(done);}});
  child.stdin.once('finish',()=>{child.exitCode=0;child.emit('close',0);});
  child.kill=()=>{child.exitCode=1;child.emit('close',1);};
  const sink=broadcastSink('rtmps://a.rtmps.youtube.com/live2/fixture',{spawnProcess:()=>child});
  for(let i=0;i<40;i++)await sink.write(file);
  assert.equal(child.listenerCount('close'),1);assert.equal(child.stdin.listenerCount('drain'),0);
  await sink.close();
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('YouTube adapter forces unlisted, AI disclosure, secure ingest and confirms actual live state',async()=>{
 const calls=[];let livePoll=0;
 const fetcher=async(url,options={})=>{
  const body=options.body instanceof URLSearchParams?Object.fromEntries(options.body):options.body?JSON.parse(options.body):null;
  calls.push({url,method:options.method,body});let value={};
  if(url.includes('channels?'))value={items:[{id:'fixture-channel'}]};
  else if(url.includes('liveBroadcasts?part=snippet'))value={id:'broadcast1',snippet:{liveChatId:'chat1'}};
  else if(url.includes('liveStreams?part=snippet'))value={id:'stream1',cdn:{ingestionInfo:{rtmpsIngestionAddress:'rtmps://a.rtmps.youtube.com/live2',streamName:'fixture-key'}}};
  else if(url.includes('liveStreams?part=status'))value={items:[{status:{streamStatus:'active'}}]};
  else if(url.includes('/transition?'))value={status:{lifeCycleStatus:'liveStarting'}};
  else if(url.includes('liveBroadcasts?part=status'))value={items:[{status:{lifeCycleStatus:++livePoll>0?'live':'liveStarting'}}]};
  return new Response(JSON.stringify(value),{status:200});
 };
 const api=createYouTube({channelId:'fixture-channel',accessToken:async()=>'fake-access-token'},{fetcher});
 const session=await api.setup({config});assert.equal(session.watchUrl,'https://www.youtube.com/watch?v=broadcast1');
 assert.equal(await api.start(session),false);assert.equal(await api.start(session),true);
 assert.equal(calls.find(c=>c.url.includes('liveBroadcasts?part=snippet')).body.status.privacyStatus,'unlisted');
 assert.equal(calls.find(c=>c.url.includes('videos?part=status')).body.status.containsSyntheticMedia,true);
 assert.equal(calls.filter(c=>c.url.includes('oauth2')).length,0);
});

test('an encoder that exits unsuccessfully or cannot drain is never reported complete',async()=>{
 for(const outcome of ['failure','timeout']){
  const child=new EventEmitter();child.exitCode=null;child.stderr=new PassThrough();
  child.stdin=new Writable({write(_chunk,_encoding,done){done();}});
  child.kill=()=>{child.exitCode=1;child.emit('close',1);};
  if(outcome==='failure')child.stdin.once('finish',()=>{child.exitCode=1;child.emit('close',1);});
  const sink=broadcastSink('rtmps://a.rtmps.youtube.com/live2/fixture',{spawnProcess:()=>child,closeTimeoutMs:10});
  await assert.rejects(sink.close(),/final segment/);
 }
});

test('end completes only this adapter’s created broadcast using its last run token without reopening a grant',async()=>{
 let stopped=false,tokenReads=0;const writes=[];
 const api=createYouTube({channelId:'fixture',accessToken:async()=>{tokenReads++;if(stopped)throw Error('revoked');return 'fixture';}},{fetcher:async(url,options={})=>{
  let data={};
  if(options.method==='POST'||options.method==='DELETE')writes.push(url);
  if(url.includes('channels?'))data={items:[{id:'fixture'}]};
  else if(url.includes('liveBroadcasts?part=snippet'))data={id:'own-broadcast',snippet:{}};
  else if(url.includes('liveStreams?part=snippet'))data={id:'own-stream',cdn:{ingestionInfo:{rtmpsIngestionAddress:'rtmps://a.rtmps.youtube.com/live2',streamName:'fixture'}}};
  else if(url.includes('liveBroadcasts?part=status'))data={items:[{status:{lifeCycleStatus:'live'}}]};
  return new Response(JSON.stringify(data));
 }});
 const session=await api.setup({config}),count=tokenReads;stopped=true;
 await api.finish(session);assert.equal(tokenReads,count);
 assert(writes.some(url=>url.includes('broadcastStatus=complete')));
 const writeCount=writes.length;
 await assert.rejects(api.finish({...session,id:'another-broadcast'}),/different broadcast/);
 await assert.rejects(api.finish({id:'another-broadcast'}),/different broadcast/);
 assert.equal(writes.length,writeCount);
});

test('expired access still allows status, emergency end and disconnect; a final-start retry stays idempotent',async()=>{
 const showId=randomUUID(),requestId=randomUUID(),state={id:showId,run_id:requestId,state:'queued',owner_id:owner};
 let ended=false,disconnected=false;
 const app=express();app.use(express.json());
 const fixtureStore={call:async(actor,action,id,data)=>{
  if(['sweep','grant_developer'].includes(action))return {};
  assert.equal(actor,owner);
  if(action==='list')return {shows:[state]};
  if(action==='workspace')return {entitlement:{enabled:false,maxDailyStarts:1},usage:{dailyStarts:1},workerReady:false};
  if(action==='get')return state;
  if(action==='queue'){assert.equal(data.requestId,requestId);return state;}
  if(action==='control'){ended=true;return {...state,state:'cancelled'};}
  throw Error(action);
 }};
 registerLiveStudio(app,{store:fixtureStore,requireUser:async()=>({id:owner}),access:async()=>({allowed:false}),startWorker:false,
  connections:{registerPublic(){},summary:async()=>({connectionConfigured:false,connection:null}),disconnect:async(actor)=>{assert.equal(actor,owner);disconnected=true;return {disconnected:true};}}});
 const server=app.listen(0);await new Promise(r=>server.once('listening',r));const base='http://127.0.0.1:'+server.address().port+'/api/live-studio';
 const request=(url,method,body)=>fetch(base+url,{method,headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 try{
  const status=await(await fetch(base)).json();assert.equal(status.access.canStart,false);assert.equal(status.shows.length,1);
  assert.equal((await request('/shows/'+showId+'/start','POST',{mode:'rehearsal',consent:true,requestId})).status,200);
  assert.equal((await request('/shows/'+showId+'/start','POST',{mode:'rehearsal',consent:true,requestId:randomUUID()})).status,403);
  assert.equal((await request('/shows/'+showId+'/control','POST',{action:'end',confirmed:true,requestId:randomUUID()})).status,200);assert(ended);
  assert.equal((await request('/connections/youtube','DELETE',{confirmed:true})).status,200);assert(disconnected);
 }finally{await new Promise(r=>server.close(r));}
});
