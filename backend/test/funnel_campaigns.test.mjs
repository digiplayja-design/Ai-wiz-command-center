import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
import {createCampaignStore,campaignInput,reportInput} from '../funnels/campaigns.mjs';
let db,server,base,f,c,generations=0;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const doc={brand:'Test',headline:'Your next step',subheadline:'Contact our business.',cta:'Ask us',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'hello@example.com',booking_url:''};
const plan={name:'Autumn launch',platform:'meta',headline:'Explore our services',body:'Ask our team about your needs.',cta:'Learn more',audience:'Local businesses seeking our services.',daily_cents:2500,days:14};
const rpc=async(name,p)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_id??p.p_funnel,JSON.stringify(p.p_data??{})])).rows[0].r;
const funnel=(actor,action,id=null,data={})=>rpc('korlix_funnel_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
const campaign=(actor,action,id=f.id,data={})=>rpc('korlix_funnel_campaign_v1',{p_actor:actor,p_action:action,p_funnel:id,p_data:data});
const payload=(extra={})=>({campaign_id:c.id,version:c.version,...extra});
const request=(path,body,actor=owner,method='POST')=>fetch(base+'/api/funnels/'+f.id+'/campaigns'+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922090333_funnel_campaign_workspace.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 f=await funnel(owner,'create',null,{name:'Services',slug:'services',document:doc});
 const database={rpc:async(name,p)=>{try{return{data:await rpc(name,p)}}catch(error){return{error}}}};
 const app=express();app.use(express.json());registerFunnels(app,{store:createFunnelStore(database),campaignStore:createCampaignStore(database),environment:{OPENAI_API_KEY:'test-not-real'},requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};},generateAdCopy:async()=>{generations++;return plan;}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});
test('Browser roles and other owners cannot read or mutate campaign data',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec(`reset role;set role ${role}`);
  for(const table of ['korlix_funnel_campaigns','korlix_funnel_campaign_reports'])for(const sql of [`select * from ${table}`,`delete from ${table}`,`update ${table} set updated_at=now()`])await assert.rejects(db.query(sql),/permission denied/);
  await assert.rejects(campaign(owner,'create',f.id,plan),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 await assert.rejects(campaign(other,'list'),/not found/);await assert.rejects(campaign(basic,'create',f.id,plan),/Enterprise/);
});
test('Plans are persisted without ad publication; review requires a published page and exact version',async()=>{
 c=await campaign(owner,'create',f.id,plan);assert.equal(c.state,'draft');
 await assert.rejects(campaign(owner,'review',f.id,payload({confirmed:true})),/Publish/);
 f=await funnel(owner,'publish',f.id,{version:f.version,confirmed:true});
 await assert.rejects(campaign(owner,'review',f.id,payload()),/confirm/);
 c=await campaign(owner,'review',f.id,payload({confirmed:true}));assert.equal(c.state,'reviewed');
 const out=await campaign(owner,'list');assert.equal(out.campaigns[0].review_current,true);
 await assert.rejects(campaign(owner,'save',f.id,payload({...plan,version:1})),/changed/);
 await assert.rejects(campaign(owner,'save',f.id,payload({...plan,platform:'google'})),/channel stays fixed/);
});
test('Editing or republishing invalidates plan review; archive never claims to pause an external ad',async()=>{
 c=await campaign(owner,'save',f.id,payload({...plan,name:'Renamed'}));assert.equal(c.state,'draft');
 c=await campaign(owner,'review',f.id,payload({confirmed:true}));
 f=await funnel(owner,'save',f.id,{version:f.version,name:'Services',document:{...doc,headline:'Updated offer'}});f=await funnel(owner,'publish',f.id,{version:f.version,confirmed:true});
 assert.equal((await campaign(owner,'list')).campaigns[0].review_current,false);
 c=await campaign(owner,'archive',f.id,payload({confirmed:true}));assert.equal(c.state,'archived');
 await assert.rejects(campaign(owner,'save',f.id,payload(plan)),/Reopen/);
 c=await campaign(owner,'reopen',f.id,payload());assert.equal(c.state,'draft');
});
test('Daily manual reports replace the same day, reject stale writes and use matching UTC days for lead costs',async()=>{
 const today=new Date().toISOString().slice(0,10),yesterday=new Date(Date.now()-86400000).toISOString().slice(0,10);
 const tag='k143_'+c.id.replaceAll('-','');
 for(const [day,source] of [[today,'facebook'],[yesterday,'facebook'],[today,'google']])await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,utm,consent_text,created_at) values($1,$2,1,'Test','test@example.com',$3,'test',$4)`,[f.id,randomUUID(),JSON.stringify({utm_campaign:tag,utm_source:source}),day+'T12:00:00Z']);
 c=await campaign(owner,'report',f.id,payload({day:today,spend_cents:2500,clicks:10,impressions:1000,note:'Entered from platform dashboard'}));
 const stale=c.version;c=await campaign(owner,'report',f.id,payload({day:today,spend_cents:3000,clicks:12,impressions:1100}));
 await assert.rejects(campaign(owner,'report',f.id,payload({version:stale,day:today,spend_cents:1,clicks:1,impressions:1})),/changed/);
 const item=(await campaign(owner,'list')).campaigns[0];assert.equal(item.reports.length,1);assert.equal(item.reports[0].spend_cents,3000);assert.equal(item.tagged_leads,2);assert.equal(item.covered_leads,1);
 await assert.rejects(campaign(owner,'report',f.id,payload({day:'2099-01-01',spend_cents:1,clicks:1,impressions:1})),/reporting date/);
 c=await campaign(owner,'removeReport',f.id,payload({day:today,confirmed:true}));assert.equal((await campaign(owner,'list')).campaigns[0].covered_leads,0);
});
test('HTTP fails closed and supplies stable links and honest platform readiness',async()=>{
 assert.equal((await request('',null,'','GET')).status,401);assert.equal((await request('',null,basic,'GET')).status,403);assert.equal((await request('',null,other,'GET')).status,404);
 const out=await(await request('',null,owner,'GET')).json();assert.equal(out.ad_publishing_ready,false);assert.equal(out.reporting_source,'manual');
 const url=new URL(out.campaigns[0].tracking_url);assert.equal(url.searchParams.get('utm_campaign'),'k143_'+c.id.replaceAll('-',''));assert.equal(out.campaigns[0].planned_total_cents,35000);
 assert.equal((await request('/save',payload({...plan,daily_cents:-1}))).status,400);
 assert.equal((await request('/review',payload())).status,400);
 assert.equal((await request('/generate',{brief:'Draft'},other)).status,404);assert.equal(generations,0);
 assert.equal((await request('/generate',{brief:'Draft'},basic)).status,403);assert.equal(generations,0);
 assert.equal((await request('/generate',{brief:'Draft'})).status,200);assert.equal(generations,1);
 for(let i=1;i<10;i++)await funnel(owner,'budget');
 assert.equal((await request('/generate',{brief:'Draft'})).status,429);assert.equal(generations,1);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await request('/archive',payload({confirmed:true}))).status,403);
});
test('Inputs reject nonfinite, fractional, excessive, malformed and impossible values',()=>{
 for(const value of [-1,0,1.5,Infinity,1000001,'2500'])assert.throws(()=>campaignInput({...plan,daily_cents:value}));
 for(const day of ['2026-02-30','today',null,'2026-1-1'])assert.throws(()=>reportInput({day,spend_cents:0,clicks:0,impressions:0}));
 assert.throws(()=>campaignInput({...plan,headline:'x'.repeat(181)}));assert.throws(()=>campaignInput({...plan,platform:'invented'}));
});
