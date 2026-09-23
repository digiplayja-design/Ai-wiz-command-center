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
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN:'fixture-developer-token',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=googleAdsConfiguration(env),rootId='1234567890',account={id:'9876543210',name:'Growth account',currency:'USD',timezone:'UTC',manager:false,status:'ENABLED',test_account:false};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'google',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,server,base,f,c,clock=Date.now(),providerCalls=0;
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-targeting${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql','20260923085331_funnel_google_creative.sql','20260923094201_funnel_google_creative_review.sql','20260923103256_funnel_google_keywords.sql','20260923105943_funnel_google_keyword_review.sql','20260923112526_funnel_google_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
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

test('Targeting reads are private and no-store, with no row or provider requirement',async()=>{
 await db.exec('delete from korlix_google_ads_connections');const res=await req();assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'no-store');const d=await res.json();assert.equal(d.source,'google_targeting_draft');assert.equal(d.version,0);assert.equal(d.draft_complete,false);assert.equal(d.ad_publishing_ready,false);assert.deepEqual(d.assets,empty());assert.deepEqual(d.catalog,catalog);assert.equal(d.saved_labels,null);assert.equal(d.context.destination,`https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_${c.id.replaceAll('-','')}`);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_targeting')).rows[0].n,0);assert.equal(providerCalls,0);
});
test('Enterprise tier, ownership, campaign scope and service-only grants protect both routes',async()=>{
 const d=await targeting();for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('',null,actor)).status,status);assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets},actor)).status,status);}
 assert.equal((await req('',null,owner,{funnel:randomUUID()})).status,404);assert.equal((await req('',null,owner,{campaign:randomUUID()})).status,404);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_targeting'),/permission denied/);await assert.rejects(targeting(),/permission denied/);await assert.rejects(db.query('select korlix_google_targeting_catalog_v1()'),/permission denied/);await db.exec('reset role;set role service_role');}
 const rows=(await db.query("select prosecdef,proconfig from pg_proc where proname in ('korlix_funnel_google_targeting_v1','korlix_google_targeting_catalog_v1','korlix_google_targeting_valid_v1')")).rows;assert.equal(rows.length,3);for(const p of rows){assert.equal(p.prosecdef,false);assert.deepEqual(p.proconfig,['search_path=public, pg_temp']);}
 assert.equal((await db.query("select relrowsecurity rls from pg_class where oid='korlix_funnel_google_targeting'::regclass")).rows[0].rls,true);
});
test('Empty and complete choices roundtrip, with exact saved labels and increasing versions',async()=>{
 let d=await save(empty());assert.equal(d.version,1);assert.equal(d.draft_complete,false);assert.equal(d.draft_current,true);assert.deepEqual(d.saved_labels,{countries:{},content_languages:{}});
 const response=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets});assert.equal(response.status,200);d=await response.json();assert.equal(d.version,2);assert.equal(d.draft_complete,true);assert.deepEqual(d.assets,assets);assert.deepEqual(d.saved_context,d.context);assert.deepEqual(d.saved_labels,{countries:{US:'United States',JM:'Jamaica',CA:'Canada'},content_languages:{en:'English',es:'Spanish'}});
 d=await save({...assets,location_mode:'presence_or_interest',bidding:'maximize_conversions'});assert.equal(d.version,3);assert.equal(d.draft_complete,true);assert.equal(d.ad_publishing_ready,false);
 d=await save(empty());assert.equal(d.version,4);assert.equal(d.draft_complete,false);
});
test('JavaScript and SQL reject unknown codes, overlaps, duplicates, types, excessive lists and extra fields',async()=>{
 const bad=[null,[],{}, {...assets,extra:true},{...assets,countries:null},{...assets,countries:['XX']},{...assets,countries:['us']},{...assets,countries:['US','US']},{...assets,countries:[null]},{...assets,countries:[2840]},{...assets,excluded_countries:['US']},{...assets,excluded_countries:['CA','CA']},{...assets,content_languages:['xx']},{...assets,content_languages:['en','en']},{...assets,location_mode:null},{...assets,location_mode:'all'},{...assets,bidding:'manual_cpc'}, {...assets,countries:catalog.countries.slice(0,21).map(x=>x.code)}, {...assets,content_languages:catalog.languages.slice(0,11).map(x=>x.code)}];
 for(const a of bad){assert.throws(()=>googleTargetingAssets(a));assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false,JSON.stringify(a));}
 const max={...empty(),countries:catalog.countries.slice(0,20).map(x=>x.code),excluded_countries:catalog.countries.slice(20,40).map(x=>x.code),content_languages:catalog.languages.slice(0,10).map(x=>x.code)};
 for(const a of [empty(),assets,max]){googleTargetingAssets(a);assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
 await save(max);await assert.rejects(db.query('update korlix_funnel_google_targeting set assets=$1',[JSON.stringify({...assets,excluded_countries:['US']})]),/check constraint/);
});
test('Requests cannot forge actor, snapshot, destination, readiness or revision',async()=>{
 const d=await targeting(),body={version:0,fingerprint:d.fingerprint,assets};
 for(const patch of [{version:-1},{version:1.5},{version:2147483648},{fingerprint:'x'},{actor:other},{public_base:'https://attacker.test'},{ad_publishing_ready:true},{saved_labels:{}},{assets:null}]){assert.throws(()=>googleTargetingInput({...body,...patch}));assert.equal((await req('/save',{...body,...patch})).status,400);}
 assert.equal((await req('?actor='+other)).status,400);assert.equal((await req('/save?force=true',body)).status,400);
});
test('Concurrent drafts have one winner without provider calls',async()=>{
 const d=await targeting(),body={version:0,fingerprint:d.fingerprint,assets};const results=await Promise.all([req('/save',body),req('/save',{...body,assets:{...assets,countries:['JM']}})]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);assert.equal((await targeting()).version,1);assert.equal(providerCalls,0);
});
test('Campaign and published-page changes flag stale context and reject earlier fingerprints',async()=>{
 const d=await save();c=await campaign('save',{...plan,audience:'A changed audience'});let next=await targeting();assert.equal(next.draft_current,false);assert.equal(next.saved_context.audience,plan.audience);assert.deepEqual(next.saved_labels,d.saved_labels);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,409);
 const fresh=await save();assert.equal(fresh.draft_current,true);f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Published change'}});f=await funnel('publish',{version:f.version,confirmed:true});next=await targeting();assert.equal(next.draft_current,false);assert.equal(next.version,fresh.version);
});
test('Targeting saves preserve setup, copy and keyword reviews; reporting and unpublished edits preserve draft context',async()=>{
 const setupBefore=await saveReview();
 const creative=(action='read',data={})=>rpc('korlix_funnel_google_creative_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
 let cr=await creative();cr=await creative('save',{version:0,fingerprint:cr.fingerprint,assets:{headlines:['Meet the team','Explore services','Start here'],descriptions:['Find support for your business.','Talk with our team today.'],path1:'',path2:''}});const creativeBefore=await creative('review',{version:cr.version,review_fingerprint:cr.review_fingerprint,confirmed:true});
 const keywords=(action='read',data={})=>rpc('korlix_funnel_google_keywords_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
 let k=await keywords();k=await keywords('save',{version:0,fingerprint:k.fingerprint,assets:{exact:['service'],phrase:[],broad:[],negative_exact:[],negative_phrase:[],negative_broad:[]}});const keywordsBefore=await keywords('review',{version:k.version,review_fingerprint:k.review_fingerprint,confirmed:true});
 const d=await save();assert.deepEqual(await creative(),creativeBefore);assert.deepEqual(await setup(),setupBefore);assert.deepEqual(await keywords(),keywordsBefore);
 c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Unpublished'}});const next=await targeting();assert.equal(next.draft_current,true);assert.equal(next.fingerprint,d.fingerprint);assert.equal((await keywords()).review_current,true);assert.equal((await creative()).review_current,true);
});
test('Archive blocks editing; paused pages remain drafts; tier downgrade is immediate',async()=>{
 await save();c=await campaign('archive',{confirmed:true});let d=await targeting();assert.equal(d.editable,false);assert.deepEqual(d.assets,assets);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,400);c=await campaign('reopen');assert.equal((await targeting()).editable,true);
 f=await funnel('pause',{version:f.version});d=await targeting();assert.equal(d.context.page_state,'paused');assert.equal(d.ad_publishing_ready,false);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,403);
});
test('Non-Google campaigns are rejected; funnel deletion cascades its targeting draft',async()=>{
 await save();await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await req()).status,400);await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_targeting')).rows[0].n,0);
});
test('Read and save share 30 requests per owner per minute',async()=>{for(let i=0;i<30;i++)assert.equal((await req()).status,200);const r=await req('/save',{version:0,fingerprint:'a'.repeat(64),assets});assert.equal(r.status,429);assert.equal(r.headers.get('cache-control'),'no-store');});
