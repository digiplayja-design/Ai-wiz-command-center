import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher} from '../funnels/meta.mjs';
import {metaTargetingAssets,metaTargetingInput,metaTargetingReviewInput,metaTargetingCatalog} from '../funnels/meta_targeting.mjs';
import {normalizeImage} from '../funnels/images.mjs';
import sharp from 'sharp';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-secret-not-real',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=metaConfiguration(env),account={id:'act_123',name:'Growth account',currency:'USD',timezone:'UTC',status:1},page={id:'98765432101234567890',name:'Growth Page',category:'Education'};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,server,base,f,c,clock=Date.now(),providerCalls=0;
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/meta-targeting${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,pages,selected_page,refreshed_at,pages_refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,$8,$9,now(),now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id,JSON.stringify([page]),page.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923011934_funnel_meta_page_identity.sql','20260923015323_funnel_meta_campaign_preparation.sql','20260922194529_funnel_images.sql','20260923133926_funnel_meta_creative.sql','20260923140507_funnel_meta_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,metaProvider:new Proxy({},{get:()=>()=>{providerCalls++;throw Error('No provider operation is allowed');}})});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_meta_connections;delete from korlix_funnel_images;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const blank={primary_text:'',headline:'',description:'',cta:'LEARN_MORE',image_id:null,image_alt:''};
const assets={...blank,primary_text:'Plan your next step with our team.',headline:'Meet our team',description:'Local support for your business.'};
const creative=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_creative_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
async function save(a=assets){const d=await creative();return creative('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
async function image(actor=owner){const n=await normalizeImage(await sharp({create:{width:600,height:400,channels:3,background:'#17a9b0'}}).png().toBuffer());return rpc('korlix_funnel_images_v1',{p_actor:actor,p_action:'put',p_data:{label:'Our team.png',width:n.width,height:n.height,sha256:n.sha256,content:n.bytes.toString('base64')}});}
const imageCommand=(action,id=null,actor=owner)=>rpc('korlix_funnel_images_v1',{p_actor:actor,p_action:action,p_id:id,p_data:{confirmed:true}});

const empty={countries:[],age_min:18,age_max:65,placements:'undecided',categories:['UNDECIDED']};
const choices={countries:['US','JM'],age_min:25,age_max:65,placements:'facebook_feed',categories:['NONE']};
const targeting=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_targeting_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
async function saveTarget(a=choices){const d=await targeting();return targeting('save',{version:d.version,fingerprint:d.fingerprint,assets:a});}
async function completeCreative(){const a=await image();return save({...assets,image_id:a.id,image_alt:'Team'});}
async function review(){const d=await targeting();return targeting('review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});}
async function ready(){await completeCreative();return saveTarget();}
test('Read is owner scoped, credential free, no-store and creates no draft or review',async()=>{
 await db.exec('delete from korlix_meta_connections');const r=await req();assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');const d=await r.json();assert.equal(d.source,'meta_targeting_draft');assert.equal(d.version,0);assert.deepEqual(d.assets,empty);assert.equal(d.ad_publishing_ready,false);assert.equal(d.review_ready,false);assert.equal(d.catalog.countries.length,249);assert.deepEqual(d.catalog,metaTargetingCatalog);assert.equal((await db.query('select count(*)::int n from korlix_funnel_meta_targeting')).rows[0].n,0);assert.equal(providerCalls,0);
 for(const secret of ['sealed','config_hash','meta_user_id','binding_id','private-fixture-token'])assert(!JSON.stringify(d).includes(secret));
});
test('Reads, saves and reviews enforce ownership, current tier, platform and private SQL grants',async()=>{
 const d=await targeting();for(const [actor,status] of [['',401],[other,404],[basic,403]])for(const [suffix,body] of [['',null],['/save',{version:0,fingerprint:d.fingerprint,assets:choices}],['/review',{version:0,review_fingerprint:d.review_fingerprint,confirmed:true}],['/clear-review',{version:0,confirmed:true}]])assert.equal((await req(suffix,body,actor)).status,status);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_meta_targeting'),/permission denied/);await assert.rejects(targeting(),/permission denied/);await db.exec('reset role;set role service_role');}
 const schema=(await db.query("select p.prosecdef,p.proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_meta_targeting'::regclass) rls from pg_proc p where oid='korlix_funnel_meta_targeting_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(schema.prosecdef,false);assert(schema.rls);assert.deepEqual(schema.proconfig,['search_path=public, pg_temp']);
 await db.query("update korlix_funnel_campaigns set platform='google' where id=$1",[c.id]);assert.equal((await req()).status,400);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);
});
test('Country, category, age and placement validation matches API and SQL',async()=>{
 const bad=[null,{},[],{...choices,extra:true},{...choices,countries:['ZZ']},{...choices,countries:['US','US']},{...choices,countries:['us']},{...choices,countries:[3]},{...choices,countries:metaTargetingCatalog.countries.slice(0,21).map(v=>v.code)},{...choices,age_min:17},{...choices,age_min:25.5},{...choices,age_min:'25'},{...choices,age_min:60,age_max:50},{...choices,age_max:66},{...choices,placements:'instagram'}, {...choices,categories:[]},{...choices,categories:['NONE','HOUSING']},{...choices,categories:['HOUSING','HOUSING']},{...choices,categories:['UNKNOWN']},{...choices,categories:['HOUSING']},{...choices,categories:['UNDECIDED']}];
 for(const a of bad){assert.throws(()=>metaTargetingAssets(a));assert.equal((await db.query('select korlix_meta_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false);}
 for(const a of [empty,choices,{...choices,age_min:18,categories:['HOUSING','EMPLOYMENT']},{...choices,age_min:65,age_max:65},{...choices,placements:'automatic'}]){metaTargetingAssets(a);assert.equal((await db.query('select korlix_meta_targeting_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
});
test('Strict request shapes cannot forge versions, readiness, contexts or actors',async()=>{
 const d=await targeting(),b={version:0,fingerprint:d.fingerprint,assets:choices};
 for(const patch of [{version:-1},{version:1.5},{version:2147483648},{fingerprint:'bad'},{actor:other},{public_base:'https://bad.test'},{configured:true},{review_current:true},{assets:null}]){assert.throws(()=>metaTargetingInput({...b,...patch}));assert.equal((await req('/save',{...b,...patch})).status,400);}
 for(const a of ['review','clear_review']){const body={version:0,confirmed:true,...(a==='review'?{review_fingerprint:d.review_fingerprint}:{})};for(const patch of [{confirmed:'true'},{version:1.5},{extra:true}])assert.throws(()=>metaTargetingReviewInput(a,{...body,...patch}));}
 assert.equal((await req('?actor='+other)).status,400);assert.equal((await req('/save?actor='+other,b)).status,400);await assert.rejects(targeting(null),/Unknown/);
});
test('Incomplete and complete saves preserve revision history and snapshot country labels',async()=>{
 let d=await saveTarget(empty);assert.equal(d.version,1);assert.equal(d.draft_revision,1);assert.equal(d.draft_complete,false);assert.equal(d.review_ready,false);d=await saveTarget();assert.equal(d.version,2);assert.equal(d.draft_revision,2);assert.equal(d.draft_complete,true);assert.equal(d.draft_current,true);assert.deepEqual(d.saved_labels,{US:'United States',JM:'Jamaica'});assert.equal(d.review_ready,false);assert.equal(d.review_checks.creative_saved,false);
 const r=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets:choices});assert.equal(r.status,200);assert.deepEqual((await targeting()).assets,choices);
});
test('Combined review covers current creative and targeting without provider activation',async()=>{
 await db.exec('delete from korlix_meta_connections');const d=await ready(),before=await creative();assert.equal(d.review_ready,true);assert.equal(d.creative.setup.ready_for_review,false);
 const result=await req('/review',{version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true});assert.equal(result.status,200);const r=await result.json();assert.equal(r.version,2);assert.equal(r.draft_revision,1);assert.equal(r.updated_at,d.updated_at);assert.equal(r.review_current,true);assert.equal(r.ad_publishing_ready,false);assert.deepEqual(r.reviewed_snapshot.assets,choices);assert.deepEqual(r.reviewed_snapshot.creative.assets,before.assets);assert.deepEqual(r.reviewed_snapshot.creative.image,before.image);assert.equal(r.reviewed_snapshot.creative.version,before.version);assert.deepEqual((await creative()),before);assert.equal(providerCalls,0);
});
test('Creative edits stale a review but not targeting; old review keeps the original creative',async()=>{
 await ready();const r=await review(),old=r.reviewed_snapshot;await save({...r.creative.assets,headline:'Updated headline'});const next=await targeting();assert.equal(next.draft_current,true);assert.equal(next.review_ready,true);assert.equal(next.review_current,false);assert.deepEqual(next.reviewed_snapshot,old);
 assert.equal((await req('/review',{version:r.version,review_fingerprint:r.review_fingerprint,confirmed:true})).status,409);assert.equal((await review()).review_current,true);
});
test('Target changes and identical resaves invalidate review through draft revision',async()=>{
 await ready();let r=await review();const old=r.reviewed_snapshot;let d=await saveTarget();assert.equal(d.review_current,false);assert.equal(d.draft_revision,2);assert.deepEqual(d.reviewed_snapshot,old);r=await review();assert.equal(r.review_current,true);d=await saveTarget({...choices,countries:['CA'],placements:'automatic'});assert.equal(d.review_current,false);assert.equal(d.saved_labels.CA,'Canada');assert.deepEqual(d.reviewed_snapshot.assets,choices);
});
test('Campaign, public page and Page identity changes stale preparation and reject old saves',async()=>{
 const d=await ready();await review();c=await campaign('save',{...plan,headline:'New offer'});let r=await targeting();assert.equal(r.draft_current,false);assert.equal(r.review_current,false);assert.equal(r.creative.draft_current,false);assert.equal((await req('/save',{version:r.version,fingerprint:d.fingerprint,assets:choices})).status,409);
 c=await campaign('review',{confirmed:true});await completeCreative();await saveTarget();await review();f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'New public page'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await targeting()).review_current,false);
 await completeCreative();await saveTarget();await db.query('update korlix_meta_connections set selected_page=null where user_id=$1',[owner]);assert.equal((await targeting()).draft_current,false);
});
test('Unpublished changes and manual reports preserve review; archived campaigns are read only',async()=>{
 await ready();const d=await review();c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:100,clicks:2,impressions:10,note:'Owner report'});f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'Unpublished edit'}});assert.equal((await targeting()).review_current,true);
 c=await campaign('archive',{confirmed:true});const next=await targeting();assert.equal(next.editable,false);assert.equal(next.review_current,false);await assert.rejects(saveTarget(),/Reopen/);await assert.rejects(review(),/Save complete/);const cleared=await targeting('clear_review',{version:d.version,confirmed:true});assert.equal(cleared.reviewed_snapshot,null);
});
test('Review needs complete fresh drafts, page publication and plan review',async()=>{
 let d=await saveTarget();await assert.rejects(review(),/Save complete/);await save();await assert.rejects(review(),/Save complete/);await completeCreative();await saveTarget(empty);await assert.rejects(review(),/Save complete/);await saveTarget();await funnel('pause',{version:f.version,confirmed:true});await assert.rejects(review(),/Save complete/);
});
test('Version and fingerprint checks reject concurrent stale saves and reviews',async()=>{
 let d=await targeting(),body={version:d.version,fingerprint:d.fingerprint,assets:choices};let results=await Promise.all([req('/save',body),req('/save',body)]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);await completeCreative();d=await targeting();body={version:d.version,review_fingerprint:d.review_fingerprint,confirmed:true};results=await Promise.all([req('/review',body),req('/review',body)]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);
});
test('Clearing review requires exact confirmation/version and preserves draft and creative',async()=>{
 await ready();const r=await review();for(const data of [{version:r.version-1,confirmed:true},{version:r.version,confirmed:'true'}])await assert.rejects(targeting('clear_review',data));const d=await targeting('clear_review',{version:r.version,confirmed:true});assert.equal(d.review_current,false);assert.equal(d.reviewed_snapshot,null);assert.equal(d.reviewed_at,null);assert.equal(d.version,r.version+1);assert.equal(d.draft_revision,r.draft_revision);assert.deepEqual(d.assets,r.assets);assert.deepEqual(d.creative,r.creative);assert.equal(d.updated_at,r.updated_at);
});
test('Historical review keeps image metadata after replacement and deletion; funnel deletion cascades',async()=>{
 await ready();const r=await review(),id=r.creative.assets.image_id;await save();await imageCommand('delete',id);const d=await targeting();assert.equal(d.review_current,false);assert.equal(d.reviewed_snapshot.creative.image.id,id);assert.equal(d.reviewed_snapshot.creative.image.sha256.length,64);await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_meta_targeting')).rows[0].n,0);
});
test('Targeting reads and saves preserve all existing creative, setup and campaign rows',async()=>{
 await completeCreative();await saveReview();const rows=async()=>(await db.query("select jsonb_build_object('creative',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_meta_creatives t),'setup',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_meta_preparations t),'campaign',(select jsonb_agg(to_jsonb(t)) from korlix_funnel_campaigns t),'connection',(select jsonb_agg(to_jsonb(t)) from korlix_meta_connections t)) r")).rows[0].r;const before=await rows();await targeting();await saveTarget();await review();assert.deepEqual(await rows(),before);assert.equal(providerCalls,0);
});
test('All targeting actions share a thirty-request owner rate limit',async()=>{for(let i=0;i<30;i++)assert.equal((await req()).status,200);assert.equal((await req('/clear-review',{version:0,confirmed:true})).status,429);assert.equal(providerCalls,0);});
