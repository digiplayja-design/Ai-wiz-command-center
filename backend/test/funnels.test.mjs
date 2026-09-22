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
let db, f, server, base, clock=Date.now(), generationCalls=0, captureFailure=false;
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
  const store=createFunnelStore({rpc:async(_name,p)=>{try{
    const data=await rpc(p.p_actor,p.p_action,p.p_id,p.p_data);
    if(captureFailure&&p.p_action==='lead'){captureFailure=false;return{error:{code:'PGRST503'}};}
    return{data};
  }catch(error){return{error}}}});
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

const decodeHtml=s=>s.replace(/&#39;/g,"'").replace(/&quot;/g,'"').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
const hiddenField=(html,name)=>decodeHtml(html.match(new RegExp(`name="${name}" value="([^"]*)"`))?.[1]??'');
async function journey() {
  const funnel=await publish(await create(owner,{document:{...doc,form_mode:'guided'}}));
  const page=await http('/f/'+funnel.slug+'?utm_source=partner&utm_campaign=autumn');
  const html=await page.text(),token=hiddenField(html,'token'),cookie=page.headers.get('set-cookie').split(';')[0];clock+=2000;
  const body={token,name:'Taylor Morgan',email:'Taylor@example.com',phone:'+12025550100',message:'I would like to learn more.',utm_source:'partner',utm_campaign:'autumn'};
  const post=(suffix,fields,override={})=>http(`/f/${funnel.slug}/${suffix}`,{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie,...override},body:new URLSearchParams({...body,...fields})});
  return {f:funnel,html,token,body,post};
}
const privateSnapshot=async()=>Promise.all(['korlix_funnels','korlix_funnel_leads','korlix_contacts','korlix_funnel_followup_settings','korlix_funnel_followup_tasks','korlix_funnel_sequences','korlix_funnel_usage','korlix_agent_email_recipients'].map(async table=>(await db.query(`select coalesce(jsonb_agg(to_jsonb(x)),'[]') v from ${table} x`)).rows[0].v));
test('Guided steps preserve entered fields and attribution without saving partial inquiries; only reviewed submission captures once',async()=>{
  const j=await journey();
  assert.match(j.html,/1 · Contact details/);assert.match(j.html,/Continue to request/);assert(!j.html.includes('name="consent"'));
  await db.query('insert into korlix_funnel_followup_settings(funnel_id,enabled) values($1,true)',[j.f.id]);
  const before=await privateSnapshot();
  const step=await j.post('step',{step:'request'});assert.equal(step.status,200);const requestHtml=await step.text();
  assert.match(requestHtml,/<h2>Your request<\/h2>/);assert.equal(hiddenField(requestHtml,'name'),'Taylor Morgan');assert.match(requestHtml,/I would like to learn more\./);
  assert.equal(hiddenField(requestHtml,'token'),j.token);assert.equal(step.headers.get('set-cookie'),null);assert.equal(step.headers.get('cache-control'),'no-store');assert.equal(step.headers.get('x-robots-tag'),'noindex, nofollow');
  assert.match(step.headers.get('content-security-policy'),/default-src 'none'/);assert(!requestHtml.includes('<script'));assert(!requestHtml.includes('action="/f/'+j.f.slug+'/lead'));
  const review=await j.post('step',{step:'review',consent:'yes'});assert.equal(review.status,200);const reviewHtml=await review.text();
  assert.match(reviewHtml,/<h2>Review your inquiry<\/h2>/);assert.match(reviewHtml,/Taylor Morgan/);assert.match(reviewHtml,/This does not subscribe you to marketing messages/);
  assert.equal(hiddenField(reviewHtml,'utm_source'),'partner');assert.equal(hiddenField(reviewHtml,'utm_campaign'),'autumn');
  assert.deepEqual(await privateSnapshot(),before);
  const review_token=hiddenField(reviewHtml,'review_token');assert.match(review_token,/^[a-f0-9]{64}$/);
  for(let i=0;i<2;i++){const sent=await j.post('lead',{consent:'yes',review_token});assert.equal(sent.status,303);assert.equal(sent.headers.get('location'),`/f/${j.f.slug}?received=1#contact`);}
  const leads=await rpc(owner,'leads',j.f.id);assert.equal(leads.total,1);assert.equal(leads.leads[0].email,'taylor@example.com');assert.equal(leads.leads[0].utm.utm_campaign,'autumn');
  assert.equal((await db.query('select count(*)::integer n from korlix_funnel_followup_tasks where funnel_id=$1',[j.f.id])).rows[0].n,1);
  const contact=(await db.query('select email_permission,call_permission from korlix_contacts where id=$1',[leads.leads[0].contact_id])).rows[0];assert.equal(contact.email_permission,'transactional');assert.equal(contact.call_permission,'none');
});
test('Guided validation keeps safe field values, prevents unreviewed sends, and requires fresh consent after back/edit',async()=>{
  const j=await journey();
  const invalid=await j.post('step',{step:'request',email:'bad',name:'Taylor & Co'});assert.equal(invalid.status,400);const errorHtml=await invalid.text();
  assert.match(errorHtml,/role="alert"/);assert.match(errorHtml,/value="Taylor &amp; Co"/);assert.match(errorHtml,/value="bad"/);assert.match(errorHtml,/<h2>Your contact details/);
  const consent=await j.post('step',{step:'review'});assert.equal(consent.status,400);assert.match(await consent.text(),/Confirm that this business may respond/);
  const reviewed=await(await j.post('step',{step:'review',consent:'yes'})).text(),review_token=hiddenField(reviewed,'review_token');
  for(const step of ['edit_contact','edit_request']){
    const back=await j.post('step',{step,consent:'yes',review_token});assert.equal(back.status,200);const html=await back.text();
    assert(!html.includes('name="review_token"'));assert(!html.includes('checked'));assert(!html.includes('name="consent" value="yes" required checked'));
    if(step==='edit_contact')assert(!html.includes('name="consent"'));
  }
  for(const patch of [{review_token:''},{review_token:'0'.repeat(64)},{name:'Changed'},{email:'other@example.com'},{phone:'+12025550999'},{message:'Changed'},{utm_source:'different'},{consent:'no'}]){
    const r=await j.post('lead',{consent:'yes',review_token,...patch});assert.equal(r.status,400);assert(!((await r.text()).includes('name="review_token"')));
  }
  assert.equal((await rpc(owner,'leads',j.f.id)).total,0);
});
test('Guided steps enforce existing cookie, nonce age, page version, bot, and entitlement protections',async()=>{
  const j=await journey();
  for(const [fields,headers]of [[{token:''},{}],[{token:j.token+'.bad'},{}],[{website:'spam'},{}],[{step:'unsupported'},{}],[{},{Cookie:''}]]){
    assert.equal((await j.post('step',{step:'request',...fields},headers)).status,400);
  }
  const otherJourney=await journey(),review=await(await j.post('step',{step:'review',consent:'yes'})).text();
  assert.equal((await otherJourney.post('lead',{consent:'yes',review_token:hiddenField(review,'review_token')})).status,400);
  await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await j.post('step',{step:'request'})).status,404);
  await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
  clock+=1800001;assert.equal((await j.post('step',{step:'request'})).status,400);
  const fresh=await journey();await rpc(owner,'pause',fresh.f.id,{version:fresh.f.version});assert.equal((await fresh.post('step',{step:'request'})).status,404);
  assert.equal((await rpc(owner,'leads',j.f.id)).total,0);
});
test('Changing the draft does not change a live journey until publication; legacy documents keep one-page forms',async()=>{
  const j=await journey();
  const saved=await rpc(owner,'save',j.f.id,{version:j.f.version,name:j.f.name,document:{...doc,form_mode:'single'}});
  assert.equal((await j.post('step',{step:'request'})).status,200);
  await rpc(owner,'publish',j.f.id,{version:saved.version,confirmed:true});assert.equal((await j.post('step',{step:'request'})).status,400);
  const singlePage=await http('/f/'+j.f.slug),html=await singlePage.text();assert(!html.includes('Inquiry progress'));assert.match(html,/name="consent"/);
  assert.equal(document(doc).form_mode,'single');assert.throws(()=>document({...doc,form_mode:'auto_capture'}));
  const createResponse=await http('/api/funnels',{method:'POST',...auth(owner,{name:'Guided editor',slug:'editor-'+randomUUID(),document:{...doc,form_mode:'guided'}})});
  assert.equal(createResponse.status,201);const created=(await createResponse.json()).funnel;assert.equal(created.draft.form_mode,'guided');
  const savedResponse=await http('/api/funnels/'+created.id,{method:'PUT',...auth(owner,{version:created.version,name:created.name,document:{...doc,form_mode:'single'}})});
  assert.equal(savedResponse.status,200);assert.equal((await savedResponse.json()).funnel.draft.form_mode,'single');
});
test('Guided review escaping and disabled preview never embed visitor HTML or authorize capture',async()=>{
  const j=await journey(),name='\"><img src=x onerror=alert(1)>',message='</textarea><script>alert(1)</script>';
  const r=await j.post('step',{step:'review',consent:'yes',name,message});assert.equal(r.status,200);const html=await r.text();
  assert(!html.includes('<script>'));assert(!html.includes('<img src=x'));assert.match(html,/&lt;script&gt;/);assert.equal(hiddenField(html,'message'),message);
  for(const step of ['contact','request','review']){
    const preview=renderPage(document({...doc,form_mode:'guided'}),{preview:true,step,values:{name,email:'visitor@example.com',message}});
    for(const button of preview.matchAll(/<button\b[^>]*>/g))assert.match(button[0],/disabled/);
    assert(!preview.includes('<script>'));assert(!preview.includes('<img src=x'));
  }
  assert.equal((await rpc(owner,'leads',j.f.id)).total,0);
});
test('A lost capture response retains the reviewed nonce and permits an idempotent retry without claiming success',async()=>{
  const j=await journey(),review=await(await j.post('step',{step:'review',consent:'yes'})).text(),review_token=hiddenField(review,'review_token');
  captureFailure=true;
  const uncertain=await j.post('lead',{consent:'yes',review_token});assert.equal(uncertain.status,503);const html=await uncertain.text();
  assert.match(html,/Receipt was not confirmed/);assert.match(html,/<h2>Review your inquiry/);assert.equal(hiddenField(html,'token'),j.token);assert.equal(hiddenField(html,'review_token'),review_token);
  assert.equal((await rpc(owner,'leads',j.f.id)).total,1);
  assert.equal((await j.post('lead',{consent:'yes',review_token})).status,303);assert.equal((await rpc(owner,'leads',j.f.id)).total,1);
});
test('A full-length non-ASCII request survives URL encoding through review and final capture',async()=>{
  const j=await journey(),message='詳'.repeat(2000);
  const review=await j.post('step',{step:'review',consent:'yes',message});assert.equal(review.status,200);
  const review_token=hiddenField(await review.text(),'review_token');
  assert.equal((await j.post('lead',{consent:'yes',message,review_token})).status,303);
  const leads=await rpc(owner,'leads',j.f.id);assert.equal(leads.total,1);assert.equal(leads.leads[0].message,message);
});

test('Section editor saves privately, rejects stale and foreign saves, and publishes the ordered snapshot deliberately',async()=>{
 const sections=[{kind:'faq',visible:false},{kind:'text',id:'text-1',heading:'Our process',body:'Step one.\nStep two.'},{kind:'inquiry'},{kind:'benefits'},{kind:'main_image'}];
 let f=await create();f=await publish(f);
 const path='/api/funnels/'+f.id;
 const saved=await http(path,{method:'PUT',...auth(owner,{version:f.version,name:f.name,document:{...doc,sections}})});
 assert.equal(saved.status,200);const changed=(await saved.json()).funnel;
 assert.equal((await rpc(null,'public',null,{slug:f.slug})).document.sections,undefined);
 const before=await(await http('/f/'+f.slug)).text();assert(!before.includes('data-section="text-1"'));
 assert.equal((await http(path,{method:'PUT',...auth(other,{version:changed.version,name:f.name,document:{...doc,sections}})})).status,404);
 assert.equal((await http(path,{method:'PUT',...auth(owner,{version:f.version,name:f.name,document:{...doc,sections}})})).status,409);
 const published=await http(path+'/publish',{method:'POST',...auth(owner,{version:changed.version,confirmed:true})});assert.equal(published.status,200);
 const html=await(await http('/f/'+f.slug)).text();assert(html.includes('Our process'));assert(!html.includes('What next?'));
 assert(html.indexOf('data-section="text-1"')<html.indexOf('id="contact"'));assert.equal((html.match(/id="contact"/g)||[]).length,1);
 const copied=await http('/api/funnels',{method:'POST',...auth(owner,{name:'Copied page',slug:'copied-'+randomUUID(),document:changed.draft})});
 assert.equal(copied.status,201);assert.deepEqual((await copied.json()).funnel.draft.sections,changed.draft.sections);
 assert.equal((await rpc(owner,'leads',f.id)).total,0);
});
test('An unfinished text section can be saved but cannot be published, without changing the prior live page',async()=>{
 let f=await publish(await create());const path='/api/funnels/'+f.id;
 const sections=[{kind:'main_image'},{kind:'benefits'},{kind:'inquiry'},{kind:'faq'},{kind:'text',id:'text-1',heading:'',body:''}];
 const r=await http(path,{method:'PUT',...auth(owner,{version:f.version,name:f.name,document:{...doc,sections}})});assert.equal(r.status,200);f=(await r.json()).funnel;
 const blocked=await http(path+'/publish',{method:'POST',...auth(owner,{version:f.version,confirmed:true})});assert.equal(blocked.status,400);assert.match((await blocked.json()).error,/Complete the heading/);
 assert.equal((await rpc(null,'public',null,{slug:f.slug})).document.sections,undefined);
});
