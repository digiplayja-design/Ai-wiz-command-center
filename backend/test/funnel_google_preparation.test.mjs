import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher} from '../funnels/google_ads_provider.mjs';
import {googlePreparationInput} from '../funnels/google_preparation.mjs';
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
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-setup${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:new Proxy({},{get:()=>()=>{providerCalls++;throw Error('No provider operation is allowed');}})});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('Setup preview is owner scoped, credential free, read only and uses the server campaign destination',async()=>{
 const r=await req();assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');const body=await r.json();assert.equal(body.ready_for_review,true);assert.equal(body.review_current,false);assert.equal(body.version,0);assert.equal(body.ad_publishing_ready,false);assert.equal(body.current_snapshot.campaign.planned_total_cents,35000);assert.equal(body.current_snapshot.google_ads.login_customer_id,rootId);assert.equal(body.current_snapshot.landing_page.destination,`https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_${c.id.replaceAll('-','')}`);
 for(const secret of ['sealed','config_hash','meta_user_id','binding_id','private-fixture-token'])assert(!JSON.stringify(body).includes(secret));assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_preparations')).rows[0].n,0);assert.equal(providerCalls,0);
});
test('Real HTTP ownership and private SQL privileges deny other owners and browser roles',async()=>{
 for(const [actor,status] of [['',401],[other,404],[basic,403]])assert.equal((await req('',null,actor)).status,status);
 assert.equal((await req('',null,owner,{campaign:randomUUID()})).status,404);assert.equal((await req('',null,owner,{funnel:randomUUID()})).status,404);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_preparations'),/permission denied/);await assert.rejects(setup(),/permission denied/);await db.exec('reset role;set role service_role');}
 const schema=(await db.query("select p.prosecdef,(select relrowsecurity from pg_class where oid='korlix_funnel_google_preparations'::regclass) rls from pg_proc p where p.oid='korlix_funnel_google_preparation_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(schema.prosecdef,false);assert.equal(schema.rls,true);
});
test('Review and clear use exact versions and preserve campaign, connection and reporting data',async()=>{
 const before=(await db.query('select to_jsonb(c) c from korlix_google_ads_connections c')).rows;const campaignBefore=(await db.query('select to_jsonb(c) c from korlix_funnel_campaigns c')).rows;
 const preview=await setup(),body={version:preview.version,fingerprint:preview.fingerprint,confirmed:true};let r=await req('/review',body);assert.equal(r.status,200);const saved=await r.json();assert.equal(saved.version,1);assert.equal(saved.review_current,true);assert.deepEqual(saved.reviewed_snapshot,preview.current_snapshot);
 assert.equal((await req('/review',body)).status,409);assert.equal((await req('/clear',{version:0,confirmed:true})).status,409);
 r=await req('/clear',{version:1,confirmed:true});assert.equal(r.status,200);const cleared=await r.json();assert.equal(cleared.version,2);assert.equal(cleared.reviewed_snapshot,null);assert.equal(cleared.review_current,false);
 assert.deepEqual((await db.query('select to_jsonb(c) c from korlix_google_ads_connections c')).rows,before);assert.deepEqual((await db.query('select to_jsonb(c) c from korlix_funnel_campaigns c')).rows,campaignBefore);assert.equal(providerCalls,0);
});
test('Changed campaign, published content and Google Ads identities invalidate saved reviews and stale submissions',async()=>{
 const saved=await saveReview();c=await campaign('save',{...plan,headline:'Changed offer'});let r=await setup();assert.equal(r.review_current,false);assert.equal(r.checks.plan_reviewed,false);assert.equal(r.reviewed_snapshot.campaign.headline,plan.headline);
 c=await campaign('review',{confirmed:true});await saveReview();f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'New public offer'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await setup()).review_current,false);
 c=await campaign('review',{confirmed:true});const fresh=await saveReview();await db.query('update korlix_google_ads_connections set login_customer_id=$2 where user_id=$1',[owner,'1111111111']);r=await setup();assert.equal(r.review_current,false);assert.equal(r.checks.access_context,false);
 await assert.rejects(setup('review',{version:fresh.version,fingerprint:fresh.fingerprint,confirmed:true}),/changed/);assert.notEqual(r.fingerprint,saved.fingerprint);
});
test('Manual results and unpublished edits preserve a current setup review',async()=>{
 const saved=await saveReview();const day=new Date().toISOString().slice(0,10);c=await campaign('report',{day,spend_cents:1000,clicks:10,impressions:1000,note:'Owner entered'});f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'Unpublished draft'}});
 const r=await setup();assert.equal(r.fingerprint,saved.fingerprint);assert.equal(r.review_current,true);assert.equal(r.current_snapshot.landing_page.headline,doc.headline);
});
test('Configuration, expired access, invalid access context and non-USD or inactive accounts block review without converting amounts',async()=>{
 const saved=await saveReview();let r=await setup('read',{configured:false});assert.equal(r.checks.google_configured,false);assert.equal(r.review_current,false);
 r=await setup('read',{config_hash:'different'});assert.equal(r.checks.google_connected,false);assert.equal(r.review_current,false);
 await db.query("update korlix_google_ads_connections set refresh_expires_at=now()-interval '1 second' where user_id=$1",[owner]);r=await setup();assert.equal(r.ready_for_review,false);await assert.rejects(setup('review',{version:saved.version,fingerprint:r.fingerprint,confirmed:true}),/Complete the setup/);
 await db.query("update korlix_google_ads_connections set refresh_expires_at=now()+interval '1 day',accounts=$2 where user_id=$1",[owner,JSON.stringify([{...account,currency:'JMD',status:'SUSPENDED'}])]);r=await setup();assert.equal(r.checks.currency_supported,false);assert.equal(r.checks.account_active,false);assert.equal(r.current_snapshot.campaign.currency,'USD');assert.equal(r.current_snapshot.campaign.daily_cents,2500);
});
test('Disconnect and reconnect cannot reuse a saved Google Ads setup review',async()=>{
 const saved=await saveReview();await db.query('delete from korlix_google_ads_connections where user_id=$1',[owner]);let r=await setup();assert.equal(r.checks.google_connected,false);assert.equal(r.review_current,false);assert.deepEqual(r.reviewed_snapshot,saved.reviewed_snapshot);
 await connect();r=await setup();assert.equal(r.ready_for_review,true);assert.equal(r.review_current,false);assert.notEqual(r.fingerprint,saved.fingerprint);
});
test('Archiving, page pausing and a tier downgrade cannot preserve an actionable setup review',async()=>{
 await saveReview();c=await campaign('archive',{confirmed:true});assert.equal((await setup()).review_current,false);
 await db.query("update korlix_funnels set state='paused' where id=$1",[f.id]);assert.equal((await setup()).checks.page_published,false);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);
});
test('Exact HTTP schemas reject injected destinations, readiness, query fields, and unconfirmed mutations',async()=>{
 const r=await setup();assert.equal((await req('?fields=sealed')).status,400);
 for(const extra of [{confirmed:false},{version:'0'},{fingerprint:'invalid'},{public_base:'https://evil.example'},{configured:true}])assert.equal((await req('/review',{version:0,fingerprint:r.fingerprint,confirmed:true,...extra})).status,400);
 assert.equal((await req('/clear',{version:0})).status,400);await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await req()).status,400);assert.equal(providerCalls,0);
});
test('Concurrent reviews admit only the currently displayed preparation version',async()=>{
 const r=await setup();const body={version:r.version,fingerprint:r.fingerprint,confirmed:true};const responses=await Promise.all([req('/review',body),req('/review',body)]);assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);assert.equal((await setup()).version,1);
});
test('Setup routes share an owner rate limit and deletion cascades only local review data',async()=>{
 await saveReview();for(let i=0;i<30;i++)assert.equal((await req()).status,200);assert.equal((await req()).status,429);assert.equal(providerCalls,0);
 await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_preparations')).rows[0].n,0);assert.equal((await db.query('select count(*)::int n from korlix_google_ads_connections')).rows[0].n,1);
});
test('Preparation input accepts version zero only for an unsaved review and rejects unsafe integers',()=>{
 assert.deepEqual(googlePreparationInput('review',{version:0,fingerprint:'a'.repeat(64),confirmed:true}),{version:0,fingerprint:'a'.repeat(64),confirmed:true});
 for(const version of [-1,1.5,Infinity,2147483648,null])assert.throws(()=>googlePreparationInput('clear',{version,confirmed:true}));
});

test('Direct accounts preserve their access identity; manager and test accounts cannot pass review',async()=>{
 await db.query('update korlix_google_ads_connections set roots=$2,root_id=$3,root_name=$4,login_customer_id=null where user_id=$1',[owner,JSON.stringify([account.id]),account.id,'Direct advertiser']);
 let r=await setup();assert.equal(r.ready_for_review,true);const direct=await saveReview();assert.equal(direct.reviewed_snapshot.google_ads.login_customer_id,null);
 await db.query('update korlix_google_ads_connections set accounts=$2 where user_id=$1',[owner,JSON.stringify([{...account,manager:true,test_account:true}])]);
 r=await setup();assert.equal(r.checks.account_active,false);assert.equal(r.checks.production_account,false);assert.equal(r.review_current,false);await assert.rejects(setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true}),/Complete the setup/);
});
test('Access roots, manager context, reconnect flags and unknown test identity fail closed',async()=>{
 await saveReview();
 for(const patch of ["roots='[]'", "login_customer_id=null", "needs_reconnect=true", "accounts=jsonb_set(accounts,'{0,test_account}','null')"]){
  await db.query('update korlix_google_ads_connections set '+patch+' where user_id=$1',[owner]);
  const r=await setup();assert.equal(r.ready_for_review,false);assert.equal(r.review_current,false);
  await db.query('delete from korlix_google_ads_connections where user_id=$1',[owner]);await connect();
 }
 assert.equal(providerCalls,0);
});
