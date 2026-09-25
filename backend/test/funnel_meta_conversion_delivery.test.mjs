import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {createMetaWebsiteConsent} from '../funnels/meta_website_consent.mjs';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher,MetaAccessError} from '../funnels/meta.mjs';
import {metaDestinationProof,metaDestinationProofValid} from '../funnels/meta_conversion_destination.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_ENABLED:'true',KORLIX_META_CONVERSION_SETUP_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-conversion-secret',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback'};
env.KORLIX_META_DELIVERY_ENABLED='true';env.KORLIX_META_CONTEXT_ENABLED='true';env.KORLIX_FUNNEL_PUBLIC_BASE_URL='https://example.com';
const config=metaConfiguration(env),account={id:'act_123',name:'Advertiser',currency:'USD',timezone:'UTC',status:1};
const destination={pixel_id:'987654321',name:'Website inquiries'};
const doc={brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const plan={name:'Growth plan',platform:'meta',headline:'Explore',body:'Talk to us',cta:'Learn more',audience:'Businesses',daily_cents:2500,days:14};
let db,server,base,handler,f,c,clock=Date.now(),providerCalls=0,hook=null,provided=[destination];
const rpc=async(name,p)=>(await db.query(name==='korlix_meta_v1'?`select public.${name}($1,$2,$3) r`:`select public.${name}($1,$2,$3,$4) r`,name==='korlix_meta_v1'?[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={},id=f?.id)=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const ctx=()=>({campaign_id:c.id,configured:true,config_hash:config.hash});
const link=(action='read',data={})=>rpc('korlix_funnel_meta_campaign_link_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{...ctx(),...data}});
const direct=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_destination_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{...ctx(),...data}});
const request=(suffix='',body=null,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/meta-conversion-destination${suffix}`,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const read=async()=>{const r=await request();assert.equal(r.status,200,await r.clone().text());return r.json();};
const ledger=async()=>(await db.query('select * from korlix_funnel_meta_conversion_destinations')).rows;
async function linked(){const l=await link();return link('save',{version:l.version,fingerprint:l.fingerprint,confirmed:true,provider_campaign_id:'456',provider_campaign_name:'Campaign'});}
async function choices(){const d=await read(),r=await request('/choices?fingerprint='+d.fingerprint);assert.equal(r.status,200,await r.clone().text());return {d,list:await r.json()};}
const input=(d,choice)=>({version:d.version,fingerprint:d.fingerprint,confirmed:true,...choice});
async function save(){const {d,list}=await choices();return request('/save',input(d,list.choices[0]));}
const provider={account:async()=>{providerCalls++;return account;},conversionDestinations:async()=>{providerCalls++;if(hook)await hook();return structuredClone(provided);}};
test.before(async()=>{
 db=new PGlite();await db.exec("create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;");
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 await db.exec('alter default privileges in schema public grant all on tables to anon,authenticated,service_role');
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923194721_funnel_meta_campaign_link.sql','20260924222246_funnel_meta_conversion_destination.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql','20260924015359_funnel_campaign_attribution_grants.sql','20260924020959_funnel_conversion_intake.sql','20260924224119_meta_website_measurement_consent.sql','20260925002037_funnel_meta_conversion_delivery.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{const data=await rpc(name,p);if(lost===p.p_action&&name==='korlix_meta_delivery_v1'){lost=null;return{error:{code:'XX000'}};}return{data};}catch(error){return{error}}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,metaProvider:provider,metaDeliveryProvider:deliveryProvider});server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
 handler.close();clock=Date.now();await db.exec('delete from korlix_funnels;delete from korlix_meta_connections');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);const binding=randomUUID();
 await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id]);await linked();providerCalls=0;hook=null;provided=[destination];sends=[];sendHook=null;authHook=null;system='777777';lost=null;
});
test.after(async()=>{await writeFile('/tmp/k195-expected-functions.json',JSON.stringify((await db.query("select proname,md5(prosrc) hash from pg_proc where proname='korlix_meta_delivery_v1' order by proname")).rows));handler.close();server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

let sends=[],sendHook=null,authHook=null,system='777777',lost=null;
const deliveryProvider={authorize:async(t,d)=>{if(authHook)await authHook();return {system_user_id:system,expires_at:null};},send:async(token,destination,body)=>{sends.push({token,destination,body});if(sendHook)await sendHook();return {trace_id:'MetaTraceFixture',has_warnings:false};}};
const mc=createMetaWebsiteConsent(null,'https://example.com',true).config;
const dctx=()=>({...ctx(),measurement_configured:mc.configured,measurement_config_hash:mc.config_hash,public_origin:mc.public_origin,delivery_configured:true});
const delivery=(action='read',data={},actor=owner)=>rpc('korlix_meta_delivery_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{...dctx(),...data}});
const api=(suffix='',body=null,actor=owner)=>fetch(base+'/api/funnels/'+f.id+'/campaigns/'+c.id+'/meta-delivery'+suffix,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const state=async()=>{const r=await api();assert.equal(r.status,200,await r.clone().text());return r.json();};
const measure=(action,data={},actor=owner)=>rpc('korlix_meta_measurement_v2',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,days:30,...mc,...data}});
const confirm=d=>({fingerprint:d.fingerprint,confirmed:true});
async function authorize(){const d=await state(),r=await api('/authorize',{...confirm(d),access_token:'private-system-user-token-fixture'});assert.equal(r.status,200,await r.clone().text());return r.json();}
async function setup(){
 const d=await direct();await direct('save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});
 code=(await rpc('korlix_funnel_attribution_v1',{p_actor:owner,p_action:'create_link',p_funnel:f.id,p_data:{campaign_id:c.id,days:30}})).link.code;
 await measure('settings',{enabled:true,expected_revision:null,confirmed:true});await authorize();
}
async function arm(enabled=true){const d=await state(),r=await api('/settings',{...confirm(d),enabled});assert.equal(r.status,200,await r.clone().text());return r.json();}
let code;
async function receipt(choice='granted',browser=true){
 const m=await measure('read'),request_id=randomUUID();
 await measure('capture',{slug:f.slug,code,published_version:f.published_version,request_id,name:'Visitor',email:randomUUID()+'@example.com',message:'Private message',utm:{},settings_revision:m.revision,policy_version:'meta_measurement_v2',measurement_consent:choice,observed_at:new Date().toISOString(),click_id:'private_fbclid',...(browser?{client_user_agent:'Fixture browser',event_source_url:'https://example.com/f/'+f.slug}:{})},null);
 clock=Date.now();return (await db.query('select r.* from korlix_meta_measurement_receipts r join korlix_funnel_leads l on l.id=r.lead_id where l.request_id=$1',[request_id])).rows[0];
}
async function send(event_id){const d=await state();return api('/send',{...confirm(d),event_id});}
const attempts=async()=>(await db.query('select * from korlix_meta_delivery_attempts')).rows;

test('K195 default local read, strict inputs and service-only ownership boundaries',async()=>{
 const d=await state();assert.equal(d.enabled,false);assert.equal(d.authorization.connected,false);assert.equal(d.provider_verified,false);assert.deepEqual(d.rows,[]);assert.equal(providerCalls,0);
 for(const [actor,status] of [['',401],[other,404],[basic,403]])assert.equal((await api('',null,actor)).status,status);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);for(const t of ['connections','settings','attempts','observations'])await assert.rejects(db.query('select * from korlix_meta_delivery_'+t),/permission denied/);await assert.rejects(delivery(),/permission denied/);await db.exec('reset role;set role service_role');}
 assert.equal((await api('?extra=1')).status,400);
 assert.equal((await api('/authorize',{...confirm(d),access_token:'x',sealed:{}})).status,400);
 for(const suffix of ['/claim','/dispatch','/received','/credentials'])assert.equal((await api(suffix,{confirmed:true})).status,404);
});
test('K195 separate system-user authorization seals credentials and requires explicit confirmation',async()=>{
 await setup();const d=await state();assert.equal(d.authorization.current,true);assert.equal(d.can_enable,true);assert.equal(d.enabled,false);assert.equal(sends.length,0);
 const row=(await db.query('select * from korlix_meta_delivery_connections')).rows[0];
 assert(!JSON.stringify(row).includes('private-system'));assert(!JSON.stringify(d).includes('sealed'));
 assert.equal(tokenCipher(config.key).open(row.sealed,'korlix-meta-delivery:'+owner+':'+c.id+':'+row.binding_id),'private-system-user-token-fixture');
 assert.throws(()=>tokenCipher(config.key).open(row.sealed,'korlix-meta:'+owner+':'+row.binding_id));
 assert.equal((await api('/authorize',{fingerprint:d.fingerprint,confirmed:false,access_token:'private-system-user-token-fixture'})).status,400);
 const r=await api('/disconnect',confirm(d));assert.equal(r.status,200);assert.equal((await r.json()).authorization.connected,false);
 assert.equal((await db.query('select count(*)::int n from korlix_meta_delivery_connections')).rows[0].n,0);
});
test('K195 future-only consent window excludes history, declined and incomplete receipts',async()=>{
 await setup();const old=await receipt();await arm();assert.deepEqual((await state()).rows,[]);assert.equal((await send(old.event_id)).status,409);
 await receipt('declined');await receipt('granted',false);assert.deepEqual((await state()).rows,[]);
 const r=await receipt(),d=await state();assert.equal(d.rows[0].state,'ready');assert(!JSON.stringify(d).includes('private_fbclid'));assert(!JSON.stringify(d).includes('Fixture browser'));
 assert.equal((await api('/send',{...confirm(d),event_id:r.event_id,client_user_agent:'forged'})).status,400);
});
test('K195 stable identity is committed before one write and receipt acceptance stays distinct from attribution',async()=>{
 await setup();await arm();const r=await receipt();
 sendHook=async()=>{const a=(await attempts())[0];assert.equal(a.state,'uncertain');assert.equal(a.trace_id,null);assert.match(a.request_hash,/^[a-f0-9]{64}$/);};
 const result=await send(r.event_id);assert.equal(result.status,200,await result.clone().text());const d=await result.json();assert.equal(d.rows[0].state,'received');assert(d.rows[0].received_at);assert.equal(d.provider_verified,false);assert.equal(sends.length,1);
 const sent=sends[0];assert.equal(sent.token,'private-system-user-token-fixture');assert.deepEqual(sent.destination,destination);assert.equal(sent.body.data[0].event_id,r.event_id);assert.equal(sent.body.data[0].event_time,Math.floor(Date.parse(r.captured_at)/1000));assert.equal(sent.body.data[0].user_data.fbc,'fb.1.'+new Date(r.observed_at).getTime()+'.private_fbclid');
 for(const v of ['private-fixture-token','Visitor','Private message','client_ip_address','test_event_code'])assert(!JSON.stringify(sent).includes(v));
 assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,1);
 assert.deepEqual((await db.query('select state from korlix_meta_delivery_observations order by recorded_at')).rows.map(x=>x.state),['checking','uncertain','received']);
});
test('K195 concurrent clicks and lost provider response never duplicate an event',async()=>{
 await setup();await arm();const r=await receipt(),b={...confirm(await state()),event_id:r.event_id};
 sendHook=()=>{throw Error('private provider details');};const rs=await Promise.all([api('/send',b),api('/send',b)]);assert.deepEqual(rs.map(x=>x.status).sort(),[409,503]);assert.equal(sends.length,1);
 assert.equal((await state()).rows[0].state,'uncertain');assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,1);
});
test('K195 lost committed dispatch response does not perform the HTTP write or permit retry',async()=>{
 await setup();await arm();const r=await receipt();lost='dispatch';assert.equal((await send(r.event_id)).status,503);assert.equal(sends.length,0);
 assert.equal((await state()).rows[0].state,'uncertain');assert.equal((await send(r.event_id)).status,409);
});
test('K195 lost final storage response preserves the original Meta receipt without resend',async()=>{
 await setup();await arm();const r=await receipt();lost='received';assert.equal((await send(r.event_id)).status,503);assert.equal(sends.length,1);
 assert.equal((await state()).rows[0].state,'received');assert.equal((await send(r.event_id)).status,409);
});
test('K195 concurrent setting writes and authorization replay have one winner',async()=>{
 await setup();const d=await state(),b={...confirm(d),enabled:true},rs=await Promise.all([api('/settings',b),api('/settings',b)]);assert.deepEqual(rs.map(x=>x.status).sort(),[200,409]);
 assert.equal((await api('/authorize',{...confirm(d),access_token:'private-system-user-token-fixture'})).status,409);
});
test('K195 revoked or altered credential evidence blocks enable and send',async()=>{
 await setup();authHook=()=>{throw Error('private expired token');};let d=await state();assert.equal((await api('/settings',{...confirm(d),enabled:true})).status,503);assert.equal((await state()).enabled,false);
 authHook=null;await arm();const r=await receipt();system='888888';assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,0);assert.equal((await state()).rows[0].state,'blocked');
});
test('K195 changed account or destination fails before dispatch',async()=>{
 await setup();await arm();const r=await receipt();provided=[];assert.equal((await send(r.event_id)).status,409);assert.equal(sends.length,0);assert.equal((await attempts())[0].state,'blocked');
});
test('K195 disable, grant replacement and measurement revision exclude pending old inquiries',async()=>{
 await setup();await arm();const r=await receipt();await arm(false);assert.equal((await send(r.event_id)).status,409);await arm();assert.deepEqual((await state()).rows,[]);
 const next=await receipt();await authorize();assert.equal((await state()).enabled,false);await arm();assert.equal((await send(next.event_id)).status,409);
 const pending=await receipt();await measure('settings',{enabled:false,expected_revision:(await measure('read')).revision,confirmed:true});assert.equal((await state()).current,false);assert.equal((await send(pending.event_id)).status,409);
});
test('K195 concurrent deletion, disconnect, settings or entitlement loss during preflight prevent upload',async()=>{
 for(const change of ['receipt','disconnect','stop','tier','grant']){
  handler.close();await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);hook=null;
  await setup();
  // Reset consent with its current revision for later loop iterations.
  await measure('settings',{enabled:true,expected_revision:(await measure('read')).revision,confirmed:true});await authorize();await arm();const r=await receipt();
  hook=async()=>{
   if(change==='receipt')await db.query('delete from korlix_funnel_leads where id=$1',[r.lead_id]);
   if(change==='disconnect')await db.query('delete from korlix_meta_connections');
   if(change==='stop')await arm(false);
   if(change==='tier')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
   if(change==='grant')await api('/disconnect',confirm(await state()));
  };
  const response=await send(r.event_id);assert([403,404,409].includes(response.status),change+': '+await response.text());assert.equal(sends.length,0);hook=null;
  // Recreate a clean owner/campaign and ad connection for the next race.
  await db.exec('delete from korlix_funnels;delete from korlix_meta_connections');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
  f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);const binding=randomUUID();
  await db.query("insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,now()+interval '1 day',$6,$7,now())",[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token','korlix-meta:'+owner+':'+binding)),JSON.stringify([account]),account.id]);await linked();
 }
});
test('K195 append-only evidence, credential disconnect cascade and inquiry cleanup',async()=>{
 await setup();await arm();const r=await receipt();assert.equal((await send(r.event_id)).status,200);
 await assert.rejects(db.query("update korlix_meta_delivery_observations set state='blocked'"),/permission denied/);
 await assert.rejects(db.query("update korlix_meta_delivery_attempts set context_hash=repeat('a',64)"),/permission denied/);
 await db.query('delete from korlix_meta_connections');assert.equal((await db.query('select count(*)::int n from korlix_meta_delivery_connections')).rows[0].n,0);assert.equal((await state()).rows[0].state,'received');
 await db.query('delete from korlix_funnel_leads where id=$1',[r.lead_id]);assert.deepEqual(await attempts(),[]);assert.equal((await db.query('select count(*)::int n from korlix_meta_delivery_observations')).rows[0].n,0);
});
test('K195 platform gate off permits local stop/disconnect but never reads secrets or sends',async()=>{
 await setup();await arm();const receiptRow=await receipt(),calls=[];
 const database={rpc:async(name,p)=>{calls.push(p.p_action);try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());const off=registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,KORLIX_META_DELIVERY_ENABLED:'false'},metaProvider:provider,metaDeliveryProvider:deliveryProvider});
 const srv=app.listen(0);await new Promise(r=>srv.once('listening',r));const url='http://127.0.0.1:'+srv.address().port+'/api/funnels/'+f.id+'/campaigns/'+c.id+'/meta-delivery';
 try{
  let d=await(await fetch(url)).json();assert.equal(d.configured,false);assert.equal(d.current,false);
  for(const [suffix,b]of [['/authorize',{access_token:'private-system-user-token-fixture'}],['/send',{event_id:receiptRow.event_id}],['/settings',{enabled:true}]]){
   const r=await fetch(url+suffix,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...confirm(d),...b})});assert.equal(r.status,503);
  }
  assert(!calls.includes('credentials'));assert(!calls.includes('secret'));assert(!calls.includes('claim'));
  let r=await fetch(url+'/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...confirm(d),enabled:false})});assert.equal(r.status,200);d=await r.json();
  r=await fetch(url+'/disconnect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(confirm(d))});assert.equal(r.status,200);assert.equal(sends.length,0);
 }finally{off.close();srv.closeAllConnections();await new Promise(r=>srv.close(r));}
});
