import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {measurementCandidate,measurementDisclosure} from '../funnels/conversion_intake.mjs';
import {registerFunnels} from '../funnels/routes.mjs';
let db,server,base,f,c,clock=Date.now()-3000000,loseReceipt=false;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const doc={brand:'Attribution studio',headline:'A useful next step',subheadline:'Ask our team.',cta:'Send inquiry',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore',body:'Talk to us.',cta:'Learn more',audience:'Local businesses',daily_cents:2500,days:14};
const rpc=async(name,actor,action,id,data={})=>(await db.query(`select public.${name}($1,$2,$3,$4::jsonb) r`,[actor,action,id,JSON.stringify(data)])).rows[0].r;
const funnel=(action,data={},id=f?.id,actor=owner)=>rpc('korlix_funnel_v1',actor,action,id,data);
const campaign=(action,data={},id=f.id,actor=owner)=>rpc('korlix_funnel_campaign_v1',actor,action,id,data);
const attr=(action,data={},actor=owner,id=f.id)=>rpc('korlix_funnel_attribution_v1',actor,action,id,{campaign_id:c.id,days:30,...data});
const api=(suffix='',body,actor=owner,method=body?'POST':'GET')=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/attribution${suffix}`,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const data=(extra={})=>({slug:f.slug,published_version:f.published_version,request_id:randomUUID(),name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'Please respond.',utm:{},...extra});
const counts=async()=>Object.fromEntries(await Promise.all(['korlix_funnel_leads','korlix_contacts','korlix_funnel_followup_tasks','korlix_funnel_attribution_events','korlix_funnel_measurement_receipts'].map(async t=>[t,(await db.query(`select count(*)::int n from ${t}`)).rows[0].n])));
const hidden=(html,key)=>html.match(new RegExp(`name="${key}" value="([^"]*)"`))?.[1]??'';
async function visit(query='',target=f){
 const r=await fetch(base+'/f/'+target.slug+query),html=await r.text();assert.equal(r.status,200,html);
 const token=hidden(html,'token'),cookie=r.headers.get('set-cookie').split(';')[0];clock+=2000;
 const body={token,measurement_token:hidden(html,'measurement_token'),name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'A request',consent:'yes'};
 const post=(fields={},suffix='lead')=>fetch(`${base}/f/${target.slug}/${suffix}`,{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie},body:new URLSearchParams({...body,...fields})});
 return {token,body,post,html};
}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 await db.exec('alter default privileges in schema public grant all on tables to service_role');
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922090333_funnel_campaign_workspace.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql','20260924015359_funnel_campaign_attribution_grants.sql','20260924020959_funnel_conversion_intake.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(n,p)=>{try{const out=await rpc(n,p.p_actor,p.p_action,p.p_id??p.p_funnel,p.p_data);if(loseReceipt&&n==='korlix_funnel_measurement_v1'&&p.p_action==='capture'){loseReceipt=false;return{error:{code:'XX000'}};}return{data:out};}catch(error){return{error};}}};
 const app=express();app.use(express.json());registerFunnels(app,{database,environment:{KORLIX_FUNNEL_FORM_SECRET:'unit-test-only'},requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,now:()=>clock});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;f=await funnel('create',{name:'Attribution',slug:'attr-'+randomUUID(),document:doc},null);f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const measure=(action,data={},actor=owner,id=f.id)=>rpc('korlix_funnel_measurement_v1',actor,action,id,{campaign_id:c.id,days:30,...data});
const mapi=(suffix='',body,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/measurement${suffix}`,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const enable=async()=>{const k=(await attr('create_link')).link.code;await measure('settings',{enabled:true,expected_revision:(await measure('read')).revision});return k;};
const rows=async()=>(await db.query('select r.* from korlix_funnel_measurement_receipts r join korlix_funnel_leads l on l.id=r.lead_id where l.funnel_id=$1',[f.id])).rows;

test('K188 default read and visits do not enable or record measurement; receipts never imply provider acceptance',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k+'&fbclid=not_saved');assert.equal(j.body.measurement_token,'');assert(!j.html.includes('measurement_consent'));assert.equal((await j.post({measurement_consent:'yes',click_id:'forged'})).status,303);assert.deepEqual(await rows(),[]);
 const r=await mapi();assert.equal(r.status,200);assert.match(r.headers.get('cache-control'),/no-store/);const d=await r.json();assert.equal(d.enabled,false);assert.equal(d.revision,null);assert.equal(d.can_enable,true);assert.equal(d.provider_verified,false);assert.equal(d.provider_delivery,'not_implemented');assert.equal(d.rows.length,30);assert.deepEqual(d.totals,{receipts:0,declined:0,missing_click:0,awaiting_setup:0});
 assert.equal((await db.query('select count(*)::int n from korlix_funnel_measurement_settings')).rows[0].n,0);
});
test('K188 service-only invoker grants survive hosted defaults, with immutable receipt rows',async()=>{
 for(const role of ['anon','authenticated']){await db.exec(`reset role;set role ${role}`);for(const t of ['korlix_funnel_measurement_settings','korlix_funnel_measurement_receipts'])await assert.rejects(db.query('select * from '+t),/permission denied/);await assert.rejects(measure('read'),/permission denied/);}
 await db.exec('reset role;set role service_role');for(const t of ['korlix_funnel_measurement_settings','korlix_funnel_measurement_receipts'])await assert.rejects(db.query('delete from '+t),/permission denied/);await assert.rejects(db.query("update korlix_funnel_measurement_receipts set state='declined'"),/permission denied/);
 for(const [actor,status] of [['',401],[basic,403],[other,404]]){assert.equal((await mapi('',null,actor)).status,status);assert.equal((await mapi('/settings',{enabled:true,expected_revision:null,days:30},actor)).status,status);}
 const r=(await db.query("select prosecdef,proconfig from pg_proc where proname='korlix_funnel_measurement_v1'")).rows[0];assert.equal(r.prosecdef,false);assert.deepEqual(r.proconfig,['search_path=public, pg_temp']);
});
test('K188 settings require recognized link and valid scope, serialize revisions and preserve explicit disable',async()=>{
 assert.equal((await mapi('/settings',{enabled:true,expected_revision:null,days:30})).status,409);const k=(await attr('create_link')).link.code;
 const a=await mapi('/settings',{enabled:true,expected_revision:null,days:30});assert.equal(a.status,200);const d=await a.json();assert.equal(d.collecting,true);assert.equal((await mapi('/settings',{enabled:false,expected_revision:null,days:30})).status,409);
 const repeated=await measure('settings',{enabled:true,expected_revision:d.revision});assert.equal(repeated.revision,d.revision);const off=await measure('settings',{enabled:false,expected_revision:d.revision});assert.equal(off.enabled,false);assert.notEqual(off.revision,d.revision);assert.equal((await visit('?kl='+k)).body.measurement_token,'');
 c=await campaign('create',{...plan,platform:'other'});await attr('create_link');await assert.rejects(measure('settings',{enabled:true,expected_revision:null}),/Google or Meta/);
});
test('K188 exact owner inputs reject duplicate windows and unsupported settings',async()=>{
 for(const query of ['?days=8','?days=7&days=30','?days=07','?enabled=true'])assert.equal((await mapi(query)).status,400);
 for(const body of [{},{enabled:'true',days:30,expected_revision:null},{enabled:true,days:'30',expected_revision:null},{enabled:true,days:30,expected_revision:null,click_id:'x'},{enabled:true,days:30,expected_revision:'bad'}])assert.equal((await mapi('/settings',body)).status,400);
 assert.equal((await mapi('/settings',{enabled:false,days:30,expected_revision:null})).status,429);
});
test('K188 explicit decline succeeds, saves exact disclosure and never stores candidate or contact details in measurement',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=private_candidate');assert(j.body.measurement_token);assert(!j.html.includes('private_candidate'));assert(!j.token.includes(j.body.measurement_token));assert.match(j.html,/name="measurement_consent" value="yes">/);assert.equal((await j.post()).status,303);
 const [r]=await rows();assert.equal(r.state,'declined');assert.equal(r.click_id,null);assert.equal(r.click_type,null);assert.equal(r.observed_at,null);assert.equal(r.consent_text,measurementDisclosure(doc.brand,'meta'));assert.equal(r.privacy_url,doc.privacy_url);assert.equal(r.page_version,f.published_version);assert.equal(r.event_name,'inquiry_submitted');assert(!JSON.stringify(r).includes(j.body.email));
 const response=await fetch(base+'/f/'+f.slug+'?kl='+k+'&received=1');assert(!((await response.text()).includes('measurement_token')));assert.equal(response.headers.get('referrer-policy'),'no-referrer');
});
test('K188 only explicit opt-in stores matching Meta or Google identifiers, with stable event and timestamps',async()=>{
 for(const platform of ['meta','google'])for(const kind of platform==='meta'?['fbclid']:['gclid','gbraid','wbraid']){
 c=await campaign('create',{...plan,platform,name:kind});const k=await enable(),j=await visit('?kl='+k+'&'+kind+'=Click_123-ABC');assert.equal((await j.post({measurement_consent:'yes',click_id:'forged',click_type:'forged'})).status,303);
 const r=(await rows()).find(r=>r.campaign_id===c.id);assert.equal(r.platform,platform);assert.equal(r.click_type,kind);assert.equal(r.click_id,'Click_123-ABC');assert.equal(r.consent,'granted');assert.equal(r.state,'awaiting_setup');assert.match(r.event_id,/^[0-9a-f-]{36}$/);assert.equal(r.consent_text,measurementDisclosure(doc.brand,platform));
 const report=await measure('read');assert.equal(report.totals.awaiting_setup,1);assert(!JSON.stringify(report).includes('Click_123'));assert(!JSON.stringify(report).includes('event_id'));}
});
test('K188 malformed, duplicate, foreign and missing IDs produce no-click receipts without copying unsafe values',async()=>{
 const k=await enable();for(const query of ['','&fbclid=a&fbclid=b','&gclid=foreign','&fbclid=%3Cscript%3E','&fbclid='+ 'a'.repeat(513)]){const j=await visit('?kl='+k+query);assert.equal((await j.post({measurement_consent:'yes'})).status,303);}
 assert((await rows()).every(r=>r.state==='missing_click'&&r.click_id===null));assert.equal((await measure('read')).totals.missing_click,5);
 assert.equal(measurementCandidate({gclid:'x',gbraid:'y'},'google'),null);assert.deepEqual(measurementCandidate({gclid:'x',fbclid:'foreign'},'google'),{type:'gclid',id:'x'});
});
test('K188 encrypted contexts are bound to the exact browser form and reject tampering, arrays and transferred envelopes',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=private_id'),otherVisit=await visit('?kl='+k+'&fbclid=other_id');
 assert.equal((await j.post({measurement_token:'a'+j.body.measurement_token.slice(1)})).status,400);assert.equal((await j.post({measurement_token:otherVisit.body.measurement_token,measurement_consent:'yes'})).status,400);assert.equal((await j.post({measurement_consent:'no'})).status,400);assert.equal((await j.post({measurement_consent:'yes',consent:''})).status,400);assert.deepEqual(await rows(),[]);
 const body=new URLSearchParams({...j.body,measurement_consent:'yes'});body.append('measurement_consent','yes');const r=await fetch(base+'/f/'+f.slug+'/lead',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:'kf_'+f.slug+'='+j.token},body});assert.equal(r.status,400);
 assert.equal((await j.post({measurement_consent:'yes'})).status,303);
});
test('K188 guided review binds optional consent and context; edits and redisplay preserve the choice',async()=>{
 f=await funnel('save',{version:f.version,name:f.name,document:{...doc,form_mode:'guided'}});f=await funnel('publish',{version:f.version,confirmed:true});const k=await enable(),j=await visit('?kl='+k+'&fbclid=guided_click');
 const fields={measurement_consent:'yes',step:'review'},r=await j.post(fields,'step'),html=await r.text();assert.equal(r.status,200);assert.match(html,/Advertising measurement: Allowed/);assert.equal(hidden(html,'measurement_token'),j.body.measurement_token);const review=hidden(html,'review_token');
 assert.equal((await j.post({review_token:review})).status,400);assert.equal((await j.post({review_token:review,measurement_consent:'yes',measurement_token:''})).status,400);
 const edit=await j.post({...fields,step:'edit_request'},'step');assert.match(await edit.text(),/name="measurement_consent" value="yes" checked/);
 const contact=await j.post({...fields,step:'edit_contact'},'step');assert.equal(hidden(await contact.text(),'measurement_consent'),'yes');
 assert.equal((await j.post({measurement_consent:'yes',review_token:review})).status,303);assert.equal((await rows())[0].state,'awaiting_setup');
});
test('K188 disabling and re-enabling invalidates old forms while inquiry capture continues',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=old_click');let d=await measure('read');d=await measure('settings',{enabled:false,expected_revision:d.revision});await measure('settings',{enabled:true,expected_revision:d.revision});assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);assert.equal((await attr('read')).totals.link_inquiries,1);
 const next=await visit('?kl='+k+'&fbclid=old_click');d=await measure('read');await measure('settings',{enabled:false,expected_revision:d.revision});assert.equal((await next.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
});
test('K188 lost responses and concurrent replay retain first consent and a single receipt',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=once');loseReceipt=true;assert.equal((await j.post({measurement_consent:'yes'})).status,503);const saved=(await rows())[0];const rs=await Promise.all([j.post(),j.post({measurement_consent:'yes'})]);assert.deepEqual(rs.map(r=>r.status),[303,303]);assert.deepEqual(await rows(),[saved]);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K188 measurement receipt failure rolls back CRM, inquiry, followup and attribution together',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=rollback'),before=await counts();await db.exec("reset role;create function public.k188_fail() returns trigger language plpgsql as $$begin raise exception 'receipt unavailable';end$$;create trigger k188_fail before insert on korlix_funnel_measurement_receipts for each row execute function public.k188_fail();set role service_role");
 try{assert.equal((await j.post({measurement_consent:'yes'})).status,400);assert.deepEqual(await counts(),before);}finally{await db.exec('reset role;drop trigger k188_fail on korlix_funnel_measurement_receipts;drop function public.k188_fail();set role service_role');}
 assert.equal((await j.post({measurement_consent:'yes'})).status,303);
});
test('K188 existing inquiry cannot gain a receipt or change consent later',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=late');assert.equal((await j.post({measurement_token:''})).status,303);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
 const next=await visit('?kl='+k+'&fbclid=denied');assert.equal((await next.post()).status,303);assert.equal((await next.post({measurement_consent:'yes'})).status,303);assert.equal((await rows())[0].state,'declined');assert.equal((await rows())[0].click_id,null);
});
test('K188 inquiry cleanup cascades measurement and tombstones suppress replay',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=remove');assert.equal((await j.post({measurement_consent:'yes'})).status,303);const nonce=JSON.parse(Buffer.from(j.token.split('.')[0],'base64url')).n;await db.query("insert into korlix_funnel_removed_requests(funnel_id,request_id,expires_at) values($1,$2,now()+interval '1 day')",[f.id,nonce]);await db.query('delete from korlix_funnel_leads where funnel_id=$1',[f.id]);assert.deepEqual(await rows(),[]);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);assert.equal((await measure('read')).totals.receipts,0);
});
test('K188 reporting states reconcile for 7/30/90 UTC dates and never expose identifiers',async()=>{
 const k=await enable();for(const [q,choice] of [['&fbclid=report_secret','yes'],['','yes'],['&fbclid=declined_secret',undefined]]){const j=await visit('?kl='+k+q);assert.equal((await j.post(choice?{measurement_consent:choice}:{})).status,303);}
 for(const days of [7,30,90]){const d=await measure('read',{days});assert.equal(d.rows.length,days);assert.equal(d.rows[0].day,d.from_day);assert.equal(d.rows.at(-1).day,d.through_day);assert.deepEqual(d.totals,{receipts:3,declined:1,missing_click:1,awaiting_setup:1});assert(!JSON.stringify(d).includes('_secret'));}
 await db.exec("reset role");await db.query("update korlix_funnel_measurement_receipts set captured_at=((now() at time zone 'UTC')::date-7)::timestamp at time zone 'UTC' where campaign_id=$1 and state='awaiting_setup'",[c.id]);await db.exec('set role service_role');assert.equal((await measure('read',{days:7})).totals.receipts,2);assert.equal((await measure('read',{days:30})).totals.receipts,3);
});
test('K188 pause, archive, republish and entitlement changes stop stale measurement safely',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=stale');c=await campaign('archive',{campaign_id:c.id,version:c.version,confirmed:true});assert.equal((await measure('read')).collecting,false);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
 c=await campaign('create',plan);const nextKey=await enable(),next=await visit('?kl='+nextKey+'&fbclid=stale');f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Changed'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await next.post({measurement_consent:'yes'})).status,400);f=await funnel('pause',{version:f.version});assert.equal((await next.post({measurement_consent:'yes'})).status,404);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);try{assert.equal((await mapi()).status,403);}finally{await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);}
});
