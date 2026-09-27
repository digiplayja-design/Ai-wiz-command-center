import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerVirtualCloset} from '../virtual_closet/routes.mjs';
import {createTryOn,suggestOutfit,normalizeUpload} from '../virtual_closet/ai.mjs';
let db,server,base,owner,other,usage,bytes,providerCalls,uploadFail,removeFail,providerFail,gate,allowed,storageReads;
const objects=new Map();
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_closet_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function upload({kind='garment',key=randomUUID(),actor=owner,status=201,buffer=bytes}={}){const form=new FormData();form.append('image',new Blob([buffer],{type:'image/jpeg'}),'clothing.png');for(const [k,v]of Object.entries({request_key:key,kind,name:kind==='photo'?'My photo':'Ivory blazer',category:'outerwear'}))form.append(k,v);const r=await fetch(base+'/assets',{method:'POST',headers:{Authorization:actor},body:form});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));return d.asset;}
async function start(extra={},status=202){const p=await upload({kind:'photo'}),g=await upload();return api('/jobs',{request_key:randomUUID(),kind:'tryon',photo_id:p.id,garment_ids:[g.id],prompt:'Business lunch',consent:true,...extra},'POST',owner,status);}
async function finished(id){for(let i=0;i<100;i++){const r=await api('/jobs/'+id);if(r.job.state!=='running')return r;await new Promise(r=>setTimeout(r,10));}throw Error('Job did not finish');}
async function credits(){return (await db.query('select credits_used from usage_counters where id=$1',[usage])).rows[0].credits_used;}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;create policy broad_legacy on storage.objects for all to anon,authenticated using(true) with check(true);grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);grant all on usage_counters to service_role;`);
 await db.exec(await readFile(new URL('../../supabase/migrations/20260927152252_virtual_closet.sql',import.meta.url),'utf8'));
 bytes=await sharp({create:{width:60,height:80,channels:3,background:'#ddd'}}).png().toBuffer();
 const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){if(process.env.CLOSET_DEBUG)console.error(error.message,error.code,error.where);return {error};}}};
 const storage={storage:{from(name){assert.equal(name,'korlix-virtual-closet');return {
  upload:async(path,data)=>{if(uploadFail)return {error:Error('offline')};objects.set(path,data);return {data:{path}};},
  download:async(path)=>{storageReads++;return objects.has(path)?{data:new Blob([objects.get(path)])}:{error:Error('not found')};},
  remove:async(paths)=>{if(removeFail)return {error:Error('offline')};paths.forEach(p=>objects.delete(p));return {data:[]};},
  createSignedUrls:async(paths,ttl)=>{assert.equal(ttl,600);return {data:paths.map(path=>({path,signedUrl:'https://private.test/'+path+'?signed=true'}))};},
 };}}};
 const app=express();app.use(express.json());registerVirtualCloset(app,{database,storageDatabase:storage,
  requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,
  aiAccess:async()=>({allowed,usageId:usage,reason:'Upgrade required'}),logger:{warn(){}},
  tryOn:async()=>{providerCalls++;if(gate)await gate;if(providerFail)throw Error('offline');return {image:bytes,thumb:bytes,width:60,height:80,mime:'image/png',extension:'png',summary:'Ivory blazer outfit.',model:'fixture',quality:'max'};},
  style:async({garments})=>{providerCalls++;if(providerFail)throw Error('offline');return {message:'Try the ivory blazer.',garmentIds:[garments[0].id]};},
 });server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/virtual-closet';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();usage=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);await db.exec('set role service_role');objects.clear();providerCalls=storageReads=0;uploadFail=removeFail=providerFail=false;gate=null;allowed=true;});
test.after(async()=>{await new Promise(r=>server.close(r));await db.close();});
test('uploads decode actual images, normalize originals, and expose only signed owner assets',async()=>{
 const a=await upload();assert.equal(a.state,'ready');assert.match(a.imageUrl,new RegExp(owner));assert.equal(a.path,undefined);assert.equal(a.user_id,undefined);
 const r=await api();assert.equal(r.assets.length,1);assert.equal(objects.size,2);const image=[...objects.values()][0];assert.equal((await sharp(image).metadata()).format,'jpeg');
 const download=await fetch(base+'/assets/'+a.id+'/file',{headers:{Authorization:owner}});assert.equal(download.status,200);assert.equal(download.headers.get('x-content-type-options'),'nosniff');assert.match(download.headers.get('content-disposition'),/attachment/);
 await upload({buffer:Buffer.from('<svg/>'),status:400});await upload({buffer:Buffer.alloc(15*1024*1024+1),status:400});await upload({actor:'',status:401});
});
test('other users cannot list, download, remove or use another person\'s photo',async()=>{
 const a=await upload({kind:'photo'});assert.equal((await api('',null,'GET',other)).assets.length,0);
 await api('/assets/'+a.id+'/file',null,'GET',other,404);await api('/assets/'+a.id,{confirmed:true},'DELETE',other,404);assert.equal(storageReads,0);
 const foreign=await upload({kind:'photo',actor:other});await start({photo_id:foreign.id},404);assert.equal(providerCalls,0);
});
test('same upload key does not create duplicate media; changed bytes require a fresh key',async()=>{
 const key=randomUUID();const a=await upload({key});const b=await upload({key});assert.equal(a.id,b.id);assert.equal(objects.size,2);
 await upload({key,buffer:await sharp(bytes).negate().png().toBuffer(),status:409});
});
test('failed upload and failed deletion are visible and recoverable',async()=>{
 uploadFail=true;const key=randomUUID();await upload({key,status:503});assert.equal((await api()).assets[0].state,'uploading');await upload({key,status:409});
 await db.query("update korlix_closet_assets set lease_until=now()-interval '1 minute' where id=$1",[key]);uploadFail=false;const a=await upload({key});assert.equal(a.state,'ready');
 removeFail=true;await api('/assets/'+key,{confirmed:true},'DELETE',owner,503);const r=await api();assert.equal(r.assets[0].state,'deleting');assert.equal(r.assets[0].imageUrl,null);
 removeFail=false;await api('/assets/'+key,{confirmed:true},'DELETE');assert.equal((await api()).assets.length,0);assert.equal(objects.size,0);
});
test('try-on saves a recoverable look, charges once and replays without new provider calls',async()=>{
 const j=(await start()).job;const done=await finished(j.id);assert.equal(done.job.state,'completed');assert.equal(done.asset.kind,'look');assert.equal(await credits(),1);
 const replay=await api('/jobs',{request_key:j.id,kind:'tryon',photo_id:j.photo_id,garment_ids:j.garment_ids,prompt:j.prompt,consent:true});assert.equal(replay.job.id,j.id);assert.equal(providerCalls,1);assert.equal(await credits(),1);
 await rpc('job_finish',j.id,{result:done.job.result});assert.equal(await credits(),1);
 await api('/jobs/'+j.id,null,'GET',other,404);
});
test('concurrent or duplicate requests cannot create a second paid job',async()=>{
 let release;gate=new Promise(r=>release=r);const j=(await start()).job;
 await api('/jobs',{request_key:randomUUID(),kind:'tryon',photo_id:j.photo_id,garment_ids:j.garment_ids,prompt:'',consent:true},'POST',owner,409);
 await api('/assets/'+j.photo_id,{confirmed:true},'DELETE',owner,409);
 const replay=await api('/jobs',{request_key:j.id,kind:'tryon',photo_id:j.photo_id,garment_ids:j.garment_ids,prompt:j.prompt,consent:true});assert.equal(replay.job.state,'running');
 release();await finished(j.id);assert.equal(providerCalls,1);assert.equal(await credits(),1);
});
test('provider failure, denied access and missing consent never charge',async()=>{
 providerFail=true;const j=(await start()).job;assert.equal((await finished(j.id)).job.state,'failed');assert.equal(await credits(),0);
 allowed=false;await start({},403);await start({consent:false},400);assert.equal(providerCalls,1);
});
test('interrupted jobs fail visibly without an automatic retry or charge',async()=>{
 const p=await upload({kind:'photo'}),g=await upload();const j=await rpc('job_begin',randomUUID(),{kind:'tryon',photo_id:p.id,garment_ids:[g.id],prompt:'',usage_id:usage});
 await db.query("update korlix_closet_jobs set created_at=now()-interval '13 minutes' where id=$1",[j.id]);const r=await api('/jobs/'+j.id);assert.equal(r.job.state,'failed');assert.match(r.job.error,/interrupted/);assert.equal(providerCalls,0);assert.equal(await credits(),0);
});
test('Nova suggestions use owned wardrobe records and charge only once',async()=>{
 const a=await upload();const j=(await api('/jobs',{request_key:randomUUID(),kind:'style',prompt:'Business lunch',consent:true},'POST',owner,202)).job;
 const done=await finished(j.id);assert.equal(done.job.result.garmentIds[0],a.id);assert.equal(await credits(),1);
});
test('photo quota is enforced and confirmed deletion releases the slot',async()=>{
 const photos=[];for(let i=0;i<5;i++)photos.push(await upload({kind:'photo'}));await upload({kind:'photo',status:429});await api('/assets/'+photos[0].id,{confirmed:true},'DELETE');await upload({kind:'photo'});
});
test('RLS, grants and restrictive bucket policy block direct client access',async()=>{
 await db.exec("reset role;insert into storage.objects values('closet','korlix-virtual-closet'),('other','unrelated');set role authenticated;");
 try{assert.deepEqual((await db.query('select id from storage.objects')).rows,[{id:'other'}]);await assert.rejects(db.query('select * from korlix_closet_assets'),/permission denied/);await assert.rejects(rpc('list'),/permission denied/);await assert.rejects(db.query("insert into storage.objects values('attack','korlix-virtual-closet')"),/row-level security/);}finally{await db.exec('reset role;set role service_role');}
});
test('vision planning and editing use all references, identity rules and maximum quality',async()=>{
 const image=(await normalizeUpload({buffer:bytes})).image;const calls=[];const client={responses:{create:async(body,options)=>{calls.push({body,options});return {status:'completed',output_text:JSON.stringify({editPrompt:'Match the supplied blazer.',summary:'Ivory blazer outfit.'})};}},images:{edit:async(body,options)=>{calls.push({body,options});return {data:[{b64_json:bytes.toString('base64')}]};}}};
 const out=await createTryOn({client,toFile:async(bytes,name)=>({bytes,name}),photo:{bytes:image},garments:[{bytes:image,name:'Blazer',category:'outerwear'}],prompt:'Business lunch'});
 assert.equal(calls[0].body.model,'gpt-6-astra');assert.equal(calls[0].body.reasoning.effort,'xhigh');assert.equal(calls[0].body.store,false);assert.equal(calls[0].body.input[0].content.filter(c=>c.type==='input_image').length,2);
 assert.equal(calls[1].body.image.length,2);assert.equal(calls[1].body.quality,'max');assert.match(calls[1].body.prompt,/body shape/);assert.equal(calls[1].body.input_fidelity,undefined);assert.equal(out.mime,'image/png');
 client.images.edit=async()=>({data:[{b64_json:'bad'}]});await assert.rejects(createTryOn({client,toFile:async()=>({}),photo:{bytes:image},garments:[{bytes:image,name:'Blazer',category:'outerwear'}],prompt:''}),/unreadable/);
});
test('stylist rejects invented IDs and incomplete model responses',async()=>{
 const id=randomUUID();const client={responses:{create:async()=>({status:'completed',output_text:JSON.stringify({message:'Try this.',garmentIds:[randomUUID()]})})}};
 await assert.rejects(suggestOutfit({client,garments:[{id,name:'Blazer',category:'outerwear'}],prompt:'Lunch'}),/match an outfit/);
 client.responses.create=async()=>({status:'incomplete'});await assert.rejects(suggestOutfit({client,garments:[{id,name:'Blazer',category:'outerwear'}],prompt:'Lunch'}),/did not finish/);
});
