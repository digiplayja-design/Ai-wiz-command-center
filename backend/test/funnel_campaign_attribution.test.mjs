import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
let db,server,base,f,c,clock=Date.now(),loseReceipt=false;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const doc={brand:'Attribution studio',headline:'A useful next step',subheadline:'Ask our team.',cta:'Send inquiry',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore',body:'Talk to us.',cta:'Learn more',audience:'Local businesses',daily_cents:2500,days:14};
const rpc=async(name,actor,action,id,data={})=>(await db.query(`select public.${name}($1,$2,$3,$4::jsonb) r`,[actor,action,id,JSON.stringify(data)])).rows[0].r;
const funnel=(action,data={},id=f?.id,actor=owner)=>rpc('korlix_funnel_v1',actor,action,id,data);
const campaign=(action,data={},id=f.id,actor=owner)=>rpc('korlix_funnel_campaign_v1',actor,action,id,data);
const attr=(action,data={},actor=owner,id=f.id)=>rpc('korlix_funnel_attribution_v1',actor,action,id,{campaign_id:c.id,days:30,...data});
const api=(suffix='',body,actor=owner,method=body?'POST':'GET')=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/attribution${suffix}`,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const data=(extra={})=>({slug:f.slug,published_version:f.published_version,request_id:randomUUID(),name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'Please respond.',utm:{},...extra});
const counts=async()=>Object.fromEntries(await Promise.all(['korlix_funnel_leads','korlix_contacts','korlix_funnel_followup_tasks','korlix_funnel_attribution_events'].map(async t=>[t,(await db.query(`select count(*)::int n from ${t}`)).rows[0].n])));
const hidden=(html,key)=>html.match(new RegExp(`name="${key}" value="([^"]*)"`))?.[1]??'';
async function visit(query='',target=f){
 const r=await fetch(base+'/f/'+target.slug+query),html=await r.text();assert.equal(r.status,200,html);
 const token=hidden(html,'token'),cookie=r.headers.get('set-cookie').split(';')[0];clock+=2000;
 const body={token,name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'A request',consent:'yes'};
 const post=(fields={},suffix='lead')=>fetch(`${base}/f/${target.slug}/${suffix}`,{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie},body:new URLSearchParams({...body,...fields})});
 return {token,body,post,html};
}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922090333_funnel_campaign_workspace.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(n,p)=>{try{const out=await rpc(n,p.p_actor,p.p_action,p.p_id??p.p_funnel,p.p_data);if(loseReceipt&&n==='korlix_funnel_attribution_v1'&&p.p_action==='capture'){loseReceipt=false;return{error:{code:'XX000'}};}return{data:out};}catch(error){return{error};}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,environment:{KORLIX_FUNNEL_FORM_SECRET:'unit-test-only'},requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,now:()=>clock});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;f=await funnel('create',{name:'Attribution',slug:'attr-'+randomUUID(),document:doc},null);f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('K187 reads are side-effect free; link creation is stable and idempotent',async()=>{
 let r=await api();assert.equal(r.status,200);assert.match(r.headers.get('cache-control'),/no-store/);let d=await r.json();assert.equal(d.link,null);assert.equal(d.provider_verified,false);assert.equal(d.rows.length,30);assert.deepEqual(d.totals,{link_inquiries:0,tag_only_inquiries:0,tag_conflicts:0});
 const rs=await Promise.all([api('/link',{days:7}),api('/link',{days:7})]);const a=await rs[0].json(),b=await rs[1].json();assert.deepEqual(a.link,b.link);const u=new URL(a.link.url);assert.match(u.searchParams.get('kl'),/^[a-f0-9]{64}$/);assert.equal(u.searchParams.get('utm_source'),'facebook');assert.equal(u.searchParams.get('utm_campaign'),'k143_'+c.id.replaceAll('-',''));assert(!JSON.stringify(a).includes('"code"'));assert.equal((await db.query('select count(*)::int n from korlix_funnel_attribution_links where campaign_id=$1',[c.id])).rows[0].n,1);
});
test('K187 browser roles, other owners and lower tiers cannot access attribution',async()=>{
 for(const role of ['anon','authenticated']){await db.exec(`reset role;set role ${role}`);for(const t of ['korlix_funnel_attribution_links','korlix_funnel_attribution_events'])await assert.rejects(db.query('select * from '+t),/permission denied/);await assert.rejects(attr('read'),/permission denied/);}
 await db.exec('reset role;set role service_role');
 for(const [actor,status]of [['',401],[basic,403],[other,404]]){assert.equal((await api('',null,actor)).status,status);assert.equal((await api('/link',{days:30},actor)).status,status);}
 for(const t of ['korlix_funnel_attribution_links','korlix_funnel_attribution_events']){await assert.rejects(db.query('delete from '+t),/permission denied/);await assert.rejects(db.query('update '+t+' set '+(t.endsWith('links')?'created_at=now()':'captured_at=now()')),/permission denied/);}
});
test('K187 exact route inputs and published nonarchived link creation are enforced',async()=>{
 for(const query of ['?days=8','?days=7&days=30','?days=07','?campaign_id=x'])assert.equal((await api(query)).status,400);
 for(const body of [{},{days:'30'},{days:8},{days:30,code:'a'.repeat(64)}])assert.equal((await api('/link',body)).status,400);
 clock+=60000;f=await funnel('pause',{version:f.version});assert.equal((await api('/link',{days:30})).status,409);f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('archive',{campaign_id:c.id,version:c.version,confirmed:true});assert.equal((await api('/link',{days:30})).status,409);assert.equal((await api()).status,200);
});
test('K187 recognized link creates atomic inquiry evidence independently of edited URL tags',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k+'&utm_source=google');assert.equal(JSON.parse(Buffer.from(j.token.split('.')[0],'base64url')).a,k);
 assert.equal((await j.post({utm_source:'fake',utm_campaign:'forged'})).status,303);const events=(await db.query('select a.*,l.utm from korlix_funnel_attribution_events a join korlix_funnel_leads l on l.id=a.lead_id where l.funnel_id=$1',[f.id])).rows;assert.equal(events.length,1);assert.equal(events[0].campaign_id,c.id);assert.equal(events[0].utm.utm_source,'fake');const d=await attr('read');assert.equal(d.totals.link_inquiries,1);assert.equal(d.totals.tag_only_inquiries,0);assert.equal(d.totals.tag_conflicts,1);
});
test('K187 plain or invalid link visits and browser-supplied evidence never gain a link association',async()=>{
 const k=(await attr('create_link')).link.code;
 for(const query of ['', '?kl='+'a'.repeat(64),'?kl=bad','?kl='+k+'&kl='+k]){const j=await visit(query);assert(!JSON.parse(Buffer.from(j.token.split('.')[0],'base64url')).a);assert.equal((await j.post({code:k,a:k,campaign_id:c.id,utm_source:'facebook',utm_campaign:'k143_'+c.id.replaceAll('-','')})).status,303);}
 const d=await attr('read');assert.equal(d.totals.link_inquiries,0);assert.equal(d.totals.tag_only_inquiries,4);
});
test('K187 cross-funnel codes cannot resolve or capture, even under the same owner',async()=>{
 const k=(await attr('create_link')).link.code,first=f;let second=await funnel('create',{name:'Second',slug:'second-'+randomUUID(),document:doc},null);second=await funnel('publish',{version:second.version,confirmed:true},second.id);const j=await visit('?kl='+k,second);assert(!JSON.parse(Buffer.from(j.token.split('.')[0],'base64url')).a);assert.equal((await j.post()).status,303);await assert.rejects(attr('capture',data({slug:second.slug,published_version:second.published_version,code:k}),null,second.id),/link changed/);assert.equal((await attr('read')).totals.link_inquiries,0);f=first;
});
test('K187 form signatures prevent replacing link evidence and body codes are ignored',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k),parts=j.token.split('.'),p=JSON.parse(Buffer.from(parts[0],'base64url'));p.a='f'.repeat(64);const forged=Buffer.from(JSON.stringify(p)).toString('base64url')+'.'+parts[1];assert.equal((await j.post({token:forged})).status,400);assert.equal((await j.post({code:'f'.repeat(64)})).status,303);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K187 guided review preserves link evidence and enforces consent and exact review',async()=>{
 f=await funnel('save',{version:f.version,name:f.name,document:{...doc,form_mode:'guided'}});f=await funnel('publish',{version:f.version,confirmed:true});const k=(await attr('create_link')).link.code,j=await visit('?kl='+k);
 assert.equal((await j.post({consent:'no',step:'review'},'step')).status,400);assert.equal((await attr('read')).totals.link_inquiries,0);
 const review=await j.post({step:'review'},'step'),html=await review.text(),signature=hidden(html,'review_token');assert.equal(review.status,200);assert.equal(hidden(html,'token'),j.token);assert.equal((await j.post({review_token:signature,message:'Changed'})).status,400);assert.equal((await j.post({review_token:signature})).status,303);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K187 lost HTTP receipt and concurrent replay retain one inquiry and association',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k);loseReceipt=true;assert.equal((await j.post()).status,503);const replies=await Promise.all([j.post(),j.post()]);assert.deepEqual(replies.map(r=>r.status),[303,303]);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K187 event persistence failure rolls back CRM, inquiry and workflow task together',async()=>{
 await db.query('insert into korlix_funnel_followup_settings(funnel_id,enabled) values($1,true)',[f.id]);const k=(await attr('create_link')).link.code,j=await visit('?kl='+k),before=await counts();
 await db.exec("reset role;create function public.k187_fail_event() returns trigger language plpgsql as $$begin raise exception 'forced event failure';end$$;create trigger k187_fail before insert on korlix_funnel_attribution_events for each row execute function public.k187_fail_event();set role service_role");
 try{assert.equal((await j.post()).status,400);assert.deepEqual(await counts(),before);}finally{await db.exec('reset role;drop trigger k187_fail on korlix_funnel_attribution_events;drop function public.k187_fail_event();set role service_role');}
 assert.equal((await j.post()).status,303);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K187 existing untracked inquiries cannot be backfilled and evidence cannot move to another campaign',async()=>{
 const k=(await attr('create_link')).link.code,a=data();await funnel('lead',a,null,null);await attr('capture',{...a,code:k},null);assert.equal((await attr('read')).totals.link_inquiries,0);
 const b=data();await attr('capture',{...b,code:k},null);const otherCampaign=await campaign('create',{...plan,name:'Second campaign'});const k2=(await attr('create_link',{campaign_id:otherCampaign.id})).link.code;await attr('capture',{...b,code:k2},null);assert.equal((await attr('read')).totals.link_inquiries,1);assert.equal((await attr('read',{campaign_id:otherCampaign.id})).totals.link_inquiries,0);
});
test('K187 historical and direct visits remain distinct from evidence, with UTC windows and reconciled totals',async()=>{
 const k=(await attr('create_link')).link.code,a=data({utm:{utm_source:'facebook',utm_campaign:'k143_'+c.id.replaceAll('-','')}});await attr('capture',{...a,code:k},null);await funnel('lead',data({utm:a.utm}),null,null);await funnel('lead',data(),null,null);
 const second=await campaign('create',plan),k2=(await attr('create_link',{campaign_id:second.id})).link.code;await attr('capture',{...data({utm:a.utm}),code:k2},null);
 for(const days of [7,30,90]){const d=await attr('read',{days});assert.equal(d.rows.length,days);assert.deepEqual(d.totals,{link_inquiries:1,tag_only_inquiries:1,tag_conflicts:0});assert.equal(d.rows[0].day,d.from_day);assert.equal(d.rows.at(-1).day,d.through_day);assert.equal(d.timezone,'UTC');assert.equal(d.includes_today,true);}
 await db.query("update korlix_funnel_leads set created_at=((now() at time zone 'UTC')::date-7)::timestamp at time zone 'UTC' where request_id=$1",[a.request_id]);assert.equal((await attr('read',{days:7})).totals.link_inquiries,0);assert.equal((await attr('read',{days:30})).totals.link_inquiries,1);
});
test('K187 inquiry cleanup cascades attribution and tombstone retries cannot recreate it',async()=>{
 const k=(await attr('create_link')).link.code,a=data();await attr('capture',{...a,code:k},null);
 await db.query("insert into korlix_funnel_removed_requests(funnel_id,request_id,expires_at) values($1,$2,now()+interval '1 day')",[f.id,a.request_id]);await db.query('delete from korlix_funnel_leads where funnel_id=$1',[f.id]);assert.equal((await attr('read')).totals.link_inquiries,0);await attr('capture',{...a,code:k},null);assert.equal((await attr('read')).totals.link_inquiries,0);
});
test('K187 republish, page pause and entitlement loss stop stale capture',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k);f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Changed'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await j.post()).status,400);const next=await visit('?kl='+k);f=await funnel('pause',{version:f.version});assert.equal((await next.post()).status,404);f=await funnel('publish',{version:f.version,confirmed:true});const last=await visit('?kl='+k);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);try{assert.equal((await last.post()).status,404);assert.equal((await api()).status,403);}finally{await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);}
});
