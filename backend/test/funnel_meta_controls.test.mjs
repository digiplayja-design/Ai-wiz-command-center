import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {metaConfiguration,tokenCipher} from '../funnels/meta.mjs';
import {MetaPausedAccessError} from '../funnels/meta_paused_provider.mjs';
import {normalizeImage} from '../funnels/images.mjs';
import sharp from 'sharp';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_BUDGET_ENABLED:'true',KORLIX_META_CONTROLS_ENABLED:'true',KORLIX_META_CREATE_PAUSED_ENABLED:'true',KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-secret-not-real',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback',KORLIX_FUNNEL_PUBLIC_BASE_URL:'https://example.com'};
const config=metaConfiguration(env),account={id:'act_123',name:'Growth account',currency:'USD',timezone:'UTC',status:1},page={id:'98765432101234567890',name:'Growth Page',category:'Education'};
const doc={brand:'Test business',headline:'Your next step',subheadline:'Talk to our team.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Businesses seeking our services.',daily_cents:2500,days:14};
let db,database,server,base,f,c,clock=Date.now(),providerCalls=0,writes=[],validateHook,writeHook,findHook;
const rpc=async(name,p)=>(await db.query(name==='korlix_meta_v1'?`select public.${name}($1,$2,$3) r`:`select public.${name}($1,$2,$3,$4) r`,name==='korlix_meta_v1'?[p.p_actor,p.p_action,JSON.stringify(p.p_data??{})]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;

const funnel=(action,data={})=>rpc('korlix_funnel_v1',{p_actor:owner,p_action:action,p_id:action==='create'?null:f.id,p_data:data});
const campaign=(action,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c?.id,version:c?.version,...data}});
const setup=(action='read',data={},actor=owner)=>rpc('korlix_funnel_meta_preparation_v1',{p_actor:actor,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,configured:true,config_hash:config.hash,public_base:'https://example.com',...data}});
const req=(suffix='',body=null,actor=owner,ids={})=>fetch(`${base}/api/funnels/${ids.funnel??f.id}/campaigns/${ids.campaign??c.id}/meta-create${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
async function connect(){const binding=randomUUID();await db.query('insert into korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,accounts,selected_account,pages,selected_page,refreshed_at,pages_refreshed_at) values($1,$2,$3,$4,$5,now()+interval \'1 day\',$6,$7,$8,$9,now(),now())',[owner,binding,config.hash,'123456',JSON.stringify(tokenCipher(config.key).seal('private-fixture-token',`korlix-meta:${owner}:${binding}`)),JSON.stringify([account]),account.id,JSON.stringify([page]),page.id]);}
async function saveReview(){const r=await setup();return setup('review',{version:r.version,fingerprint:r.fingerprint,confirmed:true});}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default \'transactional_only\',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;');
 for(const id of [owner,other,basic]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles values($1,$2)',[id,id===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260922111502_funnel_meta_connection.sql','20260923011934_funnel_meta_page_identity.sql','20260923015323_funnel_meta_campaign_preparation.sql','20260922194529_funnel_images.sql','20260923133926_funnel_meta_creative.sql','20260923140507_funnel_meta_targeting.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 for(const file of ['20260923162339_funnel_meta_radius.sql','20260923180917_funnel_meta_locations.sql','20260923232651_funnel_meta_paused_create.sql','20260924000946_funnel_meta_controls.sql','20260924010035_funnel_meta_budget.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,environment:env,now:()=>clock,metaProvider:provider});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;await db.exec('delete from korlix_funnels;delete from korlix_meta_connections;delete from korlix_funnel_images;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);f=await funnel('create',{name:'Services',slug:'services',document:doc});f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);c=await campaign('review',{confirmed:true});await connect();providerCalls=0;writes=[];validateHook=null;writeHook=null;findHook=null;controlWrites=[];controlHook=null;controlValidateHook=null;graphHook=null;statusHook=null;currentBudget=2500;budgetWrites=[];budgetInspectHook=null;budgetValidateHook=null;budgetWriteHook=null;statuses={campaign:'PAUSED',ad_set:'PAUSED',ad:'PAUSED'};});
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
async function ready(){await saveReview();await completeCreative();await saveTarget();return review();}

const resources={image_hash:'a'.repeat(32),campaign:'101',ad_set:'102',creative:'103',ad:'104'};
const provider={
 account:async()=>{providerCalls++;return account;},
 verifyCreationAccess:async()=>{providerCalls++;return {verified:true};},
 validatePausedMeta:async(...args)=>{providerCalls++;return validateHook?validateHook(...args):{validated:true};},
 createPausedMetaResource:async(token,s,r,stage,bytes)=>{writes.push(stage);assert.equal(token,'private-fixture-token');assert.equal(s.budget_acknowledged,true);assert.deepEqual(Object.keys(r),Object.keys(resources).slice(0,writes.length-1));if(stage==='image_hash')assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');return writeHook?writeHook(token,s,r,stage,bytes):resources[stage];},
 findPausedMeta:async(...args)=>{providerCalls++;return findHook?findHook(...args):resources;}
};
const read=async()=>{const r=await req();assert.equal(r.status,200,await r.clone().text());return r.json();};
const input=d=>({fingerprint:d.fingerprint,start_date:d.earliest_start,confirmed:true,budget_acknowledged:true});
const create=async()=>req('/create',input(await read()));
const ledger=async()=>(await db.query('select * from korlix_funnel_meta_creations')).rows;

let controlWrites=[],controlHook=null,controlValidateHook=null,graphHook=null,statusHook=null,statuses={campaign:'PAUSED',ad_set:'PAUSED',ad:'PAUSED'};
function graph(){return {resources,statuses:{...statuses},effective_statuses:{campaign:statuses.campaign,ad_set:statuses.ad_set==='PAUSED'?'PAUSED':statuses.campaign==='PAUSED'?'CAMPAIGN_PAUSED':'ACTIVE',ad:statuses.ad==='PAUSED'?'PAUSED':statuses.campaign==='PAUSED'?'CAMPAIGN_PAUSED':statuses.ad_set==='PAUSED'?'ADSET_PAUSED':'ACTIVE'}};}
Object.assign(provider,{
 verifyMetaControlAccess:async()=>{providerCalls++;return {verified:true};},
 createdMetaStatus:async()=>{providerCalls++;return statusHook?statusHook():{resource:resources.campaign,name:'Saved campaign',status:statuses.campaign,effective_status:statuses.campaign};},
 inspectCreatedMeta:async(_token,s)=>{providerCalls++;assert.equal(s.plan.daily_cents,currentBudget);return graphHook?graphHook():graph();},
 validateMetaControl:async(_a,_s,_r,action,stage)=>controlValidateHook?controlValidateHook(action,stage):{validated:true},
 applyMetaControlStage:async(_a,_s,r,action,stage)=>{assert.deepEqual(r,resources);controlWrites.push({action,stage});const value={confirmed:true,resource:r[stage],stage,status:action==='activate'?'ACTIVE':'PAUSED'};if(controlHook)return controlHook(action,stage,value);statuses[stage]=value.status;return value;}
});
const controls=(suffix='',body=null,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/meta-controls${suffix}`,{method:body===null?'GET':'POST',headers:{Authorization:actor,'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
const record=async()=>{const r=await controls();assert.equal(r.status,200,await r.clone().text());return r.json();};
const inspect=async()=>{const r=await controls('/inspect',{});assert.equal(r.status,200,await r.clone().text());return r.json();};
const inputControl=(d,action='activate')=>({proof:d.observation.proof,action,confirmed:true,spend_acknowledged:action==='activate'});
const commands=async()=>(await db.query('select * from korlix_funnel_meta_commands order by sequence')).rows;
async function created(){await ready();const r=await create();assert.equal(r.status,201,await r.clone().text());providerCalls=0;}
test('K185 local record stays provider-free and denies browser SQL/HTTP access',async()=>{
 let d=await record();assert.equal(d.checks.creation_recorded,false);assert.equal(providerCalls,0);assert.deepEqual(await commands(),[]);
 for(const [actor,status]of [['',401],[other,404],[basic,403]])for(const [path,body]of [['',null],['/inspect',{}],['/apply',{proof:'YQ.'+'a'.repeat(43),action:'activate',confirmed:true,spend_acknowledged:true}]])assert.equal((await controls(path,body,actor)).status,status);
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_meta_commands'),/permission denied/);await assert.rejects(rpc('korlix_funnel_meta_controls_v1',{p_actor:owner,p_action:'read',p_funnel:f.id,p_data:{campaign_id:c.id}}),/permission denied/);await db.exec('reset role;set role service_role');}
 const a=(await db.query("select prosecdef,proconfig,(select relrowsecurity from pg_class where oid='korlix_funnel_meta_commands'::regclass) rls from pg_proc where oid='korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb)'::regprocedure")).rows[0];assert.equal(a.prosecdef,false);assert.equal(a.rls,true);assert.deepEqual(a.proconfig,['search_path=public, pg_temp']);for(const endpoint of ['finish','progress','reset','resume','reconcile'])assert.equal((await controls('/'+endpoint,{})).status,404);
});
test('K185 activation enables children before campaign, pause changes only parent, resume skips active children',async()=>{
 await created();const original=await ledger();let d=await inspect();assert.equal(d.observation.can_activate,true);let r=await controls('/apply',inputControl(d));assert.equal(r.status,200,await r.clone().text());d=await r.json();assert.equal(d.latest_command.state,'confirmed');assert.deepEqual(d.latest_command.steps,['ad','ad_set','campaign']);assert.deepEqual(d.latest_command.progress,{ad:'ACTIVE',ad_set:'ACTIVE',campaign:'ACTIVE'});assert.deepEqual(controlWrites.map(x=>x.stage),['ad','ad_set','campaign']);assert.equal(d.observation,undefined);assert.equal(d.dispatch,undefined);
 d=await inspect();assert.equal(d.observation.can_pause,true);r=await controls('/apply',inputControl(d,'pause'));assert.equal(r.status,200);assert.deepEqual((await r.json()).latest_command.progress,{campaign:'PAUSED'});assert.equal(statuses.ad,'ACTIVE');assert.equal(statuses.ad_set,'ACTIVE');d=await inspect();assert.equal(d.observation.can_activate,true);r=await controls('/apply',inputControl(d));assert.equal(r.status,200);assert.deepEqual((await r.json()).latest_command.steps,['campaign']);assert.equal(controlWrites.length,5);assert.deepEqual((await commands()).map(x=>x.sequence),[1,2,3]);assert.deepEqual(await ledger(),original);assert(!JSON.stringify(d).includes('private-fixture-token'));
});
test('K185 partial child failure preserves receipts, never activates parent and blocks further commands',async()=>{
 await created();const d=await inspect();controlHook=async(_a,stage,value)=>{if(stage==='ad_set')throw Error('secret result');statuses[stage]=value.status;return value;};const r=await controls('/apply',inputControl(d));assert.equal(r.status,200);const after=await r.json();assert.equal(after.latest_command.state,'unknown');assert.deepEqual(after.latest_command.progress,{ad:'ACTIVE'});assert.equal(statuses.campaign,'PAUSED');assert.match(after.notice,/may be spending/);assert(!JSON.stringify(after).includes('secret result'));assert.equal(controlWrites.length,2);statuses.campaign='ACTIVE';const seen=await inspect();assert.equal(seen.observation.can_pause,false);assert.equal(seen.observation.proof,null);assert.equal((await commands())[0].state,'unknown');assert.equal((await controls('/apply',inputControl(d))).status,409);assert.equal(controlWrites.length,2);
});
test('K185 lost final activation receipt stays unknown even if campaign is observed active',async()=>{
 await created();const d=await inspect();controlHook=async(_a,stage,value)=>{statuses[stage]=value.status;if(stage==='campaign')throw Error();return value;};assert.equal((await controls('/apply',inputControl(d))).status,200);const row=(await commands())[0];assert.equal(row.state,'unknown');assert.deepEqual(row.progress,{ad:'ACTIVE',ad_set:'ACTIVE'});const seen=await inspect();assert.equal(seen.observation.status.status,'ACTIVE');assert.equal(seen.observation.can_pause,false);assert.equal(controlWrites.length,3);
});
test('K185 concurrency and repeated proof claim one activation command',async()=>{
 await created();const d=await inspect(),body=inputControl(d);const rs=await Promise.all([controls('/apply',body),controls('/apply',body)]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal((await commands()).length,1);assert.equal(controlWrites.length,3);assert.equal((await controls('/apply',body)).status,409);
});
test('K185 preclaim validation or storage failures send no mutations',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{throw Error('secret');};assert.equal((await controls('/apply',inputControl(d))).status,503);assert.deepEqual(await commands(),[]);assert.equal(controlWrites.length,0);controlValidateHook=null;const original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim'?{error:{code:'XX000'}}:original(n,p);try{assert.equal((await controls('/apply',inputControl(d))).status,503);assert.equal(controlWrites.length,0);}finally{database.rpc=original;}
});
test('K185 failed progress storage stops following status writes',async()=>{
 await created();const d=await inspect(),original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_controls_v1'&&p.p_action==='progress'?{error:{code:'XX000'}}:original(n,p);try{const r=await controls('/apply',inputControl(d));assert.equal(r.status,200);assert.deepEqual((await r.json()).latest_command.progress,{});assert.equal(controlWrites.length,1);assert.equal(statuses.campaign,'PAUSED');}finally{database.rpc=original;}
});
test('K185 failed completion storage retains all receipts but cannot settle via status reads',async()=>{
 await created();const d=await inspect(),original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_controls_v1'&&p.p_action==='finish'?{error:{code:'XX000'}}:original(n,p);try{const r=await controls('/apply',inputControl(d));assert.equal(r.status,200);const row=(await r.json()).latest_command;assert.equal(row.state,'unknown');assert.equal(Object.keys(row.progress).length,3);}finally{database.rpc=original;}assert.equal((await inspect()).observation.proof,null);
});
test('K185 malformed command success never advances to the next resource',async()=>{
 await created();const d=await inspect();controlHook=async(_a,_stage,value)=>({...value,resource:'999'});assert.equal((await controls('/apply',inputControl(d))).status,200);assert.equal((await commands())[0].state,'unknown');assert.deepEqual((await commands())[0].progress,{});assert.equal(controlWrites.length,1);
});
test('K185 proof tampering, expiry, wrong action and body injection stop before writes',async()=>{
 await created();const d=await inspect(),body=inputControl(d);for(const patch of [{proof:body.proof+'a'},{confirmed:false},{spend_acknowledged:false},{account_id:account.id},{action:'pause',spend_acknowledged:false},{action:'budget'}]){clock+=60000;assert([400,409].includes((await controls('/apply',{...body,...patch})).status));}assert.equal((await controls('/apply',body)).status,409);assert.equal(controlWrites.length,0);assert.equal((await controls('/inspect',{resource:'101'})).status,400);assert.equal((await controls('?configured=true')).status,400);
});
test('K185 changed budget or policy inspection prevents activation while active parent remains pausable',async()=>{
 await created();graphHook=async()=>{throw Error('changed modeled content');};let d=await inspect();assert.equal(d.observation.can_activate,false);assert.equal(d.observation.proof,null);statuses.campaign='ACTIVE';d=await inspect();assert.equal(d.observation.can_pause,true);assert.equal((await controls('/apply',inputControl(d,'pause'))).status,200);assert.deepEqual(controlWrites,[{action:'pause',stage:'campaign'}]);
});
test('K185 stale drafts, archive, paused landing page and removed Page do not block account-authorized pause',async()=>{
 await created();const a=await creative();await creative('save',{version:a.version,fingerprint:a.fingerprint,assets:{...a.assets,headline:'Changed'}});c=await campaign('archive',{confirmed:true});f=await funnel('pause',{version:f.version});await db.query('update korlix_meta_connections set selected_page=null,pages_access_denied=true,version=version+1 where user_id=$1',[owner]);let d=await record();assert.equal(d.activation_ready,false);statuses.campaign='ACTIVE';d=await inspect();assert.equal(d.observation.can_pause,true);assert.equal((await controls('/apply',inputControl(d,'pause'))).status,200);
});
test('K185 connection or local edits during validation invalidate claim',async()=>{
 await created();let d=await inspect();controlValidateHook=async()=>{await db.query('update korlix_meta_connections set version=version+1 where user_id=$1',[owner]);return{validated:true};};assert.equal((await controls('/apply',inputControl(d))).status,409);assert.equal(controlWrites.length,0);assert.deepEqual(await commands(),[]);
});
test('K185 external status drift after validation prevents claim',async()=>{
 await created();const d=await inspect();controlValidateHook=async()=>{statuses.campaign='ACTIVE';return{validated:true};};assert.equal((await controls('/apply',inputControl(d))).status,409);assert.equal(controlWrites.length,0);assert.deepEqual(await commands(),[]);
});
test('K185 content change after first receipt stops before campaign enable',async()=>{
 await created();const d=await inspect();controlHook=async(_a,stage,value)=>{statuses[stage]=value.status;const cr=await creative();await creative('save',{version:cr.version,fingerprint:cr.fingerprint,assets:{...cr.assets,headline:'Changed during activation'}});return value;};assert.equal((await controls('/apply',inputControl(d))).status,200);assert.equal(controlWrites.length,1);assert.equal(statuses.campaign,'PAUSED');assert.deepEqual((await commands())[0].progress,{ad:'ACTIVE'});
});
test('K185 connection change after child receipt stops subsequent writes',async()=>{
 await created();const d=await inspect();controlHook=async(_a,stage,value)=>{statuses[stage]=value.status;await db.query('update korlix_meta_connections set version=version+1 where user_id=$1',[owner]);return value;};assert.equal((await controls('/apply',inputControl(d))).status,200);assert.equal(controlWrites.length,1);assert.deepEqual((await commands())[0].progress,{ad:'ACTIVE'});
});
test('K185 late tier loss persists child receipt and denies remaining activation',async()=>{
 await created();const d=await inspect();controlHook=async(_a,stage,value)=>{statuses[stage]=value.status;await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return value;};assert.equal((await controls('/apply',inputControl(d))).status,403);assert.equal(controlWrites.length,1);assert.deepEqual((await commands())[0].progress,{ad:'ACTIVE'});
});
test('K185 late tier loss on single pause persists confirmed completion',async()=>{
 await created();statuses.campaign='ACTIVE';const d=await inspect();controlHook=async(_a,stage,value)=>{statuses[stage]=value.status;await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return value;};assert.equal((await controls('/apply',inputControl(d,'pause'))).status,403);assert.equal((await commands())[0].state,'confirmed');assert.deepEqual((await commands())[0].progress,{campaign:'PAUSED'});
});
test('K185 revoked Meta credentials mark current connection invalid',async()=>{
 await created();graphHook=async()=>{throw new MetaPausedAccessError();};assert.equal((await controls('/inspect',{})).status,409);assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,true);assert.equal(controlWrites.length,0);
});
test('K185 stale preclaim and postclaim deadlines prevent late provider mutations',async()=>{
 await created();let d=await inspect();controlValidateHook=async()=>{clock+=76000;return {validated:true};};assert.equal((await controls('/apply',inputControl(d))).status,409);assert.equal(controlWrites.length,0);assert.deepEqual(await commands(),[]);controlValidateHook=null;d=await inspect();const original=database.rpc;database.rpc=async(n,p)=>{const result=await original(n,p);if(n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim')clock+=86000;return result;};try{assert.equal((await controls('/apply',inputControl(d))).status,200);assert.equal(controlWrites.length,0);assert.equal((await commands())[0].state,'unknown');}finally{database.rpc=original;}
});
test('K185 internal receipt order, identities and completion cannot be forged',async()=>{
 await created();const d=await inspect();controlHook=async()=>{throw Error();};await controls('/apply',inputControl(d));const row=(await commands())[0];const call=(action,data={})=>rpc('korlix_funnel_meta_controls_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,command_id:row.id,...data}});await assert.rejects(call('progress',{stage:'campaign',resource:'101',status:'ACTIVE'}),/reordered/);await assert.rejects(call('progress',{stage:'ad',resource:'999',status:'ACTIVE'}),/receipt/);await assert.rejects(call('finish'),/receipts/);await call('progress',{stage:'ad',resource:'104',status:'ACTIVE'});await assert.rejects(call('progress',{stage:'ad',resource:'104',status:'ACTIVE'}),/reordered/);
});
test('K185 controls remain default-off and paused creation gate can be off for existing resources',async()=>{
 await created();for(const patch of [{KORLIX_META_CONTROLS_ENABLED:undefined},{KORLIX_META_API_VERSION:'v25.0'},{KORLIX_META_CREATE_PAUSED_ENABLED:undefined}]){const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async()=>({id:owner}),environment:{...env,...patch},metaProvider:provider,now:()=>clock});const srv=app.listen(0);await new Promise(r=>srv.once('listening',r));try{const url=`http://127.0.0.1:${srv.address().port}/api/funnels/${f.id}/campaigns/${c.id}/meta-controls`;const d=await(await fetch(url)).json();const enabled=Object.hasOwn(patch,'KORLIX_META_CREATE_PAUSED_ENABLED');assert.equal(d.checks.platform_enabled,enabled);const r=await fetch(url+'/inspect',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});assert.equal(r.status,enabled?200:409);}finally{srv.closeAllConnections();await new Promise(r=>srv.close(r));}}
});

// K186 reuses the actual K185 journal and Express routes; no provider is contacted.
let currentBudget=2500,budgetWrites=[],budgetInspectHook=null,budgetValidateHook=null,budgetWriteHook=null;
Object.assign(provider,{
 inspectMetaBudget:async(_token,s,r)=>{providerCalls++;if(budgetInspectHook)return budgetInspectHook(s,r);const g=graph();return {status:{resource:r.campaign,name:s.provider_name+' Campaign',status:g.statuses.campaign,effective_status:g.effective_statuses.campaign},budget:{resource:r.ad_set,daily_cents:currentBudget,status:g.statuses.ad_set,effective_status:g.effective_statuses.ad_set}};},
 validateMetaBudget:async(...args)=>budgetValidateHook?budgetValidateHook(...args):{validated:true},
 applyMetaBudget:async(_token,s,r,cents)=>{budgetWrites.push(cents);const result={confirmed:true,resource:r.ad_set,daily_cents:cents};if(budgetWriteHook)return budgetWriteHook(cents,result);currentBudget=cents;return result;}
});
const preview=async(cents=3500)=>{const r=await controls('/budget-preview',{daily_cents:cents});assert.equal(r.status,200,await r.clone().text());return r.json();};
const budgetInput=d=>({proof:d.budget_preview.proof,daily_cents:d.budget_preview.daily_cents,confirmed:true,spend_acknowledged:true});
test('K186 confirmed budgets serialize with status commands and preserve original creation history',async()=>{
 await created();const original=await ledger();let d=await record();assert.equal(providerCalls,0);assert.deepEqual(d.managed_budget,{daily_cents:2500,original_daily_cents:2500,command_id:null,confirmed_at:null});
 d=await preview();let r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200,await r.clone().text());d=await r.json();assert.equal(d.latest_command.state,'confirmed');assert.deepEqual(d.latest_command.steps,['budget']);assert.deepEqual(d.latest_command.progress,{budget:3500});assert.equal(d.managed_budget.daily_cents,3500);assert.equal(d.managed_budget.command_id,d.latest_command.id);assert.equal(d.managed_budget.original_daily_cents,2500);
 d=await inspect();assert.equal(d.observation.can_activate,true);assert.equal((await controls('/apply',inputControl(d))).status,200);d=await preview(1000);assert.equal(d.budget_preview.increase,false);assert.equal(d.budget_preview.graph,null);assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.equal((await record()).managed_budget.daily_cents,1000);assert.deepEqual(budgetWrites,[3500,1000]);assert.deepEqual((await commands()).map(x=>x.action),['budget','activate','budget']);assert.deepEqual(await ledger(),original);
});
test('K186 reductions work with stale drafts, archive and no Page; increases do not',async()=>{
 await created();const a=await creative();await creative('save',{version:a.version,fingerprint:a.fingerprint,assets:{...a.assets,headline:'Changed'}});c=await campaign('archive',{confirmed:true});f=await funnel('pause',{version:f.version});await db.query('update korlix_meta_connections set selected_page=null,pages_access_denied=true,version=version+1 where user_id=$1',[owner]);statuses.campaign='ACTIVE';
 assert.equal((await controls('/budget-preview',{daily_cents:3500})).status,409);const d=await preview(2000);assert.equal(d.activation_ready,false);assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.deepEqual(budgetWrites,[2000]);assert.equal(statuses.campaign,'ACTIVE');
});
test('K186 budget input, confirmations and proof binding reject before mutation',async()=>{
 await created();for(const cents of [99,1000001,2.5,'2500',null]){clock+=60000;assert.equal((await controls('/budget-preview',{daily_cents:cents})).status,400);}assert.equal((await controls('/budget-preview',{daily_cents:2500})).status,409);let d=await preview();const body=budgetInput(d);
 for(const patch of [{confirmed:false},{spend_acknowledged:false},{daily_cents:4000},{ad_set:'999'},{proof:body.proof+'a'}]){clock+=60000;assert([400,409].includes((await controls('/budget-apply',{...body,...patch})).status));}clock+=60000;assert.equal((await controls('/budget-apply',body)).status,409);assert.deepEqual(budgetWrites,[]);assert.deepEqual(await commands(),[]);
});
test('K186 budget and activation race claim at most one command',async()=>{
 await created();const b=await preview(),a=await inspect();const rs=await Promise.all([controls('/budget-apply',budgetInput(b)),controls('/apply',inputControl(a))]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal((await commands()).length,1);assert((budgetWrites.length===1&&controlWrites.length===0)||(budgetWrites.length===0&&controlWrites.length===3));
});
test('K186 two budget confirmations serialize and an accepted proof cannot be replayed',async()=>{
 await created();const d=await preview(),body=budgetInput(d);const rs=await Promise.all([controls('/budget-apply',body),controls('/budget-apply',body)]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal((await controls('/budget-apply',body)).status,409);assert.equal(budgetWrites.length,1);assert.equal((await commands()).length,1);
});
test('K186 provider budget drift and failed validation prevent the claim',async()=>{
 await created();const d=await preview();budgetValidateHook=async()=>{currentBudget=2600;return{validated:true};};assert.equal((await controls('/budget-apply',budgetInput(d))).status,409);assert.deepEqual(await commands(),[]);assert.equal(budgetWrites.length,0);currentBudget=2500;budgetValidateHook=async()=>{throw new MetaPausedAccessError();};assert.equal((await controls('/budget-apply',budgetInput(d))).status,409);assert.equal((await db.query('select needs_reconnect from korlix_meta_connections')).rows[0].needs_reconnect,true);assert.equal(budgetWrites.length,0);
});
test('K186 failed budget claim sends nothing and cannot advance managed amount',async()=>{
 await created();const d=await preview(),original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim'?{error:{code:'XX000'}}:original(n,p);try{assert.equal((await controls('/budget-apply',budgetInput(d))).status,503);assert.deepEqual(budgetWrites,[]);assert.deepEqual(await commands(),[]);}finally{database.rpc=original;}
});
test('K186 lost budget response remains unknown and blocks status and later budget commands',async()=>{
 await created();const d=await preview();budgetWriteHook=async cents=>{currentBudget=cents;throw Error('private response');};let r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200);const after=await r.json();assert.equal(after.latest_command.state,'unknown');assert.deepEqual(after.latest_command.progress,{});assert.equal(after.managed_budget.daily_cents,2500);assert(!JSON.stringify(after).includes('private response'));statuses.campaign='ACTIVE';assert.equal((await inspect()).observation.can_pause,false);assert.equal((await controls('/budget-preview',{daily_cents:2000})).status,409);assert.equal(budgetWrites.length,1);
});
for(const stage of ['progress','finish'])test('K186 failed '+stage+' storage preserves uncertainty and original managed budget',async()=>{
 await created();const d=await preview(),original=database.rpc;database.rpc=async(n,p)=>n==='korlix_funnel_meta_controls_v1'&&p.p_action===stage?{error:{code:'XX000'}}:original(n,p);try{const r=await controls('/budget-apply',budgetInput(d));assert.equal(r.status,200);const after=await r.json();assert.equal(after.latest_command.state,'unknown');assert.equal(after.managed_budget.daily_cents,2500);assert.deepEqual(after.latest_command.progress,stage==='progress'?{}:{budget:3500});assert.equal(budgetWrites.length,1);}finally{database.rpc=original;}
});
test('K186 changed local state after claim stops before the budget write',async()=>{
 await created();const d=await preview(),original=database.rpc;database.rpc=async(n,p)=>{const out=await original(n,p);if(n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim')await db.query('update korlix_meta_connections set version=version+1 where user_id=$1',[owner]);return out;};try{assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.equal((await commands())[0].state,'unknown');assert.equal(budgetWrites.length,0);}finally{database.rpc=original;}
});
test('K186 changed provider budget after claim stops before mutation',async()=>{
 await created();const d=await preview(),original=database.rpc;database.rpc=async(n,p)=>{const out=await original(n,p);if(n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim')currentBudget=2600;return out;};try{assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.equal((await commands())[0].state,'unknown');assert.equal(budgetWrites.length,0);}finally{database.rpc=original;}
});
test('K186 late access loss preserves accepted budget receipt but denies private response',async()=>{
 await created();const d=await preview();budgetWriteHook=async(cents,result)=>{currentBudget=cents;await db.query("update user_profiles set tier='basic' where id=$1",[owner]);return result;};assert.equal((await controls('/budget-apply',budgetInput(d))).status,403);const row=(await commands())[0];assert.equal(row.state,'confirmed');assert.deepEqual(row.progress,{budget:3500});assert.equal(budgetWrites.length,1);
});
test('K186 budget receipts require the exact ad set and amount before completion',async()=>{
 await created();const d=await preview();budgetWriteHook=async()=>{throw Error();};await controls('/budget-apply',budgetInput(d));const row=(await commands())[0],call=(action,data={})=>rpc('korlix_funnel_meta_controls_v1',{p_actor:owner,p_action:action,p_funnel:f.id,p_data:{campaign_id:c.id,command_id:row.id,...data}});
 await assert.rejects(call('finish'),/receipts/);await assert.rejects(call('progress',{stage:'budget',resource:'999',daily_cents:3500}),/receipt/);await assert.rejects(call('progress',{stage:'budget',resource:'102',daily_cents:3501}),/receipt/);await call('progress',{stage:'budget',resource:'102',daily_cents:3500});await assert.rejects(call('progress',{stage:'budget',resource:'102',daily_cents:3500}),/receipt/);await call('finish');assert.equal((await record()).managed_budget.daily_cents,3500);
});
test('K186 budget deadline checks stop stale writes before and after claim',async()=>{
 await created();let d=await preview();budgetValidateHook=async()=>{clock+=76000;return{validated:true};};assert.equal((await controls('/budget-apply',budgetInput(d))).status,409);assert.deepEqual(await commands(),[]);budgetValidateHook=null;d=await preview();const original=database.rpc;database.rpc=async(n,p)=>{const out=await original(n,p);if(n==='korlix_funnel_meta_controls_v1'&&p.p_action==='claim')clock+=86000;return out;};try{assert.equal((await controls('/budget-apply',budgetInput(d))).status,200);assert.equal((await commands())[0].state,'unknown');assert.equal(budgetWrites.length,0);}finally{database.rpc=original;}
});
test('K186 default-off budget gate leaves status controls available and protects both routes',async()=>{
 await created();const app=express();app.use(express.json());registerFunnels(app,{database,requireUser:async q=>q.headers.authorization===owner?{id:owner}:null,environment:{...env,KORLIX_META_BUDGET_ENABLED:undefined},metaProvider:provider,now:()=>clock});const srv=app.listen(0);await new Promise(r=>srv.once('listening',r));try{const url=`http://127.0.0.1:${srv.address().port}/api/funnels/${f.id}/campaigns/${c.id}/meta-controls`;const d=await(await fetch(url,{headers:{Authorization:owner}})).json();assert.equal(d.budget_enabled,false);assert.equal(d.checks.platform_enabled,true);assert.equal((await fetch(url+'/budget-preview',{method:'POST',headers:{Authorization:owner,'Content-Type':'application/json'},body:JSON.stringify({daily_cents:3500})})).status,409);for(const suffix of ['budget-preview','budget-apply'])assert.equal((await fetch(url+'/'+suffix,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);}finally{srv.closeAllConnections();await new Promise(r=>srv.close(r));}
});
