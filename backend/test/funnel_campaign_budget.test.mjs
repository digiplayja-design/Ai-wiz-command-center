import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {campaignBudgetSummary} from '../funnels/campaign_budget.mjs';

let db,server,base,f,c;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const today=new Date().toISOString().slice(0,10);
const day=n=>new Date(Date.parse(today)+n*86400000).toISOString().slice(0,10);
const plan={name:'Budget tracking',platform:'meta',headline:'Explore',body:'Contact us.',cta:'Learn more',audience:'Businesses',daily_cents:2500,days:4};
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const command=(name,action,data={},actor=owner,funnel=f.id)=>rpc(name,{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
const budget=(action='read',data={},actor=owner,funnel=f.id)=>command('korlix_funnel_campaign_budget_v1',action,{campaign_id:c.id,...data},actor,funnel);
const campaign=(action,data={})=>command('korlix_funnel_campaign_v1',action,{campaign_id:c.id,version:c.version,...data});
const http=(suffix='',body,actor=owner,query='')=>fetch(base+`/api/funnels/${f.id}/campaigns/${c.id}/budget`+suffix+query,{method:body?'POST':'GET',headers:{authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const actor of [owner,other,basic]){await db.query('insert into auth.users values($1)',[actor]);await db.query('insert into user_profiles values($1,$2)',[actor,actor===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql','20260923190107_funnel_campaign_budget_pacing.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 f=await command('korlix_funnel_v1','create',{name:'Budget test',slug:'budget-test',document:{brand:'Test',headline:'Next step',subheadline:'Contact us',cta:'Ask',thank_you:'Thank you',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'',contact_email:'',booking_url:''}},owner,null);
 c=await command('korlix_funnel_campaign_v1','create',plan);
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,environment:{},requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error();return{id:q.headers.authorization};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Private table/RPC deny browser roles; service RPC repeats tier and ownership',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec(`reset role;set role ${role}`);
  for(const sql of ['select * from korlix_funnel_campaign_budget_windows','delete from korlix_funnel_campaign_budget_windows','update korlix_funnel_campaign_budget_windows set start_date=null'])await assert.rejects(db.query(sql),/permission denied/);
  await assert.rejects(budget(),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 await assert.rejects(budget('read',{},basic),/Enterprise/);await assert.rejects(budget('read',{},other),/not found/);
 await assert.rejects(budget('read',{campaign_id:randomUUID()}),/not found/);
 const fn=(await db.query("select md5(prosrc) body_hash,prosecdef,proconfig,has_function_privilege('anon',oid,'execute') anon,has_function_privilege('authenticated',oid,'execute') authenticated,has_function_privilege('service_role',oid,'execute') service from pg_proc where proname='korlix_funnel_campaign_budget_v1'")).rows[0];
 assert.equal(fn.prosecdef,false);assert.equal(fn.anon,false);assert.equal(fn.authenticated,false);assert.equal(fn.service,true);assert.deepEqual(fn.proconfig,['search_path=public, pg_temp']);
 assert.equal((await db.query("select relrowsecurity from pg_class where relname='korlix_funnel_campaign_budget_windows'")).rows[0].relrowsecurity,true);
 await writeFile('/tmp/k178-function-hashes.json',JSON.stringify(fn,null,2));
});
test('Save a reporting window without altering plan version/review; read uses current plan and server UTC date',async()=>{
 const empty=await budget();assert.equal(empty.version,0);assert.equal(empty.start_date,null);assert.equal(campaignBudgetSummary(empty).pacing,null);
 const saved=await budget('save',{version:0,campaign_version:c.version,start_date:day(-2)});
 assert.equal(saved.version,1);assert.equal(saved.campaign_version,c.version);assert.equal(saved.start_date,day(-2));assert.equal(saved.as_of_date,today);
 assert.equal(saved.budget_enforced,false);assert.equal(saved.ad_publishing_ready,false);
 const actual=(await command('korlix_funnel_campaign_v1','list')).campaigns[0];assert.equal(actual.version,c.version);assert.equal(actual.state,c.state);
});
test('Missing days stay unknown, today is partial, outside reports are excluded and overspend remains signed',async()=>{
 for(const [offset,spend] of [[-3,99999999],[-2,0],[0,12000]])c=await campaign('report',{day:day(offset),spend_cents:spend,clicks:0,impressions:0});
 const p=campaignBudgetSummary(await budget()).pacing;
 assert.equal(p.planned_total_cents,10000);assert.equal(p.recorded_spend_cents,12000);assert.equal(p.balance_cents,-2000);
 assert.equal(p.completed_days,2);assert.equal(p.reported_completed_days,1);assert.deepEqual(p.missing_dates,[day(-1)]);
 assert.equal(p.completed_spend_cents,0);assert.equal(p.reported_days_variance_cents,-2500);assert.equal(p.excluded_report_days,1);
 assert.deepEqual(p.rows.map(r=>r.status),['recorded','missing','today','future']);assert.equal(p.rows[0].spend_cents,0);assert.equal(p.rows[1].spend_cents,null);
});
test('Concurrent saves, report edits and plan edits invalidate old versions; clear keeps a monotonic tombstone',async()=>{
 let b=await budget();
 await assert.rejects(budget('save',{version:0,campaign_version:c.version,start_date:day(-1)}),/changed/);
 c=await campaign('report',{day:day(-1),spend_cents:3000,clicks:0,impressions:0});
 await assert.rejects(budget('save',{version:b.version,campaign_version:b.campaign_version,start_date:day(-1)}),/changed/);
 c=await campaign('save',{...plan,daily_cents:3000,days:3});b=await budget();
 assert.equal(campaignBudgetSummary(b).pacing.planned_total_cents,9000);
 const cleared=await budget('clear',{version:b.version,campaign_version:c.version,confirmed:true});assert.equal(cleared.version,2);assert.equal(cleared.start_date,null);assert.equal(cleared.reports.length,4);
 await assert.rejects(budget('save',{version:b.version,campaign_version:c.version,start_date:today}),/changed/);
 const newer=await budget('save',{version:cleared.version,campaign_version:c.version,start_date:today});assert.equal(newer.version,3);
});
test('SQL independently rejects invalid dates, types, unsupported fields and unconfirmed clears',async()=>{
 const b=await budget(),data={version:b.version,campaign_version:c.version};
 for(const start_date of ['2026-02-30','2026-9-01','not a date',null,7,day(-731),day(366)])await assert.rejects(budget('save',{...data,start_date}));
 for(const extra of [{version:'3'},{version:-1},{version:3.5},{campaign_version:'5'},{actor:other},{start_date:null}])await assert.rejects(budget('save',{...data,start_date:today,...extra}));
 for(const confirmed of [false,'true',null])await assert.rejects(budget('clear',{...data,confirmed}),/Confirm/);
 await assert.rejects(budget('read',{unexpected:1}),/Unexpected/);await assert.rejects(budget('unsupported'),/supported/);
});
test('HTTP uses authentication, exact shape, no-store, stale-write conflicts and honest readiness',async()=>{
 assert.equal((await http('',null,'')).status,401);assert.equal((await http('',null,basic)).status,403);assert.equal((await http('',null,other)).status,404);
 assert.equal((await http('',null,owner,'?start_date=2026-01-01')).status,400);
 const response=await http(),body=await response.json();assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');assert.equal(body.reporting_source,'manual');assert.equal(body.budget_enforced,false);
 assert.equal((await http('/save',{version:0,campaign_version:c.version,start_date:today})).status,409);
 for(const extra of [{actor:other},{version:'3'},{start_date:'2026-02-30'}])assert.equal((await http('/save',{version:body.version,campaign_version:c.version,start_date:today,...extra})).status,400);
 assert.equal((await http('/clear',{version:body.version,campaign_version:c.version,confirmed:false})).status,400);
 const saved=await http('/save',{version:body.version,campaign_version:c.version,start_date:day(-2)});assert.equal(saved.status,200);assert.equal((await saved.json()).pacing.missing_dates.length,0);
});
test('Archive is read-only, downgrade blocks access, reporting windows cascade with campaign deletion',async()=>{
 let b=await budget();c=await campaign('archive',{confirmed:true});assert.equal((await budget()).state,'archived');
 await assert.rejects(budget('save',{version:b.version,campaign_version:c.version,start_date:today}),/Reopen/);await assert.rejects(budget('clear',{version:b.version,campaign_version:c.version,confirmed:true}),/Reopen/);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);await assert.rejects(budget(),/Enterprise/);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 c=await campaign('reopen');
 const another=await command('korlix_funnel_campaign_v1','create',plan);
 await budget('save',{campaign_id:another.id,version:0,campaign_version:another.version,start_date:today});
 await db.query('delete from korlix_funnel_campaigns where id=$1',[another.id]);assert.equal((await db.query('select 1 from korlix_funnel_campaign_budget_windows where campaign_id=$1',[another.id])).rows.length,0);
});
test('Shared route rate limit returns 429 and no-store',async()=>{
 let response;for(let i=0;i<35;i++)response=await http();assert.equal(response.status,429);assert.equal(response.headers.get('cache-control'),'no-store');
});

const snapshot=(extra={})=>({as_of_date:'2026-03-01',daily_cents:100,days:3,currency:'USD',reporting_source:'manual',budget_enforced:false,ad_publishing_ready:false,start_date:'2026-02-28',reports:[],...extra});
test('UTC arithmetic crosses leap days/year ends; future and finished windows preserve missing dates',()=>{
 assert.deepEqual(campaignBudgetSummary(snapshot({as_of_date:'2024-03-01',start_date:'2024-02-28'})).pacing.rows.map(r=>r.day),['2024-02-28','2024-02-29','2024-03-01']);
 const year=campaignBudgetSummary(snapshot({start_date:'2025-12-31'})).pacing;assert.equal(year.end_date,'2026-01-02');assert.equal(year.phase,'finished');assert.equal(year.missing_dates.length,3);
 const future=campaignBudgetSummary(snapshot({start_date:'2026-03-02'})).pacing;assert.equal(future.phase,'upcoming');assert.equal(future.completed_days,0);assert.equal(future.reported_days,0);assert.deepEqual(future.missing_dates,[]);
});
test('Bounded integer sums retain precision at maximum spend; malformed source fails closed',()=>{
 const reports=Array.from({length:90},(_,i)=>({day:new Date(Date.parse('2026-01-01')+i*86400000).toISOString().slice(0,10),spend_cents:100000000}));
 const p=campaignBudgetSummary(snapshot({as_of_date:'2026-04-02',start_date:'2026-01-01',days:90,daily_cents:1000000,reports})).pacing;
 assert.equal(p.recorded_spend_cents,9000000000);assert.equal(p.balance_cents,-8910000000);
 for(const extra of [{currency:'JMD'},{budget_enforced:true},{ad_publishing_ready:true},{days:0},{daily_cents:1.5},{start_date:'2026-02-30'},
  {reports:[{day:'2026-03-02',spend_cents:1}]},{reports:[{day:'2026-02-28',spend_cents:-1}]},{reports:[{day:'2026-02-28',spend_cents:0},{day:'2026-02-28',spend_cents:0}]}])assert.throws(()=>campaignBudgetSummary(snapshot(extra)));
});
