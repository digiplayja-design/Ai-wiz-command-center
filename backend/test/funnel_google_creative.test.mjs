import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher} from '../funnels/google_ads_provider.mjs';
import {googleCreativeInput,googleCreativeAssets,googleDraftUnits} from '../funnels/google_creative.mjs';
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
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-creative${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql','20260923085331_funnel_google_creative.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:new Proxy({},{get:()=>()=>{providerCalls++;throw Error('No provider operation is allowed');}})});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const assets={headlines:['Meet our team','Explore our services','Start a conversation'],descriptions:['Tell us what your business needs.','Discover how our team can help you.'],path1:'services',path2:'talk'};
const creative=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_creative_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
async function save(a=assets){const d=await creative();return creative('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
test('Owner read is credential free, no-store, creates no row and needs no Google connection',async()=>{
 await db.exec('delete from korlix_google_ads_connections');const res=await req();assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'no-store');const d=await res.json();assert.equal(d.source,'google_search_draft');assert.equal(d.version,0);assert.equal(d.text_complete,false);assert.equal(d.ad_publishing_ready,false);assert.equal(d.context.destination,`https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_${c.id.replaceAll('-','')}`);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_creatives')).rows[0].n,0);assert.equal(providerCalls,0);
});
test('HTTP ownership, current tier and SQL privileges protect reads and writes',async()=>{
 const d=await creative();for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('',null,actor)).status,status);assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets},actor)).status,status);}
 assert.equal((await req('',null,owner,{funnel:randomUUID()})).status,404);assert.equal((await req('',null,owner,{campaign:randomUUID()})).status,404);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_creatives'),/permission denied/);await assert.rejects(creative(),/permission denied/);await db.exec('reset role;set role service_role');}
 const s=(await db.query("select p.prosecdef,p.proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_google_creatives'::regclass) rls from pg_proc p where oid='korlix_funnel_google_creative_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(s.prosecdef,false);assert(s.rls);assert.deepEqual(s.proconfig,['search_path=public, pg_temp']);
});
test('Saves incomplete and complete drafts with monotonically increasing versions',async()=>{
 let d=await save({...assets,headlines:['One headline'],descriptions:[]});assert.equal(d.text_complete,false);assert.equal(d.version,1);assert.equal(d.draft_current,true);assert.equal(d.ad_publishing_ready,false);
 const r=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets});assert.equal(r.status,200);d=await r.json();assert.equal(d.version,2);assert.equal(d.text_complete,true);assert.deepEqual(d.assets,assets);assert.deepEqual(d.saved_context,d.context);
 d=await save({headlines:[],descriptions:[],path1:'',path2:''});assert.equal(d.version,3);assert.equal(d.text_complete,false);
});
test('Text validation enforces limits, Unicode width, uniqueness and plain display paths',async()=>{
 assert.equal(googleDraftUnits('中aé'),5);
 const bad=[{...assets,headlines:Array(16).fill('a')},{...assets,headlines:['a'.repeat(31)]},{...assets,descriptions:['a'.repeat(91)]},{...assets,headlines:['中'.repeat(16)]},{...assets,headlines:['Same','same']},{...assets,headlines:['']},{...assets,headlines:[23]},{...assets,descriptions:['x\ny']},{...assets,headlines:['{keyword}']},{...assets,path1:'a/b'},{...assets,path1:'has space'},{...assets,path1:'',path2:'second'},{...assets,path1:'x?y'},{...assets,path2:'a'.repeat(16)},{...assets,path1:'x\\y'},{...assets,path1:' x'},{...assets,extra:true}];
 for(const a of bad){assert.throws(()=>googleCreativeAssets(a));assert.equal((await db.query('select korlix_google_creative_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false);}
 for(const a of [assets,{...assets,headlines:['中'.repeat(15)],descriptions:['x'.repeat(90)],path1:'x'.repeat(15)}]){googleCreativeAssets(a);assert.equal((await db.query('select korlix_google_creative_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
 const d=await creative();assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets:{...assets,headlines:['a'.repeat(31)]}})).status,400);
});
test('Malformed payloads and query injection cannot set URLs, readiness, actor or versions',async()=>{
 const d=await creative(),body={version:0,fingerprint:d.fingerprint,assets};
 for(const patch of [{version:-1},{version:1.5},{version:2147483648},{fingerprint:'x'},{actor:other},{public_base:'https://attacker.test'},{ad_publishing_ready:true},{assets:null}]){assert.throws(()=>googleCreativeInput({...body,...patch}));assert.equal((await req('/save',{...body,...patch})).status,400);}
 assert.equal((await req('?campaign_id='+randomUUID())).status,400);assert.equal((await req('/save?actor='+other,body)).status,400);
});
test('Concurrent writers cannot overwrite a newer draft and no Google operation occurs',async()=>{
 const d=await creative(),body={version:0,fingerprint:d.fingerprint,assets};const results=await Promise.all([req('/save',body),req('/save',{...body,assets:{...assets,path1:'different'}})]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);assert.equal((await creative()).version,1);assert.equal(providerCalls,0);
});
test('Campaign copy and published content stale the draft and reject saves from old context',async()=>{
 const d=await save();c=await campaign('save',{...plan,headline:'A different offer'});let next=await creative();assert.equal(next.draft_current,false);assert.equal(next.saved_context.headline,plan.headline);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,409);
 let fresh=await save();assert.equal(fresh.draft_current,true);
 f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'A changed page'}});f=await funnel('publish',{version:f.version,confirmed:true});next=await creative();assert.equal(next.draft_current,false);assert.equal(next.version,fresh.version);
});
test('Manual reports and unpublished page edits preserve context and setup reviews',async()=>{
 const setupBefore=await saveReview();let d=await save();assert.equal((await setup()).review_current,true);assert.equal((await setup()).version,setupBefore.version);
 c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Unpublished change'}});const next=await creative();assert.equal(next.draft_current,true);assert.equal(next.fingerprint,d.fingerprint);assert.equal((await setup()).review_current,true);
});
test('Archive blocks writes but retains draft; pause and downgrade update authority immediately',async()=>{
 const d=await save();c=await campaign('archive',{confirmed:true});let next=await creative();assert.equal(next.editable,false);assert.equal(next.draft_current,false);assert.equal((await req('/save',{version:next.version,fingerprint:next.fingerprint,assets})).status,400);
 c=await campaign('reopen');assert.equal((await creative()).editable,true);f=await funnel('pause',{version:f.version});next=await creative();assert.equal(next.context.page_state,'paused');assert.equal(next.ad_publishing_ready,false);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,403);
});
test('Non-Google plans are rejected and deleting a funnel cascades only its draft',async()=>{
 await save();await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await req()).status,400);await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_creatives')).rows[0].n,0);
});
test('Read and save share an owner rate limit',async()=>{for(let i=0;i<30;i++)assert.equal((await req()).status,200);const r=await req();assert.equal(r.status,429);assert.equal(r.headers.get('cache-control'),'no-store');});
