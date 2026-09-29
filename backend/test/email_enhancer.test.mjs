import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {normalizeEmailInput,validateEmailResult,enhanceEmail,registerEmailEnhancer} from '../email_enhancer/enhancer.mjs';
const brief={source:'Please confirm invoice 104 for $200 by October 2.',context:'',recipient:'Jordan',goal:'Confirm receipt',signature:'Alex',mode:'Polish',tone:'Professional',length:'Shorter',language:'Original language'};
const result={subjects:['Invoice 104 confirmation','Please confirm receipt','Following up on invoice 104'],body:'Hi Jordan,\nPlease confirm receipt of invoice 104 for $200 by October 2.\nAlex',changes:['Clarified the request.','Added a greeting.'],checks:['Confirm the date before sending.']};
test('all supported workflows are bounded and reply intent is required',()=>{
  assert.deepEqual(normalizeEmailInput(brief),brief);
  for(const patch of [{source:''},{source:'x'.repeat(12001)},{mode:'Reply'},{tone:'Invented'},{language:'unknown'},{context:[]},{signature:'\0'}]) assert.throws(()=>normalizeEmailInput({...brief,...patch}));
  assert.equal(normalizeEmailInput({...brief,mode:'Reply',context:'Say I can attend.'}).mode,'Reply');
});
test('malformed, oversized and header-injecting provider output is rejected',()=>{
  assert.deepEqual(validateEmailResult(result),result);
  for(const patch of [{body:''},{body:'x'.repeat(18001)},{subjects:['Only one']},{subjects:['A\r\nBcc: x','B','C']},{checks:[{}]},{changes:Array(6).fill('Too many')}]) assert.throws(()=>validateEmailResult({...result,...patch}));
});
test('generation is structured, text-only, no provider storage or tool access',async()=>{
  let request,options;
  const client={responses:{create:async(r,o)=>{request=r;options=o;return {status:'completed',output_text:JSON.stringify(result)};}}};
  assert.deepEqual(await enhanceEmail({client,input:brief}),result);
  assert.equal(request.store,false);assert.equal(request.tools,undefined);assert.equal(request.text.format.strict,true);assert.equal(options.maxRetries,0);
  assert.deepEqual(JSON.parse(request.input[0].content),brief);assert.match(request.instructions,/never invent facts/i);assert.match(request.instructions,/K-Nova/);
  for(const response of [{status:'incomplete',output_text:JSON.stringify(result)},{status:'completed',output_text:'not json'},{status:'completed',output:[{content:[{type:'refusal'}]}]}]) await assert.rejects(enhanceEmail({client:{responses:{create:async()=>response}},input:brief}));
});
test('authenticated route enforces consent, credits, isolated retries and failures',async t=>{
  let calls=0,charges=0,allowed=true,broken=false,clock=0,pending;
  const app=express();app.use(express.json());
  registerEmailEnhancer(app,{requireUser:async r=>r.headers.authorization?{id:r.headers.authorization}:null,access:async()=>({allowed,reason:'No credits'}),charge:async()=>{charges++;},generate:async()=>{calls++;if(pending)await pending;if(broken)throw Error('private email detail');return result;},now:()=>clock,logger:{warn(){}}});
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>server.close());const base=`http://127.0.0.1:${server.address().port}/api/email-enhancer`;
  async function send(body={},user='a',expected=200){const r=await fetch(base,{method:'POST',headers:{'Content-Type':'application/json',...(user?{Authorization:user}:{})},body:JSON.stringify({...brief,consent:true,requestKey:randomUUID(),...body})});const j=await r.json();assert.equal(r.status,expected,JSON.stringify(j));assert.equal(r.headers.get('cache-control'),'no-store');return j;}
  await send({},'',401);await send({consent:false},'a',400);await send({requestKey:'bad'},'a',400);allowed=false;await send({},'a',429);assert.equal(calls,0);allowed=true;
  const key=randomUUID();await send({requestKey:key});await send({requestKey:key});assert.equal(calls,1);assert.equal(charges,1);
  await send({requestKey:key,source:'Different valid source'},'a',409);await send({requestKey:key},'b');assert.equal(charges,2);
  let release;pending=new Promise(r=>release=r);const inFlight=send();while(calls<3)await new Promise(r=>setTimeout(r,5));await send({},'a',409);release();await inFlight;pending=null;assert.equal(charges,3);
  broken=true;const failed=await send({},'a',503);assert.doesNotMatch(failed.error,/private email/);assert.equal(charges,3);broken=false;
  clock=16*60*1000;await send({requestKey:key});assert.equal(charges,4);
});
