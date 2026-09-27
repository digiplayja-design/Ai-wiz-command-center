'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {createMeetingRecordings,validateRecordingRequest}=require('../k135z_zoom/meeting_recordings.cjs');
const {objectPath}=require('../k135z_zoom/recording_store.cjs');
const {createRecordingEncoder}=require('../k135z_zoom/recording_encoder.cjs');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const {mkdtemp,writeFile,rm,readFile}=require('node:fs/promises');
const {join}=require('node:path'),{tmpdir}=require('node:os');
const p={tenantId:'11111111-1111-4111-8111-111111111111',userId:'11111111-1111-4111-8111-111111111111',agentId:'agent'};
const ctx={...p,sessionId:'session',meetingUuid:'meeting',streamId:'stream',generation:1};
const id=()=>randomUUID().replaceAll('-','');
const tick=()=>new Promise(r=>setImmediate(r));
function fixture(options={}) {
  const rows=new Map(),objects=new Map(),encoders=[];
  let clock=Date.now(),allowed=true,verifyCalls=0,uploadGate=null,encoderGate=null;
  const own=(a,b)=>['tenantId','userId','agentId'].every(k=>a[k]===b[k]);
  const store={
    async list(who){return [...rows.values()].filter(r=>own(r.context,who)).map(r=>structuredClone(r));},
    async get(who,key){const r=rows.get(key);return r&&own(r.context,who)?structuredClone(r):null;},
    async reserve(who,{id,context,processId,now}) {
      if([...rows.values()].some(r=>own(r.context,who)&&['recording','saving'].includes(r.status)))throw Error('active');
      const r={id,context:structuredClone(context),process_id:processId,status:'recording',
        created_at:now,updated_at:now,duration_ms:0,byte_size:0,end_reason:null};rows.set(id,r);return structuredClone(r);
    },
    async update(who,key,patch,guard={}) {
      const r=rows.get(key);
      if(!r||!own(r.context,who)||guard.processId&&guard.processId!==r.process_id||
        guard.updatedAt&&guard.updatedAt!==r.updated_at||guard.statuses&&!guard.statuses.includes(r.status))return null;
      Object.assign(r,patch);return structuredClone(r);
    },
    async upload(path,bytes){if(uploadGate)await uploadGate;objects.set(path,bytes);},
    async link(path){assert(objects.has(path));return 'https://storage.example.test/'+path;},
    async remove(who,row){assert(own(row.context,who));rows.delete(row.id);objects.delete(objectPath(who,row.id));},
  };
  const manager=createMeetingRecordings({store,now:()=>clock,...options,
    encoderFactory:async args=>{
      const e={bytes:0,voice:[],aborted:false,write(b){this.bytes+=b.length;return true;},
        writeVoice(b,offset){this.voice.push({bytes:Buffer.from(b),offset});return true;},
        async finish(){return Buffer.from([73,68,51,...Array(100).fill(0)]);},async abort(){this.aborted=true;},args};
      encoders.push(e);if(encoderGate)await encoderGate;return e;
    }});
  const run=(body,who=p)=>manager.run({principal:who,body,verify:async()=>{
    verifyCalls++;if(!allowed)throw Error('denied');
  }});
  return {manager,rows,objects,encoders,run,store,
    start:(key=id())=>run({action:'start',id:key,context:ctx,consent:true}),
    set allowed(v){allowed=v;},get verifyCalls(){return verifyCalls;},
    set uploadGate(v){uploadGate=v;},set encoderGate(v){encoderGate=v;},
    advance(ms){clock+=ms;},close:()=>manager.close()};
}
test('recording requires separate explicit consent and rejects unknown fields',()=>{
  for(const body of [{action:'start',id:id(),context:ctx,consent:false},
    {action:'start',id:id(),context:ctx,consent:true,userId:'22222222-2222-4222-8222-222222222222'},
    {action:'delete',id:'../../other'},{action:'play',id:id(),path:'other/file.mp3'}])
    assert.throws(()=>validateRecordingRequest(body));
});
test('no recorder or stored media exists without an explicit Start',async t=>{
  const f=fixture();t.after(f.close);f.manager.accept(ctx,Buffer.alloc(640));
  assert.deepEqual((await f.run({action:'list'})).recordings,[]);assert.equal(f.encoders.length,0);
});
test('Start rechecks authority, Stop saves received audio and rejects late packets',async t=>{
  const f=fixture();t.after(f.close);const {recording}=await f.start();
  assert.equal(f.verifyCalls,2);f.manager.accept(ctx,Buffer.alloc(32000));
  const stopped=await f.run({action:'stop',id:recording.id});assert.equal(stopped.recording.status,'saving');
  f.manager.accept(ctx,Buffer.alloc(32000));await tick();
  const saved=(await f.run({action:'list'})).recordings[0];assert.equal(saved.status,'ready');
  assert.equal(saved.durationMs,1000);assert.equal(f.encoders[0].bytes,32000);
  assert.match((await f.run({action:'play',id:saved.id})).url,/https:/);
  await f.run({action:'delete',id:saved.id});assert.equal(f.objects.size,0);assert.equal(f.rows.size,0);
});
test('repeated Start is idempotent and a second recording cannot overlap',async t=>{
  const f=fixture();t.after(f.close);const key=id();await f.start(key);await f.start(key);
  assert.equal(f.encoders.length,1);await assert.rejects(f.start(),{code:'K135Z_RECORDING_CONFLICT'});
});
test('foreign owners and agents cannot list, stop, play, download or delete',async t=>{
  const f=fixture();t.after(f.close);const {recording}=await f.start();
  for(const other of [{...p,userId:'22222222-2222-4222-8222-222222222222'},{...p,tenantId:'22222222-2222-4222-8222-222222222222'},{...p,agentId:'other'}]) {
    assert.deepEqual((await f.run({action:'list'},other)).recordings,[]);
    for(const action of ['stop','play','download','delete'])
      await assert.rejects(f.run({action,id:recording.id},other),{code:'K135Z_RECORDING_NOT_FOUND'});
  }
});
test('wrong meeting audio never enters a recording',async t=>{
  const f=fixture();t.after(f.close);await f.start();
  f.manager.accept({...ctx,meetingUuid:'other'},Buffer.alloc(640));
  f.manager.accept({...ctx,agentId:'other'},Buffer.alloc(640));
  assert.equal(f.encoders[0].bytes,0);
});
test('Nova voice requires a consented active recording and the exact owner and meeting',async t=>{
  const f=fixture();t.after(f.close);const recordingId=id(),playbackId=id();
  const begin={action:'voice-start',id:recordingId,context:ctx,playbackId};
  await assert.rejects(f.run(begin),{code:'K135Z_RECORDING_VOICE_SESSION_CHANGED'});
  await f.start(recordingId);f.manager.accept(ctx,Buffer.alloc(32000));
  for(const body of [{...begin,context:{...ctx,meetingUuid:'other'}},{...begin,id:id()}])
    await assert.rejects(f.run(body),{code:'K135Z_RECORDING_VOICE_SESSION_CHANGED'});
  await assert.rejects(f.run(begin,{...p,agentId:'other'}),{code:'K135Z_RECORDING_VOICE_SESSION_CHANGED'});
  f.allowed=false;await assert.rejects(f.run(begin));f.allowed=true;
  await f.run(begin);
  const packet={...begin,action:'voice-chunk',sequence:1,pcm:Buffer.alloc(16000,1).toString('base64')};
  await f.run(packet);await f.run(packet);
  assert.equal(f.encoders[0].voice.length,1);assert.equal(f.encoders[0].voice[0].offset,32000);
  await assert.rejects(f.run({...packet,sequence:3}),{code:'K135Z_RECORDING_VOICE_SEQUENCE'});
  f.allowed=false;await assert.rejects(f.run({...packet,sequence:2}));f.allowed=true;
  await f.run({action:'stop',id:recordingId});await tick();
  await assert.rejects(f.run({...packet,sequence:2}),{code:'K135Z_RECORDING_VOICE_SESSION_CHANGED'});
  assert.equal((await f.run({action:'list'})).recordings[0].durationMs,1500);
});
test('Nova packets reject oversized, malformed, odd and unbounded input',()=>{
  const packet={action:'voice-chunk',id:id(),context:ctx,playbackId:id(),sequence:1,pcm:Buffer.alloc(16000).toString('base64')};
  validateRecordingRequest(packet);
  for(const patch of [{pcm:''},{pcm:'not base64'},{pcm:'AA=='},{pcm:Buffer.alloc(16002).toString('base64')},
    {sequence:0},{sequence:181},{sequence:1.5},{playbackId:'../file'},{url:'https://outside.test'}])
    assert.throws(()=>validateRecordingRequest({...packet,...patch}));
});
test('Nova timeline is server anchored and bounded by recording duration',async t=>{
  const f=fixture({maxDurationMs:1000});t.after(f.close);const {recording}=await f.start();
  const begin={action:'voice-start',id:recording.id,context:ctx,playbackId:id()};await f.run(begin);
  const packet={...begin,action:'voice-chunk',pcm:Buffer.alloc(16000).toString('base64')};
  await f.run({...packet,sequence:1});await f.run({...packet,sequence:2});
  await assert.rejects(f.run({...packet,sequence:3}),{code:'K135Z_RECORDING_VOICE_LIMIT'});
  assert.equal(f.encoders[0].voice.length,2);
});
test('Stop while Nova authorization is pending cannot append late voice',async t=>{
  const f=fixture();t.after(f.close);const {recording}=await f.start();
  const begin={action:'voice-start',id:recording.id,context:ctx,playbackId:id()};await f.run(begin);
  let release;const gate=new Promise(r=>release=r);
  const pending=f.manager.run({principal:p,body:{...begin,action:'voice-chunk',sequence:1,pcm:Buffer.alloc(3200).toString('base64')},verify:()=>gate});
  f.manager.accept(ctx,Buffer.alloc(640));await f.run({action:'stop',id:recording.id});release();
  await assert.rejects(pending,{code:'K135Z_RECORDING_VOICE_SESSION_CHANGED'});
  assert.equal(f.encoders[0].voice.length,0);
});
test('revocation during encoder setup never arms late recording',async t=>{
  const f=fixture();t.after(f.close);let release;f.encoderGate=new Promise(r=>release=r);
  const starting=f.start();await tick();f.allowed=false;release();await assert.rejects(starting);
  f.manager.accept(ctx,Buffer.alloc(640));assert.equal(f.encoders[0].bytes,0);
  assert.equal(f.encoders[0].aborted,true);assert.equal([...f.rows.values()][0].status,'failed');
});
test('stream closure saves audio without a browser Stop request',async t=>{
  const f=fixture();t.after(f.close);await f.start();f.manager.accept(ctx,Buffer.alloc(640));
  f.manager.streamClosed(ctx);await tick();
  const r=(await f.run({action:'list'})).recordings[0];assert.equal(r.status,'ready');assert.equal(r.endReason,'capture_ended');
});
test('empty audio is failed, never a downloadable successful recording',async t=>{
  const f=fixture();t.after(f.close);const {recording}=await f.start();
  await f.run({action:'stop',id:recording.id});await tick();
  assert.equal([...f.rows.values()][0].end_reason,'no_audio');assert.equal(f.objects.size,0);
  await assert.rejects(f.run({action:'play',id:recording.id}),{code:'K135Z_RECORDING_NOT_READY'});
});
test('upload in progress is not ready and cannot be deleted',async t=>{
  const f=fixture();t.after(f.close);let release;f.uploadGate=new Promise(r=>release=r);
  const {recording}=await f.start();f.manager.accept(ctx,Buffer.alloc(640));
  await f.run({action:'stop',id:recording.id});await tick();
  await assert.rejects(f.run({action:'delete',id:recording.id}),{code:'K135Z_RECORDING_STILL_ACTIVE'});
  release();await tick();assert.equal([...f.rows.values()][0].status,'ready');
});
test('duration cap ends and saves recording automatically',async t=>{
  const f=fixture({maxDurationMs:15});t.after(f.close);await f.start();f.manager.accept(ctx,Buffer.alloc(640));
  await new Promise(r=>setTimeout(r,35));assert.equal([...f.rows.values()][0].end_reason,'duration_limit');
});
test('stale interrupted recording becomes failed and permits a new Start',async t=>{
  const f=fixture();t.after(f.close);
  const old=id();f.rows.set(old,{id:old,context:ctx,process_id:randomUUID(),status:'recording',
    created_at:new Date(0).toISOString(),updated_at:new Date(0).toISOString(),duration_ms:500,byte_size:0,end_reason:null});
  await f.start();assert.equal(f.rows.get(old).status,'failed');assert.equal(f.rows.get(old).end_reason,'interrupted');
});
test('encoder or upload failure never returns a playable success',async t=>{
  for(const problem of ['codec','storage']) {
    const f=fixture();t.after(f.close);const {recording}=await f.start();
    f.manager.accept(ctx,Buffer.alloc(640));
    if(problem==='codec')f.encoders[0].finish=async()=>{throw Error('private codec details');};
    else f.store.upload=async()=>{throw Error('private storage details');};
    await f.run({action:'stop',id:recording.id});await tick();
    assert.equal(f.rows.get(recording.id).status,'failed');
    await assert.rejects(f.run({action:'play',id:recording.id}),{code:'K135Z_RECORDING_NOT_READY'});
  }
});
test('audio packet at the duration limit is trimmed and saved instead of corrupting the encoder',async t=>{
  const f=fixture({maxDurationMs:100});t.after(f.close);await f.start();
  f.manager.accept(ctx,Buffer.alloc(6400));await tick();
  assert.equal(f.encoders[0].bytes,3200);
  const row=[...f.rows.values()][0];assert.equal(row.status,'ready');assert.equal(row.duration_ms,100);
  assert.equal(row.end_reason,'duration_limit');
});
test('shutdown waits for pending encoder setup to abort and for saved media to finish',async()=>{
  const f=fixture();let release;f.encoderGate=new Promise(r=>release=r);
  const starting=f.start();const rejected=assert.rejects(starting);
  await tick();let closed=false;const closing=f.close().then(()=>{closed=true;});
  await tick();assert.equal(closed,false);release();await rejected;await closing;
  assert.equal(f.encoders[0].aborted,true);assert.equal(f.encoders[0].bytes,0);
  const g=fixture();g.uploadGate=new Promise(r=>release=r);
  await g.start();g.manager.accept(ctx,Buffer.alloc(640));closed=false;
  const saved=g.close().then(()=>{closed=true;});await tick();assert.equal(closed,false);
  release();await saved;assert.equal([...g.rows.values()][0].status,'ready');
});
test('an in-flight heartbeat cannot overwrite the final saved state',async t=>{
  const f=fixture({heartbeatMs:5});t.after(f.close);
  const original=f.store.update;let release,entered;
  const gate=new Promise(r=>release=r),waiting=new Promise(r=>entered=r);
  f.store.update=async(...args)=>{if(args[2].status==='recording'){entered();await gate;}return original(...args);};
  const {recording}=await f.start();f.manager.accept(ctx,Buffer.alloc(640));
  const keepAlive=setTimeout(()=>release(),1000);
  await waiting;await f.run({action:'stop',id:recording.id});
  assert.equal((await f.run({action:'list'})).recordings[0].status,'saving');
  release();clearTimeout(keepAlive);await tick();assert.equal(f.rows.get(recording.id).status,'ready');
});
test('recording HTTP route gates authentication, entitlement, ownership, consent and live host authority',async t=>{
  const Z=require('../k135z_zoom/zoom_routes.cjs'),f=fixture();t.after(f.close);
  let entitled=true,owned=true,active=true,authCalls=0;
  const lease={validForMs:1000,authority:{viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true},
    record:{snapshot:{context:ctx,state:'listening'},pending:null,uncertain:false}};
  const deps={workspaceHttpEnabled:true,workspaceRecordings:f.manager,
    workspaceStore:{readCaptureLease:async()=>lease},workspaceTransport:{captureActive:()=>active},
    authenticateRequest:async()=>{authCalls++;return p;},resolveEnterprise:async()=>entitled,authorizeAgent:async()=>owned};
  const handler=Z.createK135zZoomHandlers(deps).workspaceRecordings;
  const request={action:'start',id:id(),context:ctx,consent:true};
  async function run(body=request,headers={}) {
    const res={setHeader(k,v){if(k==='Cache-Control')assert.equal(v,'no-store');},
      status(n){this.statusCode=n;return this;},json(body){this.body=body;}};
    await handler({headers:{authorization:'Bearer offline','content-type':'application/json','x-korlix-agent-id':'agent',...headers},body},res);
    return res;
  }
  assert.equal((await run(request,{authorization:''})).statusCode,401);
  entitled=false;assert.equal((await run()).statusCode,403);entitled=true;
  owned=false;assert.equal((await run()).statusCode,403);owned=true;
  assert.equal((await run({...request,consent:false})).statusCode,400);
  active=false;assert.equal((await run()).statusCode,403);active=true;
  for(const key of ['viewerAuthorized','hostAuthorized','listeningAuthorized']){
    lease.authority[key]=false;assert.equal((await run()).statusCode,403);lease.authority[key]=true;
  }
  assert.equal(f.encoders.length,0);
  assert.equal((await run({...request,context:{...ctx,agentId:'foreign'}})).statusCode,409);
  authCalls=0;const started=await run();assert.equal(started.statusCode,200);assert.equal(authCalls,3);
  assert.equal(started.body.recording.status,'recording');
  assert.equal(JSON.stringify(started.body).includes('object_path'),false);
  const voice={action:'voice-start',id:request.id,context:ctx,playbackId:id()};
  assert.equal((await run(voice)).statusCode,200);
  const packet={...voice,action:'voice-chunk',sequence:1,pcm:Buffer.alloc(640).toString('base64')};
  for(const key of ['viewerAuthorized','hostAuthorized','listeningAuthorized']){
    lease.authority[key]=false;assert.equal((await run(packet)).statusCode,403);lease.authority[key]=true;
  }
  assert.equal((await run(packet)).statusCode,200);
  f.manager.accept(ctx,Buffer.alloc(640));await run({action:'stop',id:request.id});await tick();
  active=false;lease.validForMs=0;
  assert.equal((await run({action:'list'})).body.recordings[0].status,'ready');
  assert.equal((await run({action:'play',id:request.id})).statusCode,200);
});
test('real encoder produces decodable 16 kHz mono MP3 without media persistence after finish',async()=>{
  const encoder=await createRecordingEncoder();
  const pcm=Buffer.alloc(32000);
  for(let n=0;n<16000;n++)pcm.writeInt16LE(Math.round(Math.sin(2*Math.PI*440*n/16000)*8000),n*2);
  assert.equal(encoder.write(pcm),true);
  const mp3=await encoder.finish();assert(mp3.length>1000&&mp3.length<15000);
  const dir=await mkdtemp(join(tmpdir(),'nova-codec-test-'));
  try {
    await writeFile(join(dir,'audio.mp3'),mp3);
    const {stdout}=await promisify(execFile)('ffprobe',['-v','error','-show_entries','stream=codec_name,sample_rate,channels','-of','json',join(dir,'audio.mp3')]);
    const stream=JSON.parse(stdout).streams[0];assert.equal(stream.codec_name,'mp3');assert.equal(stream.sample_rate,'16000');assert.equal(stream.channels,1);
  } finally {await rm(dir,{recursive:true,force:true});}
});
test('real MP3 mix preserves human audio and adds only the played Nova interval',async()=>{
  const encoder=await createRecordingEncoder();
  function tone(hz,count){const b=Buffer.alloc(count*2);for(let i=0;i<count;i++)b.writeInt16LE(Math.round(Math.sin(2*Math.PI*hz*i/16000)*5000),i*2);return b;}
  assert.equal(encoder.write(tone(440,32000)),true);
  assert.equal(encoder.writeVoice(tone(880,8000),32000),true);
  assert.equal(encoder.writeVoice(Buffer.alloc(16002),0),false);
  assert.equal(encoder.writeVoice(Buffer.alloc(2),115200000),false);
  const mp3=await encoder.finish();
  const dir=await mkdtemp(join(tmpdir(),'nova-mix-test-'));
  try {
    const file=join(dir,'audio.mp3');await writeFile(file,mp3);
    const {stdout:pcm}=await promisify(execFile)('ffmpeg',['-v','error','-i',file,'-f','s16le','-ar','16000','-ac','1','pipe:1'],{encoding:'buffer'});
    const energy=(hz,from,to)=>{let a=0,b=0,n=0;for(let i=Math.floor(from*16000);i<Math.floor(to*16000);i++,n++){
      const s=pcm.readInt16LE(i*2);a+=s*Math.cos(2*Math.PI*hz*i/16000);b+=s*Math.sin(2*Math.PI*hz*i/16000);}
      return Math.sqrt(a*a+b*b)*2/n;};
    assert(energy(440,.25,.75)>3000);assert(energy(880,.25,.75)<100);
    assert(energy(440,1.2,1.4)>3000);assert(energy(880,1.2,1.4)>3000);
    assert(energy(880,1.75,1.95)<100);
  } finally {await rm(dir,{recursive:true,force:true});}
});
test('quiet Zoom input still saves a bounded 45-second played voice tail',async()=>{
  const encoder=await createRecordingEncoder();
  const voice=Buffer.alloc(16000);
  for(let i=0;i<8000;i++)voice.writeInt16LE(Math.round(Math.sin(2*Math.PI*880*i/16000)*3000),i*2);
  for(let offset=0;offset<45*32000;offset+=voice.length)assert.equal(encoder.writeVoice(voice,offset),true);
  const mp3=await encoder.finish();assert(mp3.length>300000&&mp3.length<400000);
  const dir=await mkdtemp(join(tmpdir(),'nova-tail-test-'));
  try {
    const file=join(dir,'audio.mp3');await writeFile(file,mp3);
    const {stdout}=await promisify(execFile)('ffprobe',['-v','error','-show_entries','format=duration','-of','json',file]);
    const duration=Number(JSON.parse(stdout).format.duration);assert(duration>=45&&duration<45.2);
  }finally {await rm(dir,{recursive:true,force:true});}
});
test('storage adapter scopes every lookup and mutation to tenant, user and agent',async()=>{
  const {createRecordingStore,BUCKET}=require('../k135z_zoom/recording_store.cjs');
  const queries=[],media=[];let data=[];
  const client={supabaseUrl:'https://project.test',from(table){
    const call={table,filters:[]};queries.push(call);
    const q={select(){return q;},eq(k,v){call.filters.push([k,v]);return q;},in(){return q;},
      order(){return q;},limit(){return q;},update(patch){call.patch=patch;return q;},delete(){return q;},
      maybeSingle(){return Promise.resolve({data,error:null});},then(a,b){return Promise.resolve({data,error:null}).then(a,b);}};
    return q;
  },storage:{from(bucket){assert.equal(bucket,BUCKET);return {
    async upload(path,bytes,options){media.push({action:'upload',path,options});return {error:null};},
    async createSignedUrl(path,expiry,options){media.push({action:'link',path,expiry,options});return {data:{signedUrl:'https://project.test/storage/v1/object/sign/korlix-meeting-recordings/audio?token=private'}};},
    async remove(paths){media.push({action:'delete',paths});return {error:null};},
  };}}};
  const store=createRecordingStore(client),key=id(),path=objectPath(p,key);
  await store.list(p);data=null;await store.get(p,key);await store.update(p,key,{status:'saving'});
  data={id:key,status:'deleting'};await store.remove(p,{id:key});
  for(const query of queries){assert.equal(query.table,'k135z_meeting_recordings');
    for(const pair of [['tenant_id',p.tenantId],['user_id',p.userId],['agent_id',p.agentId]])
      assert(query.filters.some(value=>JSON.stringify(value)===JSON.stringify(pair)));}
  await store.upload(path,Buffer.alloc(64));await store.link(path,true);
  assert.deepEqual(media.find(x=>x.action==='delete').paths,[path]);
  assert.deepEqual(media.find(x=>x.action==='upload').options,{contentType:'audio/mpeg',cacheControl:'0',upsert:false});
  assert.equal(media.find(x=>x.action==='link').expiry,3600);
  assert.equal(path.includes(p.userId),false);
});
test('migration denies metadata and media even with a broad legacy storage policy',async()=>{
  const {PGlite}=await import('@electric-sql/pglite');const db=new PGlite();
  try {
    await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
      create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
      create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;
      grant usage on schema public,storage to anon,authenticated,service_role;
      grant all on storage.objects to anon,authenticated;
      create policy legacy on storage.objects for all to anon,authenticated using(true) with check(true);`);
    await db.exec(await readFile(join(__dirname,'../../supabase/migrations/20260927024536_k135z_meeting_recordings.sql'),'utf8'));
    await db.exec("insert into storage.objects values('private','korlix-meeting-recordings'),('other','other-bucket')");
    for(const role of ['anon','authenticated']) {
      await db.exec('set role '+role);
      await assert.rejects(db.query('select * from public.k135z_meeting_recordings'));
      assert.deepEqual((await db.query('select id from storage.objects')).rows,[{id:'other'}]);
      await assert.rejects(db.exec("insert into storage.objects values('illegal','korlix-meeting-recordings')"));
      await db.exec('reset role');
    }
    const bucket=(await db.query("select * from storage.buckets where id='korlix-meeting-recordings'")).rows[0];
    assert.equal(bucket.public,false);assert.deepEqual(bucket.allowed_mime_types,['audio/mpeg']);
    await db.exec('set role service_role');
    const recordingId=id();
    const insert=(key,context=ctx)=>db.query(`insert into public.k135z_meeting_recordings
      (id,tenant_id,user_id,agent_id,context,process_id,status,object_path)
      values($1,$2,$3,$4,$5,$6,'recording',$7)`,
      [key,p.tenantId,p.userId,p.agentId,JSON.stringify(context),randomUUID(),objectPath(p,key)]);
    await insert(recordingId);
    await assert.rejects(insert(id()));
    await assert.rejects(db.exec("update public.k135z_meeting_recordings set status='ready'"));
    await db.exec("update public.k135z_meeting_recordings set status='failed'");
    await assert.rejects(insert(id(),{...ctx,agentId:'foreign'}));
    await insert(id());
    await db.exec('reset role');
  } finally {await db.close();}
});
