import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
import {metaCampaignChoiceProof} from '../funnels/meta_campaign_link.mjs';
import {googleReportRange} from '../funnels/google_ads_performance.mjs';
import {linkedGoogleRows,googleCampaignChoiceProof,googleCampaignChoiceProofValid} from '../funnels/google_campaign_link.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'fixture-google-client.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-google-secret-not-real',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'};
const config=googleAdsConfiguration(env),rootId='1111111111',defaultAccount={id:'1234567890',name:'Growth account',currency:'KWD',timezone:'America/New_York',status:'ENABLED',manager:false,test_account:false};
const doc={brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'',contact_email:'',booking_url:''};
const plan={name:'Growth plan',platform:'google',headline:'Explore',body:'Talk to us',cta:'Learn more',audience:'Businesses',daily_cents:2500,days:14};
const providerReport=()=>({rows:[{campaign_id:'456',campaign_name:'Same name',spend:'0.123456',clicks:3,impressions:20,status:'ENABLED',channel:'SEARCH'},{campaign_id:'789',campaign_name:'Same name',spend:'2.00',clicks:7,impressions:80,status:'PAUSED',channel:'DISPLAY'}],totals:{spend:'2.123456',clicks:10,impressions:100},reported_campaigns:2});
let db,server,base,f,c,account,clock=Date.now(),providerCalls=0,reportImpl,accountImpl,rootsImpl,refreshImpl,handler;
const rpc=async(name,p)=>(await db.query(name==='korlix_google_ads_v1'?`select public.${name}($1,$2,$3) r`:`select public.${name}($1,$2,$3,$4) r`,name==='korlix_google_ads_v1'?[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={},actor=owner,id=f?.id)=>rpc('korlix_funnel_v1',{p_actor:actor,p_action:action,p_id:action==='create'?null:id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const link=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_campaign_link_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,...data}});
const request=(suffix='',body=null,actor=owner,campaignId=c.id)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${campaignId}/google-link${suffix}`,{method:body===null?'GET':'POST',headers:{authorization:actor,'content-type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$6,$7,$8,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,JSON.stringify([account]),account.id]);}
async function choices(){const d=await link();const r=await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`);assert.equal(r.status,200);return {d,out:await r.json()};}
async function saveLink(index=0){const {d,out}=await choices();const r=await request('/save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,...out.choices[index]});assert.equal(r.status,200);return r.json();}
async function performance(days=7){const d=await link();return request(`/performance?days=${days}&fingerprint=${d.fingerprint}`);}
test.before(async()=>{
 db=new PGlite();await db.exec("create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;");
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923203416_funnel_google_campaign_link.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:{refresh:async(...args)=>{providerCalls++;return refreshImpl(...args);},roots:async(...args)=>{providerCalls++;return rootsImpl(...args);},account:async(...args)=>{providerCalls++;return accountImpl(...args);},campaignPerformance:async(...args)=>{providerCalls++;return reportImpl(...args);}}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{handler.close();clock=Date.now(); // Reset rate counters without advancing the report beyond the database's local day.
 await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);account={...defaultAccount};f=await funnel('create',{name:'Services',slug:'services',document:doc});c=await campaign('create',plan);await connect();providerCalls=0;accountImpl=async()=>account;reportImpl=async()=>providerReport();rootsImpl=async()=>[rootId];refreshImpl=async()=>"private-access-token";});
test.after(async()=>{handler.close();server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('Local read is private, owner/tier/platform-scoped and never calls Google or leaks credentials',async()=>{
 const r=await request(),d=await r.json();assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(d.lookup_ready,true);assert.equal(d.report_ready,false);assert.equal(d.link,null);assert.equal(d.version,0);assert.equal(providerCalls,0);
 for(const secret of ['sealed','config_hash','google_user_id','binding_id','private-fixture-token'])assert(!JSON.stringify(d).includes(secret));
 for(const [actor,status] of [['',401],[other,404],[basic,403]])assert.equal((await request('',null,actor)).status,status);
 await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await request()).status,400);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_campaign_links'),/permission denied/);await assert.rejects(link(),/permission denied/);await db.exec('reset role;set role service_role');}
 const p=(await db.query("select md5(prosrc) body_hash,prosecdef,proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_google_campaign_links'::regclass) rls from pg_proc where oid='korlix_funnel_google_campaign_link_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(p.prosecdef,false);assert.equal(p.rls,true);assert.deepEqual(p.proconfig,['search_path=public, pg_temp']);await writeFile('/tmp/k180-function-hashes.json',JSON.stringify(p,null,2));
});
test('Choices use provider IDs even for identical names; saving only changes the link and never stores a receipt/metrics',async()=>{
 const {d,out}=await choices();assert.equal(out.choices.length,2);assert.equal(out.choices[0].provider_campaign_name,out.choices[1].provider_campaign_name);assert.notEqual(out.choices[0].provider_campaign_id,out.choices[1].provider_campaign_id);
 const calls=providerCalls,r=await request('/save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,...out.choices[1]});assert.equal(r.status,200);const saved=await r.json();assert.equal(saved.link.provider_campaign_id,'789');assert.equal(saved.link_current,true);assert.equal(saved.version,1);assert.equal(providerCalls,calls);
 const row=(await db.query('select to_jsonb(x) r from korlix_funnel_google_campaign_links x')).rows[0].r;
 for(const key of ['proof','spend','clicks','impressions','sealed'])assert(!JSON.stringify(row).includes('"'+key+'"'));
 assert.equal((await campaign('list')).campaigns[0].version,c.version);assert.equal(saved.ad_publishing_ready,false);assert.equal(saved.attribution_verified,false);
});
test('Choice receipts reject forgery, altered labels, cross-plan reuse, expiry and changes to context',async()=>{
 const {d,out}=await choices(),choice=out.choices[0],body={version:d.version,fingerprint:d.fingerprint,confirmed:true,...choice};
 for(const patch of [{proof:'bad'},{provider_campaign_id:'999'},{provider_campaign_name:'Changed'},{proof:choice.proof.slice(0,-1)+(choice.proof.endsWith('0')?'1':'0')}])assert.equal((await request('/save',{...body,...patch})).status,400);
 const original=c;c=await campaign('create',{...plan,name:'Second plan'});const second=await link();assert.equal((await request('/save',{...body,version:second.version,fingerprint:second.fingerprint})).status,400);c=original;
 clock+=31*60000;assert.equal((await request('/save',body)).status,400);clock=Date.now();
 c=await campaign('save',{...plan,name:'Updated plan'});assert.equal((await request('/save',body)).status,409);
});
test('One provider campaign cannot be linked to two of the same owner plans; clear preserves monotonic versions',async()=>{
 const first=await saveLink(),original=c;c=await campaign('create',{...plan,name:'Second plan'});const {d,out}=await choices();const body={version:d.version,fingerprint:d.fingerprint,confirmed:true,...out.choices[0]};
 assert.equal((await request('/save',body)).status,409);const second=c;c=original;
 const clear=await request('/clear',{version:first.version,fingerprint:first.fingerprint,confirmed:true});assert.equal(clear.status,200);const cleared=await clear.json();assert.equal(cleared.version,2);assert.equal(cleared.link,null);
 assert.equal((await request('/clear',{version:first.version,fingerprint:first.fingerprint,confirmed:true})).status,409);
 c=second;assert.equal((await request('/save',body)).status,200);
});
test('Performance contains only the linked row with exact decimals and matching local tagged inquiries',async()=>{
 await saveLink();const range=googleReportRange(7,account.timezone,clock);
 const bounds=(await db.query("select $1::date::timestamp at time zone $3 start_at, ($2::date+1)::timestamp at time zone $3 end_at",[range.from,range.to,account.timezone])).rows[0];
 const start=Date.parse(bounds.start_at),end=Date.parse(bounds.end_at),tag='k143_'+c.id.replaceAll('-','');
 for(const [time,source,campaignTag] of [[start-1,'google',tag],[start,'google',tag],[end-1,'google',tag],[end,'google',tag],[start+1,'facebook',tag],[start+1,'google','other']])await db.query("insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,utm,consent_text,created_at) values($1,$2,1,'Test','test@example.com',$3,'test',$4)",[f.id,randomUUID(),JSON.stringify({utm_campaign:campaignTag,utm_source:source}),new Date(time).toISOString()]);
 const response=await performance(),r=await response.json();assert.equal(response.status,200);assert.equal(r.row.campaign_id,'456');assert.equal(r.row.spend,'0.123456');assert.equal(r.account.currency,'KWD');assert.equal(r.measurement.tagged_inquiries,2);assert.equal(r.measurement.timezone,account.timezone);assert.equal(Date.parse(r.measurement.start_inclusive),start);assert.equal(Date.parse(r.measurement.end_exclusive),end);assert.deepEqual(r.range,range);assert(!JSON.stringify(r).includes('"campaign_id":"789"'));assert.equal(r.row.status,'ENABLED');assert.equal(r.row.channel,'SEARCH');assert.equal(r.attribution_verified,false);
});
test('No Google row is not a zero result; an explicit zero row remains reportable',async()=>{
 await saveLink();reportImpl=async()=>({rows:[],totals:{spend:'0.00',clicks:0,impressions:0},reported_campaigns:0});let r=await(await performance()).json();assert.equal(r.row,null);assert.equal(r.measurement.tagged_inquiries,0);
 reportImpl=async()=>({rows:[{campaign_id:'456',campaign_name:'Renamed by Google',spend:'0.00',clicks:0,impressions:0,status:'PAUSED',channel:'SEARCH'}],totals:{spend:'0.00',clicks:0,impressions:0},reported_campaigns:1});r=await(await performance()).json();assert.equal(r.row.spend,'0.00');assert.equal(r.row.campaign_name,'Renamed by Google');assert.equal(r.link.provider_campaign_name,'Same name');
});
test('Provider account changes and malformed adapter results fail before any receipt is issued',async()=>{
 for(const patch of [{id:'9999999999'},{currency:'USD'},{timezone:'UTC'},{status:'SUSPENDED'},{manager:true},{test_account:true}]){accountImpl=async()=>({...account,...patch});const d=await link();assert.equal((await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`)).status,409);}
 accountImpl=async()=>account;
 for(const bad of [{rows:[]}, {...providerReport(),reported_campaigns:3}, {...providerReport(),totals:{spend:'2.123455',clicks:10,impressions:100}}, {...providerReport(),rows:[providerReport().rows[0],providerReport().rows[0]]}]){clock+=60000;reportImpl=async()=>bad;const d=await link();assert.equal((await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`)).status,503);}
});
test('Disconnect, downgrade, plan edit and relink during provider work suppress late output',async()=>{
 for(const change of ['disconnect','downgrade','plan','clear']){
  clock+=60000;await db.exec('delete from korlix_google_ads_connections;delete from korlix_funnel_google_campaign_links;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);await connect();reportImpl=async()=>providerReport();await saveLink();
  reportImpl=async()=>{if(change==='disconnect')await db.exec('delete from korlix_google_ads_connections');else if(change==='downgrade')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);else if(change==='plan')c=await campaign('save',{...plan,name:'New plan'});else{const d=await link();await link('clear',{version:d.version,fingerprint:d.fingerprint,confirmed:true});}return providerReport();};
  const r=await performance();assert.equal(r.status,change==='downgrade'?403:409);assert(!JSON.stringify(await r.json()).includes('0.123456'));
 }
});
test('Revoked provider access marks reconnect without leaking remote details',async()=>{
 reportImpl=async()=>{throw new GoogleAdsAccessError();};const d=await link(),r=await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`);assert.equal(r.status,409);assert.equal((await link()).lookup_ready,false);assert.equal((await db.query('select needs_reconnect from korlix_google_ads_connections')).rows[0].needs_reconnect,true);
});
test('Connection reselection/configuration/binding changes stale links; clear works after disconnect and on archive',async()=>{
 let d=await saveLink();await db.query("update korlix_google_ads_connections set selected_account=null,version=nextval('korlix_google_ads_version_seq')");assert.equal((await link()).link_current,false);
 await db.exec('delete from korlix_google_ads_connections');await connect();assert.equal((await link()).link_current,false);
 c=await campaign('archive',{confirmed:true});d=await link();assert.equal(d.editable,false);assert.equal(d.lookup_ready,false);assert.equal((await request('/clear',{version:d.version,fingerprint:d.fingerprint,confirmed:true})).status,200);
 await db.exec('delete from korlix_google_ads_connections');assert.equal((await link()).link,null);
});
test('SQL rejects stale/unconfirmed/forged shapes and out-of-period measurement; no arbitrary range is accepted',async()=>{
 const d=await saveLink(),baseData={version:d.version,fingerprint:d.fingerprint,confirmed:true};
 for(const patch of [{version:'1'},{version:0},{confirmed:'true'},{fingerprint:'bad'},{actor:other}])await assert.rejects(link('clear',{...baseData,...patch}));
 const range=googleReportRange(7,account.timezone,clock);
 for(const patch of [{days:1},{days:'7'},{from:'2026-02-30'},{to:'2099-01-01'},{from:'2026-01-01'}])await assert.rejects(link('measure',{fingerprint:d.fingerprint,...range,...patch}));
 for(const suffix of ['?actor=x','/campaigns?days=7','/performance?days=7&fingerprint='+d.fingerprint+'&account_id=act_999'])assert.equal((await request(suffix)).status,400);
 assert.equal((await request('/clear',{...baseData,extra:true})).status,400);
});
test('New reporting routes share the existing Google report quota and reject unconfigured access',async()=>{
 const d=await link();for(let i=0;i<10;i++)assert.equal((await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`)).status,200);
 assert.equal((await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`)).status,429);
 const conn=(await db.query('select version from korlix_google_ads_connections')).rows[0];assert.equal((await fetch(`${base}/api/funnels/google-ads/campaign-performance?days=7&version=${conn.version}&account_id=${account.id}&root_id=${rootId}`,{headers:{authorization:owner}})).status,429);
 assert.equal((await link('read',{configured:false})).lookup_ready,false);
});
test('PostgreSQL calendar boundaries honor DST and fractional-hour timezone offsets',async()=>{
 const r=(await db.query("select '2026-03-08'::timestamp at time zone 'America/New_York' a, '2026-03-09'::timestamp at time zone 'America/New_York' b, '2026-11-01'::timestamp at time zone 'America/New_York' c, '2026-11-02'::timestamp at time zone 'America/New_York' d, '2026-09-01'::timestamp at time zone 'Asia/Kathmandu' e")).rows[0];
 assert.equal(Date.parse(r.b)-Date.parse(r.a),23*3600000);assert.equal(Date.parse(r.d)-Date.parse(r.c),25*3600000);assert.equal(new Date(r.e).toISOString(),'2026-08-31T18:15:00.000Z');
});
test('Receipt domain binds every identity and expires; malformed metrics never receive signatures',()=>{
 const scope={actor:'u',funnel:'f',campaign:'c',fingerprint:'a'.repeat(64)},row={provider_campaign_id:'123',provider_campaign_name:'Name'},time=Date.now();
 const proof=googleCampaignChoiceProof('secret',scope,row,time);assert(googleCampaignChoiceProofValid('secret',scope,row,proof,time));
 for(const field of ['actor','funnel','campaign','fingerprint'])assert(!googleCampaignChoiceProofValid('secret',{...scope,[field]:'other'},row,proof,time));
 assert(!googleCampaignChoiceProofValid('other',scope,row,proof,time));assert(!googleCampaignChoiceProofValid('secret',scope,row,proof,time+1800000));
 for(const change of [{spend:'NaN'},{spend:'-1'},{clicks:9007199254740992},{campaign_id:'../x'},{campaign_id:'9223372036854775808'},{campaign_id:'0'},{status:'BOGUS'},{channel:'BOGUS'},{campaign_name:'\0'}])assert.throws(()=>linkedGoogleRows({...providerReport(),rows:[{...providerReport().rows[0],...change},providerReport().rows[1]]}));
});
test('Google hierarchy is checked before and after reporting, including unchanged account under a new manager',async()=>{
 const d=await saveLink();assert.equal(d.root_id,rootId);assert.equal(d.link.login_customer_id,rootId);
 rootsImpl=async()=>[];let r=await performance();assert.equal(r.status,409);assert(!JSON.stringify(await r.json()).includes('private-'));
 rootsImpl=async()=>[rootId];reportImpl=async()=>{await db.query("update korlix_google_ads_connections set roots=$1,root_id='2222222222',login_customer_id='2222222222',version=nextval('korlix_google_ads_version_seq')",[JSON.stringify(['2222222222'])]);return providerReport();};
 r=await performance();assert.equal(r.status,409);const stale=await link();assert.equal(stale.link_current,false);assert.equal(stale.lookup_ready,true);
 assert.equal((await request('/clear',{version:stale.version,fingerprint:stale.fingerprint,confirmed:true})).status,200);
});
test('Direct access sends no manager header; changing test-account identity requires relinking',async()=>{
 await db.query('update korlix_google_ads_connections set roots=$1,root_id=$2,login_customer_id=null',[JSON.stringify([account.id]),account.id]);rootsImpl=async()=>[account.id];
 accountImpl=async(token,id,manager)=>{assert.equal(token,'private-access-token');assert.equal(id,account.id);assert.equal(manager,null);return account;};
 reportImpl=async(token,a,manager,range)=>{assert.equal(manager,null);assert.equal(a.id,account.id);assert.equal(range.days,7);return providerReport();};
 const saved=await saveLink();assert.equal(saved.link.root_id,account.id);assert.equal(saved.link.login_customer_id,null);
 await assert.rejects(db.query("update korlix_funnel_google_campaign_links set root_id='2222222222',login_customer_id=null"),/check constraint/);
 account.test_account=true;await db.query('update korlix_google_ads_connections set accounts=$1,version=nextval(\'korlix_google_ads_version_seq\')',[JSON.stringify([account])]);
 assert.equal((await link()).link_current,false);const again=await saveLink();assert.equal(again.link.account.test_account,true);const performanceResult=await performance();assert.equal(performanceResult.status,200,await performanceResult.clone().text());
});
test('Expired refresh credentials and inconsistent manager context cannot reach Google; OAuth revocation invalidates access',async()=>{
 await db.exec("update korlix_google_ads_connections set refresh_expires_at=now()+interval '30 seconds'");let d=await link();assert.equal(d.lookup_ready,false);assert.equal((await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`)).status,409);assert.equal(providerCalls,0);
 await db.exec('update korlix_google_ads_connections set refresh_expires_at=null,login_customer_id=null');d=await link();assert.equal(d.lookup_ready,false);
 await db.query('update korlix_google_ads_connections set login_customer_id=$1',[rootId]);refreshImpl=async()=>{throw new GoogleAdsAccessError();};d=await link();const r=await request(`/campaigns?days=7&fingerprint=${d.fingerprint}`);assert.equal(r.status,409);assert.equal(providerCalls,1);assert.equal((await link()).lookup_ready,false);
});
test('Google receipts cannot reuse Meta proofs; int64 campaign IDs are preserved without numeric rounding',async()=>{
 const d=await link(),row={provider_campaign_id:'456',provider_campaign_name:'Same name'},scope={actor:owner,funnel:f.id,campaign:c.id,fingerprint:d.fingerprint};
 assert.equal((await request('/save',{version:d.version,fingerprint:d.fingerprint,confirmed:true,...row,proof:metaCampaignChoiceProof(config.secret,scope,row,clock)})).status,400);
 reportImpl=async()=>{const r=providerReport();r.rows[0].campaign_id='9223372036854775807';return r;};const saved=await saveLink();assert.equal(saved.link.provider_campaign_id,'9223372036854775807');const response=await performance();assert.equal(response.status,200,await response.clone().text());const r=await response.json();assert.equal(r.row.campaign_id,'9223372036854775807');
 await assert.rejects(link('save',{version:saved.version,fingerprint:saved.fingerprint,confirmed:true,provider_campaign_id:'9223372036854775808',provider_campaign_name:'Too large'}));
});
test('Choice boundary accepts 500 complete campaigns and rejects oversized or inconsistent data',async()=>{
 const report={rows:Array.from({length:500},(_,i)=>({campaign_id:String(i+1),campaign_name:'Campaign',spend:'1.00',clicks:1,impressions:2,status:'PAUSED',channel:'SEARCH'})),totals:{spend:'500.00',clicks:500,impressions:1000},reported_campaigns:500};
 reportImpl=async()=>report;assert.equal((await choices()).out.choices.length,500);
 assert.throws(()=>linkedGoogleRows({...report,rows:[...report.rows,{...report.rows[0],campaign_id:'501'}],reported_campaigns:501}));
});
