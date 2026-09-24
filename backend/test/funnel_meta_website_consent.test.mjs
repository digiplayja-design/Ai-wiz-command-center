import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {measurementCandidate} from '../funnels/conversion_intake.mjs';
import {metaWebsiteDisclosure,metaBrowserAgent,createMetaWebsiteConsent} from '../funnels/meta_website_consent.mjs';
import {registerFunnels} from '../funnels/routes.mjs';
let db,server,base,f,c,clock=Date.now(),loseReceipt=false,handler;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const doc={brand:'Attribution studio',headline:'A useful next step',subheadline:'Ask our team.',cta:'Send inquiry',thank_you:'Thank you.',layout:'consultation',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:''};
const plan={name:'Autumn campaign',platform:'meta',headline:'Explore',body:'Talk to us.',cta:'Learn more',audience:'Local businesses',daily_cents:2500,days:14};
const rpc=async(name,actor,action,id,data={})=>(await db.query(`select public.${name}($1,$2,$3,$4::jsonb) r`,[actor,action,id,JSON.stringify(data)])).rows[0].r;
const funnel=(action,data={},id=f?.id,actor=owner)=>rpc('korlix_funnel_v1',actor,action,id,data);
const campaign=(action,data={},id=f.id,actor=owner)=>rpc('korlix_funnel_campaign_v1',actor,action,id,data);
const attr=(action,data={},actor=owner,id=f.id)=>rpc('korlix_funnel_attribution_v1',actor,action,id,{campaign_id:c.id,days:30,...data});
const api=(suffix='',body,actor=owner,method=body?'POST':'GET')=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/attribution${suffix}`,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const data=(extra={})=>({slug:f.slug,published_version:f.published_version,request_id:randomUUID(),name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'Please respond.',utm:{},...extra});
const counts=async()=>Object.fromEntries(await Promise.all(['korlix_funnel_leads','korlix_contacts','korlix_funnel_followup_tasks','korlix_funnel_attribution_events','korlix_meta_measurement_receipts'].map(async t=>[t,(await db.query(`select count(*)::int n from ${t}`)).rows[0].n])));
const hidden=(html,key)=>html.match(new RegExp(`name="${key}" value="([^"]*)"`))?.[1]??'';
const origin='https://measure.example.test',agent='Mozilla/5.0 K194Fixture';
const config={configured:true,public_origin:origin,config_hash:createHash('sha256').update('meta_measurement_v2\0'+origin).digest('hex')};
async function visit(query='',target=f){clock=Math.max(clock,Date.now()+1000);
 const r=await fetch(base+'/f/'+target.slug+query),html=await r.text();assert.equal(r.status,200,html);
 const token=hidden(html,'token'),cookie=r.headers.get('set-cookie').split(';')[0];clock+=2000;
 const body={token,measurement_token:hidden(html,'measurement_token'),name:'Visitor',email:'v-'+randomUUID()+'@example.com',message:'A request',consent:'yes'};
 const post=(fields={},suffix='lead',headers={})=>fetch(`${base}/f/${target.slug}/${suffix}`,{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:cookie,'User-Agent':agent,...headers},body:new URLSearchParams({...body,...fields})});
 return {token,body,post,html};
}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 await db.exec('alter default privileges in schema public grant all on tables to service_role');
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922031813_funnel_followups.sql','20260922035232_funnel_scheduled_followups.sql','20260922042253_funnel_sequences.sql','20260922090333_funnel_campaign_workspace.sql','20260922145937_funnel_lead_inbox.sql','20260922172151_funnel_lead_management.sql','20260922180817_funnel_inquiry_cleanup.sql','20260922211345_funnel_inquiry_questions.sql','20260922215214_funnel_conditional_questions.sql','20260922222703_funnel_booking_routes.sql','20260924013755_funnel_campaign_attribution.sql','20260924015359_funnel_campaign_attribution_grants.sql','20260924020959_funnel_conversion_intake.sql','20260924224119_meta_website_measurement_consent.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(n,p)=>{try{const out=await rpc(n,p.p_actor,p.p_action,p.p_id??p.p_funnel,p.p_data);if(loseReceipt&&n==='korlix_meta_measurement_v2'&&p.p_action==='capture'){loseReceipt=false;return{error:{code:'XX000'}};}return{data:out};}catch(error){return{error};}}};
 const app=express();app.use(express.json());handler=registerFunnels(app,{database,environment:{KORLIX_FUNNEL_FORM_SECRET:'unit-test-only',KORLIX_META_CONTEXT_ENABLED:'true',KORLIX_FUNNEL_PUBLIC_BASE_URL:origin},requireUser:async q=>[owner,other,basic].includes(q.headers.authorization)?{id:q.headers.authorization}:null,now:()=>clock});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{handler.close();clock=Date.now()+1000;f=await funnel('create',{name:'Attribution',slug:'attr-'+randomUUID(),document:doc},null);f=await funnel('publish',{version:f.version,confirmed:true});c=await campaign('create',plan);});
test.after(async()=>{await writeFile('/tmp/k194-expected-functions.json',JSON.stringify((await db.query("select proname,md5(prosrc) hash from pg_proc where proname='korlix_meta_measurement_v2'")).rows));handler.close();server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

const measure=(action,data={},actor=owner,id=f.id)=>rpc('korlix_meta_measurement_v2',actor,action,id,{campaign_id:c.id,days:30,...config,...data,...(action==='settings'?{confirmed:true}:{})});
const mapi=(suffix='',body,actor=owner)=>fetch(`${base}/api/funnels/${f.id}/campaigns/${c.id}/meta-website-consent${suffix}`,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify({...body,confirmed:body.confirmed??true})}:{})});
const enable=async()=>{const k=(await attr('create_link')).link.code;await measure('settings',{enabled:true,expected_revision:(await measure('read')).revision});return k;};
const rows=async()=>(await db.query('select r.* from korlix_meta_measurement_receipts r join korlix_funnel_leads l on l.id=r.lead_id where l.funnel_id=$1',[f.id])).rows;

test('K194 default read and visits do not enable or record measurement; receipts never imply provider acceptance',async()=>{
 const k=(await attr('create_link')).link.code,j=await visit('?kl='+k+'&fbclid=not_saved');assert.equal(j.body.measurement_token,'');assert(!j.html.includes('measurement_consent'));assert.equal((await j.post({measurement_consent:'yes',click_id:'forged'})).status,303);assert.deepEqual(await rows(),[]);
 const r=await mapi();assert.equal(r.status,200);assert.match(r.headers.get('cache-control'),/no-store/);const d=await r.json();assert.equal(d.enabled,false);assert.equal(d.revision,null);assert.equal(d.can_enable,true);assert.equal(d.provider_verified,false);assert.equal(d.send_ready,false);assert.equal(d.rows.length,30);assert.deepEqual(d.totals,{receipts:0,declined:0,missing_click:0,missing_browser:0,prepared:0});
 assert.equal((await db.query('select count(*)::int n from korlix_meta_measurement_settings')).rows[0].n,0);
});
test('K194 service-only invoker grants survive hosted defaults, with immutable receipt rows',async()=>{
 for(const role of ['anon','authenticated']){await db.exec(`reset role;set role ${role}`);for(const t of ['korlix_meta_measurement_settings','korlix_meta_measurement_receipts'])await assert.rejects(db.query('select * from '+t),/permission denied/);await assert.rejects(measure('read'),/permission denied/);}
 await db.exec('reset role;set role service_role');for(const t of ['korlix_meta_measurement_settings','korlix_meta_measurement_receipts'])await assert.rejects(db.query('delete from '+t),/permission denied/);await assert.rejects(db.query("update korlix_meta_measurement_receipts set state='declined'"),/permission denied/);
 for(const [actor,status] of [['',401],[basic,403],[other,404]]){assert.equal((await mapi('',null,actor)).status,status);assert.equal((await mapi('/settings',{enabled:true,expected_revision:null,days:30},actor)).status,status);}
 const r=(await db.query("select prosecdef,proconfig from pg_proc where proname='korlix_meta_measurement_v2'")).rows[0];assert.equal(r.prosecdef,false);assert.deepEqual(r.proconfig,['search_path=public, pg_temp']);
});
test('K194 settings require recognized link and valid scope, serialize revisions and preserve explicit disable',async()=>{
 assert.equal((await mapi('/settings',{enabled:true,expected_revision:null,days:30})).status,409);const k=(await attr('create_link')).link.code;
 const a=await mapi('/settings',{enabled:true,expected_revision:null,days:30});assert.equal(a.status,200);const d=await a.json();assert.equal(d.collecting,true);assert.equal((await mapi('/settings',{enabled:false,expected_revision:null,days:30})).status,409);
 const repeated=await measure('settings',{enabled:true,expected_revision:d.revision});assert.equal(repeated.revision,d.revision);const off=await measure('settings',{enabled:false,expected_revision:d.revision});assert.equal(off.enabled,false);assert.notEqual(off.revision,d.revision);assert.equal((await visit('?kl='+k)).body.measurement_token,'');
 c=await campaign('create',{...plan,platform:'other'});await attr('create_link');await assert.rejects(measure('settings',{enabled:true,expected_revision:null}),/Meta campaign/);
});
test('K194 exact owner inputs reject duplicate windows and unsupported settings',async()=>{
 for(const query of ['?days=8','?days=7&days=30','?days=07','?enabled=true'])assert.equal((await mapi(query)).status,400);
 for(const body of [{},{enabled:'true',days:30,expected_revision:null},{enabled:true,days:'30',expected_revision:null},{enabled:true,days:30,expected_revision:null,click_id:'x'},{enabled:true,days:30,expected_revision:'bad'}])assert.equal((await mapi('/settings',body)).status,400);
 assert.equal((await mapi('/settings',{enabled:false,days:30,expected_revision:null})).status,429);
});
test('K194 explicit decline succeeds, saves exact disclosure and never stores candidate or contact details in measurement',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=private_candidate');assert(j.body.measurement_token);assert(!j.html.includes('private_candidate'));assert(!j.token.includes(j.body.measurement_token));assert.match(j.html,/name="measurement_consent" value="yes">/);assert.equal((await j.post()).status,303);
 const [r]=await rows();assert.equal(r.state,'declined');assert.equal(r.click_id,null);assert.equal(r.client_user_agent,null);assert.equal(r.event_source_url,null);assert.equal(r.observed_at,null);assert.equal(r.consent_text,metaWebsiteDisclosure(doc.brand));assert.equal(r.privacy_url,doc.privacy_url);assert.equal(r.page_version,f.published_version);assert.equal(r.event_name,'Lead');assert(!JSON.stringify(r).includes(j.body.email));
 const response=await fetch(base+'/f/'+f.slug+'?kl='+k+'&received=1');assert(!((await response.text()).includes('measurement_token')));assert.equal(response.headers.get('referrer-policy'),'no-referrer');
});
test('K194 affirmative consent retains exact header and canonical query-free source, never forged body/host metadata',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=Click_123-ABC&email=private-query');
 assert.equal((await j.post({measurement_consent:'yes',click_id:'forged',client_user_agent:'forged',event_source_url:'https://evil.example/private'},'lead',{'Host':'evil.example','Referer':'https://evil.example/?secret=1','X-Forwarded-For':'192.0.2.10'})).status,303);
 const r=(await rows())[0];assert.equal(r.click_id,'Click_123-ABC');assert.equal(r.client_user_agent,agent);assert.equal(r.event_source_url,origin+'/f/'+f.slug);assert.equal(r.action_source,'website');assert.equal(r.policy_version,'meta_measurement_v2');assert.equal(r.consent_text,metaWebsiteDisclosure(doc.brand));assert.equal(r.state,'prepared');assert.equal(r.event_name,'Lead');assert.match(r.event_id,/^[0-9a-f-]{36}$/);
 for(const value of ['forged','private-query','192.0.2.10',j.body.email])assert(!JSON.stringify(r).includes(value));
 const report=await measure('read');assert.equal(report.totals.prepared,1);for(const value of ['Click_123',agent,'event_id','client_user_agent','event_source_url'])assert(!JSON.stringify(report).includes(value));
});
test('K194 malformed, duplicate, foreign and missing IDs produce no-click receipts without copying unsafe values',async()=>{
 const k=await enable();for(const query of ['','&fbclid=a&fbclid=b','&gclid=foreign','&fbclid=%3Cscript%3E','&fbclid='+ 'a'.repeat(513)]){const j=await visit('?kl='+k+query);assert.equal((await j.post({measurement_consent:'yes'})).status,303);}
 assert((await rows()).every(r=>r.state==='missing_click'&&r.click_id===null));assert.equal((await measure('read')).totals.missing_click,5);
 assert.equal(measurementCandidate({gclid:'x',gbraid:'y'},'google'),null);assert.deepEqual(measurementCandidate({gclid:'x',fbclid:'foreign'},'google'),{type:'gclid',id:'x'});
});
test('K194 encrypted contexts are bound to the exact browser form and reject tampering, arrays and transferred envelopes',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=private_id'),otherVisit=await visit('?kl='+k+'&fbclid=other_id');
 assert.equal((await j.post({measurement_token:'a'+j.body.measurement_token.slice(1)})).status,400);assert.equal((await j.post({measurement_token:otherVisit.body.measurement_token,measurement_consent:'yes'})).status,400);assert.equal((await j.post({measurement_consent:'no'})).status,400);assert.equal((await j.post({measurement_consent:'yes',consent:''})).status,400);assert.deepEqual(await rows(),[]);
 const body=new URLSearchParams({...j.body,measurement_consent:'yes'});body.append('measurement_consent','yes');const r=await fetch(base+'/f/'+f.slug+'/lead',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:'kf_'+f.slug+'='+j.token},body});assert.equal(r.status,400);
 assert.equal((await j.post({measurement_consent:'yes'})).status,303);
});
test('K194 guided review binds optional consent and context; edits and redisplay preserve the choice',async()=>{
 f=await funnel('save',{version:f.version,name:f.name,document:{...doc,form_mode:'guided'}});f=await funnel('publish',{version:f.version,confirmed:true});const k=await enable(),j=await visit('?kl='+k+'&fbclid=guided_click');
 const fields={measurement_consent:'yes',step:'review'},r=await j.post(fields,'step'),html=await r.text();assert.equal(r.status,200);assert.match(html,/Advertising measurement: Allowed/);assert.equal(hidden(html,'measurement_token'),j.body.measurement_token);const review=hidden(html,'review_token');
 assert.equal((await j.post({review_token:review})).status,400);assert.equal((await j.post({review_token:review,measurement_consent:'yes',measurement_token:''})).status,400);
 const edit=await j.post({...fields,step:'edit_request'},'step');assert.match(await edit.text(),/name="measurement_consent" value="yes" checked/);
 const contact=await j.post({...fields,step:'edit_contact'},'step');assert.equal(hidden(await contact.text(),'measurement_consent'),'yes');
 assert.equal((await j.post({measurement_consent:'yes',review_token:review})).status,303);assert.equal((await rows())[0].state,'prepared');
});
test('K194 disabling and re-enabling invalidates old forms while inquiry capture continues',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=old_click');let d=await measure('read');d=await measure('settings',{enabled:false,expected_revision:d.revision});await measure('settings',{enabled:true,expected_revision:d.revision});assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);assert.equal((await attr('read')).totals.link_inquiries,1);
 const next=await visit('?kl='+k+'&fbclid=old_click');d=await measure('read');await measure('settings',{enabled:false,expected_revision:d.revision});assert.equal((await next.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
});
test('K194 lost responses and concurrent replay retain first consent and a single receipt',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=once');loseReceipt=true;assert.equal((await j.post({measurement_consent:'yes'})).status,503);const saved=(await rows())[0];const rs=await Promise.all([j.post(),j.post({measurement_consent:'yes'})]);assert.deepEqual(rs.map(r=>r.status),[303,303]);assert.deepEqual(await rows(),[saved]);assert.equal((await attr('read')).totals.link_inquiries,1);
});
test('K194 measurement receipt failure rolls back CRM, inquiry, followup and attribution together',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=rollback'),before=await counts();await db.exec("reset role;create function public.k194_fail() returns trigger language plpgsql as $$begin raise exception 'receipt unavailable';end$$;create trigger k194_fail before insert on korlix_meta_measurement_receipts for each row execute function public.k194_fail();set role service_role");
 try{assert.equal((await j.post({measurement_consent:'yes'})).status,400);assert.deepEqual(await counts(),before);}finally{await db.exec('reset role;drop trigger k194_fail on korlix_meta_measurement_receipts;drop function public.k194_fail();set role service_role');}
 assert.equal((await j.post({measurement_consent:'yes'})).status,303);
});
test('K194 existing inquiry cannot gain a receipt or change consent later',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=late');assert.equal((await j.post({measurement_token:''})).status,303);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
 const next=await visit('?kl='+k+'&fbclid=denied');assert.equal((await next.post()).status,303);assert.equal((await next.post({measurement_consent:'yes'})).status,303);assert.equal((await rows())[0].state,'declined');assert.equal((await rows())[0].click_id,null);
});
test('K194 inquiry cleanup cascades measurement and tombstones suppress replay',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=remove');assert.equal((await j.post({measurement_consent:'yes'})).status,303);const nonce=JSON.parse(Buffer.from(j.token.split('.')[0],'base64url')).n;await db.query("insert into korlix_funnel_removed_requests(funnel_id,request_id,expires_at) values($1,$2,now()+interval '1 day')",[f.id,nonce]);await db.query('delete from korlix_funnel_leads where funnel_id=$1',[f.id]);assert.deepEqual(await rows(),[]);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);assert.equal((await measure('read')).totals.receipts,0);
});
test('K194 reporting states reconcile for 7/30/90 UTC dates and never expose identifiers',async()=>{
 const k=await enable();for(const [q,choice] of [['&fbclid=report_secret','yes'],['','yes'],['&fbclid=declined_secret',undefined]]){const j=await visit('?kl='+k+q);assert.equal((await j.post(choice?{measurement_consent:choice}:{})).status,303);}
 for(const days of [7,30,90]){const d=await measure('read',{days});assert.equal(d.rows.length,days);assert.equal(d.rows[0].day,d.from_day);assert.equal(d.rows.at(-1).day,d.through_day);assert.deepEqual(d.totals,{receipts:3,declined:1,missing_click:1,missing_browser:0,prepared:1});assert(!JSON.stringify(d).includes('_secret'));}
 await db.exec("reset role");await db.query("update korlix_meta_measurement_receipts set captured_at=((now() at time zone 'UTC')::date-7)::timestamp at time zone 'UTC' where campaign_id=$1 and state='prepared'",[c.id]);await db.exec('set role service_role');assert.equal((await measure('read',{days:7})).totals.receipts,2);assert.equal((await measure('read',{days:30})).totals.receipts,3);
});
test('K194 pause, archive, republish and entitlement changes stop stale measurement safely',async()=>{
 const k=await enable(),j=await visit('?kl='+k+'&fbclid=stale');c=await campaign('archive',{campaign_id:c.id,version:c.version,confirmed:true});assert.equal((await measure('read')).collecting,false);assert.equal((await j.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
 c=await campaign('create',plan);const nextKey=await enable(),next=await visit('?kl='+nextKey+'&fbclid=stale');f=await funnel('save',{version:f.version,name:f.name,document:{...doc,headline:'Changed'}});f=await funnel('publish',{version:f.version,confirmed:true});assert.equal((await next.post({measurement_consent:'yes'})).status,400);f=await funnel('pause',{version:f.version});assert.equal((await next.post({measurement_consent:'yes'})).status,404);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);try{assert.equal((await mapi()).status,403);}finally{await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);}
});
test('K194 missing or oversized browser metadata keeps inquiry and receipt but no partial measurement identifiers',async()=>{
 const k=await enable();for(const value of ['', 'x'.repeat(1025)]){const j=await visit('?kl='+k+'&fbclid=do_not_retain');assert.equal((await j.post({measurement_consent:'yes'},'lead',{'User-Agent':value})).status,303);}
 for(const r of await rows()){assert.equal(r.state,'missing_browser');for(const key of ['click_id','observed_at','client_user_agent','event_source_url'])assert.equal(r[key],null);}
 assert.equal((await measure('read')).totals.missing_browser,2);
});
test('K194 browser bounds do not truncate or invent context, and decline never reads the user-agent header',async()=>{
 for(const value of [undefined,null,[],12,'',' leading','trailing ','a\nb','a\tb','é','x'.repeat(1025)])assert.equal(metaBrowserAgent(value),null);
 assert.equal(metaBrowserAgent('x'.repeat(1024)),'x'.repeat(1024));
 const calls=[],consent=createMetaWebsiteConsent({rpc:async(_n,p)=>{calls.push(p.p_data);return {data:{ok:true}}}},origin,true);
 const headers={get 'user-agent'(){throw Error('header must not be read');}},context={revision:randomUUID(),observed:Date.now(),click:{type:'fbclid',id:'private'}};
 await consent.capture(f,data(),'code',context,'declined',headers);await consent.capture(f,data(),'code',{...context,click:null},'granted',headers);
 const disabled=createMetaWebsiteConsent({rpc:async(_n,p)=>{calls.push(p.p_data);return {data:{ok:true}}}},origin,false);await disabled.capture(f,data(),'code',context,'granted',headers);
 assert(calls.every(d=>!Object.hasOwn(d,'client_user_agent')&&!Object.hasOwn(d,'event_source_url')));assert(!Object.hasOwn(calls[0],'click_id'));
 for(const url of ['http://example.com','https://example.com/path','https://user:pass@example.com','https://example.com/?email=private','https://127.0.0.1','https://localhost','https://example.com:8443','https://[::ffff:192.0.2.1]'])assert.equal(createMetaWebsiteConsent(null,url,true).configured,false);
 assert.equal(createMetaWebsiteConsent(null,origin,false).configured,false);assert.equal(await createMetaWebsiteConsent(null,origin,false).resolve(f,'code'),null);
});
test('K194 click-only receipts stay unchanged, new consent takes priority and disabling restores the separately enabled click-only flow',async()=>{
 const k=(await attr('create_link')).link.code;
 const legacy=(action,extra={})=>rpc('korlix_funnel_measurement_v1',owner,action,f.id,{campaign_id:c.id,days:30,...extra});
 await legacy('settings',{enabled:true,expected_revision:null});const old=await visit('?kl='+k+'&fbclid=legacy');assert(!old.html.includes('browser information'));assert.equal((await old.post({measurement_consent:'yes'})).status,303);
 const snapshot=(await db.query('select * from korlix_funnel_measurement_receipts where campaign_id=$1',[c.id])).rows;
 await measure('settings',{enabled:true,expected_revision:null});assert.equal((await old.post({measurement_consent:'yes'})).status,303);assert.deepEqual(await rows(),[]);
 const next=await visit('?kl='+k+'&fbclid=future');assert(next.html.includes('browser information (user agent)'));assert.equal((await next.post({measurement_consent:'yes'})).status,303);assert.equal((await rows()).length,1);
 assert.deepEqual((await db.query('select * from korlix_funnel_measurement_receipts where campaign_id=$1',[c.id])).rows,snapshot);
 const d=await measure('read');await measure('settings',{enabled:false,expected_revision:d.revision});const fallback=await visit('?kl='+k+'&fbclid=legacy_again');assert(!fallback.html.includes('browser information'));assert.equal((await fallback.post({measurement_consent:'yes'})).status,303);assert.equal((await rows()).length,1);assert.equal((await legacy('read')).totals.receipts,2);
});
test('K194 SQL rejects pre-enable, wrong-policy and forged page/browser evidence without partial inquiry writes',async()=>{
 const k=await enable(),s=await measure('read'),before=await counts();
 const capture=(patch={})=>rpc('korlix_meta_measurement_v2',null,'capture',f.id,{...data(),...config,code:k,settings_revision:s.revision,policy_version:'meta_measurement_v2',measurement_consent:'granted',click_id:'fixture',observed_at:new Date(Date.now()+1000).toISOString(),client_user_agent:agent,event_source_url:origin+'/f/'+f.slug,...patch});
 for(const patch of [{policy_version:'measurement_v1'},{observed_at:'2020-01-01T00:00:00Z'},{observed_at:'infinity'},{event_source_url:origin+'/f/'+f.slug+'?secret=1'},{event_source_url:'https://evil.example/f/x'},{client_user_agent:'bad\n'},{client_user_agent:'x'.repeat(1025)},{click_id:123}]){await assert.rejects(capture(patch));assert.deepEqual(await counts(),before);}
 await capture();assert.equal((await rows()).length,1);
});
test('K194 platform disable or canonical-origin change suspends capture without blocking inquiry and renewal excludes old context',async()=>{
 const k=await enable(),s=await measure('read');
 const changed={...config,config_hash:'a'.repeat(64),public_origin:'https://changed.example.test'};
 for(const patch of [{configured:false},changed]){
  const d=await measure('read',patch);assert.equal(d.collecting,false);
  const out=await rpc('korlix_meta_measurement_v2',null,'capture',f.id,{...data(),...config,...patch,code:k,settings_revision:s.revision,policy_version:'meta_measurement_v2',measurement_consent:'granted',click_id:'not_saved',observed_at:new Date().toISOString(),client_user_agent:agent,event_source_url:origin+'/f/'+f.slug});assert(out);assert.deepEqual(await rows(),[]);
 }
 const renewed=await measure('settings',{...changed,enabled:true,expected_revision:s.revision});assert.notEqual(renewed.revision,s.revision);assert.equal(renewed.collecting,true);
 assert.equal((await measure('read')).collecting,false);
});
test('K194 confirmation and concurrent settings require the latest revision',async()=>{
 await attr('create_link');assert.equal((await mapi('/settings',{enabled:true,days:30,expected_revision:null,confirmed:false})).status,400);
 const b={enabled:true,days:30,expected_revision:null};const rs=await Promise.all([mapi('/settings',b),mapi('/settings',b)]);assert.deepEqual(rs.map(r=>r.status).sort(),[200,409]);assert.equal((await measure('read')).enabled,true);
});
