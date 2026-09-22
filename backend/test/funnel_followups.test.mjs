import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { createFunnelFollowups,createFollowupStore,followupSettings } from '../funnels/followups.mjs';
import { registerFunnels } from '../funnels/routes.mjs';
import { korlixAgentEmailDraftInput } from '../korlix_agent_email.mjs';

const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
let db;
const funnel=async(u,a,f=null,p={})=>(await db.query('select korlix_funnel_v1($1,$2,$3,$4::jsonb) v',[u,a,f,JSON.stringify(p)])).rows[0].v;
const cmd=async(u,a,f,p={})=>(await db.query('select korlix_funnel_followup_v1($1,$2,$3,$4::jsonb) v',[u,a,f,JSON.stringify(p)])).rows[0].v;
const store=createFollowupStore({rpc:async(_name,p)=>{try{return {data:await cmd(p.p_actor,p.p_action,p.p_id,p.p_data)}}catch(error){return{error}}}});
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
function service({failSend=false,failBeforeProvider=false,changed=false,lateSuppression=false}={}) {
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
  const delivery={getDeliveryStatus:async()=>({canSend:true}),sendApprovedDraft:async({messageId})=>{
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
  for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
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
    assert.equal((await fetch(url+'/send',{method:'POST',headers:{Authorization:other,'Content-Type':'application/json'},body:JSON.stringify({task_id:randomUUID(),version:1,confirmed:true})})).status,404);
  }finally{await new Promise(r=>server.close(r));}
});
