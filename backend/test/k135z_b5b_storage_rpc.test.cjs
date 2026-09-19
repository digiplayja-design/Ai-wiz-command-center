'use strict';
// Gate6A requires the isolated Unix-socket harness. No URL, remote host, fallback, or skips.
const test=require('node:test'), assert=require('node:assert/strict');
const fs=require('node:fs'), path=require('node:path');
const {spawn}=require('node:child_process');
const C=require('../k135z_zoom/b5b_contract.cjs');
const {SupabaseZoomRepository}=require('../k135z_zoom/b5b_repository.cjs');
const U='11111111-1111-4111-8111-111111111111', V='22222222-2222-4222-8222-222222222222';
const P={tenantId:'demo_tenant',userId:U,agentId:'nova'};
let cfg;
function configuration() {
  const root=process.env.K135Z_G6A_LOCAL_ROOT, nonce=process.env.K135Z_G6A_NONCE,
    psql=process.env.K135Z_G6A_PSQL;
  assert(root && /^\/tmp\/k135z-g6a-[A-Za-z0-9_-]+$/.test(root),'isolated test root required');
  assert(nonce && /^[a-f0-9]{48}$/.test(nonce),'isolated instance binding required');
  assert(psql && /^\/usr\/lib\/postgresql\/(15|16|17|18)\/bin\/psql$/.test(psql),'approved local psql required');
  for(const p of [root,root+'/socket',root+'/data']) {
    assert.equal(fs.realpathSync(p),p,'linked local test path');
    const s=fs.lstatSync(p);assert(s.isDirectory() && s.uid===process.getuid() && (s.mode&0o777)===0o700);
  }
  const marker=JSON.parse(fs.readFileSync(root+'/INSTANCE.json','utf8'));
  assert.equal(marker.nonce,nonce);assert.equal(marker.database,'k135z_gate6a_local');
  return {root,nonce,psql};
}
function sql(text,role='service_role') {
  assert(cfg,'local instance must be verified first');
  assert(['service_role','k135z_local_admin','anon','authenticated','gate6a_untrusted'].includes(role));
  const prefix=role==='k135z_local_admin'?'':'set role '+role+';\n';
  const input=prefix+text+'\n';
  return new Promise((resolve,reject)=>{
    const p=spawn(cfg.psql,['-X','-w','-qAt','-v','ON_ERROR_STOP=1','-h',cfg.root+'/socket',
      '-p','5432','-U','k135z_local_admin','-d','k135z_gate6a_local'],{
      env:{PATH:'/usr/bin:/bin',HOME:cfg.root,LANG:'C',LC_ALL:'C',PGCONNECT_TIMEOUT:'5',
        PGPASSFILE:'/dev/null',PGSERVICEFILE:'/dev/null',PGOPTIONS:'-c statement_timeout=15000 -c lock_timeout=10000'},
      stdio:['pipe','pipe','pipe']});
    let out='',err='',limit=false;
    const timer=setTimeout(()=>{limit=true;p.kill('SIGKILL');},20000);
    p.on('error',e=>{clearTimeout(timer);reject(e);});
    p.stdout.on('data',b=>{out+=b;if(out.length>1048576){limit=true;p.kill('SIGKILL');}});
    p.stderr.on('data',b=>{err+=b;if(err.length>1048576){limit=true;p.kill('SIGKILL');}});
    p.on('close',rc=>{clearTimeout(timer);
      if(rc!==0||limit)reject(new Error(limit?'LOCAL_SQL_TIMEOUT_OR_LIMIT':err.trim()));else resolve(out.trim());});
    p.stdin.on('error',()=>{});p.stdin.end(input);
  });
}
function expression(op,payload) {
  assert(/^[a-z_]+$/.test(op));
  const b=Buffer.from(JSON.stringify(payload)).toString('base64');
  return "public.k135z_b5b_storage_v1('"+op+"',convert_from(decode('"+b+"','base64'),'UTF8')::jsonb)";
}
async function rpc(op,payload,role='service_role') {return JSON.parse(await sql('select '+expression(op,payload)+';',role));}
const repo=new SupabaseZoomRepository({client:{async rpc(name,{operation,payload}) {
  assert.equal(name,'k135z_b5b_storage_v1');
  try{return {data:await rpc(operation,payload),error:null};}catch{return {data:null,error:{message:'local test SQL rejected'}};}
}}});
function state(extra={}) {return {...P,returnTo:null,createdAtMs:1000,expiresAtMs:10000,...extra};}
function connection(principal=P,extra={}) {const key=C.identityKey(principal);return {key,...principal,zoomAccountId:'account-A',
  zoomUserId:'zoom-user-A',scope:'meeting:read',expiresAtMs:30000,connectedAtMs:1000,updatedAtMs:2000,
  encryptedTokens:{version:2,algorithm:'aes-256-gcm',iv:Buffer.alloc(12,1).toString('base64url'),
    tag:Buffer.alloc(16,2).toString('base64url'),ciphertext:Buffer.from('synthetic ciphertext').toString('base64url')},...extra};}
function session(label,status='started',eventTs=1000,account='account-A') {
  const sessionKey=C.hash(JSON.stringify([account,'meeting-'+label,'stream-'+label]));
  return {sessionKey,zoomAccountId:account,meetingUuid:'meeting-'+label,streamId:'stream-'+label,eventTs,status,
    mediaConnected:false,transcriptCollected:false,audioInjected:false};
}
function event(label,mutation={kind:'none'},name='meeting.updated') {
  return {eventId:C.hash('event-'+label),payloadHash:C.hash('payload-'+label),event:name,eventTs:1000,mutation};
}
function sessEvent(label,v) {return {...event(label,{kind:'session',key:v.sessionKey,record:v},'meeting.rtms_'+v.status),eventTs:v.eventTs};}
async function denied(op,payload,code='ZOOM_') {await assert.rejects(()=>rpc(op,payload),e=>e.message.includes(code));}

test.before(async()=>{
  cfg=configuration();
  const info=JSON.parse(await sql("select json_build_object('directory',current_setting('data_directory'),"+
    "'nonce',current_setting('k135z.gate6a_instance',true),'db',current_database(),'tcp',inet_server_addr());",'k135z_local_admin'));
  assert.deepEqual(info,{directory:cfg.root+'/data',nonce:cfg.nonce,db:'k135z_gate6a_local',tcp:null});
});

test('RPC has exact operation and payload parameters and a hardened definer path',async()=>{
  const r=JSON.parse(await sql("select json_build_object('definer',prosecdef,'args',proargnames,'config',proconfig) "+
    "from pg_proc where oid='public.k135z_b5b_storage_v1(text,jsonb)'::regprocedure;",'k135z_local_admin'));
  assert.equal(r.definer,true);assert.deepEqual(r.args,['operation','payload']);
  assert(r.config.includes('search_path=pg_catalog, pg_temp'));
});
test('RPC denies anon authenticated and ungranted roles',async()=>{
  for(const role of ['anon','authenticated','gate6a_untrusted'])
    await assert.rejects(()=>rpc('session_get',{key:C.hash('missing')},role),/permission denied/);
});
test('private schema has RLS and no direct table access for service clients',async()=>{
  const r=JSON.parse(await sql("select json_build_object('count',count(*),'rls',bool_and(relrowsecurity)) "+
    "from pg_class where relnamespace='k135z_b5b_private'::regnamespace and relkind='r';",'k135z_local_admin'));
  assert.equal(r.count,4);assert.equal(r.rls,true);
  for(const role of ['service_role','anon','authenticated','gate6a_untrusted'])
    await assert.rejects(()=>sql('select * from k135z_b5b_private.connections;',role),/permission denied/);
});
test('unknown operation null values and extra envelope fields are rejected',async()=>{
  await denied('unknown',{});await denied('session_get',null);
  await denied('session_get',{key:C.hash('missing'),extra:true});
  await denied('session_get',{key:null});
});
test('state roundtrip through the unchanged Supabase repository adapter',async()=>{
  const h=C.hash('state-roundtrip'),v=state();await repo.saveOAuthState(h,v);
  assert.deepEqual(await repo.consumeOAuthState(h,2000),v);
  await assert.rejects(()=>repo.consumeOAuthState(h,2000),e=>e.code==='ZOOM_OAUTH_STATE_REPLAYED');
});
test('unknown state is invalid without creating a consumed record',async()=>{
  assert.deepEqual(await rpc('state_consume',{stateHash:C.hash('never-created'),nowMs:2000}),{outcome:'invalid'});
});
test('expired and premature state attempts consume once and then replay',async()=>{
  for(const [label,nowMs] of [['expired',10000],['premature',999]]){
    const stateHash=C.hash(label);await rpc('state_create',{stateHash,record:state()});
    assert.deepEqual(await rpc('state_consume',{stateHash,nowMs}),{outcome:'expired'});
    assert.deepEqual(await rpc('state_consume',{stateHash,nowMs:2000}),{outcome:'replayed'});
  }
});
test('concurrent OAuth state consumers yield exactly one winner',async()=>{
  const stateHash=C.hash('parallel-state');await rpc('state_create',{stateHash,record:state()});
  const r=await Promise.all(Array.from({length:6},()=>rpc('state_consume',{stateHash,nowMs:2000})));
  assert.equal(r.filter(x=>x.outcome==='ok').length,1);assert.equal(r.filter(x=>x.outcome==='replayed').length,5);
});
test('duplicate and already-consumed state hashes cannot be recreated',async()=>{
  const stateHash=C.hash('state-no-reset'),record=state();await rpc('state_create',{stateHash,record});
  await denied('state_create',{stateHash,record},'ZOOM_STATE_EXISTS');
  await rpc('state_consume',{stateHash,nowMs:2000});await denied('state_create',{stateHash,record},'ZOOM_STATE_EXISTS');
});
test('state TTL fractional clocks identity fields and unknown user are rejected',async()=>{
  for(const r of [state({expiresAtMs:1000}),state({expiresAtMs:601001}),state({createdAtMs:1.5}),
    state({agentId:null}),state({userId:'00000000-0000-0000-0000-000000000000'}),
    {...state(),extra:1}])await denied('state_create',{stateHash:C.hash(JSON.stringify(r)),record:r});
  await assert.rejects(()=>rpc('state_create',{stateHash:C.hash('unknown-user'),record:state({userId:'33333333-3333-4333-8333-333333333333'})}),/foreign key/);
});
test('returnTo supports null and HTTPS while rejecting unsafe forms',async()=>{
  const record=state({returnTo:'https://example.test/app?done=1'}),stateHash=C.hash('return-ok');
  await rpc('state_create',{stateHash,record});assert.deepEqual((await rpc('state_consume',{stateHash,nowMs:2000})).record,record);
  for(const returnTo of ['http://example.test','https://user:pass@example.test','https://example.test/%0a','https://example.test/a b'])
    await denied('state_create',{stateHash:C.hash(returnTo),record:state({returnTo})});
});
test('connections roundtrip and update through the unchanged adapter',async()=>{
  const r=connection({...P,agentId:'roundtrip'});await repo.saveConnection(r.key,r);assert.deepEqual(await repo.getConnection(r.key),r);
  const next={...r,scope:'meeting:read user:read',updatedAtMs:3000};await repo.saveConnection(r.key,next);
  assert.deepEqual(await repo.getConnection(r.key),next);
});
test('connection keys isolate tenant user and agent identities',async()=>{
  const rows=[connection({...P,agentId:'isolation'}),connection({...P,agentId:'isolation',tenantId:'other_tenant'}),
    connection({...P,agentId:'isolation',userId:V}),connection({...P,agentId:'other-agent'})];
  for(const [i,r] of rows.entries()){r.scope='scope-'+i;await repo.saveConnection(r.key,r);}
  for(const r of rows)assert.deepEqual(await repo.getConnection(r.key),r);
});
test('noncanonical and mismatched connection bindings are rejected',async()=>{
  const r=connection({...P,agentId:'bad-binding'});
  await denied('connection_save',{key:r.key,record:{...r,agentId:'different'}});
  await denied('connection_get',{key:JSON.stringify(JSON.parse(r.key),null,1)});
  await denied('connection_get',{key:'[null,null,null]'});
});
test('token envelope rejects plaintext extra fields malformed base64 and wrong algorithm',async()=>{
  const r=connection({...P,agentId:'envelope'});
  for(const encryptedTokens of [{...r.encryptedTokens,access_token:'synthetic'}, {...r.encryptedTokens,version:1},
    {...r.encryptedTokens,algorithm:'none'}, {...r.encryptedTokens,iv:'abc='},
    {...r.encryptedTokens,tag:'A'}, {...r.encryptedTokens,ciphertext:''}])
    await denied('connection_save',{key:r.key,record:{...r,encryptedTokens}});
});
test('connection deletion is scoped and idempotent',async()=>{
  const r=connection({...P,agentId:'delete'});await repo.saveConnection(r.key,r);
  assert.equal(await repo.deleteConnection(r.key),true);assert.equal(await repo.deleteConnection(r.key),false);
  assert.equal(await repo.getConnection(r.key),null);
});
test('provider deauthorization matches both provider account and user',async()=>{
  const a=connection({...P,agentId:'deauth-1'},{zoomAccountId:'deauth-account',zoomUserId:'deauth-user'});
  const b=connection({...P,agentId:'deauth-2'},{zoomAccountId:'deauth-account',zoomUserId:'other-user'});
  const c=connection({...P,agentId:'deauth-3'},{zoomAccountId:'other-account',zoomUserId:'deauth-user'});
  for(const r of [a,b,c])await repo.saveConnection(r.key,r);
  assert.equal(await repo.deleteConnectionsByZoomIdentity({zoomAccountId:a.zoomAccountId,zoomUserId:a.zoomUserId}),1);
  assert.equal(await repo.getConnection(a.key),null);assert.deepEqual(await repo.getConnection(b.key),b);assert.deepEqual(await repo.getConnection(c.key),c);
});
test('session metadata roundtrips without authorizing audio or transcripts',async()=>{
  const r=session('roundtrip');assert.equal(await repo.getRtmsSession(r.sessionKey),null);
  assert.deepEqual(await repo.upsertRtmsSession(r.sessionKey,r),r);assert.deepEqual(await repo.getRtmsSession(r.sessionKey),r);
  for(const flag of ['mediaConnected','transcriptCollected','audioInjected'])
    await denied('session_upsert',{key:r.sessionKey,record:{...r,[flag]:true}},'ZOOM_MEDIA_DISABLED');
});
test('session provider identity mismatch and payload additions are rejected',async()=>{
  const r=session('invalid');await denied('session_upsert',{key:C.hash('wrong'),record:r});
  await denied('session_upsert',{key:r.sessionKey,record:{...r,meetingUuid:'other'}});
  await denied('session_upsert',{key:r.sessionKey,record:{...r,transcript:'not allowed'}});
});
test('session rejects stale transitions and retains stopped as terminal',async()=>{
  const r=session('ordered');await repo.upsertRtmsSession(r.sessionKey,r);
  const later={...r,status:'interrupted',eventTs:2000};await repo.upsertRtmsSession(r.sessionKey,later);
  assert.deepEqual(await repo.upsertRtmsSession(r.sessionKey,{...r,eventTs:500}),later);
  const stop={...r,status:'stopped',eventTs:3000};await repo.upsertRtmsSession(r.sessionKey,stop);
  assert.deepEqual(await repo.upsertRtmsSession(r.sessionKey,{...r,eventTs:4000}),stop);
});
test('session key remains bound to the provider account',async()=>{
  const a=session('same','started',1000,'account-X'),b=session('same','started',1000,'account-Y');
  assert.notEqual(a.sessionKey,b.sessionKey);await repo.upsertRtmsSession(a.sessionKey,a);await repo.upsertRtmsSession(b.sessionKey,b);
  assert.deepEqual(await repo.getRtmsSession(a.sessionKey),a);assert.deepEqual(await repo.getRtmsSession(b.sessionKey),b);
});
test('webhook event is accepted once and duplicate has no effects',async()=>{
  const e=event('once');assert.deepEqual(await repo.applyWebhookEvent(e),{accepted:true,duplicate:false,deletedConnections:0});
  assert.deepEqual(await repo.applyWebhookEvent(e),{accepted:false,duplicate:true,deletedConnections:0});
});
test('concurrent webhook duplicates yield exactly one acceptance',async()=>{
  const e=event('parallel');const r=await Promise.all(Array.from({length:6},()=>rpc('event_apply',e)));
  assert.equal(r.filter(x=>x.accepted).length,1);assert.equal(r.filter(x=>x.duplicate).length,5);
});
test('reused event identity with another payload hash is rejected',async()=>{
  const e=event('conflict');await repo.applyWebhookEvent(e);
  await denied('event_apply',{...e,payloadHash:C.hash('different')},'ZOOM_EVENT_ID_CONFLICT');
});
test('event applies session metadata with matching event type and time',async()=>{
  const r=session('event');await repo.applyWebhookEvent(sessEvent('session',r));assert.deepEqual(await repo.getRtmsSession(r.sessionKey),r);
  await denied('event_apply',{...sessEvent('wrong-ts',r),eventTs:2000});
  await denied('event_apply',{...sessEvent('wrong-name',r),event:'app_deauthorized'});
});
test('invalid event mutation rolls back event reservation',async()=>{
  const e=event('bad-plan',{kind:'none',extra:1});await denied('event_apply',e);
  const n=await sql("select count(*) from k135z_b5b_private.events where event_id='"+e.eventId+"';",'k135z_local_admin');assert.equal(n,'0');
});
test('mutation failure rolls back dedup insertion and permits a corrected retry',async()=>{
  const r=session('forced-failure'),e=sessEvent('forced-failure',r);
  await sql("create function public.gate6a_fixture_reject() returns trigger language plpgsql as $$begin "+
    "if new.session_key='"+r.sessionKey+"' then raise exception 'LOCAL_FIXTURE_REJECTION'; end if; return new; end$$; "+
    "create trigger gate6a_reject before insert on k135z_b5b_private.sessions for each row execute function public.gate6a_fixture_reject();",'k135z_local_admin');
  try {await assert.rejects(()=>rpc('event_apply',e),/LOCAL_FIXTURE_REJECTION/);
    assert.equal(await sql("select count(*) from k135z_b5b_private.events where event_id='"+e.eventId+"';",'k135z_local_admin'),'0');
  } finally {await sql('drop trigger gate6a_reject on k135z_b5b_private.sessions;drop function public.gate6a_fixture_reject();','k135z_local_admin');}
  assert.equal((await repo.applyWebhookEvent(e)).accepted,true);
});
test('deauthorization webhook is atomic and duplicate cannot repeat deletion',async()=>{
  const r=connection({...P,agentId:'event-deauth'},{zoomAccountId:'event-account',zoomUserId:'event-user'});
  await repo.saveConnection(r.key,r);const e=event('deauth',{kind:'deauthorize',zoomAccountId:r.zoomAccountId,zoomUserId:r.zoomUserId},'app_deauthorized');
  assert.equal((await repo.applyWebhookEvent(e)).deletedConnections,1);
  await repo.saveConnection(r.key,r);assert.equal((await repo.applyWebhookEvent(e)).deletedConnections,0);
  assert.deepEqual(await repo.getConnection(r.key),r);
});
test('caller transaction rollback preserves atomic storage semantics',async()=>{
  const stateHash=C.hash('rollback');await sql('begin;select '+expression('state_create',{stateHash,record:state()})+';rollback;');
  assert.equal((await rpc('state_consume',{stateHash,nowMs:2000})).outcome,'invalid');
});
test('independent connections observe committed durable rows',async()=>{
  const r=connection({...P,agentId:'durability'});await repo.saveConnection(r.key,r);
  const second=new SupabaseZoomRepository({client:{async rpc(name,{operation,payload}){assert.equal(name,'k135z_b5b_storage_v1');return {data:await rpc(operation,payload),error:null};}}});
  assert.deepEqual(await second.getConnection(r.key),r);
});
test('backend RPC errors remain sanitized by the existing adapter',async()=>{
  await assert.rejects(()=>repo.saveOAuthState(C.hash('bad-fk-adapter'),state({userId:'33333333-3333-4333-8333-333333333333'})),
    e=>e.code==='ZOOM_STORAGE_UNAVAILABLE'&&!e.message.includes('foreign key'));
});
test('B1 tables still exist and the new metadata never populates B1 consent sessions',async()=>{
  const count=await sql("select count(*) from pg_class where relnamespace='public'::regnamespace and relkind='r' and "+
    "relname in ('korlix_zoom_oauth_states','korlix_zoom_connections','korlix_zoom_meeting_sessions','korlix_zoom_webhook_events','korlix_zoom_audit_events');",'k135z_local_admin');
  assert.equal(count,'5');assert.equal(await sql('select count(*) from public.korlix_zoom_meeting_sessions;','k135z_local_admin'),'0');
});
