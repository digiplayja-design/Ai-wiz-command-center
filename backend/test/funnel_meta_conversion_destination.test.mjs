import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher,MetaAccessError} from '../funnels/meta.mjs';
import {metaDestinationProof,metaDestinationProofValid} from '../funnels/meta_conversion_destination.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_ENABLED:'true',KORLIX_META_CONVERSION_SETUP_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-conversion-secret',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback'};
const config=metaConfiguration(env),account={id:'act_123',name:'Advertiser',currency:'USD',timezone:'UTC',status:1};
const destination={pixel_id:'987654321',name:'Website inquiries'};
const doc={brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'',booking_url:''};
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
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923194721_funnel_meta_campaign_link.sql','20260924222246_funnel_meta_conversion_destination.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,metaProvider:provider});server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
 handler.close();clock=Date.now();await db.exec('delete from korlix_funnels;delete from korlix_meta_connections');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 f=await funnel('create',{name:'Services',slug:'services',document:doc});c=await campaign('create',plan);const binding=randomUUID();
 await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id]);await linked();providerCalls=0;hook=null;provided=[destination];
});
test.after(async()=>{await writeFile('/tmp/k193-expected-functions.json',JSON.stringify((await db.query("select proname,md5(prosrc) hash from pg_proc where proname in ('korlix_funnel_meta_destination_v1','korlix_meta_conversion_destination_valid') order by proname")).rows));handler.close();server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('K193 initial local read creates nothing and never implies upload readiness',async()=>{
 const r=await request(),d=await r.json();assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(d.source,'meta_conversion_destination');assert.equal(d.lookup_ready,true);assert.equal(d.version,0);assert.equal(d.selection,null);assert.equal(d.selection_current,false);assert.equal(d.send_ready,false);assert.equal(d.provider_verified,false);assert.equal(d.delivery_state,'not_implemented');assert.equal(providerCalls,0);assert.deepEqual(await ledger(),[]);
 for(const s of ['sealed','binding_id','config_hash','private-fixture-token'])assert(!JSON.stringify(d).includes(s));
});
test('K193 discovery signs choices and save rechecks provider before storing a scoped destination',async()=>{
 const {d,list}=await choices();assert.equal(list.choices.length,1);assert.equal(list.send_ready,false);assert.equal((await ledger()).length,0);const count=providerCalls;
 const r=await request('/save',input(d,list.choices[0]));assert.equal(r.status,200,await r.clone().text());const saved=await r.json();assert.equal(providerCalls,count+2);assert.equal(saved.version,1);assert.equal(saved.selection_current,true);assert.deepEqual(saved.selection.destination,destination);assert.equal(saved.selection.context.provider_campaign_id,'456');assert.equal(saved.selection.context.account.id,account.id);assert.equal(saved.send_ready,false);
 const row=(await ledger())[0];assert(!JSON.stringify(row).includes('proof'));assert(!JSON.stringify(row).includes('token'));assert.equal((await request('/save',input(d,list.choices[0]))).status,409);assert.equal((await ledger())[0].version,1);
});
test('K193 forged, altered, expired and cross-purpose choices cannot cause provider work or writes',async()=>{
 const {d,list}=await choices(),valid=input(d,list.choices[0]),count=providerCalls;
 for(const patch of [{proof:'bad'},{confirmed:false},{destination:{...destination,name:'Changed'}},{destination:{...destination,pixel_id:'123'}},{destination:{...destination,extra:true}},{extra:true}]){const r=await request('/save',{...valid,...patch});assert([400,409].includes(r.status));}
 assert.equal(providerCalls,count);assert.deepEqual(await ledger(),[]);clock+=6*60000;assert.equal((await request('/save',valid)).status,409);assert.equal(providerCalls,count);
 const scope={actor:owner,funnel:f.id,campaign:c.id,fingerprint:d.fingerprint},proof=metaDestinationProof(config.secret,scope,destination,Date.now());for(const key of ['actor','funnel','campaign','fingerprint'])assert(!metaDestinationProofValid(config.secret,{...scope,[key]:'other'},destination,proof,Date.now()));
});
test('K193 provider removal or changed action fields reject stale choices without persisting',async()=>{
 for(const next of [[],[{...destination,name:'Renamed'}],[{...destination,pixel_id:'123'}]]){handler.close();provided=[destination];const {d,list}=await choices();provided=next;assert.equal((await request('/save',input(d,list.choices[0]))).status,409);assert.deepEqual(await ledger(),[]);}
});
test('K193 late local edits, disconnects, relinks and entitlement loss discard provider data',async()=>{
 for(const change of [()=>db.query("update korlix_funnel_campaigns set version=version+1 where id=$1",[c.id]),()=>db.query('update korlix_meta_connections set version=version+1'),async()=>{const l=await link();await link('clear',{version:l.version,fingerprint:l.fingerprint,confirmed:true});},()=>db.query("update user_profiles set tier='basic' where id=$1",[owner])]){
  handler.close();await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);await linked();const d=await read();hook=change;const r=await request('/choices?fingerprint='+d.fingerprint);assert([403,409].includes(r.status));assert.deepEqual(await ledger(),[]);hook=null;
 }
});
test('K193 selection becomes stale after account/link changes; clear remains local on archive and disconnect',async()=>{
 assert.equal((await save()).status,200);const original=(await ledger())[0];await db.query('update korlix_meta_connections set needs_reconnect=true');c=await campaign('archive',{confirmed:true});const d=await read();assert.equal(d.lookup_ready,false);assert.equal(d.selection_current,false);assert.deepEqual((await ledger())[0],original);const calls=providerCalls;
 const r=await request('/clear',{version:d.version,fingerprint:d.fingerprint,confirmed:true});assert.equal(r.status,200);const cleared=await r.json();assert.equal(cleared.version,2);assert.equal(cleared.selection,null);assert.equal(providerCalls,calls);assert.equal((await ledger()).length,1);
});
test('K193 concurrent confirmed saves have one winner and clear prevents old-choice replay',async()=>{
 const {d,list}=await choices(),b=input(d,list.choices[0]);const rs=await Promise.all([request('/save',b),request('/save',b)]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal((await ledger())[0].version,1);
 const saved=await read();assert.equal((await request('/clear',{version:saved.version,fingerprint:saved.fingerprint,confirmed:true})).status,200);assert.equal((await request('/save',b)).status,409);assert.equal((await read()).selection,null);
});
test('K193 ownership, Enterprise and SQL role/grant boundaries protect setup and helpers',async()=>{
 const {d,list}=await choices();for(const [actor,status]of [['',401],[other,404],[basic,403]]){assert.equal((await request('',null,actor)).status,status);assert.equal((await request('/choices?fingerprint='+d.fingerprint,null,actor)).status,status);assert.equal((await request('/save',input(d,list.choices[0]),actor)).status,status);}
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(direct(),/permission denied/);await assert.rejects(db.query('select * from korlix_funnel_meta_conversion_destinations'),/permission denied/);await assert.rejects(db.query('select korlix_meta_conversion_destination_valid($1)',[JSON.stringify(destination)]),/permission denied/);await db.exec('reset role;set role service_role');}
 const p=(await db.query("select prosecdef,proconfig from pg_proc where oid='korlix_funnel_meta_destination_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(p.prosecdef,false);assert.deepEqual(p.proconfig,['search_path=public, pg_temp']);assert.equal((await db.query("select has_table_privilege('service_role','korlix_funnel_meta_conversion_destinations','delete') v")).rows[0].v,false);
});
test('K193 SQL rejects invalid action snapshots and expired checks; campaign removal cascades selection',async()=>{
 const d=await direct(),write={version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()};
 for(const patch of [{pixel_id:'act_123'},{pixel_id:123},{extra:1},{name:''},{name:' leading'},{name:'control\n'}])await assert.rejects(direct('save',{...write,destination:{...destination,...patch}}));
 await assert.rejects(direct('save',{...write,checked_at:'infinity'}));await assert.rejects(direct('save',{...write,checked_at:'2020-01-01T00:00:00Z'}));await direct('save',write);await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.deepEqual(await ledger(),[]);
});
test('K193 missing linked campaign, inactive accounts and disabled platform cannot reach discovery',async()=>{
 const l=await link();await link('clear',{version:l.version,fingerprint:l.fingerprint,confirmed:true});let d=await read();assert.equal(d.lookup_ready,false);assert.equal((await request('/choices?fingerprint='+d.fingerprint)).status,409);
 await linked();await db.query('update korlix_meta_connections set accounts=$1',[JSON.stringify([{...account,status:2}])]);d=await read();assert.equal(d.lookup_ready,false);assert.equal((await request('/choices?fingerprint='+d.fingerprint)).status,409);assert.equal(providerCalls,0);
 const disabled=await rpc('korlix_funnel_meta_destination_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{...ctx(),configured:false}});assert.equal(disabled.lookup_ready,false);
});
test('K193 OAuth revocation requires reconnect, while ordinary failures preserve connection and selections',async()=>{
 const d=await read();hook=async()=>{throw Error('private provider token');};let r=await request('/choices?fingerprint='+d.fingerprint);assert.equal(r.status,503);assert(!(await r.text()).includes('private'));assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,false);
 hook=async()=>{throw new MetaAccessError();};r=await request('/choices?fingerprint='+d.fingerprint);assert.equal(r.status,409);assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,true);assert.deepEqual(await ledger(),[]);
});
test('K193 provider quota is shared by list/save and local reads remain available',async()=>{
 const d=await read();for(let i=0;i<10;i++)assert.equal((await request('/choices?fingerprint='+d.fingerprint)).status,200);assert.equal((await request('/choices?fingerprint='+d.fingerprint)).status,429);assert.equal((await request()).status,200);
});
test('K193 data source permission failure preserves the Meta connection; account metadata mismatch blocks discovery',async()=>{
 const {MetaConversionAccessError}=await import('../funnels/meta_conversion_provider.mjs');
 const d=await read();hook=async()=>{throw new MetaConversionAccessError();};let r=await request('/choices?fingerprint='+d.fingerprint);assert.equal(r.status,409);assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,false);
 hook=null;const original=provider.account;provider.account=async()=>({...account,name:'Renamed'});
 try{const count=providerCalls;r=await request('/choices?fingerprint='+d.fingerprint);assert.equal(r.status,409);assert.equal(providerCalls,count);assert.deepEqual(await ledger(),[]);}finally{provider.account=original;}
});
test('K193 independent setup gate and API version remain off by default, while local reads are available',async()=>{
 for(const patch of [{KORLIX_META_CONVERSION_SETUP_ENABLED:undefined},{KORLIX_META_ENABLED:'false'},{KORLIX_META_API_VERSION:'v25.0'}]){
  const database={rpc:async(name,p)=>{try{return {data:await rpc(name,p)}}catch(error){return {error}}}};
  const app=express();app.use(express.json());const h=registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,...patch},metaProvider:provider});
  const s=app.listen(0);await new Promise(r=>s.once('listening',r));const host='http://127.0.0.1:'+s.address().port+'/api/funnels',path=host+`/${f.id}/campaigns/${c.id}/meta-conversion-destination`;
  try{
   const r=await fetch(host+'/meta-conversion-destination/readiness');assert.equal(r.headers.get('cache-control'),'no-store');assert.deepEqual(await r.json(),{configured:false,send_ready:false,provider_verified:false});
   const d=await (await fetch(path)).json();assert.equal(d.lookup_ready,false);assert.equal((await fetch(path+'/choices?fingerprint='+d.fingerprint)).status,409);assert.equal(providerCalls,0);
  }finally{h.close();s.closeAllConnections();await new Promise(r=>s.close(r));}
 }
});
