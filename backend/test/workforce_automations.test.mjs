import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { automationInput, automationEvents, localDay, previousDay, approvedRuleMatches, automationTemplates, createWorkforceAutomations } from '../workforce/automations.mjs';
import { defaults } from '../workforce/core.mjs';

const [owner, employee, other, recipient] = Array.from({length:4}, () => randomUUID());
let db, org, otherOrg;
const auto = async (actor, action, o=org, p={}) => (await db.query('select korlix_workforce_automation_v1($1,$2,$3,$4::jsonb) v', [actor,action,o,JSON.stringify(p)])).rows[0].v;
const work = async (actor, email, action, o, p={}) => (await db.query('select korlix_workforce_command_v1($1,$2,$3,$4,$5::jsonb) v', [actor,email,action,o,JSON.stringify(p)])).rows[0].v;
const input = (extra={}) => automationInput({ id:randomUUID(), name:'Work update reminder', kind:'missed_update', channel:'call_review', delay_minutes:10,
  local_time:'08:00', days:[0,1,2,3,4,5,6], daily_limit:5, ...extra });
const fixture = (extra={}) => ({ organization:{ name:'Team', timezone:'America/New_York' }, active_plan:true,
  members:[{user_id:employee, display_name:'Employee', active:true}], shifts:[], updates:[], schedule:[], ...extra });
const rawEmail = r => ({ id:r.email_rule_id, enabled:true, send_mode:'autopilot', trigger_key:`workforce.${r.org_id}.${r.id}`, preapproved_by:owner,preapproved_at:new Date().toISOString(),
  approval_version:r.email_approval_version,marketing:false,recipient_scope:{recipientIds:[recipient]},subject_template:automationTemplates.subject,text_template:automationTemplates.text,html_template:'',max_sends_per_day:r.daily_limit });

test.before(async () => {
  db=new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create schema storage; create table auth.users(id uuid primary key); create table user_profiles(id uuid primary key,tier text); create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]); grant usage on schema public to service_role; grant select,update on user_profiles to service_role;');
  for(const u of [owner,employee,other]) { await db.query('insert into auth.users values($1)',[u]); await db.query('insert into user_profiles values($1,$2)',[u,u===employee?'basic':'enterprise']); }
  for(const f of ['20260922000006_enterprise_workforce.sql','20260922013258_workforce_automations.sql']) await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
  await db.exec('set role service_role');
  org=(await work(owner,'owner@example.com','create',null,{name:'Team',display_name:'Owner',timezone:'UTC'})).id;
  otherOrg=(await work(other,'other@example.com','create',null,{name:'Other',display_name:'Other',timezone:'UTC'})).id;
  await db.query("insert into korlix_workforce_members(org_id,user_id,role,display_name,email) values($1,$2,'employee','Employee','employee@example.com')",[org,employee]);
});
test.after(async()=>db?.close());

test('Private RPC, owner-only configuration, immutable idempotent creation, fresh Enterprise gates', async()=>{
  for(const role of ['anon','authenticated']) {
    await db.exec(`reset role;set role ${role}`);
    await assert.rejects(db.query('select * from korlix_workforce_automations'),/permission denied/);
    await assert.rejects(auto(owner,'state'),/permission denied/);
  }
  await db.exec('reset role;set role service_role');
  await assert.rejects(auto(employee,'state'),/owner access/);
  await assert.rejects(auto(owner,'state',otherOrg),/owner access/);
  const p=input(); const r=await auto(owner,'create',org,p);
  assert.equal(r.enabled,false);
  assert.equal((await auto(owner,'create',org,p)).id,r.id);
  await assert.rejects(auto(owner,'create',org,{...p,name:'Changed'}),/different settings/);
  await assert.rejects(auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:false}),/approve/);
  await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
  await assert.rejects(auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true}),/Enterprise/);
  assert.equal((await auto(owner,'state')).active_plan,false);
  await auto(owner,'pause_all');
  await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Durable queue deduplicates events, leases claims, rejects stale completions and cancels paused work',async()=>{
  const r=await auto(owner,'create',org,input());
  await auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true});
  const event={rule_id:r.id,event_key:'update:test:start',subject:'Reminder',body:'A work update is due.',member_id:employee,expires_at:new Date(Date.now()+3600000).toISOString()};
  await auto(owner,'enqueue',org,event); await auto(owner,'enqueue',org,event);
  const j=await auto(owner,'claim',org,{rule_id:r.id});
  assert.equal(j.attempts,1);assert.equal(await auto(owner,'claim',org,{rule_id:r.id}),null);
  assert.equal((await auto(owner,'finish',org,{rule_id:r.id,job_id:j.id,lease_token:randomUUID(),status:'sent'})).saved,false);
  await auto(owner,'pause',org,{rule_id:r.id,version:2});
  assert.equal((await auto(owner,'finish',org,{rule_id:r.id,job_id:j.id,lease_token:j.lease_token,status:'sent'})).saved,false);
  await assert.rejects(auto(owner,'enable',org,{rule_id:r.id,version:2,confirmed:true}),/changed/);
  const jobs=(await auto(owner,'state')).jobs.filter(x=>x.rule_id===r.id); assert.equal(jobs.length,1);assert.equal(jobs[0].status,'cancelled');
});
test('Hourly events use policy grace and work time, resolve on update, pause on break, and filter deactivated members',()=>{
  const now=Date.parse('2026-09-22T15:00:00Z'), r={...input(),enabled:true};
  const shift={id:randomUUID(),user_id:employee,state:'working',worked_seconds:0,break_seconds:0,segment_start:new Date(now-79*60000).toISOString(),policy_snapshot:{...defaults,hourly_updates:true}};
  let f=fixture({shifts:[shift]}); assert.equal(automationEvents(r,f,now).length,0);
  shift.segment_start=new Date(now-81*60000).toISOString();
  const first=automationEvents(r,f,now)[0];assert.match(first.event_key,/start$/);
  f.updates=[{id:randomUUID(),shift_id:shift.id,worked_seconds_at_submit:80*60}]; assert.equal(automationEvents(r,f,now).length,0);
  f.updates=[];shift.state='break'; assert.equal(automationEvents(r,f,now).length,0);
  shift.state='working';f.members[0].active=false;assert.equal(automationEvents(r,f,now).length,0);
});
test('Lease recovery keeps the event stable and concurrent claims reserve the daily limit',async()=>{
  const r=await auto(owner,'create',org,input({daily_limit:1}));
  await auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true});
  for (const key of ['first','second']) await auto(owner,'enqueue',org,{rule_id:r.id,event_key:key,subject:'Reminder',body:'Due',expires_at:new Date(Date.now()+3600000).toISOString()});
  const first=await auto(owner,'claim',org,{rule_id:r.id});
  assert.equal(await auto(owner,'claim',org,{rule_id:r.id}),null);
  await db.query("update korlix_workforce_automation_jobs set lease_until=now()-interval '1 second' where id=$1",[first.id]);
  const recovered=await auto(owner,'claim',org,{rule_id:r.id});
  assert.equal(recovered.id,first.id);assert.notEqual(recovered.lease_token,first.lease_token);assert.equal(recovered.attempts,2);
  assert.equal((await auto(owner,'finish',org,{rule_id:r.id,job_id:first.id,lease_token:first.lease_token,status:'sent'})).saved,false);
  await auto(owner,'finish',org,{rule_id:r.id,job_id:recovered.id,lease_token:recovered.lease_token,status:'review'});
  assert.equal(await auto(owner,'claim',org,{rule_id:r.id}),null);
});
test('Missed clock-ins stop when a real shift overlaps or the schedule ends; inactive dates do not fire',()=>{
  const now=Date.parse('2026-09-22T15:00:00Z'),r={...input({kind:'missed_shift'}),enabled:true};
  const s={id:randomUUID(),user_id:employee,starts_at:new Date(now-20*60000).toISOString(),ends_at:new Date(now+3600000).toISOString(),version:1};
  const f=fixture({schedule:[s]});assert.equal(automationEvents(r,f,now).length,1);
  f.shifts=[{user_id:employee,clock_in:new Date(now-5*60000).toISOString()}];assert.equal(automationEvents(r,f,now).length,0);
  f.shifts=[];assert.equal(automationEvents(r,f,now+3600000).length,0);
  r.days=[0];assert.equal(automationEvents(r,f,now).length,0);
});
test('Previous-day summaries handle midnight, DST repeated hours and bounded catch-up',()=>{
  assert.equal(localDay(Date.parse('2026-01-01T05:00:00Z'),'America/New_York').minutes,0);
  assert.equal(previousDay('2026-03-09'),'2026-03-08');
  const r={...input({kind:'daily_summary',channel:'email',recipient_id:recipient,local_time:'01:00'}),enabled:true};
  const f=fixture();
  const a=automationEvents(r,f,Date.parse('2026-11-01T05:30:00Z'))[0];
  const b=automationEvents(r,f,Date.parse('2026-11-01T06:30:00Z'))[0];
  assert.equal(a.event_key,b.event_key);assert.equal(a.report_date,'2026-10-31');
  assert.equal(automationEvents(r,f,Date.parse('2026-11-01T13:00:00Z')).length,0);
});
test('Email approval pins the exact recipient, template, owner and approval version',()=>{
  const r={...input({channel:'email',recipient_id:recipient}),org_id:org,owner_id:owner,email_rule_id:randomUUID(),email_approval_version:3};
  const raw=rawEmail(r);assert(approvedRuleMatches(raw,r));
  for(const patch of [{enabled:false},{preapproved_by:other},{approval_version:4},{recipient_scope:{recipientIds:[randomUUID()]}},{text_template:'Changed'}]) assert.equal(approvedRuleMatches({...raw,...patch},r),false);
});
test('Worker survives retries without duplicates; call reviews never place calls; owner resolution is auditable',async()=>{
  await auto(owner,'pause_all');
  const s=await work(employee,'employee@example.com','clock_in',org,{request_id:randomUUID(),flags:[]});
  const snap=await work(owner,'','snapshot',org);
  const shift=snap.shifts.find(x=>x.user_id===employee);
  await db.query("update korlix_workforce_shifts set segment_start=now()-interval '3 hours',policy_snapshot=$2 where id=$1",[shift.id,JSON.stringify({...defaults,hourly_updates:true})]);
  const r=await auto(owner,'create',org,input({member_id:employee}));await auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true});
  let sends=0;
  const service=createWorkforceAutomations({store:{command:auto},emailStore:{},delivery:{runAutopilot(){sends++;throw Error('No sends expected');}},persistence:{command:work},autoStart:false,environment:{}});
  await service.tick();await service.tick();service.close();
  const jobs=(await auto(owner,'state')).jobs.filter(x=>x.rule_id===r.id);assert.equal(jobs.length,1);assert.equal(jobs[0].status,'review');assert.equal(sends,0);
  await assert.rejects(auto(employee,'resolve',org,{id:jobs[0].id}),/owner/);
  await auto(owner,'resolve',org,{id:jobs[0].id});assert.equal((await auto(owner,'state')).jobs.find(x=>x.id===jobs[0].id).status,'reviewed');
});
test('Worker emails use one preapproved rule and stable event ID; changed approvals block sends',async()=>{
  await auto(owner,'pause_all');
  let r=await auto(owner,'create',org,input({channel:'email',recipient_id:recipient}));
  r=await auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true,email_rule_id:randomUUID(),email_approval_version:1});
  let raw=rawEmail({...r,owner_id:owner}),calls=[];
  const service=createWorkforceAutomations({store:{command:auto},emailStore:{getRule:async()=>raw},delivery:{runAutopilot:async({body})=>{calls.push(body);return {results:[{ruleId:r.email_rule_id,recipientId:recipient,sent:true,messageId:randomUUID()}]};}},persistence:{command:work},autoStart:false,
    environment:{KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'custom_nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'assistant-nova'}});
  await service.tick();await service.tick();assert.equal(calls.length,1);assert.equal(calls[0].ruleId,r.email_rule_id);assert.match(calls[0].eventId,/^workforce:/);
  // A second update cycle is new work, but a changed email approval must block it.
  const sh=(await work(owner,'','snapshot',org)).shifts[0];
  await db.query("insert into korlix_workforce_updates(org_id,user_id,shift_id,request_id,summary,quantity,output_unit,worked_seconds_at_submit) values($1,$2,$3,$4,'Earlier update',1,'tasks',1)",[org,employee,sh.id,randomUUID()]);
  raw={...raw,approval_version:2};await service.tick();service.close();assert.equal(calls.length,1);
  assert((await auto(owner,'state')).jobs.some(j=>j.rule_id===r.id&&j.status==='blocked'));
});
test('Closed email windows retry the same event and cancel if the employee has since clocked out',async()=>{
  await auto(owner,'pause_all');
  let r=await auto(owner,'create',org,input({channel:'email',recipient_id:recipient}));
  r=await auto(owner,'enable',org,{rule_id:r.id,version:1,confirmed:true,email_rule_id:randomUUID(),email_approval_version:1});
  const calls=[];
  const service=createWorkforceAutomations({store:{command:auto},emailStore:{getRule:async()=>rawEmail({...r,owner_id:owner})},delivery:{runAutopilot:async({body})=>{calls.push(body);return {results:[{ruleId:r.email_rule_id,skipped:'send_window_closed'}]};}},persistence:{command:work},autoStart:false,
    environment:{KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'custom_nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'assistant-nova'}});
  await service.tick();
  const job=(await auto(owner,'state')).jobs.find(j=>j.rule_id===r.id);assert.equal(job.status,'pending');assert.equal(calls.length,1);
  await db.query("update korlix_workforce_automation_jobs set next_attempt_at=now()-interval '1 second' where id=$1",[job.id]);
  await service.tick();assert.equal(calls.length,2);assert.equal(calls[0].eventId,calls[1].eventId);
  const shift=(await work(owner,'','snapshot',org)).shifts.find(s=>s.user_id===employee&&s.state!=='ended');
  await work(employee,'employee@example.com','clock_out',org,{request_id:randomUUID(),version:shift.version,flags:[]});
  await db.query("update korlix_workforce_automation_jobs set next_attempt_at=now()-interval '1 second' where id=$1",[job.id]);
  await service.tick();service.close();assert.equal(calls.length,2);
  assert.equal((await auto(owner,'state')).jobs.find(j=>j.id===job.id).status,'cancelled');
});
