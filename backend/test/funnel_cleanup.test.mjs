import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
import {cleanupQuery,readCleanupToken} from '../funnels/cleanup.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),secret='local-cleanup-fixture';
let db,server,base,clock=Date.now();
const rpc=async(action,f,data={},actor=owner)=>(await db.query(`select korlix_funnel_cleanup_${action}_v1($1,$2,$3) v`,[actor,f,data])).rows[0].v;
const core=async(action,f,data={},actor=owner)=>(await db.query('select korlix_funnel_v1($1,$2,$3,$4) v',[actor,action,f,data])).rows[0].v;
const fresh=async(actor=owner)=>(await core('create',null,{name:'Cleanup test',slug:'cleanup-'+randomUUID(),document:{brand:'Example',privacy_url:'https://example.com/privacy',contact_email:'team@example.com'}},actor)).id;
const lead=async(f,{status='won',date='2020-01-01',name='Cleanup visitor'}={})=>(await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,consent_text,created_at,inbox_status) values($1,gen_random_uuid(),1,$2,'visitor@example.com','Inquiry only',$3,$4) returning id`,[f,name,date.length===10?date+'T00:00:00Z':date,status])).rows[0].id;
const task=async(f,l,state='dismissed',message=null,sequence=null)=>(await db.query(`insert into korlix_funnel_followup_tasks(funnel_id,lead_id,channel,state,due_at,subject,body,to_email,message_id,sequence_id,scheduled_for,scheduled_approved_at,schedule_agent_id) values($1,$2,'email',$3,now(),'Subject','Body','visitor@example.com',$4,$5,case when $3='scheduled' then now()+interval '1 hour' end,case when $3='scheduled' then now() end,case when $3='scheduled' then 'nova' end) returning id`,[f,l,state,message,sequence])).rows[0].id;
const sequence=async(f,l,state='cancelled')=>(await db.query(`insert into korlix_funnel_sequences(funnel_id,lead_id,name,state,total_steps) values($1,$2,'Local history',$3,2) returning id`,[f,l,state])).rows[0].id;
const single=l=>({mode:'single',lead_id:l});
const retention={mode:'retention',before:'2025-01-01',statuses:['won','lost']};
const deletion=p=>({review_id:randomUUID(),items:p.selected.map(({id,fingerprint})=>({id,fingerprint}))});
const count=async(t,f)=>(await db.query(`select count(*)::integer n from ${t} where funnel_id=$1`,[f])).rows[0].n;
async function request(f,action,data,actor=owner) {
 clock+=1000;
 const r=await fetch(base+`/api/funnels/${f}/inbox/cleanup/${action}`,{method:'POST',headers:{'Content-Type':'application/json',...(actor?{Authorization:actor}:{})},body:JSON.stringify(data)});
 return {status:r.status,data:await r.json(),cache:r.headers.get('cache-control')};
}
test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;
 create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);
 create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);
 create table korlix_agent_email_messages(id uuid primary key default gen_random_uuid(),user_id uuid,body text);
 grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients,korlix_agent_email_messages to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const store=createFunnelStore({rpc:async(name,p)=>{try{return {data:(await db.query(`select ${name}($1,$2,$3) v`,[p.p_actor,p.p_id,p.p_data])).rows[0].v};}catch(error){return {error};}}});
 const app=express();app.use(express.json());registerFunnels(app,{store,now:()=>clock,environment:{KORLIX_FUNNEL_FORM_SECRET:secret},requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};},followups:new Proxy({},{get:()=>()=>{throw Error('Cleanup attempted email delivery');}})});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Preview is read-only, owner scoped and service-only, including private replay receipts',async()=>{
 const f=await fresh(),l=await lead(f),foreign=await fresh(other),x=await lead(foreign);
 await db.exec('begin read only');assert.equal((await rpc('preview',f,single(l))).eligible,1);await db.exec('rollback');
 for(const role of ['anon','authenticated']){
  await db.exec(`reset role;set role ${role}`);
  for(const action of ['preview','delete'])await assert.rejects(rpc(action,f,single(l)),/permission denied/);
  await assert.rejects(db.query('select korlix_funnel_cleanup_state_v1($1)',[l]),/permission denied/);
  for(const table of ['korlix_funnel_cleanup_receipts','korlix_funnel_removed_requests'])await assert.rejects(db.query('select * from '+table),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 for(const [actor,status]of [[null,401],[other,404],[basic,403]])assert.equal((await request(f,'preview',single(l),actor)).status,status);
 assert.equal((await request(f,'preview',single(x))).status,404);
 const review=await request(f,'preview',single(l));assert.equal(review.cache,'no-store');assert.equal(review.data.selected[0].fingerprint,undefined);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await request(f,'delete',{confirmation:'DELETE',review_token:review.data.review_token})).status,403);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 assert.equal(await count('korlix_funnel_leads',f),1);
});
test('Retention uses UTC cutoff and closed stages, selects the oldest 100 eligible records, and excludes all protected activity',async()=>{
 const f=await fresh();
 await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,consent_text,created_at,inbox_status)
 select $1,gen_random_uuid(),1,'Old '||g,'old'||g||'@example.com','Inquiry only','2020-01-01'::timestamptz+g*interval '1 second',case when g%2=0 then 'won' else 'lost' end from generate_series(1,105) g`,[f]);
 await lead(f,{status:'new'});await lead(f,{status:'qualified'});await lead(f,{date:'2025-01-01T00:00:00Z'});
 for(const state of ['review','scheduled','processing','needs_review','sent'])await task(f,await lead(f),state);
 await task(f,await lead(f),'dismissed',randomUUID());
 for(const state of ['active','paused'])await sequence(f,await lead(f),state);
 const foreign=await fresh();await task(foreign,await lead(f));
 await db.exec("set timezone='Pacific/Honolulu'");
 const p=await rpc('preview',f,retention);await db.exec("set timezone='UTC'");
 assert.equal(p.matched,114);assert.equal(p.eligible,105);assert.equal(p.blocked,9);assert.equal(p.selected.length,100);assert.equal(p.blocked_examples.length,5);
 assert.equal(p.selected[0].name,'Old 1');assert.equal(p.selected.at(-1).name,'Old 100');
 for(const row of p.selected)assert.ok(['won','lost'].includes(row.status));
 assert.equal((await rpc('preview',f,{...retention,statuses:['won']})).eligible,52);
 for(const q of [{...retention,before:'2025-02-30'},{...retention,before:'2099-01-01'},{...retention,statuses:['new']},{...retention,statuses:[]},{...retention,statuses:['won','won']},{...retention,search:'ignored'},null,[]])assert.throws(()=>cleanupQuery(q));
 await assert.rejects(rpc('preview',f,{...retention,before:'2025-02-30'}),/UTC cutoff/);
});
test('Only a signed, current, actor-and-funnel-bound review and exact confirmation can delete',async()=>{
 const f=await fresh(),l=await lead(f,{status:'new'}),f2=await fresh();
 const p=(await request(f,'preview',single(l))).data,body={confirmation:'DELETE',review_token:p.review_token};
 for(const invalid of [{...body,confirmation:'delete'},{...body,confirmation:''},{...body,lead_id:l},{...body,review_token:p.review_token+'.bad'}])assert.ok([400,409].includes((await request(f,'delete',invalid)).status));
 assert.equal((await request(f2,'delete',body)).status,409);assert.equal((await request(f,'delete',body,other)).status,409);
 assert.throws(()=>readCleanupToken(secret,p.review_token,owner,f,clock+600001));
 assert.equal(await count('korlix_funnel_leads',f),1);
 const deleted=await request(f,'delete',body);assert.equal(deleted.status,200);assert.deepEqual(deleted.data,{deleted_count:1,replayed:false});
 assert.deepEqual((await request(f,'delete',body)).data,{deleted_count:1,replayed:true});assert.equal(await count('korlix_funnel_leads',f),0);
});
test('Changed metadata, tasks, or sequences invalidate the entire batch; a fresh review cannot remove protected records',async()=>{
 for(const kind of ['lead','task','sequence']){
  const f=await fresh(),a=await lead(f),b=await lead(f);
  const t=kind==='task'?await task(f,b):null,q=kind==='sequence'?await sequence(f,b):null;
  const p=await rpc('preview',f,retention),data=deletion(p);
  if(kind==='lead')await db.query("update korlix_funnel_leads set private_note='Changed' where id=$1",[b]);
  if(kind==='task')await db.query("update korlix_funnel_followup_tasks set state='processing',version=version+1 where id=$1",[t]);
  if(kind==='sequence')await db.query("update korlix_funnel_sequences set state='active',version=version+1 where id=$1",[q]);
  await assert.rejects(rpc('delete',f,data),/changed/);assert.equal(await count('korlix_funnel_leads',f),2);assert.equal(await count('korlix_funnel_cleanup_receipts',f),0);
  const next=await rpc('preview',f,retention);assert.equal(next.eligible,kind==='lead'?2:1);assert.ok(next.selected.some(x=>x.id===a));
 }
});
test('Deletion removes only reviewed local inquiry history; CRM permissions, Email Center, other inquiries and counts remain consistent',async()=>{
 const f=await fresh(),l=await lead(f),untouched=await lead(f,{date:'2025-01-01'}),seq=await sequence(f,l);await task(f,l,'dismissed',null,seq);
 const c=(await db.query("insert into korlix_contacts(user_id,name,email,email_permission,do_not_contact) values($1,'CRM visitor','crm@example.com','none',true) returning id",[owner])).rows[0].id;
 await db.query('update korlix_funnel_leads set contact_id=$1 where id=$2',[c,l]);
 await db.query("insert into korlix_agent_email_recipients(user_id,email,active,consent_status) values($1,'crm@example.com',false,'unsubscribed')",[owner]);
 await db.query("insert into korlix_agent_email_messages(user_id,body) values($1,'Retained email record')",[owner]);
 const snapshot=()=>Promise.all(['korlix_contacts','korlix_agent_email_recipients','korlix_agent_email_messages'].map(async t=>(await db.query(`select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') v from ${t} x`)).rows[0].v));
 const before=await snapshot(),p=await rpc('preview',f,retention);assert.equal(p.selected[0].followups,1);assert.equal(p.selected[0].sequences,1);
 const body=deletion(p);assert.deepEqual(await rpc('delete',f,body),{deleted_count:1,replayed:false});assert.deepEqual(await snapshot(),before);
 assert.equal(await count('korlix_funnel_followup_tasks',f),0);assert.equal(await count('korlix_funnel_sequences',f),0);assert.equal(await count('korlix_funnel_leads',f),1);
 const inbox=(await db.query('select korlix_funnel_inbox_v1($1,$2,$3) v',[owner,f,{}])).rows[0].v;assert.equal(inbox.total,1);assert.equal(inbox.leads[0].id,untouched);assert.equal(inbox.status_totals.won,1);
 await assert.rejects(rpc('delete',f,{...body,items:[{...body.items[0],fingerprint:'0'.repeat(32)}]}),/review changed/);
 const receipt=(await db.query('select to_jsonb(x) v from korlix_funnel_cleanup_receipts x where funnel_id=$1',[f])).rows[0].v;
 assert.deepEqual(Object.keys(receipt).sort(),['created_at','deleted_count','funnel_id','id','selection_hash','user_id']);
});
test('Competing cleanup reviews cannot both delete a record; repeated identical review is idempotent',async()=>{
 const f=await fresh(),l=await lead(f),a=(await request(f,'preview',single(l))).data,b=(await request(f,'preview',single(l))).data;
 const responses=await Promise.all([a,b].map(p=>request(f,'delete',{review_token:p.review_token,confirmation:'DELETE'})));
 assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);assert.equal(await count('korlix_funnel_cleanup_receipts',f),1);
});
test('A deleted recent public submission cannot be recreated by a valid form replay; new submissions still enqueue normally',async()=>{
 const f=await fresh(),published=await core('publish',f,{version:1,confirmed:true});
 await db.query("insert into korlix_funnel_followup_settings(funnel_id,enabled) values($1,true)",[f]);
 const input={slug:published.slug,published_version:published.published_version,request_id:randomUUID(),name:'Public visitor',email:'public@example.com'};
 await core('lead',null,input,null);
 const l=(await db.query('select id from korlix_funnel_leads where request_id=$1',[input.request_id])).rows[0].id;
 assert.equal((await rpc('preview',f,single(l))).blocked,1);
 await db.query("update korlix_funnel_followup_tasks set state='dismissed',version=version+1 where lead_id=$1",[l]);
 await rpc('delete',f,deletion(await rpc('preview',f,single(l))));
 assert.equal(await count('korlix_funnel_removed_requests',f),1);
 for(let i=0;i<2;i++)assert.deepEqual(await core('lead',null,input,null),{received:true});
 assert.equal(await count('korlix_funnel_leads',f),0);assert.equal(await count('korlix_funnel_followup_tasks',f),0);
 await core('lead',null,{...input,request_id:randomUUID(),private_note:'Injected note',inbox_status:'won'},null);
 assert.equal(await count('korlix_funnel_leads',f),1);assert.equal(await count('korlix_funnel_followup_tasks',f),1);
 const saved=(await db.query('select inbox_status,private_note from korlix_funnel_leads where funnel_id=$1',[f])).rows[0];assert.deepEqual(saved,{inbox_status:'new',private_note:''});
});
