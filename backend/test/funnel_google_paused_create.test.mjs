import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher,GoogleAdsAccessError,googleDigest,createGoogleAdsProvider} from '../funnels/google_ads_provider.mjs';
import {googleTargetingInput,googleTargetingAssets,googleTargetingCatalog as catalog} from '../funnels/google_targeting.mjs';
import {googlePausedRequest} from '../funnels/google_paused_provider.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED:'true',KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=googleAdsConfiguration(env),rootId='1234567890',account={id:'9876543210',name:'Growth account',currency:'USD',timezone:'UTC',manager:false,status:'ENABLED',test_account:false};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'google',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,database,server,base,f,c,clock=Date.now(),providerCalls=0,createCalls=0,validateHook=null,createHook=null,findHook=null;
const rpc=async(name,p)=>name==='korlix_google_ads_v1'?(await db.query(`select public.${name}($1,$2,$3) r`,[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})])).rows[0].r:(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-create${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql','20260923085331_funnel_google_creative.sql','20260923094201_funnel_google_creative_review.sql','20260923103256_funnel_google_keywords.sql','20260923105943_funnel_google_keyword_review.sql','20260923112526_funnel_google_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923120825_funnel_google_targeting_review.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923123817_funnel_google_preflight.sql',import.meta.url),'utf8'));
 for(const file of ['20260923153540_funnel_google_radius.sql','20260923172253_funnel_google_locations.sql','20260923210921_funnel_google_paused_create.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260924034142_funnel_google_search_language_contract.sql',import.meta.url),'utf8'));
 await db.exec('set role service_role');
 database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:provider});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;createCalls=0;validateHook=null;createHook=null;findHook=null;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const empty=()=>({countries:[],excluded_countries:[],content_languages:[],location_mode:'undecided',bidding:'undecided'});
const assets={countries:['US','JM'],excluded_countries:['CA'],content_languages:['en','es'],location_mode:'presence',bidding:'maximize_clicks'};
const targeting=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_targeting_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
async function save(a=assets){const d=await targeting();return targeting('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}


const preflight=(data={},actor=owner,action='read')=>rpc('korlix_funnel_google_preflight_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const creative=(action='read',data={})=>rpc('korlix_funnel_google_creative_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
const keywords=(action='read',data={})=>rpc('korlix_funnel_google_keywords_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
async function reviewDraft(fn,a){let d=await fn();d=await fn('save',{version:d.version,fingerprint:d.fingerprint,assets:a});return fn('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});}
async function ready(){await saveReview();await reviewDraft(creative,{headlines:['Meet the team','Explore services','Start here'],descriptions:['Find support for your business.','Talk with our team today.'],path1:'',path2:''});await reviewDraft(keywords,{exact:['service'],phrase:[],broad:[],negative_exact:[],negative_phrase:[],negative_broad:[]});await reviewDraft(targeting,assets);}
async function rows(){return (await db.query("select jsonb_build_object('funnels',(select jsonb_agg(to_jsonb(t)) from korlix_funnels t),'campaigns',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_campaigns t),'connections',(select jsonb_agg(to_jsonb(t)) from korlix_google_ads_connections t),'setup',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_google_preparations t),'creative',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_google_creatives t),'keywords',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_google_keywords t),'targeting',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_google_targeting t)) r")).rows[0].r;}

const resources={budget:'customers/9876543210/campaignBudgets/101',campaign:'customers/9876543210/campaigns/102',ad_group:'customers/9876543210/adGroups/103',ad:'customers/9876543210/adGroupAds/103~104'};
const provider={
 refresh:async()=>{providerCalls++;return 'access-fixture';},roots:async()=>[rootId],account:async()=>account,
 validatePausedSearch:async(access,s)=>{providerCalls++;if(validateHook)return validateHook(s);return {validated:true};},
 createPausedSearch:async(access,s)=>{createCalls++;if(createHook)return createHook(s);return resources;},
 findPausedSearch:async(access,s)=>{providerCalls++;return findHook?findHook(s):resources;}
};
const read=async()=>{const r=await req();assert.equal(r.status,200,await r.clone().text());return r.json();};
const input=d=>({fingerprint:d.fingerprint,start_date:d.today,confirmed:true,budget_acknowledged:true,no_eu_political_ads:true});
const create=async()=>req('/create',input(await read()));
const ledger=async()=> (await db.query('select * from korlix_funnel_google_creations')).rows;
test('K181 reads local preparation without provider calls or creation writes',async()=>{
 const r=await req();assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');const d=await r.json();assert.equal(d.source,'google_paused_creation');assert.equal(d.create_ready,false);assert.equal(d.activation_supported,false);assert.equal(d.ad_publishing_ready,false);assert.equal(d.attempt,null);assert.equal(providerCalls,0);assert.deepEqual(await ledger(),[]);
});
test('K181 creates one full paused campaign after current reviews, then repeated taps only read the record',async()=>{
 await ready();const d=await read();assert.equal(d.create_ready,true);const before=await rows();let captured;createHook=async s=>{captured=s;return resources;};
 const r=await req('/create',input(d));assert.equal(r.status,201,await r.clone().text());const out=await r.json();assert.equal(out.attempt.state,'created');assert.equal(out.create_ready,false);assert.equal(out.attempt.snapshot.start_date,d.today);assert.deepEqual(out.attempt.resources,resources);assert.equal(captured.identity.account.id,account.id);assert.equal(captured.creative.headlines.length,3);assert.equal(captured.targeting.countries[1],'JM');assert.equal(captured.no_eu_political_ads,true);assert.equal(captured.search_language_mode,'automatic_from_creative_v1');assert.equal(out.draft.search_language_mode,'automatic_from_creative_v1');assert.equal((await ledger())[0].request_hash,googleDigest(JSON.stringify(googlePausedRequest(captured))));assert.equal(createCalls,1);assert.deepEqual(await rows(),before);
 const again=await req('/create',input(d));assert.equal(again.status,200);assert.equal((await again.json()).attempt.id,out.attempt.id);assert.equal(createCalls,1);assert.equal((await ledger()).length,1);
 for(const secret of ['sealed','binding_id','config_hash','private-fixture-token','request_hash'])assert(!JSON.stringify(out).includes(secret));
});
test('K181 timeout reserves the plan permanently and read-only reconciliation recovers confirmed resources',async()=>{
 await ready();createHook=async()=>{throw Error('provider might have committed token-secret');};let r=await create();assert.equal(r.status,200);let d=await r.json();assert.equal(d.attempt.state,'unknown');assert(!JSON.stringify(d).includes('token-secret'));assert.equal(createCalls,1);
 findHook=async()=>null;r=await req('/reconcile',{attempt_id:d.attempt.id});assert.equal(r.status,200);d=await r.json();assert.equal(d.attempt.state,'unknown');assert.match(d.notice,/does not prove/);r=await create();assert.equal(r.status,200);assert.equal(createCalls,1);
 findHook=null;r=await req('/reconcile',{attempt_id:d.attempt.id});assert.equal(r.status,200);d=await r.json();assert.equal(d.attempt.state,'created');assert.deepEqual(d.attempt.resources,resources);assert.equal(createCalls,1);
});
test('K181 validate-only rejection does not claim or mutate, while malformed mutation success stays unknown',async()=>{
 await ready();validateHook=async()=>{throw Error('private provider detail');};let r=await create();assert.equal(r.status,503);assert.equal(createCalls,0);assert.deepEqual(await ledger(),[]);assert(!(await r.text()).includes('private provider detail'));
 validateHook=null;createHook=async()=>({...resources,ad:'customers/0000000000/adGroupAds/103~104'});r=await create();assert.equal(r.status,200);assert.equal((await r.json()).attempt.state,'unknown');assert.equal(createCalls,1);
});
test('K181 concurrent confirmations claim exactly one dispatch',async()=>{
 await ready();const d=await read();const responses=await Promise.all([req('/create',input(d)),req('/create',input(d))]);assert(responses.every(r=>[200,201].includes(r.status)));assert.equal(createCalls,1);assert.equal((await ledger()).length,1);
});
test('K181 edits during provider validation invalidate the claim and send nothing',async()=>{
 await ready();validateHook=async()=>{const d=await creative();await creative('save',{version:d.version,fingerprint:d.fingerprint,assets:{...d.assets,path1:'services'}});return {validated:true};};const r=await create();assert([400,409].includes(r.status));assert.equal(createCalls,0);assert.deepEqual(await ledger(),[]);
});
test('K181 connection changes during validation prevent mutation',async()=>{
 await ready();validateHook=async()=>{await db.query('update korlix_google_ads_connections set version=version+1 where user_id=$1',[owner]);return {validated:true};};assert.equal((await create()).status,409);assert.equal(createCalls,0);assert.deepEqual(await ledger(),[]);
});
test('K181 incomplete, conversion bidding, test account, archive and paused page cannot create',async()=>{
 assert.equal((await read()).create_ready,false);await ready();let d=await targeting();await targeting('save',{version:d.version,fingerprint:d.fingerprint,assets:{...assets,bidding:'maximize_conversions'}});d=await targeting();await targeting('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});assert.equal((await read()).checks.maximize_clicks,false);assert.equal((await create()).status,409);
 await ready();await db.query("update korlix_google_ads_connections set accounts=jsonb_set(accounts,'{0,test_account}','true') where user_id=$1",[owner]);assert.equal((await read()).create_ready,false);await db.query('update korlix_google_ads_connections set accounts=$2 where user_id=$1',[owner,JSON.stringify([account])]);await ready();c=await campaign('archive',{confirmed:true});assert.equal((await read()).create_ready,false);f=await funnel('pause',{version:f.version});assert.equal((await read()).create_ready,false);assert.equal(createCalls,0);
});
test('K181 strict body, extra query, date and fingerprint checks occur before provider access',async()=>{
 await ready();const d=await read(),valid=input(d);for(const patch of [{confirmed:false},{budget_acknowledged:false},{no_eu_political_ads:false},{start_date:'2026-02-30'},{start_date:'2000-01-01'},{account_id:'1234567890'},{fingerprint:'a'.repeat(64)}]){clock+=60000;const r=await req('/create',{...valid,...patch});assert([400,409].includes(r.status),await r.text());}
 assert.equal((await req('?configured=true')).status,400);assert.equal((await req('/create?configured=true',valid)).status,400);assert.equal(createCalls,0);assert.equal(providerCalls,0);
});
test('K181 current ownership, tier and browser role protect reads and internal completion',async()=>{
 await ready();for(const [actor,status]of [['',401],[other,404],[basic,403]]){assert.equal((await req('',null,actor)).status,status);assert.equal((await req('/create',input(await read()),actor)).status,status);}
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(rpc('korlix_funnel_google_create_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id}}),/permission denied/);await assert.rejects(db.query('select * from korlix_funnel_google_creations'),/permission denied/);await db.exec('reset role;set role service_role');}
 const attrs=(await db.query("select prosecdef,proconfig from pg_proc where oid='korlix_funnel_google_create_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(attrs.prosecdef,false);assert.deepEqual(attrs.proconfig,['search_path=public, pg_temp']);assert.equal((await req('/finish',{})).status,404);
});
test('K181 records a successful provider outcome even if Enterprise access is revoked after dispatch',async()=>{
 await ready();createHook=async()=>{await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return resources;};assert.equal((await create()).status,403);const l=await ledger();assert.equal(l[0].state,'created');assert.deepEqual(l[0].resources,resources);assert.equal(createCalls,1);
});
test('K181 reconciliation requires the saved account and validates returned identities',async()=>{
 await ready();createHook=async()=>{throw Error();};let d=await (await create()).json();assert.equal((await req('/reconcile',{attempt_id:randomUUID()})).status,409);findHook=async()=>({...resources,campaign:'customers/1111111111/campaigns/102'});assert.equal((await req('/reconcile',{attempt_id:d.attempt.id})).status,409);assert.equal((await ledger())[0].state,'unknown');
 await db.query("update korlix_google_ads_connections set selected_account=null where user_id=$1",[owner]);assert.equal((await req('/reconcile',{attempt_id:d.attempt.id})).status,409);assert.equal(createCalls,1);
});
test('K181 write quota is separate from local reads and never creates twice',async()=>{
 await ready();const d=await read();for(let i=0;i<5;i++)assert([200,201].includes((await req('/create',input(d))).status));const r=await req('/create',input(d));assert.equal(r.status,429);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal((await req()).status,200);assert.equal(createCalls,1);
});
test('K181 production-default creation flag and unsupported API version block every provider call',async()=>{
 await ready();
 for(const patch of [{KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED:undefined},{KORLIX_GOOGLE_ADS_API_VERSION:'v26'}]){
  const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,...patch},googleAdsProvider:provider});
  const s=app.listen(0);await new Promise(r=>s.once('listening',r));
  try{const url=`http://127.0.0.1:${s.address().port}/api/funnels/${f.id}/campaigns/${c.id}/google-create`;const d=await (await fetch(url)).json();assert.equal(d.checks.platform_enabled,false);assert.equal(d.create_ready,false);const response=await fetch(url+'/create',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input(d))});assert.equal(response.status,409);assert.equal(providerCalls,0);assert.equal(createCalls,0);}
  finally{s.closeAllConnections();await new Promise(r=>s.close(r));}
 }
});
test('K181 failed completion storage leaves a durable unknown record and never resends',async()=>{
 await ready();const original=database.rpc;database.rpc=async(name,p)=>name==='korlix_funnel_google_create_v1'&&p.p_action==='finish'?{error:{code:'XX000'}}:original(name,p);
 try{const r=await create();assert.equal(r.status,200);assert.equal((await r.json()).attempt.state,'unknown');assert.equal((await ledger())[0].state,'unknown');assert.equal(createCalls,1);}finally{database.rpc=original;}
 const d=await read();const response=await req('/reconcile',{attempt_id:d.attempt.id});assert.equal(response.status,200);assert.equal((await response.json()).attempt.state,'created');assert.equal(createCalls,1);
});
test('K181 failed durable claim sends no mutation and invalid OAuth requires reconnect',async()=>{
 await ready();const original=database.rpc;database.rpc=async(name,p)=>name==='korlix_funnel_google_create_v1'&&p.p_action==='claim'?{error:{code:'XX000'}}:original(name,p);
 try{assert.equal((await create()).status,503);assert.equal(createCalls,0);assert.deepEqual(await ledger(),[]);}finally{database.rpc=original;}
 validateHook=async()=>{throw new GoogleAdsAccessError();};assert.equal((await create()).status,409);assert.equal(createCalls,0);const row=(await db.query('select needs_reconnect from korlix_google_ads_connections where user_id=$1',[owner])).rows[0];assert.equal(row.needs_reconnect,true);
});
async function installCreationContract(legacy=false){
 let sql=await readFile(new URL('../../supabase/migrations/'+(legacy?'20260923210921_funnel_google_paused_create.sql':'20260924034142_funnel_google_search_language_contract.sql'),import.meta.url),'utf8');
 if(legacy)sql='begin;\n'+sql.slice(sql.indexOf('create function public.korlix_funnel_google_create_v1')).replace('create function','create or replace function');
 await db.exec('reset role');await db.exec(sql);await db.exec('set role service_role');
}
test('K189 migration invalidates old confirmations before provider access without rewriting historical attempts',async()=>{
 await ready();let old;
 try{await installCreationContract(true);old=await read();assert(!Object.hasOwn(old.draft,'search_language_mode'));}finally{await installCreationContract();}
 const current=await read();assert.notEqual(current.fingerprint,old.fingerprint);assert.equal((await req('/create',input(old))).status,409);assert.equal(providerCalls,0);assert.equal(createCalls,0);
 let saved;
 try{
  await installCreationContract(true);old=await read();const id=randomUUID(),snapshot={...old.draft,start_date:old.today,end_date:new Date(Date.parse(old.today+'T00:00:00Z')+(old.draft.plan.days-1)*86400000).toISOString().slice(0,10),provider_name:'KORLIX '+id,no_eu_political_ads:true,budget_acknowledged:true};
  await rpc('korlix_funnel_google_create_v1',{p_actor:owner,p_action:'claim',p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',create_enabled:true,...input(old),attempt_id:id,request_hash:googleDigest(JSON.stringify(googlePausedRequest(snapshot)))}});saved=await ledger();
 }finally{await installCreationContract();}
 assert.deepEqual(await ledger(),saved);const d=await read();assert.equal(d.draft.search_language_mode,'automatic_from_creative_v1');assert(!Object.hasOwn(d.attempt.snapshot,'search_language_mode'));
 findHook=async s=>{assert.deepEqual(s,saved[0].snapshot);return resources;};assert.equal((await req('/reconcile',{attempt_id:d.attempt.id})).status,200);assert.equal(createCalls,0);assert.deepEqual((await ledger())[0].snapshot,saved[0].snapshot);assert.equal((await ledger())[0].request_hash,saved[0].request_hash);
});
test('K189 project access error neither claims a dispatch nor invalidates encrypted OAuth credentials',async()=>{
 await ready();const before=(await rows()).connections;
 const p=createGoogleAdsProvider(config,{fetchImpl:async()=>new Response(JSON.stringify({error:{details:[{errors:[{errorCode:{authorizationError:'CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION'}}]}]}}),{status:403})});
 validateHook=async()=>p.roots('fixture');const r=await create();assert.equal(r.status,409);assert.match(await r.text(),/Cloud project needs approval/);assert.deepEqual((await rows()).connections,before);assert.equal(createCalls,0);assert.deepEqual(await ledger(),[]);
});
