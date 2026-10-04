import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile, readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

let db, owner, other;
const defaults = {business_name:'Test Service',customer_mode:'off',followup_mode:'off',followup_days:3,supervisor_mode:'off',supervisor_emails:[],timezone:'America/New_York',summary_time:'17:00',summary_days:[1,2,3,4,5],include_photos:false,daily_limit:25,paused:false};
const rpc = async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_fieldproof_email_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const jobs = async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_fieldproof_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const setting = async(extra={},version=0)=>(await rpc('save_settings',null,{version,settings:{...defaults,...extra},confirmed:true})).settings;
const job = async(actor=owner)=>jobs('job_create',randomUUID(),{title:'Meter repair',summary:'Saved service record',customer:'Acme'},actor);
const recipient = async(j,extra={},version=0)=>rpc('save_job',j.id,{version,job_settings:{customer_email:'customer@example.com',enabled:true,...extra},confirmed:true});
const close = async j=>jobs('job_complete',j.id,{version:j.version,ready:true,name:'Technician'});
const deliveries = async()=> (await rpc('state')).deliveries;
const claim = async()=>rpc('claim',null,{lease_token:randomUUID()},null);
async function prepared(row) {
 const attachment=row.kind==='customer_report'?{filename:'FieldProof.pdf',path:`${row.owner_id}/${row.id}/report.pdf`,sha256:'a'.repeat(64),bytes:100}:null;
 const payload={to:row.recipient,subject:'Your service report',text:'Saved technician records.',html:'<p>Saved records.</p>',replyTo:'owner@example.com',senderFingerprint:'verified-sender',...(attachment?{attachment}:{})};
 return rpc('prepare',row.id,{lease_token:row.lease_token,payload,subject:payload.subject,...(attachment?{attachment_path:attachment.path,attachment_sha256:attachment.sha256,attachment_bytes:attachment.bytes}:{})},row.owner_id);
}
async function automatic(extra={}) {
 await setting({customer_mode:'automatic',...extra});const j=await job();await recipient(j);await close(j);return j;
}
async function ready(extra={}) {await automatic(extra);let row=await claim();await prepared(row);return claim();}

test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create table auth.users(id uuid primary key);create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;
 create policy broad_legacy on storage.objects for all to anon,authenticated using(true) with check(true);
 grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;
 create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);
 grant all on usage_counters to service_role;`);
 const dir=new URL('../../supabase/migrations/',import.meta.url), files=await readdir(dir);
 for(const suffix of ['_fieldproof.sql','_fieldproof_workspace_upgrade.sql','_fieldproof_autonomous_email.sql']) await db.exec(await readFile(new URL(files.find(f=>f.endsWith(suffix)),dir),'utf8'));
});
test.beforeEach(async()=>{
 await db.exec('reset role; delete from auth.users; truncate public.korlix_fieldproof_email_gc;');
 owner=randomUUID();other=randomUUID();for(const id of [owner,other]) await db.query('insert into auth.users values($1)',[id]);
 await db.exec('set role service_role');
});
test.after(async()=>{await db?.close();});

test('defaults are off; settings and recipients are versioned, confirmed, scoped, and independent of job revisions',async()=>{
 const state=await rpc('state');assert.equal(state.settings.version,0);assert.equal(state.settings.customer_mode,'off');assert.deepEqual(state.deliveries,[]);
 const s=await setting({customer_mode:'draft'});assert.equal(s.version,1);assert.equal(s.summary_time,'17:00');assert.equal(s.created_at,undefined);
 await assert.rejects(rpc('save_settings',null,{version:1,settings:defaults}),/Confirm/);
 await assert.rejects(setting({},0),/changed/);await assert.rejects(setting({timezone:'Not/AZone'},1),/Invalid/);
 const j=await job();await recipient(j);assert.equal((await jobs('job_get',j.id)).job.version,j.version);
 await assert.rejects(rpc('job_state',j.id,{},other),/not found/);
 await assert.rejects(recipient(j,{},0),/changed/);
 assert.equal((await rpc('state',null,{},other)).settings.version,0);
});

test('closeout queues report and one delayed follow-up atomically, without retroactive or repeated jobs',async()=>{
 const old=await job();await close(old);await setting({customer_mode:'automatic',followup_mode:'draft',followup_days:3});await recipient(old);assert.equal((await deliveries()).length,0);
 const j=await job();await recipient(j);await close(j);let all=await deliveries();assert.equal(all.length,2);
 assert.deepEqual(all.map(x=>x.kind).sort(),['customer_followup','customer_report']);
 const follow=all.find(x=>x.kind==='customer_followup'), report=all.find(x=>x.kind==='customer_report');
 assert.equal(follow.delivery_mode,'draft');assert(Date.parse(follow.scheduled_at)-Date.parse(report.scheduled_at)>=3*86400000-1000);
 await db.query('update korlix_fieldproof_jobs set updated_at=now() where id=$1',[j.id]);assert.equal((await deliveries()).length,2);
 const c=await claim();assert.equal(c.id,report.id);assert.equal(await claim(),null);
});

test('drafts require explicit current approval and prepared payload is immutable',async()=>{
 await setting({customer_mode:'draft'});const j=await job();await recipient(j);await close(j);let row=await claim();const lease=row.lease_token;row=await prepared(row);
 assert.equal(row.state,'draft');assert.equal(await claim(),null);
 await assert.rejects(rpc('approve',row.id,{version:row.version}),/Confirm/);
 await assert.rejects(rpc('prepare',row.id,{lease_token:lease,payload:{}}),/lease/);
 row=await rpc('approve',row.id,{version:row.version,confirmed:true});assert.equal(row.state,'ready');
 row=await claim();assert.equal(row.state,'sending');assert.equal(row.first_attempt_at,null);
 await assert.rejects(rpc('finish',row.id,{lease_token:row.lease_token,state:'accepted',provider_id:'receipt'}),/receipt/);
});

test('settings, recipient changes, job reopening and deletion invalidate waiting emails',async()=>{
 let j=await automatic();let row=await claim();await prepared(row);await recipient(j,{customer_email:'changed@example.com'},1);
 assert.equal((await deliveries())[0].state,'cancelled');assert.equal(await claim(),null);
 j=await jobs('job_reopen',j.id,{version:j.version});await close(j);row=await claim();assert.equal(row.recipient,'changed@example.com');
 await setting({customer_mode:'automatic',paused:true},1);assert.equal((await rpc('delivery',row.id)).state,'cancelled');
 await assert.rejects(prepared(row),/lease/);
});

test('daily reservation is atomic and counts one delivery once across safe retries',async()=>{
 let row=await ready({daily_limit:1});row=await rpc('authorize',row.id,{lease_token:row.lease_token});assert.equal(row.attempt_count,1);
 row=await rpc('finish',row.id,{lease_token:row.lease_token,state:'unknown',code:'provider_timeout'});
 const first=row.first_attempt_at,payload=row.payload;
 row=await rpc('retry',row.id,{version:row.version,confirmed:true});row=await claim();row=await rpc('authorize',row.id,{lease_token:row.lease_token});
 assert.equal(row.first_attempt_at,first);assert.deepEqual(row.payload,payload);assert.equal(row.attempt_count,2);
 await rpc('finish',row.id,{lease_token:row.lease_token,state:'accepted',provider_id:'provider-one'});
 const j=await job();await recipient(j);await close(j);await prepared(await claim());row=await claim();row=await rpc('authorize',row.id,{lease_token:row.lease_token});
 assert.equal(row.state,'retry');assert.equal(row.code,'daily_limit');assert.equal(row.first_attempt_at,null);
 assert.equal((await db.query('select sum(reserved)::int n from korlix_fieldproof_email_daily_usage where owner_id=$1',[owner])).rows[0].n,1);
});

test('crashes after send authorization become unknown and never silently resend',async()=>{
 let row=await ready();row=await rpc('authorize',row.id,{lease_token:row.lease_token});
 await db.query("update korlix_fieldproof_email_deliveries set lease_until=now()-interval '1 second' where id=$1",[row.id]);
 assert.equal(await claim(),null);row=await rpc('delivery',row.id);assert.equal(row.state,'unknown');assert.equal(row.code,'send_interrupted');
 await assert.rejects(rpc('finish',row.id,{lease_token:row.lease_token,state:'accepted',provider_id:'late'}),/lease/);
 row=await rpc('retry',row.id,{version:row.version,confirmed:true});assert.equal((await claim()).id,row.id);
 await db.query("update korlix_fieldproof_email_deliveries set state='unknown',first_attempt_at=now()-interval '24 hours' where id=$1",[row.id]);
 row=await rpc('delivery',row.id);await assert.rejects(rpc('retry',row.id,{version:row.version,confirmed:true}),/safely/);
});

test('interrupted preparation is recoverable but stale lease cannot save or acknowledge',async()=>{
 await automatic();let row=await claim();const old={...row};await db.query("update korlix_fieldproof_email_deliveries set lease_until=now()-interval '1 second' where id=$1",[row.id]);
 row=await claim();assert.equal(row.id,old.id);assert.notEqual(row.lease_token,old.lease_token);
 await assert.rejects(prepared(old),/lease/);assert.equal((await prepared(row)).state,'ready');
});

test('changing scope after an uncertain attempt preserves unknown outcome and blocks unsafe replay',async()=>{
 let row=await ready();row=await rpc('authorize',row.id,{lease_token:row.lease_token});
 row=await rpc('finish',row.id,{lease_token:row.lease_token,state:'unknown',code:'provider_timeout'});
 row=await rpc('retry',row.id,{version:row.version,confirmed:true});
 await setting({customer_mode:'off'},1);row=await rpc('delivery',row.id);
 assert.equal(row.state,'unknown');assert.equal(row.code,'settings_changed');assert.equal(await claim(),null);
 await assert.rejects(rpc('retry',row.id,{version:row.version,confirmed:true}),/no longer current/);
});

test('payload rejects base64, arbitrary attachment metadata, foreign paths and missing report sizes',async()=>{
 await automatic();const row=await claim(),path=`${owner}/${row.id}/report.pdf`;
 const payload={to:row.recipient,subject:'Report',text:'Test',html:'<p>Test</p>',replyTo:'owner@example.com',attachment:{filename:'report.pdf',path,sha256:'a'.repeat(64),bytes:100}};
 const input={lease_token:row.lease_token,payload,subject:'Report',attachment_path:path,attachment_sha256:'a'.repeat(64),attachment_bytes:100};
 await assert.rejects(rpc('prepare',row.id,{...input,payload:{...payload,attachments:[{content:'base64'}]}}),/Invalid immutable/);
 await assert.rejects(rpc('prepare',row.id,{...input,payload:{...payload,attachment:{...payload.attachment,content:'base64'}}}),/verified report/);
 await assert.rejects(rpc('prepare',row.id,{...input,attachment_bytes:null,payload:{...payload,attachment:{...payload.attachment,bytes:null}}}),/verified report/);
 await assert.rejects(rpc('prepare',row.id,{...input,attachment_path:`${other}/${row.id}/report.pdf`}),/verified report/);
 assert.equal((await prepared(row)).state,'ready');
});

test('unsubscribe tokens do not rotate older links; suppression cancels all waiting account mail',async()=>{
 await automatic();const row=await claim();
 for(const hash of ['1'.repeat(64),'2'.repeat(64)]) assert.equal((await rpc('recipient_token',row.id,{recipient:row.recipient,token_hash:hash})).created,true);
 await rpc('unsubscribe',null,{token_hash:'1'.repeat(64)},null);assert.equal((await rpc('delivery',row.id)).state,'cancelled');
 assert.deepEqual(await rpc('unsubscribe',null,{token_hash:'x'},null),{ok:true});
 const j=await job();await recipient(j);await close(j);assert.equal((await deliveries()).length,1);
 assert.equal((await db.query('select count(*)::int n from korlix_fieldproof_email_recipient_tokens')).rows[0].n,2);
});

test('early signed bounce uses authorized delivery identity and survives later acceptance',async()=>{
 let row=await ready();
 await rpc('suppress',row.id,{provider_id:'one',reason:'email.bounced'},null);assert.equal((await rpc('state')).suppressions.length,0);
 row=await rpc('authorize',row.id,{lease_token:row.lease_token});
 await rpc('suppress',row.id,{provider_id:'one',reason:'email.bounced'},null);
 row=await rpc('finish',row.id,{lease_token:row.lease_token,state:'accepted',provider_id:'one'});assert.equal(row.code,'bounced');assert.equal(row.provider_id,'one');
 await rpc('suppress',row.id,{provider_id:'foreign',reason:'email.complained'},null);assert.equal((await rpc('delivery',row.id)).code,'bounced');
 await rpc('suppress',null,{provider_id:'one',reason:'email.complained'},null);assert.equal((await rpc('delivery',row.id)).code,'complained');
 assert.equal((await rpc('state',null,{},other)).suppressions.length,0);
});

test('summary window matches first repeated minute and first valid spring-gap minute',async()=>{
 await setting({supervisor_mode:'draft',supervisor_emails:['supervisor@example.com'],summary_days:[0,1,2,3,4,5,6],summary_time:'02:30'});
 const window=async now=>(await db.query('select korlix_fieldproof_email_summary_window(s,$2::timestamptz) w from korlix_fieldproof_email_settings s where owner_id=$1',[owner,now])).rows[0].w;
 let w=await window('2026-03-08T07:01:00Z');assert.equal(new Date(w.scheduled_at).toISOString(),'2026-03-08T07:00:00.000Z');
 await setting({supervisor_mode:'draft',supervisor_emails:['supervisor@example.com'],summary_days:[0,1,2,3,4,5,6],summary_time:'01:30'},1);
 w=await window('2026-11-01T05:35:00Z');assert.equal(new Date(w.scheduled_at).toISOString(),'2026-11-01T05:30:00.000Z');
 w=await window('2026-11-02T08:00:00Z');assert.equal(Date.parse(w.period_end)-Date.parse(w.period_start),25*3600000);
 assert.equal(w.event_key,'supervisor:2026-11-02');assert.equal(w.report_date,'2026-11-01');
});

test('summary enqueue verifies current local period, skips old setup, and deduplicates each recipient',async()=>{
 const time=(await db.query("select to_char(now() at time zone 'UTC','HH24:MI') t")).rows[0].t;
 await setting({supervisor_mode:'automatic',supervisor_emails:['a@example.com','b@example.com'],summary_days:[0,1,2,3,4,5,6],summary_time:time,timezone:'UTC'});
 let w=(await db.query('select korlix_fieldproof_email_summary_window(s,now()) w from korlix_fieldproof_email_settings s where owner_id=$1',[owner])).rows[0].w;
 assert.deepEqual(await rpc('enqueue_summary',null,w),[]);
 await db.query("update korlix_fieldproof_email_settings set updated_at=now()-interval '2 days' where owner_id=$1",[owner]);
 assert.equal((await rpc('enqueue_summary',null,w)).length,2);assert.equal((await rpc('enqueue_summary',null,w)).length,2);assert.equal((await deliveries()).length,2);
 await assert.rejects(rpc('enqueue_summary',null,{...w,period_start:'2001-01-01T00:00:00Z'}),/previous local/);
 assert.equal((await rpc('due_accounts',null,{},null)).length,1);
});

test('private report cleanup survives job/account deletion and removes deterministic uncommitted uploads',async()=>{
 const j=await automatic();const row=await claim();await prepared(row);
 await jobs('job_delete_begin',j.id,{version:j.version});let d=await rpc('delivery',row.id);assert.equal(d.payload,null);assert.equal(d.attachment_path,null);assert.equal(d.state,'cancelled');
 assert.equal((await rpc('cleanup',null,{},null)).length,0);
 await db.query("update korlix_fieldproof_email_gc set not_before=now()-interval '1 second'");let gc=await rpc('cleanup',null,{},null);
 assert.equal(gc.length,1);assert.equal(gc[0].attachment_path,`${owner}/${row.id}/report.pdf`);assert.equal(gc[0].gc,true);
 await rpc('cleanup_done',null,{ids:[],gc_ids:[gc[0].id]},null);assert.equal((await rpc('cleanup',null,{},null)).length,0);
 const j2=await job();await recipient(j2);await close(j2);const uncommitted=await claim();
 await db.exec('reset role');await db.query('delete from auth.users where id=$1',[owner]);await db.exec('set role service_role');
 assert((await db.query('select attachment_path from korlix_fieldproof_email_gc')).rows.some(x=>x.attachment_path===`${owner}/${uncommitted.id}/report.pdf`));
});

test('30-day retention requires storage acknowledgement before clearing report paths',async()=>{
 let row=await ready();row=await rpc('authorize',row.id,{lease_token:row.lease_token});row=await rpc('finish',row.id,{lease_token:row.lease_token,state:'accepted',provider_id:'old'});
 await db.query("update korlix_fieldproof_email_deliveries set prepared_at=now()-interval '31 days' where id=$1",[row.id]);
 const batch=await rpc('cleanup',null,{},null);assert.equal(batch[0].id,row.id);assert.equal(batch[0].gc,false);assert((await rpc('delivery',row.id)).payload);
 await rpc('cleanup_done',null,{ids:[row.id],gc_ids:[]},null);row=await rpc('delivery',row.id);assert.equal(row.payload,null);assert.equal(row.attachment_path,null);assert(row.redacted_at);
});

test('history capacity prunes old terminal mail through GC, never blocks completed jobs',async()=>{
 await setting({customer_mode:'automatic'});const j=await job();await recipient(j);
 await db.query(`insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,state,expires_at)
 select $1,$2,1,1,1,'customer_report','old:'||i,'customer@example.com','automatic','accepted',now()+interval '1 day' from generate_series(1,500) i`,[owner,j.id]);
 await close(j);assert.equal((await db.query('select count(*)::int n from korlix_fieldproof_email_deliveries where owner_id=$1',[owner])).rows[0].n,500);
 assert.equal((await db.query('select count(*)::int n from korlix_fieldproof_email_gc')).rows[0].n,1);assert.equal((await claim()).kind,'customer_report');
});

test('event tombstones survive report pruning and prevent new delivery IDs for old requests',async()=>{
 await automatic();let row=await claim();await prepared(row);
 const request=randomUUID(),j=(await jobs('list'))[0];
 const manual=await rpc('prepare_job',j.id,{confirmed:true,request_key:request});
 assert.equal((await rpc('prepare_job',j.id,{confirmed:true,request_key:request})).id,manual.id);
 await db.query('delete from korlix_fieldproof_email_deliveries where id=$1',[manual.id]);
 await assert.rejects(rpc('prepare_job',j.id,{confirmed:true,request_key:request}),/already processed/);
 await db.query('delete from korlix_fieldproof_email_deliveries where id=$1',[row.id]);
 await db.query(`insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,expires_at)
 values($1,$2,$3,$4,$5,$6,$7,$8,$9,now()+interval '1 day')`,[row.owner_id,row.job_id,row.job_version,row.settings_version,row.job_settings_version,row.kind,row.event_key,row.recipient,row.delivery_mode]);
 assert.equal((await deliveries()).length,0);
});

test('a full waiting queue leaves job closeout available and records a visible queue notice',async()=>{
 await setting({customer_mode:'automatic'});const j=await job();await recipient(j);
 await db.query(`insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,state,expires_at)
 select $1,$2,1,1,1,'customer_report','pending:'||i,'customer@example.com','automatic','draft',now()+interval '1 day' from generate_series(1,500) i`,[owner,j.id]);
 assert.equal((await close(j)).state,'completed');assert.equal((await rpc('state')).queue_notice,'queue_full');
 assert.equal((await db.query('select count(*)::int n from korlix_fieldproof_email_deliveries')).rows[0].n,500);
});

test('RLS and grants deny direct clients, RPC impersonation, and permissive legacy storage policies',async()=>{
 await db.exec('reset role');await db.exec("insert into storage.objects values('mail','korlix-fieldproof-mail'),('other','other');set role authenticated");
 assert.deepEqual((await db.query('select id from storage.objects')).rows,[{id:'other'}]);
 await assert.rejects(db.query("insert into storage.objects values('forged','korlix-fieldproof-mail')"),/row-level security/);
 for(const table of ['settings','job_settings','deliveries','recipients','recipient_tokens','daily_usage','gc','events']) await assert.rejects(db.query(`select * from korlix_fieldproof_email_${table}`),/permission denied/);
 await assert.rejects(rpc('state'),/permission denied/);await db.exec('reset role');
 const security=(await db.query("select proname,prosecdef from pg_proc where proname like 'korlix_fieldproof_email_%'")).rows;assert(security.length>=6);assert(security.every(x=>x.prosecdef===false));
 const rls=(await db.query("select relrowsecurity from pg_class where relname like 'korlix_fieldproof_email_%' and relkind='r'")).rows;assert(rls.every(x=>x.relrowsecurity));
});
