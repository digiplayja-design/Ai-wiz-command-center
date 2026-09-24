import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {googleAdsConfiguration,googleTokenCipher} from '../funnels/google_ads_provider.mjs';
import {googleKeywordsInput,googleKeywordsAssets,googleKeywordGroups} from '../funnels/google_keywords.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=googleAdsConfiguration(env),rootId='1234567890',account={id:'9876543210',name:'Growth account',currency:'USD',timezone:'UTC',manager:false,status:'ENABLED',test_account:false};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'google',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,server,base,f,c,clock=Date.now(),providerCalls=0;
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/google-keywords${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,roots,root_id,root_name,login_customer_id,accounts,selected_account,refreshed_at) values($1,$2,$3,$4,null,$5,$6,$7,$6,$8,$9,now())',[owner,binding,config.hash,JSON.stringify(googleTokenCipher(config.key).seal('private-fixture-token',`korlix-google-ads:refresh:${owner}:${binding}`)),JSON.stringify([rootId]),rootId,'Growth manager',JSON.stringify([account]),account.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922233935_funnel_google_ads_connection.sql','20260923073916_funnel_google_campaign_preparation.sql','20260923085331_funnel_google_creative.sql','20260923094201_funnel_google_creative_review.sql','20260923103256_funnel_google_keywords.sql','20260923105943_funnel_google_keyword_review.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,googleAdsProvider:new Proxy({},{get:()=>()=>{providerCalls++;throw Error('No provider operation is allowed');}})});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_google_ads_connections;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});


const empty=()=>Object.fromEntries(googleKeywordGroups.map(k=>[k,[]]));
const assets={...empty(),exact:['business support'],phrase:['local services'],negative_broad:['jobs','free']};
const keywords=(action='read',data={},actor=owner)=>rpc('korlix_funnel_google_keywords_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
async function save(a=assets){const d=await keywords();return keywords('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
test('Read without provider credentials is private, no-store, creates no row and has no readiness',async()=>{
 await db.exec('delete from korlix_google_ads_connections');const res=await req();assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'no-store');const d=await res.json();assert.equal(d.source,'google_keyword_draft');assert.equal(d.version,0);assert.equal(d.keyword_count,0);assert.equal(d.negative_count,0);assert.equal(d.ad_publishing_ready,false);assert.equal(d.context.destination,`https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_${c.id.replaceAll('-','')}`);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_keywords')).rows[0].n,0);assert.equal(providerCalls,0);
});
test('Current tier, owner, funnel, campaign, role privileges and RLS protect both routes',async()=>{
 const d=await keywords();for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('',null,actor)).status,status);assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets},actor)).status,status);}
 assert.equal((await req('',null,owner,{funnel:randomUUID()})).status,404);assert.equal((await req('',null,owner,{campaign:randomUUID()})).status,404);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_google_keywords'),/permission denied/);await assert.rejects(keywords(),/permission denied/);await db.exec('reset role;set role service_role');}
 const p=(await db.query("select prosecdef,proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_google_keywords'::regclass) rls from pg_proc where oid='korlix_funnel_google_keywords_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(p.prosecdef,false);assert(p.rls);assert.deepEqual(p.proconfig,['search_path=public, pg_temp']);
});
test('Empty, positive and negative lists roundtrip with saved context and increasing versions',async()=>{
 let d=await save(empty());assert.equal(d.version,1);assert.equal(d.keyword_count,0);assert.equal(d.draft_current,true);
 const response=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets});assert.equal(response.status,200);d=await response.json();assert.equal(d.version,2);assert.equal(d.keyword_count,2);assert.equal(d.negative_count,2);assert.deepEqual(d.assets,assets);assert.deepEqual(d.saved_context,d.context);
 d=await save({...empty(),negative_exact:['same text'],exact:['same text'],phrase:['same text']});assert.equal(d.keyword_count,2);assert.equal(d.negative_count,1);assert.equal(d.ad_publishing_ready,false);
 d=await save(empty());assert.equal(d.version,4);assert.equal(d.keyword_count,0);assert.equal(d.negative_count,0);
});
test('JavaScript and SQL enforce match lists, Unicode lengths, word counts, operators and duplicates',async()=>{
 const bad=[null,[],{}, {...assets,extra:true},{...assets,exact:null},{...assets,exact:[null]},{...assets,exact:['']},{...assets,exact:[' leading']},{...assets,exact:['two  spaces']},{...assets,exact:['a'.repeat(81)]},{...assets,exact:['中'.repeat(81)]},{...assets,exact:[Array(11).fill('word').join(' ')]},{...assets,exact:['same','SAME']},{...assets,exact:['[term]']},{...assets,exact:['"term"']},{...assets,exact:['+term']},{...assets,exact:['x\ny']},{...assets,exact:['x\ty']},{...assets,exact:['x\u200by']},{...assets,exact:['x\u00ady']},{...assets,exact:['x\\y']},{...assets,exact:Array.from({length:51},(_,i)=>'word '+i)},{...assets,exact:Array.from({length:50},(_,i)=>'word '+i),phrase:['another']},{...assets,negative_exact:Array.from({length:50},(_,i)=>'word '+i)}];
 for(const a of bad){assert.throws(()=>googleKeywordsAssets(a));assert.equal((await db.query('select korlix_google_keywords_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false,JSON.stringify(a));}
 for(const a of [empty(),assets,{...empty(),exact:['中'.repeat(80),'😀'.repeat(80),Array(10).fill('word').join(' '),"women's shoes",'A & B']},{...empty(),exact:Array.from({length:50},(_,i)=>'word '+i),negative_broad:Array.from({length:50},(_,i)=>'exclude '+i)}]){googleKeywordsAssets(a);assert.equal((await db.query('select korlix_google_keywords_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
 const d=await keywords();assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets:{...assets,exact:['[term]']}})).status,400);
 await save();await assert.rejects(db.query('update korlix_funnel_google_keywords set assets=$1',[JSON.stringify({...assets,exact:['[term]']})]),/check constraint/);
});
test('Malformed request fields cannot override actor, readiness, destination or revision',async()=>{
 const d=await keywords(),body={version:0,fingerprint:d.fingerprint,assets};
 for(const patch of [{version:-1},{version:1.5},{version:2147483648},{fingerprint:'x'},{actor:other},{public_base:'https://attacker.test'},{ad_publishing_ready:true},{assets:null}]){assert.throws(()=>googleKeywordsInput({...body,...patch}));assert.equal((await req('/save',{...body,...patch})).status,400);}
 assert.equal((await req('?actor='+other)).status,400);assert.equal((await req('/save?force=true',body)).status,400);
});
test('Concurrent saves have one winner and do not call Google',async()=>{
 const d=await keywords(),body={version:0,fingerprint:d.fingerprint,assets};const results=await Promise.all([req('/save',body),req('/save',{...body,assets:{...assets,broad:['another term']}})]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);assert.equal((await keywords()).version,1);assert.equal(providerCalls,0);
});
test('Published context and campaign changes flag stale drafts and reject earlier fingerprints',async()=>{
 const d=await save();c=await campaign('save',{...plan,audience:'A changed audience'});let next=await keywords();assert.equal(next.draft_current,false);assert.equal(next.saved_context.audience,plan.audience);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,409);
 const fresh=await save();assert.equal(fresh.draft_current,true);f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Published change'}});f=await funnel('publish',{version:f.version,confirmed:true});next=await keywords();assert.equal(next.draft_current,false);assert.equal(next.version,fresh.version);
});
test('Keyword saves preserve setup and copy reviews; reports and unpublished edits preserve keyword context',async()=>{
 const setupBefore=await saveReview();
 const creative=(action='read',data={})=>rpc('korlix_funnel_google_creative_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,public_base:'https://example.com',...data}});
 let creativeBefore=await creative();creativeBefore=await creative('save',{version:0,fingerprint:creativeBefore.fingerprint,assets:{headlines:['Meet the team','Explore services','Start here'],descriptions:['Find support for your business.','Talk with our team today.'],path1:'',path2:''}});creativeBefore=await creative('review',{version:creativeBefore.version,review_fingerprint:creativeBefore.review_fingerprint,confirmed:true});
 const d=await save();assert.deepEqual(await creative(),creativeBefore);assert.deepEqual(await setup(),setupBefore);
 c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Unpublished'}});const next=await keywords();assert.equal(next.draft_current,true);assert.equal(next.fingerprint,d.fingerprint);assert.equal((await creative()).review_current,true);assert.equal((await setup()).review_current,true);
});
test('Archive keeps read/copy while blocking saves; pause and downgrade affect state immediately',async()=>{
 await save();c=await campaign('archive',{confirmed:true});let d=await keywords();assert.equal(d.editable,false);assert.deepEqual(d.assets,assets);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,400);c=await campaign('reopen');assert.equal((await keywords()).editable,true);
 f=await funnel('pause',{version:f.version});d=await keywords();assert.equal(d.context.page_state,'paused');assert.equal(d.ad_publishing_ready,false);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,403);
});
test('Non-Google campaigns are rejected and parent deletion cascades keyword draft',async()=>{
 await save();await db.query("update korlix_funnel_campaigns set platform='meta' where id=$1",[c.id]);assert.equal((await req()).status,400);await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_google_keywords')).rows[0].n,0);
});
test('Read and save share the owner rate limit',async()=>{for(let i=0;i<30;i++)assert.equal((await req()).status,200);const r=await req('/save',{version:0,fingerprint:'a'.repeat(64),assets});assert.equal(r.status,429);assert.equal(r.headers.get('cache-control'),'no-store');});

async function reviewKeywords(){const d=await keywords();return keywords('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});}
test('K167 saves exact review, exposes no provider approval, and clear preserves draft revision and assets',async()=>{
 const draft=await save(),beforeSetup=await setup();assert.equal(draft.review_ready,true);assert.equal(draft.review_current,false);assert.equal(draft.draft_revision,1);
 const response=await req('/review',{version:draft.version,review_fingerprint:draft.review_fingerprint,confirmed:true});assert.equal(response.status,200);let d=await response.json();assert.equal(d.version,2);assert.equal(d.draft_revision,1);assert.equal(d.review_current,true);assert.equal(d.ad_publishing_ready,false);assert.deepEqual(d.reviewed_snapshot,{assets,context:draft.saved_context,draft_revision:1,saved_at:draft.updated_at});assert.equal(d.updated_at,draft.updated_at);
 d=await (await req('/clear-review',{version:d.version,confirmed:true})).json();assert.equal(d.version,3);assert.equal(d.review_current,false);assert.equal(d.reviewed_snapshot,null);assert.equal(d.reviewed_at,null);assert.equal(d.draft_revision,1);assert.deepEqual(d.assets,assets);assert.deepEqual(await setup(),beforeSetup);assert.equal(providerCalls,0);
});
test('K167 every save stales the saved review even when asset text is unchanged',async()=>{
 await save();const reviewed=await reviewKeywords();let next=await save();assert.equal(next.draft_revision,2);assert.equal(next.version,3);assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot,reviewed.reviewed_snapshot);assert.notEqual(next.review_fingerprint,reviewed.review_fingerprint);
 const r=await req('/review',{version:next.version,review_fingerprint:reviewed.review_fingerprint,confirmed:true});assert.equal(r.status,409);
 next=await reviewKeywords();assert.equal(next.reviewed_snapshot.draft_revision,2);assert.equal(next.review_current,true);
});
test('K167 review requires current positive saved keywords, a published page and reviewed plan',async()=>{
 let d=await keywords();assert.equal(d.review_ready,false);assert.equal((await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true})).status,400);
 await save({...empty(),negative_broad:['jobs']});assert.equal((await keywords()).review_ready,false);await assert.rejects(reviewKeywords(),/current positive keywords/);
 await save();c=await campaign('save',{...plan,headline:'Changed'});d=await keywords();assert.equal(d.review_ready,false);assert.equal(d.review_checks.current_context,false);await save();assert.equal((await keywords()).review_checks.plan_reviewed,false);await assert.rejects(reviewKeywords(),/review the campaign/);
 c=await campaign('review',{confirmed:true});await save();assert.equal((await keywords()).review_ready,true);f=await funnel('pause',{version:f.version});await save();d=await keywords();assert.equal(d.review_checks.page_published,false);await assert.rejects(reviewKeywords(),/publish the page/);
});
test('K167 review stays current through reporting and unpublished edits, but stales on published changes',async()=>{
 await save();const d=await reviewKeywords();c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:1,impressions:2,note:'Fixture'});f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Another draft'}});let next=await keywords();assert.equal(next.review_current,true);assert.equal(next.review_fingerprint,d.review_fingerprint);f=await funnel('publish',{version:f.version,confirmed:true});next=await keywords();assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot,d.reviewed_snapshot);
});
test('K167 review mutations reject forged confirmations, snapshots, query fields and stale versions',async()=>{
 await save();const d=await keywords(),body={version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true};
 for(const patch of [{confirmed:false},{confirmed:'true'},{version:-1},{version:1.5},{review_fingerprint:'x'},{reviewed_snapshot:{}},{assets},{actor:other}])assert.equal((await req('/review',{...body,...patch})).status,400);
 assert.equal((await req('/clear-review',{version:d.version,confirmed:false})).status,400);assert.equal((await req('/clear-review',{version:d.version,confirmed:true,review_fingerprint:d.review_fingerprint})).status,400);
 await reviewKeywords();assert.equal((await req('/review',body)).status,409);assert.equal((await req('/clear-review',{version:d.version,confirmed:true})).status,409);
});
test('K167 current ownership and tier protect both review routes; archived review can be cleared',async()=>{
 await save();const d=await reviewKeywords();for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true},actor)).status,status);assert.equal((await req('/clear-review',{version:d.version,confirmed:true},actor)).status,status);}
 c=await campaign('archive',{confirmed:true});assert.equal((await keywords()).review_current,false);await assert.rejects(reviewKeywords(),/current positive keywords/);let cleared=await keywords('clear_review',{version:d.version,confirmed:true});assert.equal(cleared.reviewed_snapshot,null);assert.deepEqual(cleared.assets,assets);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req('/clear-review',{version:cleared.version,confirmed:true})).status,403);
});
test('K167 concurrent save and review never marks a different revision as reviewed',async()=>{
 await save();const d=await keywords();const results=await Promise.all([req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true}),req('/save',{version:d.version,fingerprint:d.fingerprint,assets:{...assets,broad:['another']}})]);assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);const current=await keywords();assert.equal(current.review_current,current.reviewed_snapshot!==null);if(current.review_current)assert.deepEqual(current.assets,assets);else assert.deepEqual(current.assets.broad,['another']);assert.equal(providerCalls,0);
});

test('K167 legal maximum Unicode keywords and large context fit immutable review snapshot',async()=>{
 c=await campaign('save',{...plan,body:'😀'.repeat(1000),audience:'😀'.repeat(500)});c=await campaign('review',{confirmed:true});
 const terms=Array.from({length:50},(_,i)=>'😀'.repeat(78)+String(i).padStart(2,'0'));
 const d=await save({...empty(),exact:terms,negative_broad:terms});const reviewed=await reviewKeywords();
 assert.equal(reviewed.review_current,true);assert.deepEqual(reviewed.reviewed_snapshot.assets,d.assets);assert.equal(reviewed.reviewed_snapshot.saved_at,d.updated_at);
 const size=Buffer.byteLength(JSON.stringify(reviewed.reviewed_snapshot));assert(size>32768);assert(size<98304);assert.equal(providerCalls,0);
 await assert.rejects(keywords('review',{version:reviewed.version,review_fingerprint:reviewed.review_fingerprint,confirmed:'true'}),/confirm/);
 for(const broken of [{...reviewed.reviewed_snapshot,saved_at:null},{...reviewed.reviewed_snapshot,extra:1},{assets:d.assets,context:d.context,draft_revision:1}])await assert.rejects(db.query('update korlix_funnel_google_keywords set reviewed_snapshot=$1',[JSON.stringify(broken)]),/check constraint/);
});
