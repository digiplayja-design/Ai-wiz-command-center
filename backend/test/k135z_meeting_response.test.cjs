'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createMeetingResponses,assertResponseAuthority}=require('../k135z_zoom/meeting_response.cjs');
const Z=require('../k135z_zoom/zoom_routes.cjs');
const user='11111111-1111-4111-8111-111111111111',principal={tenantId:user,userId:user,agentId:'nova'};
const context={...principal,sessionId:'session',meetingUuid:'meeting',streamId:'stream',generation:1};
const mp3=Buffer.concat([Buffer.from('ID3'),Buffer.alloc(100)]);
const copy=x=>JSON.parse(JSON.stringify(x));
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {resolve,promise};};
function fixture() {
  let now=0,active=true;
  const row={bindingRevision:1,authorityRevision:1,validForMs:30000,authority:{viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true},
    record:{snapshot:{context,revision:2,state:'listening'},pending:null,uncertain:false}};
  const calls=[];let hold,changed;
  const fetchImpl=async(url,options)=>{
    calls.push({url,body:JSON.parse(options.body),signal:options.signal});
    if(hold)await hold.promise;
    if(changed)changed();
    return new Response(url.endsWith('audio/speech')?mp3:JSON.stringify({choices:[{finish_reason:'stop',message:{content:'From the recent captions, the team will review the draft.'}}]}),
      {headers:{'content-type':url.endsWith('audio/speech')?'audio/mpeg':'application/json'}});
  };
  const service=createMeetingResponses({env:{OPENAI_API_KEY:'offline'},fetchImpl,now:()=>now});
  const input={principal,signal:new AbortController().signal,body:{context},
    check:async()=>{assertResponseAuthority(principal,context,row,active);return copy(row);},
    preview:()=>({context,lines:[{speaker:'Host',text:'We will review the draft.'}]})};
  return {row,calls,service,input,fetchImpl,
    hold:d=>hold=d,changed:f=>changed=f,time:t=>now=t,active:v=>active=v,
    draft:()=>service.run({...input,kind:'response'}),
    voice:id=>service.run({...input,kind:'response-voice',body:{context,draftId:id,approved:true}})};
}
test('draft uses server captions only, is partial, and does not synthesize or play audio',async()=>{
  const f=fixture(),r=await f.draft();assert.equal(r.draft.coverage,'partial');assert.equal(f.calls.length,1);
  const body=f.calls[0].body;assert.equal(body.store,false);assert.equal(body.max_completion_tokens,220);
  assert.match(body.messages[0].content,/untrusted/);assert.match(body.messages[1].content,/review the draft/);
  assert.equal(body.messages[1].content.includes(user),false);
});
test('explicit approval produces exact stored words and is single use',async()=>{
  const f=fixture(),{draft}=await f.draft();
  await assert.rejects(f.service.run({...f.input,kind:'response-voice',body:{context,draftId:draft.id,approved:false}}));
  assert.equal(f.calls.length,1);const {voice}=await f.voice(draft.id);
  assert.equal(f.calls[1].body.input,draft.text);assert.equal(voice.audio,mp3.toString('base64'));
  await assert.rejects(f.voice(draft.id),e=>e.code==='K135Z_RESPONSE_DRAFT_EXPIRED');
});
test('foreign context and non-host, paused, unconfirmed and expired sessions never call provider',async()=>{
  for(const mutate of [f=>f.row.authority.hostAuthorized=false,f=>f.row.authority.viewerAuthorized=false,
    f=>f.row.authority.listeningAuthorized=false,f=>f.row.validForMs=0,f=>f.row.record.pending={},
    f=>f.row.record.uncertain=true,f=>f.row.record.snapshot.state='paused',f=>f.active(false),
    f=>f.row.record.snapshot.context={...context,meetingUuid:'other'}]) {
    const f=fixture();mutate(f);await assert.rejects(f.draft());assert.equal(f.calls.length,0);
  }
});
test('permission change during generation discards result',async()=>{
  const f=fixture();f.changed(()=>f.row.authorityRevision++);
  await assert.rejects(f.draft(),e=>e.code==='K135Z_RESPONSE_CONTEXT_CHANGED');
});
test('permission change during synthesis withholds audio',async()=>{
  const f=fixture(),{draft}=await f.draft();f.changed(()=>f.row.record.snapshot.state='stopped');
  await assert.rejects(f.voice(draft.id),e=>e.code==='K135Z_RESPONSE_HOST_REQUIRED');
});
test('cancellation cannot produce a late draft',async()=>{
  const f=fixture(),d=deferred(),abort=new AbortController();f.hold(d);
  const p=f.service.run({...f.input,kind:'response',signal:abort.signal});
  await new Promise(r=>setImmediate(r));abort.abort();d.resolve();await assert.rejects(p);
});
test('expiry and another account cannot use a stored draft',async()=>{
  const f=fixture(),{draft}=await f.draft();
  await assert.rejects(f.service.run({...f.input,principal:{...principal,userId:'another'},kind:'response-voice',
    body:{context,draftId:draft.id,approved:true}}));
  f.time(90001);await assert.rejects(f.voice(draft.id));assert.equal(f.calls.length,1);
});
test('new draft invalidates old approval',async()=>{
  const f=fixture(),old=await f.draft();await f.draft();await assert.rejects(f.voice(old.draft.id));assert.equal(f.calls.length,2);
});
test('concurrent requests and account budget are bounded',async()=>{
  const f=fixture(),d=deferred();f.hold(d);const p=f.draft();await new Promise(r=>setImmediate(r));
  await assert.rejects(f.draft(),e=>e.status===429);d.resolve();await p;f.hold(null);
  for(let n=1;n<20;n++)await f.draft();await assert.rejects(f.draft(),e=>e.status===429);
  assert.equal(f.calls.length,20);
});
test('HTTP routes reject unauthenticated and arbitrary-text requests; authenticated draft roundtrip works',async()=>{
  const f=fixture(),deps=Z.createK135zZoomDependencies({env:{NODE_ENV:'test',OPENAI_API_KEY:'offline'},fetchImpl:f.fetchImpl,
    workspaceHttpEnabled:true,workspaceCommandStore:{read:async()=>{},transact:async()=>{},readCaptureLease:async()=>copy(f.row)},
    workspaceCommandTransport:{request:async()=>{},captureActive:()=>true},workspaceTranscriptPreview:f.input.preview,
    authenticateRequest:async()=>principal,resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
  const handlers=Z.createK135zZoomHandlers(deps);
  const res=()=>({setHeader(){},status(s){this.statusCode=s;return this;},json(b){this.body=b;return this;}});
  const headers={authorization:'Bearer offline','content-type':'application/json'};
  let r=res();await handlers.workspaceResponse({headers:{},body:{context}},r);assert.equal(r.statusCode,401);
  r=res();await handlers.workspaceResponse({headers,body:{context,text:'Injected words'}},r);assert.equal(r.statusCode,400);
  assert.equal(f.calls.length,0);
  r=res();await handlers.workspaceResponse({headers,body:{context}},r);assert.equal(r.statusCode,200);
  assert.equal(r.body.draft.coverage,'partial');
  const v=res();await handlers.workspaceResponseVoice({headers,body:{context,draftId:r.body.draft.id,approved:true}},v);
  assert.equal(v.statusCode,200);assert.equal(v.body.voice.audio,mp3.toString('base64'));
});
test('bad and oversized provider outputs fail without private details',async()=>{
  for(const response of [()=>new Response('private-detail',{status:500}),
    ()=>new Response('x'.repeat(16385)),
    ()=>new Response(JSON.stringify({choices:[{finish_reason:'length',message:{content:'truncated'}}]}))]) {
    const f=fixture(),service=createMeetingResponses({env:{OPENAI_API_KEY:'offline'},fetchImpl:async()=>response()});
    await assert.rejects(service.run({...f.input,kind:'response'}),e=>!e.message.includes('private-detail'));
  }
});
