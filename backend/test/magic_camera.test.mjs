import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import sharp from 'sharp';
import {PRESETS,options,instructions,prepareSource,validateOutput,renderer} from '../magic_camera/core.mjs';
import {createMagicWorker,publicJob,magicStore} from '../magic_camera/routes.mjs';
import {magicAppRouteAllowed} from '../magic_camera/auth.mjs';
let db,owner,other;
const call=async(actor,action,id=null,p={})=>(await db.query('select korlix_magic_command($1,$2,$3,$4) r',[actor,action,id,p])).rows[0].r;
const plan=async(standalone=true)=>(await db.query('select korlix_magic_plan($1,$2) r',[owner,standalone])).rows[0].r;
const reserve=async(key=randomUUID(),p={},actor=owner)=>call(actor,'reserve',null,{request_key:key,fingerprint:'a'.repeat(64),options:options(),standalone:true,...p});
async function finish(r,failed=false){await call(owner,'uploaded',r.job.id);const j=await call(null,'claim');return call(owner,failed?'fail':'finish',j.id,{worker_token:j.worker_token,width:1024,height:1024,render_ms:2400});}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text,bucket_id text);alter table storage.objects enable row level security;create table user_profiles(id uuid primary key,tier text default 'basic',is_disabled boolean default false);create function korlix_web_billing_profile(uuid) returns jsonb language sql as 'select to_jsonb(p) from user_profiles p where id=$1';grant usage on schema public,auth,storage to service_role;grant select,insert,update on user_profiles to service_role;`);
 await db.exec(await readFile(new URL('../magic_camera/schema.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../magic_camera/billing_schema.sql',import.meta.url),'utf8'));
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const id of [owner,other]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles(id) values($1)',[id]);}await db.exec('set role service_role');});
test.after(()=>db.close());
test('30 unique presets, optional style selection and custom direction preserve identity rules',()=>{
 assert.equal(PRESETS.length,30);assert.equal(new Set(PRESETS.map(x=>x.id)).size,30);
 assert.deepEqual(Object.values(Object.groupBy(PRESETS,x=>x.category)).map(x=>x.length),[5,5,5,5,5,5]);
 assert.equal(options().style,'all');assert.match(instructions(options()),/Do not assume gender/);
 assert.throws(()=>options({preset:'custom'}));assert.throws(()=>options({style:'infer'}));
 assert.match(instructions(options({preset:'custom',prompt:'Moonlit garden'})),/Moonlit garden/);
});
test('two lifetime successful free photos; failures and deletion never reset allowance',async()=>{
 assert.equal((await plan()).remaining,2);assert.equal((await plan(false)).can_generate,false);
 await finish(await reserve(),true);assert.equal((await plan()).remaining,2);
 const a=await finish(await reserve());assert.equal((await plan()).remaining,1);
 await call(owner,'delete',a.job.id);assert.equal((await plan()).remaining,1);
 await finish(await reserve());assert.equal((await plan()).remaining,0);
 await assert.rejects(reserve(),/MAG402/);assert.equal((await call(owner,'list',null,{standalone:true})).jobs.length,2);
});
test('reservations reject parallel photos; replay key is idempotent and binds exact options',async()=>{
 const key=randomUUID(),a=await reserve(key);assert.equal(a.dispatch,true);
 const replay=await reserve(key);assert.equal(replay.dispatch,false);assert.equal(replay.job.id,a.job.id);
 await assert.rejects(reserve(),/MAG409/);await assert.rejects(reserve(key,{fingerprint:'b'.repeat(64)}),/different photo/);
 await finish(a);await finish(await reserve());await assert.rejects(reserve(),/MAG402/);
 assert.equal((await reserve(key)).dispatch,false);
});
test('Pro and Ultra limits are shared between hub and standalone and enforce daily caps',async()=>{
 await db.query("update user_profiles set tier='pro' where id=$1",[owner]);
 assert.equal((await plan(false)).limit,10);await finish(await reserve());await finish(await reserve());
 assert.equal((await plan()).daily_remaining,0);await assert.rejects(reserve(),/MAG402/);
 await db.query("update user_profiles set tier='ultra' where id=$1",[owner]);assert.equal((await plan()).limit,40);
 for(let i=0;i<3;i++)await finish(await reserve());await assert.rejects(reserve(),/MAG402/);
});
test('monthly boundary does not erase lifetime trials and monthly usage is independent of gallery',async()=>{
 await finish(await reserve());await db.query("update korlix_magic_jobs set created_at=now()-interval '2 months' where owner_id=$1",[owner]);assert.equal((await plan()).remaining,1);
 await db.query("update user_profiles set tier='pro' where id=$1",[owner]);await finish(await reserve());
 await db.query("update korlix_magic_jobs set created_at=now()-interval '2 months' where owner_id=$1 and allowance='pro'",[owner]);assert.equal((await plan()).remaining,10);
});
test('ownership, stale lease fencing and private serialization',async()=>{
 const r=await reserve();await assert.rejects(call(other,'get',r.job.id),/MAG404/);
 await call(owner,'uploaded',r.job.id);const j=await call(null,'claim');
 await assert.rejects(call(owner,'finish',j.id,{worker_token:randomUUID()}),/MAG409/);
 await db.query("update korlix_magic_jobs set lease_until=now()-interval '1 second' where id=$1",[j.id]);await call(null,'sweep');
 await assert.rejects(call(owner,'finish',j.id,{worker_token:j.worker_token}),/MAG409/);assert.equal((await plan()).remaining,2);
 const publicData=publicJob(j);for(const key of ['owner_id','worker_token','fingerprint','source_purged','cleanup_version'])assert.equal(key in publicData,false);
});
test('anonymous and signed-in browser roles cannot read captures, mutate quotas, or invoke worker',async()=>{
 for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(db.query('select * from korlix_magic_jobs'),/permission denied/);await assert.rejects(call(owner,'reserve'),/permission denied/);await db.exec('reset role');}
});
test('worker stores valid output before charging, purges capture and does not render twice',async()=>{
 await call(owner,'uploaded',(await reserve()).job.id);const events=[];let renders=0;
 const storage={download:async()=>Buffer.from('private'),upload:async()=>events.push('stored'),remove:async()=>events.push('purged')};
 const wrapped=async(...args)=>{if(args[1]==='finish')events.push('charged');return call(...args);};
 const w=createMagicWorker({call:wrapped,storage,render:async()=>{renders++;return {bytes:Buffer.from('result'),width:1024,height:1024};}});
 await w.tick();await w.tick();assert.equal(renders,1);assert(events.indexOf('stored')<events.indexOf('charged'));assert(events.includes('purged'));assert.equal((await plan()).remaining,1);
});
test('storage failure never charges and releases the reservation',async()=>{
 await call(owner,'uploaded',(await reserve()).job.id);
 const w=createMagicWorker({call,storage:{download:async()=>Buffer.from('private'),upload:async()=>{throw Error('offline');},remove:async()=>{}},render:async()=>({bytes:Buffer.from('result'),width:1024,height:1024})});
 await w.tick();assert.equal((await plan()).remaining,2);
});
test('image path validates actual pixels and renderer requests Sunburst max with no retries',async()=>{
 const png=await sharp({create:{width:512,height:512,channels:3,background:'#123456'}}).png().toBuffer();
 const source=await prepareSource(png);assert.equal((await sharp(source).metadata()).format,'jpeg');
 await assert.rejects(validateOutput('not base64'));
 let request,settings;const render=renderer({client:{images:{edit:async(a,b)=>{request=a;settings=b;return {data:[{b64_json:png.toString('base64')}]};}}},toFile:async()=>({})});
 await render(source,options());assert.equal(request.model,'gpt-image-2.5-sunburst');assert.equal(request.quality,'max');assert.equal(settings.maxRetries,0);assert.equal(request.n,1);
});
test('companion session cannot escape Magic Camera scope',()=>{
 assert(magicAppRouteAllowed({method:'POST',originalUrl:'/api/magic-camera'}));assert(!magicAppRouteAllowed({method:'POST',originalUrl:'/api/generate'}));assert(!magicAppRouteAllowed({method:'GET',originalUrl:'/api/receipt-wiz'}));
 const recovery='/api/magic-camera/requests/'+randomUUID();
 for(const method of ['GET','HEAD'])assert(magicAppRouteAllowed({method,originalUrl:recovery+'?retry=1'}));
 for(const method of ['POST','PUT','PATCH','DELETE'])assert(!magicAppRouteAllowed({method,originalUrl:recovery}));
});

test('real report route attaches final image privately and never acknowledges a failed persistence',async t=>{
 const {default:express}=await import('express');const {registerMagicCamera}=await import('../magic_camera/routes.mjs');
 const ready=await finish(await reserve());let persisted,failPersist=false;
 const png=await sharp({create:{width:512,height:512,channels:3,background:'#318cff'}}).png().toBuffer();
 const storage={download:async path=>{assert(path.endsWith('/magic.png'));return png;},remove:async()=>{}};
 const app=express();app.use(express.json());registerMagicCamera(app,{call,database:{},storage,autoStart:false,requireUser:async()=>({id:owner}),reportPersist:async(report,evidence)=>{if(failPersist)throw Error('offline');persisted={report,evidence};}});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>new Promise(r=>server.close(r)));
 const url=`http://127.0.0.1:${server.address().port}/api/magic-camera/${ready.job.id}`;
 // Spend the second credit; reporting is independent of generation access.
 await finish(await reserve());assert.equal((await plan()).remaining,0);
 let r=await fetch(url+'/report',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({reason:'Offensive or hateful',details:'Synthetic test'})});assert.equal(r.status,201);assert.equal((await r.json()).accepted,true);
 assert.equal(persisted.report.contentId,ready.job.id);assert.match(persisted.report.prompt,/facial structure/);assert.equal(persisted.evidence.mimeType,'image/jpeg');assert(persisted.evidence.base64);assert.equal(persisted.report.imageUrl,'');
 failPersist=true;r=await fetch(url+'/report',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({reason:'Other'})});assert.equal(r.status,503);assert.equal((await r.json()).accepted,undefined);
 r=await fetch(url+'/image');assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal((await fetch(url+'/original')).status,404);
 r=await fetch(url+'/image?preview=1');assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/jpeg');const thumb=await sharp(Buffer.from(await r.arrayBuffer())).metadata();assert(thumb.width<=640&&thumb.height<=640);
});

test('Apple receipts bind to app, account, expiry and verified sandbox access',async()=>{
 const {appleFacts,MAGIC_BUNDLE}=await import('../magic_camera/apple.mjs');
 const decoded={bundleId:MAGIC_BUNDLE,productId:'magic_camera_starter',appAccountToken:owner,originalTransactionId:'1234567890123',expiresDate:Date.now()+86400000,environment:'Production'};
 assert.equal(appleFacts(decoded,owner,{}).active,true);
 assert.throws(()=>appleFacts({...decoded,appAccountToken:other},owner,{}),/different Korlix/);
 assert.throws(()=>appleFacts({...decoded,bundleId:'com.korlixdeveloper.korlixai'},owner,{}),/does not belong/);
 assert.throws(()=>appleFacts({...decoded,environment:'Sandbox'},owner,{}),/not enabled/);
 assert.equal(appleFacts({...decoded,revocationDate:Date.now()},owner,{}).active,false);
 assert.equal(appleFacts({...decoded,isUpgraded:true},owner,{}).active,false);
 assert.equal(appleFacts({...decoded,environment:'Sandbox'},owner,{APPLE_SANDBOX_ALLOWED_USER_IDS:owner}).active,true);
});

test('Apple and Google verified purchases grant only Magic quotas and cannot be rebound',async()=>{
 const {appleFacts,MAGIC_BUNDLE}=await import('../magic_camera/apple.mjs');
 await db.exec('reset role');await db.exec(await readFile(new URL('../magic_camera/apple_schema.sql',import.meta.url),'utf8'));await db.exec('set role service_role');
 const command=async(actor,action,p={})=>(await db.query('select korlix_magic_apple_command($1,$2,$3) r',[actor,action,p])).rows[0].r;
 const decoded={bundleId:MAGIC_BUNDLE,productId:'magic_camera_plus',appAccountToken:owner,originalTransactionId:'9876543212345',expiresDate:Date.now()+86400000,environment:'Production'};
 const facts=appleFacts(decoded,owner,{});await command(owner,'apply',facts);assert.equal((await plan()).name,'plus');assert.equal((await plan()).limit,40);assert.equal((await plan(false)).name,'locked');
 assert.equal((await db.query('select tier from user_profiles where id=$1',[owner])).rows[0].tier,'basic');
 await assert.rejects(command(other,'apply',{...facts,account_id:other}),/another account/);
 await command(owner,'apply',appleFacts({...decoded,revocationDate:Date.now()},owner,{}));assert.equal((await plan()).name,'free');
});

test('verified Google Starter purchase, duplicate prevention and expiry use dedicated Magic entitlement',async()=>{
 const {magicAccountId,MAGIC_PRODUCTS}=await import('../magic_camera/billing.mjs');const {observation}=await import('../google_play/core.mjs');
 const command=async(action,p={})=>(await db.query('select korlix_magic_billing_command($1,$2,$3) r',[owner,action,p])).rows[0].r;
 const decoded={externalAccountIdentifiers:{obfuscatedExternalAccountId:magicAccountId(owner)},subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',lineItems:[{productId:'magic_camera_starter',expiryTime:new Date(Date.now()+86400000).toISOString(),offerDetails:{basePlanId:'monthly'},autoRenewingPlan:{autoRenewEnabled:true}}]};
 const facts=observation(decoded,{userId:owner,token:'synthetic-magic-token-'+owner,products:MAGIC_PRODUCTS,accountIdentifier:magicAccountId});
 await command('prepare',{account_id:magicAccountId(owner)});const lease=await command('claim');await command('apply',{...facts,sync_token:lease.sync_token});await command('release',{sync_token:lease.sync_token,success:true});
 assert.equal((await plan()).name,'starter');assert.equal((await plan()).limit,15);assert.equal((await plan(false)).can_generate,false);await assert.rejects(command('prepare',{account_id:magicAccountId(owner)}),/already included/);
 const next=await command('claim');await command('apply',{...facts,active:false,state:'SUBSCRIPTION_STATE_EXPIRED',sync_token:next.sync_token});assert.equal((await plan()).name,'free');
});

test('private gallery pages keep older results reachable and exclude deleted records',async()=>{
 await db.query("insert into korlix_magic_jobs(owner_id,request_key,fingerprint,options,state,allowance) select $1,gen_random_uuid(),repeat('a',64),'{}','ready','pro' from generate_series(1,150)",[owner]);
 const first=await call(owner,'list',null,{standalone:true});assert.equal(first.jobs.length,100);assert.equal(first.next_offset,100);
 const next=await call(owner,'list',null,{standalone:true,offset:100});assert.equal(next.jobs.length,50);assert.equal(next.next_offset,null);assert.equal(new Set([...first.jobs,...next.jobs].map(x=>x.id)).size,150);
 assert.equal((await call(other,'list',null,{standalone:true})).jobs.length,0);await assert.rejects(call(owner,'list',null,{offset:-1}),/Invalid gallery/);
});


test('late capture uploads rearm cleanup and stale cleanup cannot confirm a deleted result',async()=>{
 const capture=await reserve();await db.query("update korlix_magic_jobs set lease_until=now()-interval '1 second' where id=$1",[capture.job.id]);
 await call(null,'sweep');const expired=(await call(owner,'get',capture.job.id)).job;
 await call(owner,'purged',expired.id,{cleanup_version:expired.cleanup_version});
 await assert.rejects(call(owner,'uploaded',expired.id),/Upload expired/);
 const late=await call(owner,'fail',expired.id);assert.equal(late.job.source_purged,false);assert(late.job.cleanup_version>expired.cleanup_version);
 await assert.rejects(call(owner,'purged',expired.id,{cleanup_version:expired.cleanup_version}),/newer cleanup/);
 const ready=await finish(await reserve());const deleted=await call(owner,'delete',ready.job.id);const removed=[];
 const worker=createMagicWorker({call,storage:{remove:async keys=>removed.push(...keys)},render:null});
 await assert.rejects(worker.cleanup(ready.job),/newer cleanup/);
 assert.equal((await call(owner,'get',ready.job.id)).job.output_purged,false);
 await worker.cleanup(deleted.job);assert.equal((await call(owner,'get',ready.job.id)).job.output_purged,true);assert(removed.some(x=>x.endsWith('/magic.png')));
 assert.equal((await plan()).remaining,1);
});

test('late output storage after lease expiry is removed and never charged',async()=>{
 const reserved=await reserve();await call(owner,'uploaded',reserved.job.id);const files=new Set();
 const storage={download:async()=>Buffer.from('capture'),remove:async keys=>keys.forEach(k=>files.delete(k)),upload:async path=>{
  await db.query("update korlix_magic_jobs set lease_until=now()-interval '1 second' where id=$1",[reserved.job.id]);
  await call(null,'sweep');const expired=(await call(owner,'get',reserved.job.id)).job;
  const cleaner=createMagicWorker({call,storage,render:null});await cleaner.cleanup(expired);
  files.add(path); // The storage write finishes after the earlier cleanup.
 }};
 const worker=createMagicWorker({call,storage,render:async()=>({bytes:Buffer.from('final'),width:1024,height:1024})});
 await worker.tick();assert.equal(files.size,0);assert.equal((await plan()).remaining,2);
 const result=(await call(owner,'get',reserved.job.id)).job;assert.equal(result.state,'failed');assert.equal(result.output_purged,true);
});

test('lost upload response recovery is read-only, owner-bound and cannot recover deleted photos',async t=>{
 const key=randomUUID(),reserved=await reserve(key);
 assert.equal((await call(owner,'request',key)).job.id,reserved.job.id);
 assert.equal((await plan()).remaining,1);
 await assert.rejects(call(other,'request',key),/MAG404/);
 await assert.rejects(call(owner,'request',randomUUID()),/MAG404/);
 const {default:express}=await import('express');const {registerMagicCamera}=await import('../magic_camera/routes.mjs');
 const recoveredStore=magicStore({rpc:async(_name,a)=>{
  try{return {data:await call(a.p_actor,a.p_action,a.p_id,a.p)};}catch(error){return {error};}
 }});
 let actor=owner;const app=express();registerMagicCamera(app,{call:recoveredStore,storage:null,autoStart:false,requireUser:async()=>({id:actor})});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>new Promise(r=>server.close(r)));
 const url=`http://127.0.0.1:${server.address().port}/api/magic-camera/requests/`;
 let r=await fetch(url+key);assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');
 const body=await r.json();assert.equal(body.job.id,reserved.job.id);assert.equal(body.job.state,'uploading');
 for(const field of ['request_key','owner_id','fingerprint','worker_token'])assert.equal(field in body.job,false);
 actor=other;r=await fetch(url+key);assert.equal(r.status,404);
 actor=owner;r=await fetch(url+'invalid');assert.equal(r.status,400);
 const ready=await finish(reserved);await finish(await reserve());assert.equal((await plan()).remaining,0);
 assert.equal((await call(owner,'request',key)).job.state,'ready');
 assert.equal((await db.query('select count(*) n from korlix_magic_jobs where owner_id=$1',[owner])).rows[0].n,2);
 await call(owner,'delete',ready.job.id);await assert.rejects(call(owner,'request',key),/MAG404/);
 assert.equal((await plan()).remaining,0);
});

test('release migration contains every tested Magic Camera schema fixture unchanged',async()=>{
 const migration=await readFile(new URL('../../supabase/migrations/20261030003135_magic_camera_foundation.sql',import.meta.url),'utf8');
 for(const name of ['schema.sql','billing_schema.sql','apple_schema.sql','session_schema.sql']){
  assert(migration.includes(await readFile(new URL('../magic_camera/'+name,import.meta.url),'utf8')),name+' differs from release migration');
 }
});
