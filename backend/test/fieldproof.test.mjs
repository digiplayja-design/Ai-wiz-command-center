import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerFieldProof} from '../fieldproof/routes.mjs';
import {jobData,readiness,prepareEvidence,reviewEvidence,TEMPLATES,reportFingerprint} from '../fieldproof/model.mjs';
let db,server,base,owner,other,usage,bytes,calls,uploadFail,removeFail,providerFail,gate,allowed,reads;
const objects=new Map();
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_fieldproof_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
const data=(extra={})=>jobData({title:'Meter replacement',customer:'Demo utility',site:'Demo site',technician:'Field technician',performedOn:'2026-09-27',summary:'Completed the assigned work.',template:'general',hours:1.25,...extra});
async function create(extra={},actor=owner,key=randomUUID()){return api('/jobs',{request_key:key,data:data(extra)},'POST',actor,201);}
async function upload(job,{key=randomUUID(),tag='after',actor=owner,status=201,buffer=bytes,note='',version:ver=job.version}={}){const form=new FormData();form.append('image',new Blob([buffer],{type:'image/jpeg'}),'misleading.jpg');for(const [k,v]of Object.entries({request_key:key,version:ver,tag,name:'Work photo',note}))form.append(k,String(v));const r=await fetch(base+'/jobs/'+job.id+'/photos',{method:'POST',headers:{Authorization:actor},body:form});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));return d;}
async function start(job,extra={},status=202){return (await api('/jobs/'+job.id+'/reviews',{request_key:randomUUID(),version:job.version,consent:true,...extra},'POST',owner,status)).review;}
async function done(id){for(let i=0;i<150;i++){const r=await api('/reviews/'+id);if(r.review.state!=='running')return r.review;await new Promise(r=>setTimeout(r,5));}throw Error('Review did not finish');}
async function credits(){return (await db.query('select credits_used from usage_counters where id=$1',[usage])).rows[0].credits_used;}
async function completeData(d){return api('/jobs/'+d.job.id,{version:d.job.version,data:{...d.job.data,checks:d.job.data.checks.map(c=>({...c,done:true}))}},'PUT');}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;create policy broad_legacy on storage.objects for all to anon,authenticated using(true) with check(true);grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);grant all on usage_counters to service_role;`);
 const dir=new URL('../../supabase/migrations/',import.meta.url);await db.exec(await readFile(new URL((await readdir(dir)).find(x=>x.endsWith('_fieldproof.sql')),dir),'utf8'));
 await db.exec(await readFile(new URL((await readdir(dir)).find(x=>x.endsWith('_fieldproof_workspace_upgrade.sql')),dir),'utf8'));
 bytes=await sharp({create:{width:60,height:80,channels:3,background:'#abc'}}).png().withMetadata().toBuffer();
 const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){if(process.env.FIELDPROOF_DEBUG)console.error(error.message,error.code,error.where);return {error};}}};
 const storage={storage:{from(name){assert.equal(name,'korlix-fieldproof');return {
  upload:async(path,data)=>{if(uploadFail)return {error:Error('offline')};objects.set(path,Buffer.from(data));return {data:{path}};},
  download:async(path)=>{reads++;return objects.has(path)?{data:new Blob([objects.get(path)])}:{error:Error('not found')};},
  remove:async(paths)=>{if(removeFail)return {error:Error('offline')};paths.forEach(p=>objects.delete(p));return {data:[]};},
  createSignedUrls:async(paths,ttl)=>{assert.equal(ttl,600);return {data:paths.map(path=>({path,signedUrl:'https://private.test/'+path+'?signed=true'}))};},
 };}}};
 const app=express();app.use(express.json());registerFieldProof(app,{database,storageDatabase:storage,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,
  aiAccess:async()=>({allowed,usageId:usage,reason:'Upgrade required'}),logger:{warn(){}},review:async input=>{calls++;if(gate)await gate;if(providerFail)throw Error('offline');return {summary:'Technician-supplied records.',observations:[],followUps:['Verify the reading.'],customerReport:'DRAFT customer report',invoiceHandoff:'DRAFT billing scope',version:input.job.version};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/fieldproof';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();usage=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);await db.exec('set role service_role');objects.clear();calls=reads=0;uploadFail=removeFail=providerFail=false;gate=null;allowed=true;});
test.after(async()=>{if(server)await new Promise(r=>server.close(r));await db?.close();});
test('jobs are private, confirmed and idempotent; caller cannot choose ownership',async()=>{
 await api('',null,'GET','',401);const id=randomUUID(),a=await create({user_id:other},owner,id),b=await create({},owner,id);assert.equal(a.job.id,b.job.id);assert.equal((await api()).jobs.length,1);await api('/jobs',{request_key:id,data:data({title:'Changed title'})},'POST',owner,409);assert.equal(a.job.user_id,undefined);assert.equal(a.job.data.user_id,undefined);assert.equal((await api('',null,'GET',other)).jobs.length,0);await api('/jobs/'+id,null,'GET',other,404);
});
test('original photo bytes and digest survive upload, thumbnail and download',async()=>{
 const a=await upload((await create()).job),photo=a.evidence[0];assert.equal(photo.mime,'image/png');assert.equal(photo.sha256,createHash('sha256').update(bytes).digest('hex'));assert.equal(photo.path,undefined);assert.match(photo.previewUrl,/signed=true/);assert.equal(objects.size,2);
 const r=await fetch(base+'/photos/'+photo.id+'/file',{headers:{Authorization:owner}});assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/png');assert.equal(r.headers.get('x-content-type-options'),'nosniff');assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
 await upload(a.job,{buffer:Buffer.from('<svg/>'),status:400});await upload(a.job,{buffer:Buffer.alloc(10*1024*1024+1),status:400});
});
test('foreign photos cannot be downloaded, deleted, uploaded to or reviewed',async()=>{
 const a=await upload((await create()).job);reads=0;await api('/photos/'+a.evidence[0].id+'/file',null,'GET',other,404);await api('/photos/'+a.evidence[0].id,{confirmed:true},'DELETE',other,404);await upload(a.job,{actor:other,status:404});await api('/jobs/'+a.job.id+'/reviews',{request_key:randomUUID(),version:a.job.version,consent:true},'POST',other,404);assert.equal(reads,0);assert.equal(calls,0);
});
test('same upload key replays once; changed content or notes requires a new key',async()=>{
 const j=(await create()).job,key=randomUUID(),a=await upload(j,{key}),b=await upload(j,{key});assert.equal(a.evidence[0].id,b.evidence[0].id);assert.equal(a.job.version,b.job.version);assert.equal(objects.size,2);await upload(j,{key,note:'Changed',status:409});await upload(j,{key,buffer:await sharp(bytes).negate().png().toBuffer(),status:409});
});
test('interrupted upload and deletion recover without hidden orphan records',async()=>{
 const j=(await create()).job,key=randomUUID();uploadFail=true;await upload(j,{key,status:503});let d=await api('/jobs/'+j.id);assert.equal(d.evidence[0].state,'uploading');await upload(j,{key,status:409});await api('/jobs/'+j.id,{version:d.job.version,data:d.job.data},'PUT',owner,409);
 await db.query("update korlix_fieldproof_evidence set lease_until=now()-interval '1 minute' where id=$1",[key]);uploadFail=false;d=await upload(j,{key});assert.equal(d.evidence[0].state,'ready');
 removeFail=true;await api('/photos/'+key,{confirmed:true},'DELETE',owner,503);assert.equal((await api('/jobs/'+j.id)).evidence[0].state,'deleting');removeFail=false;d=await api('/photos/'+key,{confirmed:true},'DELETE');assert.equal(d.evidence.length,0);assert.equal(objects.size,0);
});
test('stale edits are rejected and customer approval belongs to one revision',async()=>{
 let d=await completeData(await upload((await create({requiresApproval:true})).job));assert.deepEqual(d.readiness.missing,['Customer approval recorded for this job revision']);const old=d.job.version;
 d=await api('/jobs/'+d.job.id+'/approval',{version:old,confirmed:true,name:'Customer contact',note:'Reported verbal approval'});assert.equal(d.readiness.ready,true);assert.equal(d.job.approval.version,d.job.version);
 await api('/jobs/'+d.job.id,{version:old,data:d.job.data},'PUT',owner,409);
 const noop=await api('/jobs/'+d.job.id,{version:d.job.version,data:d.job.data},'PUT');assert.equal(noop.job.version,d.job.version);
 d=await api('/jobs/'+d.job.id,{version:d.job.version,data:{...d.job.data,summary:'Later changes'}},'PUT');assert.equal(d.readiness.ready,false);assert(d.readiness.missing.some(x=>x.includes('approval')));
});
test('closeout requires complete records and human confirmation; reopen invalidates prior approval',async()=>{
 let d=await create({requiresApproval:true});await api('/jobs/'+d.job.id+'/complete',{version:d.job.version,confirmed:true},'POST',owner,409);d=await completeData(await upload(d.job));
 d=await api('/jobs/'+d.job.id+'/approval',{version:d.job.version,confirmed:true,name:'Customer',note:''});await api('/jobs/'+d.job.id+'/complete',{version:d.job.version},'POST',owner,400);
 const fingerprint=d.fingerprint;d=await api('/jobs/'+d.job.id+'/complete',{version:d.job.version,confirmed:true});assert.equal(d.job.state,'completed');assert.notEqual(d.fingerprint,fingerprint);
 await api('/jobs/'+d.job.id,{version:d.job.version,data:d.job.data},'PUT',owner,409);await upload(d.job,{status:409});await api('/photos/'+d.evidence[0].id,{confirmed:true},'DELETE',owner,409);
 d=await api('/jobs/'+d.job.id+'/reopen',{version:d.job.version,confirmed:true});assert.equal(d.job.state,'active');assert.equal(d.readiness.ready,false);assert(d.events.some(x=>x.action==='job_closed'));
});
test('review snapshots owned evidence, charges once, and never changes checklist or approval',async()=>{
 const d=await upload((await create()).job),r=await start(d.job),result=await done(r.id);assert.equal(result.state,'completed');assert.equal(await credits(),1);assert.equal(result.input,undefined);assert.equal(result.usage_id,undefined);
 await start(d.job,{request_key:r.id},200);await rpc('review_finish',r.id,{result:{bad:true}});assert.equal(calls,1);assert.equal(await credits(),1);const after=await api('/jobs/'+d.job.id);assert.deepEqual(after.job.data.checks,d.job.data.checks);assert.equal(after.job.approval,null);assert.equal(after.job.version,d.job.version);
 await api('/reviews/'+r.id,null,'GET',other,404);
});
test('running review locks edits, uploads and deletion; failed or denied reviews charge nothing',async()=>{
 let release;gate=new Promise(r=>release=r);const d=await upload((await create()).job),r=await start(d.job);await start(d.job,{},409);await api('/jobs/'+d.job.id,{version:d.job.version,data:d.job.data},'PUT',owner,409);await api('/jobs/'+d.job.id,{version:d.job.version,confirmed:true},'DELETE',owner,409);await upload(d.job,{status:409});release();await done(r.id);
 gate=null;providerFail=true;const r2=await start(d.job);assert.equal((await done(r2.id)).state,'failed');assert.equal(await credits(),1);allowed=false;await start(d.job,{},403);await start(d.job,{consent:false},400);
});
test('restarted reviews expire without provider dispatch or debit',async()=>{
 const d=await upload((await create()).job),id=randomUUID();await rpc('review_begin',id,{job_id:d.job.id,version:d.job.version,usage_id:usage});await db.query("update korlix_fieldproof_reviews set created_at=now()-interval '9 minutes' where id=$1",[id]);assert.equal((await api('/reviews/'+id)).review.state,'failed');await rpc('review_finish',id,{result:{}});assert.equal(await credits(),0);assert.equal(calls,0);
});
test('photo quota and original-integrity verification are enforced',async()=>{
 let d=await create();for(let i=0;i<24;i++)d=await upload(d.job);await upload(d.job,{status:429});const a=await rpc('asset_get',d.evidence[0].id);objects.set(a.path,Buffer.from('corrupt'));await api('/photos/'+a.id+'/file',null,'GET',owner,503);
 objects.set(a.preview_path,Buffer.from('corrupt'));assert.equal((await done((await start(d.job)).id)).state,'failed');assert.equal(await credits(),0);
});
test('confirmed whole-job deletion retries storage cleanup before removing private records',async()=>{
 const d=await upload((await create()).job);await done((await start(d.job)).id);await api('/jobs/'+d.job.id,{version:d.job.version},'DELETE',owner,400);removeFail=true;await api('/jobs/'+d.job.id,{version:d.job.version,confirmed:true},'DELETE',owner,503);assert.equal((await api('/jobs/'+d.job.id)).job.state,'deleting');removeFail=false;await api('/jobs/'+d.job.id,{version:d.job.version,confirmed:true},'DELETE');assert.equal(objects.size,0);assert.equal((await api()).jobs.length,0);assert.equal(await credits(),1);
});
test('RLS and restrictive bucket policy deny direct client access even with broad legacy policies',async()=>{
 await db.exec("reset role;insert into storage.objects values('proof','korlix-fieldproof'),('other','unrelated');set role authenticated");try{assert.deepEqual((await db.query('select id from storage.objects')).rows,[{id:'other'}]);for(const name of ['jobs','evidence','reviews','events'])await assert.rejects(db.query('select * from korlix_fieldproof_'+name),/permission denied/);await assert.rejects(rpc('list'),/permission denied/);await assert.rejects(db.query("insert into storage.objects values('attack','korlix-fieldproof')"),/row-level security/);}finally{await db.exec('reset role;set role service_role');}
});
test('templates retain required checks/photos and input bounds',()=>{
 const d=jobData(data({template:'utility',requiredTags:[],checks:[{id:'required-0',done:true,label:'forged',required:false}]}));assert.deepEqual(d.requiredTags,['before','after','serial']);assert.equal(d.checks[0].required,true);assert.equal(d.checks[0].label,TEMPLATES.utility.checks[0].label);assert.equal(jobData(data({hours:0.29})).hours,.29);
 for(const extra of [{hours:-1},{performedOn:'2026-02-31'},{title:''},{template:'fake'},{requiredTags:['fake']},{checks:[{id:'attack',done:true,required:true,label:'x'}]}])assert.throws(()=>data(extra));
 assert.equal(readiness({data:data(),version:1,approval:null},[]).ready,false);
});
test('photo preparation preserves exact original bytes and rejects unreadable payloads',async()=>{
 const r=await prepareEvidence({buffer:bytes});assert.deepEqual(r.original,bytes);assert.equal((await sharp(r.preview).metadata()).format,'jpeg');assert.equal((await sharp(r.preview).metadata()).exif,undefined);await assert.rejects(prepareEvidence({buffer:Buffer.from('text')}));
});
const aiResult={summary:'Technician report.',observations:[{photoIds:['photo-1'],detail:'Equipment is visible.'}],followUps:['Verify serial readability.'],customerReport:'[VERIFY: result]',invoiceHandoff:'[VERIFY: billable quantities]'};
test('KORLIX vision reviews have grounded photo IDs, strict drafts and no automatic completion',async()=>{
 let request;const client={responses:{create:async q=>{request=q;return {status:'completed',output_text:JSON.stringify(aiResult)};}}};const evidence=[{id:'photo-1',state:'ready',tag:'after',name:'After',preview:bytes}],job={data:data(),version:4,approval:null};const r=await reviewEvidence({client,job,evidence});assert.equal(request.model,'gpt-6-astra');assert.equal(request.reasoning.effort,'xhigh');assert.equal(request.store,false);assert.equal(request.tools,undefined);assert.match(r.customerReport,/DRAFT/);assert.match(r.invoiceHandoff,/VERIFY/);assert.match(request.instructions,/not a certification/);assert.equal(request.input[0].content.filter(x=>x.type==='input_image').length,1);
 await assert.rejects(reviewEvidence({client:{responses:{create:async()=>({status:'completed',output_text:JSON.stringify({...aiResult,observations:[{photoIds:['invented'],detail:'x'}]})})}},job,evidence}),/unsupported photo/);
 await assert.rejects(reviewEvidence({client:{responses:{create:async()=>({status:'incomplete'})}},job,evidence}),/No credit/);
 assert.notEqual(reportFingerprint({...job,id:'job',state:'active'},evidence,null),reportFingerprint({...job,id:'job',version:5,state:'active'},evidence,null));
});
