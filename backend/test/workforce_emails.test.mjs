import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {createWorkforceEmails,workforceEmailAddress,registerWorkforceEmailPublicRoutes} from '../workforce/emails.mjs';
import {automationInput,createWorkforceAutomations} from '../workforce/automations.mjs';
import {createFieldProofEmailProvider} from '../fieldproof/email_provider.mjs';
import {defaults} from '../workforce/core.mjs';
import express from 'express';

const [owner,employee,other]=Array.from({length:3},()=>randomUUID());
let db,org,mail,worker,calls=[],fault=null;
const auto=async(actor,action,o=org,p={})=>(await db.query('select korlix_workforce_automation_v1($1,$2,$3,$4::jsonb) v',[actor,action,o,JSON.stringify(p)])).rows[0].v;
const email=async(actor,action,o=org,p={})=>(await db.query('select korlix_workforce_email_v1($1,$2,$3,$4::jsonb) v',[actor,action,o,JSON.stringify(p)])).rows[0].v;
const work=async(actor,address,action,o,p={})=>(await db.query('select korlix_workforce_command_v1($1,$2,$3,$4,$5::jsonb) v',[actor,address,action,o,JSON.stringify(p)])).rows[0].v;
const provider={status:()=>({ready:true,senderFingerprint:'test-sender'}),send:async input=>{calls.push(input);if(fault)throw fault;return {accepted:true,providerId:randomUUID()};}};
const rule=async(mode='automatic',extra={})=>{
 const c=await mail.recipientAction(owner,org,'add',{id:randomUUID(),name:'Approved supervisor',email:`${randomUUID()}@example.com`,confirmed:true});
 let r=await auto(owner,'create',org,automationInput({id:randomUUID(),name:'Employee update reminder',kind:'missed_update',channel:'workspace_email',delivery_mode:mode,recipient_id:c.id,member_id:employee,delay_minutes:0,local_time:'08:00',send_start:'00:00',send_end:'23:59',days:[0,1,2,3,4,5,6],daily_limit:5,...extra}));
 r=await worker.setEnabled(owner,org,{rule_id:r.id,version:r.version,enabled:true,confirmed:true});return {r,c};
};
const jobs=async r=>(await auto(owner,'state')).jobs.filter(x=>x.rule_id===r.id);
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);grant usage on schema public to service_role;grant select,update on user_profiles to service_role;');
 for(const u of [owner,employee,other]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===employee?'basic':'enterprise']);}
 for(const f of ['20260922000006_enterprise_workforce.sql','20260922013258_workforce_automations.sql','20261004042716_workforce_autonomous_email.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 await db.exec('set role service_role');org=(await work(owner,'owner@example.com','create',null,{name:'Team',display_name:'Owner',timezone:'UTC'})).id;
 await db.query("insert into korlix_workforce_members(org_id,user_id,role,display_name,email)values($1,$2,'employee','Employee','employee@example.com')",[org,employee]);
 await work(employee,'employee@example.com','clock_in',org,{request_id:randomUUID(),flags:[]});
 await db.query("update korlix_workforce_shifts set segment_start=now()-interval '3 hours',policy_snapshot=$2 where org_id=$1",[org,JSON.stringify({...defaults,hourly_updates:true})]);
 const database={rpc:async(name,p)=>{try{return {data:await email(p.p_actor,p.p_action,p.p_org,p.p)};}catch(e){return {error:{message:e.message}};}},auth:{admin:{getUserById:async id=>({data:{user:{id,email:'owner@example.com',email_confirmed_at:'2026-01-01'}}})}}};
 mail=createWorkforceEmails({database,provider});worker=createWorkforceAutomations({store:{command:auto},emailStore:{},delivery:{},persistence:{command:work},workspaceEmail:mail,autoStart:false,environment:{}});
});
test.after(async()=>{worker?.close();await db?.close();});
test.beforeEach(async()=>{if(db)await auto(owner,'pause_all');calls=[];fault=null;});

test('workspace recipients are owner-only, explicitly approved, idempotent and service-private',async()=>{
 await assert.rejects(mail.recipientAction(employee,org,'list'),/owner access/);
 await assert.rejects(mail.recipientAction(other,org,'list'),/owner access/);
 const body={id:randomUUID(),name:'Supervisor',email:'manager@example.com'};
 await assert.rejects(mail.recipientAction(owner,org,'add',body),/Confirm permission/);
 const a=await mail.recipientAction(owner,org,'add',{...body,confirmed:true});
 assert.equal((await mail.recipientAction(owner,org,'add',{...body,confirmed:true})).id,a.id);
 for(const role of ['anon','authenticated']){await db.exec(`reset role;set role ${role}`);await assert.rejects(email(owner,'recipients'),/permission denied/);await assert.rejects(db.query('select * from korlix_workforce_email_tokens'),/permission denied/);}
 await db.exec('reset role;set role service_role');
 assert.throws(()=>workforceEmailAddress('x@example.com\nBcc: a@example.com'));
});
test('automatic email has one immutable event, verified reply-to and private opt-out token',async()=>{
 const {r,c}=await rule();await worker.tick();await worker.tick();assert.equal(calls.length,1);
 assert.equal(calls[0].to,c.email);assert.equal(calls[0].replyTo,'owner@example.com');assert.match(calls[0].text,/Stop these workspace emails: https:/);
 const j=(await jobs(r))[0];assert.equal(j.status,'sent');assert.equal(j.email_payload,undefined);assert.equal(j.lease_token,undefined);assert.equal(j.recipient_email,c.email);
});
test('review mode prepares exact drafts and approval sends only while conditions still apply',async()=>{
 const {r}=await rule('review');await worker.tick();assert.equal(calls.length,0);let j=(await jobs(r))[0];assert.equal(j.status,'draft');
 await assert.rejects(mail.review(owner,org,{action:'approve',job_id:j.id,version:j.version,confirmed:false}),/approve/);
 await assert.rejects(mail.review(employee,org,{action:'approve',job_id:j.id,version:j.version,confirmed:true}),/owner access/);
 await mail.review(owner,org,{action:'approve',job_id:j.id,version:j.version,confirmed:true});await worker.tick();assert.equal(calls.length,1);assert.equal((await jobs(r))[0].status,'sent');
});
test('revocation cancels queued drafts and cannot be undone by stale approvals',async()=>{
 const {r,c}=await rule('review');await worker.tick();const j=(await jobs(r))[0];await mail.recipientAction(owner,org,'revoke',{id:c.id});
 await assert.rejects(mail.review(owner,org,{action:'approve',job_id:j.id,version:j.version,confirmed:true}),/authorized/);await worker.tick();assert.equal(calls.length,0);assert.equal((await jobs(r))[0].status,'cancelled');
});
test('ambiguous transport outcomes never retry and provider events reconcile without sending',async()=>{
 const {r}=await rule();fault=Object.assign(new Error('Timeout'),{outcome:'uncertain',retryable:true});await worker.tick();await worker.tick();assert.equal(calls.length,1);
 let j=(await jobs(r))[0];assert.equal(j.status,'unknown');const providerId=randomUUID();
 await mail.providerEvent({job_id:j.id,provider_id:providerId,event:'email.delivered'});assert.equal((await jobs(r))[0].status,'delivered');
 await mail.providerEvent({job_id:j.id,provider_id:providerId,event:'email.bounced'});assert.equal((await jobs(r))[0].status,'bounced');
 await mail.providerEvent({job_id:j.id,provider_id:providerId,event:'email.delivered'});assert.equal((await jobs(r))[0].status,'bounced');
 assert.equal((await auto(owner,'state')).rules.find(x=>x.id===r.id).enabled,false);
});
test('pausing invalidates draft approval; inactive plans cannot dispatch but can stop recipients',async()=>{
 const {r,c}=await rule('review');await worker.tick();const j=(await jobs(r))[0];
 await worker.setEnabled(owner,org,{rule_id:r.id,version:r.version,enabled:false});await assert.rejects(mail.review(owner,org,{action:'approve',job_id:j.id,version:j.version,confirmed:true}),/authorized/);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 await assert.rejects(mail.recipientAction(owner,org,'add',{id:randomUUID(),name:'No',email:'no@example.com',confirmed:true}),/Enterprise/);
 await mail.recipientAction(owner,org,'revoke',{id:c.id});await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);assert.equal(calls.length,0);
});
test('unsubscribe token is scoped to its workspace and stops future delivery',async()=>{
 const {r,c}=await rule();await worker.tick();const token=calls[0].text.match(/unsubscribe\/([A-Za-z0-9_-]+)/)[1];await mail.unsubscribe(token);await mail.unsubscribe(token);
 assert.equal((await mail.recipientAction(owner,org,'list')).recipients.find(x=>x.id===c.id).active,false);
 assert.equal((await auto(owner,'state')).rules.find(x=>x.id===r.id).enabled,false);
});
test('transport gives Workforce a separate idempotency namespace and signed-event tag',async()=>{
 let sent;const id=randomUUID();const p=createFieldProofEmailProvider({environment:{RESEND_API_KEY:'private',KORLIX_AGENT_EMAIL_FROM:'sender@example.com'},namespace:'workforce',fetchImpl:async(url,init)=>{sent=init;return new Response(JSON.stringify({id:randomUUID()}),{status:200});}});
 await p.send({id,to:'recipient@example.com',replyTo:'owner@example.com',subject:'Workforce',text:'Approved update'});
 assert.equal(sent.headers['Idempotency-Key'],`wf-email:${id}`);assert.deepEqual(JSON.parse(sent.body).tags,[{name:'workforce_delivery',value:id}]);
});
test('unsubscribe GET never changes settings; POST invokes opt-out and rejects malformed tokens',async()=>{
 let stopped=0;const app=express();registerWorkforceEmailPublicRoutes(app,{service:{unsubscribe:async()=>{stopped++;}}});
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));const base=`http://127.0.0.1:${server.address().port}/api/workforce/email/unsubscribe/`;
 try{assert.equal((await fetch(base+'a'.repeat(43))).status,200);assert.equal(stopped,0);assert.equal((await fetch(base+'a'.repeat(43),{method:'POST'})).status,200);assert.equal(stopped,1);assert.equal((await fetch(base+'bad',{method:'POST'})).status,404);}finally{await new Promise(resolve=>server.close(resolve));}
});

test('quiet windows defer automatic sends and daily account quota includes other rules',async()=>{
 const start=new Date().getUTCHours()<12?'12:00':'00:00',end=new Date().getUTCHours()<12?'13:00':'01:00';
 const {r}=await rule('automatic',{send_start:start,send_end:end});await worker.tick();assert.equal(calls.length,0);assert.equal((await jobs(r))[0].status,'pending');
 await auto(owner,'pause_all');
 const source=await rule();await worker.tick();await auto(owner,'pause_all');calls=[];
 await db.query("insert into korlix_workforce_automation_jobs(org_id,rule_id,event_key,status,subject,body,expires_at,dispatch_at,completed_at) select $1,$2,'quota-'||g,'sent','Quota','',now()+interval '1 hour',now(),now() from generate_series(1,100)g",[org,source.r.id]);
 const target=await rule();await worker.tick();assert.equal(calls.length,0);assert.equal((await jobs(target.r))[0].status,'pending');
 await db.query("delete from korlix_workforce_automation_jobs where event_key like 'quota-%'");
});
test('sender changes, stale claims and interrupted dispatches cannot authorize a second request',async()=>{
 const {r}=await rule();await auto(owner,'enqueue',org,{rule_id:r.id,event_key:'isolated-crash',subject:'Reminder',body:'Work is due',expires_at:new Date(Date.now()+3600000).toISOString()});
 let j=await auto(owner,'claim',org,{rule_id:r.id});
 j=await email(owner,'prepare',org,{job_id:j.id,lease_token:j.lease_token,reply_to:'owner@example.com',sender_fingerprint:'test-sender',token_hash:'a'.repeat(64),unsubscribe_url:'https://example.com/stop'});
 await assert.rejects(email(owner,'authorize',org,{job_id:j.id,lease_token:j.lease_token,reply_to:'owner@example.com',sender_fingerprint:'changed'}),/changed/);
 await assert.rejects(email(owner,'authorize',org,{job_id:j.id,lease_token:randomUUID(),reply_to:'owner@example.com',sender_fingerprint:'test-sender'}),/claim expired/);
 await email(owner,'authorize',org,{job_id:j.id,lease_token:j.lease_token,reply_to:'owner@example.com',sender_fingerprint:'test-sender'});
 await db.query("update korlix_workforce_automation_jobs set lease_until=now()-interval '1 second' where id=$1",[j.id]);
 await auto(null,'due_rules',null);assert.equal((await jobs(r)).find(x=>x.id===j.id).status,'unknown');
 assert.equal(await auto(owner,'claim',org,{rule_id:r.id}),null);assert.equal(calls.length,0);
});

test('shared webhook rejects forged signatures and retries failed persistence before acknowledgment',async()=>{
 const bytes=Buffer.from('workforce-test-webhook-secret'),secret='whsec_'+bytes.toString('base64');let persisted=0,broken=false,nextCalls=0;
 const app=express();app.use(express.json({verify(req,res,buffer){req.korlixAgentEmailRawBody=Buffer.from(buffer);}}));
 registerWorkforceEmailPublicRoutes(app,{environment:{RESEND_WEBHOOK_SECRET:secret},service:{providerEvent:async value=>{persisted++;assert.equal(value.event,'email.bounced');assert.equal(Object.keys(value).length,3);if(broken)throw Error('storage unavailable');}}});
 app.post('/api/agent-email/resend/webhook',(req,res)=>{nextCalls++;res.json({ok:true});});
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
 const url=`http://127.0.0.1:${server.address().port}/api/agent-email/resend/webhook`,body=JSON.stringify({type:'email.bounced',data:{email_id:randomUUID(),tags:{workforce_delivery:randomUUID()},to:['ignored@example.com']}});
 const stamp=String(Math.floor(Date.now()/1000)),event='workforce-test',signature=createHmac('sha256',bytes).update(`${event}.${stamp}.${body}`).digest('base64');
 const headers={'Content-Type':'application/json','svix-id':event,'svix-timestamp':stamp,'svix-signature':'v1,'+signature};
 try{
  assert.equal((await fetch(url,{method:'POST',body,headers:{...headers,'svix-signature':'v1,forged'}})).status,401);assert.equal(persisted,0);
  broken=true;assert.equal((await fetch(url,{method:'POST',body,headers})).status,503);assert.equal(nextCalls,0);
  broken=false;assert.equal((await fetch(url,{method:'POST',body,headers})).status,200);assert.equal(nextCalls,1);
 }finally{await new Promise(resolve=>server.close(resolve));}
});
