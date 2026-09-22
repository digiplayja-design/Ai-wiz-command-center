import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
import {leadChange} from '../funnels/lead_management.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),f=randomUUID(),foreign=randomUUID();
let db,server,base,lead,foreignLead;
const rpc=async(actor,id,data)=>(await db.query('select korlix_funnel_lead_manage_v1($1,$2,$3) v',[actor,id,data])).rows[0].v;
const request=(method='GET',data=null,actor=owner,id=lead,funnel=f)=>fetch(base+`/api/funnels/${funnel}/inbox/${id}`,{
 method,headers:{'Content-Type':'application/json',...(actor?{Authorization:actor}:{})},...(data?{body:JSON.stringify(data)}:{}),
});
const change=(version=1,status='qualified',private_note='Review the requested consultation.')=>({version,status,private_note});
const list=async(query={},suffix='')=>{
 const r=await fetch(base+`/api/funnels/${f}/inbox${suffix}?`+new URLSearchParams(query),{headers:{Authorization:owner}});
 return {status:r.status,data:await r.json()};
};
test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
 create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);
 create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,
 consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);
 grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]) {
  await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);
 }
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql',
  '20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922145937_funnel_lead_inbox.sql',
  '20260922172151_funnel_lead_management.sql']) await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 for(const [id,user] of [[f,owner],[foreign,other]]) {
  await db.query("insert into korlix_funnels(id,user_id,name,slug,draft) values($1,$2,'Lead management',$3,'{}')",[id,user,'lead-'+id]);
  await db.query("insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,message,consent_text,created_at) values($1,gen_random_uuid(),1,'Avery Morgan','avery@example.com','Please contact me','Inquiry only','2026-09-01')",[id]);
 }
 lead=(await db.query('select id from korlix_funnel_leads where funnel_id=$1',[f])).rows[0].id;
 foreignLead=(await db.query('select id from korlix_funnel_leads where funnel_id=$1',[foreign])).rows[0].id;
 await db.query("insert into korlix_funnel_followup_tasks(funnel_id,lead_id,channel,state,due_at,subject,body,to_email,scheduled_for,scheduled_approved_at,schedule_agent_id) values($1,$2,'email','scheduled',now(),'Existing subject','Existing body','avery@example.com',now()+interval '1 hour',now(),'nova')",[f,lead]);
 const store=createFunnelStore({rpc:async(name,p)=>{
  try {
   assert.ok(['korlix_funnel_lead_manage_v1','korlix_funnel_inbox_v1'].includes(name));
   return {data:(await db.query(`select ${name}($1,$2,$3) v`,[p.p_actor,p.p_id,p.p_data])).rows[0].v};
  } catch(error) {return {error};}
 }});
 const app=express();app.use(express.json());
 registerFunnels(app,{store,environment:{},requireUser:async q=>{
  if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};
 },followups:new Proxy({},{get:()=>()=>{throw Error('Lead editing touched the live follow-up service');}})});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Current Enterprise ownership is required for reads and updates; browser RPC and table access stay denied',async()=>{
 for(const role of ['anon','authenticated']) {
  await db.exec(`reset role;set role ${role}`);
  await assert.rejects(rpc(owner,f,{action:'get',lead_id:lead}),/permission denied/);
  await assert.rejects(db.query('select private_note from korlix_funnel_leads'),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 for(const method of ['GET','PATCH'])for(const [actor,status] of [[null,401],[other,404],[basic,403]]) {
  assert.equal((await request(method,method==='PATCH'?change():null,actor)).status,status);
 }
 assert.equal((await request('GET',null,owner,foreignLead)).status,404);
 assert.equal((await request('PATCH',change(),owner,foreignLead)).status,404);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await request('PATCH',change())).status,403);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Only owner metadata changes; visitor fields, CRM permissions, schedules and all delivery state are preserved',async()=>{
 const tables=['korlix_contacts','korlix_agent_email_recipients','korlix_funnel_followup_tasks','korlix_funnel_followup_settings','korlix_funnel_sequences','korlix_funnels','korlix_funnel_usage'];
 const snapshot=()=>Promise.all(tables.map(async t=>(await db.query(`select coalesce(jsonb_agg(to_jsonb(x)),'[]') v from ${t} x`)).rows[0].v));
 const before=await snapshot();
 const original=(await db.query('select to_jsonb(l) v from korlix_funnel_leads l where id=$1',[lead])).rows[0].v;
 const first=await request();assert.equal(first.status,200);assert.equal(first.headers.get('cache-control'),'no-store');
 const existing=await first.json();assert.equal(existing.lead.inbox_status,'new');assert.equal(existing.lead.inbox_version,1);assert.equal(existing.scheduled_followups,1);
 const r=await request('PATCH',change(1,'won','  Interested in the proposal.  '));assert.equal(r.status,200);
 const saved=(await r.json()).lead;assert.equal(saved.inbox_status,'won');assert.equal(saved.private_note,'Interested in the proposal.');assert.equal(saved.inbox_version,2);assert.ok(saved.inbox_updated_at);
 const after=(await db.query('select to_jsonb(l) v from korlix_funnel_leads l where id=$1',[lead])).rows[0].v;
 for(const [key,value] of Object.entries(original))if(!['inbox_status','private_note','inbox_version','inbox_updated_at'].includes(key))assert.deepEqual(after[key],value,key);
 assert.deepEqual(await snapshot(),before);
 const noop=(await(await request('PATCH',change(2,'won','Interested in the proposal.'))).json()).lead;
 assert.equal(noop.inbox_version,2);assert.equal(noop.inbox_updated_at,saved.inbox_updated_at);
});
test('Competing updates cannot overwrite one another; failed validation changes nothing',async()=>{
 const results=await Promise.all([request('PATCH',change(2,'qualified','Owner A')),request('PATCH',change(2,'in_review','Owner B'))]);
 assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
 const now=(await(await request()).json()).lead;assert.equal(now.inbox_version,3);
 for(const patch of [{...change(3),status:'sent'}, {...change(3),private_note:'x'.repeat(4001)}, {...change(3),version:'3'},
  {...change(3),private_note:'bad\u0001note'}, {...change(3),email:'changed@example.com'}, {...change(3),version:0}])assert.equal((await request('PATCH',patch)).status,400);
 assert.deepEqual((await(await request()).json()).lead,now);
 await assert.rejects(rpc(owner,f,{action:'update',lead_id:lead,version:3,status:'bad',private_note:''}),/Check the lead/);
 await assert.rejects(rpc(owner,f,{action:'delete',lead_id:lead}),/valid inquiry/);
 assert.throws(()=>leadChange(null));assert.throws(()=>leadChange([]));
});
test('Status filtering, counts, cursor binding and CSV all use the same owner metadata',async()=>{
 await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,message,utm,consent_text,created_at,inbox_status,private_note)
 select $1,gen_random_uuid(),1,'Qualified '||g,'lead'||g||'@example.com','Searchable inquiry',jsonb_build_object('utm_source','facebook'),'Inquiry only',
 '2026-09-02T12:00:00.123456Z'::timestamptz,'qualified',case when g=1 then '=HYPERLINK("https://bad.example")' else 'Private follow-up note' end from generate_series(1,57) g`,[f]);
 await db.query("insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,utm,consent_text,created_at,inbox_status) values($1,gen_random_uuid(),1,'Lost inquiry','lost@example.com','{\"utm_source\":\"facebook\"}','Inquiry only','2026-09-02T00:00:00Z','lost')",[f]);
 const q={source:'facebook',from:'2026-09-02',to:'2026-09-02',status:'qualified'};
 let page=(await list(q)).data;assert.equal(page.filtered_total,57);assert.equal(page.status_totals.qualified,57);assert.equal(page.status_totals.lost,1);
 const ids=new Set(page.leads.map(l=>l.id));assert.equal(page.leads.length,25);
 const wrong=await list({...q,status:'lost',cursor:page.next_cursor,snapshot:page.snapshot});assert.equal(wrong.status,400);
 while(page.next_cursor) {
  page=(await list({...q,cursor:page.next_cursor,snapshot:page.snapshot})).data;
  for(const l of page.leads){assert.ok(!ids.has(l.id));ids.add(l.id);assert.equal(l.inbox_status,'qualified');}
 }
 assert.equal(ids.size,57);
 const exported=(await list(q,'/export')).data;assert.equal(exported.count,57);
 assert.match(exported.csv,/Lead status \(owner-set\)/);assert.match(exported.csv,/Private note/);assert.match(exported.csv,/'=HYPERLINK/);assert.match(exported.csv,/Qualified/);
 assert.ok(!exported.csv.includes('Lost inquiry'));assert.equal((await list({status:'unknown'})).status,400);
 const filtered=(await list({...q,search:'Qualified 1'})).data;assert.equal(filtered.filtered_total,11);assert.equal(filtered.status_totals.qualified,11);
});
test('Schema keeps the RPC invoker-only with an explicit search path and no added browser grants',async()=>{
 const fn=(await db.query("select prosecdef,proconfig from pg_proc where proname='korlix_funnel_lead_manage_v1'")).rows[0];
 assert.equal(fn.prosecdef,false);assert.deepEqual(fn.proconfig,['search_path=public, pg_temp']);
 assert.equal((await db.query("select has_function_privilege('anon','korlix_funnel_lead_manage_v1(uuid,uuid,jsonb)','execute') a,has_function_privilege('authenticated','korlix_funnel_lead_manage_v1(uuid,uuid,jsonb)','execute') b")).rows[0].a,false);
});
test('Public capture cannot set owner metadata and public page responses never expose private notes',async()=>{
 await db.query("update korlix_funnels set state='published',published_version=1,published='{\"brand\":\"Example business\"}' where id=$1",[f]);
 const publicPage=(await db.query("select korlix_funnel_v1(null,'public',null,$1) v",[{slug:'lead-'+f}])).rows[0].v;
 assert.deepEqual(Object.keys(publicPage).sort(),['document','id','published_version','slug']);
 const requestId=randomUUID();
 await db.query("select korlix_funnel_v1(null,'lead',null,$1)",[{slug:'lead-'+f,published_version:1,request_id:requestId,name:'New visitor',email:'visitor@example.com',inbox_status:'won',private_note:'Injected owner note'}]);
 const captured=(await db.query('select inbox_status,private_note,inbox_version from korlix_funnel_leads where request_id=$1',[requestId])).rows[0];
 assert.deepEqual(captured,{inbox_status:'new',private_note:'',inbox_version:1});
});
