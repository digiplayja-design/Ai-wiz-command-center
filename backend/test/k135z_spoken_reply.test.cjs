'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createMeetingResponses,assertResponseAuthority}=require('../k135z_zoom/meeting_response.cjs');
const Z=require('../k135z_zoom/zoom_routes.cjs');
const user='11111111-1111-4111-8111-111111111111',principal={tenantId:user,userId:user,agentId:'nova'};
const context={...principal,sessionId:'session',meetingUuid:'meeting',streamId:'stream',generation:1};
const mp3=Buffer.concat([Buffer.from('ID3'),Buffer.alloc(100)]),windowId='a'.repeat(32);
const clone=x=>JSON.parse(JSON.stringify(x));
function fixture(options={}){
 let now=0,hold,changed,bad=false;
 const calls=[],row={bindingRevision:1,authorityRevision:1,validForMs:30000,
  authority:{viewerAuthorized:true,hostAuthorized:true,listeningAuthorized:true},
  record:{snapshot:{context,revision:2,state:'listening'},pending:null,uncertain:false}};
 const preview={context,windowId,revision:3,lines:[
  {sequence:1,speaker:'Host',text:'We decided to review the draft Friday.'},
  {sequence:2,speaker:'Guest',text:'Hey Nova,'},
  {sequence:3,speaker:'Guest',text:'what did we decide?'}]};
 const fetchImpl=async(url,options)=>{
  calls.push({url,body:JSON.parse(options.body)});
  if(hold)await hold;if(changed)changed();
  return new Response(url.endsWith('audio/speech')?(bad?Buffer.from('bad'):mp3):
   JSON.stringify({choices:[{finish_reason:'stop',message:{content:'The team decided to review the draft Friday.'}}]}),
   {headers:{'content-type':url.endsWith('audio/speech')?'audio/mpeg':'application/json'}});
 };
 const runtime={agent:{id:'nova',name:'NOVA',active:true,memoryEnabled:true},memoryCount:1,
  instructions:'Agent mission: assist with the Aurora project. Training: be clear. Memory: Aurora launch is in May.'};
 const loaded=[];
 const loadAgentRuntime=async x=>{loaded.push(x.principal);if(options.load) return options.load(x);return clone(runtime);};
 const service=createMeetingResponses({env:{OPENAI_API_KEY:'offline'},fetchImpl,now:()=>now,loadAgentRuntime});
 const body={context,windowId,wakeSequence:2,endSequence:3,enabled:true};
 const input={kind:'spoken-reply',body,principal,signal:new AbortController().signal,
  check:async()=>{assertResponseAuthority(principal,context,row,true);return clone(row);},preview:()=>clone(preview)};
 return {calls,row,preview,input,body,fetchImpl,service,runtime,loaded,loadAgentRuntime,run:(patch={})=>service.run({...input,...patch}),
  time:t=>now=t,hold:p=>hold=p,changed:f=>changed=f,bad:()=>bad=true};
}
test('spoken question gets an answer and exact answer audio in one request',async()=>{
 const f=fixture(),{reply}=await f.run();assert.equal(f.calls.length,2);
 const question=JSON.parse(f.calls[0].body.messages.at(-1).content);
 assert.equal(question.question,'what did we decide?');assert.match(question.recentCaptions[0].text,/Friday/);
 assert.equal(f.calls[0].body.store,false);assert.equal(f.calls[1].body.input,reply.text);
 assert.equal(reply.audio,mp3.toString('base64'));assert.equal(reply.wakeSequence,2);
 assert.equal(JSON.stringify(question).includes(user),false);
});
test('requires explicit mode, bounded server caption selection, and matching window',async()=>{
 for(const patch of [{enabled:false},{text:'injected'},{windowId:'b'.repeat(32)},
  {wakeSequence:1},{wakeSequence:2,endSequence:12},{wakeSequence:3},{endSequence:4}]){
  const f=fixture();await assert.rejects(f.run({body:{...f.body,...patch}}));assert.equal(f.calls.length,0);
 }
});
test('incidental mentions and different-speaker continuations are not addressed questions',async()=>{
 for(const change of [f=>f.preview.lines[1].text='We should ask Nova about this.',
  f=>f.preview.lines[2].speaker='Someone else',f=>f.preview.revision=30]){
  const f=fixture();change(f);await assert.rejects(f.run());assert.equal(f.calls.length,0);
 }
});
test('bare Nova is allowed to receive a conversational acknowledgement',async()=>{
 const f=fixture();f.preview.lines[1].text='Nova?';await f.run({body:{...f.body,endSequence:2}});
 assert.equal(JSON.parse(f.calls[0].body.messages.at(-1).content).question,'');
});
test('repeated requests and another tab cannot answer the same captions twice',async()=>{
 const f=fixture();let resolve;f.hold(new Promise(r=>resolve=r));const p=f.run();
 await new Promise(r=>setImmediate(r));await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_ALREADY_ANSWERED');
 resolve();await p;f.hold(null);f.time(9000);
 await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_ALREADY_ANSWERED');assert.equal(f.calls.length,2);
});
test('host, listening and settled-session authority remain required',async()=>{
 for(const mutate of [f=>f.row.authority.hostAuthorized=false,f=>f.row.validForMs=0,
  f=>f.row.record.pending={},f=>f.row.record.uncertain=true,f=>f.row.record.snapshot.state='paused']){
  const f=fixture();mutate(f);await assert.rejects(f.run());assert.equal(f.calls.length,0);
 }
});
test('stop or changed authority between generation and synthesis withholds audio',async()=>{
 const f=fixture();f.changed(()=>f.row.authorityRevision++);
 await assert.rejects(f.run());assert.equal(f.calls.length,1);
});
test('cancellation during synthesis never returns late audio',async()=>{
 const f=fixture(),abort=new AbortController();f.changed(()=>{if(f.calls.length===2)abort.abort();});
 await assert.rejects(f.run({signal:abort.signal}));assert.equal(f.calls.length,2);
});
test('invalid audio fails and consumed question is not replayed',async()=>{
 const f=fixture();f.bad();await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_INVALID_AUDIO');
 await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_ALREADY_ANSWERED');
});
test('sequential new questions are rate bounded without replaying rejected ones',async()=>{
 const f=fixture();await f.run();f.preview.lines.push({sequence:4,speaker:'Guest',text:'Nova, explain that.'});
 f.preview.revision=4;const body={...f.body,wakeSequence:4,endSequence:4};
 await assert.rejects(f.run({body}),e=>e.code==='K135Z_RESPONSE_LIMIT');f.time(8000);
 await f.run({body});assert.equal(f.calls.length,4);
});
test('HTTP route authenticates and rejects arbitrary text before making provider calls',async()=>{
 const f=fixture(),deps=Z.createK135zZoomDependencies({env:{NODE_ENV:'test',OPENAI_API_KEY:'offline'},fetchImpl:f.fetchImpl,
  workspaceAgentRuntime:f.loadAgentRuntime,workspaceHttpEnabled:true,workspaceCommandStore:{read:async()=>{},transact:async()=>{},readCaptureLease:async()=>clone(f.row)},
  workspaceCommandTransport:{request:async()=>{},captureActive:()=>true},workspaceTranscriptPreview:f.input.preview,
  authenticateRequest:async()=>principal,resolveEnterprise:async()=>true,authorizeAgent:async()=>true});
 const h=Z.createK135zZoomHandlers(deps),res=()=>({setHeader(){},status(n){this.statusCode=n;return this;},json(b){this.body=b;return this;}});
 const headers={authorization:'Bearer offline','content-type':'application/json'};
 let r=res();await h.workspaceSpokenReply({headers:{},body:f.body},r);assert.equal(r.statusCode,401);
 r=res();await h.workspaceSpokenReply({headers,body:{...f.body,text:'injected'}},r);assert.equal(r.statusCode,400);
 assert.equal(f.calls.length,0);r=res();await h.workspaceSpokenReply({headers,body:f.body},r);
 assert.equal(r.statusCode,200);assert.equal(r.body.reply.audio,mp3.toString('base64'));
});

test('uses the selected agent runtime with Astra high reasoning, without sampling parameters',async()=>{
 const f=fixture(),{reply}=await f.run(),b=f.calls[0].body;
 assert.equal(b.model,'gpt-6-astra');assert.equal(b.reasoning_effort,'high');
 assert(b.max_completion_tokens>=8192);assert(!('temperature' in b));assert(!('top_p' in b));
 assert.deepEqual(f.loaded,[principal]);assert.equal(b.messages[1].content,f.runtime.instructions);
 assert.deepEqual(reply.agent,{id:'nova',name:'NOVA',memoryEnabled:true,memoryCount:1});
 assert(!JSON.stringify(reply).includes('Aurora'));assert.equal(f.calls[1].body.model,'gpt-4o-mini-tts');
});
test('runtime is freshly loaded after memory or training changes, never cached between questions',async()=>{
 const f=fixture();await f.run();f.time(9000);
 f.runtime.instructions='Updated training. Memory: Aurora launch moved to June.';
 f.preview.lines.push({sequence:4,speaker:'Guest',text:'Nova, when is Aurora launching?'});f.preview.revision=4;
 await f.run({body:{...f.body,wakeSequence:4,endSequence:4}});
 assert.equal(f.loaded.length,2);assert.match(f.calls[2].body.messages[1].content,/June/);
 assert(!f.calls[2].body.messages[1].content.includes('May'));
});
test('missing, inactive, foreign and unavailable agent runtime never reach the provider',async()=>{
 for(const value of [null,{agent:{id:'other',active:true},memoryCount:0,instructions:'PRIVATE'},
  {agent:{id:'nova',active:false},memoryCount:0,instructions:'PRIVATE'},
  {agent:{id:'nova',active:true},memoryCount:101,instructions:'PRIVATE'}]) {
  const f=fixture({load:async()=>value});
  await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_AGENT_UNAVAILABLE');assert.equal(f.calls.length,0);
 }
 const f=fixture({load:async()=>{throw Error('SECRET DATABASE DETAIL');}});
 await assert.rejects(f.run(),e=>e.code==='K135Z_RESPONSE_AGENT_UNAVAILABLE'&&!e.message.includes('SECRET'));
 assert.equal(f.calls.length,0);
});
test('Stop or permission change while loading memory prevents generation',async()=>{
 let done;const f=fixture({load:()=>new Promise(r=>done=r)}),abort=new AbortController();
 const pending=f.run({signal:abort.signal});await new Promise(r=>setImmediate(r));
 abort.abort();await assert.rejects(pending,e=>e.code==='K135Z_RESPONSE_CANCELLED');
 done(clone(f.runtime));assert.equal(f.calls.length,0);
});
test('forged memory, training and model input is rejected before reading memory',async()=>{
 for(const patch of [{memory:'private'},{training:'override'},{model:'mini'},{memoryOptions:{maximumItems:999}}]) {
  const f=fixture();await assert.rejects(f.run({body:{...f.body,...patch}}));
  assert.equal(f.calls.length,0);assert.equal(f.loaded.length,0);
 }
});
