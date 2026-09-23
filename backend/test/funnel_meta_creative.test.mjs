import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher} from '../funnels/meta.mjs';
import {metaCreativeAssets,metaCreativeInput} from '../funnels/meta_creative.mjs';
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
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/meta-creative${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,pages,selected_page,refreshed_at,pages_refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,$8,$9,now(),now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id,JSON.stringify([page]),page.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923011934_funnel_meta_page_identity.sql','20260923015323_funnel_meta_campaign_preparation.sql','20260922194529_funnel_images.sql','20260923133926_funnel_meta_creative.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
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
test('Read is private, no-store, credential free and creates no draft without a connection',async()=>{
 await db.exec('delete from korlix_meta_connections');const res=await req();assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'no-store');const d=await res.json();assert.equal(d.source,'meta_ad_draft');assert.equal(d.version,0);assert.equal(d.creative_complete,false);assert.equal(d.ad_publishing_ready,false);assert.deepEqual(d.assets,blank);assert.equal(d.setup.current_snapshot.landing_page.destination,`https://example.com/f/services?utm_source=facebook&utm_medium=paid&utm_campaign=k143_${c.id.replaceAll('-','')}`);assert.equal((await db.query('select count(*)::int n from korlix_funnel_meta_creatives')).rows[0].n,0);assert.equal(providerCalls,0);
 for(const secret of ['sealed','config_hash','meta_user_id','binding_id','private-fixture-token'])assert(!JSON.stringify(d).includes(secret));
});
test('Owner, current Enterprise tier, platform and browser-role boundaries apply to all commands',async()=>{
 const d=await creative();for(const [actor,status] of [['',401],[other,404],[basic,403]]){assert.equal((await req('',null,actor)).status,status);assert.equal((await req('/save',{version:0,fingerprint:d.fingerprint,assets},actor)).status,status);}
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_meta_creatives'),/permission denied/);await assert.rejects(creative(),/permission denied/);await db.exec('reset role;set role service_role');}
 const schema=(await db.query("select p.prosecdef,p.proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_meta_creatives'::regclass) rls from pg_proc p where oid='korlix_funnel_meta_creative_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(schema.prosecdef,false);assert(schema.rls);assert.deepEqual(schema.proconfig,['search_path=public, pg_temp']);
 await db.query("update korlix_funnel_campaigns set platform='google' where id=$1",[c.id]);assert.equal((await req()).status,400);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await req()).status,403);
});
test('Saves incomplete and complete drafts with image metadata and monotonic versions',async()=>{
 let d=await save();assert.equal(d.version,1);assert.equal(d.creative_complete,false);const a=await image();const complete={...assets,image_id:a.id,image_alt:'Our team at work'};
 const res=await req('/save',{version:d.version,fingerprint:d.fingerprint,assets:complete});assert.equal(res.status,200);d=await res.json();assert.equal(d.version,2);assert.equal(d.creative_complete,true);assert.equal(d.draft_current,true);assert.equal(d.image.width,600);assert.equal(d.image.id,a.id);assert.equal(d.image.sha256.length,64);assert.deepEqual(d.saved_context,d.setup.current_snapshot);assert.deepEqual((await creative()).assets,complete);
 d=await save(blank);assert.equal(d.version,3);assert.equal(d.image,null);assert.equal(d.creative_complete,false);
});
test('Plain text bounds, Unicode and button/image shapes match SQL and API validation',async()=>{
 const bad=[{...assets,primary_text:'x'.repeat(1001)},{...assets,headline:'😀'.repeat(101)},{...assets,description:'x'.repeat(201)},{...assets,image_alt:'x'},{...assets,primary_text:'line\nbreak'},{...assets,headline:'hidden\u200btext'},{...assets,headline:'bad\u0085text'},{...assets,cta:'LAUNCH'},{...assets,image_id:'https://evil.test/image'},{...assets,image_id:42},{...assets,extra:true},{...assets,headline:4},{...assets,headline:' space'}];
 for(const a of bad){assert.throws(()=>metaCreativeAssets(a));assert.equal((await db.query('select korlix_meta_creative_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,false);await assert.rejects(save(a));}
 for(const a of [blank,assets,{...assets,primary_text:'😀'.repeat(1000),headline:'中'.repeat(100),description:'x'.repeat(200)}]){metaCreativeAssets(a);assert.equal((await db.query('select korlix_meta_creative_valid_v1($1::jsonb) ok',[JSON.stringify(a)])).rows[0].ok,true);}
});
test('Payloads cannot set actor, destination, launch readiness or unsafe versions',async()=>{
 const d=await creative(),body={version:0,fingerprint:d.fingerprint,assets};
 for(const patch of [{version:-1},{version:1.5},{version:2147483648},{fingerprint:'x'},{actor:other},{public_base:'https://evil.test'},{ad_publishing_ready:true},{assets:null}]){assert.throws(()=>metaCreativeInput({...body,...patch}));assert.equal((await req('/save',{...body,...patch})).status,400);}
 assert.equal((await req('?actor='+other)).status,400);assert.equal((await req('/save?actor='+other,body)).status,400);
});
test('Stale or concurrent writes cannot overwrite saved text',async()=>{
 const d=await creative(),body={version:0,fingerprint:d.fingerprint,assets};const results=await Promise.all([req('/save',body),req('/save',{...body,assets:{...assets,headline:'Different'}})]);assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);assert.equal((await creative()).version,1);assert.equal(providerCalls,0);
});
test('Campaign, public page and selected Page changes invalidate the saved context',async()=>{
 let d=await save();c=await campaign('save',{...plan,headline:'Changed offer'});let next=await creative();assert.equal(next.draft_current,false);assert.equal(next.saved_context.campaign.headline,plan.headline);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,409);
 d=await save();f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'New public offer'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await creative()).draft_current,false);
 d=await save();await db.query('update korlix_meta_connections set selected_page=null where user_id=$1',[owner]);next=await creative();assert.equal(next.draft_current,false);assert.equal(next.saved_context.meta.page.id,page.id);assert.equal((await req('/save',{version:d.version,fingerprint:d.fingerprint,assets})).status,409);
});
test('Unpublished edits and manual reports preserve context; archived drafts stay readable',async()=>{
 const d=await save();c=await campaign('report',{day:new Date().toISOString().slice(0,10),spend_cents:1000,clicks:10,impressions:1000,note:'Owner entered'});f=await funnel('save',{version:f.version,name:'Services',document:{...doc,headline:'Unpublished'}});assert.equal((await creative()).fingerprint,d.fingerprint);
 c=await campaign('archive',{confirmed:true});assert.equal((await creative()).editable,false);await assert.rejects(save(),/Reopen/);assert.equal(providerCalls,0);
});
test('Other-owner and deleted images cannot be selected, even through direct RPC',async()=>{
 const a=await image(other);await assert.rejects(save({...assets,image_id:a.id,image_alt:'Other image'}),/no longer available/);await assert.rejects(save({...assets,image_id:randomUUID(),image_alt:'Missing'}),/no longer available/);
 const own=await image();await imageCommand('delete',own.id);await assert.rejects(save({...assets,image_id:own.id,image_alt:'Removed'}),/no longer available/);
});
test('Saved creative image references block deletion and never enable public delivery',async()=>{
 const a=await image();await save({...assets,image_id:a.id,image_alt:'Team'});const list=await imageCommand('list');assert.equal(list.images[0].creative_count,1);assert.equal(list.images[0].page_count,0);
 await assert.rejects(imageCommand('delete',a.id),/saved Meta ad draft/);await assert.rejects(db.query('delete from korlix_funnel_images where id=$1',[a.id]),/foreign key/);
 const pub=await fetch(`${base}/f/services/media/${a.id}`);assert.equal(pub.status,404);assert.equal((await imageCommand('get',a.id)).width,600);
 await save();assert.equal((await imageCommand('list')).images[0].creative_count,0);assert.equal((await imageCommand('delete',a.id)).deleted,true);
});
test('Existing published-image protection and public delivery survive the image RPC update',async()=>{
 const a=await image();f=await funnel('save',{version:f.version,name:'Services',document:{...doc,hero_image:{id:a.id,alt:'Team'}}});f=await funnel('publish',{version:f.version,confirmed:true});const list=await imageCommand('list');assert.equal(list.images[0].page_count,1);assert.equal(list.images[0].creative_count,0);
 await assert.rejects(imageCommand('delete',a.id),/saved draft or published page/);assert.equal((await fetch(`${base}/f/services/media/${a.id}`)).status,200);
});
test('Funnel and owner deletion cascade without leaving or blocking creative references',async()=>{
 const a=await image();await save({...assets,image_id:a.id,image_alt:'Team'});await db.query('delete from korlix_funnels where id=$1',[f.id]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_meta_creatives')).rows[0].n,0);assert.equal((await imageCommand('delete',a.id)).deleted,true);
 f=await funnel('create',{name:'Services',slug:'services',document:doc});c=await campaign('create',plan);const b=await image();await save({...assets,image_id:b.id,image_alt:'Team'});
 await db.exec('reset role');await db.query('delete from auth.users where id=$1',[owner]);assert.equal((await db.query('select count(*)::int n from korlix_funnel_meta_creatives')).rows[0].n,0);await db.query('insert into auth.users values($1)',[owner]);await db.exec('set role service_role');
});
