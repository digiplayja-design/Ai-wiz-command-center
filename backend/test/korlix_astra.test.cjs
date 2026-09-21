'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {TEXT_MODEL, astraRequest, createTextResponse} = require('../korlix_astra.cjs');

test('Astra Responses preserves tools, input and output format without unsupported sampling', () => {
  const original = {model:TEXT_MODEL, input:[{role:'user',content:'Search this'}],
    temperature:0.2, top_p:1, top_logprobs:2, logprobs:true,
    tools:[{type:'web_search'}], tool_choice:'required', store:false,
    text:{format:{type:'json_object'}}, reasoning:{effort:'high'}, max_output_tokens:12000};
  const body = astraRequest(original);
  assert.equal(body.reasoning.effort, 'high');
  assert.equal(body.max_output_tokens, 12000);
  for (const key of ['input','tools','tool_choice','store','text']) assert.deepEqual(body[key],original[key]);
  for (const key of ['temperature','top_p','top_logprobs','logprobs']) assert(!Object.hasOwn(body,key));
  assert.equal(original.temperature,0.2);
});

test('unsupported none/minimal efforts become low; explicit deeper efforts survive', () => {
  for (const effort of ['none','minimal','low','medium','high','xhigh','max']) {
    const body = astraRequest({model:TEXT_MODEL, reasoning:{effort}});
    assert.equal(body.reasoning.effort, ['none','minimal'].includes(effort)?'low':effort);
  }
  assert.throws(()=>astraRequest({model:TEXT_MODEL,reasoning:{effort:'invalid'}}));
});

test('Chat Completions gets the correct reasoning field and a reasoning token allowance', () => {
  const body=astraRequest({model:TEXT_MODEL,reasoning:{effort:'none'},max_tokens:220,temperature:0.2},'chat/completions');
  assert.equal(body.reasoning_effort,'low');assert.equal(body.max_completion_tokens,8192);
  assert(!body.reasoning);assert(!body.max_tokens);assert(!Object.hasOwn(body,'temperature'));
  assert.throws(()=>astraRequest({model:TEXT_MODEL,tools:[{type:'function'}]},'chat/completions'),/Responses/);
});

test('Astra cache settings and output logprobs are migrated without changing other includes', () => {
  const body=astraRequest({model:TEXT_MODEL,prompt_cache_retention:'24h',
    include:['reasoning.encrypted_content','message.output_text.logprobs']});
  assert.deepEqual(body.prompt_cache_options,{ttl:'30m'});
  assert.deepEqual(body.include,['reasoning.encrypted_content']);assert(!body.prompt_cache_retention);
});

test('specialized models and explicit non-Astra fallbacks retain their payloads', () => {
  for(const model of ['gpt-realtime-2.1','gpt-image-1','gpt-4o-mini-tts','text-embedding-3-large','gpt-4o-mini']) {
    const body={model,temperature:0.7,max_output_tokens:220};
    assert.deepEqual(astraRequest(body),body);
  }
});

test('SDK calls preserve request options and reject incomplete Astra responses', async () => {
  const options={signal:new AbortController().signal};let seen;
  const client={responses:{create:async(...args)=>{seen=args;return {status:'completed',output_text:'Answer'};}}};
  assert.equal((await createTextResponse(client,{model:TEXT_MODEL,input:'Hello'},options)).output_text,'Answer');
  assert.equal(seen[0].reasoning.effort,'low');assert.equal(seen[1],options);
  client.responses.create=async()=>({status:'incomplete',output_text:'Partial'});
  await assert.rejects(createTextResponse(client,{model:TEXT_MODEL}),/could not complete/);
});

function serverFunctions(relative, env={}) {
  const source=fs.readFileSync(require.resolve(relative),'utf8');
  const names=['getOpenAIModelForTier','createOpenAIResponse','createAdvancedFileResponse',
    'korlixLiveDocsValidDocumentModel','korlixLiveDocsDocumentModel',
    'korlixLiveDocsDocumentModelRequest','korlixLiveConvoAgentModelProofV1'];
  const definitions=names.map(name=>{
    const match=new RegExp('(?:async )?function '+name+'\\b').exec(source);
    assert(match, name);const end=source.indexOf('\n}\n',match.index);
    return source.slice(match.index,end+2);
  }).join('\n');
  const scope={process:{env},createTextResponse,Buffer,
    buildFileAnalysisPrompt:()=> 'Read the supplied file accurately.',
    getUploadMimeType:file=>file.mimetype,
    isImageUpload:file=>file.mimetype.startsWith('image/'),
    isPdfUpload:file=>file.mimetype==='application/pdf'};
  vm.createContext(scope);vm.runInContext(definitions,scope);return scope;
}

for(const source of ['../server.js','../../server.js']) {
  test(source+': all tier defaults use Astra and configured overrides still work', () => {
    const f=serverFunctions(source);
    for(const tier of ['basic','pro','ultra','enterprise']) assert.equal(f.getOpenAIModelForTier({tier}),TEXT_MODEL);
    const custom=serverFunctions(source,{OPENAI_PRO_MODEL:'gpt-4o-mini'});
    assert.equal(custom.getOpenAIModelForTier({tier:'pro'}),'gpt-4o-mini');
    assert.equal(custom.getOpenAIModelForTier({tier:'ultra'}),TEXT_MODEL);
  });
  test(source+': search and file analysis send Astra-compatible requests', async () => {
    const f=serverFunctions(source);const calls=[];
    const client={responses:{create:async body=>{calls.push(body);return {status:'completed',output_text:'Read'};}}};
    await f.createOpenAIResponse(client,{model:TEXT_MODEL,input:'Question',useSearch:true});
    assert.equal(calls[0].tools[0].type,'web_search');assert.equal(calls[0].tool_choice,'required');
    for(const mimetype of ['image/png','application/pdf','text/plain']) {
      await f.createAdvancedFileResponse({client,file:{mimetype,buffer:Buffer.from('fixture'),originalname:'test'},command:'Read'});
    }
    for(const body of calls) {assert.equal(body.model,TEXT_MODEL);assert.equal(body.reasoning.effort,'low');}
    assert.equal(calls[1].input[0].content[1].type,'input_image');
    assert.equal(calls[2].input[0].content[0].type,'input_file');
  });
  test(source+': LIVE DOCS keeps high reasoning and reports the actual configured model', () => {
    const f=serverFunctions(source);
    const request=f.korlixLiveDocsDocumentModelRequest({input:'Report in JSON'});
    assert.equal(request.model,TEXT_MODEL);assert.equal(request.reasoning.effort,'high');
    assert.equal(request.text.format.type,'json_object');assert.equal(request.max_output_tokens,12000);
    const proof=f.korlixLiveConvoAgentModelProofV1();
    assert.equal(proof.liveDocsDocumentModel,TEXT_MODEL);assert.equal(proof.liveDocsReasoningEffort,'high');
    const custom=serverFunctions(source,{OPENAI_DOCUMENT_MODEL:'gpt-4o-mini'});
    assert.equal(custom.korlixLiveConvoAgentModelProofV1().liveDocsReasoningEffort,'');
  });
}

test('telephone Astra has a reasoning allowance and rejects partial answers', async () => {
  const {createKorlixVapiNovaRuntime}=await import('../korlix_vapi_nova_responder.mjs');
  let body,partial=false;
  const runtime=createKorlixVapiNovaRuntime({
    environment:{OPENAI_API_KEY:'offline',KORLIX_VAPI_NOVA_MODEL:TEXT_MODEL},
    fetchImpl:async(_url,options)=>{body=JSON.parse(options.body);return {ok:true,status:200,
      json:async()=>({status:partial?'incomplete':'completed',output_text:'Welcome to Korlix.'})};}
  });
  assert.equal((await runtime.respond({messages:[{role:'user',content:'Hello'}]})).text,'Welcome to Korlix.');
  assert.equal(body.model,TEXT_MODEL);assert.equal(body.reasoning.effort,'low');
  assert.equal(body.max_output_tokens,8192);assert.equal(body.store,false);
  assert.match(body.instructions,/no Brain Vault access/);
  partial=true;await assert.rejects(runtime.respond({messages:[{role:'user',content:'Hello'}]}),e=>e.code==='nova_model_request_failed');
});
