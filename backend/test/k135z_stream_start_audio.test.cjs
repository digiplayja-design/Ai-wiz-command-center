'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createZoomRtmsStarter,START_SCOPE} = require('../k135z_zoom/zoom_rtms_start.cjs');
const {pcmLevel,createAudioLevelMeter} = require('../k135z_zoom/audio_level.cjs');
const Z = require('../k135z_zoom/zoom_routes.cjs');
const {createK135zRtmsStream,createK135zRtmsCommandTransport} = require('../k135z_zoom/zoom_rtms_session_manager.cjs');
const p = {tenantId:'11111111-1111-4111-8111-111111111111',userId:'11111111-1111-4111-8111-111111111111',agentId:'nova'};
const ctx = {...p,sessionId:'session',meetingUuid:'uuid+test==',streamId:null,generation:1};
function fixture(options = {}) {
  const f = {calls:[],source:null,abort:new AbortController()};
  f.connection = {scope:START_SCOPE+' meeting:read:meeting_audio meeting:read:meeting_transcript',
    connectedAtMs:100,zoomUserId:'host',zoomAccountId:'account'};
  f.row = {bindingRevision:1,authorityRevision:0,validForMs:0,
    authority:{context:ctx,viewerAuthorized:true,hostAuthorized:false,listeningAuthorized:false},
    record:{pending:null,uncertain:false,snapshot:{schemaVersion:1,context:ctx,revision:0,state:'ready',
      activeSeconds:0,hostAuthorized:false,listeningAuthorized:false,capabilities:{canSpeak:false}}}};
  f.store = {async readCaptureLease(){return structuredClone(f.row);},async changeConsent(){f.calls.push('consent');return f.row;}};
  f.repository = {async getConnection(){return {...f.connection};},async getCaptureSource(query){
    assert.equal(query.key,JSON.stringify([p.tenantId,p.userId,p.agentId]));return f.source;}};
  f.transport = {async listUpcomingMeetings(){f.calls.push('list');return {meetings:[{id:123,uuid:ctx.meetingUuid,is_host:true}]};}};
  f.oauthService = {async getAuthorizedAccess(){return {accessToken:'private-token',apiUrl:'https://api.zoom.us'};}};
  f.fetchImpl = async (url,input) => {
    f.calls.push(input.method);assert.equal(input.redirect,'error');
    assert.equal(input.headers.authorization,'Bearer private-token');
    if(input.method==='GET') {
      assert.equal(url,'https://api.zoom.us/v2/meetings/123');
      if(options.onGet)options.onGet(f);
      return Response.json({uuid:ctx.meetingUuid,host_id:options.host??'host',status:options.status??'started'});
    }
    assert.equal(url,'https://api.zoom.us/v2/live_meetings/123/rtms_app/status');
    assert.deepEqual(JSON.parse(input.body),{action:'start',settings:{client_id:'app-client'}});
    if(options.patchError)return Response.json({code:options.patchError,message:'secret-upstream-body'}, {status:400});
    if(options.hold)await options.hold;
    if(options.onPatch)options.onPatch(f);
    if(!options.noEvent) f.source = {meetingUuid:ctx.meetingUuid,streamId:'stream',serverUrls:'wss://media.zoom.us'};
    return new Response(null,{status:204});
  };
  f.start = createZoomRtmsStarter({...f,store:f.store,repository:f.repository,transport:f.transport,
    clientId:'app-client',waitMs:0});
  f.request = {action:'consent',context:ctx,bindingRevision:1,authorityRevision:0,listeningConsent:true};
  f.run = () => f.start({principal:p,request:f.request,signal:f.abort.signal});
  return f;
}
test('explicit Start resolves owned live meeting, PATCHes once and requires signed source',async()=>{
  const f=fixture();await f.run();assert.deepEqual(f.calls,['list','GET','PATCH']);
  const pending=fixture({noEvent:true});await assert.rejects(pending.run(),{code:'ZOOM_RTMS_WEBHOOK_PENDING'});
});
test('an existing verified stream does not issue another upstream Start',async()=>{
  const f=fixture();f.source={streamId:'verified'};await f.run();assert.deepEqual(f.calls,[]);
});
test('missing scope and missing consent never issue upstream requests',async()=>{
  const f=fixture();f.connection.scope='meeting:read:meeting_transcript';
  await assert.rejects(f.run(),{code:'ZOOM_RTMS_SCOPE_REQUIRED'});assert.deepEqual(f.calls,[]);
  f.request.listeningConsent=false;await assert.rejects(f.run(),{code:'ZOOM_RTMS_CONSENT_REQUIRED'});
});
test('foreign context, revision conflict, stopped and uncertain binding never start media',async()=>{
  for(const change of [f=>f.request.context={...ctx,agentId:'other'},f=>f.request.authorityRevision=1,
    f=>f.row.record.snapshot.state='stopped',f=>f.row.record.uncertain=true]){
    const f=fixture();change(f);await assert.rejects(f.run(),{code:'ZOOM_RTMS_BINDING_CHANGED'});
    assert.deepEqual(f.calls,[]);
  }
});
test('waiting meeting and different host are refused before PATCH',async()=>{
  for(const options of [{status:'waiting'},{host:'different'}]){
    const f=fixture(options);await assert.rejects(f.run());assert.equal(f.calls.includes('PATCH'),false);
  }
});
test('revoke, account reconnect and cancellation during discovery prevent Start',async()=>{
  for(const onGet of [f=>f.row.authorityRevision++,f=>f.connection.connectedAtMs++,f=>f.abort.abort()]){
    const f=fixture({onGet});await assert.rejects(f.run());assert.equal(f.calls.includes('PATCH'),false);
  }
});
test('provider rejection identifies account or host without forwarding private body',async()=>{
  for(const [code,expected] of [[2310,'ZOOM_RTMS_ACCOUNT_REJECTED'],[2308,'ZOOM_RTMS_HOST_REJECTED'],[9999,'ZOOM_RTMS_START_REJECTED']]){
    const f=fixture({patchError:code});await assert.rejects(f.run(),e=>e.code===expected&&!String(e).includes('secret'));
  }
});
test('duplicate in-flight Start is rejected and a revoked pending request cannot grant',async()=>{
  let release;const hold=new Promise(r=>release=r);const f=fixture({hold,onPatch:f=>f.row.authorityRevision++});
  const run=f.run();while(!f.calls.includes('PATCH'))await new Promise(r=>setImmediate(r));
  await assert.rejects(f.run(),{code:'ZOOM_RTMS_START_PENDING'});release();
  await assert.rejects(run,{code:'ZOOM_RTMS_BINDING_CHANGED'});assert.equal(f.calls.filter(x=>x==='PATCH').length,1);
});
test('silence, known PCM amplitude and malformed buffers produce honest numeric levels',()=>{
  assert.deepEqual(pcmLevel(Buffer.alloc(640),640),{level:0,peak:0});
  const b=Buffer.alloc(640);for(let i=0;i<b.length;i+=2)b.writeInt16LE(i%4?16384:-16384,i);
  assert.deepEqual(pcmLevel(b,640),{level:90,peak:50});
  assert.equal(pcmLevel(b,639),null);assert.equal(pcmLevel(Buffer.alloc(1),1),null);
});
test('level samples expire, paused values are zero and clear erases activity',()=>{
  let now=0;const meter=createAudioLevelMeter({clock:()=>now});
  assert.equal(meter.snapshot(true).received,false);meter.accept({level:65,peak:80});
  assert.equal(meter.snapshot(true).level,65);now=1300;assert.equal(meter.snapshot(true).level,0);
  assert.equal(meter.snapshot(false).received,false);meter.clear();assert.equal(meter.snapshot(true).packets,0);
});
function fakeSdk() {
  const clients=[];
  class Client {
    constructor(){clients.push(this);this.callbacks={};}
    setAudioParams(params){this.params=params;return true;}
    onAudioData(f){this.callbacks.audio=f;return true;}
    onTranscriptData(f){this.callbacks.text=f;return true;}
    onJoinConfirm(f){this.callbacks.join=f;return true;}
    onLeave(f){this.callbacks.leave=f;return true;}
    join(){this.callbacks.join(0);return true;}
    leave(){return true;}
    emit(){const b=Buffer.alloc(640);for(let i=0;i<b.length;i+=2)b.writeInt16LE(16384,i);this.callbacks.audio(b,640);}
  }
  return {Client,clients,RTMS_SDK_OK:0,configureLogger(){}};
}
test('a newly bound generation retires the abandoned local handle; old replies cannot revive it',async()=>{
  const sdk=fakeSdk(),t=createK135zRtmsCommandTransport({sdk,onTranscript:()=>true,audioLevels:true,
    resolveGrant:async({context})=>({context:{...context,streamId:'stream'},bindingRevision:context.generation,
      authorityRevision:1,viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true,validForMs:5000,
      serverUrls:'wss://media.zoom.us',signature:'a'.repeat(64)})});
  const cancellation={isCancelled:()=>false,subscribe:()=>()=>{}};
  const first=fixture().row.record.snapshot;
  const make=(s,id)=>({schemaVersion:1,action:'start',operation:{requestId:id,localEpoch:1,operationNumber:1},
    expectedContext:s.context,expectedSnapshotRevision:s.revision});
  try{
    const request=make(first,'first'),reply=await t.request({principal:p,request,snapshot:first,cancellation});
    assert.equal(t.settle({principal:p,request,reply}),true);
    const snapshot={...first,context:{...ctx,generation:2,sessionId:'new-session'}};
    const next=make(snapshot,'next'),accepted=await t.request({principal:p,request:next,snapshot,cancellation});
    assert.equal(accepted.outcome.kind,'acknowledged');assert.equal(t.settle({principal:p,request:next,reply:accepted}),true);
    assert.equal(t.captureActive({principal:p,context:reply.outcome.snapshot.context}),false);
    assert.equal(t.settle({principal:p,request,reply}),false);
    assert.equal(t.captureActive({principal:p,context:accepted.outcome.snapshot.context}),true);
    const stale=await t.request({principal:p,request,snapshot:first,cancellation});
    assert.equal(stale.outcome.kind,'failed');assert.equal(sdk.clients.length,2);
  }finally{t.close();}
});
test('SDK meter receives configured PCM only while connected and authorized',async()=>{
  const sdk=fakeSdk(),levels=[];let permitted=true;
  const stream=createK135zRtmsStream({sdk,context:{...ctx,streamId:'stream'},serverUrls:'wss://media.zoom.us',
    signature:'a'.repeat(64),authorize:()=>permitted,onTranscript:()=>true,onAudioLevel:x=>levels.push(x)});
  await stream.connect();assert.deepEqual(sdk.clients[0].params,{contentType:2,codec:1,sampleRate:1,channel:1,dataOpt:1,duration:20,frameSize:320});
  sdk.clients[0].emit();assert.equal(levels[0].level,90);
  permitted=false;sdk.clients[0].emit();assert.equal(levels.length,1);assert.equal(stream.status().phase,'closed');stream.close();
});
test('transport withholds levels until committed and blocks other contexts and Stop',async()=>{
  const sdk=fakeSdk();
  const t=createK135zRtmsCommandTransport({sdk,onTranscript:()=>true,audioLevels:true,
    resolveGrant:async({context})=>({context:{...context,streamId:'stream'},bindingRevision:1,authorityRevision:1,
      viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true,validForMs:5000,
      serverUrls:'wss://media.zoom.us',signature:'a'.repeat(64)})});
  const snapshot=fixture().row.record.snapshot;
  const request={schemaVersion:1,action:'start',operation:{requestId:'one',localEpoch:1,operationNumber:1},
    expectedContext:ctx,expectedSnapshotRevision:0};
  try {
    const reply=await t.request({principal:p,request,snapshot,cancellation:{isCancelled:()=>false,subscribe:()=>()=>{}}});
    assert.equal(reply.outcome.kind,'acknowledged');sdk.clients[0].emit();
    const bound=reply.outcome.snapshot.context;
    assert.equal(t.audioLevel({principal:p,context:bound}).received,false);
    assert.equal(t.settle({principal:p,request,reply}),true);sdk.clients[0].emit();
    assert.equal(t.audioLevel({principal:p,context:bound}).level,90);
    assert.equal(t.audioLevel({principal:p,context:{...bound,sessionId:'other'}}).received,false);
    t.close();assert.equal(t.audioLevel({principal:p,context:bound}).received,false);
  } finally {t.close();}
});
test('HTTP consent calls Start before granting and never grants if Start fails',async()=>{
  const f=fixture({patchError:2310});
  const handlers=Z.createK135zZoomHandlers({workspaceHttpEnabled:true,workspaceStore:f.store,
    workspaceStartRtms:f.start,authenticateRequest:async()=>p,
    resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
  let status,result;
  const req={headers:{authorization:'Bearer private', 'content-type':'application/json','x-korlix-agent-id':'nova'},body:f.request};
  await handlers.workspaceConsent(req,{setHeader(){},status(n){status=n;},json(x){result=x;}});
  assert.equal(status,403);assert.equal(result.error.code,'ZOOM_RTMS_ACCOUNT_REJECTED');assert.equal(f.calls.includes('consent'),false);
});
test('audio endpoint requires owned live consent and reveals numeric metadata only',async()=>{
  const f=fixture();let reads=0;
  const deps={workspaceHttpEnabled:true,workspaceStore:f.store,authenticateRequest:async()=>p,
    resolveEnterprise:async()=>true,authorizeAgent:async()=>true,
    workspaceTransport:{audioLevel({principal,context}){reads++;assert.deepEqual(principal,p);
      return {schemaVersion:1,context,active:true,available:true,received:true,packets:50,ageMs:10,level:65,peak:80};}}};
  const handlers=Z.createK135zZoomHandlers(deps);
  async function run(context=ctx,authorization='Bearer private'){
    let status,result,cache;
    await handlers.workspaceAudioLevel({headers:{authorization,'content-type':'application/json','x-korlix-agent-id':'nova'},
      body:{context}}, {setHeader(k,v){if(k==='Cache-Control')cache=v;},status(n){status=n;},json(x){result=x;}});
    assert.equal(cache,'no-store');return {status,result};
  }
  let out=await run();assert.equal(out.status,200);assert.equal(out.result.audioLevel.level,0);assert.equal(reads,0);
  f.row.validForMs=3000;f.row.authority.hostAuthorized=true;f.row.authority.listeningAuthorized=true;
  f.row.record.snapshot.state='listening';
  out=await run();assert.equal(out.result.audioLevel.level,65);assert.equal(reads,1);
  assert.deepEqual(Object.keys(out.result.audioLevel).sort(),['schemaVersion','context','active','available','received','packets','ageMs','level','peak'].sort());
  assert.equal((await run({...ctx,agentId:'other'})).status,409);assert.equal(reads,1);
  assert.equal((await run(ctx,'')).status,401);assert.equal(reads,1);
  f.row.validForMs=0;out=await run();assert.equal(out.result.audioLevel.received,false);assert.equal(reads,1);
  f.row.authority.viewerAuthorized=false;assert.equal((await run()).status,403);
});
