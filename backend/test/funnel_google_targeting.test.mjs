import test from 'node:test';
import {searchGoogleLocations,googleLocationsValid} from '../funnels/google_locations.mjs';
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
 // Prove the additive migration preserves an existing revision-2 draft.
 f=await funnel('create',{name:'Legacy',slug:'legacy',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);await save();await save();
 const legacy=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923120825_funnel_google_targeting_review.sql',import.meta.url),'utf8'));
 const upgraded=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 assert.equal(upgraded.draft_revision,2);assert.equal(upgraded.reviewed_at,null);assert.equal(upgraded.reviewed_snapshot,null);assert.equal(upgraded.review_fingerprint,null);
 for(const key of ['draft_revision','reviewed_at','reviewed_snapshot','review_fingerprint'])delete upgraded[key];assert.deepEqual(upgraded,legacy);
 // K174 preserves existing reviewed country drafts byte-for-byte.
 c=await campaign('review',{confirmed:true});await save();await reviewTargeting();
 const beforeRadius=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 const beforeRead=await targeting();
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923153540_funnel_google_radius.sql',import.meta.url),'utf8'));
 assert.deepEqual((await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row,beforeRadius);
 const afterRead=await targeting();assert.equal(afterRead.radius_supported,true);delete afterRead.radius_supported;assert.deepEqual(afterRead,beforeRead);
 const beforeLocations=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 const beforeLocationRead=await targeting();
 await db.exec(await readFile(new URL('../../supabase/migrations/20260923172253_funnel_google_locations.sql',import.meta.url),'utf8'));
 assert.deepEqual((await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row,beforeLocations);
 const afterLocationRead=await targeting();assert.equal(afterLocationRead.locations_supported,true);assert.equal(afterLocationRead.location_catalog_version,'google-locations-2026-08-12');delete afterLocationRead.locations_supported;delete afterLocationRead.location_catalog_version;assert.deepEqual(afterLocationRead,beforeLocationRead);
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

async function reviewTargeting(){const d=await targeting();return targeting('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});}
test('K169 review snapshots exact choices, labels, reference version and original save time; clearing preserves draft',async()=>{
 const draft=await save(),setupBefore=await setup();assert.equal(draft.review_ready,true);assert.equal(draft.review_current,false);assert.equal(draft.draft_revision,1);
 const response=await req('/review',{version:draft.version,review_fingerprint:draft.review_fingerprint,confirmed:true});assert.equal(response.status,200);let d=await response.json();assert.equal(d.version,2);assert.equal(d.draft_revision,1);assert.equal(d.review_current,true);assert.equal(d.ad_publishing_ready,false);assert.deepEqual(d.reviewed_snapshot,{assets,context:draft.saved_context,labels:draft.saved_labels,catalog_version:catalog.version,draft_revision:1,saved_at:draft.updated_at});assert.equal(d.updated_at,draft.updated_at);assert.deepEqual(d.saved_labels,draft.saved_labels);
 d=await (await req('/clear-review',{version:d.version,confirmed:true})).json();assert.equal(d.version,3);assert.equal(d.review_current,false);assert.equal(d.reviewed_snapshot,null);assert.equal(d.reviewed_at,null);assert.equal(d.draft_revision,1);assert.deepEqual(d.assets,assets);assert.equal(d.updated_at,draft.updated_at);assert.deepEqual(await setup(),setupBefore);assert.equal(providerCalls,0);
});
test('K169 every save stales a review even when choices are identical; old records stay intact',async()=>{
 await save();const reviewed=await reviewTargeting();let next=await save();assert.equal(next.draft_revision,2);assert.equal(next.version,3);assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot,reviewed.reviewed_snapshot);assert.notEqual(next.review_fingerprint,reviewed.review_fingerprint);
 assert.equal((await req('/review',{version:next.version,review_fingerprint:reviewed.review_fingerprint,confirmed:true})).status,409);
 next=await reviewTargeting();assert.equal(next.reviewed_snapshot.draft_revision,2);assert.equal(next.review_current,true);
 next=await save(empty());assert.equal(next.review_ready,false);assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot.assets,assets);assert.equal(next.reviewed_snapshot.draft_revision,2);
});
test('K169 review requires all explicit choices, a saved current context, a published page and a reviewed plan',async()=>{
 let d=await targeting();assert.equal(d.review_ready,false);assert.equal((await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true})).status,400);
 for(const patch of [{countries:[]},{content_languages:[]},{location_mode:'undecided'},{bidding:'undecided'}]){await save({...assets,...patch});d=await targeting();assert.equal(d.review_checks.complete_choices,false);await assert.rejects(reviewTargeting(),/complete current targeting/);}
 await save();c=await campaign('save',{...plan,headline:'Changed'});d=await targeting();assert.equal(d.review_ready,false);assert.equal(d.review_checks.current_context,false);await save();assert.equal((await targeting()).review_checks.plan_reviewed,false);await assert.rejects(reviewTargeting(),/review the campaign/);
 c=await campaign('review',{confirmed:true});await save();assert.equal((await targeting()).review_ready,true);f=await funnel('pause',{version:f.version});await save();assert.equal((await targeting()).review_checks.page_published,false);await assert.rejects(reviewTargeting(),/publish the page/);
});
test('K169 reports and unpublished edits preserve review; a published change invalidates review with snapshot intact',async()=>{
 await save();const d=await reviewTargeting();c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Unpublished'}});let next=await targeting();assert.equal(next.review_current,true);assert.equal(next.review_fingerprint,d.review_fingerprint);f=await funnel('publish',{version:f.version,confirmed:true});next=await targeting();assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot,d.reviewed_snapshot);
});
test('K169 review mutations reject forged confirmations, snapshots, query parameters and revisions',async()=>{
 await save();const d=await targeting(),body={version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true};
 for(const patch of [{confirmed:false},{confirmed:'true'},{confirmed:1},{confirmed:null},{reviewed_snapshot:{}},{actor:other},{version:-1},{review_fingerprint:'bad'}])assert.equal((await req('/review',{...body,...patch})).status,400);
 for(const patch of [{confirmed:'true'},{confirmed:false},{snapshot:{}},{review_fingerprint:d.review_fingerprint}])assert.equal((await req('/clear-review',{version:d.version,confirmed:true,...patch})).status,400);
 assert.equal((await req('/review?force=true',body)).status,400);assert.equal((await req('/review',{...body,version:d.version+1})).status,409);
 await assert.rejects(targeting('review',{...body,confirmed:'true'}),/confirm/);await assert.rejects(targeting('clear_review',{version:d.version,confirmed:1}),/confirm/);
 await reviewTargeting();await assert.rejects(db.query("update korlix_funnel_google_targeting set reviewed_snapshot=reviewed_snapshot||'{\"extra\":true}'::jsonb"),/check constraint/);
});
test('K169 all review routes enforce current ownership/tier; archive blocks review and permits confirmed clearing',async()=>{
 await save();const d=await reviewTargeting(),body={version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true};
 for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('/review',body,actor)).status,status);assert.equal((await req('/clear-review',{version:d.version,confirmed:true},actor)).status,status);}
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req('/review',body)).status,403);assert.equal((await req('/clear-review',{version:d.version,confirmed:true})).status,403);await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 c=await campaign('archive',{confirmed:true});const archived=await targeting();assert.equal(archived.review_current,false);assert.equal(archived.review_ready,false);await assert.rejects(reviewTargeting(),/review the campaign/);const cleared=await targeting('clear_review',{version:archived.version,confirmed:true});assert.equal(cleared.reviewed_snapshot,null);assert.deepEqual(cleared.assets,assets);assert.equal(cleared.updated_at,d.updated_at);
});
test('K169 review/save races have one winner; all four routes share a rate limit',async()=>{
 const d=await save();const responses=await Promise.all([req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true}),req('/save',{version:d.version,fingerprint:d.fingerprint,assets:{...assets,countries:['JM']}})]);assert.deepEqual(responses.map(x=>x.status).sort(),[200,409]);assert.equal(providerCalls,0);
 clock+=60000;for(let i=0;i<30;i++)assert.equal((await req()).status,200);assert.equal((await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true})).status,429);assert.equal((await req('/clear-review',{version:d.version,confirmed:true})).status,429);
});

const radius={label:'Columbus service area',latitude_micro:39961176,longitude_micro:-82998794,radius_meters:15000};
const city={id:'1023640',name:'Columbus,Ohio,United States',country:'US',type:'City'};
const region={id:'21168',name:'Ohio,United States',country:'US',type:'State'};
const locationAssets=(locations=[city])=>({...assets,countries:[],geo_locations:locations});
test('K176 reference search disambiguates cities, filters regions, handles accents and bounds results',()=>{
 const r=searchGoogleLocations({q:'Columbus',country:'US',kind:'all'});assert.ok(r.locations.some(x=>x.id===city.id));assert.ok(r.locations.length>1);assert.ok(r.locations.every(x=>x.country==='US'));
 assert.deepEqual(searchGoogleLocations({q:'Columbus Ohio',country:'US',kind:'city'}).locations[0],city);
 assert.deepEqual(searchGoogleLocations({q:'Ohio',country:'US',kind:'region'}).locations,[region]);
 assert.ok(searchGoogleLocations({q:'Sao Paulo',country:'BR',kind:'city'}).locations.some(x=>x.name.startsWith('Sao Paulo,')));
 const broad=searchGoogleLocations({q:'United States',country:'US',kind:'all'});assert.equal(broad.locations.length,30);assert.equal(broad.more,true);
 assert.equal(searchGoogleLocations({q:'no-such-location-fixture',country:'US',kind:'all'}).locations.length,0);
 for(const q of [{q:'x',country:'US',kind:'all'},{q:'x'.repeat(81),country:'US',kind:'all'},{q:'Ohio',country:'XX',kind:'all'},{q:'Ohio',country:'US',kind:'postal'},{q:' Ohio',country:'US',kind:'all'},{q:'Ohio',country:'US',kind:'all',limit:100},{q:['Ohio'],country:'US',kind:'all'}])assert.throws(()=>searchGoogleLocations(q));
});
test('K176 location search enforces owner, tier, campaign scope and no-store without provider calls or writes',async()=>{
 await db.exec('delete from korlix_google_ads_connections');
 const query='/locations?q=Columbus%20Ohio&country=US&kind=city';
 for(const [actor,status] of [['',401],[other,404],[basic,403],[owner,200]]){const r=await req(query,null,actor);assert.equal(r.status,status);assert.equal(r.headers.get('cache-control'),'no-store');if(status===200)assert.deepEqual((await r.json()).locations[0],city);}
 assert.equal((await req(query,null,owner,{campaign:randomUUID()})).status,404);
 for(const q of ['/locations?q=Ohio&country=US&kind=all&force=true','/locations?q=Ohio&q=Texas&country=US&kind=all','/locations?q=x&country=US&kind=all'])assert.equal((await req(q)).status,400);
 assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_targeting')).rows[0].n,0);assert.equal(providerCalls,0);
 for(let i=0;i<25;i++)assert.equal((await req(query)).status,200);
 assert.equal((await req()).status,429);
});
test('K176 HTTP saves reject forged reference identity, while SQL enforces shape, modes and exclusions',async()=>{
 const d=await targeting();
 for(const a of [locationAssets([{...city,id:'9999999999'}]),locationAssets([{...city,name:'Fake name'}]),locationAssets([{...city,country:'JM'}]),locationAssets([{...city,type:'State'}])]){assert.throws(()=>googleTargetingAssets(a));assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets:a})).status,400);}
 const invalid=[locationAssets(null),locationAssets([null]),locationAssets([city,city]),locationAssets([{...city,extra:true}]),locationAssets([{...city,id:1023640}]),locationAssets([{...city,name:'<Ohio>'}]),locationAssets([{...city,country:'XX'}]),locationAssets([{...city,type:'Airport'}]),{...locationAssets(),countries:['US']},{...locationAssets(),proximities:[]},{...locationAssets(),excluded_countries:['US']},locationAssets(Array(21).fill(city))];
 for(const a of invalid){assert.throws(()=>googleTargetingAssets(a));assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false);}
 assert.equal(googleLocationsValid([city,region]),true);
 for(const a of [locationAssets([]),locationAssets([city,region])]){googleTargetingAssets(a);assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
 const r=await db.query("select prosecdef,proconfig,has_function_privilege('anon',oid,'execute') anon,has_function_privilege('authenticated',oid,'execute') authenticated,has_function_privilege('service_role',oid,'execute') service from pg_proc where proname='korlix_google_location_valid_v1'");assert.deepEqual(r.rows,[{prosecdef:false,proconfig:['search_path=public, pg_temp'],anon:false,authenticated:false,service:true}]);
});
test('K176 named locations save and review with exact historical values and preserve other target modes',async()=>{
 await save(radiusAssets());const radiusReview=await reviewTargeting();
 let d=await (await req('/save',{version:radiusReview.version,fingerprint:radiusReview.fingerprint,assets:locationAssets([city,region])})).json();assert.equal(d.draft_complete,true);assert.equal(d.review_current,false);assert.deepEqual(d.reviewed_snapshot,radiusReview.reviewed_snapshot);
 d=await reviewTargeting();assert.equal(d.review_current,true);assert.deepEqual(d.reviewed_snapshot.assets.geo_locations,[city,region]);assert.equal(d.ad_publishing_ready,false);
 const snapshot=d.reviewed_snapshot;d=await save(locationAssets());assert.equal(d.review_current,false);assert.deepEqual(d.reviewed_snapshot,snapshot);
 d=await save(locationAssets([]));assert.equal(d.draft_complete,false);assert.equal(d.review_ready,false);await assert.rejects(reviewTargeting(),/complete current targeting/);
 await save(locationAssets());await reviewTargeting();const before=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 const preflight=await rpc('korlix_funnel_google_preflight_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id,configured:false,config_hash:config.hash,public_base:'https://example.com'}});assert.deepEqual(preflight.targeting.assets.geo_locations,[city]);assert.equal(preflight.targeting.review_current,true);assert.deepEqual((await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row,before);assert.equal(providerCalls,0);
});
const radiusAssets=(areas=[radius])=>({...assets,countries:[],proximities:areas});
test('K174 API and SQL agree on radius shape, precision, bounds, labels, duplicates and target modes',async()=>{
 const malformed=[null,[],{}, {...radius,extra:1},{...radius,label:''},{...radius,label:' test'},{...radius,label:'test '},{...radius,label:'x'.repeat(81)},{...radius,label:'a\nb'},{...radius,label:'a\u0085b'},{...radius,label:'a\u2028b'},{...radius,label:'<point>'},{...radius,latitude_micro:'1'},{...radius,latitude_micro:90000001},{...radius,latitude_micro:-90000001},{...radius,latitude_micro:1.5},{...radius,longitude_micro:180000001},{...radius,longitude_micro:-180000001},{...radius,radius_meters:999},{...radius,radius_meters:200001},{...radius,radius_meters:1000.1}];
 const bad=malformed.map(r=>radiusAssets([r]));bad.push({...assets,proximities:[radius]},radiusAssets([radius,{...radius,label:'duplicate point'}]),radiusAssets(Array.from({length:11},(_,i)=>({...radius,latitude_micro:i}))),radiusAssets(null),radiusAssets({}));
 const d=await targeting();
 for(const a of bad){assert.throws(()=>googleTargetingAssets(a));assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false);assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets:a})).status,400);clock+=60000;}
 for(const a of [radiusAssets(),radiusAssets([]),radiusAssets([{...radius,latitude_micro:-90000000,longitude_micro:180000000,radius_meters:1000}]),radiusAssets([{...radius,latitude_micro:90000000,longitude_micro:-180000000,radius_meters:200000,label:'🌍'.repeat(80)}]),radiusAssets(Array.from({length:10},(_,i)=>({...radius,latitude_micro:i})))]){googleTargetingAssets(a);assert.equal((await db.query('select korlix_google_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
});
test('K174 radius HTTP saves and reviews work without provider activation and preserve exact coordinates',async()=>{
 await db.exec('delete from korlix_google_ads_connections');let d=await targeting();assert.equal(d.radius_supported,true);
 const r=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets:radiusAssets()});assert.equal(r.status,200);d=await r.json();assert.deepEqual(d.assets,radiusAssets());assert.equal(d.draft_complete,true);assert.equal(d.review_ready,true);assert.equal(d.ad_publishing_ready,false);
 const reviewed=await (await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true})).json();assert.equal(reviewed.review_current,true);assert.deepEqual(reviewed.reviewed_snapshot.assets.proximities,[radius]);assert.deepEqual(reviewed.saved_labels.countries,{CA:'Canada'});assert.equal(providerCalls,0);
});
test('K174 radius edits and switching target type invalidate only the targeting review with historical values intact',async()=>{
 await save();const countryReview=await reviewTargeting();let d=await save(radiusAssets());assert.equal(d.review_current,false);assert.deepEqual(d.reviewed_snapshot,countryReview.reviewed_snapshot);
 const firstRadius=await reviewTargeting();d=await save(radiusAssets([{...radius,radius_meters:15750}]));assert.equal(d.review_current,false);assert.deepEqual(d.reviewed_snapshot.assets.proximities,[radius]);assert.notEqual(d.review_fingerprint,firstRadius.review_fingerprint);
 const secondRadius=await reviewTargeting();d=await save();assert.equal(d.review_current,false);assert.deepEqual(d.reviewed_snapshot,secondRadius.reviewed_snapshot);assert.deepEqual(d.assets,assets);
 d=await save(radiusAssets([]));assert.equal(d.draft_complete,false);assert.equal(d.review_ready,false);await assert.rejects(reviewTargeting(),/complete current targeting/);
});
test('K174 combined preflight returns saved radius details and current targeting review without writes',async()=>{
 await save(radiusAssets());await reviewTargeting();const before=(await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row;
 const d=await rpc('korlix_funnel_google_preflight_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id,configured:false,config_hash:config.hash,public_base:'https://example.com'}});
 assert.equal(d.checks.targeting_reviewed,true);assert.equal(d.checks.setup_reviewed,false);assert.equal(d.preparation_complete,false);assert.equal(d.ad_publishing_ready,false);assert.deepEqual(d.targeting.assets.proximities,[radius]);assert.deepEqual((await db.query('select to_jsonb(t) row from korlix_funnel_google_targeting t')).rows[0].row,before);assert.equal(providerCalls,0);
});
test('K174 nested radius changes obey optimistic concurrency and preserve country-only callers',async()=>{
 const d=await save(radiusAssets()),body={version:d.version,fingerprint:d.fingerprint,assets:radiusAssets([{...radius,longitude_micro:-83000000}])};
 const responses=await Promise.all([req('/save',body),req('/save',{...body,assets})]);assert.deepEqual(responses.map(x=>x.status).sort(),[200,409]);assert.equal((await req('/save',{...body,assets})).status,409);
 const fresh=await targeting();const r=await req('/save',{version:fresh.version,fingerprint:fresh.fingerprint,assets});assert.equal(r.status,200);assert.deepEqual((await r.json()).assets,assets);
});
test('K174 radius validation function and draft constraints stay private and reject malformed stored assets',async()=>{
 await save(radiusAssets());await reviewTargeting();
 await assert.rejects(db.query('update korlix_funnel_google_targeting set assets=$1',[JSON.stringify(radiusAssets([{...radius,radius_meters:0}]))]),/check constraint/);
 await assert.rejects(db.query("update korlix_funnel_google_targeting set reviewed_snapshot=jsonb_set(reviewed_snapshot,'{assets,proximities,0,latitude_micro}','90000001')"),/check constraint/);
 const fn=(await db.query("select prosecdef,proconfig from pg_proc where proname='korlix_google_radius_valid_v1'")).rows[0];assert.equal(fn.prosecdef,false);assert.deepEqual(fn.proconfig,['search_path=public, pg_temp']);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select korlix_google_radius_valid_v1($1)',[JSON.stringify(radius)]),/permission denied/);await db.exec('reset role;set role service_role');}
 for(const [actor,status] of [['',401],[other,404],[basic,403]])assert.equal((await req('/save',{version:0,fingerprint:'a'.repeat(64),assets:radiusAssets()},actor)).status,status);
});
