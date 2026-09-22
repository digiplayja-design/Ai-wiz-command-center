import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
import {csvCell,inboxQuery,leadCsv} from '../funnels/inbox.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),f=randomUUID(),foreign=randomUUID();
let db,server,base;
const rpc=async(actor=owner,id=f,data={})=>(await db.query('select korlix_funnel_inbox_v1($1,$2,$3::jsonb) v',[actor,id,JSON.stringify(data)])).rows[0].v;
const get=async(query={},suffix='',actor=owner)=>fetch(base+`/api/funnels/${f}/inbox${suffix}?`+new URLSearchParams(query),{headers:actor?{Authorization:actor}:{}});

test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]) {await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922145937_funnel_lead_inbox.sql']) await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 for(const [id,user] of [[f,owner],[foreign,other]]) await db.query("insert into korlix_funnels(id,user_id,name,slug,draft) values($1,$2,'Inbox test',$3,'{}')",[id,user,'inbox-'+id]);
 await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,message,utm,consent_text,created_at)
 select $1,gen_random_uuid(),1,'Inquiry '||g,'person'||g||'@example.com',case when g=7 then '100%_ special match' else 'Interested in a consultation' end,
 jsonb_build_object('utm_source',case when g%2=0 then 'facebook' else 'google' end,'utm_campaign','autumn'),'Inquiry only','2026-09-01T12:00:00.123456Z'::timestamptz from generate_series(1,137) g`,[f]);
 await db.query("insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,consent_text,created_at) values($1,gen_random_uuid(),1,'Private other owner','private@example.com','Inquiry only','2026-09-01')",[foreign]);
 const store=createFunnelStore({rpc:async(name,p)=>{try{return{data:name==='korlix_funnel_inbox_v1'?await rpc(p.p_actor,p.p_id,p.p_data):null}}catch(error){return{error}}}});
 const app=express();app.use(express.json());
 registerFunnels(app,{store,environment:{},requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Browser roles, other owners, signed-out users and downgraded tiers cannot list or export',async()=>{
 for(const role of ['anon','authenticated']) {
  await db.exec(`reset role;set role ${role}`);await assert.rejects(rpc(),/permission denied/);
 }
 await db.exec('reset role;set role service_role');
 for(const suffix of ['', '/export']) for(const [actor,status] of [[null,401],[other,404],[basic,403]]) assert.equal((await get({},suffix,actor)).status,status);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 await assert.rejects(rpc(),/Enterprise/);await assert.rejects(rpc(owner,f,{export:true}),/Enterprise/);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Every older inquiry is reachable, tied timestamps do not repeat and new arrivals wait for refresh',async()=>{
 let result=await (await get()).json();assert.equal(result.total,137);assert.equal(result.leads.length,25);
 const ids=new Set(result.leads.map(l=>l.id)),snapshot=result.snapshot;
 await db.query("insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,consent_text,created_at) values($1,gen_random_uuid(),1,'New arrival','new@example.com','Inquiry only',$2::timestamptz+interval '1 microsecond')",[f,snapshot]);
 let pages=1;
 while(result.next_cursor) {
  result=await (await get({snapshot,cursor:result.next_cursor})).json();pages++;
  assert.equal(result.total,137);
  for(const l of result.leads){assert.ok(!ids.has(l.id),'duplicate row');ids.add(l.id);}
 }
 assert.equal(pages,6);assert.equal(ids.size,137);assert.equal((await rpc()).total,138);
});
test('Search is literal, case insensitive, filters combine and UTC end date is inclusive',async()=>{
 const literal=await rpc(owner,f,{search:'100%_'});assert.equal(literal.filtered_total,1);assert.equal(literal.leads[0].name,'Inquiry 7');
 assert.equal((await rpc(owner,f,{source:'facebook',search:'PERSON',from:'2026-09-01',to:'2026-09-01'})).filtered_total,68);
 assert.equal((await rpc(owner,f,{from:'2026-09-02',to:'2026-09-03'})).filtered_total,0);
 const direct=await rpc(owner,f,{source:'Direct / untagged'});assert.equal(direct.filtered_total,1);
 const missing=await rpc(owner,f,{search:'not-present'});assert.equal(missing.filtered_total,0);assert.deepEqual(missing.leads,[]);assert.equal(missing.next,null);
});
test('Malformed filters and mismatched cursors fail with useful 400 responses',async()=>{
 const page=await (await get({source:'facebook'})).json();
 for(const q of [{from:'2026-02-30'},{from:'2026-09-03',to:'2026-09-01'},{search:'x'.repeat(161)},{cursor:'bad',snapshot:page.snapshot},{cursor:page.next_cursor,snapshot:page.snapshot,source:'google'},{snapshot:'infinity'},{'search[]':'x'}]) assert.equal((await get(q)).status,400,JSON.stringify(q));
 assert.throws(()=>inboxQuery({search:['a','b']}));
 await assert.rejects(rpc(owner,f,{before_at:'2026-09-01'}),/Invalid inbox/);
});
test('Export includes all matches rather than current page and does not change contact permissions',async()=>{
 const before=(await db.query('select count(*)::int n from korlix_contacts')).rows[0].n;
 const response=await get({source:'facebook'},'/export');assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
 const data=await response.json();assert.equal(data.count,68);assert.equal(data.csv.split('\r\n').length,70);assert.ok(!data.csv.includes('Private other owner'));
 assert.match(data.csv,/Identity verification/);assert.match(data.csv,/Unverified/);
 assert.equal((await db.query('select count(*)::int n from korlix_contacts')).rows[0].n,before);
 const empty=await (await get({search:'no-match'},'/export')).json();assert.equal(empty.count,0);
});
test('Spreadsheet formula injection, quotes, commas and line breaks are handled safely',()=>{
 for(const cell of ['=1+2','  +123','\t@SUM(A1)','-10','\n=HYPERLINK("https://bad.example")']) assert.ok(csvCell(cell).startsWith('"\''));
 assert.equal(csvCell('a,"b"\nc'),'"a,""b""\nc"');
 const csv=leadCsv([{name:'Zoë',phone:'+1 202 555 0111',message:'hello,\nworld',utm:{utm_source:'=1+1'}}]);
 assert.ok(csv.startsWith('\uFEFF'));assert.match(csv,/Zoë/);assert.match(csv,/'\+1/);assert.match(csv,/'=1\+1/);
});
test('Oversized export fails completely; a narrower export still works',async()=>{
 await db.query(`insert into korlix_funnel_leads(funnel_id,request_id,published_version,name,email,consent_text,created_at)
 select $1,gen_random_uuid(),1,'Large inbox','large@example.com','Inquiry only','2026-08-01' from generate_series(1,5001)`,[f]);
 const response=await get({},'/export');assert.equal(response.status,400);const data=await response.json();assert.match(data.error,/5,000/);assert.equal(data.csv,undefined);
 const narrow=await (await get({from:'2026-09-01',to:'2026-09-01'},'/export')).json();assert.equal(narrow.count,137);
 assert.equal((await rpc()).leads.length,25);
});
