'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),{spawn}=require('node:child_process');
const {K135zSupabaseWorkspaceStore,K135zAtomicWorkspaceAdapter}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
const U='11111111-1111-4111-8111-111111111111',V='22222222-2222-4222-8222-222222222222';
const literal=x=>"'"+JSON.stringify(x).replace(/'/g,"''")+"'::jsonb";
const token=()=>({isCancelled:()=>false,subscribe:()=>()=>{}});
function register(sql) {
 let serial=0;
 const rpc=async(operation,payload,role='service_role')=>JSON.parse(await sql(
  "select public.k135z_workspace_commands_v1('"+operation+"',"+literal(payload)+');',role));
 const read=p=>rpc('read',{principal:p});
 async function fixture() {
  const p={tenantId:U,userId:U,agentId:'case-'+(++serial)};
  await sql("insert into public.korlix_live_convo_agent_profiles(user_id,agent_id) values('"+U+"','"+p.agentId+"');",'admin');
  let row=await rpc('bind',{principal:p,meetingUuid:'meeting-'+serial,expectedBindingRevision:0});
  assert.equal(row.status,'ok');
  const authorize=async(fields={})=>{
   const r=await read(p);return rpc('authorize',{principal:p,context:r.record.snapshot.context,bindingRevision:r.bindingRevision,
    authorityRevision:r.authorityRevision,hostAuthorized:true,listeningAuthorized:true,leaseSeconds:60,...fields});
  };
  row=await authorize();
  const client={async rpc(name,{operation,payload}){assert.equal(name,'k135z_workspace_commands_v1');
   try{return {data:await rpc(operation,payload),error:null};}catch{return {data:null,error:{message:'SQL rejected'}};}}};
  const store=new K135zSupabaseWorkspaceStore({client});let calls=0,op=0;
  const transport={async request({request,snapshot}){calls++;
   const current=await read(p),a=current.authority;
   return {schemaVersion:1,operation:request.operation,action:request.action,outcome:{kind:'acknowledged',snapshot:{...snapshot,
    context:{...snapshot.context,streamId:snapshot.context.streamId??(request.action==='start'?'stream-'+serial:null)},
    revision:snapshot.revision+1,state:{start:'listening',pause:'paused',stop:'stopped'}[request.action],
    hostAuthorized:a.hostAuthorized,listeningAuthorized:a.listeningAuthorized}}};
  }};
  const make=(r,action='start')=>({schemaVersion:1,operation:{requestId:'request-'+serial+'-'+(++op),localEpoch:1,operationNumber:op},
   action,expectedContext:r.record.snapshot.context,expectedSnapshotRevision:r.record.snapshot.revision});
  const adapter=new K135zAtomicWorkspaceAdapter({store,transport});
  return {p,row,client,store,adapter,transport,authorize,make,get calls(){return calls;},
   async run(action='start'){const r=await read(p);return adapter.requestAtomic({principal:p,request:make(r,action),cancellation:token()});}};
 }
 const expected=r=>({bindingRevision:r.bindingRevision,authorityRevision:r.authorityRevision,record:r.record,authority:r.authority});
 const save=(f,r,record)=>rpc('compare_save',{principal:f.p,context:r.record.snapshot.context,expected:expected(r),record});
 const reserve=(f,r)=>({...r.record,version:r.record.version+1,pending:{request:f.make(r),ticketVersion:r.record.version+1,phase:'prepared'}});
 test('Gate6G RPC denies public client roles',async()=>{
  for(const role of ['anon','authenticated','gate6g_untrusted'])
   await assert.rejects(()=>rpc('read',{principal:{tenantId:U,userId:U,agentId:'missing'}},role),/permission denied/);
 });
 test('Gate6G RPC uses invoker privileges fixed search path and private RLS',async()=>{
  const info=JSON.parse(await sql("select json_build_object('definer',p.prosecdef,'config',p.proconfig,'rls',c.relrowsecurity,"+
   "'anon_schema',has_schema_privilege('anon','k135z_workspace_private','USAGE')) from pg_proc p,pg_class c "+
   "where p.oid='public.k135z_workspace_commands_v1(text,jsonb)'::regprocedure and c.oid='k135z_workspace_private.bindings'::regclass;",'admin'));
  assert.equal(info.definer,false);assert(info.config.includes('search_path=pg_catalog, pg_temp'));assert.equal(info.rls,true);assert.equal(info.anon_schema,false);
  await assert.rejects(()=>sql('select * from k135z_workspace_private.bindings;','authenticated'),/permission denied/);
 });
 test('Gate6G binding creates a server session and initially grants no host or listening permission',async()=>{
  const p={tenantId:U,userId:U,agentId:'initial'};
  await sql("insert into public.korlix_live_convo_agent_profiles(user_id,agent_id) values('"+U+"','initial');",'admin');
  const r=await rpc('bind',{principal:p,meetingUuid:'meeting-initial',expectedBindingRevision:0});
  assert.equal(r.record.snapshot.state,'ready');assert.equal(r.record.snapshot.context.generation,1);
  assert.match(r.record.snapshot.context.sessionId,/^[a-f0-9-]{36}$/);assert.equal(r.record.snapshot.context.streamId,null);
  assert.equal(r.authority.hostAuthorized,false);assert.equal(r.authority.listeningAuthorized,false);
  assert.equal((await rpc('bind',{principal:p,meetingUuid:'replacement',expectedBindingRevision:1})).status,'conflict');
 });
 test('Gate6G malformed envelopes forged tenants and extra fields are rejected',async()=>{
  const f=await fixture();for(const payload of [null,{principal:{...f.p,tenantId:V}},{principal:{...f.p,agentId:123}},{principal:f.p,extra:true}])
   await assert.rejects(()=>rpc('read',payload),/K135Z_WORKSPACE_INVALID/);
  await assert.rejects(()=>rpc('unknown',{}),/K135Z_WORKSPACE_INVALID/);
 });
 test('Gate6G current tier inactive agents and deleted agents deny database access',async()=>{
  const f=await fixture();
  for(const change of ["update public.user_profiles set tier='pro' where id='"+U+"';",
   "update public.korlix_live_convo_agent_profiles set active=false where agent_id='"+f.p.agentId+"';",
   "update public.korlix_live_convo_agent_profiles set deleted_at=now() where agent_id='"+f.p.agentId+"';"]){
   try{await sql(change,'admin');assert.equal((await read(f.p)).status,'denied');}
   finally{await sql("update public.user_profiles set tier='enterprise' where id='"+U+"'; update public.korlix_live_convo_agent_profiles set active=true,deleted_at=null where agent_id='"+f.p.agentId+"';",'admin');}
  }
 });
 test('Gate6G user and agent bindings are isolated',async()=>{
  const f=await fixture();assert.equal((await read({...f.p,agentId:'unowned'})).status,'denied');
  assert.equal((await read({...f.p,tenantId:V,userId:V})).status,'denied');
 });
 test('Gate6G Start Pause resume and Stop roundtrip through the real SQL RPC and Gate6F client',async()=>{
  const f=await fixture();for(const [action,state] of [['start','listening'],['pause','paused'],['start','listening'],['stop','stopped']]){
   const reply=await f.run(action);assert.equal(reply.outcome.kind,'acknowledged');assert.equal(reply.outcome.snapshot.state,state);
  }
  const r=await read(f.p);assert.equal(r.record.version,12);assert.equal(r.record.snapshot.revision,4);assert.equal(r.record.pending,null);assert.equal(f.calls,4);
 });
 test('Gate6G concurrent stale reservations have exactly one winner',async()=>{
  const f=await fixture(),r=await read(f.p),record=reserve(f,r);
  const results=await Promise.all(Array.from({length:6},()=>save(f,r,record)));
  assert.equal(results.filter(x=>x.status==='ok').length,1);assert.equal(results.filter(x=>x.status==='conflict').length,5);
 });
 test('Gate6G changed authority and revoke-restore invalidate a previously read decision',async()=>{
  const f=await fixture(),r=await read(f.p);await f.authorize({hostAuthorized:false});await f.authorize();
  assert.equal((await save(f,r,reserve(f,r))).status,'conflict');assert.equal((await read(f.p)).record.pending,null);
 });
 test('Gate6G expired permission leases cannot dispatch or validate an old authority snapshot',async()=>{
  const f=await fixture(),r=await read(f.p);
  await sql("update k135z_workspace_private.bindings set authority_until=clock_timestamp()-interval '1 second' where agent_id='"+f.p.agentId+"';",'admin');
  assert.equal((await save(f,r,reserve(f,r))).status,'conflict');assert.equal((await f.run()).outcome.error.code,'DENIED');assert.equal(f.calls,0);
 });
 test('Gate6G invalid lease lengths and stale authorization revisions are rejected',async()=>{
  const f=await fixture();for(const leaseSeconds of [0,61,1.5])await assert.rejects(()=>f.authorize({leaseSeconds}),/K135Z_WORKSPACE_INVALID/);
  assert.equal((await f.authorize({authorityRevision:0})).status,'conflict');
 });
 test('Gate6G malformed record writes roll back without advancing reservations',async()=>{
  const f=await fixture(),r=await read(f.p);
  for(const record of [{...r.record,version:2},{...reserve(f,r),extra:true},{...reserve(f,r),uncertain:true},
   {...reserve(f,r),snapshot:{...r.record.snapshot,capabilities:{canSpeak:true}}}])
   await assert.rejects(()=>save(f,r,record),/K135Z_WORKSPACE_INVALID/);
  assert.deepEqual((await read(f.p)).record,r.record);
 });
 test('Gate6G snapshot state cannot jump directly from ready to listening',async()=>{
  const f=await fixture(),r=await read(f.p),record={...r.record,version:1,snapshot:{...r.record.snapshot,state:'listening',
   revision:1,context:{...r.record.snapshot.context,streamId:'forged'}}};
  await assert.rejects(()=>save(f,r,record),/K135Z_WORKSPACE_INVALID/);assert.equal(f.calls,0);
 });
 test('Gate6G stopped generations remain terminal and rebinding assigns a higher generation',async()=>{
  const f=await fixture();await f.run('stop');const old=await read(f.p);
  assert.equal((await f.run()).outcome.error.code,'CONFLICT');
  const next=await rpc('bind',{principal:f.p,meetingUuid:'next-meeting',expectedBindingRevision:old.bindingRevision});
  assert.equal(next.bindingRevision,old.bindingRevision+1);assert.equal(next.record.snapshot.context.generation,next.bindingRevision);
  assert.notEqual(next.record.snapshot.context.sessionId,old.record.snapshot.context.sessionId);
  assert.equal(next.authority.hostAuthorized,false);assert.equal((await save(f,old,old.record)).status,'conflict');
 });
 test('Gate6G unknown provider outcomes remain fenced in durable storage',async()=>{
  const f=await fixture();f.transport.request=async()=>{throw Error('provider unavailable');};
  assert.equal((await f.run()).outcome.error.remoteOutcome,'unknown');const r=await read(f.p);assert.equal(r.record.uncertain,true);
  await assert.rejects(()=>save(f,r,{...r.record,version:r.record.version+1,pending:null,uncertain:false}),/K135Z_WORKSPACE_INVALID/);
  assert.equal((await f.run('stop')).outcome.error.code,'CONFLICT');
 });
 test('Gate6G read-only refresh cannot bypass an authority change at compare-save',async()=>{
  const f=await fixture(),r=await read(f.p);await f.authorize({listeningAuthorized:false});
  assert.equal((await save(f,r,r.record)).status,'conflict');assert.equal((await read(f.p)).record.version,0);
 });
 test('Gate6G a failed completion save preserves its dispatched reservation',async()=>{
  const f=await fixture(),original=f.client.rpc.bind(f.client);let commits=0;
  f.client.rpc=async(name,args)=>args.operation==='compare_save'&&++commits===3?{error:{message:'fixture failure'}}:original(name,args);
  assert.equal((await f.run()).outcome.error.remoteOutcome,'unknown');assert.equal((await read(f.p)).record.pending.phase,'dispatched');
 });
 test('Gate6G caller rollback removes the entire binding creation',async()=>{
  const p={tenantId:U,userId:U,agentId:'rollback'};
  await sql("insert into public.korlix_live_convo_agent_profiles(user_id,agent_id) values('"+U+"','rollback');",'admin');
  await sql("begin;select public.k135z_workspace_commands_v1('bind',"+literal({principal:p,meetingUuid:'rollback',expectedBindingRevision:0})+");rollback;",'service_role');
  assert.equal((await read(p)).status,'not_found');
 });
 test('Gate6G independent clients observe committed stopped records',async()=>{
  const f=await fixture();await f.run('stop');const store=new K135zSupabaseWorkspaceStore({client:f.client});
  const result=await store.read({principal:f.p,cancellation:token()});assert.equal(result.record.snapshot.state,'stopped');
 });
 test('Gate6G service clients cannot delete a generation fence directly',async()=>{
  await assert.rejects(()=>sql('delete from k135z_workspace_private.bindings;','service_role'),/permission denied/);
 });
 // Gate6K exercises the pending B5B migration in the isolated local database.
 const C=require('../k135z_zoom/b5b_contract.cjs');
 const b5=async(op,payload,role='service_role')=>JSON.parse(await sql(
   "select public.k135z_b5b_storage_v1('"+op+"',"+literal(payload)+');',role));
 let kserial=0;
 function stream() {
   const meeting_uuid='gate6k-'+(++kserial),rtms_stream_id='stream-'+kserial;
   const plan=(status,ts=100,fields={})=>C.eventPlan({body:{event:'meeting.rtms_'+status,event_ts:ts,
     payload:{meeting_uuid,rtms_stream_id,...(status==='started'?{account_id:'account-a'}:{}),...fields}}});
   const apply=p=>b5('event_apply',p);
   const get=p=>b5('session_get',{key:p.mutation.key});
   return {plan,apply,get};
 }
 test('Gate6K SQL accountless Stop closes exact stream without changing another stream',async()=>{
   const f=stream(),a=f.plan('started'),b=f.plan('started',100,{rtms_stream_id:'unrelated'});
   await f.apply(a);await f.apply(b);await f.apply(f.plan('stopped',90));
   assert.equal((await f.get(a)).status,'stopped');assert.equal((await f.get(a)).eventTs,100);
   assert.equal((await f.get(b)).status,'started');
 });
 test('Gate6K SQL terminal before Start survives fresh RPC calls and blocks revival',async()=>{
   for(const status of ['stopped','interrupted']) {
     const f=stream();await f.apply(f.plan(status));
     for(const ts of [90,110]) {const a=f.plan('started',ts);await f.apply(a);assert.equal((await f.get(a)).status,status);}
   }
 });
 test('Gate6K SQL Stop remains terminal after Interrupted and standalone upsert',async()=>{
   const f=stream(),a=f.plan('started');await f.apply(a);await f.apply(f.plan('stopped'));
   await f.apply(f.plan('interrupted',120));
   const value=await b5('session_upsert',{key:a.mutation.key,record:{...a.mutation.record,eventTs:130}});
   assert.equal(value.status,'stopped');assert.equal((await f.get(a)).status,'stopped');
 });
 test('Gate6K SQL duplicate and ID conflict do not mutate a second stream',async()=>{
   const f=stream(),p=f.plan('stopped');await f.apply(p);assert.equal((await f.apply(p)).duplicate,true);
   const wrong=f.plan('stopped',101,{rtms_stream_id:'other'});wrong.eventId=p.eventId;
   await assert.rejects(()=>f.apply(wrong),/ZOOM_EVENT_ID_CONFLICT/);
   const a=f.plan('started',102,{rtms_stream_id:'other'});await f.apply(a);assert.equal((await f.get(a)).status,'started');
 });
 test('Gate6K SQL rejects malformed terminal plans before recording an event',async()=>{
   const f=stream(),p=f.plan('stopped');
   for(const mutation of [{...p.mutation,status:'started'},{...p.mutation,streamId:null},{...p.mutation,account:'fabricated'}])
     await assert.rejects(()=>f.apply({...p,mutation}),/ZOOM_/);
   assert.equal((await f.apply(p)).accepted,true);
 });
 test('Gate6K SQL terminal storage is private and RPC denies all public client roles',async()=>{
   const f=stream();for(const role of ['anon','authenticated','gate6g_untrusted'])
     await assert.rejects(()=>b5('event_apply',f.plan('stopped'),role),/permission denied/);
   for(const role of ['anon','authenticated','service_role'])
     await assert.rejects(()=>sql('select * from k135z_b5b_private.stream_terminals;',role),/permission denied/);
   assert.equal(await sql("select to_json(relrowsecurity) from pg_class where oid='k135z_b5b_private.stream_terminals'::regclass;",'admin'),'true');
 });
 test('Gate6K SQL concurrent Start and Stop always leave a terminal session',async()=>{
   const f=stream(),a=f.plan('started');await Promise.all([f.apply(a),f.apply(f.plan('stopped'))]);
   assert.equal((await f.get(a)).status,'stopped');
 });
 test('Gate6K SQL legacy account-bearing Stop preserves other account state',async()=>{
   const f=stream(),a=f.plan('started'),b=f.plan('started',100,{account_id:'account-b'});
   await f.apply(a);await f.apply(b);await f.apply(f.plan('stopped',110,{account_id:'account-a'}));
   assert.equal((await f.get(a)).status,'stopped');assert.equal((await f.get(b)).status,'started');
 });

 const {SupabaseZoomRepository}=require('../k135z_zoom/b5b_repository.cjs');
 const {ZoomTokenVault,EnvelopeCipher}=require('../k135z_zoom/zoom_token_vault.cjs');
 const {createK135zRtmsGrantResolver}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
 async function captureFixture() {
   const f=await fixture(),context=f.row.record.snapshot.context;
   const client={async rpc(name,args){try{return {data:name==='k135z_b5b_storage_v1'
     ? await b5(args.operation,args.payload):await rpc(args.operation,args.payload),error:null};}
     catch{return {data:null,error:{message:'local SQL rejected'}};}}};
   const repository=new SupabaseZoomRepository({client});
   const vault=new ZoomTokenVault({repository,cipher:new EnvelopeCipher(Buffer.alloc(32,6)),clock:()=>1000});
   await vault.storeConnection(f.p,{access_token:'fixture-access',refresh_token:'fixture-refresh',expires_in:3600,
     account_id:'capture-account',user_id:'capture-host',scope:'meeting:read:meeting_transcript'});
   const plan=(status='started',extra={},ts=1100)=>C.eventPlan({body:{event:'meeting.rtms_'+status,event_ts:ts,
     payload:{meeting_uuid:context.meetingUuid,rtms_stream_id:'capture-stream-'+f.p.agentId,
       ...(status==='started'?{account_id:'capture-account',operator_id:'capture-host',is_original_host:true,
         server_urls:'wss://rtms.zoom.us'}:{}),...extra}}});
   const query={key:C.identityKey(f.p),meetingUuid:context.meetingUuid,streamId:null};
   const store=new K135zSupabaseWorkspaceStore({client}),resolve=createK135zRtmsGrantResolver({store,repository,clientId:'fixture-client',clientSecret:'fixture-secret'});
   return {...f,client,repository,store,context,plan,query,resolve,
     source:()=>repository.getCaptureSource(query),apply:p=>repository.applyWebhookEvent(p),
     grant:action=>resolve({principal:f.p,context,action:action??'start',signal:new AbortController().signal})};
 }
 test('Gate6L SQL verified host source and permission lease produce a bound signed grant',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const g=await f.grant();
   assert.equal(g.context.streamId,'capture-stream-'+f.p.agentId);assert.equal(g.bindingRevision,f.row.bindingRevision);
   assert.equal(g.hostAuthorized,true);assert.equal(g.listeningAuthorized,true);assert(g.validForMs>0&&g.validForMs<=5000);
   assert.equal(g.signature,require('node:crypto').createHmac('sha256','fixture-secret')
     .update(['fixture-client',f.context.meetingUuid,g.context.streamId].join(',')).digest('hex'));
   const wire=JSON.stringify(g);assert(!wire.includes('fixture-secret'));assert(!wire.includes('fixture-access'));
 });
 test('Gate6L SQL capture lease exposes remaining time without issuing or renewing permission',async()=>{
   const f=await captureFixture(),before=await read(f.p),a=await f.store.readCaptureLease({principal:f.p,context:f.context});
   const b=await f.store.readCaptureLease({principal:f.p,context:f.context});assert(b.validForMs<=a.validForMs);
   assert(a.validForMs>0&&a.validForMs<=60000);assert.equal(b.authorityRevision,before.authorityRevision);
   assert.deepEqual((await read(f.p)),before);
 });
 test('Gate6L SQL expired or revoked consent denies Start and still allows Stop grant',async()=>{
   const f=await captureFixture();await f.apply(f.plan());
   await sql("update k135z_workspace_private.bindings set authority_until=clock_timestamp()-interval '1 second' where agent_id='"+f.p.agentId+"';",'admin');
   await assert.rejects(f.grant(),{code:'DENIED'});const stop=await f.grant('stop');assert.equal(stop.validForMs,0);assert.equal(stop.hostAuthorized,false);
 });
 test('Gate6L SQL source lookup rejects another principal account operator or non-host',async()=>{
   const f=await captureFixture();for(const fields of [{operator_id:'other'},{account_id:'other'},{is_original_host:false}]) {
     const p=f.plan('started',fields,1200);await f.apply(p);assert.equal(await f.source(),null);
   }
   await f.apply(f.plan('started',{},1300));
   assert.equal(await f.repository.getCaptureSource({...f.query,key:C.identityKey({...f.p,agentId:'unconnected'})}),null);
 });
 test('Gate6L SQL source requires transcript scope and a connection older than the event',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const record=await f.repository.getConnection(f.query.key);
   for(const fields of [{scope:'meeting:read'},{scope:'meeting:read:meeting_transcripts'},
     {scope:'meeting:read:meeting_transcript:admin'},{connectedAtMs:1200}]) {
     await f.repository.saveConnection(f.query.key,{...record,...fields});assert.equal(await f.source(),null);
   }
 });
 test('Gate6L SQL ambiguous active streams are denied without guessing the latest',async()=>{
   const f=await captureFixture();await f.apply(f.plan());await f.apply(f.plan('started',{rtms_stream_id:'second-stream'},1200));
   assert.equal(await f.source(),null);
   assert.equal((await f.repository.getCaptureSource({...f.query,streamId:'second-stream'})).streamId,'second-stream');
 });
 test('Gate6L SQL accountless Stop and Interrupted invalidate stored capture source',async()=>{
   for(const status of ['stopped','interrupted']) {
     const f=await captureFixture();await f.apply(f.plan());assert(await f.source());
     await f.apply(f.plan(status));assert.equal(await f.source(),null);await assert.rejects(f.grant(),{code:'DENIED'});
   }
 });
 test('Gate6L SQL deauthorization deletes owned connection and makes source unavailable',async()=>{
   const f=await captureFixture();await f.apply(f.plan());
   await f.repository.applyWebhookEvent(C.eventPlan({body:{event:'app_deauthorized',event_ts:1400,
     payload:{account_id:'capture-account',user_id:'capture-host'}}}));assert.equal(await f.source(),null);
 });
 test('Gate6L SQL older Start cannot replace a newer host source',async()=>{
   const f=await captureFixture();await f.apply(f.plan('started',{},1300));
   await f.apply(f.plan('started',{operator_id:'other'},1200));assert(await f.source());
   const metadata=f.plan('started',{},1400);delete metadata.mutation.source;await f.apply(metadata);assert.equal(await f.source(),null);
 });
 test('Gate6L SQL malformed source rolls back event insertion and standalone metadata cannot grant',async()=>{
   const f=await captureFixture(),p=f.plan(),bad=structuredClone(p);bad.mutation.source.originalHost='true';
   await assert.rejects(()=>b5('event_apply',bad),/ZOOM_/);assert.equal((await f.apply(p)).accepted,true);
   await f.repository.upsertRtmsSession(p.mutation.key,p.mutation.record);assert.equal(await f.source(),null);
 });
 test('Gate6L SQL provider credentials and capture leases remain unavailable to public roles',async()=>{
   const f=await captureFixture();await f.apply(f.plan());for(const role of ['anon','authenticated','gate6g_untrusted']) {
     await assert.rejects(()=>b5('capture_source',f.query,role),/permission denied/);
     await assert.rejects(()=>rpc('capture_lease',{principal:f.p},role),/permission denied/);
   }
   await assert.rejects(()=>sql('select * from k135z_b5b_private.capture_sources;','service_role'),/permission denied/);
 });
 test('Gate6L SQL current agent ownership and entitlement govern permission reads',async()=>{
   const f=await captureFixture();await f.apply(f.plan());
   await sql("update public.korlix_live_convo_agent_profiles set active=false where agent_id='"+f.p.agentId+"';",'admin');
   await assert.rejects(f.grant(),{code:'DENIED'});
 });
 test('Gate6L SQL owned event drives atomic Start Pause and Stop through the SDK bridge',async t=>{
   const f=await captureFixture();await f.apply(f.plan());let joined=0,left=0;
   class Client {
     onJoinConfirm(fn){this.confirm=fn;return true;}onTranscriptData(){return true;}onLeave(){return true;}
     join(){joined++;this.confirm(0);return true;}leave(){left++;return true;}
   }
   const {createK135zRtmsCommandTransport}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
   const transport=createK135zRtmsCommandTransport({sdk:{Client,RTMS_SDK_OK:0,configureLogger(){}},resolveGrant:f.resolve,onTranscript:()=>true});
   t.after(()=>transport.close());const adapter=new K135zAtomicWorkspaceAdapter({store:f.store,transport});
   for(const [action,state] of [['start','listening'],['pause','paused'],['stop','stopped']]) {
     const row=await read(f.p),reply=await adapter.requestAtomic({principal:f.p,request:f.make(row,action),cancellation:token()});
     assert.equal(reply.outcome.kind,'acknowledged');assert.equal(reply.outcome.snapshot.state,state);
   }
   assert.equal(joined,1);assert.equal(left,1);assert.equal((await read(f.p)).record.pending,null);
 });

 // Gate6M consent changes execute against the same real SQL used in deployment.
 async function consent6m(f,action='consent',fields={}) {
   const r=await read(f.p);
   return f.store.changeConsent({principal:f.p,request:{action,context:r.record.snapshot.context,
     bindingRevision:r.bindingRevision,authorityRevision:r.authorityRevision,
     ...(action==='consent'?{listeningConsent:true}:{}),...fields}});
 }
 test('Gate6M SQL consent requires an owned signed host source',async()=>{
   const f=await captureFixture();await consent6m(f,'revoke');
   await assert.rejects(()=>consent6m(f),{code:'DENIED'});
   await f.apply(f.plan('started',{is_original_host:false}));await assert.rejects(()=>consent6m(f),{code:'DENIED'});
   await f.apply(f.plan('started',{},1200));const a=await consent6m(f);
   assert.equal(a.authority.hostAuthorized,true);assert.equal(a.authority.listeningAuthorized,true);
   assert(a.validForMs>0&&a.validForMs<=30000);
 });
 test('Gate6M SQL renewal preserves authority revision record and command fences',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const a=await consent6m(f);
   const b=await consent6m(f,'renew');assert.equal(b.authorityRevision,a.authorityRevision);
   assert.deepEqual(b.record,a.record);assert.equal(b.bindingRevision,a.bindingRevision);
   assert(b.validForMs>0&&b.validForMs<=30000);
   assert.equal((await save(f,await read(f.p),reserve(f,await read(f.p)))).status,'ok');
 });
 test('Gate6M SQL expired revoked and stale consent cannot be renewed',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const a=await consent6m(f);
   await sql("update k135z_workspace_private.bindings set authority_until=clock_timestamp()-interval '1 second' where agent_id='"+f.p.agentId+"';",'admin');
   await assert.rejects(()=>consent6m(f,'renew'),{code:'DENIED'});
   await consent6m(f);await consent6m(f,'revoke');
   await assert.rejects(()=>consent6m(f,'renew'),{code:'DENIED'});
   await assert.rejects(()=>consent6m(f,'renew',{authorityRevision:a.authorityRevision}),{code:'CONFLICT'});
 });
 test('Gate6M SQL permission issue is explicit and cannot accept caller host or duration',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const r=await read(f.p);
   const base={principal:f.p,context:f.context,bindingRevision:r.bindingRevision,authorityRevision:r.authorityRevision};
   for(const extra of [{listeningConsent:false},{listeningConsent:'true'},{listeningConsent:true,hostAuthorized:true},
     {listeningConsent:true,leaseSeconds:600}])
     await assert.rejects(()=>rpc('consent',{...base,...extra}),/K135Z_WORKSPACE_INVALID/);
   assert.equal((await read(f.p)).authorityRevision,r.authorityRevision);
 });
 test('Gate6M SQL consent operations reject stale context and revision fences',async()=>{
   const f=await captureFixture();await f.apply(f.plan());
   for(const action of ['consent','renew','revoke'])for(const fields of [
     {context:{...f.context,meetingUuid:'foreign'}},{bindingRevision:99},{authorityRevision:99}])
     await assert.rejects(()=>consent6m(f,action,fields),{code:'CONFLICT'});
 });
 test('Gate6M SQL provider Stop and disconnect deny renewal but allow revocation',async()=>{
   const f=await captureFixture();await f.apply(f.plan());await consent6m(f);
   await f.apply(f.plan('stopped',{},1300));await assert.rejects(()=>consent6m(f,'renew'),{code:'DENIED'});
   await f.repository.deleteConnection(f.query.key);const a=await consent6m(f,'revoke');
   assert.equal(a.validForMs,0);assert.equal(a.authority.listeningAuthorized,false);
 });
 test('Gate6M SQL pending and stopped commands cannot issue or renew consent',async()=>{
   const f=await captureFixture();await f.apply(f.plan());let r=await read(f.p);
   await save(f,r,reserve(f,r));
   for(const action of ['consent','renew'])await assert.rejects(()=>consent6m(f,action),{code:'CONFLICT'});
   const a=await consent6m(f,'revoke');assert.equal(a.authority.hostAuthorized,false);
   const g=await captureFixture();await g.apply(g.plan());await g.run('stop');
   for(const action of ['consent','renew'])await assert.rejects(()=>consent6m(g,action),{code:'CONFLICT'});
 });
 test('Gate6M SQL consent cannot be called by public roles or inactive agents',async()=>{
   const f=await captureFixture();await f.apply(f.plan());const r=await read(f.p),p={principal:f.p,context:f.context,
     bindingRevision:r.bindingRevision,authorityRevision:r.authorityRevision};
   for(const role of ['anon','authenticated','gate6g_untrusted'])for(const op of ['consent','renew','revoke'])
     await assert.rejects(()=>rpc(op,{...p,...(op==='consent'?{listeningConsent:true}:{})},role),/permission denied/);
   await sql("update public.korlix_live_convo_agent_profiles set active=false where agent_id='"+f.p.agentId+"';",'admin');
   assert.equal((await rpc('renew',p)).status,'denied');
 });
 test('Gate6M SQL bind client creates the next server generation without permission',async()=>{
   const f=await captureFixture();await f.run('stop');const old=await read(f.p);
   const row=await f.store.bindWorkspace({principal:f.p,meetingUuid:'next-owned-meeting',expectedBindingRevision:old.bindingRevision});
   assert.equal(row.bindingRevision,old.bindingRevision+1);assert.equal(row.validForMs,0);
   assert.equal(row.authority.listeningAuthorized,false);assert.notEqual(row.record.snapshot.context.sessionId,f.context.sessionId);
 });
 test('Gate6M SQL new consent is refused during listening while renewal keeps the SDK capture open',async t=>{
   const f=await captureFixture();await f.apply(f.plan());await consent6m(f);let joins=0,leaves=0;
   class Client {onJoinConfirm(fn){this.confirm=fn;return true;}onTranscriptData(){return true;}onLeave(){return true;}
     join(){joins++;this.confirm(0);return true;}leave(){leaves++;return true;}}
   const routes=require('../k135z_zoom/zoom_routes.cjs'),deps=routes.createK135zZoomDependencies({env:{NODE_ENV:'test',
     KORLIX_ZOOM_CLIENT_ID:'fixture-client',KORLIX_ZOOM_CLIENT_SECRET:'fixture-secret'},repository:f.repository,
     workspaceHttpEnabled:true,workspaceCommandClient:f.client,rtmsSdk:{Client,RTMS_SDK_OK:0,configureLogger(){}},onRtmsTranscript:()=>true,
     authenticateRequest:async()=>f.p,resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
   t.after(()=>deps.workspaceTransport.close());const handlers=routes.createK135zZoomHandlers(deps);
   const invoke=async(name,body)=>{const res={status(n){this.code=n;return this;},json(v){this.body=v;return this;},setHeader(){}};
     await handlers[name]({headers:{authorization:'Bearer fixture-token','content-type':'application/json'},body},res);
     assert.equal(res.code,200,JSON.stringify(res.body));return res.body;};
   await invoke('workspaceCommand',f.make(await read(f.p),'start'));assert.equal(joins,1);
   await assert.rejects(()=>consent6m(f),{code:'CONFLICT'});
   const before=await read(f.p);await invoke('workspaceConsent',{action:'renew',context:before.record.snapshot.context,
     bindingRevision:before.bindingRevision,authorityRevision:before.authorityRevision});
   assert.equal((await read(f.p)).authorityRevision,before.authorityRevision);
   await new Promise(r=>setTimeout(r,1100));assert.equal(leaves,0);assert.equal(joins,1);
   for(const action of ['pause','start','stop']) {
     const out=await invoke('workspaceCommand',f.make(await read(f.p),action));
     assert.equal(out.reply.outcome.kind,'acknowledged',JSON.stringify(out));
   }
   assert.equal(joins,2);assert.equal(leaves,2);
 });

}
function nativeSql() {
 const root=process.env.K135Z_G6G_LOCAL_ROOT,nonce=process.env.K135Z_G6G_NONCE,psql=process.env.K135Z_G6G_PSQL;
 assert(root&&/^\/tmp\/k135z-g6g-[a-f0-9]{24}$/.test(root));assert(nonce&&/^[a-f0-9]{48}$/.test(nonce));
 assert(psql&&/^\/usr\/lib\/postgresql\/(15|16|17|18)\/bin\/psql$/.test(psql));
 for(const p of [root,root+'/socket',root+'/data']){assert.equal(fs.realpathSync(p),p);const s=fs.statSync(p);
  assert(s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o777)===0o700);}
 const sql=(text,role='service_role')=>new Promise((resolve,reject)=>{
  assert(['admin','service_role','anon','authenticated','gate6g_untrusted'].includes(role));
  const proc=spawn(psql,['-X','-w','-qAt','-v','ON_ERROR_STOP=1','-h',root+'/socket','-p','5432','-U','k135z_local_admin','-d','k135z_gate6g_local'],
   {env:{PATH:'/usr/bin:/bin',HOME:root,PGPASSFILE:'/dev/null',PGSERVICEFILE:'/dev/null',PGCONNECT_TIMEOUT:'5',
    PGOPTIONS:'-c statement_timeout=10000 -c lock_timeout=5000',LD_PRELOAD:process.env.LD_PRELOAD||''},stdio:['pipe','pipe','pipe']});
  let out='',err='',limited=false;const timer=setTimeout(()=>{limited=true;proc.kill('SIGKILL');},15000);
  proc.stdout.on('data',b=>{out+=b;if(out.length>1048576){limited=true;proc.kill('SIGKILL');}});
  proc.stderr.on('data',b=>{err+=b;if(err.length>1048576){limited=true;proc.kill('SIGKILL');}});
  proc.on('error',e=>{clearTimeout(timer);reject(e);});proc.on('close',code=>{clearTimeout(timer);
   if(code||limited)reject(Error(limited?'LOCAL_SQL_LIMIT':err.trim()));else resolve(out.trim());});
  proc.stdin.on('error',()=>{});proc.stdin.end((role==='admin'?'':'set role '+role+';\n')+text+'\n');
 });
 test.before(async()=>{const info=JSON.parse(await sql("select json_build_object('directory',current_setting('data_directory'),"+
  "'nonce',current_setting('k135z.gate6g_instance',true),'database',current_database(),'tcp',inet_server_addr());",'admin'));
  assert.deepEqual(info,{directory:root+'/data',nonce,database:'k135z_gate6g_local',tcp:null});});
 return sql;
}
module.exports={register};
if(require.main===module)register(nativeSql());
