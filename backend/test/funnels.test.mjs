import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {document,publishReady,leadInput} from '../funnels/core.mjs';
import {renderPage} from '../funnels/render.mjs';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
const [owner,other,basic]=Array.from({length:3},()=>randomUUID());
const doc={brand:'Example Studio',headline:'A better next step',subheadline:'Talk to our team.',cta:'Get in touch',thank_you:'Thank you.',benefits:['Personal attention'],faq:[{q:'What next?',a:'We respond to your inquiry.'}],layout:'consultation',accent:'cyan',privacy_url:'https://example.com/privacy',booking_url:'',contact_email:'hello@example.com'};
let db, f, server, base, clock=Date.now(), generationCalls=0;
const rpc=async(actor,action,id=null,data={})=>(await db.query('select korlix_funnel_v1($1,$2,$3,$4::jsonb) v',[actor,action,id,JSON.stringify(data)])).rows[0].v;
const create=(actor=owner,extra={})=>rpc(actor,'create',null,{name:'Test funnel',slug:'test-'+randomUUID(),document:doc,...extra});
const publish=async x=>rpc(owner,'publish',x.id,{version:x.version,confirmed:true});
const inquiry=(x,extra={})=>({slug:x.slug,published_version:x.published_version,request_id:randomUUID(),name:'Visitor',email:'visitor@example.com',phone:'+1 202 555 0123',message:'Tell me more.',utm:{utm_source:'facebook',utm_campaign:'test'},...extra});
const http=async(path,options={})=>fetch(base+path,options);
const auth=(actor=owner,body)=>({headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});

test.before(async()=>{
  db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
  for(const u of [owner,other,basic]) {await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
  for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql']) await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  await db.exec('set role service_role');
  const store=createFunnelStore({rpc:async(_name,p)=>{try{return{data:await rpc(p.p_actor,p.p_action,p.p_id,p.p_data)}}catch(error){return{error}}}});
  const app=express();app.use(express.json());
  registerFunnels(app,{store,now:()=>clock,environment:{OPENAI_API_KEY:'test-not-real'},requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};},generate:async()=>{generationCalls++;return doc;}});
  server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(resolve=>server?.close(resolve));await db?.close();});

test('Browser roles cannot access private tables or service-only commands',async()=>{
  for(const role of ['anon','authenticated']) {
    await db.exec(`reset role;set role ${role}`);
    for(const table of ['korlix_funnels','korlix_funnel_leads','korlix_funnel_usage']) await assert.rejects(db.query('select * from '+table),/permission denied/);
    await assert.rejects(rpc(owner,'list'),/permission denied/);
  }
  await db.exec('reset role;set role service_role');
  await assert.rejects(create(basic),/Enterprise/);
});
test('Private drafts, ownership, publish approval and optimistic concurrency',async()=>{
  f=await create();
  await assert.rejects(rpc(null,'public',null,{slug:f.slug}),/not available/);
  assert.equal((await rpc(other,'list')).funnels.length,0);
  await assert.rejects(rpc(other,'leads',f.id),/not found/);
  await assert.rejects(rpc(owner,'publish',f.id,{version:1,confirmed:false}),/Review/);
  f=await publish(f);
  const edited=await rpc(owner,'save',f.id,{version:f.version,name:'Changed',document:{...doc,headline:'Private unsaved offer'}});
  assert.equal((await rpc(null,'public',null,{slug:f.slug})).document.headline,doc.headline);
  await assert.rejects(rpc(owner,'save',f.id,{version:f.version,name:'Stale',document:doc}),/changed/);
  f=edited;
});
test('Lead capture is atomic, idempotent, owner scoped and does not grant calling or marketing consent',async()=>{
  const input=inquiry(f);await rpc(null,'lead',null,input);await rpc(null,'lead',null,input);
  let r=await rpc(owner,'leads',f.id);assert.equal(r.total,1);assert.equal(r.campaigns[0].source,'facebook');
  const c=(await db.query('select * from korlix_contacts where email=$1',[input.email])).rows[0];
  assert.equal(c.user_id,owner);assert.equal(c.source,'funnel');assert.equal(c.call_permission,'none');assert.equal(c.email_permission,'transactional');assert.equal(c.phone_key,null);
  await db.query("update korlix_contacts set do_not_contact=true,email_permission='blocked',call_permission='blocked' where id=$1",[c.id]);
  await rpc(null,'lead',null,inquiry(f,{name:'Someone else',phone:'another phone'}));
  const after=(await db.query('select * from korlix_contacts where id=$1',[c.id])).rows[0];
  assert.equal(after.name,'Visitor');assert.equal(after.do_not_contact,true);assert.equal(after.email_permission,'blocked');assert.equal(after.call_permission,'blocked');assert.equal(after.phone,c.phone);
  assert.equal((await db.query('select count(*)::int n from korlix_agent_email_recipients')).rows[0].n,0);
  await assert.rejects(rpc(null,'lead',null,inquiry(f,{published_version:999})),/changed/);
});
test('Tier downgrade and pause both stop public capture immediately',async()=>{
  await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
  await assert.rejects(rpc(null,'public',null,{slug:f.slug}),/not available/);
  await assert.rejects(rpc(null,'lead',null,inquiry(f)),/not available/);
  await assert.rejects(rpc(owner,'list'),/Enterprise/);
  await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
  f=await rpc(owner,'pause',f.id,{version:f.version});await assert.rejects(rpc(null,'public',null,{slug:f.slug}),/not available/);f=await publish(f);
});
test('NOVA draft endpoint checks current tier before invoking AI and enforces durable daily budget',async()=>{
  assert.equal((await http('/api/funnels/generate',{method:'POST',...auth(basic,{brief:'A business'})})).status,403);
  assert.equal(generationCalls,0);
  for(let i=0;i<10;i++)assert.equal((await rpc(owner,'budget')).remaining,9-i);
  assert.equal((await http('/api/funnels/generate',{method:'POST',...auth(owner,{brief:'A business'})})).status,429);
  assert.equal(generationCalls,0);
  assert.equal((await http('/api/funnels/generate',{method:'POST',...auth(other,{brief:'A business'})})).status,200);
  assert.equal(generationCalls,1);
});
test('Public forms reject missing, forged, expired, cross-page and cross-cookie tokens',async()=>{
  const page=await http('/f/'+f.slug);const html=await page.text();
  const token=html.match(/name="token" value="([^"]+)"/)[1];const cookie=page.headers.get('set-cookie').split(';')[0];
  assert.match(page.headers.get('content-security-policy'),/default-src 'none'/);assert.match(page.headers.get('cache-control'),/no-store/);
  const post=async(t=token,c=cookie)=>http('/f/'+f.slug+'/lead',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:c},body:new URLSearchParams({token:t,name:'Web visitor',email:'web@example.com',consent:'yes'})});
  assert.equal((await post()).status,400); // Too fast.
  clock+=2000;
  assert.equal((await post('',cookie)).status,400);assert.equal((await post(token,'')).status,400);assert.equal((await post(token.slice(0,-1)+'X',cookie)).status,400);
  const newF=await publish(await create());const otherPage=await http('/f/'+newF.slug);const otherCookie=otherPage.headers.get('set-cookie').split(';')[0];
  assert.equal((await post(token,otherCookie)).status,400);
  clock+=1800001;assert.equal((await post()).status,400);
});
test('Public HTTP form creates a CRM inquiry, captures tags, and safely deduplicates retries',async()=>{
  const page=await http('/f/'+f.slug+'?utm_source=google&utm_campaign=autumn');const html=await page.text();
  assert.match(html,/name="utm_source" value="google"/);
  const token=html.match(/name="token" value="([^"]+)"/)[1], cookie=page.headers.get('set-cookie').split(';')[0];clock+=2500;
  const submit=extra=>http('/f/'+f.slug+'/lead',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie},body:new URLSearchParams({token,name:'Web lead',email:'web@example.com',consent:'yes',utm_source:'google',utm_campaign:'autumn',...extra})});
  assert.equal((await submit({consent:'no'})).status,400);assert.equal((await submit({website:'spam.example'})).status,400);
  const before=(await rpc(owner,'leads',f.id)).total;
  for(let i=0;i<2;i++){const response=await submit();assert.equal(response.status,303);assert.match(response.headers.get('location'),/received=1/);}
  const after=await rpc(owner,'leads',f.id);assert.equal(after.total,before+1);assert.equal(after.leads.find(x=>x.email==='web@example.com').utm.utm_campaign,'autumn');
});
test('Owner routes fail closed, reject unsafe content and require a publish confirmation',async()=>{
  assert.equal((await http('/api/funnels')).status,401);
  assert.equal((await http('/api/funnels',auth(basic))).status,403);
  assert.equal((await http('/api/funnels/'+f.id+'/leads',auth(other))).status,404);
  assert.equal((await http('/api/funnels/'+f.id+'/publish',{method:'POST',...auth(owner,{version:f.version})})).status,400);
  assert.equal((await http('/api/funnels',{method:'POST',...auth(owner,{name:'Bad',slug:'bad-page',document:{...doc,privacy_url:'javascript:alert(1)'}})})).status,400);
  assert.equal((await http('/api/funnels/'+f.id,{method:'PUT',...auth(owner,{name:'Stale',version:1,document:doc})})).status,409);
});
test('Document renderer escapes scripts and attributes and validation rejects unsafe values',()=>{
  const html=renderPage(document({...doc,headline:'<script>alert(1)</script>',brand:'" onmouseover="alert(1)'}),{token:'safe',utm:{}});
  assert(!html.includes('<script>'));assert(html.includes('&lt;script&gt;'));assert(!html.includes(' onmouseover="'));assert(!html.includes('src="https:'));
  assert.throws(()=>publishReady({...doc,privacy_url:''}));assert.throws(()=>document({...doc,benefits:Array(7).fill('x')}));
  assert.throws(()=>document({...doc,booking_url:'http://example.com'}));assert.throws(()=>leadInput({name:'x',email:'bad',consent:'yes'}));
});
