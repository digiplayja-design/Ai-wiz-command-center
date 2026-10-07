import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

// Execute the actual route callbacks with synthetic authentication/database/
// provider seams. Importing the production server would start live schedulers.
const source=readFileSync(process.env.VIDEO_SERVER_SOURCE || new URL('../server.js',import.meta.url),'utf8');
const paths=['/api/video/status/:videoId','/api/video/content/:videoId',
  '/api/video/image-to-video/status/:jobId','/api/video/image-to-video/content/:jobId'];
function handler(path,{authenticated=true,owned=true}={}) {
  let callback;let providerCalls=0;let ownerChecks=0;
  const start=source.indexOf(`app.get("${path}",`);
  assert(start>=0,'expected video endpoint must exist');
  const end=source.indexOf('\n});',start)+4;
  const job='video_synthetic_b';
  const provider=()=>{providerCalls++;return {ok:true,status:200,headers:{get:()=> 'video/mp4'},arrayBuffer:async()=>new ArrayBuffer(0)};};
  vm.runInNewContext(source.slice(start,end),{
    app:{get:(_path,cb)=>{callback=cb;}},
    requireUser:async()=>{if(!authenticated)throw Object.assign(new Error('Sign in required'),{statusCode:401});return {id:'synthetic-a'};},
    videoAccess:{requireOwnedJob:async({user,jobId,provider})=>{ownerChecks++;assert.equal(user.id,'synthetic-a');assert.equal(jobId,job);assert.equal(provider,'openai');if(!owned)throw Object.assign(new Error('Video not found'),{statusCode:404});}},
    retrieveOpenAIVideo:async()=>{providerCalls++;return {id:job,status:'completed'};},
    fetchOpenAIVideoContent:async()=>{providerCalls++;return {contentType:'video/mp4',buffer:Buffer.alloc(0)};},
    fetch:async()=>provider(),
    korlixI2vProviderUrlV2:()=> 'https://api.openai.example.invalid/v1/videos',
    korlixI2vEnvStringV2:()=>'',korlixI2vApiKeyV2:()=> 'synthetic-provider-key',
    korlixI2vIsOpenAiUrlV2:()=>true,korlixI2vIsKlingUrlV2:()=>false,
    korlixI2vAuthHeadersV2:()=>({}),korlixI2vProviderBodyV2:async()=>({status:'completed'}),
    korlixI2vPublicBaseV2:()=> 'https://app.example.invalid',
    getKorlixUserFacingError:e=>e.message,Buffer,
    console:{error:()=>{}},
  });
  return {async run(){const response={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;},setHeader(){return this;},send(body){this.body=body;return this;}};
    await callback({params:{jobId:job,videoId:job},headers:{}},response);return {code:response.code,providerCalls,ownerChecks};}};
}
for(const path of paths) {
  test(`${path}: anonymous requests never reach the provider`,async()=>{
    const result=await handler(path,{authenticated:false}).run();
    assert.equal(result.code,401);assert.equal(result.providerCalls,0);
  });
  test(`${path}: another user's ID cannot reach the provider`,async()=>{
    const result=await handler(path,{owned:false}).run();
    assert.equal(result.code,404);assert.equal(result.providerCalls,0);assert.equal(result.ownerChecks,1);
  });
  test(`${path}: verified owner retains access`,async()=>{
    const result=await handler(path).run();
    assert.equal(result.code,200);assert.equal(result.providerCalls,1);assert.equal(result.ownerChecks,1);
  });
}
test('image upload rejects anonymous clients before multer buffers the file',async()=>{
  const start=source.indexOf('async function requireVideoUploadUser(');
  assert(start>=0);
  const end=source.indexOf('\napp.post(',start);
  const callback=vm.runInNewContext(source.slice(start,end)+'\nrequireVideoUploadUser',{
    requireUser:async()=>{throw Object.assign(new Error('Sign in required'),{statusCode:401});},getKorlixUserFacingError:e=>e.message,
  });
  let nextCalls=0;const res={code:200,status(code){this.code=code;return this;},json(){return this;}};
  await callback({},res,()=>nextCalls++);
  assert.equal(res.code,401);assert.equal(nextCalls,0);
  assert(source.includes('"/api/video/image-to-video",\n  requireVideoUploadUser,\n  documentUpload.single("image")'));
});
