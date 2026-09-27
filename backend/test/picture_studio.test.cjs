'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const sharp=require('sharp');
const studio=require('../picture_studio.cjs');

async function fixture(flags={}) {
  const buffer=await sharp({create:{width:16,height:12,channels:4,background:{r:90,g:130,b:170,alpha:flags.transparentInput?0.5:1}}}).png().toBuffer();
  const output=await sharp({create:{width:16,height:12,channels:4,background:{r:100,g:140,b:180,alpha:flags.opaqueOutput?1:0.5}}}).png().toBuffer();
  const file={buffer,originalname:'portrait.png',mimetype:'image/png'};
  const calls=[],usage=[],history=[];
  const client={responses:{create:async(body,config)=>{
    calls.push({kind:'analysis',body,config});
    if(flags.analysisError) throw Error('Analysis unavailable');
    if(flags.refusal) return {status:'completed',output:[{content:[{type:'refusal',refusal:'No'}]}]};
    return {status:flags.incomplete?'incomplete':'completed',output_text:flags.badPlan?'not JSON':JSON.stringify({editPrompt:'Balance the visible light; keep the face and exact label text.',summary:'Natural color and light.'})};
  }},images:{edit:async(body,config)=>{
    calls.push({kind:'edit',body,config});
    if(flags.editError) throw Error('Edit unavailable');
    return {data:flags.emptyImage?[]:[{b64_json:flags.invalidImage?'bm90IGFuIGltYWdl':output.toString('base64')}],size:'16x12'};
  }}};
  const toFile=async(bytes,name,options)=>({bytes,name,...options});
  const run=(options={})=>studio.improvePicture({client,toFile,file,options:studio.pictureOptions(options)});
  const source=fs.readFileSync(require.resolve('../server.js'),'utf8');
  const start=source.indexOf('app.post("/api/image/improve"');
  let handler;
  const context={...studio,process:{env:{OPENAI_API_KEY:'offline'}},
    app:{post(_path,...handlers){handler=handlers.at(-1);}},documentUpload:{single:()=>()=>{}},
    isImageUpload:()=>true,requireUser:async()=>{if(flags.anonymous)throw Object.assign(Error('Sign in'),{statusCode:401});return {id:'user'};},
    getOrCreateProfile:async()=>({tier:flags.basic?'basic':'enterprise'}),getOrCreateUsageCounter:async()=>({}),
    hasAdvancedUploadAccess:tier=>tier==='enterprise',checkUsageAllowed:()=>({allowed:!flags.exhausted,reason:'No credits'}),
    createKorlixImprovedImage:async({file:uploaded,options})=>studio.improvePicture({client,toFile,file:uploaded,options}),
    saveGenerationHistory:async data=>{history.push(data);return {id:'saved'};},
    incrementUsage:async data=>{usage.push(data);return {};},sanitize:x=>String(x),getKorlixUserFacingError:e=>e.message,console:{error(){}},
  };
  vm.runInNewContext(source.slice(start,source.indexOf('\n});',start)+4),context);
  const route=async(body={},uploaded=file)=>{
    const result={status:200};
    await handler({body,file:uploaded},{status(value){result.status=value;return this;},json(value){result.body=value;return this;}});
    return result;
  };
  return {file,calls,usage,history,run,route};
}

test('Astra sees the actual image at original detail and xhigh before a max-quality edit',async()=>{
  const f=await fixture();const result=await f.run({prompt:'Keep my hairline. Improve lighting.',imageSize:'1536x2304'});
  assert.equal(f.calls.length,2);const [a,e]=f.calls;
  assert.equal(a.body.model,'gpt-6-astra');assert.equal(a.body.reasoning.effort,'xhigh');assert.equal(a.body.store,false);
  assert.equal(a.body.max_output_tokens,32768);assert.equal(a.body.input[0].content[1].detail,'original');
  assert.match(a.body.input[0].content[1].image_url,/^data:image\/png;base64,/);
  assert.equal(a.body.text.format.strict,true);assert.equal(a.config.maxRetries,0);
  assert.equal(e.body.model,'gpt-image-2.5-sunburst');assert.equal(e.body.quality,'max');assert.equal(e.body.size,'1536x2304');
  assert.equal(e.body.output_format,'png');assert.equal(e.body.n,1);assert.equal(e.body.input_fidelity,undefined);
  assert.deepEqual(e.body.image.bytes,f.file.buffer);assert.match(e.body.prompt,/Keep my hairline/);assert.match(e.body.prompt,/visible light/);
  assert.equal(result.analysisModel,'gpt-6-astra');assert.equal(result.reasoningEffort,'xhigh');assert.equal(result.imageQuality,'max');
});

test('cutout and truly transparent inputs request real transparency; opaque PNGs stay auto',async()=>{
  for(const [flags,body,background] of [[{},{preset:'cutout'},'transparent'],[{transparentInput:true},{},'transparent'],[{}, {},'auto'],[{transparentInput:true},{prompt:'Put me in a garden background'},'auto']]) {
    const f=await fixture(flags);await f.run(body);assert.equal(f.calls[1].body.background,background);
  }
});

test('each treatment and finish changes the grounded edit instructions without rewriting the user request',async()=>{
  for(const preset of ['enhance','restore','headshot','product','cutout','custom']) {
    const options=studio.pictureOptions({preset,strength:'subtle',prompt:'Keep the blue logo text.'});
    const prompt=studio.pictureInstructions(options);
    assert.match(prompt,/Keep the blue logo text/);assert.match(prompt,/restrained/);assert.match(prompt,/hairline/);
  }
  assert.match(studio.pictureInstructions(studio.pictureOptions({preserveIdentity:'false'})),/does not request an identity change/);
});

test('forged models, quality and reasoning cannot downgrade server-owned settings',async()=>{
  const f=await fixture();await f.run({model:'fake',quality:'low',reasoningEffort:'low'});
  assert.equal(f.calls[0].body.reasoning.effort,'xhigh');assert.equal(f.calls[1].body.quality,'max');
});

test('invalid options, oversized instructions and unreadable images fail without provider spend',async()=>{
  for(const body of [{preset:'__proto__'},{strength:'unknown'},{imageSize:'9999x9999'},{preserveIdentity:'maybe'},{prompt:[]},{prompt:'x'.repeat(12001)}]) {
    const f=await fixture();const r=await f.route(body);assert.equal(r.status,400);assert.equal(f.calls.length,0);assert.equal(f.usage.length,0);
  }
  const f=await fixture();const r=await f.route({}, {...f.file,buffer:Buffer.from('not an image')});
  assert.equal(r.status,400);assert.equal(f.calls.length,0);assert.equal(f.history.length,0);
});

test('signed-out, lower-tier and exhausted accounts cannot request analysis or editing',async()=>{
  for(const flags of [{anonymous:true},{basic:true},{exhausted:true}]) {
    const f=await fixture(flags);const r=await f.route();assert(r.status>=400);assert.equal(f.calls.length,0);assert.equal(f.usage.length,0);
  }
});

test('incomplete, refused and malformed analysis fails closed before image editing or charging',async()=>{
  for(const flags of [{analysisError:true},{incomplete:true},{refusal:true},{badPlan:true}]) {
    const f=await fixture(flags);const r=await f.route();assert(r.status>=400);assert.equal(f.calls.length,1);assert.equal(f.usage.length,0);assert.equal(f.history.length,0);
  }
});

test('failed, missing, corrupt or opaque cutout outputs never consume user credits',async()=>{
  for(const flags of [{editError:true},{emptyImage:true},{invalidImage:true},{opaqueOutput:true}]) {
    const f=await fixture(flags);const r=await f.route({preset:'cutout'});assert(r.status>=400);assert.equal(f.usage.length,0);assert.equal(f.history.length,0);
  }
});

test('the active upload route returns real model settings and charges once only after success',async()=>{
  const f=await fixture();const r=await f.route({preset:'restore',prompt:'Keep it black and white.'});
  assert.equal(r.status,200);assert.equal(r.body.analysisModel,'gpt-6-astra');assert.equal(r.body.imageQuality,'max');
  assert.equal(r.body.reasoningEffort,'xhigh');assert.equal(r.body.creditsUsed,1);assert.equal(f.usage.length,1);assert.equal(f.history.length,1);
  assert.match(f.history[0].command,/Keep it black and white/);assert.equal(r.body.editSummary,'Natural color and light.');
});

test('bounded vision copy respects orientation and size while retaining original editor bytes',async()=>{
  const large=await sharp({create:{width:3000,height:2000,channels:3,background:'#8899aa'}}).jpeg().toBuffer();
  const result=await studio.preparePicture({buffer:large});const meta=await sharp(result.analysis).metadata();
  assert.equal(meta.width,2048);assert(meta.height<=2048);assert.equal(result.mime,'image/jpeg');
});
