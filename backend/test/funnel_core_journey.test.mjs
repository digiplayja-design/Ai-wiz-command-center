import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';

const owner=randomUUID(),other=randomUUID();
const doc={brand:'Journey fixture',headline:'Find your next step',subheadline:'Ask our team.',cta:'Send inquiry',thank_you:'We received your inquiry.',benefits:['Clear next steps'],faq:[],layout:'consultation',accent:'cyan',privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:'https://example.com/advice',form_mode:'guided',
 questions:[{id:'q-1',type:'choice',label:'Service',required:true,options:['Installation','Advice']},{id:'q-2',type:'text',label:'Installation address',required:true,options:[],show_when:{question_id:'q-1',equals:'Installation'}}],
 booking_routes:[{id:'route-1',name:'Installation consultation',question_id:'q-1',equals:'Installation',url:'https://example.com/installation',button_label:'Choose a time'}]};
let db,server,base,f,clock=Date.now()-5000,providerCalls=0;
const localFetch=fetch;
const json=async(r,status=200)=>{const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));return d;};
const api=(suffix='',body,method=body?'POST':'GET',actor=owner)=>fetch(base+'/api/funnels'+suffix,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const hidden=(h,k)=>(h.match(new RegExp(`name="${k}" value="([^"]*)"`))?.[1]??'').replaceAll('&amp;','&').replaceAll('&#39;',"'").replaceAll('&quot;','"');
const counts=async()=>Object.fromEntries(await Promise.all(['korlix_funnel_leads','korlix_contacts','korlix_funnel_followup_tasks','korlix_funnel_followup_settings','korlix_funnel_sequences','korlix_agent_email_recipients','korlix_funnel_attribution_events','korlix_funnel_measurement_receipts'].map(async t=>[t,(await db.query(`select count(*)::int n from ${t}`)).rows[0].n])));
async function publish(){f=(await json(await api('/'+f.id+'/publish',{version:f.version,confirmed:true}))).funnel;}
async function visit(answer='Advice',email='v-'+randomUUID()+'@example.com'){
 const page=await fetch(base+'/f/'+f.slug+'?utm_source=partner&utm_campaign=k196');const html=await page.text();assert.equal(page.status,200,html);
 assert.equal(page.headers.get('cache-control'),'no-store');assert.match(page.headers.get('content-security-policy'),/default-src 'none'/);
 clock+=2000;const cookie=page.headers.get('set-cookie').split(';')[0];
 const body={token:hidden(html,'token'),name:'Journey Visitor',email,message:'K196 inquiry',consent:'yes',utm_source:'partner',utm_campaign:'k196','answer_q-1':answer};
 const post=(suffix='lead',extra={})=>fetch(`${base}/f/${f.slug}/${suffix}`,{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie},body:new URLSearchParams({...body,...extra})});
 return {html,body,post};
}
async function submit(v,extra={}){
 const review=await v.post('step',{step:'review',...extra});const html=await review.text();assert.equal(review.status,200,html);
 const fields={...extra,review_token:hidden(html,'review_token')};const r=await v.post('lead',fields);assert.equal(r.status,303,await r.text());return fields;
}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;alter default privileges in schema public grant all on tables to service_role;`);
 for(const u of [owner,other]){await db.query('insert into auth.users values($1)',[u]);await db.query("insert into user_profiles values($1,'enterprise')",[u]);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922090333_funnel_campaign_workspace.sql','20260922145937_funnel_lead_inbox.sql','20260922163931_funnel_rehearsal_readonly.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql','20260924015359_funnel_campaign_attribution_grants.sql','20260924020959_funnel_conversion_intake.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{
  const args=name==='korlix_funnel_rehearsal_v1'?[p.p_actor,p.p_id]:['korlix_funnel_inbox_v1','korlix_funnel_lead_manage_v1','korlix_funnel_cleanup_preview_v1','korlix_funnel_cleanup_delete_v1'].includes(name)?[p.p_actor,p.p_id,p.p_data]:[p.p_actor,p.p_action,p.p_id??p.p_funnel,p.p_data];
  return {data:(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args)).rows[0].r};
 }catch(error){return{error};}}};
 const forbidden=new Proxy({},{get:()=>()=>{providerCalls++;throw Error('Provider action during a core journey');}});
 const app=express();app.use(express.json());registerFunnels(app,{database,environment:{KORLIX_FUNNEL_FORM_SECRET:'k196-local-fixture-only',KORLIX_FUNNEL_SCHEDULER_ENABLED:'false'},requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,now:()=>clock,metaProvider:forbidden,googleAdsProvider:forbidden,generate:forbidden.generate});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
 globalThis.fetch=(url,options)=>{assert(String(url).startsWith(base+'/'),'Only localhost fixture requests are allowed');return localFetch(url,options);};
});
test.beforeEach(async()=>{clock+=60000;f=(await json(await api('',{name:'Core journey',slug:'journey-'+randomUUID(),document:doc}),201)).funnel;});
test.after(async()=>{globalThis.fetch=localFetch;server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();assert.equal(providerCalls,0);});

test('K196 private creation, read-only rehearsal, publication and saved-draft isolation form one journey',async()=>{
 assert.equal((await fetch(base+'/f/'+f.slug)).status,404);
 const before=await counts();
 for(const scenario of ['valid','invalid_email','missing_consent']){
  const d=await json(await api('/'+f.id+'/rehearsal',{source:'draft',scenario,version:f.version,name:f.name,document:doc}));
  assert.equal(d.accepted_in_scenario,scenario==='valid');assert.deepEqual(d.performed_actions,[]);assert.equal(d.delivery_tested,false);
 }
 assert.deepEqual(await counts(),before);
 await publish();assert.match(await(await fetch(base+'/f/'+f.slug)).text(),/Find your next step/);
 const previous=f;f=(await json(await api('/'+f.id,{version:f.version,name:f.name,document:{...doc,headline:'Saved future headline'}},'PUT'))).funnel;
 assert.equal((await api('/'+f.id,{version:previous.version,name:f.name,document:doc},'PUT')).status,409);
 const live=await(await fetch(base+'/f/'+f.slug)).text();assert(live.includes(doc.headline));assert(!live.includes('Saved future headline'));
 await publish();assert.match(await(await fetch(base+'/f/'+f.slug)).text(),/Saved future headline/);
});

test('K196 guided conditional inquiry reaches booking receipt, CRM, lead management and filtered export exactly once',async()=>{
 await publish();const v=await visit('Advice');const before=await counts();
 const contact=await v.post('step',{step:'request'});assert.equal(contact.status,200);assert.deepEqual(await counts(),before);
 const fields=await submit(v,{'answer_q-2':'Hidden value must not persist'});
 assert.equal((await v.post('lead',fields)).status,303);
 const inbox=await json(await api('/'+f.id+'/inbox?source=partner&search=K196'));assert.equal(inbox.filtered_total,1);const lead=inbox.leads[0];
 assert.equal(lead.utm.utm_campaign,'k196');assert.equal(lead.outcome.booking_url,doc.booking_url);
 assert.equal(lead.answers.length,1);assert.equal(lead.answers[0].value,'Advice');
 const contactRow=(await db.query('select * from korlix_contacts where id=$1',[lead.contact_id])).rows[0];assert.equal(contactRow.email_permission,'transactional');assert.equal(contactRow.call_permission,'none');assert.equal(contactRow.phone_key,null);
 const details=await json(await api('/'+f.id+'/inbox/'+lead.id));
 await json(await api('/'+f.id+'/inbox/'+lead.id,{version:details.lead.inbox_version,status:'qualified',private_note:'=Private owner note'},'PATCH'));
 const exported=await json(await api('/'+f.id+'/inbox/export?source=partner&status=qualified&search=K196'));assert.equal(exported.count,1);assert.match(exported.csv,/Qualified/);assert.match(exported.csv,/'=Private owner note/);assert.match(exported.csv,/Advice/);assert(!exported.csv.includes('Hidden value'));
 const outcome=await(await fetch(base+'/f/'+f.slug+'?received=1')).text();assert(!outcome.includes('Private owner note'));
 assert.equal((await api('/'+f.id+'/inbox',null,'GET',other)).status,404);
 const installation=await visit('Installation');assert.equal((await installation.post('step',{step:'review'})).status,400);
 await submit(installation,{'answer_q-2':'100 Fixture Road'});
 const last=(await json(await api('/'+f.id+'/inbox'))).leads.find(l=>l.email===installation.body.email);assert.equal(last.outcome.booking_url,doc.booking_routes[0].url);assert.equal(last.answers.length,2);
});

test('K196 workflow creates review tasks while existing contact preferences and deferred providers remain unchanged',async()=>{
 await publish();const state=await json(await api('/'+f.id+'/followups'));const settings={...state.settings,enabled:true,email_enabled:true,call_enabled:true,delay_minutes:0,subject:'Hello {{name}}',body:'Requested next step for {{brand}}: {{booking_url}}',confirmed:true};
 await json(await api('/'+f.id+'/followups/settings',settings));
 const v=await visit();await submit(v);
 const inbox=await json(await api('/'+f.id+'/inbox')),lead=inbox.leads[0];
 const followups=await json(await api('/'+f.id+'/followups'));assert.equal(followups.tasks.length,2);assert(followups.tasks.every(t=>t.state==='review'));assert(followups.tasks.every(t=>t.lead_id===lead.id));assert.equal(followups.email_ready,false);assert.equal(followups.outbound_calling_enabled,false);
 const email=followups.tasks.find(t=>t.channel==='email');assert.match(email.subject,/Journey Visitor/);assert.match(email.body,/Journey fixture/);
 await db.query("update korlix_contacts set do_not_contact=true,email_permission='blocked',call_permission='blocked' where id=$1",[lead.contact_id]);
 const saved=(await db.query('select to_jsonb(c) r from korlix_contacts c where id=$1',[lead.contact_id])).rows[0].r;
 const returning=await visit('Advice',v.body.email);await submit(returning);
 assert.deepEqual((await db.query('select to_jsonb(c) r from korlix_contacts c where id=$1',[lead.contact_id])).rows[0].r,saved);
 assert.equal((await db.query('select count(*)::int n from korlix_agent_email_recipients')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from korlix_funnel_sequences')).rows[0].n,0);
 for(const provider of ['meta','google-ads','google-delivery','meta-delivery'])assert.equal((await json(await api('/'+provider+'/readiness'))).configured,false);
});

test('K196 reviewed inquiry cleanup suppresses replay and page pause preserves CRM history',async()=>{
 await publish();const v=await visit();const fields=await submit(v);const lead=(await json(await api('/'+f.id+'/inbox'))).leads[0];
 const preview=await json(await api('/'+f.id+'/inbox/cleanup/preview',{mode:'single',lead_id:lead.id}));assert.equal(preview.selected.length,1);
 await json(await api('/'+f.id+'/inbox/cleanup/delete',{confirmation:'DELETE',review_token:preview.review_token}));
 // A replay may acknowledge the original receipt, but must not recreate it.
 assert.equal((await v.post('lead',fields)).status,303);
 assert.equal((await json(await api('/'+f.id+'/inbox'))).total,0);
 assert.equal((await db.query('select count(*)::int n from korlix_contacts where id=$1',[lead.contact_id])).rows[0].n,1);
 const fresh=await visit();await json(await api('/'+f.id+'/pause',{version:f.version}));
 assert.equal((await fetch(base+'/f/'+f.slug)).status,404);assert.equal((await fresh.post('step',{step:'review'})).status,404);
});
