import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {registerPod} from '../pod/routes.mjs';

const ACTOR='11111111-1111-4111-8111-111111111111';
const OTHER='22222222-2222-4222-8222-222222222222';
const EPISODE='33333333-3333-4333-8333-333333333333';
const REQUEST='44444444-4444-4444-8444-444444444444';
const WHEN='2026-10-01T00:00:00.000Z';
const SECRET='INTERNAL_METADATA_MUST_NOT_LEAVE_SERVER';
const settings={requestId:REQUEST,category:'technology',topic:'How does technology help?',
  durationSeconds:300,hostCount:2,style:'balanced',consent:true};
const entitlement={allowed:true,limits:{maxSessionSeconds:900},remainingSeconds:700};
const clone=value=>structuredClone(value);
const episode=(overrides={})=>({id:EPISODE,...settings,state:'active',phase:'listening',version:1,
  createdAt:WHEN,startedAt:WHEN,turns:[],sources:[],...overrides});
const turn={id:'turn-1',seq:1,speaker:'host',text:'A short useful thought.',sourceIds:['source-1'],createdAt:WHEN};
const brief={text:'A verified research brief.',sources:[{id:'source-1',title:'Source',url:'https://www.nasa.gov/'}],checkedAt:WHEN};
const usage={inputTokens:12,outputTokens:4,totalTokens:16,usageKnown:true,status:'completed'};
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};

function wav({seconds=0.01,channels=1,rate=24000}={}) {
  const dataBytes=Math.round(seconds*rate)*channels*2;
  const bytes=Buffer.alloc(44+dataBytes);
  bytes.write('RIFF',0);bytes.writeUInt32LE(bytes.length-8,4);bytes.write('WAVE',8);
  bytes.write('fmt ',12);bytes.writeUInt32LE(16,16);bytes.writeUInt16LE(1,20);
  bytes.writeUInt16LE(channels,22);bytes.writeUInt32LE(rate,24);bytes.writeUInt32LE(rate*channels*2,28);
  bytes.writeUInt16LE(channels*2,32);bytes.writeUInt16LE(16,34);bytes.write('data',36);
  bytes.writeUInt32LE(dataBytes,40);return bytes;
}

class Response extends EventEmitter {
  constructor(){super();this.statusCode=200;this.headers={};this.headersSent=false;this.writableEnded=false;this.destroyed=false;this.writes=[];}
  set(name,value){this.headers[name.toLowerCase()]=value;return this;}
  status(code){this.statusCode=code;return this;}
  json(value){this.writes.push(value);this.body=value;this.headersSent=true;this.writableEnded=true;return this;}
  disconnect(){this.destroyed=true;this.emit('close');}
}

function harness(t,{user={id:ACTOR},authError,access=()=>clone(entitlement),store:storeOverrides={},
  providers:providerOverrides={},state=episode()}={}) {
  const handlers=new Map(),calls=[],providerCalls=[],accessCalls=[],authCalls=[];
  const app=Object.fromEntries(['get','post','delete'].map(method=>[method,(path,handler)=>handlers.set(`${method.toUpperCase()} ${path}`,handler)]));
  const implementations={
    list:async()=>({episodes:[clone(state)]}),
    create:async()=>({episode:clone(state)}),
    get:async()=>({episode:clone(state)}),
    control:async(_actor,_id,action)=>({episode:{...clone(state),state:action==='end'?'ended':action==='resume'?'active':'paused'}}),
    contribute:async()=>({episode:clone(state)}),
    remove:async()=>({deleted:true}),
    claim:async()=>({dispatch:true,episode:clone(state),brief:clone(brief)}),
    authorizeDispatch:async()=>({allowed:true}),
    recordUsage:async()=>({recorded:true,allowed:true}),
    finish:async(_actor,_id,_request,result)=>({committed:true,episode:{...clone(state),turns:result.turn?[clone(result.turn)]:[]},turn:result.turn,text:result.text}),
    fail:async()=>({episode:clone(state)}),
    ...storeOverrides,
  };
  const store=Object.fromEntries(Object.entries(implementations).map(([method,impl])=>[method,async(...args)=>{
    calls.push({method,args});return impl(...args);
  }]));
  const providerImplementations={
    research:async()=>({brief:clone(brief),usage:clone(usage)}),
    turn:async()=>({...clone(turn),usage:clone(usage)}),
    speak:async()=>({wav:wav(),mime:'audio/wav',durationSeconds:0.01,usage:{usageKnown:false,status:'completed'}}),
    transcribe:async()=>({text:'The listener spoke.',usage:clone(usage)}),
    ...providerOverrides,
  };
  const providers=Object.fromEntries(Object.entries(providerImplementations).map(([method,impl])=>[method,async(args)=>{
    providerCalls.push({method,args});return impl(args);
  }]));
  const registered=registerPod(app,{store,providers,startSweep:false,logger:{warn(){}},
    requireUser:async request=>{authCalls.push(request);if(authError)throw authError;return user;},
    access:async authenticated=>{accessCalls.push(authenticated);return access(authenticated);},
    runtimeOptions:{watchdogMs:60000,operationTimeoutMs:60000},
  });
  t.after(()=>registered.stop());
  function start(method,path,{body={},params={id:EPISODE}}={}) {
    const handler=handlers.get(`${method} ${path}`);assert.ok(handler,`registered ${method} ${path}`);
    const request=new EventEmitter();Object.assign(request,{body,params,aborted:false});
    const response=new Response();const done=handler(request,response);
    return {request,response,done};
  }
  async function invoke(method,path,options){const value=start(method,path,options);await value.done;return value.response;}
  return {start,invoke,calls,providerCalls,accessCalls,authCalls,registered,handlers};
}

const endpoints=[
  ['GET','/api/pod',{}],
  ['POST','/api/pod/episodes',settings],
  ['GET','/api/pod/episodes/:id',{}],
  ['POST','/api/pod/episodes/:id/control',{action:'resume'}],
  ['POST','/api/pod/episodes/:id/contributions',{requestId:REQUEST,text:'My contribution.'}],
  ['POST','/api/pod/episodes/:id/next',{requestId:REQUEST,version:1}],
  ['POST','/api/pod/episodes/:id/prepare',{requestId:REQUEST,version:1}],
  ['POST','/api/pod/episodes/:id/play-prepared',{requestId:REQUEST,version:1}],
  ['POST','/api/pod/episodes/:id/transcribe',{requestId:REQUEST,audioBase64:wav().toString('base64')}],
  ['DELETE','/api/pod/episodes/:id',{confirmed:true}],
];

test('every endpoint requires authentication and keeps responses private',async t=>{
  for(const auth of [{user:null},{authError:new Error('private auth server details')}]) {
    const h=harness(t,auth);
    for(const [method,path,body] of endpoints) {
      const response=await h.invoke(method,path,{body});
      assert.equal(response.statusCode,401,`${method} ${path}`);
      assert.deepEqual(response.body,{error:'Sign in to use The Pod and You.',code:'pod_sign_in'});
      assert.equal(response.headers['cache-control'],'no-store');
      assert.equal(response.headers['x-content-type-options'],'nosniff');
    }
    assert.equal(h.calls.length,0);assert.equal(h.providerCalls.length,0);assert.equal(h.accessCalls.length,0);
  }
});

test('banned accounts cannot read private history or dispatch work',async t=>{
  const h=harness(t,{user:{id:ACTOR,banned_until:'2999-01-01T00:00:00Z'}});
  const response=await h.invoke('GET','/api/pod');
  assert.equal(response.statusCode,403);assert.equal(h.calls.length,0);assert.equal(h.providerCalls.length,0);
});

test('catalog, create, and history use the authenticated owner and make no provider calls',async t=>{
  const h=harness(t);
  const catalog=await h.invoke('GET','/api/pod',{body:{actor:OTHER,userId:OTHER}});
  assert.equal(catalog.statusCode,200);assert.deepEqual(catalog.body.access.durations,[300,600]);
  assert.equal(catalog.body.access.maxSeconds,700);assert.equal(catalog.body.catalog.length,7);
  for(let attempt=0;attempt<2;attempt++) {
    const created=await h.invoke('POST','/api/pod/episodes',{body:{...settings,actor:OTHER,userId:OTHER,ownerId:OTHER,
      limits:{maxSessionSeconds:999999},unlimited:true,usage:{totalTokens:-1}}});
    assert.equal(created.statusCode,200);
  }
  const read=await h.invoke('GET','/api/pod/episodes/:id',{body:{actor:OTHER}});assert.equal(read.statusCode,200);
  assert.equal(h.providerCalls.length,0);
  assert.ok(h.calls.length>=4);assert.ok(h.calls.every(call=>call.args[0]===ACTOR));
  for(const call of h.calls.filter(call=>call.method==='create')) {
    assert.deepEqual(call.args[1],{requestId:REQUEST,input:{category:settings.category,topic:settings.topic,
      durationSeconds:300,hostCount:2,style:'balanced'},limits:entitlement.limits,unlimited:false});
  }
  assert.ok(h.accessCalls.every(user=>user.id===ACTOR));
});

test('replaying an existing turn returns text without regenerating unavailable audio',async t=>{
  const h=harness(t,{store:{claim:async()=>({dispatch:false,episode:episode({turns:[clone(turn)]}),result:{turn:clone(turn)}})}});
  for(let replay=0;replay<2;replay++) {
    const response=await h.invoke('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}});
    assert.equal(response.statusCode,200);assert.equal(response.body.replayed,true);
    assert.deepEqual(response.body.turn,turn);assert.equal(response.body.audio,null);assert.equal(response.body.audioUnavailable,true);
  }
  assert.equal(h.providerCalls.length,0);
  assert.equal(h.calls.filter(call=>['authorizeDispatch','recordUsage','finish'].includes(call.method)).length,0);
});

test('access is enforced for every paid or continuing action while stop controls remain available',async t=>{
  const denied={allowed:false,reason:'Your allowance is exhausted.',status:403};
  const h=harness(t,{access:()=>denied});
  for(const [method,path,body] of endpoints.filter(([method,path])=>method==='POST'&&path!=='/api/pod/episodes/:id/control')) {
    const before=h.calls.length;
    const response=await h.invoke(method,path,{body});assert.equal(response.statusCode,403,`${method} ${path}`);
    assert.equal(response.body.code,'pod_access_denied');assert.equal(h.calls.length,before);
  }
  const resume=await h.invoke('POST','/api/pod/episodes/:id/control',{body:{action:'resume'}});
  assert.equal(resume.statusCode,403);
  for(const action of ['pause','interrupt','end','heartbeat']) {
    const response=await h.invoke('POST','/api/pod/episodes/:id/control',{body:{action}});assert.equal(response.statusCode,200,action);
  }
  const catalog=await h.invoke('GET','/api/pod');
  assert.equal(catalog.body.access.allowed,false);assert.deepEqual(catalog.body.access.durations,[]);assert.equal(catalog.body.access.maxSeconds,0);
  const history=await h.invoke('GET','/api/pod/episodes/:id');assert.equal(history.statusCode,200);
  assert.equal(h.providerCalls.length,0);
});

test('entitlement is rechecked immediately before dispatch',async t=>{
  let checked=0;
  const h=harness(t,{access:()=>++checked===1?entitlement:{allowed:false,reason:'Allowance changed.'}});
  const response=await h.invoke('POST','/api/pod/episodes/:id/transcribe',{body:{requestId:REQUEST,audioBase64:wav().toString('base64')}});
  assert.equal(response.statusCode,403);assert.equal(checked,2);assert.equal(h.providerCalls.length,0);
  assert.equal(h.calls.filter(call=>call.method==='authorizeDispatch').length,0);
  assert.equal(h.calls.filter(call=>call.method==='fail').length,1);
});

test('transient audio is validated before reading, claiming, or dispatching an episode',async t=>{
  const h=harness(t);
  const corrupted=wav();corrupted.write('JUNK',36);
  const invalid=[undefined,'','!!!=',`${wav().toString('base64')}\n`,Buffer.alloc(44).toString('base64'),
    wav({channels:2}).toString('base64'),wav({rate:16000}).toString('base64'),corrupted.toString('base64'),
    wav({seconds:30.01}).toString('base64')];
  for(const audioBase64 of invalid) {
    const response=await h.invoke('POST','/api/pod/episodes/:id/transcribe',{body:{requestId:REQUEST,audioBase64}});
    assert.equal(response.statusCode,400);
  }
  assert.equal(h.calls.length,0);assert.equal(h.providerCalls.length,0);
});

test('valid transcription stays transient and is never submitted as a contribution',async t=>{
  const h=harness(t);const input=wav();
  const response=await h.invoke('POST','/api/pod/episodes/:id/transcribe',{body:{requestId:REQUEST,audioBase64:input.toString('base64'),actor:OTHER}});
  assert.equal(response.statusCode,200);assert.equal(response.body.text,'The listener spoke.');
  assert.deepEqual(h.providerCalls.map(call=>call.method),['transcribe']);
  assert.deepEqual(h.providerCalls[0].args.wav,input);
  assert.ok(h.providerCalls[0].args.signal instanceof AbortSignal);
  assert.equal(h.calls.filter(call=>call.method==='contribute').length,0);
  assert.ok(h.calls.every(call=>call.args[0]===ACTOR));
  const persisted=JSON.stringify(h.calls);
  assert.ok(!persisted.includes('audioBase64'));assert.ok(!persisted.includes('"type":"Buffer"'));
});

test('public episodes and replayed turns exclude nested and top-level internal metadata',async t=>{
  const privateTurn={...turn,providerRequestId:SECRET,usage:{secret:SECRET},ownerId:SECRET};
  const privateSource={...brief.sources[0],providerResponseId:SECRET,raw:{secret:SECRET}};
  const privateEpisode=episode({ownerId:SECRET,brief:{text:SECRET},lease:SECRET,
    turns:[privateTurn],sources:[privateSource],evidence:{secret:SECRET}});
  const h=harness(t,{state:privateEpisode,store:{
    create:async()=>({episode:privateEpisode,privateReceipt:SECRET}),
    claim:async()=>({dispatch:false,episode:privateEpisode,result:{turn:privateTurn,privateReceipt:SECRET}}),
  }});
  const responses=[
    await h.invoke('GET','/api/pod'),
    await h.invoke('POST','/api/pod/episodes',{body:settings}),
    await h.invoke('GET','/api/pod/episodes/:id'),
    await h.invoke('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}}),
  ];
  for(const response of responses) {
    assert.equal(response.statusCode,200);
    assert.ok(!JSON.stringify(response.body).includes(SECRET),'internal metadata is omitted at all depths');
    const published=response.body.episode||response.body.episodes[0];
    assert.deepEqual(published.turns,[turn]);assert.deepEqual(published.sources,brief.sources);
  }
  assert.deepEqual(responses.at(-1).body.turn,turn);
});

test('disconnect aborts late work, records provider usage, and returns no audio',async t=>{
  const started=deferred(),completion=deferred();
  const h=harness(t,{providers:{speak:async args=>{started.resolve(args);return completion.promise;}}});
  const pending=h.start('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}});
  const speechArgs=await Promise.race([started.promise,pending.done.then(()=>assert.fail('the request ended before speech started'))]);
  pending.request.aborted=true;pending.response.disconnect();
  assert.equal(speechArgs.signal.aborted,true);
  completion.resolve({wav:wav(),durationSeconds:0.01,usage:{...usage,providerRequestId:'late-request'}});
  await pending.done;
  assert.equal(pending.response.writes.length,0);
  const receipts=h.calls.filter(call=>call.method==='recordUsage');
  assert.deepEqual(receipts.map(call=>call.args[3].callKey),['turn','speak']);
  assert.equal(receipts.at(-1).args[3].evidence.providerRequestId,'late-request');
  assert.equal(h.calls.filter(call=>call.method==='finish').length,0);
  assert.equal(h.calls.filter(call=>call.method==='fail').length,1);
  assert.equal(h.registered.runtime.activeCount,0);
});

test('disconnect while a claim is pending prevents later provider dispatch',async t=>{
  const claiming=deferred(),claim=deferred();
  const h=harness(t,{store:{claim:async()=>{claiming.resolve();return claim.promise;}}});
  const pending=h.start('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}});
  await claiming.promise;pending.request.aborted=true;pending.response.disconnect();
  claim.resolve({dispatch:true,episode:episode(),brief:clone(brief)});
  await pending.done;
  assert.equal(h.providerCalls.length,0,'a closed response must not initiate paid work');
  assert.equal(pending.response.writes.length,0);assert.equal(h.registered.runtime.activeCount,0);
});

test('disconnect during transcription commit retains usage and prevents response writes',async t=>{
  const finishing=deferred(),finished=deferred();
  const h=harness(t,{store:{finish:async()=>{finishing.resolve();return finished.promise;}}});
  const pending=h.start('POST','/api/pod/episodes/:id/transcribe',{
    body:{requestId:REQUEST,audioBase64:wav().toString('base64')},
  });
  await Promise.race([finishing.promise,pending.done.then(()=>assert.fail('the request ended before commit started'))]);
  const receipts=h.calls.filter(call=>call.method==='recordUsage');
  assert.equal(receipts.length,1);assert.equal(receipts[0].args[3].callKey,'transcribe');
  assert.deepEqual(receipts[0].args[3].evidence,usage);
  pending.request.aborted=true;pending.response.disconnect();
  assert.equal(h.providerCalls[0].args.signal.aborted,true);
  finished.resolve({committed:true,episode:episode(),text:'The listener spoke.'});
  await pending.done;
  assert.equal(pending.response.writes.length,0,'a transcript must not be written after disconnect during commit');
  assert.equal(h.calls.filter(call=>call.method==='recordUsage').length,1,'existing transcription usage is not repeated');
  assert.equal(h.registered.runtime.activeCount,0);
});

test('unknown route and provider errors are sanitized and never expose internals',async t=>{
  for(const options of [
    {store:{get:async()=>{throw new Error(SECRET);}}},
    {providers:{turn:async()=>{throw Object.assign(new Error(SECRET),{status:418,code:SECRET,headers:{authorization:SECRET}});}}},
  ]) {
    const h=harness(t,options);
    const response=await h.invoke('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}});
    assert.equal(response.statusCode,503);assert.equal(response.body.code,'pod_unavailable');
    assert.ok(!JSON.stringify(response.body).includes(SECRET));
    for(const failed of h.calls.filter(call=>call.method==='fail'))assert.ok(!JSON.stringify(failed.args[3]).includes(SECRET));
  }
});

test('delete requires explicit confirmation and always uses the verified actor',async t=>{
  const h=harness(t);
  const denied=await h.invoke('DELETE','/api/pod/episodes/:id',{body:{confirmed:'true',actor:OTHER}});
  assert.equal(denied.statusCode,400);assert.equal(h.calls.length,0);
  const deleted=await h.invoke('DELETE','/api/pod/episodes/:id',{body:{confirmed:true,actor:OTHER}});
  assert.deepEqual(deleted.body,{deleted:true});
  assert.deepEqual(h.calls[0],{method:'remove',args:[ACTOR,EPISODE,{confirmed:true}]});
  assert.equal(h.providerCalls.length,0);
});

test('prepare exposes only a safe handle until authenticated playback commits its transcript',async t=>{
  let staged;
  const state=episode({turns:[{...turn,id:'welcome',sourceIds:[]}]}),h=harness(t,{state,store:{
    finish:async(_actor,_id,_request,result)=>{staged=result;return {committed:true,prepared:true,preparedId:REQUEST,
      episode:{...state,preparedId:REQUEST,preparedResult:SECRET},privateReceipt:SECRET};},
    playPrepared:async(_actor,_id,{requestId,version})=>{
      assert.equal(requestId,REQUEST);assert.equal(version,1);
      return {committed:true,episode:{...state,turns:[...state.turns,staged.turn]},turn:{...staged.turn,privateReceipt:SECRET}};
    },
  }});
  const prepared=await h.invoke('POST','/api/pod/episodes/:id/prepare',{body:{requestId:REQUEST,version:1,actor:OTHER}});
  assert.equal(prepared.statusCode,200);assert.equal(prepared.body.prepared,true);assert.equal(prepared.body.preparedId,REQUEST);
  assert.equal(prepared.body.audio,undefined);assert.equal(prepared.body.turn,undefined);
  assert.equal(prepared.body.episode.turns.length,1);assert.ok(!JSON.stringify(prepared.body).includes(SECRET));
  const providerCount=h.providerCalls.length;
  const played=await h.invoke('POST','/api/pod/episodes/:id/play-prepared',{body:{requestId:REQUEST,version:1,actor:OTHER}});
  assert.equal(played.statusCode,200);assert.equal(played.body.episode.turns.length,2);
  assert.ok(played.body.audio.base64);assert.ok(!JSON.stringify(played.body).includes(SECRET));
  assert.equal(h.providerCalls.length,providerCount);
  assert.ok(h.calls.every(call=>call.args[0]===ACTOR));
});

test('prepared playback validates identifiers and versions before any cache or storage mutation',async t=>{
  const h=harness(t);
  for(const body of [{requestId:'invalid',version:1},{requestId:REQUEST,version:-1},{requestId:REQUEST,version:'1'}]) {
    const reply=await h.invoke('POST','/api/pod/episodes/:id/play-prepared',{body});assert.equal(reply.statusCode,400);
  }
  assert.equal(h.calls.length,0);assert.equal(h.providerCalls.length,0);
});

test('preparing during the final recap neither ends that speaking turn nor dispatches paid work',async t=>{
  const h=harness(t,{state:episode({summary:'The final recap.'})});
  const prepared=await h.invoke('POST','/api/pod/episodes/:id/prepare',{body:{requestId:REQUEST,version:1}});
  assert.equal(prepared.statusCode,200);assert.equal(prepared.body.prepared,false);assert.equal(prepared.body.episode.state,'active');
  assert.equal(h.providerCalls.length,0);assert.equal(h.calls.filter(c=>c.method==='control').length,0);
  const ended=await h.invoke('POST','/api/pod/episodes/:id/next',{body:{requestId:REQUEST,version:1}});
  assert.equal(ended.body.episode.state,'ended');assert.equal(h.providerCalls.length,0);
});

test('ordinary paused heartbeats preserve an in-flight transcription and its reviewable text',async t=>{
  const started=deferred(),completed=deferred();
  const state=episode({state:'paused',phase:'paused',endReason:'interrupt'});
  const h=harness(t,{state,providers:{transcribe:async args=>{started.resolve(args);return completed.promise;}}});
  const pending=h.start('POST','/api/pod/episodes/:id/transcribe',{
    body:{requestId:REQUEST,audioBase64:wav().toString('base64')},
  });
  const args=await started.promise;
  const heartbeat=await h.invoke('POST','/api/pod/episodes/:id/control',{body:{action:'heartbeat'}});
  assert.equal(heartbeat.statusCode,200);assert.equal(heartbeat.body.episode.state,'paused');
  assert.equal(args.signal.aborted,false,'a paused listener can keep their transcription alive');
  completed.resolve({text:'Please explain that point.',usage:clone(usage)});
  await pending.done;
  assert.equal(pending.response.statusCode,200);assert.equal(pending.response.body.text,'Please explain that point.');
  assert.equal(h.calls.filter(call=>call.method==='fail').length,0);
  assert.deepEqual(h.providerCalls.map(call=>call.method),['transcribe']);
});

test('actual heartbeat loss still cancels an in-flight paused transcription and retains its usage receipt',async t=>{
  const started=deferred(),completed=deferred();
  const state=episode({state:'paused',phase:'paused',endReason:'interrupt'});
  const h=harness(t,{state,store:{control:async()=>({episode:{...state,endReason:'heartbeat_lost',version:2}})},
    providers:{transcribe:async args=>{started.resolve(args);return completed.promise;}}});
  const pending=h.start('POST','/api/pod/episodes/:id/transcribe',{
    body:{requestId:REQUEST,audioBase64:wav().toString('base64')},
  });
  const args=await started.promise;
  await h.invoke('POST','/api/pod/episodes/:id/control',{body:{action:'heartbeat'}});
  assert.equal(args.signal.aborted,true);
  completed.resolve({text:'Must not leak after disconnect.',usage:clone(usage)});
  await pending.done;
  assert.equal(pending.response.statusCode,409);assert.equal(pending.response.body.text,undefined);
  assert.equal(h.calls.filter(call=>call.method==='recordUsage').length,1);
  assert.equal(h.calls.filter(call=>call.method==='finish').length,0);
});

test('small-talk assets require an active owned episode and match the selected panel',async t=>{
 const path='/api/pod/episodes/:id/small-talk/:clip';
 const options=clip=>({params:{id:EPISODE,clip}});
 for(const state of ['paused','ended','ready']){
  const h=harness(t,{state:episode({state,deadlineAt:new Date(Date.now()+60000).toISOString()})});
  assert.equal((await h.invoke('POST',path,options('host-0'))).statusCode,409);
  assert.equal(h.providerCalls.length,0);
 }
 const h=harness(t,{state:episode({deadlineAt:new Date(Date.now()+60000).toISOString()})});
 assert.equal((await h.invoke('POST',path,options('challenger-0'))).statusCode,409);
 assert.equal((await h.invoke('POST',path,options('constructor'))).statusCode,409);
 const result=await h.invoke('POST',path,options('host-0'));
 assert.equal(result.statusCode,200);assert.equal(result.body.speaker,'host');
 assert.equal((await h.invoke('POST',path,options('host-0'))).statusCode,200);
 assert.equal(h.providerCalls.length,1);assert.equal(h.providerCalls[0].method,'speak');
 assert(h.calls.filter(c=>c.method==='get').every(c=>c.args[0]===ACTOR));
 const denied=harness(t,{access:()=>({allowed:false,status:403})});
 assert.equal((await denied.invoke('POST',path,options('host-0'))).statusCode,403);
 assert.equal(denied.providerCalls.length,0);
 const other=harness(t,{store:{get:async()=>{throw Object.assign(new Error('Not found'),{name:'PodStorageError',status:404});}}});
 assert.equal((await other.invoke('POST',path,options('host-0'))).statusCode,404);assert.equal(other.providerCalls.length,0);
});
