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
const env={KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED:'true',KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:'https://example.com/api/funnels/google-upload-access/callback',KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_CLIENT_ID:'fixture-google-client.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-google-secret',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'};
const config=googleAdsConfiguration(env),uploadConfig=googleUploadConfiguration(env),account={id:'1234567890',name:'Advertiser',currency:'USD',timezone:'UTC',status:'ENABLED',manager:false,test_account:false};
const destination={conversion_customer_id:'8888888888',conversion_action_id:'9223372036854775807',resource_name:'customers/8888888888/conversionActions/9223372036854775807',name:'Inquiry submitted',status:'ENABLED',type:'UPLOAD_CLICKS',category:'SUBMIT_LEAD_FORM',counting_type:'ONE_PER_CLICK',primary_for_goal:false,click_window_days:30,attribution_model:'GOOGLE_ADS_LAST_CLICK',default_value:0,default_currency:'USD',always_use_default_value:false};
const doc={brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'',booking_url:''};
const plan={name:'Growth plan',platform:'google',headline:'Explore',body:'Talk to us',cta:'Learn more',audience:'Businesses',daily_cents:2500,days:14};
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
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923203416_funnel_google_campaign_link.sql','20260924071214_funnel_google_conversion_destination.sql','20260924090911_google_upload_authorization.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:provider,googleUploadProvider:uploadProvider});server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
 handler.close();clock=Date.now();await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 f=await funnel('create',{name:'Services',slug:'services',document:doc});c=await campaign('create',plan);const binding=randomUUID();
 await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,roots,root_id,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,$5,$6,$6,$7,$8,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([root]),root,JSON.stringify([account]),account.id]);await linked();const d=await direct();await direct('save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});providerCalls=0;hook=null;provided=[destination];rootAccess=[root];liveAccount=account;oauthCalls=[];exchangeHook=null;refreshHook=null;grantedScopes=[...googleUploadScopes];
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
test('K191 reads locally without permission or upload claims and keeps all new SQL objects private',async()=>{
 const d=await read();assert.equal(d.authorization,null);assert.equal(d.pending,null);assert.equal(d.version,0);assert.equal(d.can_authorize,true);assert.equal(d.send_ready,false);assert.equal(d.provider_verified,false);assert.equal(d.delivery_state,'not_implemented');assert.equal(providerCalls,0);assert.equal(oauthCalls.length,0);
 for(const role of ['anon','authenticated']){
  await db.exec('reset role;set role '+role);for(const table of ['korlix_google_upload_connections','korlix_google_upload_oauth_attempts'])await assert.rejects(db.query('select * from '+table),/permission denied/);
  await assert.rejects(upload(),/permission denied/);await assert.rejects(db.query("select nextval('korlix_google_upload_version_seq')"),/permission denied/);await assert.rejects(db.query("select korlix_google_upload_sealed_valid('{}')"),/permission denied/);await db.exec('reset role;set role service_role');
 }
 const funcs=(await db.query("select prosecdef,proconfig from pg_proc where proname in ('korlix_google_upload_sealed_valid','korlix_google_upload_access_v1')")).rows;assert.equal(funcs.length,2);assert(funcs.every(x=>x.prosecdef===false&&x.proconfig[0]==='search_path=public, pg_temp'));
 assert((await db.query("select relrowsecurity from pg_class where relname in ('korlix_google_upload_connections','korlix_google_upload_oauth_attempts')")).rows.every(x=>x.relrowsecurity));
});
test('K191 explicit OAuth preserves Ads connection, uses single-use PKCE and original-window proof, then verifies Ads access',async()=>{
 const before=(await db.query('select to_jsonb(c) v from korlix_google_ads_connections c')).rows;
 const a=await begin(),url=new URL(a.authorization_url);assert.deepEqual(url.searchParams.get('scope').split(' '),googleUploadScopes);
 const pending=(await db.query('select * from korlix_google_upload_oauth_attempts')).rows[0];assert(!JSON.stringify(pending).includes(a.proof));assert.equal((await finish(a)).status,409);
 const cb=await callback(a);assert.equal(cb.status,200);assert.match(cb.headers.get('content-security-policy'),/frame-ancestors 'none'/);assert.equal(cb.headers.get('referrer-policy'),'no-referrer');assert.equal(cb.headers.get('cache-control'),'no-store');
 assert.equal(googleChallenge(oauthCalls[0][2]),url.searchParams.get('code_challenge'));assert.equal((await db.query('select verifier_sealed from korlix_google_upload_oauth_attempts')).rows[0].verifier_sealed,null);
 assert.equal((await callback(a)).status,409);assert.equal(oauthCalls.filter(x=>x[0]==='exchange').length,1);
 assert.equal((await finish({...a,proof:'a'.repeat(43)})).status,409);assert.equal((await request('/finish',{id:a.id,proof:a.proof,confirmed:true},other)).status,404);assert.equal((await request('/finish',{id:a.id,proof:a.proof,confirmed:true},basic)).status,403);
 const r=await finish(a);assert.equal(r.status,200,await r.clone().text());const d=await r.json();assert.equal(d.authorization.current,true);assert(d.version>0);assert.equal(d.pending,null);assert.equal(d.send_ready,false);assert.equal(d.provider_verified,false);assert.equal(providerCalls,1);assert.deepEqual(oauthCalls.find(x=>x[0]==='refresh'),['refresh','private-upload-refresh']);
 assert.deepEqual((await db.query('select to_jsonb(c) v from korlix_google_ads_connections c')).rows,before);
 const u=(await ledger())[0];assert.equal(googleTokenCipher(config.key).open(u.sealed,`korlix-google-upload:refresh:${owner}:${a.id}`),'private-upload-refresh');assert.throws(()=>googleTokenCipher(config.key).open(u.sealed,`korlix-google-ads:refresh:${owner}:${a.id}`));
 const callbackHtml=await cb.text();for(const secret of ['private-code','private-upload-refresh','private-upload-access','candidate','sealed','proof_hash','state_hash','config_hash','ads_binding_id'])assert(!(JSON.stringify(d)+callbackHtml).includes(secret));assert.equal((await finish(a)).status,409);
});
test('K191 anonymous, other-owner, Basic and unconfirmed requests cannot authorize',async()=>{
 const d=await read();for(const [actor,status]of [['',401],[other,404],[basic,403]]){
  assert.equal((await request('',null,actor)).status,status);assert.equal((await request('/begin',confirmation(d),actor)).status,status);
 }
 for(const b of [{...confirmation(d),confirmed:false},{...confirmation(d),extra:true},{...confirmation(d),fingerprint:'bad'}])assert.equal((await request('/begin',b)).status,400);
 assert.equal((await request('?extra=1')).status,400);assert.equal(oauthCalls.length,0);assert.deepEqual(await ledger(),[]);
});
test('K191 cancel, expiry, supersession, malformed state and omitted permission cannot save credentials',async()=>{
 const a=await begin();assert.equal((await callback(a,'&error=access_denied')).status,400);assert.equal(oauthCalls.length,0);assert.equal((await finish(a)).status,409);
 await nextAttempt();const b=await begin();assert.equal((await callback(a)).status,404);await db.exec("update korlix_google_upload_oauth_attempts set expires_at=now()-interval '1 second'");assert.equal((await callback(b)).status,409);
 assert.equal((await fetch(base+'/api/funnels/google-upload-access/callback?state=a&state=b')).status,400);
 await read();await nextAttempt();const missing=await begin();grantedScopes=[googleUploadScopes[0]];assert.equal((await callback(missing)).status,409);assert.equal((await finish(missing)).status,409);assert.deepEqual(await ledger(),[]);
});
test('K191 destination edits or upload disconnect during callback discard exchanged credentials',async()=>{
 for(const action of ['destination','disconnect']){
  handler.close();const a=await begin();exchangeHook=async()=>{if(action==='disconnect'){const d=await read();await upload('disconnect',confirmation(d));}else{const d=await direct();await direct('clear',{version:d.version,fingerprint:d.fingerprint,confirmed:true});}};
  assert.equal((await callback(a)).status,409);assert.deepEqual(await ledger(),[]);exchangeHook=null;
  const d=await direct();if(!d.selection){await direct('save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});}await nextAttempt();
 }
});
test('K191 permission and destination changes during finish prevent new access and preserve existing grant',async()=>{
 const saved=await grant(),old=(await ledger())[0];
 for(const change of [async()=>{const d=await direct();await direct('clear',{version:d.version,fingerprint:d.fingerprint,confirmed:true});},()=>db.query("update korlix_google_ads_connections set version=version+1"),()=>db.query("update user_profiles set tier='basic' where id=$1",[owner])]){
  await nextAttempt();await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);await linked();const d=await direct();await direct('save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});
  const a=await begin();assert.equal((await callback(a)).status,200);hook=change;const r=await finish(a);assert([403,409].includes(r.status),await r.text());assert.deepEqual((await ledger())[0],old);hook=null;
 }
 assert(saved.authorization.current);
});
test('K191 wrong Google account or changed action cannot replace a saved upload grant',async()=>{
 await grant();const old=(await ledger())[0];
 for(const change of [()=>{rootAccess=[];},()=>{liveAccount={...account,name:'Changed'};}]){
  await nextAttempt();const a=await begin();assert.equal((await callback(a)).status,200);change();assert.equal((await finish(a)).status,409);assert.deepEqual((await ledger())[0],old);rootAccess=[root];liveAccount=account;
 }
 for(const rows of [[],[{...destination,default_value:15}]]){
  await nextAttempt();const a=await begin();assert.equal((await callback(a)).status,200);provided=rows;assert.equal((await finish(a)).status,409);assert.deepEqual((await ledger())[0],old);
 }
 provided=[destination];await nextAttempt();const a=await begin();assert.equal((await callback(a)).status,200);refreshHook=()=>{throw Error('private token body');};const r=await finish(a);assert.equal(r.status,503);assert(!(await r.text()).includes('private'));assert.deepEqual((await ledger())[0],old);
});
test('K191 concurrent finish has one winner; local disconnect removes upload secrets without Ads/provider work',async()=>{
 const a=await begin();assert.equal((await callback(a)).status,200);const rs=await Promise.all([finish(a),finish(a)]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal(oauthCalls.filter(x=>x[0]==='refresh').length,1);
 let d=await read();const oldVersion=d.version,calls=providerCalls+oauthCalls.length;assert.equal((await request('/disconnect',{...confirmation(d),confirmed:false})).status,400);
 assert.equal((await request('/disconnect',confirmation(d))).status,200);assert.equal(providerCalls+oauthCalls.length,calls);assert.deepEqual(await ledger(),[]);assert.equal((await db.query('select count(*)::int n from korlix_google_ads_connections')).rows[0].n,1);
 d=await grant();assert(d.version>oldVersion);assert.equal((await finish(a)).status,409);
});
test('K191 archive/config/account changes make access stale; clearing remains local, Ads deletion cascades credentials',async()=>{
 await grant();c=await campaign('archive',{confirmed:true});let d=await read();assert.equal(d.can_authorize,false);assert.equal(d.authorization.current,false);assert.equal((await request('/disconnect',confirmation(d))).status,200);
 c=await campaign('reopen');const fresh=await direct();await direct('save',{version:fresh.version,fingerprint:fresh.fingerprint,confirmed:true,destination,checked_at:new Date().toISOString()});await grant();d=await upload('read',{configured:false});assert.equal(d.authorization.current,false);assert.equal(d.can_authorize,false);
 await db.query('delete from korlix_google_ads_connections where user_id=$1',[owner]);assert.deepEqual(await ledger(),[]);assert.equal((await db.query('select count(*)::int n from korlix_google_upload_oauth_attempts')).rows[0].n,0);
});
test('K191 SQL rejects untrusted sealing, scopes, stale versions and expired checks',async()=>{
 const d=await read();await assert.rejects(upload('begin',{...confirmation(d),id:randomUUID(),state_hash:'a'.repeat(64),proof_hash:'b'.repeat(64),verifier_sealed:{v:1,iv:'bad',tag:'bad',ciphertext:'plain'}}));
 const a=await begin();assert.equal((await callback(a)).status,200);await upload('claim',{id:a.id,proof_hash:(await import('../funnels/google_ads_provider.mjs')).googleDigest(a.proof),confirmed:true});
 for(const checked_at of ['infinity','2020-01-01T00:00:00Z'])await assert.rejects(upload('finish',{id:a.id,checked_at}));assert.deepEqual(await ledger(),[]);
});
test('K191 current-state fingerprint prevents stale begin/disconnect and request quota is bounded',async()=>{
 const d=await read();await begin();assert.equal((await request('/begin',confirmation(d))).status,409);assert.equal((await request('/disconnect',confirmation(d))).status,409);
 for(let i=0;i<7;i++)await request('/finish',{id:randomUUID(),proof:'a'.repeat(43),confirmed:true});assert.equal((await request('/finish',{id:randomUUID(),proof:'a'.repeat(43),confirmed:true})).status,429);assert.equal((await request()).status,200);
});
