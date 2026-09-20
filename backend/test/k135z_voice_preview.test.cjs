'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {createVoicePreview, registerVoicePreview, PHRASE, PATH} = require('../k135z_zoom/voice_preview.cjs');
const audio = Buffer.concat([Buffer.from('ID3'),Buffer.alloc(125)]);
const response = () => new Response(audio, {headers:{'content-type':'audio/mpeg'}});
const deferred = () => {let resolve; const promise = new Promise(r => {resolve=r;}); return {promise,resolve};};
const env = {OPENAI_API_KEY:'test-only-key'};

test('fixed greeting is single-flight and cached; callers cannot select content or voice', async () => {
  const d=deferred(), calls=[];
  const generate=createVoicePreview({env,fetchImpl:async(url,options)=>{calls.push([url,options]);await d.promise;return response();}});
  const first=generate({input:'private meeting text'}), second=generate();
  assert.equal(calls.length,1);d.resolve();assert.deepEqual(await first,audio);assert.deepEqual(await second,audio);
  await generate();assert.equal(calls.length,1);
  assert.equal(calls[0][0],'https://api.openai.com/v1/audio/speech');
  const sent=JSON.parse(calls[0][1].body);
  assert.equal(sent.input,PHRASE);assert.equal(sent.voice,'marin');assert.equal(sent.response_format,'mp3');
  assert.ok(!JSON.stringify(sent).includes('private meeting text'));
});
test('voice uses only an allowlisted server setting', async () => {
  for (const [configured,expected] of [['coral','coral'],['PRIVATE_VALUE','marin']]) {
    let payload;
    await createVoicePreview({env:{...env,KORLIX_LIVE_CONVO_VOICE:configured},
      fetchImpl:async(_url,o)=>{payload=JSON.parse(o.body);return response();}})();
    assert.equal(payload.voice,expected);
  }
});
test('failed preparation has cooldown and a hard three-attempt process budget', async () => {
  let clock=0,calls=0;
  const generate=createVoicePreview({env,now:()=>clock,fetchImpl:async()=>{calls++;throw Error('secret-provider-detail');}});
  for(let i=0;i<3;i++){
    await assert.rejects(generate(),e=>e.code==='VOICE_PROVIDER_FAILED'&&!e.message.includes('secret'));
    await assert.rejects(generate(),e=>e.code===(i===2?'VOICE_LIMIT_REACHED':'VOICE_RETRY_LATER'));
    clock+=60001;
  }
  await assert.rejects(generate(),e=>e.code==='VOICE_LIMIT_REACHED');assert.equal(calls,3);
});
test('missing configuration never contacts a provider', async () => {
  let calls=0;
  await assert.rejects(createVoicePreview({env:{},fetchImpl:()=>{calls++;}})(),e=>e.code==='VOICE_NOT_CONFIGURED');
  assert.equal(calls,0);
});
test('provider errors, invalid audio, and oversized clips are never cached or served', async () => {
  const bad=[()=>new Response('private provider error',{status:401}),
    ()=>new Response('not audio',{headers:{'content-type':'audio/mpeg'}}),
    ()=>new Response(Buffer.alloc(1024*1024+1),{headers:{'content-type':'audio/mpeg'}})];
  for(const fetchImpl of bad)await assert.rejects(createVoicePreview({env,fetchImpl})(),e=>e.code==='VOICE_PROVIDER_FAILED');
});
test('provider timeout aborts the request and returns a safe error', async () => {
  let signal;
  const generate=createVoicePreview({env,timeoutMs:10,fetchImpl:(_url,o)=>{
    signal=o.signal;return new Promise((_r,reject)=>signal.addEventListener('abort',()=>reject(Error('private timeout'))));
  }});
  await assert.rejects(generate(),e=>e.code==='VOICE_PROVIDER_FAILED');assert.equal(signal.aborted,true);
});
test('public route rejects supplied text and query before synthesis, then returns only the fixed audio', async () => {
  const routes=new Map();let calls=0;
  registerVoicePreview({post:(p,h)=>routes.set(p,h)},{env,fetchImpl:async()=>{calls++;return response();}});
  const handle=routes.get(PATH);
  const res=()=>({headers:{},setHeader(k,v){this.headers[k]=v;},status(n){this.statusCode=n;return this;},
    json(body){this.body=body;return this;},end(body){this.body=body;return this;}});
  for(const req of [{body:{text:'secret meeting text'}},{body:{},query:{voice:'other'}},{body:[]},{body:null}]){
    const r=res();await handle(req,r);assert.equal(r.statusCode,400);assert.equal(calls,0);
  }
  const r=res();await handle({body:{}},r);
  assert.equal(r.statusCode,200);assert.equal(r.headers['Content-Type'],'audio/mpeg');
  assert.equal(r.headers['Cache-Control'],'no-store');assert.deepEqual(r.body,audio);assert.equal(calls,1);
  const unavailable=new Map();registerVoicePreview({post:(p,h)=>unavailable.set(p,h)},{env:{}});
  const failed=res();await unavailable.get(PATH)({body:{}},failed);
  assert.equal(failed.statusCode,503);assert.deepEqual(failed.body,{code:'VOICE_NOT_CONFIGURED'});
});
async function fixture(load=async()=>audio) {
  const {VoicePreview}=await import('../k135z_zoom/audio_probe/voice_session.mjs');
  const plays=[],d=deferred();let stops=0;
  const player={play:(...args)=>{plays.push(args);return d.promise;},stop:()=>{stops++;}};
  return {p:new VoicePreview({player,load}),player,plays,d,stops:()=>stops};
}
test('preparing is silent; explicit broadcast confirmation and Play are both required', async () => {
  const {p,plays,d}=await fixture();await p.play();await p.prepare();await p.play();assert.equal(plays.length,0);
  p.setReady(true);const played=p.play();assert.equal(plays.length,1);
  assert.equal(plays[0][0],audio);assert.equal(plays[0][1],'audio/mpeg');
  p.confirm(true);assert.equal(p.result,null);d.resolve();await played;assert.equal(p.finished,true);
  assert.equal(p.result,null);p.confirm(true);assert.equal(p.result,true);
});
test('Stop during preparation aborts and ignores late audio without autoplay', async () => {
  const d=deferred();let signal;
  const {p,plays}=await fixture(s=>{signal=s;return d.promise;});
  p.setReady(true);const preparation=p.prepare();p.stop();assert.equal(signal.aborted,true);
  d.resolve(audio);await preparation;assert.equal(p.bytes,null);assert.equal(p.ready,false);
  assert.equal(p.loading,false);assert.equal(plays.length,0);
});
test('an old preparation cannot overwrite a newer one after Stop', async () => {
  const d=deferred();let calls=0;const newer=Buffer.from(audio);
  const {p}=await fixture(()=>++calls===1?d.promise:Promise.resolve(newer));
  const old=p.prepare();p.stop();await p.prepare();d.resolve(audio);await old;
  assert.equal(p.bytes,newer);assert.equal(p.loading,false);assert.equal(p.ready,false);
});
test('Stop silences immediately and stale completion cannot grant confirmation', async () => {
  const {p,d,stops}=await fixture();await p.prepare();p.setReady(true);const played=p.play();p.stop();
  assert.equal(stops(),1);assert.equal(p.playing,false);d.resolve();await played;p.confirm(true);
  assert.equal(p.finished,false);assert.equal(p.result,null);assert.equal(p.ready,false);
});
test('failed replay clears old success and does not retry automatically', async () => {
  const {p,d,player,plays}=await fixture();await p.prepare();p.setReady(true);const first=p.play();
  d.resolve();await first;p.confirm(true);assert.equal(p.result,true);
  let failedPlays=0;player.play=async()=>{failedPlays++;throw Error('private browser error');};
  await p.play();p.confirm(true);assert.equal(p.result,null);assert.equal(p.finished,false);
  assert.equal(failedPlays,1);assert.equal(plays.length,1);assert.ok(!p.message.includes('private'));
});
test('voice media keeps MP3 bytes/type and waits for ended; Stop clears its source', async () => {
  const {MediaTonePlayer}=await import('../k135z_zoom/audio_probe/media_player.mjs');
  const listeners=new Map();let supplied,revoked=0;
  const media={ended:false,pause(){this.paused=true;},removeAttribute(){delete this.src;},load(){},remove(){},setAttribute(){},
    addEventListener:(k,v)=>listeners.set(k,v),removeEventListener:k=>listeners.delete(k),play:async()=>{}};
  const player=new MediaTonePlayer({createAudio:()=>media,createUrl:(bytes,type)=>{supplied={bytes,type};return 'blob:voice';},revokeUrl:()=>{revoked++;}});
  const played=player.play(audio,'audio/mpeg');assert.equal(supplied.bytes,audio);assert.equal(supplied.type,'audio/mpeg');
  assert.equal(media.autoplay,false);assert.equal(media.loop,false);
  const rejected=assert.rejects(played,/STOPPED/);player.stop();await rejected;
  assert.equal(media.paused,true);assert.equal(media.src,undefined);assert.equal(revoked,1);
});
