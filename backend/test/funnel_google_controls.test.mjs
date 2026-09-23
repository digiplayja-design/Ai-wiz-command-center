import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
import {googleTargetingInput,googleTargetingAssets,googleTargetingCatalog as catalog} from '../funnels/google_targeting.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_GOOGLE_ADS_BUDGET_ENABLED:'true',KORLIX_GOOGLE_ADS_CONTROLS_ENABLED:'true',KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED:'true',KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN:'fixture-developer-token',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
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
 for(const file of ['20260923153540_funnel_google_radius.sql','20260923172253_funnel_google_locations.sql','20260923210921_funnel_google_paused_create.sql','20260923221038_funnel_google_controls.sql','20260923225318_funnel_google_budget.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:provider});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;createCalls=0;validateHook=null;createHook=null;findHook=null;controlCalls=0;controlHook=null;controlValidateHook=null;inspectionHook=null;observedStatus='PAUSED';budgetCalls=0;budgetHook=null;budgetValidateHook=null;budgetInspectHook=null;effectiveCents=2500;});
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
let controlCalls=0,controlHook=null,controlValidateHook=null,inspectionHook=null,observedStatus='PAUSED';
let budgetCalls=0,budgetHook=null,budgetValidateHook=null,budgetInspectHook=null,effectiveCents=2500;
const provider={
 inspectSearchBudget:async(a,s)=>{if(budgetInspectHook)return budgetInspectHook(s);if(s.plan.daily_cents!==effectiveCents)throw Error('budget drift');return {status:{resource:resources.campaign,name:s.provider_name,status:observedStatus},budget:{resource:resources.budget,daily_cents:effectiveCents}};},
 validateSearchBudget:async()=>budgetValidateHook?budgetValidateHook():({validated:true}),
 applySearchBudget:async(a,s,r,cents)=>{budgetCalls++;if(budgetHook)return budgetHook(cents);effectiveCents=cents;return {confirmed:true,action:'budget'};},
 createdSearchStatus:async()=>({resource:resources.campaign,name:'Created campaign',status:observedStatus}),
 inspectCreatedSearch:async()=>inspectionHook?inspectionHook():({resources,statuses:{campaign:observedStatus,ad_group:'PAUSED',ad:'PAUSED'},policy:'APPROVED'}),
 validateSearchControl:async()=>controlValidateHook?controlValidateHook():({validated:true}),
 applySearchControl:async(access,s,r,action)=>{controlCalls++;if(controlHook)return controlHook(action);observedStatus=action==='activate'?'ENABLED':'PAUSED';return {confirmed:true,action};},
 refresh:async()=>{providerCalls++;return 'access-fixture';},roots:async()=>[rootId],account:async()=>account,
 validatePausedSearch:async(access,s)=>{providerCalls++;if(validateHook)return validateHook(s);return {validated:true};},
 createPausedSearch:async(access,s)=>{createCalls++;if(createHook)return createHook(s);return resources;},
 findPausedSearch:async(access,s)=>{providerCalls++;return findHook?findHook(s):resources;}
};
const read=async()=>{const r=await req();assert.equal(r.status,200,await r.clone().text());return r.json();};
const input=d=>({fingerprint:d.fingerprint,start_date:d.today,confirmed:true,budget_acknowledged:true,no_eu_political_ads:true});
const create=async()=>req('/create',input(await read()));
const ledger=async()=> (await db.query('select * from korlix_funnel_google_creations')).rows;

const controls=(suffix='',body=null,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/google-controls${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
const record=async()=>{const r=await controls();assert.equal(r.status,200,await r.clone().text());return r.json();};
const inspect=async()=>{const r=await controls('/inspect',{});assert.equal(r.status,200,await r.clone().text());return r.json();};
const controlInput=(d,action='activate')=>({proof:d.observation.proof,action,confirmed:true,spend_acknowledged:action==='activate'});
const commands=async()=> (await db.query('select * from korlix_funnel_google_commands order by sequence')).rows;
async function created(){await ready();const r=await create();assert.equal(r.status,201,await r.clone().text());providerCalls=0;}

test('K182 local reads do not call Google, and actual SQL roles deny browser access',async()=>{
 const d=await record();assert.equal(d.checks.creation_recorded,false);assert.equal(providerCalls,0);assert.deepEqual(await commands(),[]);
 for(const [actor,status]of [['',401],[other,404],[basic,403]])assert.equal((await controls('',null,actor)).status,status);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_commands'),/permission denied/);await assert.rejects(rpc('korlix_funnel_google_controls_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id}}),/permission denied/);await db.exec('reset role;set role service_role');}
 const attr=(await db.query("select prosecdef,proconfig from pg_proc where oid='korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(attr.prosecdef,false);assert.deepEqual(attr.proconfig,['search_path=public, pg_temp']);assert.equal((await controls('/finish',{})).status,404);
});
test('K182 explicit fresh preview activates, pauses and permits a fresh resume, with ordered receipts',async()=>{
 await created();let d=await inspect();assert.equal(d.observation.can_activate,true);assert.equal(d.observation.can_pause,false);let r=await controls('/apply',controlInput(d));assert.equal(r.status,200,await r.clone().text());d=await r.json();assert.equal(d.latest_command.state,'confirmed');assert.equal(d.latest_command.action,'activate');assert.equal(d.observation,undefined);
 d=await inspect();assert.equal(d.observation.can_pause,true);r=await controls('/apply',controlInput(d,'pause'));assert.equal(r.status,200);d=await inspect();assert.equal(d.observation.can_activate,true);r=await controls('/apply',controlInput(d));assert.equal(r.status,200);assert.equal(controlCalls,3);assert.deepEqual((await commands()).map(x=>x.sequence),[1,2,3]);
 assert(!JSON.stringify(d).includes('private-fixture-token'));assert(!JSON.stringify(d).includes('config_hash'));
});
test('K182 concurrent confirmations and replay dispatch once',async()=>{
 await created();const d=await inspect(),body=controlInput(d);const responses=await Promise.all([controls('/apply',body),controls('/apply',body)]);assert(responses.some(r=>r.status===200));assert(responses.some(r=>r.status===409));assert.equal(controlCalls,1);assert.equal((await commands()).length,1);assert.equal((await controls('/apply',body)).status,409);
});
test('K182 uncertain activation blocks every later command even when status is observed enabled',async()=>{
 await created();const d=await inspect();controlHook=async()=>{observedStatus='ENABLED';throw Error('secret result lost');};const r=await controls('/apply',controlInput(d));assert.equal(r.status,200);const after=await r.json();assert.equal(after.latest_command.state,'unknown');assert.match(after.notice,/may be spending/);assert(!JSON.stringify(after).includes('secret result'));
 const seen=await inspect();assert.equal(seen.observation.status.status,'ENABLED');assert.equal(seen.observation.can_pause,false);assert.equal(seen.observation.proof,null);assert.equal((await commands())[0].state,'unknown');assert.equal((await controls('/apply',controlInput(d))).status,409);assert.equal(controlCalls,1);
});
test('K182 failed receipt persistence preserves unknown and does not resend',async()=>{
 await created();const d=await inspect(),original=database.rpc;database.rpc=async(name,p)=>name==='korlix_funnel_google_controls_v1'&&p.p_action==='finish'?{error:{code:'XX000'}}:original(name,p);
 try{const r=await controls('/apply',controlInput(d));assert.equal(r.status,200);assert.equal((await r.json()).latest_command.state,'unknown');}finally{database.rpc=original;}
 assert.equal(controlCalls,1);assert.equal((await controls('/apply',controlInput(d))).status,409);
});
test('K182 validation or claim failure dispatches nothing',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{throw Error('hidden');};assert.equal((await controls('/apply',controlInput(d))).status,503);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
 controlValidateHook=null;const original=database.rpc;database.rpc=async(name,p)=>name==='korlix_funnel_google_controls_v1'&&p.p_action==='claim'?{error:{code:'XX000'}}:original(name,p);
 try{assert.equal((await controls('/apply',controlInput(d))).status,503);assert.equal(controlCalls,0);}finally{database.rpc=original;}
});
test('K182 stale provider state, tampered proof, expiry, wrong action and extra fields block before dispatch',async()=>{
 await created();const d=await inspect(),body=controlInput(d);
 for(const patch of [{proof:body.proof+'a'},{confirmed:false},{spend_acknowledged:false},{account_id:account.id},{action:'budget'}]){clock+=60000;assert([400,409].includes((await controls('/apply',{...body,...patch})).status));}
 assert.equal((await controls('/apply',body)).status,409);clock-=300000;observedStatus='ENABLED';assert.equal((await controls('/apply',body)).status,409);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
 assert.equal((await controls('/inspect',{campaign_id:c.id})).status,400);assert.equal((await controls('?configured=true')).status,400);
});
test('K182 provider drift blocks activation but preserves pause when enabled',async()=>{
 await created();inspectionHook=async()=>{throw Error('changed budget or copy');};let d=await inspect();assert.equal(d.observation.can_activate,false);assert.equal(d.observation.proof,null);
 observedStatus='ENABLED';d=await inspect();assert.equal(d.observation.can_pause,true);assert.equal((await controls('/apply',controlInput(d,'pause'))).status,200);assert.equal(controlCalls,1);
});
test('K182 stale reviews, archived plan, and paused landing page block activation but allow pause',async()=>{
 await created();let cr=await creative();await creative('save',{version:cr.version,fingerprint:cr.fingerprint,assets:{...cr.assets,path1:'new'}});c=await campaign('archive',{confirmed:true});f=await funnel('pause',{version:f.version});let d=await record();assert.equal(d.activation_ready,false);
 observedStatus='ENABLED';d=await inspect();assert.equal(d.observation.can_pause,true);assert.equal((await controls('/apply',controlInput(d,'pause'))).status,200);
});
test('K182 local content or account edits during provider validation invalidate the SQL claim',async()=>{
 await created();let d=await inspect();controlValidateHook=async()=>{await db.query('update korlix_google_ads_connections set version=version+1 where user_id=$1',[owner]);return {validated:true};};assert.equal((await controls('/apply',controlInput(d))).status,409);assert.equal(controlCalls,0);
});
test('K182 late entitlement loss still records accepted receipt but returns access denial',async()=>{
 await created();const d=await inspect();controlHook=async action=>{await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return {confirmed:true,action};};assert.equal((await controls('/apply',controlInput(d))).status,403);assert.equal((await commands())[0].state,'confirmed');assert.equal(controlCalls,1);
});
test('K182 disabled controls gate and unsupported API version never call Google',async()=>{
 await created();for(const patch of [{KORLIX_GOOGLE_ADS_CONTROLS_ENABLED:undefined},{KORLIX_GOOGLE_ADS_API_VERSION:'v26'}]){
  const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,...patch},googleAdsProvider:provider});const server=app.listen(0);await new Promise(r=>server.once('listening',r));
  try{const url=`http://127.0.0.1:${server.address().port}/api/funnels/${f.id}/campaigns/${c.id}/google-controls`;const d=await(await fetch(url)).json();assert.equal(d.checks.platform_enabled,false);assert.equal((await fetch(url+'/inspect',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,409);assert.equal(providerCalls,0);}finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
 }
});
test('K182 provider state changed during validation blocks dispatch on the final read',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{observedStatus='ENABLED';return {validated:true};};assert.equal((await controls('/apply',controlInput(d))).status,409);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
});
test('K182 local content changes during validation fail the coherent SQL claim',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{const cr=await creative();await creative('save',{version:cr.version,fingerprint:cr.fingerprint,assets:{...cr.assets,path1:'changed'}});return {validated:true};};assert.equal((await controls('/apply',controlInput(d))).status,409);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
});
test('K182 revoked Google access marks reconnection and does not claim a command',async()=>{
 await created();inspectionHook=async()=>{throw new GoogleAdsAccessError();};assert.equal((await controls('/inspect',{})).status,409);assert.equal((await db.query('select needs_reconnect from korlix_google_ads_connections where user_id=$1',[owner])).rows[0].needs_reconnect,true);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
});
test('K182 slow preflight cannot start a delayed mutation after the client timeout window',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{clock+=76000;return {validated:true};};assert.equal((await controls('/apply',controlInput(d))).status,409);assert.equal(controlCalls,0);assert.deepEqual(await commands(),[]);
});

const proposal=async(cents=3000)=>{const r=await controls('/budget-preview',{daily_cents:cents});assert.equal(r.status,200,await r.clone().text());return r.json();};
const budgetInput=d=>({proof:d.budget_preview.proof,daily_cents:d.budget_preview.daily_cents,confirmed:true,spend_acknowledged:true});
test('K183 budget receipts change the effective provider amount without changing creation or plan history',async()=>{
 await created();const old=await ledger(),beforePlan=(await db.query('select * from korlix_funnel_campaigns')).rows;
 let d=await record();assert.equal(d.managed_budget.daily_cents,2500);assert.equal(budgetCalls,0);
 d=await proposal();assert.equal(d.budget_preview.increase,true);assert.equal(d.budget_preview.graph.policy,'APPROVED');let r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200,await r.clone().text());d=await r.json();assert.equal(d.latest_command.state,'confirmed');assert.equal(d.latest_command.daily_cents,3000);assert.equal(d.managed_budget.daily_cents,3000);assert.equal(d.managed_budget.original_daily_cents,2500);assert.equal(d.managed_budget.command_id,d.latest_command.id);
 assert.deepEqual(await ledger(),old);assert.deepEqual((await db.query('select * from korlix_funnel_campaigns')).rows,beforePlan);
 d=await proposal(1500);assert.equal(d.budget_preview.increase,false);assert.equal(d.budget_preview.graph,null);r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200);assert.equal((await r.json()).managed_budget.daily_cents,1500);assert.equal(budgetCalls,2);
 inspectionHook=async()=>({resources,statuses:{campaign:'PAUSED',ad_group:'PAUSED',ad:'PAUSED'},policy:'APPROVED'});
 assert.equal((await inspect()).observation.can_activate,true);assert.deepEqual((await commands()).map(x=>x.sequence),[1,2]);
});
test('K183 simultaneous status and budget confirmations share one dispatch slot',async()=>{
 await created();const status=await inspect(),budget=await proposal();const rs=await Promise.all([controls('/apply',controlInput(status)),controls('/budget-apply',budgetInput(budget))]);assert.deepEqual(rs.map(x=>x.status).sort(),[200,409]);assert.equal(controlCalls+budgetCalls,1);assert.equal((await commands()).length,1);
});
test('K183 replayed or altered budget proposals cannot dispatch',async()=>{
 await created();const d=await proposal(),input=budgetInput(d);
 for(const patch of [{daily_cents:3001},{confirmed:false},{spend_acknowledged:false},{budget_id:resources.budget}]){assert([400,409].includes((await controls('/budget-apply',{...input,...patch})).status));}
 clock+=60000;assert.equal((await controls('/budget-apply',input)).status,200);assert.equal((await controls('/budget-apply',input)).status,409);assert.equal(budgetCalls,1);
});
test('K183 uncertain budget outcome blocks status and budget commands and retains prior effective amount',async()=>{
 await created();const status=await inspect(),d=await proposal();budgetHook=async cents=>{effectiveCents=cents;throw Error('hidden');};const r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200);const out=await r.json();assert.equal(out.latest_command.state,'unknown');assert.equal(out.managed_budget.daily_cents,2500);assert.match(out.notice,/uncertain/);assert.equal((await controls('/apply',controlInput(status))).status,409);assert.equal((await controls('/budget-preview',{daily_cents:2000})).status,409);assert.equal(budgetCalls,1);assert.equal(controlCalls,0);
});
test('K183 reductions can proceed with stale reviews while increases cannot',async()=>{
 await created();c=await campaign('archive',{confirmed:true});observedStatus='ENABLED';assert.equal((await controls('/budget-preview',{daily_cents:3000})).status,409);
 inspectionHook=async()=>{throw Error('not needed for reduction');};const d=await proposal(1000);assert.equal(d.activation_ready,false);assert.equal(d.budget_preview.status.status,'ENABLED');assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.equal(observedStatus,'ENABLED');assert.equal(budgetCalls,1);
});
test('K183 provider or local drift after validation prevents claim and leaves no journal entry',async()=>{
 await created();let d=await proposal();budgetValidateHook=async()=>{effectiveCents=2600;return {validated:true};};assert.equal((await controls('/budget-apply',budgetInput(d))).status,503);assert.equal(budgetCalls,0);assert.deepEqual(await commands(),[]);
 effectiveCents=2500;budgetValidateHook=async()=>{await db.query('update korlix_google_ads_connections set version=version+1 where user_id=$1',[owner]);return {validated:true};};d=await proposal();assert.equal((await controls('/budget-apply',budgetInput(d))).status,409);assert.equal(budgetCalls,0);
});
test('K183 malformed budgets, cross-purpose proofs, removed campaigns and unapproved increases fail closed',async()=>{
 await created();for(const cents of [null,'3000',99,1000001,100.5])assert.equal((await controls('/budget-preview',{daily_cents:cents})).status,400);
 const status=await inspect();assert.equal((await controls('/budget-apply',{proof:status.observation.proof,daily_cents:3000,confirmed:true,spend_acknowledged:true})).status,409);
 observedStatus='REMOVED';assert.equal((await controls('/budget-preview',{daily_cents:2000})).status,409);observedStatus='PAUSED';inspectionHook=async()=>({resources,statuses:{campaign:'PAUSED',ad_group:'PAUSED',ad:'PAUSED'},policy:'DISAPPROVED'});assert.equal((await controls('/budget-preview',{daily_cents:3000})).status,409);assert.equal(budgetCalls,0);
});
test('K183 failed budget receipt persistence retains unknown and the prior effective amount',async()=>{
 await created();let d=await proposal(),original=database.rpc;database.rpc=async(name,p)=>name==='korlix_funnel_google_controls_v1'&&p.p_action==='finish'?{error:{code:'XX000'}}:original(name,p);
 try{const r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200);assert.equal((await r.json()).latest_command.state,'unknown');}finally{database.rpc=original;}
 assert.equal(budgetCalls,1);assert.equal((await record()).managed_budget.daily_cents,2500);
});
test('K183 actual SQL budget bounds and spending/current-review requirements are enforced',async()=>{
 await created();const d=await proposal();const claim=(patch={})=>rpc('korlix_funnel_google_controls_v1',{p_actor:owner,p_action:'claim',p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',create_enabled:true,controls_enabled:true,budget_enabled:true,fingerprint:d.fingerprint,action:'budget',daily_cents:3000,confirmed:true,spend_acknowledged:true,command_id:randomUUID(),observed:d.budget_preview,...patch}});
 for(const patch of [{daily_cents:99},{daily_cents:1000001},{daily_cents:2500},{daily_cents:null},{daily_cents:'3000'},{spend_acknowledged:false},{observed:{kind:'budget',daily_cents:3001,budget:{daily_cents:2500}}}])await assert.rejects(claim(patch));
 assert.deepEqual(await commands(),[]);await assert.rejects(db.query("insert into korlix_funnel_google_commands(id,campaign_id,user_id,sequence,action,fingerprint,observed,daily_cents) values($1,$2,$3,1,'budget',$4,'{}',null)",[randomUUID(),c.id,owner,d.fingerprint]),/check constraint/);
});
test('K183 default-off budget gate never contacts Google and preserves status controls',async()=>{
 await created();const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,KORLIX_GOOGLE_ADS_BUDGET_ENABLED:undefined},googleAdsProvider:provider,now:()=>clock});const srv=app.listen(0);await new Promise(r=>srv.once('listening',r));
 try{const url=`http://127.0.0.1:${srv.address().port}/api/funnels/${f.id}/campaigns/${c.id}/google-controls`;let r=await fetch(url);let d=await r.json();assert.equal(d.budget_enabled,false);assert.equal(d.checks.platform_enabled,true);r=await fetch(url+'/budget-preview',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({daily_cents:3000})});assert.equal(r.status,409);assert.equal(providerCalls,0);}finally{srv.closeAllConnections();await new Promise(r=>srv.close(r));}
});
