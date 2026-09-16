'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../k135z_zoom/b5b_contract.cjs');
const {RPC, SupabaseZoomRepository, MemoryZoomRepository} = require('../k135z_zoom/b5b_repository.cjs');
const {EnvelopeCipher, ZoomTokenVault} = require('../k135z_zoom/zoom_token_vault.cjs');
const {ZoomOAuthService} = require('../k135z_zoom/zoom_oauth_service.cjs');
const {createK135zZoomDependencies, createK135zZoomHandlers, isEnterprisePrincipal} = require('../k135z_zoom/zoom_routes.cjs');
const {ZoomWebhookVerifier} = require('../k135z_zoom/zoom_webhook_verifier.cjs');
const WHO={tenantId:'tenant-1',userId:'11111111-1111-4111-8111-111111111111',agentId:'agent-1'};
const NOW=1800000000000, H='a'.repeat(64), KEY=C.identityKey(WHO), ORIGIN='https://app.korlix.test';
const STATE={...WHO,returnTo:ORIGIN+'/#/meeting-copilot',createdAtMs:NOW,expiresAtMs:NOW+600000};
function response() { return {statusCode:200,body:null,status(s){this.statusCode=s;return this;},json(v){this.body=v;return v;}}; }
function fixture(extra={}) {
  const repository=new MemoryZoomRepository(), cipher=new EnvelopeCipher(Buffer.alloc(32,7));
  const tokenVault=new ZoomTokenVault({repository,cipher,clock:()=>NOW});
  let calls=0;
  const transport={liveEnabled:false,async exchangeAuthorizationCode(){calls++;return {access_token:'fixture-access',refresh_token:'fixture-refresh',expires_in:3600,account_id:'zoom-account',user_id:'zoom-user',scope:'meeting:read'};}};
  const config={clientId:'fixture-client',clientSecret:'fixture-secret',redirectUri:'https://api.korlix.test/callback',allowedReturnOrigins:[ORIGIN]};
  const oauthService=new ZoomOAuthService({repository,tokenVault,transport,config,clock:()=>NOW,authorizeStoredIdentity:async()=>true,...extra});
  return {repository,cipher,tokenVault,transport,oauthService,config,calls:()=>calls};
}
async function connect(f, who=WHO) {
  const r=await f.oauthService.startAuthorization({principal:who,returnTo:STATE.returnTo});
  await f.oauthService.completeAuthorization({code:'fixture-code',state:new URL(r.authorizationUrl).searchParams.get('state')});
}
function event(kind='started',ts=NOW,extra={}) {return {body:{event:'meeting.rtms_'+kind,event_ts:ts,payload:{account_id:'zoom-account',object:{uuid:'meeting-one',rtms_stream_id:'stream-one'}},...extra}};}
function signed(body,verifier) {const rawBody=JSON.stringify(body),timestamp=String(NOW/1000);return {rawBody,headers:{'x-zm-request-timestamp':timestamp,'x-zm-signature':verifier.sign({timestamp,rawBody})}};}

test('B5B identity requires explicit tenant, UUID user and agent; no personal fallback',()=>{
  assert.deepEqual(C.identity(WHO),WHO);
  assert.deepEqual(C.identityFromKey(KEY),WHO);
  for(const v of [{}, {...WHO,tenantId:undefined},{...WHO,userId:'user-1'},{...WHO,agentId:undefined},{...WHO,userId:undefined,user_metadata:{sub:WHO.userId}},{...WHO,id:'other'}]) assert.throws(()=>C.identity(v));
  assert.notEqual(C.identityKey({...WHO,agentId:'agent-2'}),KEY);
  assert.notEqual(C.identityKey({...WHO,tenantId:'tenant-2'}),KEY);
});
test('B5B return allowlist rejects empty, malformed, non-HTTPS and credentials',()=>{
  assert.equal(C.normalizeReturnTo(STATE.returnTo,[ORIGIN]),STATE.returnTo);
  assert.equal(C.normalizeReturnTo(null,[]),null);
  for(const value of ['https://evil.test/','http://127.0.0.1/','ftp://127.0.0.1/','https://name:secret@app.korlix.test/','//app.korlix.test/','https://app.korlix.test\\@evil.test/',' https://app.korlix.test/','https://app.korlix.test/%0d%0aLocation:evil']) assert.throws(()=>C.normalizeReturnTo(value,[ORIGIN]));
  for(const list of [[],['bad'],[ORIGIN+'/unexpected'],[ORIGIN+'?q=1'],['https://u:p@app.korlix.test']]) assert.throws(()=>C.normalizeReturnTo(STATE.returnTo,list));
});
test('B5B default dependencies reject forged request identity and Enterprise claims',async()=>{
  const d=createK135zZoomDependencies({env:{NODE_ENV:'production',KORLIX_K135Z_ZOOM_ALLOW_EPHEMERAL_STORE:'true',KORLIX_K135Z_ZOOM_LIVE_TRANSPORT_ENABLED:'true'}});
  const req={user:{...WHO,tier:'enterprise',app_metadata:{tier:'enterprise'}},korlixUser:WHO};
  assert.equal(await d.authenticateRequest(req),null); assert.equal(await d.resolveEnterprise(req.user,req),false);
  assert.equal(await d.authorizeAgent(WHO,req),false); assert.equal(d.transport.liveEnabled,false);
  await assert.rejects(d.repository.getConnection(KEY),{code:'ZOOM_PERSISTENT_STORAGE_NOT_CONFIGURED'});
  const res=response();await createK135zZoomHandlers(d).start(req,res);assert.equal(res.statusCode,401);
});
test('B5B Enterprise helper ignores user metadata and arbitrary tier fragments',()=>{
  for(const p of [{tier:'enterprise'},{user_metadata:{tier:'enterprise'}},{app_metadata:{tier:'not_enterprise'}},{app_metadata:{tier:'enterprise_cancelled'}}]) assert.equal(isEnterprisePrincipal(p),false);
  assert.equal(isEnterprisePrincipal({app_metadata:{tier:'enterprise'}}),true);
});
test('B5B handler requires strict true entitlement and agent ownership before state creation',async()=>{
  for(const entitlement of [true,1,'true']) {
    const f=fixture(),res=response();
    const h=createK135zZoomHandlers({...f,authenticateRequest:async()=>WHO,resolveEnterprise:async()=>entitlement,authorizeAgent:async()=>false});
    await h.start({query:{}},res);assert.equal(res.statusCode,403);assert.equal(f.repository.oauthStates.size,0);
  }
  const f=fixture(),res=response(); const h=createK135zZoomHandlers({...f,authenticateRequest:async()=>WHO,resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
  await h.start({query:{return_to:STATE.returnTo}},res);assert.equal(res.statusCode,200);assert.equal(f.repository.oauthStates.size,1);
});
test('B5B callback rechecks stored authority before token exchange',async()=>{
  const f=fixture({authorizeStoredIdentity:async()=>false});
  const r=await f.oauthService.startAuthorization({principal:WHO});const state=new URL(r.authorizationUrl).searchParams.get('state');
  await assert.rejects(f.oauthService.completeAuthorization({code:'x',state}),{code:'ZOOM_STORED_AUTHORIZATION_DENIED'});
  assert.equal(f.calls(),0);assert.equal(f.repository.connections.size,0);
});
test('B5B callback revalidates a changed return allowlist before exchange',async()=>{
  const f=fixture(),r=await f.oauthService.startAuthorization({principal:WHO,returnTo:STATE.returnTo});
  f.oauthService.config.allowedReturnOrigins=[];
  await assert.rejects(f.oauthService.completeAuthorization({code:'x',state:new URL(r.authorizationUrl).searchParams.get('state')}));assert.equal(f.calls(),0);
});
test('B5B OAuth state one-time, boundary-expired and cross-instance adapter contract',async()=>{
  const r=new MemoryZoomRepository();await r.saveOAuthState(H,STATE);
  const results=await Promise.allSettled([r.consumeOAuthState(H,NOW),r.consumeOAuthState(H,NOW)]);
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(results.find(x=>x.status==='rejected').reason.code,'ZOOM_OAUTH_STATE_REPLAYED');
  await r.saveOAuthState('b'.repeat(64),STATE);
  await assert.rejects(r.consumeOAuthState('b'.repeat(64),STATE.expiresAtMs),{code:'ZOOM_OAUTH_STATE_EXPIRED'});
  await assert.rejects(r.saveOAuthState('c'.repeat(64),{...STATE,expiresAtMs:NOW+600001}));
});
test('B5B ciphertext is bound to tenant/user/agent and rejects envelope swapping',async()=>{
  const f=fixture();await connect(f); const r=await f.repository.getConnection(KEY);
  assert.equal(r.encryptedTokens.version,2);assert.equal(f.cipher.decrypt(r.encryptedTokens,KEY).accessToken,'fixture-access');
  assert.throws(()=>f.cipher.decrypt(r.encryptedTokens,C.identityKey({...WHO,agentId:'other'})),{code:'ZOOM_TOKEN_DECRYPTION_FAILED'});
  assert.throws(()=>f.cipher.decrypt(r.encryptedTokens));
  assert.throws(()=>new EnvelopeCipher('short'));
  const status=await f.oauthService.getStatus(WHO);assert.equal(status.connected,true);
  for(const value of ['fixture-access','fixture-refresh','ciphertext']) assert.equal(JSON.stringify(status).includes(value),false);
  await assert.rejects(f.repository.saveConnection(KEY,{...r,accessToken:'forbidden'}));
  await assert.rejects(f.repository.saveConnection(KEY,{...r,agentId:'other'}));
});
test('B5B duplicate signed webhook does not apply a second mutation',async()=>{
  const f=fixture(),verifier=new ZoomWebhookVerifier({secret:'fixture-webhook',clock:()=>NOW});
  const handlers=createK135zZoomHandlers({...f,webhookVerifier:verifier});
  const req=signed(event().body,verifier),a=response(),b=response();
  await handlers.webhook(req,a);await handlers.webhook(req,b);
  assert.equal(a.statusCode,200);assert.equal(a.body.accepted,true);assert.equal(b.body.duplicate,true);assert.equal(b.body.accepted,false);
  assert.equal(f.repository.webhookEvents.size,1);assert.equal(f.repository.rtmsSessions.size,1);
});
test('B5B signature failure has no event or session effect',async()=>{
  const f=fixture(),verifier=new ZoomWebhookVerifier({secret:'fixture-webhook',clock:()=>NOW});
  const req=signed(event().body,verifier);req.rawBody+=' ';const res=response();
  await createK135zZoomHandlers({...f,webhookVerifier:verifier}).webhook(req,res);
  assert.equal(res.statusCode,401);assert.equal(f.repository.webhookEvents.size,0);assert.equal(f.repository.rtmsSessions.size,0);
});
test('B5B equivalent JSON order deduplicates; provider ID payload conflict is rejected',async()=>{
  const e=event(),r=new MemoryZoomRepository(); const a=C.eventPlan(e),b=C.eventPlan({body:{payload:e.body.payload,event_ts:NOW,event:e.body.event}});
  assert.equal(a.eventId,b.eventId);await r.applyWebhookEvent(a);assert.equal((await r.applyWebhookEvent(b)).duplicate,true);
  const x=C.eventPlan(event('started',NOW,{event_id:'same'}));await r.applyWebhookEvent(x);
  await assert.rejects(r.applyWebhookEvent(C.eventPlan(event('started',NOW+1,{event_id:'same'}))),{code:'ZOOM_EVENT_ID_CONFLICT'});
});
test('B5B stopped session cannot be revived by delayed or newer started event',async()=>{
  const r=new MemoryZoomRepository(),s=C.eventPlan(event('stopped',NOW+100));
  await r.applyWebhookEvent(s);await r.applyWebhookEvent(C.eventPlan(event('started',NOW)));
  await r.applyWebhookEvent(C.eventPlan(event('started',NOW+200)));
  assert.equal((await r.getRtmsSession(s.mutation.key)).status,'stopped');
});
test('B5B session key binds Zoom account and event metadata excludes media credentials',()=>{
  const a=event(),b=event();b.body.payload.account_id='different';
  assert.notEqual(C.eventPlan(a).mutation.key,C.eventPlan(b).mutation.key);
  a.body.payload.object.server_urls=['wss://fixture-secret'];a.body.payload.object.transcript='private';
  const p=C.eventPlan(a);assert.equal(JSON.stringify(p).includes('fixture-secret'),false);assert.equal(JSON.stringify(p).includes('private'),false);
  const r=p.mutation.record;assert.equal(r.mediaConnected,false);assert.equal(r.transcriptCollected,false);assert.equal(r.audioInjected,false);
  assert.throws(()=>C.validatePlan({...p,mutation:{...p.mutation,record:{...r,audioInjected:true}}}));
});
test('B5B deauthorization matches account AND user and duplicate does not delete a reconnection',async()=>{
  const f=fixture();await connect(f);const original=await f.repository.getConnection(KEY);
  const other={...WHO,agentId:'other'},otherKey=C.identityKey(other);
  await f.repository.saveConnection(otherKey,{...original,...other,key:otherKey,zoomUserId:'different'});
  const p=C.eventPlan({body:{event:'app_deauthorized',event_ts:NOW,payload:{account_id:'zoom-account',user_id:'zoom-user'}}});
  const a=await f.repository.applyWebhookEvent(p);assert.equal(a.deletedConnections,1);assert.ok(await f.repository.getConnection(otherKey));
  await f.repository.saveConnection(KEY,original);const b=await f.repository.applyWebhookEvent(p);assert.equal(b.duplicate,true);assert.ok(await f.repository.getConnection(KEY));
  assert.throws(()=>C.eventPlan({body:{event:'app_deauthorized',event_ts:NOW,payload:{account_id:'zoom-account'}}}));
});
test('B5B RPC adapter sends validated exact operations and persists through injected shared fake',async()=>{
  const stored=new Map(),calls=[];
  const client={async rpc(name,args){calls.push([name,structuredClone(args)]);assert.equal(name,RPC);
    switch(args.operation){
      case 'state_create':assert.equal(args.payload.record.agentId,WHO.agentId);stored.set(args.payload.stateHash,structuredClone(args.payload.record));return {data:true,error:null};
      case 'state_consume': {const record=stored.get(args.payload.stateHash);stored.delete(args.payload.stateHash);return {data:record?{outcome:'ok',record}:{outcome:'replayed'},error:null};}
      case 'connection_get':return {data:null,error:null};
      case 'event_apply':return {data:{accepted:true,duplicate:false,deletedConnections:0},error:null};
      default:throw Error('unexpected operation');
    }
  }};
  const a=new SupabaseZoomRepository({client});await a.saveOAuthState(H,STATE);
  const b=new SupabaseZoomRepository({client});assert.deepEqual(await b.consumeOAuthState(H,NOW),STATE);
  await assert.rejects(a.consumeOAuthState(H,NOW),{code:'ZOOM_OAUTH_STATE_REPLAYED'});
  assert.equal(await b.getConnection(KEY),null);await b.applyWebhookEvent(C.eventPlan(event()));
  assert.equal(calls[0][1].operation,'state_create');assert.deepEqual(calls[1][1].payload,{stateHash:H,nowMs:NOW});
  assert.equal(calls.length,5);
});
test('B5B RPC failures are sanitized and never silently fall back or retry',async()=>{
  let calls=0;const r=new SupabaseZoomRepository({client:{async rpc(){calls++;return {error:{message:'Bearer secret'},data:null};}}});
  await assert.rejects(r.getConnection(KEY),e=>e.code==='ZOOM_STORAGE_UNAVAILABLE'&&!String(e).includes('secret'));assert.equal(calls,1);
  await assert.rejects(r.saveOAuthState(H,{...STATE,access_token:'secret'}));assert.equal(calls,1);
  const bad=new SupabaseZoomRepository({client:{async rpc(){return {data:{...STATE,userId:'other'}};}}});
  await assert.rejects(bad.getConnection(KEY));
});
test('B5B RPC covers encrypted connection operations, metadata session and deauthorization contract',async()=>{
  const f=fixture();await connect(f);const record=await f.repository.getConnection(KEY),p=C.eventPlan(event()),calls=[];
  const client={async rpc(name,args){assert.equal(name,RPC);calls.push(args);
    const values={connection_save:true,connection_get:record,connection_delete:true,connection_deauthorize:2,session_upsert:p.mutation.record,session_get:p.mutation.record,event_apply:{accepted:false,duplicate:true,deletedConnections:0}};
    assert.ok(Object.hasOwn(values,args.operation));return {data:values[args.operation]};}};
  const r=new SupabaseZoomRepository({client});await r.saveConnection(KEY,record);assert.deepEqual(await r.getConnection(KEY),record);
  assert.equal(await r.deleteConnection(KEY),true);assert.equal(await r.deleteConnectionsByZoomIdentity({zoomAccountId:'a',zoomUserId:'b'}),2);
  assert.deepEqual(calls.at(-1).payload,{zoomAccountId:'a',zoomUserId:'b'});
  assert.deepEqual(await r.upsertRtmsSession(p.mutation.key,p.mutation.record),p.mutation.record);
  assert.deepEqual(await r.getRtmsSession(p.mutation.key),p.mutation.record);
  assert.equal(await r.recordWebhookEvent(p.eventId,{event:p.event,eventTs:p.eventTs,payloadHash:p.payloadHash}),false);
  assert.equal(JSON.stringify(calls).includes('fixture-access'),false);assert.equal(JSON.stringify(calls).includes('fixture-refresh'),false);
});
