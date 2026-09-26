'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {createMeetingResponses, assertResponseAuthority} = require('../k135z_zoom/meeting_response.cjs');
const Z = require('../k135z_zoom/zoom_routes.cjs');
const user = '11111111-1111-4111-8111-111111111111';
const principal = {tenantId:user,userId:user,agentId:'nova'};
const context = {...principal,sessionId:'session',meetingUuid:'meeting',streamId:'stream',generation:1};
const mp3 = Buffer.concat([Buffer.from('ID3'),Buffer.alloc(100)]);
const copy = x => JSON.parse(JSON.stringify(x));
function fixture() {
  let now = 0, bad = false, hold, after;
  const row = {bindingRevision:1,authorityRevision:1,validForMs:30000,
    authority:{viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true},
    record:{snapshot:{context,revision:2,state:'listening'},pending:null,uncertain:false}};
  const calls = [], env = {OPENAI_API_KEY:'offline',KORLIX_LIVE_CONVO_VOICE:'cedar'};
  const fetchImpl = async (url, options) => {
    calls.push({url,body:JSON.parse(options.body)});
    if (hold) await hold;
    after?.();
    return new Response(bad ? 'invalid audio' : mp3, {headers:{'content-type':'audio/mpeg'}});
  };
  const service = createMeetingResponses({env,fetchImpl,now:()=>now});
  const input = {kind:'waiting-voice',body:{context,enabled:true},principal,signal:new AbortController().signal,
    check:async()=>{assertResponseAuthority(principal,context,row,true);return copy(row);},
    preview:()=>{throw Error('Must not read captions');}};
  return {row,env,calls,fetchImpl,service,input,run:()=>service.run(input),
    time:t=>now=t,bad:v=>bad=v,hold:p=>hold=p,after:f=>after=f};
}
test('prepares only two fixed phrases in the configured voice; cache never contains meeting context', async () => {
  const f=fixture(), r=await f.run();
  assert.equal(f.calls.length,2); assert.equal(r.waitingVoice.clips.length,2);
  for (const call of f.calls) {
    assert.match(call.url,/audio\/speech$/); assert.equal(call.body.voice,'cedar');
    assert.equal(call.body.model,'gpt-4o-mini-tts');
    assert.equal(JSON.stringify(call.body).includes(user),false);
    assert.equal(JSON.stringify(call.body).includes('meeting'),false);
  }
  assert.match(r.waitingVoice.clips[0].text,/I'm on it/);
  const second=await f.run(); assert.deepEqual(second,r); assert.equal(f.calls.length,2);
  f.time(3600001); await f.run(); assert.equal(f.calls.length,4);
});
test('explicit opt-in and strict body reject arbitrary text, voice, and memory', async () => {
  const f=fixture();
  for (const body of [{context,enabled:false},{context},{context,enabled:true,text:'injected'},
    {context,enabled:true,voice:'alloy'},{context,enabled:true,memory:'private'}]) {
    await assert.rejects(f.service.run({...f.input,body}));
  }
  assert.equal(f.calls.length,0);
});
test('unavailable authority is checked before generation and even on cached audio', async () => {
  for (const warm of [false,true]) {
    for (const change of [f=>f.row.authority.hostAuthorized=false,
      f=>f.row.authority.viewerAuthorized=false,f=>f.row.authority.listeningAuthorized=false,
      f=>f.row.validForMs=0,f=>f.row.record.snapshot.state='stopped',f=>f.row.record.pending={}]) {
      const f=fixture(); if(warm) await f.run(); const count=f.calls.length;
      change(f); await assert.rejects(f.run()); assert.equal(f.calls.length,count);
    }
  }
});
test('authority changes and cancellation discard preparation and do not fill cache', async () => {
  for (const cancel of [false,true]) {
    const f=fixture(), abort=new AbortController();
    f.after(()=>{if(cancel)abort.abort();else f.row.authorityRevision++;});
    await assert.rejects(f.service.run({...f.input,signal:abort.signal}));
    assert.equal(f.calls.length,1); f.after(null); await f.run(); assert.equal(f.calls.length,3);
  }
});
test('concurrent warmups and repeated failed synthesis have bounded provider cost', async () => {
  const f=fixture();let release;f.hold(new Promise(r=>release=r));
  const first=f.run(); await new Promise(r=>setImmediate(r));
  await assert.rejects(f.run(),e=>e.status===429); release();await first;
  assert.equal(f.calls.length,2);
  const broken=fixture();broken.bad(true);
  for(let n=0;n<3;n++)await assert.rejects(broken.run());
  await assert.rejects(broken.run(),e=>e.status===429);assert.equal(broken.calls.length,3);
});
test('cache is replaced when configured voice changes', async () => {
  const f=fixture();await f.run();f.env.KORLIX_LIVE_CONVO_VOICE='marin';await f.run();
  assert.equal(f.calls.length,4);assert.equal(f.calls[2].body.voice,'marin');
});
test('HTTP route authenticates and validates before preparing waiting speech', async () => {
  const f=fixture(), deps=Z.createK135zZoomDependencies({env:f.env,fetchImpl:f.fetchImpl,
    workspaceHttpEnabled:true,workspaceCommandStore:{read:async()=>{},transact:async()=>{},readCaptureLease:async()=>copy(f.row)},
    workspaceCommandTransport:{request:async()=>{},captureActive:()=>true},workspaceTranscriptPreview:()=>{},
    authenticateRequest:async()=>principal,resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
  const h=Z.createK135zZoomHandlers(deps);
  const res=()=>({setHeader(){},status(s){this.statusCode=s;return this;},json(b){this.body=b;return this;}});
  const headers={authorization:'Bearer offline','content-type':'application/json'};
  let r=res();await h.workspaceWaitingVoice({headers:{},body:f.input.body},r);assert.equal(r.statusCode,401);
  r=res();await h.workspaceWaitingVoice({headers,body:{...f.input.body,text:'injected'}},r);assert.equal(r.statusCode,400);
  assert.equal(f.calls.length,0);
  r=res();await h.workspaceWaitingVoice({headers,body:f.input.body},r);assert.equal(r.statusCode,200);
  assert.equal(r.body.waitingVoice.clips.length,2);
});
