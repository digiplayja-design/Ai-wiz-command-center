'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const path=require('node:path'),vm=require('node:vm'),{pathToFileURL}=require('node:url');
const C=require('../k135z_zoom/b5b_contract.cjs'),R=require('../k135z_zoom/b5b_repository.cjs');
const V=require('../k135z_zoom/zoom_token_vault.cjs'),Z=require('../k135z_zoom/zoom_routes.cjs');
// Read the entry point; do not boot the application or connect to a provider.
const source=fs.readFileSync(path.join(__dirname,'../server.js'),'utf8');
const begin='// K135Z_GATE5_TRUSTED_WIRING_BEGIN',end='// K135Z_GATE5_TRUSTED_WIRING_END';
assert.equal(source.split(begin).length,2);assert.equal(source.split(end).length,2);
const factory=vm.runInNewContext(source.split(begin)[1].split(end)[0]+'\ncreateK135zGate5Wiring;',
  {k135zGate5Contract:C,k135zGate5Repository:R,k135zGate5Vault:V});
const U='11111111-1111-4111-8111-111111111111',OTHER='22222222-2222-4222-8222-222222222222';
const P={tenantId:U,userId:U,agentId:'nova'};
function fixture(o={}) {
  const calls=[];
  const database={from(table){const eq=[];const q={select(columns){calls.push(['select',table,columns]);return q;},
    eq(k,v){eq.push([k,v]);return q;},async maybeSingle(){calls.push(['query',table,eq]);
      return o.databaseError?{data:null,error:{message:'secret-database-detail'}}:
       {data:{id:o.wrongProfile?OTHER:U,tier:o.tier??'enterprise'},error:null};}};return q;},
    async rpc(operation,args){calls.push(['rpc',operation,args]);return o.rpcError?
      {data:null,error:{message:'secret-rpc-detail'}}:{data:null,error:null};}};
  const wiring=factory({database:o.noDatabase?null:database,
    authenticateUser:async req=>{calls.push(['authenticate']);if(o.noUser)throw Error('secret-auth-detail');
      return {id:U,user_metadata:{tier:'enterprise',tenantId:OTHER}};},
    loadAgentProfile:async a=>{calls.push(['agent',a.userId,a.agentId]);if(o.agentError)throw Error('secret-agent-detail');
      return o.noAgent?null:{id:o.otherAgent?'other':a.agentId,active:!o.inactive};}});
  return {wiring,calls,database,req:o.req||{query:{agent_id:'nova'},headers:{}}};
}
async function principal(f){return f.wiring.authenticateRequest(f.req);}
async function status(f){const deps=Z.createK135zZoomDependencies({...f.wiring,env:{NODE_ENV:'test'}});
  const h=Z.createK135zZoomHandlers(deps);const r={status(n){this.statusCode=n;return this;},
    json(x){this.body=x;return this;},set(){return this;},setHeader(){}};
  await h.status(f.req,r);return r;}
test('Gate5 ESM interop and single Zoom registration before the API fallback',async()=>{
  assert(source.includes('import k135zGate5Routes from "./k135z_zoom/zoom_routes.cjs";'));
  const m=await import(pathToFileURL(path.join(__dirname,'../k135z_zoom/zoom_routes.cjs')).href);
  assert.equal(typeof m.default.registerK135zZoomRoutes,'function');
  assert.equal((source.match(/registerK135zZoomRoutes\(app,/g)||[]).length,1);
  assert(source.indexOf('registerK135zZoomRoutes(app,')<source.lastIndexOf('app.use("/api",'));
});
test('Gate5 retains the K136S import and mount',()=>{
  assert.equal((source.match(/import k136sLearningMount from/g)||[]).length,1);
  assert.equal((source.match(/k136sLearningMount\.mountK136S\(app,/g)||[]).length,1);
  assert(source.indexOf('k136sLearningMount.mountK136S(app,')<source.lastIndexOf('app.use("/api",'));
});
test('Gate5 verified user binds account and selected agent',async()=>{const f=fixture(),p=await principal(f);
  assert.equal(JSON.stringify(p),JSON.stringify(P));assert.equal(await f.wiring.resolveEnterprise(p,f.req),true);
  assert.equal(await f.wiring.authorizeAgent(C.identity(p),f.req),true);
  assert(f.calls.some(c=>c[0]==='agent'&&c[1]===U&&c[2]==='nova'));});
test('Gate5 forged request user cannot replace verified authentication',async()=>{
  const f=fixture({noUser:true,req:{query:{agent_id:'nova'},headers:{},user:{id:U,tier:'enterprise'}}});
  await assert.rejects(principal(f),e=>e.status===401);assert.equal(f.calls.filter(x=>x[0]==='query').length,0);});
test('Gate5 requires explicit agent selection',async()=>{await assert.rejects(principal(fixture({req:{query:{},headers:{}}})),e=>e.status===400);});
test('Gate5 rejects conflicting repeated and whitespace agent selectors',async()=>{
  for(const query of [{agent_id:'nova',agentId:'other'},{agent_id:['nova','nova']},{agent_id:' nova'}])
    await assert.rejects(principal(fixture({req:{query,headers:{}}})),e=>e.status===400);});
test('Gate5 rejects caller-selected foreign accounts',async()=>{
  for(const req of [{query:{agent_id:'nova',tenantId:OTHER},headers:{}},
    {query:{agent_id:'nova'},body:{user_id:OTHER},headers:{}},
    {query:{agent_id:'nova'},headers:{'x-korlix-tenant-id':OTHER}}])
    await assert.rejects(principal(fixture({req})),e=>e.status===403);});
test('Gate5 requires provenance for authorization callbacks',async()=>{const f=fixture();
  assert.equal(await f.wiring.resolveEnterprise(P,f.req),false);assert.equal(await f.wiring.authorizeAgent(P,f.req),false);});
test('Gate5 user metadata cannot grant Enterprise',async()=>{for(const tier of ['basic','pro','ultra','not_enterprise','enterprise_trial']){
  const f=fixture({tier}),p=await principal(f);assert.equal(await f.wiring.resolveEnterprise(p,f.req),false);}});
test('Gate5 rejects a mismatched database profile',async()=>{const f=fixture({wrongProfile:true}),p=await principal(f);assert.equal(await f.wiring.resolveEnterprise(p,f.req),false);});
test('Gate5 rejects missing inactive and mismatched agents',async()=>{for(const o of [{noAgent:true},{inactive:true},{otherAgent:true}]){
  const f=fixture(o),p=await principal(f);assert.equal(await f.wiring.authorizeAgent(p,f.req),false);}});
test('Gate5 stored identities recheck entitlement and agent ownership',async()=>{
  assert.equal(await fixture().wiring.authorizeStoredIdentity(P),true);
  assert.equal(await fixture({tier:'basic'}).wiring.authorizeStoredIdentity(P),false);
  assert.equal(await fixture({noAgent:true}).wiring.authorizeStoredIdentity(P),false);
  assert.equal(await fixture().wiring.authorizeStoredIdentity({...P,tenantId:OTHER}),false);
  assert.equal(await fixture().wiring.authorizeStoredIdentity({...P,userId:'invalid'}),false);});
test('Gate5 sanitizes storage and agent failures',async()=>{for(const o of [{noDatabase:true},{databaseError:true},{agentError:true}]){
  const f=fixture(o),p=await principal(f);await assert.rejects(o.agentError?()=>f.wiring.authorizeAgent(p,f.req):()=>f.wiring.resolveEnterprise(p,f.req),
    e=>e.status===503&&!e.message.includes('secret-'));}});
test('Gate5 uses durable adapter or unavailable storage, never memory fallback',()=>{
  assert.equal(fixture().wiring.repository.kind,'supabase-b5b-v1');assert(fixture({noDatabase:true}).wiring.repository instanceof V.UnavailableZoomRepository);});
test('Gate5 actual status handler reaches injected RPC',async()=>{const f=fixture(),r=await status(f);assert.equal(r.statusCode,200);
  assert(f.calls.some(x=>x[0]==='rpc'&&x[1]==='k135z_b5b_storage_v1'&&x[2].operation==='connection_get'));});
test('Gate5 actual handler denies missing auth and forged authority before RPC',async()=>{
  for(const [o,n] of [[{noUser:true},401],[{tier:'basic'},403],[{noAgent:true},403]]){const f=fixture(o),r=await status(f);
    assert.equal(r.statusCode,n);assert.equal(f.calls.filter(x=>x[0]==='rpc').length,0);assert(!JSON.stringify(r.body).includes('secret-'));}});
test('Gate5 actual handler reports unavailable RPC without secret details',async()=>{const r=await status(fixture({rpcError:true}));assert.equal(r.statusCode,503);assert(!JSON.stringify(r.body).includes('secret-rpc-detail'));});
test('Gate5 actual agent loader filters verified user selected agent and active records',async()=>{
  const m=await import(pathToFileURL(path.join(__dirname,'../korlix_live_convo_agents.js')).href),seen=[];
  const q={select(){return q;},eq(k,v){seen.push([k,v]);return q;},is(k,v){seen.push([k,v]);return q;},async maybeSingle(){return {data:null,error:null};}};
  await m.korlixAgentLoadProfileV1({client:{from(){return q;}},userId:U,agentId:'nova'});
  assert(seen.some(x=>x[0]==='user_id'&&x[1]===U));assert(seen.some(x=>x[0]==='agent_id'&&x[1]==='nova'));assert(seen.some(x=>x[0]==='deleted_at'&&x[1]===null));
});

// K135Z_GATE6D_COMMAND_TESTS_BEGIN
const { K135zWorkspaceCommandService } = require('../k135z_zoom/zoom_rtms_session_manager.cjs');
const NC = require('../k135z_copilot_notes/contract.cjs');
const context6d = Object.freeze({ ...P, sessionId:'session-6d', meetingUuid:'meeting-6d',
  streamId:'stream-6d', generation:7 });
function cancel6d(initial=false) {
  let cancelled=initial;
  const listeners=new Set();
  return { isCancelled:()=>cancelled, subscribe(fn){listeners.add(fn);return ()=>listeners.delete(fn);},
    cancel(){cancelled=true;for(const fn of [...listeners])fn();}, count:()=>listeners.size };
}
function request6d(action='start',changes={}) {
  return {schemaVersion:1, operation:{requestId:'request-6d',localEpoch:2,operationNumber:3},
    action, expectedContext:context6d, expectedSnapshotRevision:8, ...changes};
}
function reply6d(request,changes={}) {
  return {schemaVersion:1, operation:request.operation, action:request.action,
    outcome:{kind:'acknowledged',snapshot:{schemaVersion:1,context:request.expectedContext,
      revision:9,state:({start:'listening',pause:'paused',stop:'stopped',refresh:'ready'})[request.action],
      hostAuthorized:true,listeningAuthorized:true,activeSeconds:0,capabilities:{canSpeak:false},...changes}}};
}
function fixture6d(options={}) {
  const f=fixture(options),seen=[];
  const adapter={async resolveContext(input){seen.push(['resolve',input]);return options.context??context6d;},
    async requestAtomic(input){seen.push(['atomic',input]);return reply6d(input.request,options.snapshot);},...options.adapter};
  const service=new K135zWorkspaceCommandService({...f.wiring,adapter,timeoutMs:options.timeoutMs??1000,...options.service});
  return {...f,seen,adapter,service,run:(request=request6d(),token=cancel6d())=>service.request(f.req,request,token)};
}
function failure6d(reply,code,remote='notRequested') {
  assert.equal(reply.outcome.kind,'failed');assert.equal(reply.outcome.error.code,code);
  assert.equal(reply.outcome.error.remoteOutcome,remote);assert.equal(reply.outcome.error.automaticRetry,false);
  assert(!JSON.stringify(reply).includes('secret-'));
}
test('Gate6D default production wiring cannot start capture even with forged claims and enable flags',async()=>{
  const d=Z.createK135zZoomDependencies({env:{NODE_ENV:'production',KORLIX_K135Z_ZOOM_LIVE_TRANSPORT_ENABLED:'true'}});
  const result=await d.workspaceCommands.request({user:{...P,tier:'enterprise'}},request6d(),cancel6d());
  failure6d(result,'DENIED');assert.equal(d.transport.liveEnabled,false);
});
test('Gate6D valid current authority still requires an explicitly injected provider adapter',async()=>{
  const f=fixture6d({service:{adapter:null}});failure6d(await f.run(),'UNAVAILABLE');assert.equal(f.seen.length,0);
});
test('Gate6D shared dependency factory carries verified Gate5 authority into the command service',async()=>{
  const f=fixture6d(),d=Z.createK135zZoomDependencies({...f.wiring,env:{NODE_ENV:'test'},workspaceCommandAdapter:f.adapter});
  const result=await d.workspaceCommands.request(f.req,request6d(),cancel6d());
  assert.equal(result.outcome.snapshot.state,'listening');assert.equal(f.seen[1][0],'atomic');
});
test('Gate6D denies expired auth, insufficient tier and absent or inactive agents before the provider',async()=>{
  for(const options of [{noUser:true},{tier:'pro'},{noAgent:true},{inactive:true},{databaseError:true},{agentError:true}]){
    const f=fixture6d(options);failure6d(await f.run(),'DENIED');assert.equal(f.seen.length,0);
  }
});
test('Gate6D entitlement and ownership must be strict true',async()=>{
  for(const name of ['resolveEnterprise','authorizeAgent'])for(const value of [1,'true',false]){
    const f=fixture6d({service:{[name]:async()=>value}});failure6d(await f.run(),'DENIED');assert.equal(f.seen.length,0);
  }
});
test('Gate6D rejects caller-selected foreign tenant user or agent before resolving a session',async()=>{
  for(const key of ['tenantId','userId','agentId']){
    const f=fixture6d();failure6d(await f.run(request6d('start',{expectedContext:{...context6d,[key]:'foreign'}})),'BINDING_MISMATCH');
    assert.equal(f.seen.length,0);
  }
});
test('Gate6D requires exact server context including generation meeting stream and session',async()=>{
  for(const key of ['generation','sessionId','meetingUuid','streamId']){
    const f=fixture6d({context:{...context6d,[key]:key==='generation'?8:'foreign'}});
    failure6d(await f.run(),'BINDING_MISMATCH');assert.equal(f.seen.length,1);
  }
});
test('Gate6D malformed or unavailable server bindings fail before dispatch without fabricated context',async()=>{
  for(const value of [null,{}, {...context6d,generation:'7'}, {...context6d,extra:true}]){
    const f=fixture6d({adapter:{resolveContext:async()=>value}});failure6d(await f.run(),'PROTOCOL_ERROR');
    assert.equal(f.seen.filter(x=>x[0]==='atomic').length,0);
  }
  const f=fixture6d({adapter:{resolveContext:async()=>{throw Error('secret-provider');}}});
  failure6d(await f.run(),'UNAVAILABLE');
});
test('Gate6D all four commands preserve one operation domain and the exact expected revision',async()=>{
  const f=fixture6d();
  for(const action of ['refresh','start','pause','stop']){
    const request=request6d(action),token=cancel6d(),result=await f.run(request,token);
    assert.deepEqual(result.operation,request.operation);assert.equal(result.action,action);
    const sent=f.seen.at(-1)[1];assert.deepEqual(sent.request,request);assert.deepEqual(sent.principal,P);
    assert(Object.isFrozen(sent.request.expectedContext));assert.equal(token.count(),0);
    assert.equal(sent.cancellation.isCancelled(),true);
  }
});
test('Gate6D initial refresh may use null revision but mutations may not',async()=>{
  const f=fixture6d();assert.equal((await f.run(request6d('refresh',{expectedSnapshotRevision:null}))).outcome.kind,'acknowledged');
  for(const action of ['start','pause','stop'])await assert.rejects(f.run(request6d(action,{expectedSnapshotRevision:null})),{code:'K135Z_WORKSPACE_REQUEST_INVALID'});
});
test('Gate6D rejects malformed or oversized requests before authentication',async()=>{
  for(const request of [{}, {...request6d(),extra:true},request6d('start',{operation:{requestId:'x'.repeat(33000),localEpoch:0,operationNumber:0}})]){
    const f=fixture6d();await assert.rejects(f.run(request),{code:'K135Z_WORKSPACE_REQUEST_INVALID'});assert.equal(f.calls.length,0);
  }
});
test('Gate6D cannot infer authority from an unsigned body or a metadata-only RTMS event',async()=>{
  const f=fixture6d({adapter:{resolveContext:async()=>({status:'started',mediaConnected:false,transcriptCollected:false})}});
  failure6d(await f.run(),'PROTOCOL_ERROR');assert.equal(f.seen.filter(x=>x[0]==='atomic').length,0);
});
test('Gate6D first Start alone may adopt a stream while retaining every other binding field',async()=>{
  const context={...context6d,streamId:null};
  for(const action of ['start','refresh','pause','stop']){
    const f=fixture6d({context,snapshot:{context:context6d}}),result=await f.run(request6d(action,{expectedContext:context}));
    if(action==='start')assert.equal(result.outcome.snapshot.context.streamId,'stream-6d');
    else failure6d(result,'BINDING_MISMATCH','unknown');
  }
});
test('Gate6D adopted streams cannot switch and server generations cannot be invented in replies',async()=>{
  for(const changes of [{streamId:'other'},{generation:8},{sessionId:'other'},{meetingUuid:'other'},{agentId:'other'}]){
    const f=fixture6d({snapshot:{context:{...context6d,...changes}}});failure6d(await f.run(),'BINDING_MISMATCH','unknown');
  }
});
test('Gate6D Start acknowledgment requires listening host permission and listening permission',async()=>{
  for(const snapshot of [{state:'ready'},{hostAuthorized:false},{listeningAuthorized:false},{context:{...context6d,streamId:null}}]){
    const f=fixture6d({snapshot}),r=await f.run();assert.equal(r.outcome.kind,'failed');assert.equal(r.outcome.error.remoteOutcome,'unknown');
  }
});
test('Gate6D wrong acknowledgment state or stale revision is never accepted',async()=>{
  for(const action of ['start','pause','stop'])for(const snapshot of [{state:'ready'},{revision:8},{revision:7}]){
    failure6d(await fixture6d({snapshot}).run(request6d(action)),'PROTOCOL_ERROR','unknown');
  }
  failure6d(await fixture6d({snapshot:{revision:7}}).run(request6d('refresh')),'PROTOCOL_ERROR','unknown');
  assert.equal((await fixture6d({snapshot:{revision:8}}).run(request6d('refresh'))).outcome.kind,'acknowledged');
});
test('Gate6D rejects wrong operation action unknown fields and speech capability in provider replies',async()=>{
  const changes=[r=>({...r,operation:{...r.operation,operationNumber:4}}),r=>({...r,action:'stop'}),
    r=>({...r,extra:true}),r=>({...r,outcome:{kind:'acknowledged',snapshot:{...r.outcome.snapshot,capabilities:{canSpeak:true}}}})];
  for(const change of changes){const f=fixture6d({adapter:{requestAtomic:async({request})=>change(reply6d(request))}});
    failure6d(await f.run(),'PROTOCOL_ERROR','unknown');}
});
test('Gate6D returns atomic provider conflicts intact and sanitized without retry or success fabrication',async()=>{
  let calls=0;const f=fixture6d({adapter:{requestAtomic:async({request})=>{calls++;return {
    schemaVersion:1,operation:request.operation,action:request.action,outcome:{kind:'failed',error:{code:'CONFLICT',message:'secret-store-detail',remoteOutcome:'rejected',automaticRetry:false}}};}}});
  failure6d(await f.run(request6d('stop')),'CONFLICT','rejected');assert.equal(calls,1);
});
test('Gate6D thrown provider outcomes remain unknown and never trigger an automatic retry',async()=>{
  let calls=0;const f=fixture6d({adapter:{requestAtomic:async()=>{calls++;throw Error('secret-transport');}}});
  failure6d(await f.run(request6d('stop')),'UNAVAILABLE','unknown');assert.equal(calls,1);
});
test('Gate6D already cancelled requests never authenticate or dispatch',async()=>{
  const f=fixture6d(),token=cancel6d(true);failure6d(await f.run(request6d(),token),'CANCELLED');
  assert.equal(f.calls.length,0);assert.equal(f.seen.length,0);assert.equal(token.count(),0);
});
test('Gate6D cancellation while resolving context prevents dispatch and ignores late resolution',async()=>{
  let resolve;const f=fixture6d({adapter:{resolveContext:()=>new Promise(r=>{resolve=r;})}}),token=cancel6d(),pending=f.run(request6d(),token);
  await new Promise(setImmediate);token.cancel();failure6d(await pending,'CANCELLED');resolve(context6d);
  await new Promise(setImmediate);assert.equal(f.seen.filter(x=>x[0]==='atomic').length,0);assert.equal(token.count(),0);
});
test('Gate6D cancellation after dispatch signals the adapter and ignores late acknowledgments',async()=>{
  let resolve,signal=0;const token=cancel6d(),f=fixture6d({adapter:{requestAtomic:({cancellation})=>{
    cancellation.subscribe(()=>{signal++;});return new Promise(r=>{resolve=r;});}}}),pending=f.run(request6d('stop'),token);
  await new Promise(setImmediate);token.cancel();const result=await pending;failure6d(result,'CANCELLED','unknown');
  resolve(reply6d(request6d('stop')));await new Promise(setImmediate);assert.equal(signal,1);assert.equal(token.count(),0);
  failure6d(result,'CANCELLED','unknown');
});
test('Gate6D timeouts distinguish undispatched from uncertain remote commands',async()=>{
  const waiting=()=>new Promise(()=>{});
  failure6d(await fixture6d({timeoutMs:5,adapter:{resolveContext:waiting}}).run(),'TIMEOUT');
  failure6d(await fixture6d({timeoutMs:5,adapter:{requestAtomic:waiting}}).run(request6d('stop')),'TIMEOUT','unknown');
});
test('Gate6D cancellation subscription failure and invalid tokens fail closed',async()=>{
  for(const token of [null,{}, {isCancelled:()=>false,subscribe:()=>undefined},
    {isCancelled:()=>{throw Error('secret-cancel');},subscribe:()=>()=>{}},
    {isCancelled:()=>0,subscribe:()=>()=>{}}]){
    const f=fixture6d();failure6d(await f.run(request6d(),token),'PROTOCOL_ERROR');assert.equal(f.calls.length,0);
  }
});
test('Gate6D synchronous cancellation on subscribe releases the returned subscription',async()=>{
  let released=0;const f=fixture6d(),token={isCancelled:()=>false,subscribe(fn){fn();return ()=>{released++;};}};
  failure6d(await f.run(request6d(),token),'CANCELLED');assert.equal(released,1);assert.equal(f.calls.length,0);
});
test('Gate6D requests are immutable copies and do not share caller correlation objects',async()=>{
  const request=request6d(),f=fixture6d(),pending=f.run(request);request.operation.operationNumber=999;
  const result=await pending;assert.equal(result.operation.operationNumber,3);assert.equal(f.seen[1][1].request.operation.operationNumber,3);
  assert(Object.isFrozen(result.outcome.snapshot));assert.equal(NC.control(result,'reply').schemaVersion,1);
});
test('Gate6D timeout bounds cannot disable the frozen deadline',()=>{
  for(const timeoutMs of [0,-1,15001,Infinity,'15'])assert.throws(()=>new K135zWorkspaceCommandService({timeoutMs}));
});
// K135Z_GATE6D_COMMAND_TESTS_END

// K135Z_GATE6E_ATOMIC_TESTS_BEGIN
const {K135zAtomicWorkspaceAdapter}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
function fixture6e(options={}) {
  const f=fixture(),calls=[];
  let record={snapshot:{schemaVersion:1,context:{...context6d,streamId:null},revision:8,
    state:'ready',hostAuthorized:true,listeningAuthorized:true,activeSeconds:options.activeSeconds??0,capabilities:{canSpeak:false}},
    version:0,pending:null,uncertain:false},queue=Promise.resolve(),operation=0,transactions=0;
  const authority={context:record.snapshot.context,viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true};
  const store={async read(){return structuredClone({record,authority});},transact(input,decide){
    const task=queue.then(()=>{
      transactions++;calls.push(['transaction',transactions]);
      const decision=decide(structuredClone({record,authority}));
      if(options.failCommit===transactions)throw Error('secret-store-commit');
      record=structuredClone(decision.record);authority.context=record.snapshot.context;
      if(options.afterCommit)options.afterCommit({record,authority,transactions});
      return structuredClone(decision);
    });queue=task.catch(()=>{});return task;
  }};
  const transport={async request(input){calls.push(['provider',input]);
    if(options.provider)return options.provider(input);
    return reply6d(input.request,{context:{...input.snapshot.context,streamId:input.snapshot.context.streamId??(input.request.action==='start'?'stream-6e':null)},
      revision:input.snapshot.revision+1,activeSeconds:input.snapshot.activeSeconds,
      hostAuthorized:authority.hostAuthorized,listeningAuthorized:authority.listeningAuthorized});
  }};
  const adapter=new K135zAtomicWorkspaceAdapter({store,transport});
  const service=new K135zWorkspaceCommandService({...f.wiring,adapter,timeoutMs:options.timeoutMs??1000});
  const make=(action='start',changes={})=>request6d(action,{expectedContext:record.snapshot.context,
    expectedSnapshotRevision:record.snapshot.revision,operation:{requestId:'atomic-'+(++operation),localEpoch:2,operationNumber:operation},...changes});
  return {...f,store,transport,adapter,service,calls,authority,make,get record(){return record;},
    run:(action='start',token=cancel6d())=>service.request(f.req,make(action),token)};
}
test('Gate6E requires explicit storage and transport without an offline fallback',()=>{
  for(const options of [undefined,{}, {store:{}}, {store:{read(){},transact(){}},transport:{}}])
    assert.throws(()=>new K135zAtomicWorkspaceAdapter(options));
  const d=Z.createK135zZoomDependencies({env:{NODE_ENV:'production',KORLIX_K135Z_ZOOM_LIVE_TRANSPORT_ENABLED:'true'}});
  assert.equal(d.workspaceCommands.adapter,null);assert.equal(d.transport.liveEnabled,false);
});
test('Gate6E dependency factory installs the adapter only from both explicit dependencies',async()=>{
  const f=fixture6e(),d=Z.createK135zZoomDependencies({...f.wiring,env:{NODE_ENV:'test'},workspaceCommandStore:f.store,workspaceCommandTransport:f.transport});
  assert(d.workspaceCommands.adapter instanceof K135zAtomicWorkspaceAdapter);
  assert.equal((await d.workspaceCommands.request(f.req,f.make(),cancel6d())).outcome.snapshot.state,'listening');
  const partial=Z.createK135zZoomDependencies({...f.wiring,env:{NODE_ENV:'test'},workspaceCommandStore:f.store});
  assert.equal(partial.workspaceCommands.adapter,null);
});
test('Gate6E Start adopts a stream only after durable reservation dispatch and completion',async()=>{
  const f=fixture6e(),reply=await f.run();
  assert.equal(reply.outcome.snapshot.context.streamId,'stream-6e');assert.equal(reply.outcome.snapshot.revision,9);
  assert.equal(f.record.version,3);assert.equal(f.record.pending,null);assert.equal(f.record.uncertain,false);
  assert.deepEqual(f.calls.map(x=>x[0]),['transaction','transaction','provider','transaction']);
});
test('Gate6E Pause and resume retain the stream and one mutation revision domain',async()=>{
  const f=fixture6e();await f.run();
  assert.equal((await f.run('pause')).outcome.snapshot.state,'paused');
  const reply=await f.run('start');assert.equal(reply.outcome.snapshot.state,'listening');
  assert.equal(reply.outcome.snapshot.context.streamId,'stream-6e');assert.equal(reply.outcome.snapshot.revision,11);
  assert.equal(f.record.version,9);
});
test('Gate6E acknowledged Stop is terminal for every later same-generation mutation',async()=>{
  const f=fixture6e();await f.run();assert.equal((await f.run('stop')).outcome.snapshot.state,'stopped');
  for(const action of ['start','pause','stop'])failure6d(await f.run(action),'CONFLICT');
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,2);assert.equal(f.record.snapshot.state,'stopped');
});
test('Gate6E stale revisions and delayed Start never reach the provider',async()=>{
  const f=fixture6e(),old=f.make();await f.run();await f.run('pause');
  failure6d(await f.service.request(f.req,old,cancel6d()),'BINDING_MISMATCH');
  const stale=f.make('start',{expectedSnapshotRevision:8});
  failure6d(await f.service.request(f.req,stale,cancel6d()),'CONFLICT');
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,2);
});
test('Gate6E two adapters sharing storage cannot dispatch overlapping mutations',async()=>{
  let release;const f=fixture6e({provider:input=>new Promise(resolve=>{release=()=>resolve(reply6d(input.request,{context:{...input.snapshot.context,streamId:'stream-6e'}}));})});
  const pending=f.run();await new Promise(setImmediate);
  const other=new K135zAtomicWorkspaceAdapter({store:f.store,transport:f.transport});
  failure6d(await other.requestAtomic({principal:P,request:f.make('stop'),cancellation:cancel6d()}),'CONFLICT');
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,1);release();assert.equal((await pending).outcome.kind,'acknowledged');
});
test('Gate6E storage commit failure prevents any provider call',async()=>{
  for(const failCommit of [1,2]){
    const f=fixture6e({failCommit});failure6d(await f.run(),'UNAVAILABLE');
    assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
  }
});
test('Gate6E completion commit failure remains unknown and blocks subsequent commands',async()=>{
  const f=fixture6e({failCommit:3});failure6d(await f.run(),'UNAVAILABLE','unknown');
  assert.equal(f.record.pending.phase,'dispatched');assert.equal(f.record.snapshot.state,'ready');
  failure6d(await f.run(),'CONFLICT');assert.equal(f.calls.filter(x=>x[0]==='provider').length,1);
});
test('Gate6E revoked viewer authority never resolves a binding or dispatches',async()=>{
  const f=fixture6e();f.authority.viewerAuthorized=false;
  failure6d(await f.run(),'DENIED');assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
});
test('Gate6E host and listening permissions are rechecked after reservation',async()=>{
  for(const key of ['hostAuthorized','listeningAuthorized']){
    const f=fixture6e({afterCommit:({authority,transactions})=>{if(transactions===1)authority[key]=false;}});
    failure6d(await f.run(),'DENIED');assert.equal(f.record.pending,null);
    assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
  }
});
test('Gate6E authority changes during provider work cannot produce a listening acknowledgment',async()=>{
  let f;f=fixture6e({provider:async input=>{f.authority.hostAuthorized=false;
    return reply6d(input.request,{context:{...input.snapshot.context,streamId:'stream-6e'}});}});
  failure6d(await f.run(),'PROTOCOL_ERROR','unknown');assert.equal(f.record.uncertain,true);
  assert.equal(f.record.snapshot.state,'ready');
});
test('Gate6E cancellation after reservation prevents dispatch',async()=>{
  const token=cancel6d(),f=fixture6e({afterCommit:({transactions})=>{if(transactions===1)token.cancel();}});
  failure6d(await f.adapter.requestAtomic({principal:P,request:f.make(),cancellation:token}),'CANCELLED');
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);assert.equal(f.record.pending,null);
});
test('Gate6E cancellation after dispatch records uncertainty and ignores late success',async()=>{
  let release;const token=cancel6d(),f=fixture6e({provider:input=>new Promise(resolve=>{release=()=>resolve(reply6d(input.request));})});
  const pending=f.adapter.requestAtomic({principal:P,request:f.make('stop'),cancellation:token});
  await new Promise(setImmediate);token.cancel();failure6d(await pending,'CANCELLED','unknown');
  const before=structuredClone(f.record);release();await new Promise(setImmediate);
  assert.deepEqual(f.record,before);assert.equal(f.record.uncertain,true);assert.equal(token.count(),0);
});
test('Gate6E service deadline cancels a hanging provider and never retries',async()=>{
  const f=fixture6e({timeoutMs:10,provider:()=>new Promise(()=>{})});
  failure6d(await f.run('stop'),'TIMEOUT','unknown');await new Promise(setImmediate);
  assert.equal(f.record.uncertain,true);assert.equal(f.calls.filter(x=>x[0]==='provider').length,1);
  failure6d(await f.run(),'CONFLICT');
});
test('Gate6E thrown and malformed provider replies retain an unresolved reservation',async()=>{
  for(const provider of [async()=>{throw Error('secret-provider');},async()=>({unexpected:true})]){
    const f=fixture6e({provider}),reply=await f.run();
    assert.equal(reply.outcome.error.remoteOutcome,'unknown');assert.equal(reply.outcome.error.automaticRetry,false);
    assert(!JSON.stringify(reply).includes('secret-'));assert.equal(f.record.uncertain,true);
  }
});
test('Gate6E rejects forged provider correlation state context and revision',async()=>{
  const variants=[r=>({...r,action:'stop'}),r=>({...r,operation:{...r.operation,operationNumber:999}}),
    r=>({...r,outcome:{kind:'acknowledged',snapshot:{...r.outcome.snapshot,revision:12}}}),
    r=>({...r,outcome:{kind:'acknowledged',snapshot:{...r.outcome.snapshot,state:'ready'}}}),
    r=>({...r,outcome:{kind:'acknowledged',snapshot:{...r.outcome.snapshot,context:{...r.outcome.snapshot.context,generation:8}}}})];
  for(const variant of variants){const f=fixture6e({provider:async input=>variant(reply6d(input.request,{context:{...input.snapshot.context,streamId:'stream-6e'}}))});
    failure6d(await f.run(),'PROTOCOL_ERROR','unknown');assert.equal(f.record.snapshot.revision,8);assert.equal(f.record.uncertain,true);}
});
test('Gate6E a definite provider rejection clears its reservation without inventing a snapshot',async()=>{
  const f=fixture6e({provider:async input=>K135zAtomicWorkspaceAdapter.failure(input.request,'DENIED','rejected')});
  failure6d(await f.run(),'DENIED','rejected');assert.equal(f.record.pending,null);assert.equal(f.record.uncertain,false);
  assert.equal(f.record.snapshot.revision,8);assert.equal(f.record.snapshot.state,'ready');
});
test('Gate6E refresh is nonmutating and cannot clear an uncertain command',async()=>{
  const f=fixture6e(),before=structuredClone(f.record);
  assert.equal((await f.run('refresh')).outcome.snapshot.state,'ready');assert.deepEqual(f.record,before);
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
  f.transport.request=async()=>{throw Error('secret-provider');};await f.run();const unresolved=structuredClone(f.record);
  failure6d(await f.run('refresh'),'CONFLICT');assert.deepEqual(f.record,unresolved);
});
test('Gate6E foreign store bindings and malformed authority cannot reach the provider',async()=>{
  for(const edit of [a=>{a.context={...a.context,generation:8};},a=>{a.viewerAuthorized='true';}]){
    const f=fixture6e();edit(f.authority);const reply=await f.run();assert.equal(reply.outcome.kind,'failed');
    assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
  }
});
test('Gate6E rejects store callback replay and fabricated transaction results',async()=>{
  for(const replay of [true,false]){
    const f=fixture6e(),input=await f.store.read();
    f.store.transact=async(_input,decide)=>{const out=decide(input);if(replay)decide(input);return {...out,ticket:null};};
    failure6d(await f.run(),'PROTOCOL_ERROR');assert.equal(f.calls.filter(x=>x[0]==='provider').length,0);
  }
});
test('Gate6E revision overflow and inconsistent pending records fail closed',async()=>{
  const f=fixture6e(),record=structuredClone(f.record);record.snapshot.revision=Number.MAX_SAFE_INTEGER;
  f.store.read=async()=>({record,authority:f.authority});f.store.transact=async(_input,decide)=>decide({record,authority:f.authority});
  failure6d(await f.adapter.requestAtomic({principal:P,request:f.make('start',{expectedSnapshotRevision:Number.MAX_SAFE_INTEGER}),cancellation:cancel6d()}),'CONFLICT');
  assert.throws(()=>K135zAtomicWorkspaceAdapter.record({...record,uncertain:true}));
});
test('Gate6E refresh cannot report stale listening permissions after revocation',async()=>{
  const f=fixture6e();await f.run();f.authority.listeningAuthorized=false;
  failure6d(await f.run('refresh'),'DENIED');assert.equal(f.calls.filter(x=>x[0]==='provider').length,1);
});
test('Gate6E a second adapter observes a completed Stop fence from shared storage',async()=>{
  const f=fixture6e();await f.run();await f.run('stop');
  const other=new K135zAtomicWorkspaceAdapter({store:f.store,transport:f.transport});
  failure6d(await other.requestAtomic({principal:P,request:f.make(),cancellation:cancel6d()}),'CONFLICT');
  assert.equal(f.calls.filter(x=>x[0]==='provider').length,2);
});
test('Gate6E Stop from ready keeps the unadopted context and cannot fabricate a stream',async()=>{
  const f=fixture6e(),reply=await f.run('stop');assert.equal(reply.outcome.snapshot.state,'stopped');
  assert.equal(reply.outcome.snapshot.context.streamId,null);assert.equal(f.record.pending,null);
});
test('Gate6E active time cannot decrease and a paused stream cannot be replaced',async()=>{
  for(const field of ['activeSeconds','streamId']){
    const f=fixture6e({activeSeconds:10});await f.run();await f.run('pause');
    const current=f.record.snapshot;
    f.transport.request=async input=>reply6d(input.request,{revision:current.revision+1,
      context:{...current.context,...(field==='streamId'?{streamId:'replacement'}:{})},activeSeconds:field==='activeSeconds'?9:10});
    failure6d(await f.run(),'PROTOCOL_ERROR','unknown');assert.equal(f.record.snapshot.state,'paused');
  }
});
// K135Z_GATE6E_ATOMIC_TESTS_END

// K135Z_GATE6F_RPC_STORE_TESTS_BEGIN
const {K135zSupabaseWorkspaceStore}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
function fixture6f(options={}) {
  const base=fixture6e(),calls=[];
  let row={status:'ok',bindingRevision:1,authorityRevision:1,
    record:structuredClone(base.record),authority:structuredClone(base.authority)},saves=0;
  const client={async rpc(name,args){
    assert.equal(name,'k135z_workspace_commands_v1');calls.push(structuredClone(args));
    if(options.beforeRpc)await options.beforeRpc({args,row,calls});
    if(args.operation==='read')return {data:structuredClone(row),error:null};
    assert.equal(args.operation,'compare_save');saves++;
    if(options.beforeSave)await options.beforeSave({row,args,saves});
    const expected={bindingRevision:row.bindingRevision,authorityRevision:row.authorityRevision,
      record:row.record,authority:row.authority};
    if(NC.canonical(args.payload.expected)!==NC.canonical(expected))return {data:{status:'conflict'},error:null};
    if(options.failSave===saves)throw Error('secret-save-failure');
    row.record=structuredClone(args.payload.record);row.authority.context=row.record.snapshot.context;
    if(options.loseSave===saves)throw Error('secret-response-lost');
    const data=structuredClone(row);
    if(options.afterSave)options.afterSave({data,row,saves});
    return {data,error:null};
  }};
  const store=new K135zSupabaseWorkspaceStore({client,timeoutMs:options.timeoutMs??1000});
  let operation=0,providerCalls=0;
  const transport={async request(input){providerCalls++;
    if(options.provider)return options.provider(input);
    return reply6d(input.request,{context:{...input.snapshot.context,
      streamId:input.snapshot.context.streamId??(input.request.action==='start'?'stream-6f':null)},
      revision:input.snapshot.revision+1,activeSeconds:input.snapshot.activeSeconds,
      hostAuthorized:row.authority.hostAuthorized,listeningAuthorized:row.authority.listeningAuthorized});
  }};
  const adapter=new K135zAtomicWorkspaceAdapter({store,transport});
  const make=(action='start')=>request6d(action,{expectedContext:structuredClone(row.record.snapshot.context),
    expectedSnapshotRevision:row.record.snapshot.revision,
    operation:{requestId:'request-6f-'+(++operation),localEpoch:1,operationNumber:operation}});
  const input=(token=cancel6d())=>({principal:P,context:structuredClone(row.record.snapshot.context),cancellation:token});
  return {base,calls,client,store,transport,adapter,make,input,
    get row(){return row;},get providerCalls(){return providerCalls;},
    run:(action='start',token=cancel6d())=>adapter.requestAtomic({...input(token),request:make(action)})};
}
const reject6f=(promise,code)=>assert.rejects(promise,e=>e.code===code&&!e.message.includes('secret-'));
test('Gate6F store requires an explicit RPC client and bounded timeout',()=>{
  for(const options of [{},{client:{}},{client:{rpc(){}},timeoutMs:0},{client:{rpc(){}},timeoutMs:15001}])
    assert.throws(()=>new K135zSupabaseWorkspaceStore(options));
});
test('Gate6F shared factory enables the RPC store only with an explicit command client and transport',async()=>{
  const f=fixture6f(),w=f.base.wiring;
  const deps=Z.createK135zZoomDependencies({...w,env:{NODE_ENV:'test'},workspaceCommandClient:f.client,workspaceCommandTransport:f.transport});
  assert(deps.workspaceCommands.adapter.store instanceof K135zSupabaseWorkspaceStore);
  const reply=await deps.workspaceCommands.request(f.base.req,f.make(),cancel6d());assert.equal(reply.outcome.kind,'acknowledged');
  for(const options of [{workspaceCommandClient:f.client},{workspaceCommandTransport:f.transport},{database:f.client}]){
    const d=Z.createK135zZoomDependencies({...w,env:{NODE_ENV:'test'},...options});assert.equal(d.workspaceCommands.adapter,null);
  }
});
test('Gate6F explicit adapter and explicit store retain dependency precedence',()=>{
  const f=fixture6f(),opts={env:{NODE_ENV:'test'},workspaceCommandClient:{},workspaceCommandTransport:f.transport};
  const d=Z.createK135zZoomDependencies({...opts,workspaceCommandAdapter:f.adapter});assert.equal(d.workspaceCommands.adapter,f.adapter);
  const e=Z.createK135zZoomDependencies({...opts,workspaceCommandStore:f.store});assert.equal(e.workspaceCommands.adapter.store,f.store);
});
test('Gate6F reads send only canonical server identity and return frozen binding data',async()=>{
  const f=fixture6f(),r=await f.store.read({...f.input(),principal:{...P,tier:'forged'}});
  assert.deepEqual(f.calls[0],{operation:'read',payload:{principal:P}});assert(Object.isFrozen(r.record.snapshot.context));
  assert.deepEqual(Object.keys(r).sort(),['authority','record']);
});
test('Gate6F missing denied and conflicting bindings return sanitized failures',async()=>{
  for(const [status,code] of [['not_found','BINDING_MISMATCH'],['denied','DENIED'],['conflict','CONFLICT']]){
    const f=fixture6f();f.client.rpc=async()=>({data:{status},error:null});await reject6f(f.store.read(f.input()),code);
  }
});
test('Gate6F rejects malformed records unknown fields and invalid revision fences',async()=>{
  for(const edit of [r=>{r.bindingRevision=-1;},r=>{r.authorityRevision='1';},r=>{r.extra=true;},
    r=>{r.authority.viewerAuthorized='true';},r=>{r.record.uncertain=true;},r=>{r.status='toString';},r=>{r.extra='x'.repeat(100000);}]){
    const f=fixture6f(),r=structuredClone(f.row);edit(r);f.client.rpc=async()=>({data:r,error:null});
    await reject6f(f.store.read(f.input()),'PROTOCOL_ERROR');
  }
});
test('Gate6F foreign user agent and generation bindings fail before any save',async()=>{
  for(const key of ['userId','agentId','generation']){
    const f=fixture6f(),ctx={...f.row.record.snapshot.context,[key]:key==='generation'?99:'foreign'};
    if(key==='generation')await reject6f(f.store.transact({...f.input(),context:ctx},x=>({record:x.record})),'BINDING_MISMATCH');
    else {f.row.record.snapshot.context=ctx;f.row.authority.context=ctx;await reject6f(f.store.read(f.input()),'BINDING_MISMATCH');}
    assert.equal(f.calls.filter(x=>x.operation==='compare_save').length,0);
  }
});
test('Gate6F cancelled reads do not start RPC and in-flight cancellation discards the read',async()=>{
  const f=fixture6f(),token=cancel6d(true);await reject6f(f.store.read(f.input(token)),'CANCELLED');assert.equal(f.calls.length,0);
  const t=cancel6d(),g=fixture6f({beforeRpc:()=>t.cancel()});await reject6f(g.store.read(g.input(t)),'CANCELLED');
});
test('Gate6F Start Pause resume and Stop persist all three command phases',async()=>{
  const f=fixture6f();for(const [action,state] of [['start','listening'],['pause','paused'],['start','listening'],['stop','stopped']])
    assert.equal((await f.run(action)).outcome.snapshot.state,state);
  assert.equal(f.row.record.version,12);assert.equal(f.row.record.snapshot.revision,12);
  assert.equal(f.row.record.pending,null);assert.equal(f.providerCalls,4);
  assert.equal(f.calls.filter(x=>x.operation==='compare_save').length,12);
});
test('Gate6F callback runs once and competing snapshots cannot both commit',async()=>{
  const f=fixture6f();let decisions=0;
  const decide=x=>{decisions++;return {record:{...x.record,version:x.record.version+1}};};
  const results=await Promise.allSettled([f.store.transact(f.input(),decide),f.store.transact(f.input(),decide)]);
  assert.equal(decisions,2);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(results.find(x=>x.status==='rejected').reason.code,'CONFLICT');assert.equal(f.row.record.version,1);
});
test('Gate6F authority changes between read and save cannot commit or dispatch',async()=>{
  const f=fixture6f({beforeSave:({row})=>{row.authorityRevision++;row.authority.hostAuthorized=false;}});
  failure6d(await f.run(),'CONFLICT');assert.equal(f.providerCalls,0);assert.equal(f.row.record.version,0);
});
test('Gate6F binding replacement and revoke-restore cycles invalidate old decisions',async()=>{
  for(const key of ['bindingRevision','authorityRevision']){
    const f=fixture6f({beforeSave:({row})=>{row[key]++;}});let count=0;
    await reject6f(f.store.transact(f.input(),x=>{count++;return {record:x.record};}),'CONFLICT');assert.equal(count,1);
  }
});
test('Gate6F read-only refresh validates the same authority fence without changing record version',async()=>{
  const f=fixture6f(),before=structuredClone(f.row.record);
  assert.equal((await f.run('refresh')).outcome.kind,'acknowledged');assert.deepEqual(f.row.record,before);
  assert.equal(f.calls.filter(x=>x.operation==='compare_save').length,1);assert.equal(f.providerCalls,0);
});
test('Gate6F storage failure before dispatch cannot call the provider',async()=>{
  for(const failSave of [1,2]){const f=fixture6f({failSave});failure6d(await f.run(),'UNAVAILABLE');assert.equal(f.providerCalls,0);}
});
test('Gate6F lost reservation acknowledgment preserves pending work and prevents retry',async()=>{
  const f=fixture6f({loseSave:1});failure6d(await f.run(),'UNAVAILABLE');assert.equal(f.row.record.pending.phase,'prepared');
  failure6d(await f.run(),'CONFLICT');assert.equal(f.providerCalls,0);
});
test('Gate6F lost completion acknowledgment remains unknown while the saved Stop fence survives',async()=>{
  const f=fixture6f({loseSave:3});failure6d(await f.run('stop'),'UNAVAILABLE','unknown');
  assert.equal(f.row.record.snapshot.state,'stopped');failure6d(await f.run(),'CONFLICT');assert.equal(f.providerCalls,1);
});
test('Gate6F a new adapter observes the saved Stop fence',async()=>{
  const f=fixture6f();await f.run('stop');
  const a=new K135zAtomicWorkspaceAdapter({store:new K135zSupabaseWorkspaceStore({client:f.client}),transport:f.transport});
  failure6d(await a.requestAtomic({...f.input(),request:f.make()}),'CONFLICT');assert.equal(f.providerCalls,1);
});
test('Gate6F forged commit records authority and fences cannot acknowledge a command',async()=>{
  for(const edit of [d=>{d.record.version++;},d=>{d.authorityRevision++;},d=>{d.bindingRevision++;},d=>{d.authority.hostAuthorized=false;}]){
    const f=fixture6f({afterSave:({data})=>edit(data)});failure6d(await f.run(),'PROTOCOL_ERROR');assert.equal(f.providerCalls,0);
  }
});
test('Gate6F asynchronous callbacks are rejected before a save',async()=>{
  const f=fixture6f();await reject6f(f.store.transact(f.input(),async x=>({record:x.record})),'PROTOCOL_ERROR');
  assert.equal(f.calls.filter(x=>x.operation==='compare_save').length,0);
});
test('Gate6F invalid version changes and same-version mutations cannot reach storage',async()=>{
  for(const edit of [r=>({...r,version:r.version+2}),r=>({...r,snapshot:{...r.snapshot,activeSeconds:3}})]){
    const f=fixture6f();await reject6f(f.store.transact(f.input(),x=>({record:edit(x.record)})),'PROTOCOL_ERROR');
    assert.equal(f.calls.filter(x=>x.operation==='compare_save').length,0);
  }
});
test('Gate6F storage cannot switch streams or reopen a stopped generation',async()=>{
  for(const stopped of [false,true]){
    const f=fixture6f();if(stopped)await f.run('stop');
    await reject6f(f.store.transact(f.input(),x=>({record:{...x.record,version:x.record.version+1,
      snapshot:{...x.record.snapshot,...(stopped?{state:'ready'}:{context:{...x.record.snapshot.context,streamId:'forged'}})}}})),'PROTOCOL_ERROR');
  }
});
test('Gate6F cancellation after reservation can durably clear prepared work',async()=>{
  const token=cancel6d(),f=fixture6f({afterSave:({saves})=>{if(saves===1)token.cancel();}});
  failure6d(await f.run('start',token),'CANCELLED');assert.equal(f.row.record.pending,null);assert.equal(f.providerCalls,0);
});
test('Gate6F cancellation after dispatch saves uncertainty and ignores late provider success',async()=>{
  let release;const token=cancel6d(),f=fixture6f({provider:input=>new Promise(resolve=>{release=()=>resolve(reply6d(input.request));})});
  const pending=f.run('stop',token);await new Promise(setImmediate);token.cancel();failure6d(await pending,'CANCELLED','unknown');
  assert.equal(f.row.record.uncertain,true);const before=structuredClone(f.row);release();await new Promise(setImmediate);assert.deepEqual(f.row,before);
});
test('Gate6F RPC errors and malformed envelopes never expose upstream details',async()=>{
  for(const rpc of [async()=>{throw Error('secret-upstream');},async()=>({error:{message:'secret-upstream'}}),async()=>null]){
    const f=fixture6f();f.client.rpc=rpc;await reject6f(f.store.read(f.input()),'UNAVAILABLE');
  }
});
test('Gate6F RPC deadlines abort once and do not retry hanging requests',async()=>{
  const f=fixture6f({timeoutMs:5});let calls=0,signal;
  f.client.rpc=()=>{calls++;return {abortSignal(s){signal=s;return new Promise(()=>{});}};};
  await reject6f(f.store.read(f.input()),'TIMEOUT');assert.equal(calls,1);assert.equal(signal.aborted,true);
});
test('Gate6F two clients sharing an RPC store cannot dispatch overlapping commands',async()=>{
  let release;const f=fixture6f({provider:input=>new Promise(resolve=>{release=()=>resolve(reply6d(input.request));})});
  const pending=f.run('stop');await new Promise(setImmediate);
  const a=new K135zAtomicWorkspaceAdapter({store:new K135zSupabaseWorkspaceStore({client:f.client}),transport:f.transport});
  failure6d(await a.requestAtomic({...f.input(),request:f.make('stop')}),'CONFLICT');
  assert.equal(f.providerCalls,1);release();assert.equal((await pending).outcome.kind,'acknowledged');
});
// K135Z_GATE6F_RPC_STORE_TESTS_END

// K135Z_GATE6H_WEBHOOK_CAPTURE_TESTS_BEGIN
const crypto6h=require('node:crypto');
const {ZoomWebhookVerifier:Verifier6h}=require('../k135z_zoom/zoom_webhook_verifier.cjs');
const parserBegin6h='app.use(express.json({',parserEnd6h='})); // KORLIX_AGENT_EMAIL_RESEND_RAW_BODY_BUILD133';
assert.equal(source.split(parserBegin6h).length,2);assert.equal(source.split(parserEnd6h).length,2);
const parser6h=vm.runInNewContext('({'+source.split(parserBegin6h)[1].split(parserEnd6h)[0]+'})',{Buffer});
const now6h=1800000000000,secret6h='local-webhook-fixture';
function signature6h(raw,timestamp=String(now6h/1000)) {
  return 'v0='+crypto6h.createHmac('sha256',secret6h).update('v0:'+timestamp+':').update(raw).digest('hex');
}
function event6h() {return {event:'meeting.rtms_started',event_ts:now6h,payload:{account_id:'zoom-account',
  object:{uuid:'meeting-unicode-\u00e9',rtms_stream_id:'stream-local'}}};}
function request6h(raw=Buffer.from(JSON.stringify(event6h())),options={}) {
  const timestamp=options.timestamp??String(now6h/1000);
  const req={method:options.method??'POST',originalUrl:options.url??'/api/k135z/zoom/webhook',
    headers:{'x-zm-request-timestamp':timestamp,'x-zm-signature':signature6h(raw,timestamp)},body:{}};
  parser6h.verify(req,{},raw);return req;
}
function fixture6h() {
  const calls=[],repository={async applyWebhookEvent(plan){calls.push(plan);return {accepted:true,duplicate:false,deletedConnections:1};}};
  const handlers=Z.createK135zZoomHandlers({repository,webhookVerifier:new Verifier6h({secret:secret6h,clock:()=>now6h})});
  return {calls,async run(req,route='webhook') {
    const res={status(n){this.statusCode=n;return this;},json(x){this.body=x;return this;}};
    await handlers[route](req,res);return res;
  }};
}
test('Gate6H shared parser captures exact Zoom bytes for both registered endpoints',()=>{
  const raw=Buffer.from('{ "event" : "probe", "text":"\u00e9" }\n');
  for(const suffix of ['webhook','deauthorization','webhook/?probe=1','WEBHOOK?probe=1']){
    const req=request6h(raw,{url:'/api/k135z/zoom/'+suffix});assert(Buffer.isBuffer(req.rawBody));assert(req.rawBody.equals(raw));
  }
});
test('Gate6H unrelated paths and methods do not retain Zoom raw bodies',()=>{
  for(const url of ['/api/k135z/zoom/status','/api/k135z/zoom/webhook-extra','/api/k135z/zoom/webhook/extra','/api/music/webhook'])
    assert.equal(request6h(undefined,{url}).rawBody,undefined);
  assert.equal(request6h(undefined,{method:'GET'}).rawBody,undefined);
});
test('Gate6H preserves Resend body capture and the existing JSON size limit',()=>{
  const raw=Buffer.from('{ "email":"fixture" }\n'),req={method:'POST',originalUrl:'/api/agent-email/resend/webhook'};
  parser6h.verify(req,{},raw);assert(req.korlixAgentEmailRawBody.equals(raw));assert.equal(req.rawBody,undefined);
  assert.equal(parser6h.limit,'5mb');
});
test('Gate6H raw body owns its bytes and supports the request URL fallback',()=>{
  const raw=Buffer.from('{ "event":"probe" }'),req={method:'POST',url:'/api/k135z/zoom/webhook'};
  const expected=Buffer.from(raw);parser6h.verify(req,{},raw);raw.fill(0);assert(req.rawBody.equals(expected));
});
test('Gate6H signed whitespace and Unicode survive the real parser callback into the handler',async()=>{
  const f=fixture6h(),raw=Buffer.from(JSON.stringify(event6h(),null,2)+'\n'),req=request6h(raw);
  req.body=JSON.parse(raw);const res=await f.run(req);assert.equal(res.statusCode,200);
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].mutation.record.meetingUuid,'meeting-unicode-\u00e9');
});
test('Gate6H signed endpoint validation responds without a storage mutation',async()=>{
  const f=fixture6h(),raw=Buffer.from(JSON.stringify({event:'endpoint.url_validation',payload:{plainToken:'local-token'}}));
  const res=await f.run(request6h(raw));assert.equal(res.statusCode,200);
  assert.equal(res.body.plainToken,'local-token');assert.equal(res.body.encryptedToken,
    crypto6h.createHmac('sha256',secret6h).update('local-token').digest('hex'));assert.equal(f.calls.length,0);
});
test('Gate6H deauthorization reaches storage only after signature validation',async()=>{
  const f=fixture6h(),raw=Buffer.from(JSON.stringify({event:'app_deauthorized',event_ts:now6h,
    payload:{account_id:'zoom-account',user_id:'zoom-user'}}));
  const req=request6h(raw,{url:'/api/k135z/zoom/deauthorization'}),res=await f.run(req,'deauthorization');
  assert.equal(res.statusCode,200);assert.equal(f.calls.length,1);
  assert.deepEqual(f.calls[0].mutation,{kind:'deauthorize',zoomAccountId:'zoom-account',zoomUserId:'zoom-user'});
});
test('Gate6H unsigned requests are rejected before any storage call',async()=>{
  const f=fixture6h(),req=request6h();req.headers={};const res=await f.run(req);
  assert.equal(res.statusCode,401);assert.equal(f.calls.length,0);
});
test('Gate6H forged signatures are rejected before any storage call',async()=>{
  const f=fixture6h(),req=request6h();req.headers['x-zm-signature']='v0='+'0'.repeat(64);
  assert.equal((await f.run(req)).statusCode,401);assert.equal(f.calls.length,0);
});
test('Gate6H an altered request byte invalidates the signature',async()=>{
  const f=fixture6h(),req=request6h();req.rawBody=Buffer.concat([req.rawBody,Buffer.from(' ')]);
  assert.equal((await f.run(req)).statusCode,401);assert.equal(f.calls.length,0);
});
test('Gate6H expired and future signed requests cannot mutate storage',async()=>{
  for(const seconds of [-301,301]){const f=fixture6h(),req=request6h(undefined,{timestamp:String(now6h/1000+seconds)});
    assert.equal((await f.run(req)).statusCode,401);assert.equal(f.calls.length,0);}
});
test('Gate6H semantically equal reserialized JSON cannot replace signed bytes',async()=>{
  const f=fixture6h(),req=request6h(Buffer.from(JSON.stringify(event6h(),null,2)));
  req.rawBody=Buffer.from(JSON.stringify(event6h()));assert.equal((await f.run(req)).statusCode,401);assert.equal(f.calls.length,0);
});
test('Gate6H the verified raw event overrides an untrusted parsed body',async()=>{
  const f=fixture6h(),req=request6h();req.body={event:'app_deauthorized',event_ts:now6h,payload:{account_id:'foreign',user_id:'foreign'}};
  assert.equal((await f.run(req)).statusCode,200);assert.equal(f.calls.length,1);
  assert.equal(f.calls[0].mutation.kind,'session');assert.equal(f.calls[0].mutation.record.zoomAccountId,'zoom-account');
});
test('Gate6H malformed signed JSON is rejected without storage or payload disclosure',async()=>{
  const f=fixture6h(),req=request6h(Buffer.from('{"private-fixture":'));
  const res=await f.run(req);assert.equal(res.statusCode,400);assert.equal(f.calls.length,0);
  assert(!JSON.stringify(res.body).includes('private-fixture'));assert(!JSON.stringify(res.body).includes(secret6h));
});
// K135Z_GATE6H_WEBHOOK_CAPTURE_TESTS_END

// K135Z_GATE6I_RTMS_TESTS_BEGIN
const {createK135zRtmsStream:stream6i}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
const ctx6i={...P,sessionId:'session-sdk',meetingUuid:'meeting-sdk',streamId:'stream-sdk',generation:1};
function fixture6i(options={}){
  const callbacks={},packets=[],closed=[],joins=[];let created=0,left=0,allowed=true;
  class Client {
    constructor(){created++;}
    onJoinConfirm(fn){callbacks.join=fn;return options.registration!==false;}
    onTranscriptData(fn){callbacks.transcript=fn;return true;}
    onLeave(fn){callbacks.leave=fn;return true;}
    join(input){joins.push(input);if(options.syncConfirm)callbacks.join(0);if(options.throwJoin)throw Error('private-sdk-details');return options.joinResult??true;}
    leave(){left++;if(options.reentrantLeave)callbacks.leave();return options.leaveResult??true;}
  }
  const sdk={Client,RTMS_SDK_OK:0,configureLogger(){}};
  const stream=stream6i({sdk,context:ctx6i,signature:'a'.repeat(64),serverUrls:'wss://rtms.zoom.us:443',
    authorize:()=>allowed,onTranscript:p=>{packets.push(p);return options.accept??true;},onClosed:p=>closed.push(p),
    ...options.config});
  return {stream,callbacks,packets,closed,joins,created:()=>created,left:()=>left,deny:()=>{allowed=false;},
    emit(text='hello',changes={}){const b=Buffer.from(text);callbacks.transcript(b,b.length,100,
      {userId:7,userName:'Speaker',startTs:90,endTs:100,...changes});}};
}
async function connected6i(f){const p=f.stream.connect();f.callbacks.join(0);await p;return f;}
test('Gate6I SDK construction is lazy and requires server permission',async()=>{
  const f=fixture6i();assert.equal(f.created(),0);f.deny();await assert.rejects(f.stream.connect(),{code:'DENIED'});
  assert.equal(f.created(),0);assert.equal(f.joins.length,0);
});
test('Gate6I rejects untrusted endpoints and unbound streams before SDK creation',()=>{
  for(const url of ['ws://rtms.zoom.us','wss://127.0.0.1','wss://zoom.us.attacker.invalid','wss://user:pass@rtms.zoom.us','wss://rtms.zoom.us:444'])
    assert.throws(()=>fixture6i({config:{serverUrls:url}}));
  assert.throws(()=>fixture6i({config:{context:{...ctx6i,streamId:null}}}));
});
test('Gate6I does not acknowledge a join until Zoom confirms it',async()=>{
  const f=fixture6i(),p=f.stream.connect();let finished=false;p.then(()=>{finished=true;});
  await Promise.resolve();assert.equal(finished,false);assert.equal(f.stream.status().phase,'connecting');
  f.callbacks.join(0);const result=await p;assert.equal(result.state,'connected');assert.deepEqual(result.context,ctx6i);f.stream.close();
});
test('Gate6I joins with exact meeting binding and TLS verification enabled',async()=>{
  const f=await connected6i(fixture6i());assert.equal(f.joins.length,1);const j=f.joins[0];
  assert.equal(j.meeting_uuid,ctx6i.meetingUuid);assert.equal(j.rtms_stream_id,ctx6i.streamId);
  assert.equal(j.is_verify_cert,1);assert.equal(j.pollInterval,10);assert.equal(j.signature,'a'.repeat(64));f.stream.close();
});
test('Gate6I failed join confirmation releases the client without reconnecting',async()=>{
  const f=fixture6i(),p=f.stream.connect();f.callbacks.join(1);await assert.rejects(p,{code:'JOIN_FAILED'});
  assert.equal(f.left(),1);assert.equal(f.joins.length,1);f.callbacks.join(0);assert.equal(f.stream.status().phase,'closed');
});
test('Gate6I immediate SDK join rejection is not treated as success',async()=>{
  const f=fixture6i({joinResult:false,syncConfirm:true});await assert.rejects(f.stream.connect(),{code:'JOIN_FAILED'});assert.equal(f.left(),1);
});
test('Gate6I native callback registration failure prevents joining',async()=>{
  const f=fixture6i({registration:false});await assert.rejects(f.stream.connect(),{code:'SDK_ERROR'});assert.equal(f.joins.length,0);assert.equal(f.left(),1);
});
test('Gate6I join timeout closes the client and rejects late confirmation',async()=>{
  const f=fixture6i({config:{joinTimeoutMs:10}});await assert.rejects(f.stream.connect(),{code:'JOIN_TIMEOUT'});
  f.callbacks.join(0);assert.equal(f.left(),1);assert.equal(f.stream.status().phase,'closed');
});
test('Gate6I cancellation before joining never constructs a client',async()=>{
  const f=fixture6i(),abort=new AbortController();abort.abort();await assert.rejects(f.stream.connect({signal:abort.signal}),{code:'CANCELLED'});assert.equal(f.created(),0);
});
test('Gate6I cancellation during joining closes once and suppresses callbacks',async()=>{
  const f=fixture6i(),abort=new AbortController(),p=f.stream.connect({signal:abort.signal});abort.abort();
  await assert.rejects(p,{code:'CANCELLED'});f.callbacks.join(0);f.emit();assert.equal(f.left(),1);assert.equal(f.packets.length,0);
});
test('Gate6I valid transcript packets retain speaker timing and immutable context',async()=>{
  const f=await connected6i(fixture6i());f.emit('Hello \u00e9');const p=f.packets[0];
  assert.equal(p.text,'Hello \u00e9');assert.equal(p.userId,7);assert.equal(p.startTs,90);assert.equal(p.endTs,100);
  assert(Object.isFrozen(p));assert(Object.isFrozen(p.context));assert.deepEqual(p.context,ctx6i);f.stream.close();
});
test('Gate6I transcripts before confirmation and after close are discarded',async()=>{
  const f=fixture6i(),p=f.stream.connect();f.emit();assert.equal(f.packets.length,0);f.callbacks.join(0);await p;
  f.stream.close();f.emit();assert.equal(f.packets.length,0);assert.equal(f.left(),1);
});
test('Gate6I revoked permission blocks the next transcript and closes capture',async()=>{
  const f=await connected6i(fixture6i());f.deny();f.emit();assert.equal(f.packets.length,0);assert.equal(f.closed[0].code,'DENIED');assert.equal(f.left(),1);
});
test('Gate6I an expired authority lease closes even without incoming media',async()=>{
  const f=await connected6i(fixture6i({config:{leaseMs:15}}));await new Promise(r=>setTimeout(r,30));
  assert.equal(f.stream.status().phase,'closed');assert.equal(f.left(),1);
});
test('Gate6I lease renewal requires a still valid server authorization',async()=>{
  const f=await connected6i(fixture6i());assert.equal(f.stream.renew(60000),true);assert.throws(()=>f.stream.renew(60001));
  f.deny();assert.equal(f.stream.renew(),false);assert.equal(f.left(),1);
});
test('Gate6I rejects oversized malformed UTF8 and inconsistent transcript buffers',async()=>{
  for(const mode of ['large','utf8','size']){const f=await connected6i(fixture6i());
    if(mode==='large')f.emit('a'.repeat(8193));
    else f.callbacks.transcript(mode==='utf8'?Buffer.from([0xff]):Buffer.from('a'),mode==='utf8'?1:2,100,{userId:7,userName:'Speaker',startTs:90,endTs:100});
    assert.equal(f.packets.length,0);assert.equal(f.closed[0].code,'INVALID_TRANSCRIPT');}
});
test('Gate6I queue backpressure stops capture without retaining more text',async()=>{
  const f=await connected6i(fixture6i({accept:false}));f.emit();f.emit('late');assert.equal(f.packets.length,1);assert.equal(f.closed[0].code,'BACKPRESSURE');assert.equal(f.left(),1);
});
test('Gate6I close is idempotent even when native leave calls back synchronously',async()=>{
  const f=await connected6i(fixture6i({reentrantLeave:true})),a=f.stream.close(),b=f.stream.close();
  assert.deepEqual(a,b);assert.equal(a.released,true);assert.equal(f.left(),1);assert.equal(f.closed.length,1);
});
test('Gate6I failed native release remains visible and cannot be restarted',async()=>{
  const f=await connected6i(fixture6i({leaveResult:false}));assert.equal(f.stream.close().released,false);
  await assert.rejects(f.stream.connect(),{code:'ALREADY_USED'});assert.equal(f.created(),1);
});
test('Gate6I SDK exceptions expose only a sanitized failure code',async()=>{
  const f=fixture6i({throwJoin:true});await assert.rejects(f.stream.connect(),e=>e.code==='SDK_ERROR'&&!e.message.includes('private-sdk-details'));assert.equal(f.left(),1);
});
test('Gate6I remote leave ends delivery and notifies the owner once',async()=>{
  const f=await connected6i(fixture6i());f.callbacks.leave(0);f.callbacks.leave(0);f.emit();assert.equal(f.packets.length,0);assert.equal(f.closed.length,1);assert.equal(f.closed[0].code,'REMOTE_CLOSED');
});
test('Gate6I permission is rechecked when Zoom confirms the connection',async()=>{
  const f=fixture6i(),p=f.stream.connect();f.deny();f.callbacks.join(0);await assert.rejects(p,{code:'DENIED'});assert.equal(f.left(),1);
});
test('Gate6I current flat Zoom RTMS webhook fields produce the stored session binding',()=>{
  const p=C.eventPlan({body:{event:'meeting.rtms_started',event_ts:100,payload:{account_id:'account',meeting_uuid:'meeting',rtms_stream_id:'stream',server_urls:'wss://rtms.zoom.us'}}});
  assert.equal(p.mutation.record.meetingUuid,'meeting');assert.equal(p.mutation.record.streamId,'stream');assert(!JSON.stringify(p).includes('server_urls'));
});
test('Gate6I flat stopped events preserve the terminal session status',()=>{
  const p=C.eventPlan({body:{event:'meeting.rtms_stopped',event_ts:100,payload:{account_id:'account',meeting_uuid:'meeting',rtms_stream_id:'stream'}}});assert.equal(p.mutation.record.status,'stopped');
});
test('Gate6I conflicting flat and legacy webhook bindings are rejected',()=>{
  for(const object of [{uuid:'other',rtms_stream_id:'stream'},{uuid:'meeting',rtms_stream_id:'other'}])
    assert.throws(()=>C.eventPlan({body:{event:'meeting.rtms_started',event_ts:100,payload:{account_id:'account',meeting_uuid:'meeting',rtms_stream_id:'stream',object}}}));
});
test('Gate6I missing and null provider identifiers cannot create a session',()=>{
  for(const meeting_uuid of [undefined,null,''])assert.throws(()=>C.eventPlan({body:{event:'meeting.rtms_started',event_ts:100,payload:{account_id:'account',meeting_uuid,rtms_stream_id:'stream'}}}));
});
// K135Z_GATE6I_RTMS_TESTS_END

// K135Z_GATE6J_COMMAND_TRANSPORT_TESTS_BEGIN
const {createK135zRtmsCommandTransport:transport6j}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
function fixture6j(t,o={}){
  const f=fixture6f(o),clients=[],packets=[],grants=[];let time=1000;
  f.row.bindingRevision=f.row.record.snapshot.context.generation;
  class Client {
    constructor(){this.callbacks={};this.left=0;clients.push(this);}
    onJoinConfirm(fn){this.callbacks.join=fn;return true;}
    onTranscriptData(fn){this.callbacks.text=fn;return true;}
    onLeave(fn){this.callbacks.leave=fn;return true;}
    join(input){this.input=input;if(!o.manualJoin)this.callbacks.join(0);return o.joinResult??true;}
    leave(){this.left++;return o.leaveResult??true;}
    emit(){const b=Buffer.from('meeting words');this.callbacks.text(b,b.length,100,{userId:4,userName:'Speaker',startTs:90,endTs:100});}
  }
  const sdk={Client,RTMS_SDK_OK:0,configureLogger(){}};
  const config={sdk,clock:()=>time,grantTimeoutMs:100,
    async resolveGrant(input){grants.push(input);
      const g={context:{...input.context,streamId:input.context.streamId??'stream-6j'},bindingRevision:f.row.bindingRevision,
        authorityRevision:f.row.authorityRevision,viewerAuthorized:f.row.authority.viewerAuthorized,
        hostAuthorized:f.row.authority.hostAuthorized,listeningAuthorized:f.row.authority.listeningAuthorized,
        validForMs:5000,serverUrls:'wss://rtms.zoom.us',signature:'b'.repeat(64)};
      return o.grant?o.grant(g,input,grants.length):g;},
    onTranscript(packet){packets.push(packet);return o.accept??true;},...o.config};
  const transport=transport6j(config),adapter=new K135zAtomicWorkspaceAdapter({store:f.store,transport});
  t.after(()=>transport.close());
  return {...f,transport,adapter,clients,packets,grants,config,advance:n=>{time+=n;},
    run:(action='start',cancellation=cancel6d())=>adapter.requestAtomic({principal:P,request:f.make(action),cancellation})};
}
const wait6j=()=>new Promise(resolve=>setImmediate(resolve));
test('Gate6J requires explicit server grant resolution and never enables default live wiring',()=>{
  for(const value of [{},{sdk:{Client(){},RTMS_SDK_OK:0}},{sdk:{Client(){},RTMS_SDK_OK:0},resolveGrant(){}}])assert.throws(()=>transport6j(value));
  assert.equal(Z.createK135zZoomDependencies({env:{NODE_ENV:'production'}}).workspaceCommands.adapter,null);
});
test('Gate6J Start waits for SDK confirmation and commits before transcript delivery',async t=>{
  let f;f=fixture6j(t,{manualJoin:true,beforeSave:({saves})=>{if(saves===3){f.clients[0].emit();assert.equal(f.packets.length,0);}}});
  const pending=f.run();await wait6j();assert.equal(f.clients.length,1);assert.equal(f.row.record.snapshot.state,'ready');
  f.clients[0].callbacks.join(0);const reply=await pending;assert.equal(reply.outcome.snapshot.state,'listening');
  assert.equal(f.row.record.pending,null);f.clients[0].emit();assert.equal(f.packets.length,1);
});
test('Gate6J Start reads server grants rather than stale snapshot permission flags',async t=>{
  const f=fixture6j(t);f.row.record.snapshot.hostAuthorized=false;f.row.record.snapshot.listeningAuthorized=false;
  const reply=await f.run();assert.equal(reply.outcome.kind,'acknowledged');assert.equal(reply.outcome.snapshot.hostAuthorized,true);
});
test('Gate6J Pause stops capture and resume uses the same stream with a fresh client',async t=>{
  const f=fixture6j(t);await f.run();f.advance(1500);const paused=await f.run('pause');
  assert.equal(paused.outcome.snapshot.state,'paused');assert.equal(paused.outcome.snapshot.activeSeconds,1);
  f.clients[0].emit();assert.equal(f.packets.length,0);f.advance(10000);await f.run();
  assert.equal(f.clients.length,2);assert.equal(f.clients[0].left,1);
  assert.equal(f.clients[0].input.rtms_stream_id,f.clients[1].input.rtms_stream_id);
  f.advance(1600);const stopped=await f.run('stop');assert.equal(stopped.outcome.snapshot.activeSeconds,3);
  assert.equal(stopped.outcome.snapshot.state,'stopped');assert.equal(f.clients[1].left,1);
});
test('Gate6J durable Stop prevents another same-generation SDK join',async t=>{
  const f=fixture6j(t);await f.run();await f.run('stop');failure6d(await f.run(),'CONFLICT');assert.equal(f.clients.length,1);
});
test('Gate6J Stop from ready preserves the null stream and constructs no client',async t=>{
  const f=fixture6j(t),r=await f.run('stop');assert.equal(r.outcome.snapshot.context.streamId,null);assert.equal(f.clients.length,0);
});
test('Gate6J completion save failure closes the joined client and delivers no transcript',async t=>{
  const f=fixture6j(t,{failSave:3}),r=await f.run();failure6d(r,'UNAVAILABLE','unknown');
  assert.equal(f.clients[0].left,1);f.clients[0].emit();assert.equal(f.packets.length,0);
  assert.equal(f.row.record.pending.phase,'dispatched');failure6d(await f.run(),'CONFLICT');
});
test('Gate6J lost completion response closes capture even if storage saved listening',async t=>{
  const f=fixture6j(t,{loseSave:3});failure6d(await f.run(),'UNAVAILABLE','unknown');
  assert.equal(f.row.record.snapshot.state,'listening');assert.equal(f.clients[0].left,1);f.clients[0].emit();assert.equal(f.packets.length,0);
});
test('Gate6J cancelled join releases once and ignores a late confirmation',async t=>{
  const f=fixture6j(t,{manualJoin:true}),token=cancel6d(),pending=f.run('start',token);await wait6j();token.cancel();
  failure6d(await pending,'CANCELLED','unknown');f.clients[0].callbacks.join(0);f.clients[0].emit();
  assert.equal(f.clients[0].left,1);assert.equal(f.packets.length,0);assert.equal(token.count(),0);
});
test('Gate6J cancellation during grant lookup never creates a late SDK client',async t=>{
  let finish;const f=fixture6j(t,{grant:g=>new Promise(r=>{finish=()=>r(g);})}),token=cancel6d(),pending=f.run('start',token);
  await wait6j();token.cancel();failure6d(await pending,'CANCELLED','unknown');finish();await wait6j();assert.equal(f.clients.length,0);
});
test('Gate6J expired grants and denied permissions cannot create an SDK client',async t=>{
  for(const change of [{validForMs:0},{hostAuthorized:false},{listeningAuthorized:false},{viewerAuthorized:false}]){
    const f=fixture6j(t,{grant:g=>({...g,...change})});failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);
  }
});
test('Gate6J foreign meeting generation and stream grants are rejected before joining',async t=>{
  for(const field of ['meetingUuid','generation','userId']){
    const f=fixture6j(t,{grant:g=>({...g,context:{...g.context,[field]:field==='generation'?999:'foreign'}})});
    failure6d(await f.run(),'BINDING_MISMATCH');assert.equal(f.clients.length,0);
  }
  const f=fixture6j(t,{grant:g=>({...g,bindingRevision:g.bindingRevision+1})});
  failure6d(await f.run(),'BINDING_MISMATCH');assert.equal(f.clients.length,0);
});
test('Gate6J resolver latency consumes the lease instead of extending it',async t=>{
  let f;f=fixture6j(t,{grant:g=>{f.advance(1001);return {...g,validForMs:1000};}});
  failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);
});
test('Gate6J grant lookup timeout aborts and does not retry',async t=>{
  let signal;const f=fixture6j(t,{config:{grantTimeoutMs:10},grant:(_,input)=>{signal=input.signal;return new Promise(()=>{});}});
  failure6d(await f.run(),'TIMEOUT');assert.equal(signal.aborted,true);assert.equal(f.grants.length,1);assert.equal(f.clients.length,0);
});
test('Gate6J failed native release cannot acknowledge Pause or deliver late text',async t=>{
  const f=fixture6j(t,{leaveResult:false});await f.run();failure6d(await f.run('pause'),'UNAVAILABLE','unknown');
  f.clients[0].emit();assert.equal(f.packets.length,0);assert.equal(f.transport.close(),false);
});
test('Gate6J refresh denial closes capture without automatically reconnecting',async t=>{
  const f=fixture6j(t,{grant:(g,_,n)=>({...g,validForMs:40,hostAuthorized:n===1})});await f.run();
  await new Promise(r=>setTimeout(r,35));assert.equal(f.clients[0].left,1);f.clients[0].emit();assert.equal(f.packets.length,0);assert.equal(f.clients.length,1);
});
test('Gate6J authority revision changes close the old capture lease',async t=>{
  const f=fixture6j(t,{grant:(g,_,n)=>({...g,validForMs:40,authorityRevision:n})});await f.run();
  await new Promise(r=>setTimeout(r,35));assert.equal(f.clients[0].left,1);assert.equal(f.clients.length,1);
});
test('Gate6J pause releases before a hanging permission lookup',async t=>{
  const f=fixture6j(t,{config:{grantTimeoutMs:15},grant:(g,_,n)=>n===1?g:new Promise(()=>{})});await f.run();
  const pending=f.run('pause');await wait6j();assert.equal(f.clients[0].left,1);failure6d(await pending,'TIMEOUT','unknown');
});
test('Gate6J a restarted transport cannot claim ownership of an existing listening stream',async t=>{
  const f=fixture6j(t);await f.run();const other=transport6j(f.config);t.after(()=>other.close());
  const adapter=new K135zAtomicWorkspaceAdapter({store:f.store,transport:other});
  failure6d(await adapter.requestAtomic({principal:P,request:f.make('stop'),cancellation:cancel6d()}),'UNAVAILABLE','unknown');
  assert.equal(f.clients.length,1);assert.equal(f.clients[0].left,0);
});
test('Gate6J transcript backpressure closes capture and rejects later packets',async t=>{
  const f=fixture6j(t,{accept:false});await f.run();f.clients[0].emit();f.clients[0].emit();
  assert.equal(f.packets.length,1);assert.equal(f.clients[0].left,1);
});
test('Gate6J malformed or unsigned endpoint grants cannot join',async t=>{
  for(const change of [{serverUrls:'wss://attacker.invalid'},{signature:'wrong'},{extra:true}]){
    const f=fixture6j(t,{grant:g=>({...g,...change})});const r=await f.run();assert.equal(r.outcome.kind,'failed');assert.equal(f.clients.length,0);
  }
});
test('Gate6J storage authority revocation during join closes instead of acknowledging Start',async t=>{
  const f=fixture6j(t,{manualJoin:true}),pending=f.run();await wait6j();f.row.authority.hostAuthorized=false;
  f.clients[0].callbacks.join(0);failure6d(await pending,'PROTOCOL_ERROR','unknown');assert.equal(f.clients[0].left,1);
});
test('Gate6J shutdown releases active capture and prevents new requests',async t=>{
  const f=fixture6j(t);await f.run();assert.equal(f.transport.close(),true);assert.equal(f.clients[0].left,1);
  const r=await f.run('pause');failure6d(r,'UNAVAILABLE');assert.equal(f.clients.length,1);
});
test('Gate6J asynchronous settlement hooks cannot produce an acknowledgment',async()=>{
  const f=fixture6f();f.transport.settle=()=>Promise.resolve(true);failure6d(await f.run(),'UNAVAILABLE','unknown');
});
test('Gate6J stale lease refresh cannot close or renew a resumed client',async t=>{
  let finish;const f=fixture6j(t,{grant:(g,_,n)=>n===2?new Promise(r=>{finish=()=>r({...g,hostAuthorized:false});}):({...g,validForMs:n===1?40:5000})});
  await f.run();await new Promise(r=>setTimeout(r,25));assert.equal(typeof finish,'function');
  await f.run('pause');const reply=await f.run();assert.equal(reply.outcome.kind,'acknowledged');
  finish();await wait6j();assert.equal(f.clients[1].left,0);f.clients[1].emit();assert.equal(f.packets.length,1);
});
test('Gate6J SDK leave during pending completion cannot become a listening acknowledgment',async t=>{
  let f;f=fixture6j(t,{beforeSave:({saves})=>{if(saves===3)f.clients[0].callbacks.leave(0);}});
  failure6d(await f.run(),'UNAVAILABLE','unknown');assert.equal(f.clients[0].left,1);f.clients[0].emit();assert.equal(f.packets.length,0);
});
// K135Z_GATE6J_COMMAND_TRANSPORT_TESTS_END

const {createK135zRtmsGrantResolver:resolver6l}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
async function fixture6l(t,o={}) {
  const f=fixture6f(),repository=new R.MemoryZoomRepository(),clients=[],packets=[];let leaseMs=5000;
  f.row.bindingRevision=f.row.record.snapshot.context.generation;
  const original=f.client.rpc.bind(f.client);
  f.client.rpc=async(name,args)=>args.operation==='capture_lease'
    ? {data:{...structuredClone(f.row),validForMs:leaseMs},error:null}:original(name,args);
  const vault=new V.ZoomTokenVault({repository,cipher:new V.EnvelopeCipher(Buffer.alloc(32,7)),clock:()=>now6h-10});
  await vault.storeConnection(P,{access_token:'fixture-access',refresh_token:'fixture-refresh',expires_in:3600,
    account_id:'account-6l',user_id:'host-6l',scope:'meeting:read:meeting_transcripts'});
  class Client {
    constructor(){this.callbacks={};this.left=0;clients.push(this);}
    onJoinConfirm(fn){this.callbacks.join=fn;return true;} onTranscriptData(fn){this.callbacks.text=fn;return true;}
    onLeave(fn){this.callbacks.leave=fn;return true;}
    join(input){this.input=input;this.callbacks.join(0);return true;} leave(){this.left++;return true;}
    emit(){const b=Buffer.from('verified meeting');this.callbacks.text(b,b.length,10,{userId:1,userName:'Host',startTs:1,endTs:10});}
  }
  const sdk={Client,RTMS_SDK_OK:0,configureLogger(){}};
  const deps=Z.createK135zZoomDependencies({...f.base.wiring,repository,env:{NODE_ENV:'test',
    KORLIX_ZOOM_CLIENT_ID:'client-6l',KORLIX_ZOOM_CLIENT_SECRET:'secret-6l'},workspaceCommandClient:f.client,
    rtmsSdk:sdk,onRtmsTranscript:p=>{packets.push(p);return true;},
    webhookVerifier:new Verifier6h({secret:secret6h,clock:()=>now6h})});
  t.after(()=>deps.workspaceTransport.close());const handlers=Z.createK135zZoomHandlers(deps);
  const event=(status='started',fields={},ts=now6h)=>({event:'meeting.rtms_'+status,event_ts:ts,
    payload:{meeting_uuid:f.row.record.snapshot.context.meetingUuid,rtms_stream_id:'stream-6l',
      ...(status==='started'?{account_id:'account-6l',operator_id:'host-6l',is_original_host:true,server_urls:'wss://rtms.zoom.us'}:{}),...fields}});
  const deliver=async(body,alter=false)=>{
    const req=request6h(Buffer.from(JSON.stringify(body)));if(alter)req.rawBody=Buffer.concat([req.rawBody,Buffer.from(' ')]);
    const res={status(n){this.statusCode=n;return this;},json(x){this.body=x;return x;}};await handlers.webhook(req,res);return res;
  };
  const source=()=>repository.getCaptureSource({key:C.identityKey(P),meetingUuid:f.row.record.snapshot.context.meetingUuid,streamId:null});
  if(o.start!==false)assert.equal((await deliver(event())).statusCode,200);
  return {...f,repository,clients,packets,deps,event,deliver,source,setLease:n=>{leaseMs=n;},
    run:(action='start')=>deps.workspaceCommands.request(f.base.req,f.make(action),cancel6d())};
}
test('Gate6L signed owned host plus database consent joins through the shared factory',async t=>{
  const f=await fixture6l(t);assert.equal((await f.run()).outcome.kind,'acknowledged');assert.equal(f.clients.length,1);
  assert.equal(f.clients[0].input.signature,crypto6h.createHmac('sha256','secret-6l')
    .update(['client-6l',f.row.record.snapshot.context.meetingUuid,'stream-6l'].join(',')).digest('hex'));
  f.clients[0].emit();assert.equal(f.packets.length,1);assert.equal(f.row.record.pending,null);
});
test('Gate6L unsigned Start cannot create a capture source or join',async t=>{
  const f=await fixture6l(t,{start:false});assert.equal((await f.deliver(f.event(),true)).statusCode,401);
  assert.equal(await f.source(),null);failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);
});
test('Gate6L another Zoom user account or non-host Start cannot authorize capture',async t=>{
  for(const fields of [{operator_id:'someone-else'},{account_id:'other-account'},{is_original_host:false}]) {
    const f=await fixture6l(t,{start:false});await f.deliver(f.event('started',fields));
    assert.equal(await f.source(),null);failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);
  }
});
test('Gate6L webhook host proof alone cannot issue listening consent',async t=>{
  const f=await fixture6l(t);f.row.authority.listeningAuthorized=false;
  failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);assert.equal(f.row.authority.listeningAuthorized,false);
});
test('Gate6L missing transcript scope or a newer OAuth connection rejects old stream proof',async t=>{
  for(const fields of [{scope:'meeting:read'},{connectedAtMs:now6h+1}]) {
    const f=await fixture6l(t),key=C.identityKey(P),record=await f.repository.getConnection(key);
    await f.repository.saveConnection(key,{...record,...fields});failure6d(await f.run(),'DENIED');assert.equal(f.clients.length,0);
  }
});
test('Gate6L ambiguous active streams require an exact stream binding',async t=>{
  const f=await fixture6l(t);await f.deliver(f.event('started',{rtms_stream_id:'second-stream'},now6h+1));
  assert.equal(await f.source(),null);failure6d(await f.run(),'DENIED');
  const one=await f.repository.getCaptureSource({key:C.identityKey(P),meetingUuid:f.row.record.snapshot.context.meetingUuid,streamId:'stream-6l'});
  assert.equal(one.streamId,'stream-6l');
});
test('Gate6L Pause and Stop release capture even after provider deauthorization',async t=>{
  const f=await fixture6l(t);await f.run();await f.repository.deleteConnection(C.identityKey(P));
  assert.equal((await f.run('pause')).outcome.kind,'acknowledged');assert.equal(f.clients[0].left,1);
  assert.equal((await f.run('stop')).outcome.kind,'acknowledged');
});
test('Gate6L provider Stop is observed during grant refresh and late packets are discarded',async t=>{
  const f=await fixture6l(t);f.setLease(120);await f.run();await f.deliver(f.event('stopped'));
  await new Promise(r=>setTimeout(r,160));assert.equal(f.clients[0].left,1);f.clients[0].emit();assert.equal(f.packets.length,0);
});
test('Gate6L disconnected provider is observed during grant refresh without reconnecting',async t=>{
  const f=await fixture6l(t);f.setLease(120);await f.run();await f.repository.deleteConnection(C.identityKey(P));
  await new Promise(r=>setTimeout(r,160));assert.equal(f.clients[0].left,1);assert.equal(f.clients.length,1);
});
test('Gate6L zero database lease denies Start but permits Stop from ready',async t=>{
  const f=await fixture6l(t);f.setLease(0);failure6d(await f.run(),'DENIED');
  assert.equal((await f.run('stop')).outcome.kind,'acknowledged');assert.equal(f.clients.length,0);
});
test('Gate6L authority changes during provider lookup invalidate the grant',async t=>{
  const f=await fixture6l(t),read=f.repository.getCaptureSource.bind(f.repository);
  f.repository.getCaptureSource=async(...args)=>{const result=await read(...args);f.row.authorityRevision++;return result;};
  failure6d(await f.run(),'CONFLICT');assert.equal(f.clients.length,0);
});
test('Gate6L stale or legacy metadata cannot manufacture a verified source',async t=>{
  const f=await fixture6l(t,{start:false}),body=f.event();delete body.payload.operator_id;delete body.payload.is_original_host;
  await f.deliver(body);assert.equal(await f.source(),null);failure6d(await f.run(),'DENIED');
});
test('Gate6L malformed host flags and foreign endpoints are rejected before storage',async t=>{
  const f=await fixture6l(t,{start:false});for(const fields of [{is_original_host:'true'},{server_urls:'wss://evil.invalid'},
    {server_urls:'wss://name:password@rtms.zoom.us'},{server_urls:'https://rtms.zoom.us'}])
    assert.equal((await f.deliver(f.event('started',fields))).statusCode,400);
  assert.equal(f.repository.webhookEvents.size,0);
});
test('Gate6L bounded resolver timeout aborts a stuck lookup and never joins late',async t=>{
  const f=await fixture6l(t);let signal,finish;
  const repository={getCaptureSource:(_,o)=>{signal=o.signal;return new Promise(r=>{finish=r;});}};
  const resolve=resolver6l({store:f.store,repository,clientId:'client',clientSecret:'secret',timeoutMs:10});
  await reject6f(resolve({principal:P,context:f.row.record.snapshot.context,signal:new AbortController().signal}),'TIMEOUT');
  assert.equal(signal.aborted,true);finish(await f.source());assert.equal(f.clients.length,0);
});
test('Gate6L already cancelled resolver makes no permission or provider call',async()=>{
  let calls=0;const resolve=resolver6l({store:{readCaptureLease(){calls++;}},repository:{getCaptureSource(){calls++;}},clientId:'client',clientSecret:'secret'});
  const abort=new AbortController();abort.abort();
  await reject6f(resolve({principal:P,context:ctx6i,signal:abort.signal}),'CANCELLED');assert.equal(calls,0);
});
test('Gate6L capture lease decoder rejects oversized TTL wrong generation and extra fields',async t=>{
  const f=await fixture6l(t);for(const change of [{validForMs:60001},{bindingRevision:999},{extra:true}]) {
    f.client.rpc=async()=>({data:{...structuredClone(f.row),validForMs:1000,...change}});
    await reject6f(f.store.readCaptureLease({principal:P,context:f.row.record.snapshot.context}), 'PROTOCOL_ERROR');
  }
});
test('Gate6L source RPC rejects foreign response bindings and passes cancellation to the client',async()=>{
  const query={key:C.identityKey(P),meetingUuid:'m',streamId:'s'},abort=new AbortController();let signal;
  const repository=new R.SupabaseZoomRepository({client:{rpc(name,args){assert.equal(args.operation,'capture_source');assert.deepEqual(args.payload,query);
    return {abortSignal(value){signal=value;return Promise.resolve({data:{meetingUuid:'other',streamId:'s',serverUrls:'wss://rtms.zoom.us'}});}};}}});
  await assert.rejects(repository.getCaptureSource(query,{signal:abort.signal}),{code:'ZOOM_CAPTURE_BINDING_INVALID'});assert.equal(signal,abort.signal);
});
test('Gate6L default production remains disabled and explicit SDK requires all server dependencies',()=>{
  assert.equal(Z.createK135zZoomDependencies({env:{NODE_ENV:'production'}}).workspaceCommands.adapter,null);
  assert.throws(()=>Z.createK135zZoomDependencies({env:{NODE_ENV:'test'},rtmsSdk:{Client(){},RTMS_SDK_OK:0}}));
});

// Gate6M HTTP boundaries use the existing verified-user wiring.
const {EventEmitter}=require('node:events');
function fixture6m(o={}) {
  const f=fixture(o),calls=[];let finish;
  const row={...fixture6f().row,validForMs:12000};
  const store={async readCaptureLease(v){calls.push(['status',v]);return row;},
    async bindWorkspace(v){calls.push(['bind',v]);return row;},async changeConsent(v){calls.push(['consent',v]);return row;}};
  const deps=Z.createK135zZoomDependencies({...f.wiring,env:{NODE_ENV:'test'},workspaceHttpEnabled:o.enabled!==false,
    workspaceCommandStore:store});
  const h=Z.createK135zZoomHandlers(deps);
  const req=Object.assign(new EventEmitter(),f.req,{body:{},headers:{authorization:'Bearer fixture-token',
    'content-type':'application/json','x-korlix-agent-id':'nova'}});
  const res=Object.assign(new EventEmitter(),{status(n){this.statusCode=n;return this;},json(v){this.body=v;return this;},
    setHeader(k,v){this.headers??={};this.headers[k]=v;}});
  return {f,deps,h,store,row,req,res,calls,async run(name='workspaceStatus',body={}){req.body=body;await h[name](req,res);return res;}};
}
test('Gate6M HTTP registration requires explicit server opt-in',()=>{
  for(const enabled of [undefined,false,true]){
    const paths=[],app={get(){},delete(){},post(p){paths.push(p);}};
    Z.registerK135zZoomRoutes(app,{env:{NODE_ENV:'test'},workspaceHttpEnabled:enabled});
    assert.equal(paths.filter(p=>p.includes('/workspace/')).length,enabled===true?4:0);
  }
});
test('Gate6M disabled handlers cannot authenticate or read storage',async()=>{
  const f=fixture6m({enabled:false});assert.equal((await f.run()).statusCode,503);
  assert.equal(f.f.calls.length,0);assert.equal(f.calls.length,0);
});
test('Gate6M HTTP requires bearer authentication and JSON before storage',async()=>{
  for(const [headers,status] of [[{},401],[{authorization:'Bearer x'},415],
    [{authorization:'Bearer a,b','content-type':'application/json'},401]]){
    const f=fixture6m();f.req.headers=headers;assert.equal((await f.run()).statusCode,status);assert.equal(f.calls.length,0);
  }
});
test('Gate6M HTTP authenticates current Enterprise and agent ownership',async()=>{
  for(const [o,code] of [[{noUser:true},401],[{tier:'basic'},403],[{noAgent:true},403]]){
    const f=fixture6m(o);assert.equal((await f.run()).statusCode,code);assert.equal(f.calls.length,0);
  }
});
test('Gate6M HTTP rejects forged host identity secret and duration fields',async()=>{
  for(const body of [{hostAuthorized:true},{principal:P},{signature:'forged'},{leaseSeconds:600}]){
    const f=fixture6m();assert.equal((await f.run('workspaceStatus',body)).statusCode,400);assert.equal(f.calls.length,0);
  }
  for(const listeningConsent of [undefined,false,'true']){
    const f=fixture6m(),r=f.row;
    const body={action:'consent',context:r.record.snapshot.context,bindingRevision:r.bindingRevision,authorityRevision:r.authorityRevision};
    if(listeningConsent!==undefined)body.listeningConsent=listeningConsent;
    assert.equal((await f.run('workspaceConsent',body)).statusCode,400);assert.equal(f.calls.length,0);
  }
});
test('Gate6M HTTP status is read-only and excludes internal provider fields',async()=>{
  const f=fixture6m();f.row.signature='fixture-secret';f.row.serverUrls='wss://rtms.zoom.us';
  const r=await f.run();assert.equal(r.statusCode,200);assert.equal(f.calls.length,1);
  assert.equal(f.calls[0][0],'status');assert.deepEqual(f.calls[0][1].principal,P);
  assert.equal(r.headers['Cache-Control'],'no-store');assert(!JSON.stringify(r.body).includes('fixture-secret'));
  assert(!JSON.stringify(r.body).includes('serverUrls'));assert.equal(f.req.listenerCount('aborted'),0);assert.equal(f.res.listenerCount('close'),0);
});
test('Gate6M HTTP bind and consent pass only validated input with verified principal',async()=>{
  const f=fixture6m();assert.equal((await f.run('workspaceBind',{meetingUuid:'meeting',expectedBindingRevision:0})).statusCode,200);
  const row=f.row,body={action:'renew',context:row.record.snapshot.context,bindingRevision:row.bindingRevision,authorityRevision:row.authorityRevision};
  assert.equal((await f.run('workspaceConsent',body)).statusCode,200);assert.deepEqual(f.calls[1][1].principal,P);
  assert.deepEqual(f.calls[1][1].request,body);assert.equal(f.calls[1][1].signal.aborted,false);
});
test('Gate6M HTTP errors suppress storage details and forbid automatic retry',async()=>{
  const f=fixture6m();f.store.readCaptureLease=async()=>{throw Object.assign(Error('private-secret'),{code:'CONFLICT'});};
  const r=await f.run();assert.equal(r.statusCode,409);assert.equal(r.body.error.automaticRetry,false);
  assert(!JSON.stringify(r.body).includes('private-secret'));
});
test('Gate6M HTTP disconnect during authentication prevents a late storage mutation',async()=>{
  const f=fixture6m();let release;f.deps.authenticateRequest=()=>new Promise(r=>{release=r;});
  const job=f.run('workspaceBind',{meetingUuid:'meeting',expectedBindingRevision:0});
  f.req.emit('aborted');await job;release(P);await new Promise(r=>setImmediate(r));assert.equal(f.calls.length,0);
  assert.equal(f.res.statusCode,499);assert.equal(f.req.listenerCount('aborted'),0);
});
test('Gate6M HTTP disconnect propagates cancellation to a dispatched command',async()=>{
  const f=fixture6m();let cancel,token;
  f.deps.workspaceCommands={request(req,body,cancellation){token=cancellation;return new Promise(r=>{
    cancellation.subscribe(()=>{cancel=true;r({ignored:true});});});}};
  const request=request6d();const job=f.run('workspaceCommand',request);f.res.emit('close');await job;
  assert.equal(cancel,true);assert.equal(token.isCancelled(),true);assert.equal(f.res.statusCode,499);
});
test('Gate6M HTTP command uses the existing authenticated command boundary',async()=>{
  const f=fixture6m({noUser:true});const r=await f.run('workspaceCommand',request6d());
  assert.equal(r.statusCode,200);assert.equal(r.body.reply.outcome.kind,'failed');assert.equal(r.body.reply.outcome.error.code,'DENIED');
  assert.equal(f.calls.length,0);
});
test('Gate6M store abort cancels the RPC and discards a late response',async()=>{
  const {K135zSupabaseWorkspaceStore}=require('../k135z_zoom/zoom_rtms_session_manager.cjs');
  let finish,observed,calls=0;const abort=new AbortController();
  const store=new K135zSupabaseWorkspaceStore({client:{rpc(){calls++;return {abortSignal(s){observed=s;return new Promise(r=>{finish=r;});}};}}});
  const pending=store.readCaptureLease({principal:P,signal:abort.signal});await new Promise(r=>setImmediate(r));abort.abort();
  await assert.rejects(pending,{code:'CANCELLED'});assert.equal(observed.aborted,true);finish({data:fixture6f().row,error:null});
  await assert.rejects(()=>store.readCaptureLease({principal:P,signal:abort.signal}),{code:'CANCELLED'});assert.equal(calls,1);
});

test('Gate6N capture health requires the owned durable live SDK session',async t=>{
  const f=fixture6j(t),active=()=>f.transport.captureActive({principal:P,context:f.row.record.snapshot.context});
  assert.equal(active(),false);await f.run();assert.equal(active(),true);
  assert.equal(f.transport.captureActive({principal:{...P,agentId:'other'},context:f.row.record.snapshot.context}),false);
  assert.equal(f.transport.captureActive({principal:P,context:{...f.row.record.snapshot.context,streamId:'other'}}),false);
  await f.run('pause');assert.equal(active(),false);await f.run('start');assert.equal(active(),true);
  f.advance(5001);assert.equal(active(),false);
});
test('Gate6N remote close and missing transport cannot claim live capture',async t=>{
  const f=fixture6j(t);await f.run();f.clients[0].callbacks.leave(0);
  assert.equal(f.transport.captureActive({principal:P,context:f.row.record.snapshot.context}),false);
  const h=fixture6m();assert.equal((await h.run()).body.workspace.captureActive,false);
});

// K135Z_GATE6O_RUNTIME_TESTS_BEGIN
const env6o={NODE_ENV:'test',KORLIX_K135Z_WORKSPACE_ENABLED:'true',
  KORLIX_ZOOM_CLIENT_ID:'client-6l',KORLIX_ZOOM_CLIENT_SECRET:'secret-6l'};
function sdk6o() {
  const clients=[];
  class Client {
    constructor(){this.callbacks={};this.left=0;clients.push(this);}
    onJoinConfirm(fn){this.callbacks.join=fn;return true;}
    onTranscriptData(fn){this.callbacks.text=fn;return true;}
    onLeave(fn){this.callbacks.leave=fn;return true;}
    join(){this.callbacks.join(0);return true;} leave(){this.left++;return true;}
    emit(){const b=Buffer.from('runtime transcript');this.callbacks.text(b,b.length,10,
      {userId:1,userName:'Host',startTs:1,endTs:10});}
  }
  return {clients,sdk:{Client,RTMS_SDK_OK:0,configureLogger(){}}};
}
const packet6o=()=>({context:context6d,text:'meeting text',providerTimestamp:10,
  userId:1,userName:'Host',startTs:1,endTs:10});
async function runtime6o() {
  const f=fixture(),s=sdk6o(),runtime=await Z.createK135zServerRuntime({env:env6o,
    database:f.database,loadSdk:async()=>s.sdk});
  const deps=Z.createK135zZoomDependencies({...f.wiring,env:env6o,...runtime.options});
  runtime.attach(deps);return {f,...s,runtime,deps};
}
test('Gate6O disabled runtime does not load SDK or read database',async()=>{
  for(const flag of [undefined,'','false']){
    let loads=0;const r=await Z.createK135zServerRuntime({env:{KORLIX_K135Z_WORKSPACE_ENABLED:flag},
      loadSdk(){loads++;throw Error('unexpected');}});
    assert.equal(r.enabled,false);assert.deepEqual(r.options,{});assert.equal(loads,0);
    r.attach(Z.createK135zZoomDependencies({env:{NODE_ENV:'test'}}));r.bindServer(null);assert.equal(r.close(),true);
  }
});
test('Gate6O rejects malformed enable flags and missing privileged client',async()=>{
  for(const flag of [true,'TRUE',' true','1'])await assert.rejects(Z.createK135zServerRuntime({env:{KORLIX_K135Z_WORKSPACE_ENABLED:flag}}),{code:'K135Z_WORKSPACE_FLAG_INVALID'});
  for(const database of [undefined,{}, {rpc(){}}])await assert.rejects(
    Z.createK135zServerRuntime({env:env6o,database}),{code:'K135Z_WORKSPACE_DATABASE_REQUIRED'});
});
test('Gate6O validates credentials before SDK loading and hides loader errors',async()=>{
  const f=fixture();let loads=0;
  await assert.rejects(Z.createK135zServerRuntime({env:{...env6o,KORLIX_ZOOM_CLIENT_SECRET:''},database:f.database,
    loadSdk(){loads++;}}),{code:'K135Z_WORKSPACE_CREDENTIALS_REQUIRED'});assert.equal(loads,0);
  await assert.rejects(Z.createK135zServerRuntime({env:env6o,database:f.database,
    loadSdk(){throw Error('secret-sdk-path');}}),e=>e.code==='K135Z_RTMS_SDK_UNAVAILABLE'&&!e.message.includes('secret-sdk-path'));
});
test('Gate6O rejects SDK without the required native interface',async()=>{
  for(const sdk of [{},{Client(){},RTMS_SDK_OK:0,configureLogger(){}}])
    await assert.rejects(Z.createK135zServerRuntime({env:env6o,database:fixture().database,loadSdk:async()=>sdk}),{code:'K135Z_RTMS_SDK_INVALID'});
});
test('Gate6O composes shared RPC client and workspace routes without joining',async()=>{
  const f=await runtime6o(),paths=[];
  assert.equal(f.runtime.options.workspaceCommandClient,f.f.database);
  Z.registerK135zZoomRoutes({get(){},delete(){},post(p){paths.push(p);}},
    {...f.f.wiring,env:env6o,...f.runtime.options});
  assert.equal(paths.filter(p=>p.includes('/workspace/')).length,5);
  assert.equal(f.f.calls.length,0);assert.equal(f.clients.length,0);assert.equal(f.deps.transport.liveEnabled,false);
  assert.equal(f.runtime.close(),true);
});
test('Gate6O composition retains Enterprise and agent authorization',async()=>{
  const f=fixture({tier:'basic'}),s=sdk6o(),r=await Z.createK135zServerRuntime({env:env6o,database:f.database,loadSdk:async()=>s.sdk});
  const d=Z.createK135zZoomDependencies({...f.wiring,env:env6o,...r.options});r.attach(d);
  failure6d(await d.workspaceCommands.request(f.req,request6d(),cancel6d()),'DENIED');
  assert.equal(s.clients.length,0);r.close();
});
test('Gate6O runtime accepts only durably active SDK transcripts and closes capture',async t=>{
  const f=await fixture6l(t),s=sdk6o();f.client.from=f.base.database.from;
  const r=await Z.createK135zServerRuntime({env:env6o,database:f.client,loadSdk:async()=>s.sdk});
  const d=Z.createK135zZoomDependencies({...f.base.wiring,env:env6o,repository:f.repository,...r.options});r.attach(d);t.after(()=>r.close());
  assert.equal(r.options.onRtmsTranscript(packet6o()),false);
  const run=action=>d.workspaceCommands.request(f.base.req,f.make(action),cancel6d());
  assert.equal((await run('start')).outcome.kind,'acknowledged');s.clients[0].emit();
  assert.equal(r.inbox.status().queued,1);assert.equal(r.inbox.status().persisted,false);
  assert.equal((await run('pause')).outcome.kind,'acknowledged');s.clients[0].emit();assert.equal(r.inbox.status().queued,1);
  assert.equal((await run('start')).outcome.kind,'acknowledged');s.clients[1].emit();assert.equal(r.inbox.status().queued,2);
  const ctx=f.row.record.snapshot.context;assert.equal(d.workspaceTransport.captureActive({principal:P,context:ctx}),true);
  assert.equal(r.close(),true);assert.equal(d.workspaceTransport.captureActive({principal:P,context:ctx}),false);
  assert.equal(r.inbox.status().queued,0);assert.equal(s.clients[1].left,1);assert.equal(r.close(),true);
});
test('Gate6O inbox separates complete contexts and freezes captured packets',()=>{
  const q=Z.createK135zTranscriptInbox(),p=packet6o();assert.equal(q.accept(p),true);p.text='changed';
  for(const key of ['agentId','meetingUuid','streamId','sessionId','tenantId','userId'])
    assert.deepEqual(q.take({...context6d,[key]:'other'}),[]);
  assert.deepEqual(q.take({...context6d,generation:8}),[]);
  const out=q.take(context6d);assert.equal(out[0].text,'meeting text');assert(Object.isFrozen(out[0].context));
  assert.deepEqual(q.status(),{queued:0,bytes:0,closed:false,persisted:false});q.close();
});
test('Gate6O inbox enforces packet and byte limits without evicting accepted text',()=>{
  const p=packet6o(),bytes=NC.bytes(p),q=Z.createK135zTranscriptInbox({maxPackets:1,maxBytes:bytes});
  assert.equal(q.accept(p),true);assert.equal(q.accept({...p,text:'second'}),false);
  assert.equal(q.take(context6d)[0].text,p.text);assert.equal(q.accept(p),true);q.close();assert.equal(q.accept(p),false);
  const small=Z.createK135zTranscriptInbox({maxBytes:bytes-1});assert.equal(small.accept(p),false);
  assert.throws(()=>Z.createK135zTranscriptInbox({maxPackets:0}));
});
test('Gate6O inbox rejects malformed provider data without retaining it',()=>{
  const q=Z.createK135zTranscriptInbox(),p=packet6o();
  for(const value of [{...p,text:''},{...p,endTs:0},{...p,userId:-1},{...p,text:'x'.repeat(8193)},
    {...p,userName:'x'.repeat(257)},{...p,context:{...p.context,streamId:null}},{...p,secret:'unexpected'}])assert.equal(q.accept(value),false);
  assert.equal(q.status().queued,0);q.close();
});
test('Gate6O runtime rejects duplicate mismatched and post-close attachment',async()=>{
  const f=await runtime6o();assert.throws(()=>f.runtime.attach(f.deps));f.runtime.close();assert.throws(()=>f.runtime.attach(f.deps));
  const r=await Z.createK135zServerRuntime({env:{}});assert.throws(()=>r.attach({workspaceHttpEnabled:true}));r.close();
});
test('Gate6O signal shutdown releases capture before HTTP and removes listeners',async()=>{
  const f=await runtime6o(),events=[],life=Object.assign(new EventEmitter(),{exit:n=>events.push(['exit',n])});
  f.deps.workspaceTransport={captureActive:()=>false,close(){events.push(['capture']);return true;}};
  const server=Object.assign(new EventEmitter(),{close(fn){events.push(['http']);this.emit('close');fn();}});
  f.runtime.bindServer(server,{lifecycle:life});life.emit('SIGTERM');life.emit('SIGINT');
  assert.deepEqual(events,[['capture'],['http'],['exit',0]]);assert.equal(life.listenerCount('SIGTERM'),0);
  assert.equal(life.listenerCount('SIGINT'),0);assert.equal(f.runtime.inbox.status().closed,true);
});
test('Gate6O hanging HTTP shutdown is bounded and does not report success',async()=>{
  const f=await runtime6o(),events=[],life=Object.assign(new EventEmitter(),{exit:n=>events.push(n)});
  const server=Object.assign(new EventEmitter(),{close(){},closeAllConnections(){events.push('forced');}});
  f.runtime.bindServer(server,{lifecycle:life,shutdownMs:5});life.emit('SIGINT');
  await new Promise(r=>setTimeout(r,20));assert.deepEqual(events,['forced',1]);assert.equal(life.listenerCount('SIGTERM'),0);
});
test('Gate6O failed native release produces unsuccessful shutdown exactly once',async()=>{
  const f=await runtime6o(),exits=[],life=Object.assign(new EventEmitter(),{exit:n=>exits.push(n)});
  f.deps.workspaceTransport={captureActive:()=>false,close(){throw Error('native failure');}};
  const server=Object.assign(new EventEmitter(),{close(fn){fn();fn();}});
  f.runtime.bindServer(server,{lifecycle:life});life.emit('SIGTERM');assert.deepEqual(exits,[1]);assert.equal(f.runtime.close(),false);
});
test('Gate6O normal server closure releases capture without exiting the process',async()=>{
  const f=await runtime6o(),exits=[],life=Object.assign(new EventEmitter(),{exit:n=>exits.push(n)});
  const server=Object.assign(new EventEmitter(),{close(){}});f.runtime.bindServer(server,{lifecycle:life});server.emit('close');
  assert.equal(f.runtime.inbox.status().closed,true);assert.deepEqual(exits,[]);assert.equal(life.listenerCount('SIGINT'),0);
});
test('Gate6O actual server passes runtime options and binds the listening server',async()=>{
  const chunk=source.split('// K135Z_B5A_ZOOM_SERVER_REGISTRATION_BEGIN')[1].split('// K135Z_B5A_ZOOM_SERVER_REGISTRATION_END')[0];
  const observed=[],runtime={options:{workspaceHttpEnabled:true},attach:d=>observed.push(['attach',d])},database={};
  const run=vm.runInNewContext('(async()=>{'+chunk+'})',{process:{env:{}},supabaseAdmin:database,
    createK135zServerRuntime:async opts=>{assert.equal(opts.database,database);return runtime;},
    app:{},requireUser(){},korlixAgentLoadProfileV1(){},createK135zGate5Wiring:()=>({trusted:true}),
    registerK135zZoomRoutes:(_,opts)=>{assert.equal(opts.workspaceHttpEnabled,true);assert.equal(opts.trusted,true);return {dependencies:'deps'};}});
  await run();assert.deepEqual(observed,[['attach','deps']]);
  assert(source.includes('k135zServerRuntime.bindServer(k135zHttpServer);'));
});
// K135Z_GATE6O_RUNTIME_TESTS_END

// K135Z_GATE6P_PREVIEW_TESTS_BEGIN
function preview6p(o={}) {
  const f=fixture6m(o),inbox=Z.createK135zTranscriptInbox();
  const ctx={...f.row.record.snapshot.context,streamId:'preview-stream'};
  f.row.record.snapshot.context=ctx;f.row.authority.context=ctx;
  f.deps.workspaceTranscriptPreview=c=>inbox.preview(c);
  const packet=(text='Authorized caption')=>({...packet6o(),context:ctx,text});
  return {...f,inbox,ctx,packet,preview:()=>f.run('workspaceTranscript',{context:ctx})};
}
test('Gate6P preview requires current Enterprise and selected agent before reading captions',async()=>{
  for(const o of [{noUser:true},{tier:'basic'},{noAgent:true}]){
    const f=preview6p(o);f.inbox.accept(f.packet());const res=await f.preview();
    assert([401,403].includes(res.statusCode));assert.equal(f.calls.length,0);assert.equal(f.inbox.status().queued,1);
  }
});
test('Gate6P preview requires the exact current owned context and viewer authority',async()=>{
  for(const change of [{agentId:'other'},{tenantId:OTHER,userId:OTHER},{streamId:'other'},{generation:99}]){
    const f=preview6p();f.inbox.accept(f.packet());
    assert.equal((await f.run('workspaceTranscript',{context:{...f.ctx,...change}})).statusCode,409);
    assert.equal(f.inbox.status().queued,1);
  }
  const f=preview6p();f.row.authority.viewerAuthorized=false;
  assert.equal((await f.preview()).statusCode,403);
});
test('Gate6P authorized preview drains into stable repeated history without persisting',async()=>{
  const f=preview6p();assert.equal(f.inbox.accept(f.packet()),true);
  const res=await f.preview(),first=res.body.transcript;
  assert.equal(res.statusCode,200);assert.equal(res.headers['Cache-Control'],'no-store');
  assert.equal(first.lines[0].text,'Authorized caption');assert.equal(first.persisted,false);assert.equal(first.coverage,'partial');
  assert.equal(f.inbox.status().queued,0);assert.deepEqual((await f.preview()).body.transcript,first);
  assert.equal(f.calls.every(x=>x[0]==='status'),true);assert(!JSON.stringify(first).includes('signature'));
});
test('Gate6P preview retains separate histories for separate agents',()=>{
  const q=Z.createK135zTranscriptInbox(),a=packet6o(),b={...a,context:{...a.context,agentId:'second'},text:'Other agent'};
  q.accept(a);q.accept(b);assert.equal(q.preview(a.context).lines[0].text,a.text);
  assert.equal(q.status().queued,1);assert.equal(q.preview(b.context).lines[0].text,b.text);
  assert.equal(q.preview(a.context).lines.length,1);q.close();
});
test('Gate6P rebinding clears older queued and cached text for that agent',()=>{
  const q=Z.createK135zTranscriptInbox(),a=packet6o(),ctx={...a.context,generation:a.context.generation+1,sessionId:'new'};
  q.accept(a);const old=q.preview(a.context);q.accept(a);
  const next=q.preview(ctx);assert.equal(next.lines.length,0);assert.notEqual(next.windowId,old.windowId);assert.equal(q.status().queued,0);
});
test('Gate6P bounded recent window reports truncation instead of claiming complete history',()=>{
  const q=Z.createK135zTranscriptInbox(),p=packet6o();
  for(let i=0;i<65;i++)assert.equal(q.accept({...p,text:'Caption '+i}),true);
  const view=q.preview(p.context);assert.equal(view.lines.length,50);assert.equal(view.lines[0].sequence,16);
  assert.equal(view.revision,65);assert.equal(view.truncated,true);assert.equal(view.coverage,'partial');
  for(let i=0;i<10;i++){q.accept({...p,text:'z'.repeat(8192)});q.preview(p.context);}
  assert(Buffer.byteLength(JSON.stringify(q.preview(p.context)))<65536);q.close();
});
test('Gate6P preview cache eviction resets the window identity and remains isolated',()=>{
  const q=Z.createK135zTranscriptInbox(),p=packet6o();q.accept(p);const first=q.preview(p.context);
  for(let i=0;i<65;i++)q.preview({...p.context,agentId:'agent-'+i});
  const again=q.preview(p.context);assert.notEqual(again.windowId,first.windowId);assert.equal(again.lines.length,0);
  q.close();assert.throws(()=>q.preview(p.context),{code:'K135Z_TRANSCRIPT_UNAVAILABLE'});
});
test('Gate6P cancelled preview cannot drain captions after a late storage response',async()=>{
  const f=preview6p();f.inbox.accept(f.packet());let release;
  f.store.readCaptureLease=()=>new Promise(r=>{release=()=>r(f.row);});
  const pending=f.preview();while(!release)await new Promise(r=>setImmediate(r));
  f.req.emit('aborted');await pending;release();await new Promise(r=>setImmediate(r));
  assert.equal(f.res.statusCode,499);assert.equal(f.inbox.status().queued,1);
});
test('Gate6P malformed preview bodies and absent runtime return no captions',async()=>{
  const f=preview6p();
  assert.equal((await f.run('workspaceTranscript',{context:f.ctx,hostAuthorized:true})).statusCode,400);
  assert.equal(f.calls.length,0);delete f.deps.workspaceTranscriptPreview;
  assert.equal((await f.preview()).statusCode,503);
});
test('Gate6P paused and stopped sessions can read already captured captions without restarting',async()=>{
  for(const state of ['paused','stopped']){
    const f=preview6p();f.row.record.snapshot.state=state;f.row.validForMs=0;
    f.inbox.accept(f.packet());const r=await f.preview();assert.equal(r.statusCode,200);
    assert.equal(r.body.transcript.lines.length,1);assert.equal(f.calls.every(x=>x[0]==='status'),true);
  }
});
// K135Z_GATE6P_PREVIEW_TESTS_END

// K135Z_GATE6R_OAUTH_HTTP_TESTS_BEGIN
const token6r=()=>({access_token:'fixture-access',refresh_token:'fixture-refresh',token_type:'bearer',
  expires_in:3600,scope:'user:read:user meeting:read:list_upcoming_meetings',api_url:'https://api.zoom.us'});
const input6r={code:'fixture-code',clientId:'fixture-client',clientSecret:'fixture-secret',redirectUri:'https://app.example.test/callback'};
const json6r=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
function http6r(replies,extra={}){const calls=[];const transport=Z.createK135zOAuthHttpTransport({enabled:true,
  fetchImpl:async(url,options)=>{calls.push({url,...options});const next=replies.shift();
    return typeof next==='function'?next(url,options):json6r(next);},...extra});return {transport,calls};}
test('Gate6R prepared adapter is disabled by default and old production factory stays disabled',async()=>{
  let calls=0;const transport=Z.createK135zOAuthHttpTransport({fetchImpl:()=>{calls++;throw Error('unexpected');}});
  await assert.rejects(transport.exchangeAuthorizationCode(input6r),{code:'ZOOM_LIVE_TRANSPORT_DISABLED'});
  await assert.rejects(transport.listUpcomingMeetings({accessToken:'fixture'}),{code:'ZOOM_LIVE_TRANSPORT_DISABLED'});
  assert.equal(calls,0);assert.equal(Z.createFetchZoomTransport({enabled:true}).liveEnabled,false);
});
test('Gate6R exchanges exact OAuth form and resolves identity from authorized user profile',async()=>{
  const f=http6r([{...token6r(),account_id:'untrusted-token-field',user_id:'other'},
    {id:'zoom-user',account_id:'zoom-account',email:'unused@example.test'}]);
  const result=await f.transport.exchangeAuthorizationCode(input6r);
  assert.equal(result.user_id,'zoom-user');assert.equal(result.account_id,'zoom-account');assert(!('email' in result));
  assert.equal(f.calls.length,2);assert.equal(f.calls[0].url,'https://zoom.us/oauth/token');
  const form=new URLSearchParams(f.calls[0].body);assert.equal(form.get('code'),input6r.code);
  assert.equal(form.get('redirect_uri'),input6r.redirectUri);assert.equal(form.get('grant_type'),'authorization_code');
  assert.equal(f.calls[0].headers.authorization,'Basic '+Buffer.from('fixture-client:fixture-secret').toString('base64'));
  assert.equal(f.calls[1].url,'https://api.zoom.us/v2/users/me');
  assert.equal(f.calls[1].headers.authorization,'Bearer fixture-access');
  assert(f.calls.every(c=>c.redirect==='error'&&c.signal instanceof AbortSignal));
});
test('Gate6R missing profile identity refuses connection storage',async()=>{
  const f=http6r([token6r(),{id:'zoom-user'}]);const repository=new R.MemoryZoomRepository();
  const vault=new V.ZoomTokenVault({repository,cipher:new V.EnvelopeCipher(Buffer.alloc(32,7))});
  const {ZoomOAuthService}=require('../k135z_zoom/zoom_oauth_service.cjs');
  const service=new ZoomOAuthService({repository,tokenVault:vault,transport:f.transport,config:input6r,authorizeStoredIdentity:async()=>true});
  const begin=await service.startAuthorization({principal:P});
  await assert.rejects(service.completeAuthorization({code:'fixture-code',state:new URL(begin.authorizationUrl).searchParams.get('state')}),{code:'ZOOM_PROFILE_RESPONSE_INVALID'});
  assert.equal(await vault.getTokenBundle(P),null);
});
test('Gate6R standard token response connects through existing encrypted vault',async()=>{
  const f=http6r([token6r(),{id:'zoom-user',account_id:'zoom-account'}]),repository=new R.MemoryZoomRepository();
  const vault=new V.ZoomTokenVault({repository,cipher:new V.EnvelopeCipher(Buffer.alloc(32,7))});
  const {ZoomOAuthService}=require('../k135z_zoom/zoom_oauth_service.cjs');
  const service=new ZoomOAuthService({repository,tokenVault:vault,transport:f.transport,config:input6r,authorizeStoredIdentity:async()=>true});
  const begin=await service.startAuthorization({principal:P});
  await service.completeAuthorization({code:'fixture-code',state:new URL(begin.authorizationUrl).searchParams.get('state')});
  const stored=await vault.getTokenBundle(P);assert.equal(stored.record.zoomAccountId,'zoom-account');
  assert.equal(stored.record.zoomUserId,'zoom-user');assert(!JSON.stringify(stored.record).includes('fixture-access'));
});
test('Gate6R refresh sends current refresh token once and returns replacement',async()=>{
  const f=http6r([{...token6r(),refresh_token:'replacement-refresh'}]);
  const value=await f.transport.refreshAccessToken({...input6r,refreshToken:'current-refresh'});
  assert.equal(value.refresh_token,'replacement-refresh');assert.equal(f.calls.length,1);
  assert.equal(new URLSearchParams(f.calls[0].body).get('refresh_token'),'current-refresh');
});
test('Gate6R discovery uses only the current authorized user and fixed Zoom API',async()=>{
  const f=http6r([{meetings:[{id:123,topic:'Fixture meeting'}],next_page_token:''}]);
  assert.equal((await f.transport.listUpcomingMeetings({accessToken:'fixture-access'})).meetings.length,1);
  assert.equal(f.calls[0].url,'https://api.zoom.us/v2/users/me/upcoming_meetings');
  for(const extra of [{userId:'other'},{apiUrl:'https://evil.example'}])
    await assert.rejects(f.transport.listUpcomingMeetings({accessToken:'fixture-access',...extra}),{code:'ZOOM_HTTP_TARGET_REJECTED'});
  assert.equal(f.calls.length,1);
});
test('Gate6R revocation requires explicit provider success',async()=>{
  const f=http6r([{status:'success'},{status:'failed'}]);
  assert.deepEqual(await f.transport.revokeAccessToken({...input6r,accessToken:'fixture-access'}),{status:'success'});
  assert.equal(f.calls[0].url,'https://zoom.us/oauth/revoke');
  assert.equal(new URLSearchParams(f.calls[0].body).get('token'),'fixture-access');
  await assert.rejects(f.transport.revokeAccessToken({...input6r,accessToken:'fixture-access'}),{code:'ZOOM_REVOCATION_RESPONSE_INVALID'});
});
test('Gate6R upstream failures are sanitized and are not retried',async()=>{
  for(const reply of [()=>json6r({message:'private-provider-detail'},400),()=>{throw Error('private-network-detail');}]){
    const f=http6r([reply]);await assert.rejects(f.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),e=>
      e instanceof V.K135zZoomError&&!JSON.stringify(e).includes('private')&&!e.message.includes('private'));
    assert.equal(f.calls.length,1);
  }
});
test('Gate6R redirect and foreign token API origin cannot redirect credentials',async()=>{
  const redirected={status:200,redirected:true,url:'https://evil.example'};
  const a=http6r([()=>redirected]);await assert.rejects(a.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),{code:'ZOOM_HTTP_REDIRECT_REJECTED'});
  const b=http6r([{...token6r(),api_url:'https://evil.example'}]);
  await assert.rejects(b.transport.exchangeAuthorizationCode(input6r),{code:'ZOOM_API_REGION_UNSUPPORTED'});assert.equal(b.calls.length,1);
});
test('Gate6R malformed token and JSON replies cannot become a connection',async()=>{
  for(const reply of [{...token6r(),refresh_token:''},{...token6r(),expires_in:0},
    ()=>new Response('not json',{headers:{'content-type':'application/json'}}),()=>new Response('{}'),[]]){
    const f=http6r([reply]);await assert.rejects(f.transport.exchangeAuthorizationCode(input6r));assert.equal(f.calls.length,1);
  }
});
test('Gate6R oversized streaming responses are cancelled',async()=>{
  let cancelled=false;const f=http6r([()=>new Response(new ReadableStream({
    start(c){c.enqueue(new TextEncoder().encode('x'.repeat(2048)));},cancel(){cancelled=true;}}),
    {headers:{'content-type':'application/json'}})],{maxResponseBytes:1024});
  await assert.rejects(f.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),{code:'ZOOM_HTTP_RESPONSE_TOO_LARGE'});
  assert.equal(cancelled,true);
});
test('Gate6R timeout aborts an unresponsive provider and never retries',async()=>{
  const f=http6r([()=>new Promise(()=>{})],{timeoutMs:25});
  await assert.rejects(f.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),{code:'ZOOM_HTTP_TIMEOUT'});
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].signal.aborted,true);
});
test('Gate6R timeout also covers response body reads',async()=>{
  let cancelled=false;const f=http6r([()=>new Response(new ReadableStream({cancel(){cancelled=true;}}),
    {headers:{'content-type':'application/json'}})],{timeoutMs:25});
  await assert.rejects(f.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),{code:'ZOOM_HTTP_TIMEOUT'});
  assert.equal(cancelled,true);
});
test('Gate6R invalid credentials callback and flags cause no request',async()=>{
  const f=http6r([]);
  for(const extra of [{clientId:'bad:id'},{code:'bad\ncode'},{redirectUri:'http://app.example.test/callback'},
    {redirectUri:'https://user:password@app.example.test/callback'},{redirectUri:'https://app.example.test/callback#fragment'}])
    await assert.rejects(f.transport.exchangeAuthorizationCode({...input6r,...extra}));
  assert.equal(f.calls.length,0);
  for(const extra of [{enabled:'true'},{timeoutMs:0},{maxResponseBytes:99999999}])
    assert.throws(()=>Z.createK135zOAuthHttpTransport(extra),{code:'ZOOM_HTTP_OPTIONS_INVALID'});
});
// K135Z_GATE6R_OAUTH_HTTP_TESTS_END

// K135Z_GATE6S_RUNTIME_OAUTH_TESTS_BEGIN
function env6s(extra={}) {return {NODE_ENV:'production',KORLIX_K135Z_OAUTH_HTTP_ENABLED:'true',
  KORLIX_ZOOM_CLIENT_ID:'fixture-client',KORLIX_ZOOM_CLIENT_SECRET:'fixture-secret',
  KORLIX_K135Z_ZOOM_TOKEN_ENCRYPTION_KEY:'fixture-key-'.repeat(4),
  KORLIX_ZOOM_REDIRECT_URI:'https://api.example.test/api/k135z/zoom/oauth/callback',
  KORLIX_K135Z_ZOOM_ALLOWED_RETURN_ORIGINS:'https://app.example.test',...extra};}
async function runtime6s(o={}) {
  const f=fixture(o),memory=new R.MemoryZoomRepository(),providerCalls=[],storageCalls=[];
  f.database.rpc=async(name,{operation,payload})=>{
    storageCalls.push(operation);assert.equal(name,'k135z_b5b_storage_v1');
    if(o.storageError)return {data:null,error:{message:'private-storage-detail'}};
    let data;
    switch(operation) {
      case 'state_create':await memory.saveOAuthState(payload.stateHash,payload.record);data=true;break;
      case 'state_consume':data={outcome:'ok',record:await memory.consumeOAuthState(payload.stateHash,payload.nowMs)};break;
      case 'connection_save':await memory.saveConnection(payload.key,payload.record);data=true;break;
      case 'connection_get':data=await memory.getConnection(payload.key);break;
      case 'connection_delete':data=await memory.deleteConnection(payload.key);break;
      default:throw Error('unexpected storage operation');
    }
    return {data,error:null};
  };
  const env=env6s(o.env),replies=[token6r(),{id:'zoom-user',account_id:'zoom-account'},
    {meetings:[{id:123,uuid:'fixture-meeting',topic:'Controlled test',join_url:'private-link'}]}, {status:'success'}];
  const runtime=await Z.createK135zServerRuntime({env,database:f.database,
    loadSdk(){throw Error('OAuth must not load the capture SDK');},
    fetchImpl:async(url,options)=>{providerCalls.push({url,...options});return json6r(replies.shift());}});
  const deps=Z.createK135zZoomDependencies({...f.wiring,env,...runtime.options});
  if(o.attach!==false)runtime.attach(deps);
  const handlers=Z.createK135zZoomHandlers(deps);
  async function run(name,req=f.req) {
    const res={status(n){this.statusCode=n;return this;},json(body){this.body=body;return this;},
      setHeader(){},set(){return this;},redirect(url){this.location=url;return this;}};
    await handlers[name](req,res);return res;
  }
  return {...f,env,memory,providerCalls,storageCalls,runtime,deps,run};
}
test('Gate6S new OAuth opt-in defaults off and legacy live flag cannot enable it',async()=>{
  for(const flag of [undefined,'','false']) {
    let calls=0;const r=await Z.createK135zServerRuntime({env:{KORLIX_K135Z_OAUTH_HTTP_ENABLED:flag,
      KORLIX_K135Z_ZOOM_LIVE_TRANSPORT_ENABLED:'true'},fetchImpl(){calls++;},loadSdk(){calls++;}});
    assert.equal(r.oauthEnabled,false);assert.equal(r.enabled,false);assert.deepEqual(r.options,{});assert.equal(calls,0);r.close();
  }
});
test('Gate6S OAuth flag is strict and invalid startup never touches external services',async()=>{
  let calls=0;for(const flag of [true,1,null,'TRUE',' true','1'])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s({KORLIX_K135Z_OAUTH_HTTP_ENABLED:flag}),
      database:{rpc(){calls++;},from(){calls++;}},fetchImpl(){calls++;},loadSdk(){calls++;}}),{code:'K135Z_OAUTH_FLAG_INVALID'});
  assert.equal(calls,0);
});
test('Gate6S enabled OAuth needs a durable client and stable encryption key',async()=>{
  for(const database of [undefined,{}, {rpc(){}}])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s(),database}),{code:'K135Z_OAUTH_DATABASE_REQUIRED'});
  for(const key of [undefined,'','short',' fixture-key-'.repeat(4),'x'.repeat(4097),'x'.repeat(32)+'\n'])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s({KORLIX_K135Z_ZOOM_TOKEN_ENCRYPTION_KEY:key}),
      database:fixture().database}),{code:'K135Z_OAUTH_ENCRYPTION_REQUIRED'});
  await assert.rejects(Z.createK135zServerRuntime({env:env6s({KORLIX_K135Z_ZOOM_ALLOW_EPHEMERAL_STORE:'true'}),
    database:fixture().database}),{code:'K135Z_OAUTH_DURABLE_STORE_REQUIRED'});
});
test('Gate6S validates OAuth credentials without including their values in errors',async()=>{
  for(const change of [{KORLIX_ZOOM_CLIENT_ID:''},{KORLIX_ZOOM_CLIENT_ID:'private:client'},
    {KORLIX_ZOOM_CLIENT_SECRET:'private value'},{KORLIX_ZOOM_CLIENT_SECRET:'x'.repeat(1025)}])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s(change),database:fixture().database}),
      e=>e.code==='K135Z_OAUTH_CREDENTIALS_REQUIRED'&&!e.message.includes('private'));
});
test('Gate6S callback must be canonical HTTPS and match the registered route',async()=>{
  for(const uri of ['http://api.example.test/api/k135z/zoom/oauth/callback','https://user:pass@api.example.test/callback',
    'https://api.example.test/callback','https://api.example.test/api/k135z/zoom/oauth/callback?x=1',
    'https://api.example.test/api/k135z/zoom/oauth/callback#x',' https://api.example.test/api/k135z/zoom/oauth/callback'])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s({KORLIX_ZOOM_REDIRECT_URI:uri}),database:fixture().database}),
      e=>['K135Z_OAUTH_URL_INVALID','K135Z_OAUTH_CALLBACK_PATH_INVALID'].includes(e.code));
});
test('Gate6S return destinations must be explicit unique HTTPS origins',async()=>{
  for(const origins of ['',undefined,'*','https://app.example.test/path','https://app.example.test/',
    'http://app.example.test','https://*.example.test','https://app.example.test,','https://app.example.test,https://app.example.test'])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s({KORLIX_K135Z_ZOOM_ALLOWED_RETURN_ORIGINS:origins}),
      database:fixture().database}),e=>['K135Z_OAUTH_URL_INVALID','K135Z_OAUTH_RETURN_ORIGINS_REQUIRED'].includes(e.code));
});
test('Gate6S rejects alternate provider endpoints and unavailable fetch before startup',async()=>{
  for(const name of ['KORLIX_ZOOM_AUTHORIZE_URL','KORLIX_ZOOM_TOKEN_URL','KORLIX_ZOOM_API_BASE_URL'])
    await assert.rejects(Z.createK135zServerRuntime({env:env6s({[name]:'https://other.example.test'}),
      database:fixture().database}),{code:'K135Z_OAUTH_PROVIDER_URL_INVALID'});
  await assert.rejects(Z.createK135zServerRuntime({env:env6s(),database:fixture().database,fetchImpl:null}),{code:'ZOOM_FETCH_UNAVAILABLE'});
});
test('Gate6S OAuth startup is inert and does not load or enable meeting capture',async t=>{
  const f=await runtime6s();t.after(()=>f.runtime.close());
  assert.equal(f.runtime.oauthEnabled,true);assert.equal(f.runtime.enabled,false);
  assert.equal(f.deps.workspaceHttpEnabled,false);assert.equal(f.deps.workspaceCommands.adapter,null);
  assert.equal(f.providerCalls.length,0);assert.equal(f.storageCalls.length,0);assert.equal(f.calls.length,0);
  f.env.KORLIX_ZOOM_REDIRECT_URI='https://other.example.test';
  assert.equal(f.deps.oauthService.config.redirectUri,'https://api.example.test/api/k135z/zoom/oauth/callback');
});
test('Gate6S provider calls require successful attachment and stop after runtime closure',async()=>{
  const f=await runtime6s({attach:false});const call=()=>f.runtime.options.transport.listUpcomingMeetings({accessToken:'fixture'});
  await assert.rejects(call,{code:'K135Z_OAUTH_RUNTIME_UNAVAILABLE'});assert.equal(f.providerCalls.length,0);
  f.runtime.attach(f.deps);assert.equal(f.runtime.close(),true);
  await assert.rejects(call,{code:'K135Z_OAUTH_RUNTIME_UNAVAILABLE'});assert.equal(f.providerCalls.length,0);
});
test('Gate6S attachment rejects memory storage and a different privileged client',async()=>{
  for(const repository of [new R.MemoryZoomRepository(),new R.SupabaseZoomRepository({client:fixture().database})]) {
    const f=await runtime6s({attach:false});
    assert.throws(()=>f.runtime.attach({...f.deps,repository}),{code:'K135Z_OAUTH_BINDING_INVALID'});f.runtime.close();
  }
});
test('Gate6S attachment rejects substituted transport vault key and OAuth configuration',async()=>{
  for(const change of ['transport','key','redirect','vault']) {
    const f=await runtime6s({attach:false});
    if(change==='transport')f.deps.transport=Z.createFetchZoomTransport({});
    if(change==='key')f.deps.tokenVault.cipher=new V.EnvelopeCipher(Buffer.alloc(32,5));
    if(change==='redirect')f.deps.oauthService.config.redirectUri='https://other.example.test';
    if(change==='vault')f.deps.tokenVault=new V.ZoomTokenVault({repository:new R.MemoryZoomRepository(),
      cipher:new V.EnvelopeCipher(Buffer.alloc(32,5))});
    assert.throws(()=>f.runtime.attach(f.deps),{code:'K135Z_OAUTH_BINDING_INVALID'});f.runtime.close();
  }
});
test('Gate6S registered handlers connect discover and revoke through encrypted durable adapter',async t=>{
  const f=await runtime6s();t.after(()=>f.runtime.close());
  const start=await f.run('start');assert.equal(start.statusCode,200);
  const state=new URL(start.body.authorization_url).searchParams.get('state');
  const connected=await f.run('callback',{query:{state,code:'fixture-code'}});assert.equal(connected.statusCode,200);
  assert.equal(connected.body.connected,true);assert.equal(f.providerCalls.length,2);
  const stored=[...f.memory.connections.values()][0];assert(stored);assert(!JSON.stringify(stored).includes('fixture-access'));
  const upcoming=await f.run('upcoming');assert.equal(upcoming.statusCode,200);
  assert.equal(upcoming.body.meetings[0].id,'123');assert(!JSON.stringify(upcoming.body).includes('private-link'));
  const disconnected=await f.run('disconnect');assert.equal(disconnected.statusCode,200);assert.equal(f.memory.connections.size,0);
  assert.equal(f.providerCalls.length,4);assert(f.storageCalls.includes('connection_save'));
});
test('Gate6S enabled OAuth retains authentication Enterprise and agent restrictions',async t=>{
  for(const o of [{noUser:true},{tier:'basic'},{noAgent:true},{inactive:true}]) {
    const f=await runtime6s(o);t.after(()=>f.runtime.close());const res=await f.run('start');
    assert([401,403].includes(res.statusCode));assert.equal(f.providerCalls.length,0);assert.equal(f.storageCalls.length,0);
  }
});
test('Gate6S callback rechecks ownership before sending the authorization code',async t=>{
  const f=await runtime6s();t.after(()=>f.runtime.close());const start=await f.run('start');
  f.deps.oauthService.authorizeStoredIdentity=async()=>false;
  const res=await f.run('callback',{query:{state:new URL(start.body.authorization_url).searchParams.get('state'),code:'fixture-code'}});
  assert.equal(res.statusCode,403);assert.equal(f.providerCalls.length,0);assert.equal(f.memory.connections.size,0);
});
test('Gate6S storage failure blocks OAuth start and hides database details',async t=>{
  const f=await runtime6s({storageError:true});t.after(()=>f.runtime.close());const res=await f.run('start');
  assert.equal(res.statusCode,503);assert(!JSON.stringify(res.body).includes('private-storage-detail'));assert.equal(f.providerCalls.length,0);
});
test('Gate6S OAuth-only runtime binds shutdown without requiring the capture SDK',async()=>{
  const f=await runtime6s(),exits=[],life=Object.assign(new EventEmitter(),{exit:n=>exits.push(n)});
  const server=Object.assign(new EventEmitter(),{close(fn){this.emit('close');fn();}});
  f.runtime.bindServer(server,{lifecycle:life});life.emit('SIGTERM');assert.deepEqual(exits,[0]);
  await assert.rejects(f.deps.transport.listUpcomingMeetings({accessToken:'fixture'}),{code:'K135Z_OAUTH_RUNTIME_UNAVAILABLE'});
  assert.equal(life.listenerCount('SIGINT'),0);assert.equal(f.providerCalls.length,0);
});
test('Gate6S actual server registration forwards the OAuth runtime and trusted wiring',async t=>{
  const f=await runtime6s({attach:false});t.after(()=>f.runtime.close());const paths=[];let registered;
  const chunk=source.split('// K135Z_B5A_ZOOM_SERVER_REGISTRATION_BEGIN')[1].split('// K135Z_B5A_ZOOM_SERVER_REGISTRATION_END')[0];
  await vm.runInNewContext('(async()=>{'+chunk+'})',{process:{env:f.env},supabaseAdmin:f.database,
    createK135zServerRuntime:async()=>f.runtime,app:{get:p=>paths.push(p),post:p=>paths.push(p),delete:p=>paths.push(p)},
    requireUser(){},korlixAgentLoadProfileV1(){},createK135zGate5Wiring:()=>f.wiring,
    registerK135zZoomRoutes:(app,opts)=>(registered=Z.registerK135zZoomRoutes(app,opts))})();
  assert.equal(registered.dependencies.transport,f.runtime.options.transport);
  assert.equal(registered.dependencies.repository,f.wiring.repository);
  assert(paths.includes('/api/k135z/zoom/oauth/callback'));assert(!paths.some(p=>p.includes('/workspace/')));
  assert.equal(f.providerCalls.length,0);assert.equal(f.storageCalls.length,0);
});
test('Gate6S OAuth and capture can compose with separate opt-ins without joining',async t=>{
  const f=fixture(),sdk=sdk6o(),env=env6s({KORLIX_K135Z_WORKSPACE_ENABLED:'true'});let requests=0;
  const runtime=await Z.createK135zServerRuntime({env,database:f.database,loadSdk:async()=>sdk.sdk,
    fetchImpl(){requests++;throw Error('unexpected provider request');}});
  t.after(()=>runtime.close());const deps=Z.createK135zZoomDependencies({...f.wiring,env,...runtime.options});
  runtime.attach(deps);assert.equal(runtime.oauthEnabled,true);assert.equal(runtime.enabled,true);
  assert.equal(deps.workspaceHttpEnabled,true);assert(deps.workspaceCommands.adapter);
  assert.equal(sdk.clients.length,0);assert.equal(requests,0);assert.equal(f.calls.length,0);
});
// K135Z_GATE6S_RUNTIME_OAUTH_TESTS_END

test('Regional OAuth metadata keeps exchange refresh and discovery on fixed Zoom endpoints',async()=>{
  const origins=['https://api.zoom.us',...['us','eu','au','ca','in','sa','sg','uk'].map(r=>`https://api-${r}.zoom.us`),
    'https://korlix-example.zoom.us'];
  for(const api_url of [undefined,...origins.flatMap(origin=>[origin,origin+'/'])]){
    const reply={...token6r(),api_url};
    const f=http6r([reply,{id:'zoom-user',account_id:'zoom-account'},reply,{meetings:[]}]);
    const first=await f.transport.exchangeAuthorizationCode(input6r);
    const refreshed=await f.transport.refreshAccessToken({...input6r,refreshToken:first.refresh_token});
    assert.equal(first.api_url,'https://api.zoom.us');assert.equal(refreshed.api_url,'https://api.zoom.us');
    await f.transport.listUpcomingMeetings({accessToken:refreshed.access_token,apiUrl:refreshed.api_url});
    assert.deepEqual(f.calls.map(c=>c.url),['https://zoom.us/oauth/token','https://api.zoom.us/v2/users/me',
      'https://zoom.us/oauth/token','https://api.zoom.us/v2/users/me/upcoming_meetings']);
    assert(f.calls.every(c=>c.redirect==='error'));
  }
});

test('Regional OAuth rejects foreign and malformed metadata without forwarding credentials',async()=>{
  for(const api_url of [null,42,{},'','http://api-us.zoom.us','https://api-us.zoom.us.evil.example',
    'https://api-us.zoom.us@evil.example','https://user@api-us.zoom.us','https://api-us.zoom.us:443',
    'https://api-us.zoom.us/v2','https://api-us.zoom.us?x=1','https://api-us.zoom.us#x',
    'https://api-us.zoom.us\n',' https://api-us.zoom.us','https://api-us.zoom.us\\@evil.example',
    'https://127.0.0.1','https://api-us.zoom.us.','https://-invalid.zoom.us','https://nested.api-us.zoom.us']){
    const f=http6r([{...token6r(),api_url},{...token6r(),api_url}]);
    await assert.rejects(f.transport.exchangeAuthorizationCode(input6r),{code:'ZOOM_API_REGION_UNSUPPORTED'});
    assert.equal(f.calls.length,1);
    await assert.rejects(f.transport.refreshAccessToken({...input6r,refreshToken:'fixture'}),{code:'ZOOM_API_REGION_UNSUPPORTED'});
    assert.equal(f.calls.length,2);assert(f.calls.every(c=>c.url==='https://zoom.us/oauth/token'));
    await assert.rejects(f.transport.listUpcomingMeetings({accessToken:'fixture',apiUrl:api_url}),{code:'ZOOM_HTTP_TARGET_REJECTED'});
    assert.equal(f.calls.length,2);
  }
});

test('Regional OAuth connection survives encrypted storage refresh and meeting discovery',async()=>{
  let now=Date.now();const clock=()=>now;
  const f=http6r([{...token6r(),api_url:'https://api-us.zoom.us'},
    {id:'zoom-user',account_id:'zoom-account'},
    {...token6r(),api_url:'https://api-eu.zoom.us',access_token:'rotated-access',refresh_token:'rotated-refresh'},
    {meetings:[{id:123,topic:'Regional fixture'}]}]);
  const repository=new R.MemoryZoomRepository();
  const vault=new V.ZoomTokenVault({repository,cipher:new V.EnvelopeCipher(Buffer.alloc(32,7)),clock});
  const {ZoomOAuthService}=require('../k135z_zoom/zoom_oauth_service.cjs');
  const service=new ZoomOAuthService({repository,tokenVault:vault,transport:f.transport,config:input6r,
    clock,authorizeStoredIdentity:async()=>true});
  const start=await service.startAuthorization({principal:P});
  const callback={code:'fixture-code',state:new URL(start.authorizationUrl).searchParams.get('state')};
  await service.completeAuthorization(callback);
  const saved=await vault.getTokenBundle(P);
  assert.equal(saved.tokens.apiUrl,'https://api.zoom.us');assert(!JSON.stringify(saved.record).includes('fixture-access'));
  now+=3600000;
  const {ZoomMeetingDiscovery}=require('../k135z_zoom/zoom_meeting_discovery.cjs');
  await new ZoomMeetingDiscovery({oauthService:service,transport:f.transport}).listUpcoming(P);
  assert.equal(f.calls.length,4);assert.equal(f.calls[3].headers.authorization,'Bearer rotated-access');
  const rotated=await vault.getTokenBundle(P);
  assert.equal(rotated.tokens.apiUrl,'https://api.zoom.us');assert.equal(rotated.tokens.refreshToken,'rotated-refresh');
  await assert.rejects(service.completeAuthorization(callback),{code:'ZOOM_OAUTH_STATE_REPLAYED'});
  assert.equal(f.calls.length,4);
});
