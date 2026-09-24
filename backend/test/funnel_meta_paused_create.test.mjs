import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher} from '../funnels/meta.mjs';
import {MetaPausedAccessError} from '../funnels/meta_paused_provider.mjs';
import {normalizeImage} from '../funnels/images.mjs';
import sharp from 'sharp';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_CREATE_PAUSED_ENABLED:'true',KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-secret-not-real',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=metaConfiguration(env),account={id:'act_123',name:'Growth account',currency:'USD',timezone:'UTC',status:1},page={id:'98765432101234567890',name:'Growth Page',category:'Education'};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,database,server,base,f,c,clock=Date.now(),providerCalls=0,writes=[],validateHook,writeHook,findHook;
const rpc=async(name,p)=>(await db.query(name==='korlix_meta_v1'?`select public.${name}($1,$2,$3) r`:`select public.${name}($1,$2,$3,$4) r`,name==='korlix_meta_v1'?[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;

const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/meta-create${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,pages,selected_page,refreshed_at,pages_refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,$8,$9,now(),now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id,JSON.stringify([page]),page.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923011934_funnel_meta_page_identity.sql','20260923015323_funnel_meta_campaign_preparation.sql','20260922194529_funnel_images.sql','20260923133926_funnel_meta_creative.sql','20260923140507_funnel_meta_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 for(const file of ['20260923162339_funnel_meta_radius.sql','20260923180917_funnel_meta_locations.sql','20260923232651_funnel_meta_paused_create.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,metaProvider:provider});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_meta_connections;delete from korlix_funnel_images;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;writes=[];validateHook=null;writeHook=null;findHook=null;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const blank={primary_text:'',headline:'',description:'',cta:'LEARN_MORE',image_id:null,image_alt:''};
const assets={...blank,primary_text:'Plan your next step with our team.',headline:'Meet our team',description:'Local support for your business.'};
const creative=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_creative_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
async function save(a=assets){const d=await creative();return creative('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
async function image(actor=owner){const n=await normalizeImage(await sharp({create:{width:600,height:400,channels:3,background:'#17a9b0'}}).png().toBuffer());return rpc('korlix_funnel_images_v1',{p_actor:actor,p_action:'put',p_data:{label:'Our team.png',width:n.width,height:n.height,sha256:n.sha256,content:n.bytes.toString('base64')}});}
const imageCommand=(action,id=null,actor=owner)=>rpc('korlix_funnel_images_v1',{p_actor:actor,p_action:action,p_id:id,p_data:{confirmed:true}});

const empty={countries:[],age_min:18,age_max:65,placements:'undecided',categories:['UNDECIDED']};
const choices={countries:['US','JM'],age_min:25,age_max:65,placements:'facebook_feed',categories:['NONE']};
const targeting=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_targeting_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
async function saveTarget(a=choices){const d=await targeting();return targeting('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
async function completeCreative(){const a=await image();return save({...assets,image_id:a.id,image_alt:'Team'});}
async function review(){const d=await targeting();return targeting('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});}
async function ready(){await saveReview();await completeCreative();await saveTarget();return review();}

const resources={image_hash:'a'.repeat(32),campaign:'101',ad_set:'102',creative:'103',ad:'104'};
const provider={
 account:async()=>{providerCalls++;return account;},
 verifyCreationAccess:async()=>{providerCalls++;return {verified:true};},
 validatePausedMeta:async(...args)=>{providerCalls++;return validateHook?validateHook(...args):{validated:true};},
 createPausedMetaResource:async(token,s,r,stage,bytes)=>{writes.push(stage);assert.equal(token,'private-fixture-token');assert.equal(s.budget_acknowledged,true);assert.deepEqual(Object.keys(r),Object.keys(resources).slice(0,writes.length-1));if(stage==='image_hash')assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');return writeHook?writeHook(token,s,r,stage,bytes):resources[stage];},
 findPausedMeta:async(...args)=>{providerCalls++;return findHook?findHook(...args):resources;}
};
const read=async()=>{const r=await req();assert.equal(r.status,200,await r.clone().text());return r.json();};
const input=d=>({fingerprint:d.fingerprint,start_date:d.earliest_start,confirmed:true,budget_acknowledged:true});
const create=async()=>req('/create',input(await read()));
const ledger=async()=>(await db.query('select * from korlix_funnel_meta_creations')).rows;
test('K184 reads are private and local; one confirmed request creates five ordered receipts',async()=>{
 await ready();const before=await read();assert.equal(before.create_ready,true);assert.equal(providerCalls,0);const r=await create();assert.equal(r.status,201,await r.clone().text());const d=await r.json();assert.equal(d.attempt.state,'created');assert.deepEqual(d.attempt.resources,resources);assert.deepEqual(writes,Object.keys(resources));assert.equal(d.proposal,undefined);assert.equal(d.dispatch,undefined);assert.equal(r.headers.get('cache-control'),'no-store');assert(!JSON.stringify(d).includes('private-fixture-token'));
 const s=d.attempt.snapshot;assert.equal(s.start_date,before.earliest_start);assert.equal(Date.parse(s.end_time)-Date.parse(s.start_time),14*86400000-1000);assert.equal(s.plan.daily_cents,2500);const saved=await ledger();assert.match(saved[0].request_hash,/^[a-f0-9]{64}$/);assert.equal((await create()).status,200);assert.equal(writes.length,5);assert.equal((await ledger()).length,1);
});
test('K184 partial write failure preserves prefix receipts and never resumes',async()=>{
 await ready();writeHook=async(_t,_s,_r,stage)=>{if(stage==='ad_set')throw Error('private provider detail');return resources[stage];};let r=await create();assert.equal(r.status,200);let d=await r.json();assert.equal(d.attempt.state,'unknown');assert.deepEqual(d.attempt.resources,{image_hash:resources.image_hash,campaign:'101'});assert(!JSON.stringify(d).includes('private provider detail'));assert.deepEqual(writes,['image_hash','campaign','ad_set']);await create();assert.equal(writes.length,3);
 findHook=async()=>null;r=await req('/reconcile',{attempt_id:d.attempt.id});d=await r.json();assert.equal(d.attempt.state,'unknown');assert.match(d.notice,/does not prove/);findHook=null;r=await req('/reconcile',{attempt_id:d.attempt.id});assert.equal(r.status,200,await r.clone().text());assert.equal((await r.json()).attempt.state,'created');assert.equal(writes.length,3);
});
test('K184 lost upload receipt cannot be reconciled and no second upload is sent',async()=>{
 await ready();writeHook=async()=>{throw Error();};let d=await (await create()).json();assert.deepEqual(d.attempt.resources,{});assert.equal(writes.length,1);assert.equal((await req('/reconcile',{attempt_id:d.attempt.id})).status,409);await create();assert.equal(writes.length,1);
});
test('K184 validation before claim can reject safely; validation after campaign preserves partial history',async()=>{
 await ready();validateHook=async()=>{throw Error('provider-secret');};let r=await create();assert.equal(r.status,503);assert.equal(writes.length,0);assert.deepEqual(await ledger(),[]);assert(!(await r.text()).includes('provider-secret'));
 validateHook=async(_t,_s,_r,stage)=>{if(stage==='ad_set')throw Error();return {validated:true};};r=await create();assert.equal(r.status,200);assert.deepEqual((await r.json()).attempt.resources,{image_hash:resources.image_hash,campaign:'101'});assert.equal(writes.length,2);
});
test('K184 concurrent confirmations dispatch exactly one attempt',async()=>{
 await ready();const d=await read();const rs=await Promise.all([req('/create',input(d)),req('/create',input(d))]);assert(rs.every(r=>[200,201].includes(r.status)));assert.equal(writes.length,5);assert.equal((await ledger()).length,1);
});
test('K184 edit or connection change during preclaim validation prevents writes',async()=>{
 await ready();validateHook=async()=>{const d=await creative();await creative('save',{version:d.version,fingerprint:d.fingerprint,assets:{...d.assets,headline:'Changed headline'}});return {validated:true};};assert.equal((await create()).status,409);assert.equal(writes.length,0);assert.deepEqual(await ledger(),[]);
 await ready();validateHook=async()=>{await db.query('update korlix_meta_connections set version=version+1 where user_id=$1',[owner]);return {validated:true};};assert.equal((await create()).status,409);assert.equal(writes.length,0);
});
test('K184 changed connection after receipt stops following writes but records receipt',async()=>{
 await ready();writeHook=async(_t,_s,_r,stage)=>{await db.query('update korlix_meta_connections set version=version+1 where user_id=$1',[owner]);return resources[stage];};const r=await create();assert.equal(r.status,200);const d=await r.json();assert.equal(d.attempt.state,'unknown');assert.deepEqual(d.attempt.resources,{image_hash:resources.image_hash});assert.equal(writes.length,1);
});
test('K184 late entitlement revocation preserves receipt while denying subsequent reads',async()=>{
 await ready();writeHook=async(_t,_s,_r,stage)=>{await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return resources[stage];};assert.equal((await create()).status,403);const row=(await ledger())[0];assert.equal(row.state,'unknown');assert.deepEqual(row.resources,{image_hash:resources.image_hash});assert.equal(writes.length,1);
});
test('K184 failed claim sends nothing; failed receipt persistence never advances to next write',async()=>{
 await ready();const original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_create_v1'&&p.p_action==='claim'?{error:{code:'XX000'}}:original(n,p);try{assert.equal((await create()).status,503);assert.equal(writes.length,0);}finally{database.rpc=original;}
 database.rpc=async(n,p)=>n==='korlix_funnel_meta_create_v1'&&p.p_action==='progress'?{error:{code:'XX000'}}:original(n,p);try{const r=await create();assert.equal(r.status,200);assert.deepEqual((await r.json()).attempt.resources,{});assert.equal(writes.length,1);}finally{database.rpc=original;}
});
test('K184 lost completion can be recovered by read-only reconciliation with all original receipts',async()=>{
 await ready();const original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_create_v1'&&p.p_action==='finish'?{error:{code:'XX000'}}:original(n,p);let d;try{d=await (await create()).json();assert.equal(d.attempt.state,'unknown');assert.deepEqual(d.attempt.resources,resources);}finally{database.rpc=original;}
 assert.equal((await req('/reconcile',{attempt_id:d.attempt.id})).status,200);assert.equal((await ledger())[0].state,'created');assert.equal(writes.length,5);
});
test('K184 strict bodies, schedule bounds and fingerprints reject before provider calls',async()=>{
 await ready();const valid=input(await read());for(const patch of [{confirmed:false},{budget_acknowledged:false},{start_date:'2026-02-30'},{start_date:'2000-01-01'},{start_date:'2099-01-01'},{fingerprint:'a'.repeat(64)},{account_id:'act_999'}]){clock+=60000;const r=await req('/create',{...valid,...patch});assert([400,409].includes(r.status),await r.text());}assert.equal((await req('?configured=true')).status,400);assert.equal((await req('/create?configured=true',valid)).status,400);assert.equal(providerCalls,0);assert.equal(writes.length,0);
});
test('K184 both current reviews, Feed only and no special category are mandatory',async()=>{
 assert.equal((await read()).create_ready,false);await ready();await setup('clear',{version:(await setup()).version,confirmed:true});assert.equal((await read()).checks.setup_review_current,false);await ready();await saveTarget({...choices,placements:'automatic'});await review();assert.equal((await read()).checks.facebook_feed,false);await saveTarget({...choices,age_min:18,categories:['HOUSING']});await review();assert.equal((await read()).checks.no_special_category,false);assert.equal((await create()).status,409);assert.equal(writes.length,0);
});
test('K184 owner, tier, private table grants and invoker function protect the ledger',async()=>{
 await ready();for(const [actor,status]of [['',401],[other,404],[basic,403]])assert.equal((await req('',null,actor)).status,status);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_meta_creations'),/permission denied/);await assert.rejects(rpc('korlix_funnel_meta_create_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id}}),/permission denied/);await db.exec('reset role;set role service_role');}
 const attrs=(await db.query("select prosecdef,proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_meta_creations'::regclass) rls from pg_proc where oid='korlix_funnel_meta_create_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(attrs.prosecdef,false);assert.equal(attrs.rls,true);assert.deepEqual(attrs.proconfig,['search_path=public, pg_temp']);for(const endpoint of ['progress','finish','resume','reset','activate'])assert.equal((await req('/'+endpoint,{})).status,404);
});
test('K184 progress order and reconciliation cannot replace a saved receipt',async()=>{
 await ready();writeHook=async(_t,_s,_r,stage)=>{if(stage==='campaign')throw Error();return resources[stage];};const d=await (await create()).json();const internal=(action,data)=>rpc('korlix_funnel_meta_create_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,attempt_id:d.attempt.id,...data}});await assert.rejects(internal('progress',{resource:'ad_set',value:'102'}),/reordered/);await assert.rejects(internal('progress',{resource:'image_hash',value:resources.image_hash}),/reordered/);await assert.rejects(internal('finish',{resources:{...resources,image_hash:'b'.repeat(32)}}),/changed/);assert.equal((await req('/reconcile',{attempt_id:randomUUID()})).status,409);
});
test('K184 archived plans and paused pages retain history without further writes',async()=>{
 await ready();await create();c=await campaign('archive',{confirmed:true});f=await funnel('pause',{version:f.version});const d=await read();assert.equal(d.create_ready,false);assert.equal(d.attempt.state,'created');assert.equal((await create()).status,200);assert.equal(writes.length,5);
});
test('K184 access loss marks only current connection invalid and write quota excludes reads',async()=>{
 await ready();validateHook=async()=>{throw new MetaPausedAccessError();};assert.equal((await create()).status,409);assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,true);assert.equal(writes.length,0);for(let i=0;i<4;i++)await create();assert.equal((await create()).status,429);assert.equal((await req()).status,200);
});
test('K184 production default flag and unsupported version block provider access',async()=>{
 await ready();for(const patch of [{KORLIX_META_CREATE_PAUSED_ENABLED:undefined},{KORLIX_META_API_VERSION:'v25.0'}]){const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,...patch},metaProvider:provider});const s=app.listen(0);await new Promise(r=>s.once('listening',r));try{const url=`http://127.0.0.1:${s.address().port}/api/funnels/${f.id}/campaigns/${c.id}/meta-create`;const d=await(await fetch(url)).json();assert.equal(d.checks.platform_enabled,false);assert.equal(d.create_ready,false);assert.equal((await fetch(url+'/create',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input(d))})).status,409);assert.equal(providerCalls,0);}finally{s.closeAllConnections();await new Promise(r=>s.close(r));}}
});
