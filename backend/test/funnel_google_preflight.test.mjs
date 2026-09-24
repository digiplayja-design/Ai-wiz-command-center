import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher} from '../funnels/google_ads_provider.mjs';
import {googleTargetingInput,googleTargetingAssets,googleTargetingCatalog as catalog} from '../funnels/google_targeting.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=googleAdsConfiguration(env),rootId='1234567890',account={id:'9876543210',name:'Growth account',currency:'USD',timezone:'UTC',manager:false,status:'ENABLED',test_account:false};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'google',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,server,base,f,c,clock=Date.now(),providerCalls=0;
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-preflight${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql','20260923085331_funnel_google_creative.sql','20260923094201_funnel_google_creative_review.sql','20260923103256_funnel_google_keywords.sql','20260923105943_funnel_google_keyword_review.sql','20260923112526_funnel_google_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923120825_funnel_google_targeting_review.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923123817_funnel_google_preflight.sql',import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:new Proxy({},{get:()=>()=>{providerCalls++;throw Error('No provider operation is allowed');}})});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;});
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
test('K170 missing drafts return six coherent preparation checks without writes or credentials',async()=>{
 const before=await rows(),response=await req();assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');const d=await response.json();assert.equal(d.source,'google_preflight');assert.deepEqual(d.checks,{page_published:true,plan_reviewed:true,setup_reviewed:false,copy_reviewed:false,keywords_reviewed:false,targeting_reviewed:false});assert.equal(d.preparation_complete,false);assert.equal(d.ad_publishing_ready,false);assert(Number.isFinite(Date.parse(d.checked_at)));assert.equal(d.creative.version,0);assert.equal(d.targeting.version,0);assert.deepEqual(d.creative.context,d.keywords.context);assert.deepEqual(d.creative.context,d.targeting.context);assert.deepEqual(await rows(),before);for(const secret of ['sealed','config_hash','binding_id','private-fixture-token'])assert(!JSON.stringify(d).includes(secret));assert.equal(providerCalls,0);
});
test('K170 all current reviews complete preparation only and preserve every stored row',async()=>{
 await ready();const before=await rows();const d=await preflight();assert(Object.values(d.checks).every(Boolean));assert.equal(d.preparation_complete,true);assert.equal(d.ad_publishing_ready,false);assert.equal(d.creative.reviewed_snapshot.assets.headlines[0],'Meet the team');assert.equal(d.targeting.reviewed_snapshot.labels.countries.US,'United States');assert.deepEqual(await rows(),before);assert.equal(providerCalls,0);
});
test('K170 each cleared or re-saved draft changes only its corresponding review check',async()=>{
 await ready();for(const [key,fn] of [['copy_reviewed',creative],['keywords_reviewed',keywords],['targeting_reviewed',targeting]]){
  let d=await fn();await fn('save',{version:d.version,fingerprint:d.fingerprint,assets:d.assets});let summary=await preflight();assert.equal(summary.checks[key],false);assert.equal(summary.preparation_complete,false);assert.equal(Object.values(summary.checks).filter(Boolean).length,5);
  d=await fn();await fn('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});d=await fn();await fn('clear_review',{version:d.version,confirmed:true});assert.equal((await preflight()).checks[key],false);d=await fn();await fn('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});
 }
 let d=await setup();await setup('clear',{version:d.version,confirmed:true});assert.equal((await preflight()).checks.setup_reviewed,false);assert.equal(providerCalls,0);
});
test('K170 reports and unpublished edits preserve the aggregate while published changes invalidate it',async()=>{
 await ready();c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Not yet public'}});assert.equal((await preflight()).preparation_complete,true);f=await funnel('publish',{version:f.version,confirmed:true});const d=await preflight();assert.equal(d.checks.page_published,true);assert.equal(Object.values(d.checks).filter(Boolean).length,1);assert.deepEqual(d.creative.context,d.targeting.context);
});
test('K170 disabled configuration, changed account identity, disconnect and expiry block account preparation',async()=>{
 await ready();for(const patch of [{configured:false},{config_hash:'changed'}]){const d=await preflight(patch);assert.equal(d.checks.setup_reviewed,false);assert.equal(d.preparation_complete,false);assert.equal(d.checks.copy_reviewed,true);}
 await db.query("update korlix_google_ads_connections set refresh_expires_at=now()-interval '1 second' where user_id=$1",[owner]);assert.equal((await preflight()).checks.setup_reviewed,false);await db.query('delete from korlix_google_ads_connections where user_id=$1',[owner]);let d=await preflight();assert.equal(d.setup.current_snapshot.google_ads.account,null);assert.equal(d.preparation_complete,false);assert.equal(d.checks.targeting_reviewed,true);await connect();assert.equal((await preflight()).checks.setup_reviewed,false);assert.equal(providerCalls,0);
});
test('K170 current tier, ownership, campaign scope and browser-role denial protect aggregate data',async()=>{
 for(const [actor,status] of [['',401],[other,404],[basic,403]])assert.equal((await req('',null,actor)).status,status);
 for(const ids of [{campaign:randomUUID()},{funnel:randomUUID()}])assert.equal((await req('',null,owner,ids)).status,404);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(preflight(),/permission denied/);await db.exec('reset role;set role service_role');}
 const p=(await db.query("select prosecdef,proconfig from pg_proc where oid='korlix_funnel_google_preflight_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(p.prosecdef,false);assert.deepEqual(p.proconfig,['search_path=public, pg_temp']);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);
});
test('K170 checklist is read-only, rejects query injection and cannot handle non-Google campaigns',async()=>{
 for(const action of [null,'review','save','clear'])await assert.rejects(preflight({},owner,action),/read only/);
 assert.equal((await req('?configured=true')).status,400);assert.equal((await req('',{})).status,404);assert.equal((await req('/review',{confirmed:true})).status,404);
 await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await req()).status,400);
});
test('K170 archive and pause retain historical records but invalidate preparation',async()=>{
 await ready();c=await campaign('archive',{confirmed:true});let d=await preflight();assert.equal(d.checks.plan_reviewed,false);assert.equal(d.preparation_complete,false);assert(d.targeting.reviewed_snapshot);f=await funnel('pause',{version:f.version});d=await preflight();assert.equal(d.checks.page_published,false);assert.deepEqual(d.creative.context,d.keywords.context);assert.deepEqual(d.creative.context,d.targeting.context);
});
test('K170 concurrent checklist reads and targeting saves never mix component context',async()=>{
 await ready();const before=await targeting();const [response,saveResult]=await Promise.all([req(),targeting('save',{version:before.version,fingerprint:before.fingerprint,assets})]);assert.equal(response.status,200);const d=await response.json();assert.deepEqual(d.creative.context,d.targeting.context);assert.equal(d.checks.targeting_reviewed,d.targeting.review_current);assert.equal(d.preparation_complete,Object.values(d.checks).every(Boolean));assert.equal((await preflight()).checks.targeting_reviewed,false);assert.equal(saveResult.draft_revision,2);assert.equal(providerCalls,0);
});
test('K170 reads share the 30-per-owner minute limit and leave draft state untouched',async()=>{
 const before=await rows();for(let i=0;i<30;i++)assert.equal((await req()).status,200);const r=await req();assert.equal(r.status,429);assert.equal(r.headers.get('cache-control'),'no-store');assert.deepEqual(await rows(),before);assert.equal(providerCalls,0);
});
