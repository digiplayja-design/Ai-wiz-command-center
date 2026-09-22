import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { createFunnelFollowups,createFollowupStore,followupSettings } from '../funnels/followups.mjs';
import { createFunnelScheduler } from '../funnels/scheduler.mjs';
import { registerFunnels } from '../funnels/routes.mjs';
import { korlixAgentEmailDraftInput } from '../korlix_agent_email.mjs';

const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
let db;
const funnel=async(u,a,f=null,p={})=>(await db.query('select korlix_funnel_v1($1,$2,$3,$4::jsonb) v',[u,a,f,JSON.stringify(p)])).rows[0].v;
const cmd=async(u,a,f,p={})=>(await db.query('select korlix_funnel_followup_v1($1,$2,$3,$4::jsonb) v',[u,a,f,JSON.stringify(p)])).rows[0].v;
const seq=async(u,a,f,p={})=>(await db.query('select korlix_funnel_sequence_v1($1,$2,$3,$4::jsonb) v',[u,a,f,JSON.stringify(p)])).rows[0].v;
const due=async u=>(await db.query('select korlix_funnel_scheduled_due_v1($1) v',[u])).rows[0].v;
const store=createFollowupStore({rpc:async(name,p)=>{try{return {data:name==='korlix_funnel_scheduled_due_v1'?await due(p.p_owner):name==='korlix_funnel_sequence_v1'?await seq(p.p_actor,p.p_action,p.p_id,p.p_data):await cmd(p.p_actor,p.p_action,p.p_id,p.p_data)}}catch(error){return{error}}}});
const doc={brand:'Example',headline:'Example',subheadline:'Example',cta:'Ask',thank_you:'Thanks',benefits:[],faq:[],layout:'consultation',accent:'cyan',privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const settings=(s,extra={})=>({...s,enabled:true,confirmed:true,...extra});
async function create(extra={}) {
  let f=await funnel(owner,'create',null,{name:'Follow-ups',slug:'fu-'+randomUUID(),document:doc});
  f=await funnel(owner,'publish',f.id,{version:1,confirmed:true});
  const state=await cmd(owner,'state',f.id);
  await cmd(owner,'settings',f.id,settings(state.settings,extra));
  return f;
}
async function lead(f,extra={}) {
  const p={slug:f.slug,published_version:f.published_version,request_id:randomUUID(),name:'Taylor',email:randomUUID()+'@example.com',phone:'+12025550123',message:'Please explain the service.',utm:{},...extra};
  await funnel(null,'lead',null,p);
  return (await db.query('select * from korlix_funnel_leads where request_id=$1',[p.request_id])).rows[0];
}
async function task(f,l) {return (await cmd(owner,'state',f.id,{filter:'all'})).tasks.find(t=>t.lead_id===l.id&&t.channel==='email');}
function service({failSend=false,failBeforeProvider=false,changed=false,lateSuppression=false,autopilot=true}={}) {
  const records=new Map();let sends=0,recipients=0, approvals=0;
  const mailStore={findRecipientByEmail:async()=>null,findMessageByIdempotency:async(_u,_a,k)=>records.get(k)};
  const drafts={
    saveRecipient:async()=>{recipients++;return{recipient:{id:randomUUID()}};},
    createDraft:async({body})=>{
      const input=korlixAgentEmailDraftInput(body),k=input.idempotencyKey;
      if(!records.has(k))records.set(k,{id:randomUUID(),subject:input.subject,textBody:input.textBody,recipientId:input.recipientId,toEmail:'',idempotencyKey:k,htmlBody:'',messageKind:'transactional',status:'draft',attempt_count:0});
      const raw=records.get(k); const id=k.split(':')[1];raw.toEmail=(await cmd(owner,'get',currentF,{task_id:id})).task.to_email;
      if(changed)raw.subject='Changed in another window';
      return{draft:{...raw}};
    },
    approveDraft:async({messageId})=>{approvals++;const raw=[...records.values()].find(x=>x.id===messageId);raw.status='approved';
      if(lateSuppression){const t=(await cmd(owner,'get',currentF,{task_id:raw.idempotencyKey.split(':')[1]}));await db.query('update korlix_contacts set do_not_contact=true where id=$1',[t.contact.id]);}
      return{draft:{...raw}};
    },
    getDraft:async({messageId})=>({draft:{...[...records.values()].find(x=>x.id===messageId)}}),
  };
  let currentF;
  const delivery={getDeliveryStatus:async()=>({canSend:true,canAutopilot:autopilot}),sendApprovedDraft:async({messageId,scheduled,beforeProvider})=>{
    if(scheduled)assert(autopilot);
    await beforeProvider?.();
    if(failBeforeProvider)throw Error('pre-provider unavailable');
    sends++;const raw=[...records.values()].find(x=>x.id===messageId);raw.attempt_count++;
    if(failSend){raw.status='sending';throw Error('provider timeout');}
    raw.status='sent';raw.provider_message_id='provider-test-id';return{sent:true};
  }};
  const svc=createFunnelFollowups({store,emailStore:mailStore,drafts,delivery,environment:{KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'test'}});
  return {svc,records,setF:f=>currentF=f,sends:()=>sends,recipients:()=>recipients,approvals:()=>approvals};
}
test.before(async()=>{
  db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
  for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
  for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  await db.exec('set role service_role');
});
test.after(async()=>db.close());
test('Private queue enforces browser grants, current Enterprise membership, and funnel ownership',async()=>{
  const f=await create();
  await assert.rejects(cmd(other,'state',f.id),/not found/);await assert.rejects(cmd(basic,'state',f.id),/Enterprise/);
  for(const role of ['anon','authenticated']) {
    await db.exec('reset role;set role '+role);
    await assert.rejects(db.query('select * from korlix_funnel_followup_tasks'),/permission denied/);
    await assert.rejects(cmd(owner,'state',f.id),/permission denied/);
    await assert.rejects(db.query('select korlix_funnel_followup_enqueue_v1($1)',[randomUUID()]),/permission denied/);
  }
  await db.exec('reset role;set role service_role');
});
test('Disabled workflow creates no tasks; enabled insert trigger queues channels atomically with immutable template snapshots',async()=>{
  const f=await create({enabled:false,call_enabled:true});const first=await lead(f);
  assert.equal((await cmd(owner,'state',f.id)).tasks.length,0);
  const s=(await cmd(owner,'state',f.id)).settings;
  await assert.rejects(cmd(owner,'settings',f.id,{...s,enabled:true}),/confirm/);
  await cmd(owner,'settings',f.id,settings(s));const l=await lead(f);
  const state=await cmd(owner,'state',f.id);assert.equal(state.tasks.length,2);assert.equal(state.tasks[0].call_allowed,false);
  assert(!JSON.stringify(state).includes('approval_nonce'));
  const email=await task(f,l);assert.match(email.body,/Hi Taylor/);assert.match(email.subject,/Example/);
  await cmd(owner,'settings',f.id,settings(state.settings,{subject:'New subject'}));assert.equal((await task(f,l)).subject,email.subject);
  for(let i=0;i<2;i++)await cmd(owner,'enqueue',f.id,{lead_id:first.id});
  assert.equal((await cmd(owner,'state',f.id)).total,4);
});
test('Delay, optimistic versions, pause, disabled email channel and current contact permission block sending',async()=>{
  const f=await create({delay_minutes:60}),l=await lead(f);let t=await task(f,l);
  await assert.rejects(cmd(owner,'claim',f.id,{task_id:t.id,version:t.version,confirmed:true}),/not due/);
  await db.query("update korlix_funnel_followup_tasks set due_at=now()-interval '1 minute' where id=$1",[t.id]);
  await assert.rejects(cmd(owner,'edit',f.id,{task_id:t.id,version:999,subject:'A',body:'B'}),/changed/);
  t=await cmd(owner,'edit',f.id,{task_id:t.id,version:t.version,subject:'Personal response',body:'Hi Taylor.'});
  const s=(await cmd(owner,'state',f.id)).settings;
  await cmd(owner,'settings',f.id,settings(s,{email_enabled:false,call_enabled:true}));
  await assert.rejects(cmd(owner,'claim',f.id,{task_id:t.id,version:t.version,confirmed:true}),/paused/);
  await cmd(owner,'settings',f.id,settings({...s,version:s.version+1}));
  await db.query("update korlix_contacts set email_permission='none' where id=$1",[l.contact_id]);
  assert.equal((await task(f,l)).email_allowed,false);
  await assert.rejects(cmd(owner,'claim',f.id,{task_id:t.id,version:t.version,confirmed:true}),/permit/);
  await db.query("update user_profiles set tier='basic' where id=$1",[owner]);await assert.rejects(cmd(owner,'claim',f.id,{task_id:t.id,version:t.version,confirmed:true}),/Enterprise/);
  await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('One owner-reviewed email uses NOVA and repeat clicks cannot create duplicate sends',async()=>{
  const f=await create(),l=await lead(f),t=await task(f,l);const s=service();s.setF(f.id);
  await assert.rejects(s.svc.send(owner,f.id,{task_id:t.id,version:t.version}),/Review/);assert.equal(s.sends(),0);
  const results=await Promise.allSettled([1,2].map(()=>s.svc.send(owner,f.id,{task_id:t.id,version:t.version,confirmed:true})));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(s.sends(),1);assert.equal(s.approvals(),1);assert.equal(s.recipients(),1);
  assert.equal((await task(f,l)).state,'sent');assert(!JSON.stringify(results).includes('approval_nonce'));
});
test('Changed email content and late contact suppression fail before provider execution',async()=>{
  for(const extra of [{changed:true},{lateSuppression:true}]) {
    const f=await create(),l=await lead(f),t=await task(f,l);const s=service(extra);s.setF(f.id);
    await assert.rejects(s.svc.send(owner,f.id,{task_id:t.id,version:t.version,confirmed:true}));assert.equal(s.sends(),0);assert.equal((await task(f,l)).state,'needs_review');
  }
});
test('Uncertain provider outcomes are reconciled without resending; an accepted receipt clears the task',async()=>{
  const f=await create(),l=await lead(f),t=await task(f,l),s=service({failSend:true});s.setF(f.id);
  await assert.rejects(s.svc.send(owner,f.id,{task_id:t.id,version:t.version,confirmed:true}),/confirmed/);assert.equal(s.sends(),1);
  assert.equal((await s.svc.reconcile(owner,f.id,t.id)).task.state,'needs_review');assert.equal(s.sends(),1);
  const raw=[...s.records.values()][0];raw.status='sent';raw.provider_message_id='accepted';
  assert.equal((await s.svc.reconcile(owner,f.id,t.id)).task.state,'sent');assert.equal(s.sends(),1);
});
test('A pre-provider failure can return to review; stale processing is never automatically resent',async()=>{
  const f=await create(),l=await lead(f),t=await task(f,l),s=service({failBeforeProvider:true});s.setF(f.id);
  await assert.rejects(s.svc.send(owner,f.id,{task_id:t.id,version:t.version,confirmed:true}));
  assert.equal((await s.svc.reconcile(owner,f.id,t.id)).task.state,'review');assert.equal(s.sends(),0);
  let fresh=await task(f,l);await cmd(owner,'claim',f.id,{task_id:t.id,version:fresh.version,confirmed:true});
  await db.query("update korlix_funnel_followup_tasks set updated_at=now()-interval '6 minutes' where id=$1",[t.id]);
  assert.equal((await task(f,l)).state,'needs_review');assert.equal(s.sends(),0);
});
test('Call review has no provider path; completing review is distinct from placing a call',async()=>{
  const f=await create({email_enabled:false,call_enabled:true});await lead(f);const t=(await cmd(owner,'state',f.id)).tasks[0];
  await assert.rejects(cmd(owner,'claim',f.id,{task_id:t.id,version:t.version,confirmed:true}));
  assert.equal((await cmd(owner,'resolve',f.id,{task_id:t.id,version:t.version,state:'done',note:'Reviewed only.'})).state,'done');
});
test('Bounded templates, pagination, and archive suppression keep the queue manageable',async()=>{
  assert.throws(()=>followupSettings({version:1,enabled:true,email_enabled:true,call_enabled:false,delay_minutes:0,subject:'{{password}}',body:'Hi'}),/placeholders/);
  const f=await create({body:'{{name}}'.repeat(450)});
  for(let i=0;i<26;i++)await lead(f,{name:'A'.repeat(160)});
  const first=await cmd(owner,'state',f.id);assert.equal(first.total,26);assert.equal(first.tasks.length,25);assert.equal(first.tasks[0].body.length,6000);
  const last=await cmd(owner,'state',f.id,{offset:25});assert.equal(last.tasks.length,1);
  await db.query('update korlix_contacts set archived_at=now() where id=$1',[last.tasks[0].contact_id]);assert.equal((await cmd(owner,'state',f.id,{offset:25})).tasks[0].email_allowed,false);
});
test('HTTP endpoints reject anonymous users and cross-owner task mutations',async()=>{
  const f=await create(),app=express();app.use(express.json());registerFunnels(app,{followups:createFunnelFollowups({store}),requireUser:async q=>({id:q.headers.authorization})});
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  try {
    const url='http://127.0.0.1:'+server.address().port+'/api/funnels/'+f.id+'/followups';
    assert.equal((await fetch(url)).status,401);assert.equal((await fetch(url,{headers:{Authorization:other}})).status,404);
    assert.equal((await fetch(url,{headers:{Authorization:basic}})).status,403);assert.equal((await fetch(url,{headers:{Authorization:owner}})).status,200);
    for(const action of ['createSequence','resumeSequence','pauseSequence','cancelSequence','replySequence'])assert.equal((await fetch(url+'/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
    assert.equal((await fetch(url+'/sequences/'+randomUUID(),{headers:{Authorization:other}})).status,404);
    assert.equal((await fetch(url+'/send',{method:'POST',headers:{Authorization:other,'Content-Type':'application/json'},body:JSON.stringify({task_id:randomUUID(),version:1,confirmed:true})})).status,404);
  }finally{await new Promise(r=>server.close(r));}
});

const later=()=>new Date(Date.now()+3600000).toISOString();
async function scheduled(f,l,s=service()) {
  s.setF(f.id);const t=await task(f,l);
  const r=await s.svc.schedule(owner,f.id,{task_id:t.id,version:t.version,confirmed:true,scheduled_for:later()});
  return {s,t:r.task};
}
async function ready(id) {await db.query("update korlix_funnel_followup_tasks set scheduled_for=now()-interval '1 minute' where id=$1",[id]);}
test('Schedules require exact approval, valid timing, Autopilot and ownership; editing or manual send cannot bypass a schedule',async()=>{
  const f=await create(),l=await lead(f),t=await task(f,l),s=service();s.setF(f.id);
  for(const body of [
    {task_id:t.id,version:t.version,scheduled_for:later()},
    {task_id:t.id,version:t.version,confirmed:true,scheduled_for:'2026-09-22 12:00'},
    {task_id:t.id,version:t.version,confirmed:true,scheduled_for:new Date().toISOString()},
    {task_id:t.id,version:t.version,confirmed:true,scheduled_for:new Date(Date.now()+32*86400000).toISOString()},
  ])await assert.rejects(s.svc.schedule(owner,f.id,body));
  await assert.rejects(s.svc.schedule(other,f.id,{task_id:t.id,version:t.version,confirmed:true,scheduled_for:later()}),/not found/);
  await assert.rejects(service({autopilot:false}).svc.schedule(owner,f.id,{task_id:t.id,version:t.version,confirmed:true,scheduled_for:later()}),/Autopilot/);
  const r=await s.svc.schedule(owner,f.id,{task_id:t.id,version:t.version,confirmed:true,scheduled_for:later()});
  assert.equal(r.task.state,'scheduled');assert(r.task.scheduled_approved_at);assert.equal(s.sends(),0);assert.equal(s.recipients(),0);assert.equal(s.records.size,0);
  assert.equal((await cmd(owner,'state',f.id)).counts.scheduled,1);
  await assert.rejects(s.svc.edit(owner,f.id,{task_id:t.id,version:r.task.version,subject:'Changed',body:'Changed'}),/Only/);
  await assert.rejects(s.svc.send(owner,f.id,{task_id:t.id,version:r.task.version,confirmed:true}),/already/);
  assert.deepEqual(await s.svc.runScheduled(),{checked:0,sent:0});
  await s.svc.cancelSchedule(owner,f.id,{task_id:t.id,version:r.task.version});
});
test('Durable schedules send through NOVA after a simulated process restart and overlapping runners send once',async()=>{
  const f=await create(),l=await lead(f);const {t}=await scheduled(f,l);await ready(t.id);
  const restarted=service();restarted.setF(f.id);
  const results=await Promise.all([restarted.svc.runScheduled(),restarted.svc.runScheduled()]);
  assert.equal(results.reduce((n,r)=>n+r.sent,0),1);assert.equal(restarted.sends(),1);
  assert.equal((await task(f,l)).state,'sent');assert.equal((await restarted.svc.runScheduled()).sent,0);
});
test('Cancel, workflow pause and page pause require fresh approval before another scheduled send',async()=>{
  for(const action of ['cancel','workflow','page']) {
    const f=await create(),l=await lead(f),{s,t}=await scheduled(f,l);
    if(action==='cancel') {
      await assert.rejects(s.svc.cancelSchedule(owner,f.id,{task_id:t.id,version:1}),/changed/);
      await s.svc.cancelSchedule(owner,f.id,{task_id:t.id,version:t.version});
    }
    if(action==='workflow') {const st=(await cmd(owner,'state',f.id)).settings;await cmd(owner,'settings',f.id,settings(st,{enabled:false}));await cmd(owner,'settings',f.id,settings({...st,version:st.version+1}));}
    if(action==='page') {const paused=await funnel(owner,'pause',f.id,{version:f.version});await funnel(owner,'publish',f.id,{version:paused.version,confirmed:true});}
    const after=await task(f,l);assert.equal(after.state,'review');assert.equal(after.scheduled_approved_at,null);assert.equal(after.scheduled_for,null);
    assert.equal((await s.svc.runScheduled()).sent,0);assert.equal(s.sends(),0);
  }
});
test('Due-time downgrade, contact suppression, stale schedules and paused NOVA return to review without outreach',async()=>{
  for(const change of ['downgrade','consent','address','archive','expired','autopilot']) {
    const f=await create(),l=await lead(f),{t}=await scheduled(f,l);await ready(t.id);
    if(change==='downgrade')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
    if(change==='consent')await db.query('update korlix_contacts set do_not_contact=true where id=$1',[l.contact_id]);
    if(change==='address')await db.query("update korlix_contacts set email='changed@example.com' where id=$1",[l.contact_id]);
    if(change==='archive')await db.query('update korlix_contacts set archived_at=now() where id=$1',[l.contact_id]);
    if(change==='expired')await db.query("update korlix_funnel_followup_tasks set scheduled_for=now()-interval '25 hours' where id=$1",[t.id]);
    const s=service({autopilot:change!=='autopilot'});s.setF(f.id);assert.equal((await s.svc.runScheduled()).sent,0);assert.equal(s.sends(),0);
    await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);assert.equal((await task(f,l)).state,'review');
  }
});
test('Scheduled ambiguous provider outcome and interrupted claims never automatically retry',async()=>{
  const f=await create(),l=await lead(f),{t}=await scheduled(f,l);await ready(t.id);
  const s=service({failSend:true});s.setF(f.id);await s.svc.runScheduled();assert.equal(s.sends(),1);assert.equal((await task(f,l)).state,'needs_review');
  await s.svc.runScheduled();assert.equal(s.sends(),1);
  const l2=await lead(f),{t:t2}=await scheduled(f,l2);
  await ready(t2.id);await cmd(owner,'claim_scheduled',f.id,{task_id:t2.id,version:t2.version,agent_id:'nova'});
  await db.query("update korlix_funnel_followup_tasks set updated_at=now()-interval '6 minutes' where id=$1",[t2.id]);
  await s.svc.runScheduled();assert.equal((await task(f,l2)).state,'needs_review');assert.equal(s.sends(),1);
});
test('Browser roles cannot scan due schedules and call tasks cannot be scheduled',async()=>{
  const f=await create({email_enabled:false,call_enabled:true});await lead(f);const t=(await cmd(owner,'state',f.id)).tasks[0];
  await assert.rejects(cmd(owner,'schedule',f.id,{task_id:t.id,version:t.version,confirmed:true,scheduled_for:later(),agent_id:'nova'}));
  for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(due(owner),/permission denied/);}
  await db.exec('reset role;set role service_role');
});
test('Scheduler runs once per interval, preserves tasks on scan failure and stops cleanly',async()=>{
  let calls=0,callback,logs=0,cleared=0;
  const runner=createFunnelScheduler({run:async()=>{calls++;throw Error('offline');},logger:{warn:()=>logs++},setTimeoutImpl:fn=>{callback=fn;return 1;},clearTimeoutImpl:()=>cleared++});
  runner.start();runner.start();await callback();assert.equal(calls,1);assert.equal(logs,1);
  runner.stop();await callback();assert.equal(calls,1);assert.equal(cleared,1);
});

const sequenceSteps=()=>[1,25,73].map((h,i)=>({subject:'Step '+(i+1),body:'Reviewed inquiry response '+(i+1),scheduled_for:new Date(Date.now()+h*3600000).toISOString()}));
async function sequence(f,l,s=service()) {
  s.setF(f.id);const t=await task(f,l);
  return {s,...await s.svc.createSequence(owner,f.id,{task_id:t.id,version:t.version,name:'Inquiry follow-up',steps:sequenceSteps(),confirmed:true})};
}
async function sequenceReady(id) {await db.query("update korlix_funnel_followup_tasks set scheduled_for=now()-interval '1 minute',due_at=now()-interval '1 minute' where id=$1",[id]);}
test('Sequences enforce approval, ownership, private roles and atomic validation without duplicate enrollment',async()=>{
  const f=await create(),l=await lead(f),t=await task(f,l),s=service();s.setF(f.id);
  const body={task_id:t.id,version:t.version,name:'Plan',steps:sequenceSteps(),confirmed:true};
  await assert.rejects(s.svc.createSequence(other,f.id,body),/not found/);
  await assert.rejects(s.svc.createSequence(basic,f.id,body),/Enterprise/);
  await assert.rejects(s.svc.createSequence(owner,f.id,{...body,confirmed:false}),/Review/);
  await assert.rejects(service({autopilot:false}).svc.createSequence(owner,f.id,body),/Autopilot/);
  await assert.rejects(s.svc.createSequence(owner,f.id,{...body,steps:[...body.steps,{subject:'',body:'',scheduled_for:later()}]}));
  await assert.rejects(s.svc.createSequence(owner,f.id,{...body,steps:body.steps.map(x=>({...x,scheduled_for:later()}))}),/hour apart/);
  assert.equal((await task(f,l)).state,'review');assert.equal((await cmd(owner,'state',f.id)).total,1);
  const results=await Promise.allSettled([1,2].map(()=>s.svc.createSequence(owner,f.id,body)));
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal(s.sends(),0);assert.equal(s.recipients(),0);
  const q=results.find(x=>x.status==='fulfilled').value;
  assert.equal(q.steps.length,3);assert.equal(q.sequence.state,'active');assert(!JSON.stringify(q).includes('approval_nonce'));
  await cmd(owner,'enqueue',f.id,{lead_id:l.id});assert.equal((await cmd(owner,'state',f.id)).total,3);
  await assert.rejects(s.svc.sequenceDetail(other,f.id,q.sequence.id),/not found/);
  for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_sequences'),/permission denied/);await assert.rejects(seq(owner,'get',f.id,{sequence_id:q.sequence.id}),/permission denied/);}
  await db.exec('reset role;set role service_role');
});
test('Sequences run in order across workers without catch-up bursts and finish only after all provider acceptances',async()=>{
  const f=await create(),l=await lead(f),q=await sequence(f,l),s=q.s;
  for(const t of q.steps)await sequenceReady(t.id);
  await assert.rejects(s.svc.send(owner,f.id,{task_id:q.steps[1].id,version:q.steps[1].version,confirmed:true}),/sequence timeline/);
  const runs=await Promise.all([s.svc.runScheduled(),s.svc.runScheduled()]);assert.equal(runs.reduce((n,x)=>n+x.sent,0),1);assert.equal(s.sends(),1);
  assert.equal((await s.svc.runScheduled()).sent,0);
  for(let i=1;i<3;i++) {
    await db.query("update korlix_funnel_followup_tasks set updated_at=now()-interval '61 minutes' where id=$1",[q.steps[i-1].id]);
    assert.equal((await s.svc.runScheduled()).sent,1);
  }
  const finished=await s.svc.sequenceDetail(owner,f.id,q.sequence.id);assert.equal(finished.sequence.state,'completed');assert.equal(s.sends(),3);
});
test('Pause revokes every remaining approval and resume requires exact current steps, fresh times and consent',async()=>{
  const f=await create(),l=await lead(f),q=await sequence(f,l),s=q.s;
  const paused=await s.svc.pauseSequence(owner,f.id,{sequence_id:q.sequence.id,version:q.sequence.version,confirmed:true});
  assert.equal(paused.sequence.state,'paused');assert(paused.steps.every(t=>t.state==='review'&&t.scheduled_approved_at===null));
  assert.equal((await s.svc.runScheduled()).sent,0);
  const body={sequence_id:q.sequence.id,version:paused.sequence.version,confirmed:true,steps:paused.steps.map((t,i)=>({task_id:t.id,version:t.version,scheduled_for:sequenceSteps()[i].scheduled_for}))};
  await assert.rejects(s.svc.resumeSequence(owner,f.id,{...body,steps:body.steps.slice(1)}),/every remaining/);
  await assert.rejects(s.svc.resumeSequence(owner,f.id,{...body,steps:body.steps.map(x=>({...x,version:1}))}),/changed/);
  const resumed=await s.svc.resumeSequence(owner,f.id,body);assert.equal(resumed.sequence.state,'active');assert(resumed.steps.every(t=>t.state==='scheduled'));
  assert.equal(resumed.steps[0].subject,q.steps[0].subject);
});
test('Mark replied, cancel, page pause and workflow pause stop pending steps with no provider activity',async()=>{
  for(const action of ['replySequence','cancelSequence','page','workflow']){
    const f=await create(),l=await lead(f),q=await sequence(f,l),s=q.s;
    if(action==='page')await funnel(owner,'pause',f.id,{version:f.version});
    else if(action==='workflow'){const st=(await cmd(owner,'state',f.id)).settings;await cmd(owner,'settings',f.id,settings(st,{enabled:false}));}
    else await s.svc[action](owner,f.id,{sequence_id:q.sequence.id,version:q.sequence.version,confirmed:true});
    const after=await s.svc.sequenceDetail(owner,f.id,q.sequence.id);
    assert(after.steps.every(t=>t.state!=='scheduled'));assert.equal((await s.svc.runScheduled()).sent,0);assert.equal(s.sends(),0);
    if(action==='replySequence')assert.equal(after.sequence.state,'replied');
    if(action==='cancelSequence')assert.equal(after.sequence.state,'cancelled');
  }
});
test('Revoked consent, overdue timing and uncertain delivery pause all later sequence steps without retries',async()=>{
  for(const action of ['consent','overdue','uncertain']){
    const f=await create(),l=await lead(f),q=await sequence(f,l);await sequenceReady(q.steps[0].id);
    if(action==='consent')await db.query('update korlix_contacts set do_not_contact=true where id=$1',[l.contact_id]);
    if(action==='overdue')await db.query("update korlix_funnel_followup_tasks set scheduled_for=now()-interval '25 hours' where sequence_id=$1",[q.sequence.id]);
    const s=service({failSend:action==='uncertain'});s.setF(f.id);await s.svc.runScheduled();
    const after=await s.svc.sequenceDetail(owner,f.id,q.sequence.id);assert.equal(after.sequence.state,'paused');assert(after.steps.every(t=>t.state!=='scheduled'));
    await s.svc.runScheduled();assert.equal(s.sends(),action==='uncertain'?1:0);
    if(action==='uncertain')await assert.rejects(s.svc.resumeSequence(owner,f.id,{sequence_id:q.sequence.id,version:after.sequence.version,confirmed:true,steps:after.steps.map((t,i)=>({task_id:t.id,version:t.version,scheduled_for:sequenceSteps()[i].scheduled_for}))}),/delivery/);
  }
});
test('Resume excludes accepted steps; a late pause blocks the final pre-provider check',async()=>{
  const f=await create(),l=await lead(f),q=await sequence(f,l),s=q.s;await sequenceReady(q.steps[0].id);await s.svc.runScheduled();
  const current=await s.svc.sequenceDetail(owner,f.id,q.sequence.id);
  const paused=await s.svc.pauseSequence(owner,f.id,{sequence_id:q.sequence.id,version:current.sequence.version,confirmed:true});
  const body={sequence_id:q.sequence.id,version:paused.sequence.version,confirmed:true,steps:paused.steps.slice(1).map((t,i)=>({task_id:t.id,version:t.version,scheduled_for:sequenceSteps()[i].scheduled_for}))};
  const resumed=await s.svc.resumeSequence(owner,f.id,body);assert.equal(resumed.steps[0].state,'sent');assert.equal(resumed.steps[1].state,'scheduled');
  await db.query("update korlix_funnel_followup_tasks set updated_at=now()-interval '61 minutes' where id=$1",[q.steps[0].id]);
  await sequenceReady(q.steps[1].id);
  const claimed=await cmd(owner,'claim_scheduled',f.id,{task_id:q.steps[1].id,version:resumed.steps[1].version,agent_id:'nova'});
  const active=await s.svc.sequenceDetail(owner,f.id,q.sequence.id);await s.svc.pauseSequence(owner,f.id,{sequence_id:q.sequence.id,version:active.sequence.version,confirmed:true});
  await assert.rejects(cmd(owner,'check',f.id,{task_id:claimed.id}),/paused/);assert.equal(s.sends(),1);
});
