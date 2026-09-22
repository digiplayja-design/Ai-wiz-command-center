import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {createRehearsalStore,rehearseFunnel,rehearsalText} from '../funnels/rehearsal.mjs';

const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const f=randomUUID(),empty=randomUUID(),foreign=randomUUID();
const doc={brand:'KORLIX AI',headline:'Let’s talk',subheadline:'Tell us about your goals.',cta:'Ask us',
 thank_you:'Thank you. Our team will review your inquiry.',layout:'consultation',accent:'cyan',
 benefits:['Discuss your priorities'],faq:[],privacy_url:'https://example.com/privacy',
 contact_email:'team@example.com',booking_url:'https://example.com/book'};
const input=(overrides={})=>({source:'draft',scenario:'valid',version:1,name:'Editor draft',document:doc,...overrides});
let db,server,base;
const querySnapshot=async(actor=owner,id=f)=>(await db.query('select korlix_funnel_rehearsal_v1($1,$2) v',[actor,id])).rows[0].v;
const post=(body=input(),actor=owner,id=f)=>fetch(base+`/api/funnels/${id}/rehearsal`,{
 method:'POST',headers:{'Content-Type':'application/json',...(actor?{Authorization:actor}:{})},body:JSON.stringify(body),
});
test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);
 create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,
 consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);
 grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;
 grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]) {
  await db.query('insert into auth.users values($1)',[u]);
  await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);
 }
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql',
  '20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql',
  '20260922163931_funnel_rehearsal_readonly.sql']) await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 for(const [id,user] of [[f,owner],[empty,owner],[foreign,other]]) {
  await db.query("insert into korlix_funnels(id,user_id,name,slug,draft,published,state,published_version) values($1,$2,'Saved funnel',$3,$4,$5,'published',1)",
   [id,user,'rehearsal-'+id,doc,{...doc,brand:'Published brand'}]);
 }
 const lead=randomUUID();
 await db.query("insert into korlix_funnel_leads(id,funnel_id,request_id,published_version,name,email,consent_text) values($1,$2,$3,1,'Existing inquiry','existing@example.com','Inquiry only')",[lead,f,randomUUID()]);
 await db.query("insert into korlix_funnel_followup_settings(funnel_id,enabled,email_enabled,call_enabled,delay_minutes,subject,body) values($1,true,true,true,60,'Your inquiry at {{brand}}','Hi {{name}}, {{brand}} / {{funnel}} / {{booking_url}}')",[f]);
 await db.query("insert into korlix_funnel_followup_tasks(funnel_id,lead_id,channel,state,due_at,subject,body,to_email,updated_at) values($1,$2,'email','processing',now(),'Existing subject','Existing body','existing@example.com',now()-interval '10 minutes')",[f,lead]);
 const rehearsalStore=createRehearsalStore({rpc:async(name,p)=>{
  assert.equal(name,'korlix_funnel_rehearsal_v1');
  await db.exec('begin read only');
  try {const data=await querySnapshot(p.p_actor,p.p_id);await db.exec('commit');return{data};}
  catch(error) {await db.exec('rollback');return{error};}
 }});
 const app=express();app.use(express.json());
 registerFunnels(app,{rehearsalStore,environment:{},requireUser:async q=>{
  if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');
  return{id:q.headers.authorization};
 },followups:new Proxy({}, {get:()=>()=>{throw Error('Rehearsal touched the live follow-up service');}})});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Browser roles are denied; current Enterprise membership and ownership are required',async()=>{
 for(const role of ['anon','authenticated']) {
  await db.exec(`reset role;set role ${role}`);await assert.rejects(querySnapshot(),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 for(const [actor,status] of [[null,401],[other,404],[basic,403]]) assert.equal((await post(input(),actor)).status,status);
 assert.equal((await post(input(),owner,foreign)).status,404);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await post()).status,403);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Rehearsal runs in a read-only transaction and does not initialize settings or reconcile stale tasks',async()=>{
 const tables=['korlix_funnels','korlix_funnel_leads','korlix_funnel_followup_settings','korlix_funnel_followup_tasks','korlix_funnel_sequences','korlix_contacts','korlix_agent_email_recipients','korlix_funnel_usage'];
 const snapshot=async()=>Promise.all(tables.map(async table=>(await db.query(`select coalesce(jsonb_agg(to_jsonb(t)),'[]') v from public.${table} t`)).rows[0].v));
 const before=await snapshot();
 for(const id of [f,empty])for(const scenario of ['valid','missing_consent','invalid_email']) {
  const r=await post(input({scenario}),owner,id);assert.equal(r.status,200);
  const result=await r.json();assert.equal(result.kind,'simulation');assert.equal(result.delivery_tested,false);
  assert.deepEqual(result.performed_actions,[]);assert.equal(r.headers.get('cache-control'),'no-store');
 }
 assert.deepEqual(await snapshot(),before);
 const fn=(await db.query("select provolatile,prosecdef,proconfig from pg_proc where proname='korlix_funnel_rehearsal_v1'")).rows[0];
 assert.equal(fn.provolatile,'s');assert.equal(fn.prosecdef,false);assert.deepEqual(fn.proconfig,['search_path=public, pg_temp']);
});
test('Saved workflow and existing database interpolation produce matching preview messages',async()=>{
 const r=await(await post()).json();assert.equal(r.tasks.length,2);assert.equal(r.tasks[0].delay_minutes,60);
 assert.equal(r.tasks[0].subject,'Your inquiry at KORLIX AI');assert.equal(r.tasks[0].state,'review');
 const template='{{name}} / {{brand}} / {{funnel}} / {{booking_url}}';
 const dbText=(await db.query('select korlix_funnel_followup_text_v1($1,$2,$3,$4,$5) v',
  [template,'Taylor Morgan','{{name}}','{{brand}}','{{funnel}}'])).rows[0].v;
 assert.equal(rehearsalText(template,{name:'Taylor Morgan'},{brand:'{{name}}',booking_url:'{{funnel}}'},'{{brand}}',6000),dbText);
 assert.equal(rehearsalText('🟦'.repeat(205),{name:'Taylor'},doc,'Name',200), '🟦'.repeat(200));
 const normalized=await(await post(input({document:{...doc,brand:'  Trimmed brand  ',thank_you:'  Thank you  ',booking_url:'https://example.com'}}))).json();
 assert.equal(normalized.tasks[0].subject,'Your inquiry at Trimmed brand');
 assert.deepEqual(normalized.receipt,{message:'Thank you',booking_url:'https://example.com/'});
});
test('Draft and published sources stay separate; paused pages block only the published scenario',async()=>{
 const draft=await(await post(input({document:{...doc,brand:'Unsaved brand'}}))).json();
 assert.equal(draft.tasks[0].subject,'Your inquiry at Unsaved brand');
 const published=await(await post(input({source:'published',document:{...doc,brand:'Ignored'}}))).json();
 assert.equal(published.tasks[0].subject,'Your inquiry at Published brand');
 await db.query("update korlix_funnels set state='paused' where id=$1",[f]);
 const paused=await(await post(input({source:'published'}))).json();assert.equal(paused.accepted_in_scenario,false);assert.deepEqual(paused.tasks,[]);
 const hypothetical=await(await post()).json();assert.equal(hypothetical.accepted_in_scenario,true);assert.equal(hypothetical.checks[0].status,'scenario');
 await db.query("update korlix_funnels set state='published' where id=$1",[f]);
});
test('Invalid samples and missing page details never predict a received inquiry or task',async()=>{
 for(const patch of [{scenario:'missing_consent'},{scenario:'invalid_email'},{document:{...doc,privacy_url:''}},{document:{...doc,contact_email:''}}]) {
  const r=await(await post(input(patch))).json();assert.equal(r.accepted_in_scenario,false);assert.deepEqual(r.tasks,[]);assert.equal(r.receipt,null);
  assert.ok(r.checks.some(c=>c.status==='blocked'));
 }
 const disabled=await(await post(input(),owner,empty)).json();assert.equal(disabled.accepted_in_scenario,true);assert.equal(disabled.workflow_configured,false);assert.deepEqual(disabled.tasks,[]);
});
test('Stale versions, invalid inputs and unavailable deployments fail without invented success',async()=>{
 for(const [patch,status] of [[{version:99},409],[{scenario:'send_email'},400],[{source:'other'},400],[{name:''},400]]) assert.equal((await post(input(patch))).status,status);
 const state=await querySnapshot();assert.throws(()=>rehearseFunnel(state,null),/Choose/);
 await assert.rejects(createRehearsalStore() (owner,f),/not available/);
 await assert.rejects(createRehearsalStore({rpc:async()=>({error:{code:'PGRST202',message:'secret detail'}})})(owner,f),e=>e.status===503&&!e.message.includes('secret'));
});
