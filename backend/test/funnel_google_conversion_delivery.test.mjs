import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
import {googleUploadConfiguration,googleUploadScopes,createGoogleUploadProvider} from '../funnels/google_upload_provider.mjs';
import {googleChallenge} from '../funnels/google_ads_provider.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),root='9999999999';
const env={KORLIX_GOOGLE_DELIVERY_ENABLED:'true',KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED:'true',KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:'https://example.com/api/funnels/google-upload-access/callback',KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_CLIENT_ID:'fixture-google-client.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-google-secret',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'};
const config=googleAdsConfiguration(env),uploadConfig=googleUploadConfiguration(env),account={id:'1234567890',name:'Advertiser',currency:'USD',timezone:'UTC',status:'ENABLED',manager:false,test_account:false};
const destination={conversion_customer_id:'8888888888',conversion_action_id:'9223372036854775807',resource_name:'customers/8888888888/conversionActions/9223372036854775807',name:'Inquiry submitted',status:'ENABLED',type:'UPLOAD_CLICKS',category:'SUBMIT_LEAD_FORM',counting_type:'ONE_PER_CLICK',primary_for_goal:false,click_window_days:30,attribution_model:'GOOGLE_ADS_LAST_CLICK',default_value:0,default_currency:'USD',always_use_default_value:false};
const doc={brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const plan={name:'Growth plan',platform:'google',headline:'Explore',body:'Talk to us',cta:'Learn more',audience:'Businesses',daily_cents:2500,days:14};
let sends=[],sendHook=null,statusHook=null,statusValue={state:'succeeded',errors:[],warnings:[]};
const deliveryProvider={ingest:async(token,body)=>{sends.push({token,body});if(sendHook)await sendHook();return {request_id:'provider-request',has_warnings:false};},status:async()=>{if(statusHook)await statusHook();return structuredClone(statusValue);}};
let db,server,base,handler,f,c,clock=Date.now(),providerCalls=0,hook=null,provided=[destination],rootAccess=[root],liveAccount=account,oauthCalls=[],exchangeHook=null,refreshHook=null,grantedScopes=[...googleUploadScopes];
const rpc=async(name,p)=>(await db.query(name==='korlix_google_ads_v1'?`select public.${name}($1,$2,$3) r`:`select public.${name}($1,$2,$3,$4) r`,name==='korlix_google_ads_v1'?[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={},id=f?.id)=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const ctx=()=>({campaign_id:c.id,configured:true,config_hash:config.hash});
const link=(action='read',data={})=>rpc('korlix_funnel_google_campaign_link_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{...ctx(),...data}});
const direct=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_destination_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{...ctx(),...data}});
const request=(suffix='',body=null,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/google-upload-access${suffix}`,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const read=async()=>{const r=await request();assert.equal(r.status,200,await r.clone().text());return r.json();};
const ledger=async()=>(await db.query('select * from korlix_google_upload_connections')).rows;
async function linked(){const l=await link();return link('save',{version:l.version,fingerprint:l.fingerprint,confirmed:true,provider_campaign_id:'456',provider_campaign_name:'Campaign'});}
const uploadProvider={authorizationUrl:(...args)=>createGoogleUploadProvider(uploadConfig).authorizationUrl(...args),exchange:async(code,verifier)=>{oauthCalls.push(['exchange',code,verifier]);if(exchangeHook)await exchangeHook();return {refresh_token:'private-upload-refresh',refresh_expires_at:null,scopes:grantedScopes};},refresh:async(value)=>{oauthCalls.push(['refresh',value]);if(refreshHook)await refreshHook();return 'private-upload-access';}};
const provider={refresh:async()=>{providerCalls++;return 'access-fixture';},roots:async()=>rootAccess,account:async()=>liveAccount,conversionDestinations:async()=>{providerCalls++;if(hook)await hook();return structuredClone(provided);}};
test.before(async()=>{
 db=new PGlite();await db.exec("create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;");
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 await db.exec('alter default privileges in schema public grant all on tables to anon,authenticated,service_role');
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922090333_funnel_campaign_workspace.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql','20260924015359_funnel_campaign_attribution_grants.sql','20260924020959_funnel_conversion_intake.sql','20260922233935_funnel_google_ads_connection.sql','20260923203416_funnel_google_campaign_link.sql','20260924071214_funnel_google_conversion_destination.sql','20260924090911_google_upload_authorization.sql','20260924213815_funnel_google_conversion_delivery.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:provider,googleUploadProvider:uploadProvider,googleDeliveryProvider:deliveryProvider});server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
 handler.close();clock=Date.now();await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);const binding=randomUUID();
 await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,roots,root_id,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,$6,$6,$7,$8,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([root]),root,JSON.stringify([account]),account.id]);await linked();const d=await direct();await direct('save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});sends=[];sendHook=null;statusHook=null;statusValue={state:'succeeded',errors:[],warnings:[]};providerCalls=0;hook=null;provided=[destination];rootAccess=[root];liveAccount=account;oauthCalls=[];exchangeHook=null;refreshHook=null;grantedScopes=[...googleUploadScopes];
});
test.after(async()=>{handler?.close();server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
const uctx=()=>({campaign_id:c.id,ads_configured:true,ads_config_hash:config.hash,configured:true,config_hash:uploadConfig.hash});
const upload=(action='read',data={},actor=owner)=>rpc('korlix_google_upload_access_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{...uctx(),...data}});
const confirmation=d=>({version:d.version,fingerprint:d.fingerprint,confirmed:true});
async function begin(){const d=await read(),r=await request('/begin',confirmation(d));assert.equal(r.status,200,await r.clone().text());return r.json();}
const callback=(a,extra='')=>fetch(base+'/api/funnels/google-upload-access/callback?state='+encodeURIComponent(new URL(a.authorization_url).searchParams.get('state'))+'&code=private-code'+extra);
const finish=a=>request('/finish',{id:a.id,proof:a.proof,confirmed:true});
async function grant(){const a=await begin();assert.equal((await callback(a)).status,200);const r=await finish(a);assert.equal(r.status,200,await r.clone().text());return r.json();}
async function nextAttempt(){await db.exec("update korlix_google_upload_oauth_attempts set created_at=now()-interval '1 minute'");handler.close();}

const delivery=(action='read',data={},actor=owner)=>rpc('korlix_google_delivery_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{...uctx(),delivery_configured:true,...data}});
const api=(suffix='',body=null,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/google-delivery${suffix}`,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const state=async()=>{const r=await api();assert.equal(r.status,200,await r.clone().text());return r.json();};
const measure=(action,data={},actor=owner)=>rpc('korlix_funnel_measurement_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,days:30,...data}});
let code;
async function setup(){
 await grant();const a=await rpc('korlix_funnel_attribution_v1',{p_actor:owner,p_action:'create_link',p_funnel:f.id,p_data:{campaign_id:c.id,days:30}});code=a.link.code;
 await measure('settings',{enabled:true,expected_revision:null});
}
async function arm(enabled=true){const d=await state(),r=await api('/settings',{enabled,fingerprint:d.fingerprint,confirmed:true});assert.equal(r.status,200,await r.clone().text());return r.json();}
async function receipt(choice='granted',kind='gclid'){
 const m=await measure('read'),request_id=randomUUID();
 await measure('capture',{slug:f.slug,code,published_version:f.published_version,request_id,name:'Visitor',email:randomUUID()+'@example.com',message:'Question',utm:{},settings_revision:m.revision,platform:'google',policy_version:'measurement_v1',measurement_consent:choice,...(kind?{click_type:kind,click_id:'private_click_123',observed_at:new Date().toISOString()}: {})},null);
 clock=Date.now();return (await db.query('select r.* from korlix_funnel_measurement_receipts r join korlix_funnel_leads l on l.id=r.lead_id where l.request_id=$1',[request_id])).rows[0];
}
async function send(event_id){const d=await state();return api('/send',{event_id,fingerprint:d.fingerprint,confirmed:true});}
const attempts=async()=>(await db.query('select * from korlix_google_delivery_attempts')).rows;
async function cooldown(){await db.exec("update korlix_google_delivery_attempts set poll_after=now()-interval '1 second'");handler.close();}

test('K192 defaults and service-only SQL enforce ownership, consent and no historical uploads',async()=>{
 let d=await state();assert.equal(d.enabled,false);assert.equal(d.current,false);assert.equal(d.can_enable,false);assert.deepEqual(d.rows,[]);assert.equal(sends.length,0);
 for(const [actor,status]of [['',401],[other,404],[basic,403]])assert.equal((await api('',null,actor)).status,status);
 for(const role of ['anon','authenticated']){
  await db.exec('reset role;set role '+role);for(const table of ['korlix_google_delivery_settings','korlix_google_delivery_attempts','korlix_google_delivery_observations'])await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(delivery(),/permission denied/);
  await db.exec('reset role;set role service_role');
 }
 await setup();const old=await receipt();await arm();assert.deepEqual((await state()).rows,[]);assert.equal((await send(old.event_id)).status,409);
 await receipt('declined');await receipt('granted',null);assert.deepEqual((await state()).rows,[]);
 const r=await receipt();d=await state();assert.equal(d.rows.length,1);assert.equal(d.rows[0].state,'ready');assert.equal(d.provider_verified,false);
 assert(!JSON.stringify(d).includes('private_click'));assert.equal((await api('/send',{event_id:r.event_id,fingerprint:d.fingerprint,confirmed:false})).status,400);
 assert.equal((await api('/send',{event_id:r.event_id,fingerprint:d.fingerprint,confirmed:true,click_id:'forged'})).status,400);
});
test('K192 single dispatch records stable identity and request hash before write, then checks actual processing',async()=>{
 await setup();await arm();const r=await receipt();sendHook=async()=>{const a=(await attempts())[0];assert.equal(a.state,'uncertain');assert.equal(a.request_id,null);assert.match(a.request_hash,/^[a-f0-9]{64}$/);};
 const result=await send(r.event_id);assert.equal(result.status,200,await result.clone().text());let d=await result.json();assert.equal(d.rows[0].state,'submitted');assert.equal(d.rows[0].checked_at,null);assert.equal(sends.length,1);
 const body=sends[0].body;assert.equal(body.events[0].transactionId,r.event_id);assert.equal(body.events[0].adIdentifiers.gclid,'private_click_123');assert.equal(body.events[0].consent.adPersonalization,'CONSENT_DENIED');assert.equal(body.destinations[0].operatingAccount.accountId,destination.conversion_customer_id);assert.equal(body.destinations[0].loginAccount.accountId,root);
 assert(!JSON.stringify(body).includes('Visitor'));for(const key of ['request_id','sealed','binding_id','request_hash','click_id'])assert(!JSON.stringify(d).includes('"'+key+'"'));
 assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,1);
 const p=await api('/check',{event_id:r.event_id});assert.equal(p.status,200,await p.clone().text());d=await p.json();assert.equal(d.rows[0].state,'succeeded');assert.equal(d.rows[0].can_check,false);assert.equal(d.provider_verified,false);assert(d.rows[0].checked_at);
 const log=(await db.query('select state from korlix_google_delivery_observations order by recorded_at')).rows.map(x=>x.state);assert.deepEqual(log,['checking','uncertain','submitted','succeeded']);
});
test('K192 concurrency and lost provider responses cannot duplicate delivery',async()=>{
 await setup();await arm();const r=await receipt(),d=await state(),b={event_id:r.event_id,fingerprint:d.fingerprint,confirmed:true};sendHook=()=>{throw Error('private transport data');};
 const rs=await Promise.all([api('/send',b),api('/send',b)]);assert.deepEqual(rs.map(x=>x.status).sort(),[409,503]);assert.equal(sends.length,1);assert.equal((await state()).rows[0].state,'uncertain');
 assert.equal((await send(r.event_id)).status,409);assert.equal((await api('/check',{event_id:r.event_id})).status,409);assert.equal(sends.length,1);
});
test('K192 context changes, deletion and entitlement loss during preflight prevent the write',async()=>{
 for(const change of ['destination','disable','receipt','tier','access','account']){
  await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);handler.close();await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections');
  f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);const binding=randomUUID();
  await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,roots,root_id,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,$6,$6,$7,$8,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([root]),root,JSON.stringify([account]),account.id]);
  await linked();let d=await direct();await direct('save',{...confirmation(d),destination,checked_at:new Date().toISOString()});hook=null;await setup();await arm();const r=await receipt();
  hook=async()=>{
   if(change==='destination'){d=await direct();await direct('clear',confirmation(d));}
   if(change==='disable')await arm(false);
   if(change==='receipt')await db.query('delete from korlix_funnel_leads where id=$1',[r.lead_id]);
   if(change==='tier')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
   if(change==='access')await db.query('delete from korlix_google_upload_connections');
   if(change==='account')await db.query('update korlix_google_ads_connections set version=version+1');
  };
  const response=await send(r.event_id);assert([403,404,409].includes(response.status),change+': '+await response.text());assert.equal(sends.length,0);hook=null;
 }
});
test('K192 disabled settings, renewed consent or destination context exclude old pending inquiries',async()=>{
 await setup();await arm();const old=await receipt();await arm(false);assert.equal((await send(old.event_id)).status,409);await arm();assert.deepEqual((await state()).rows,[]);assert.equal((await send(old.event_id)).status,409);
 const pending=await receipt();await measure('settings',{enabled:false,expected_revision:(await measure('read')).revision});assert.equal((await state()).current,false);assert.equal((await send(pending.event_id)).status,409);
});
test('K192 braid counting restrictions, age and changed provider metadata block dispatch',async()=>{
 await setup();await arm();const braid=await receipt('granted','wbraid');assert.equal((await state()).rows[0].state,'ineligible');assert.equal((await send(braid.event_id)).status,409);
 const r=await receipt();provided=[{...destination,default_value:12}];assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,0);assert.equal((await attempts())[0].state,'blocked');
});
test('K192 status polling is bounded, append-only and never repeats ingestion',async()=>{
 await setup();await arm();const r=await receipt();assert.equal((await send(r.event_id)).status,200);statusValue={state:'processing',errors:[],warnings:[]};let p=await api('/check',{event_id:r.event_id});assert.equal(p.status,200);assert.equal((await p.json()).rows[0].state,'processing');assert.equal((await api('/check',{event_id:r.event_id})).status,429);
 await cooldown();statusValue={state:'rejected',errors:[{reason:'PROCESSING_ERROR_REASON_INVALID_GCLID',count:1}],warnings:[]};p=await api('/check',{event_id:r.event_id});assert.equal(p.status,200,await p.clone().text());assert.equal((await p.json()).rows[0].state,'rejected');assert.equal(sends.length,1);
 await assert.rejects(db.query("update korlix_google_delivery_observations set state='succeeded'"),/permission denied/);await assert.rejects(db.query("update korlix_google_delivery_attempts set context_hash=repeat('a',64)"),/permission denied/);
 await db.query('delete from korlix_funnel_leads where id=$1',[r.lead_id]);assert.deepEqual(await attempts(),[]);assert.equal((await db.query('select count(*)::int n from korlix_google_delivery_observations')).rows[0].n,0);
});
test('K192 stale settings and internal-only fields cannot be supplied through HTTP',async()=>{
 await setup();const d=await state();await arm();assert.equal((await api('/settings',{enabled:false,fingerprint:d.fingerprint,confirmed:true})).status,409);
 for(const suffix of ['/dispatch','/claim','/received','/poll','/status'])assert.equal((await api(suffix,{id:randomUUID()})).status,404);
 assert.equal((await api('?extra=1')).status,400);assert.equal(sends.length,0);
});

test('K192 platform-off routes permit local reads and stop but never retrieve credentials or upload',async()=>{
 await setup();await arm();const r=await receipt();
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());const off=registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,KORLIX_GOOGLE_DELIVERY_ENABLED:'false'},googleAdsProvider:provider,googleUploadProvider:uploadProvider,googleDeliveryProvider:deliveryProvider});
 const srv=app.listen(0);await new Promise(resolve=>srv.once('listening',resolve));const url='http://127.0.0.1:'+srv.address().port+'/api/funnels/'+f.id+'/campaigns/'+c.id+'/google-delivery';
 try{
  const d=await(await fetch(url)).json();assert.equal(d.configured,false);assert.equal(d.current,false);
  for(const [suffix,body]of [['send',{event_id:r.event_id,fingerprint:d.fingerprint,confirmed:true}],['check',{event_id:r.event_id}],['settings',{enabled:true,fingerprint:d.fingerprint,confirmed:true}]])assert.equal((await fetch(url+'/'+suffix,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})).status,503);
  assert.equal((await fetch(url+'/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:false,fingerprint:d.fingerprint,confirmed:true})})).status,200);assert.equal(sends.length,0);assert.deepEqual(await attempts(),[]);
 }finally{off.close();srv.closeAllConnections();await new Promise(resolve=>srv.close(resolve));}
});
