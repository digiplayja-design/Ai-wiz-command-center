import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerBabyBlend} from '../babyblend/routes.mjs';
import {createPortrait,normalizeUpload,options} from '../babyblend/ai.mjs';
let db,server,base,owner,other,usage,bytes,bytes2,calls,uploadFail,removeFail,providerFail,gate,allowed,reads;
const objects=new Map();
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_babyblend_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function upload({key=randomUUID(),actor=owner,status=201,buffer=bytes}={}){const f=new FormData();f.append('image',new Blob([buffer],{type:'image/png'}),'person.png');f.append('request_key',key);const r=await fetch(base+'/photos',{method:'POST',headers:{Authorization:actor},body:f});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));return d.asset;}
async function pair(){return [(await upload()).id,(await upload({buffer:bytes2})).id];}
const body=(ids,extra={})=>({request_key:randomUUID(),photo_ids:ids,age:'baby',style:'natural',consent:true,adult_photo_permission:true,...extra});
async function done(id){for(let i=0;i<150;i++){const r=await api('/jobs/'+id);if(r.job.state!=='running')return r;await new Promise(r=>setTimeout(r,10));}throw Error('Portrait did not finish');}
async function credits(){return (await db.query('select credits_used from usage_counters where id=$1',[usage])).rows[0].credits_used;}
test.before(async()=>{db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;create policy broad_legacy on storage.objects for all to anon,authenticated using(true) with check(true);grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);grant all on usage_counters to service_role;`);
 const dir=new URL('../../supabase/migrations/',import.meta.url);await db.exec(await readFile(new URL((await readdir(dir)).find(x=>x.endsWith('_babyblend.sql')),dir),'utf8'));
 bytes=await sharp({create:{width:60,height:80,channels:3,background:'#abcdde'}}).png().withMetadata().toBuffer();bytes2=await sharp(bytes).negate().png().toBuffer();
 const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){if(process.env.BABYBLEND_DEBUG)console.error(error.message,error.code,error.where);return {error};}}};
 const storage={storage:{from(name){assert.equal(name,'korlix-babyblend');return {
 upload:async(path,data)=>{if(uploadFail)return {error:Error('offline')};objects.set(path,Buffer.from(data));return {data:{path}};},
 download:async(path)=>{reads++;return objects.has(path)?{data:new Blob([objects.get(path)])}:{error:Error('missing')};},
 remove:async(paths)=>{if(removeFail)return {error:Error('offline')};paths.forEach(p=>objects.delete(p));return {data:[]};},
 createSignedUrls:async(paths,ttl)=>{assert.equal(ttl,600);return {data:paths.map(path=>({path,signedUrl:'https://private.test/'+path+'?signed=true'}))};}
 };}}};
 const app=express();app.use(express.json());registerBabyBlend(app,{database,storageDatabase:storage,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,
 aiAccess:async()=>({allowed,usageId:usage,reason:'Upgrade required'}),logger:{warn(){}},generate:async({photos,age,style})=>{calls++;assert.equal(photos.length,2);assert.notEqual(photos[0].digest,photos[1].digest);if(gate)await gate;if(providerFail)throw Error('offline');return {image:bytes,thumb:bytes2,width:60,height:80,mime:'image/png',extension:'png',summary:'AI imagining',model:'fixture',quality:'max',age,style};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/babyblend';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();usage=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);await db.exec('set role service_role');objects.clear();calls=reads=0;uploadFail=removeFail=providerFail=false;gate=null;allowed=true;});
test.after(async()=>{if(server)await new Promise(r=>server.close(r));await db?.close();});
test('source photos are private, normalized and signed; malformed/oversize uploads are rejected',async()=>{
 await api('',null,'GET','',401);const a=await upload();assert.equal(a.kind,'source');assert.equal(a.state,'ready');assert.equal(a.user_id,undefined);assert.equal(a.path,undefined);assert.match(a.imageUrl,/signed=true/);const b=[...objects.values()][0],m=await sharp(b).metadata();assert.equal(m.format,'jpeg');assert.equal(m.exif,undefined);
 await upload({buffer:Buffer.from('<svg/>'),status:400});await upload({buffer:Buffer.alloc(15*1024*1024+1),status:400});await upload({actor:'',status:401});
});
test('foreign source photos, jobs and downloads cannot be read, removed or rendered',async()=>{
 const ids=await pair();assert.equal((await api('',null,'GET',other)).assets.length,0);await api('/assets/'+ids[0]+'/file',null,'GET',other,404);await api('/assets/'+ids[0],{confirmed:true},'DELETE',other,404);await api('/jobs',body(ids),'POST',other,404);assert.equal(reads,0);assert.equal(calls,0);
});
test('upload replay is exact and interrupted uploads recover with their lease',async()=>{
 const key=randomUUID();uploadFail=true;await upload({key,status:503});assert.equal((await api()).assets[0].state,'uploading');await upload({key,status:409});
 await db.query("update korlix_babyblend_assets set lease_until=now()-interval '1 minute' where id=$1",[key]);uploadFail=false;const a=await upload({key}),b=await upload({key});assert.equal(a.id,b.id);assert.equal(objects.size,2);await upload({key,buffer:bytes2,status:409});
});
test('generation persists a portrait and charges once even on replay and repeated finish',async()=>{
 const request=body(await pair()),j=(await api('/jobs',request,'POST',owner,202)).job,r=await done(j.id);assert.equal(r.job.state,'completed');assert.equal(r.asset.id,j.id);assert.equal(r.asset.kind,'portrait');assert.equal(r.job.charged,1);assert.equal(await credits(),1);assert.equal(r.job.usage_id,undefined);assert.equal(r.job.photoIds.length,2);
 allowed=false;const replay=await api('/jobs',request);assert.equal(replay.job.id,j.id);assert.equal(calls,1);await rpc('job_finish',j.id,{result:r.job.result});assert.equal(await credits(),1);await api('/jobs/'+j.id,null,'GET',other,404);
 const file=await fetch(base+'/assets/'+j.id+'/file',{headers:{Authorization:owner}});assert.equal(file.status,200);assert.equal(file.headers.get('content-type'),'image/png');assert.equal(file.headers.get('x-content-type-options'),'nosniff');assert.deepEqual(Buffer.from(await file.arrayBuffer()),bytes);
});
test('changed generation payload, duplicate photo IDs and duplicate source bytes are rejected',async()=>{
 const ids=await pair();await api('/jobs',body([ids[0],ids[0]]),'POST',owner,400);const copy=await upload();await api('/jobs',body([ids[0],copy.id]),'POST',owner,400);const request=body(ids),j=(await api('/jobs',request,'POST',owner,202)).job;await done(j.id);await api('/jobs',{...request,age:'toddler'},'POST',owner,409);await api('/jobs',{...request,photo_ids:[...ids].reverse()},'POST',owner,409);assert.equal(calls,1);
});
test('running jobs resume without redispatch and protect the references from deletion',async()=>{
 let release;gate=new Promise(r=>release=r);const request=body(await pair()),j=(await api('/jobs',request,'POST',owner,202)).job;await api('/jobs',body(request.photo_ids),'POST',owner,409);await api('/assets/'+request.photo_ids[0],{confirmed:true},'DELETE',owner,409);assert.equal((await api('/jobs',request)).job.state,'running');release();await done(j.id);assert.equal(calls,1);assert.equal(await credits(),1);
});
test('permission, consent, invalid options and denied entitlement block dispatch',async()=>{
 const ids=await pair();for(const extra of [{consent:false},{adult_photo_permission:false},{age:'adult'},{style:'medical'},{photo_ids:ids.slice(0,1)}])await api('/jobs',body(ids,extra),'POST',owner,400);allowed=false;await api('/jobs',body(ids),'POST',owner,403);assert.equal(calls,0);assert.equal(await credits(),0);
});
test('provider failure and portrait storage failure never create a ready uncharged output',async()=>{
 const ids=await pair();providerFail=true;let j=(await api('/jobs',body(ids),'POST',owner,202)).job;assert.equal((await done(j.id)).job.state,'failed');providerFail=false;uploadFail=true;j=(await api('/jobs',body(ids),'POST',owner,202)).job;assert.equal((await done(j.id)).job.state,'failed');const a=(await api()).assets.find(x=>x.kind==='portrait');assert.equal(a.state,'uploading');assert.equal(a.imageUrl,null);await api('/assets/'+a.id+'/file',null,'GET',owner,409);assert.equal(await credits(),0);
});
test('interrupted generation times out and late output cannot charge or become public',async()=>{
 const ids=await pair(),j=await rpc('job_begin',randomUUID(),{photo_ids:ids,age:'baby',style:'natural',usage_id:usage});await db.query("update korlix_babyblend_jobs set created_at=now()-interval '13 minutes' where id=$1",[j.id]);assert.equal((await api('/jobs/'+j.id)).job.state,'failed');await rpc('job_finish',j.id,{result:{assetId:j.id}});assert.equal(await credits(),0);assert.equal(calls,0);
});
test('source and portrait downloads reject changed stored bytes before rendering',async()=>{
 const ids=await pair();objects.set([...objects.keys()].find(p=>p.includes(ids[0])&&p.endsWith('image.jpg')),Buffer.from('changed'));
 await api('/assets/'+ids[0]+'/file',null,'GET',owner,503);const j=(await api('/jobs',body(ids),'POST',owner,202)).job;assert.equal((await done(j.id)).job.state,'failed');assert.equal(calls,0);assert.equal(await credits(),0);
});
test('deletion is confirmed and retryable, and removes both normalized files',async()=>{
 const a=await upload();await api('/assets/'+a.id,{},'DELETE',owner,400);removeFail=true;await api('/assets/'+a.id,{confirmed:true},'DELETE',owner,503);assert.equal((await api()).assets[0].state,'deleting');removeFail=false;await api('/assets/'+a.id,{confirmed:true},'DELETE');assert.equal(objects.size,0);assert.equal((await api()).assets.length,0);
});
test('source quota is enforced and removal releases a slot',async()=>{
 for(let i=0;i<10;i++)await upload();await upload({status:429});const ids=(await api()).assets.map(a=>a.id);await api('/assets/'+ids[0],{confirmed:true},'DELETE');await upload();
 assert.equal((await api()).assets.length,10);
});
test('RLS, RPC grants and restrictive bucket policy block direct client access',async()=>{
 await upload();await db.exec('reset role');assert.equal((await db.query("select count(*) n from pg_class where relname in ('korlix_babyblend_assets','korlix_babyblend_jobs') and relrowsecurity")).rows[0].n,2);
 await db.query("insert into storage.objects values('blocked','korlix-babyblend'),('allowed','other')");await db.exec('set role authenticated');await assert.rejects(()=>db.query('select * from korlix_babyblend_assets'),/permission denied/);await assert.rejects(()=>rpc('list'),/permission denied/);assert.deepEqual((await db.query('select id from storage.objects')).rows,[{id:'allowed'}]);
});
test('vision planning and maximum-quality rendering use both references and fixed creative limits',async()=>{
 let planned,rendered;const out=await createPortrait({photos:[{bytes},{bytes:bytes2}],age:'toddler',style:'studio',toFile:async(b,n,m)=>({b,n,m}),client:{responses:{create:async(q,o)=>{planned=q;assert.equal(o.maxRetries,0);return {status:'completed',output_text:JSON.stringify({decision:'ready',editPrompt:'Soft light and a coherent fictional face.'})};}},images:{edit:async(q,o)=>{rendered=q;assert.equal(o.maxRetries,0);return {data:[{b64_json:bytes.toString('base64')}]};}}}});
 assert.equal(planned.model,'gpt-6-astra');assert.equal(planned.reasoning.effort,'max');assert.equal(planned.store,false);assert.equal(planned.input[0].content.filter(x=>x.type==='input_image').length,2);assert.equal(rendered.image.length,2);assert.equal(rendered.quality,rendered.model.startsWith('gpt-image-2.5-')?'max':'high');assert.equal(rendered.size,'1024x1536');assert.match(rendered.prompt,/two years/);assert.match(rendered.prompt,/studio portrait/);assert.match(rendered.prompt,/never a genetic/);assert.match(rendered.prompt,/fully clothed/);assert.match(out.summary,/not a genetic prediction/);
});
test('unsuitable references, refused analysis and invalid image output fail without an edit retry',async()=>{
 for(const decision of ['needs_clearer_photo','adult_photo_required','unknown']){let edited=false;await assert.rejects(()=>createPortrait({photos:[{bytes},{bytes:bytes2}],age:'baby',style:'natural',toFile:async()=>({}),client:{responses:{create:async()=>({status:'completed',output_text:JSON.stringify({decision,editPrompt:'Plan'})})},images:{edit:async()=>{edited=true;}}}}));assert.equal(edited,false);}
 await assert.rejects(()=>createPortrait({photos:[{bytes},{bytes:bytes2}],age:'child',style:'artistic',toFile:async()=>({}),client:{responses:{create:async()=>({status:'completed',output_text:JSON.stringify({decision:'ready',editPrompt:'Plan'})})},images:{edit:async()=>({data:[{b64_json:Buffer.from('bad').toString('base64')}]})}}}),/could not be read/);
 assert.throws(()=>options({age:'baby',style:'__proto__',photo_ids:[randomUUID(),randomUUID()]}));const prepared=await normalizeUpload({buffer:bytes});assert.equal((await sharp(prepared.image).metadata()).exif,undefined);
});
test('storage reservation protects a running portrait and full accounts cannot start',async()=>{
 const ids=await pair();
 for(let i=0;i<11;i++){const id=randomUUID();await db.query(`insert into korlix_babyblend_assets(id,user_id,kind,state,details,path,thumb_path,digest,thumb_digest,bytes,width,height,lease,lease_until) values($1,$2,'portrait','ready','{}',$3,$4,$5,$5,$6,100,100,$7,now())`,[id,owner,`${owner}/${id}/image.png`,`${owner}/${id}/thumb.jpg`,'a'.repeat(64),(i===10?24:25)*1024*1024,randomUUID()]);}
 const id=randomUUID(),j=await rpc('job_begin',id,{photo_ids:ids,age:'baby',style:'natural',usage_id:usage});assert.equal(j.state,'running');
 const source=randomUUID(),data={kind:'source',details:{},lease:randomUUID(),path:`${owner}/${source}/image.jpg`,thumb_path:`${owner}/${source}/thumb.jpg`,digest:'b'.repeat(64),thumb_digest:'c'.repeat(64),bytes:2*1024*1024,width:100,height:100};
 await assert.rejects(()=>rpc('asset_begin',source,data),/storage is full/);await rpc('job_fail',id,{error:'Fixture interruption'});await rpc('asset_begin',source,data);
 await assert.rejects(()=>rpc('job_begin',randomUUID(),{photo_ids:ids,age:'baby',style:'natural',usage_id:usage}),/Make room/);assert.equal(await credits(),0);
});
