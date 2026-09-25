import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
import {cents,csv,profile,entry,monthQuery} from '../bookkeeping/core.mjs';
const owner=randomUUID(),other=randomUUID();let db,server,base,b;
const migration='20260925015926_bookkeeping_foundation.sql';
const profileData=(extra={})=>({name:'Fixture LLC',legal_structure:'llc',tax_treatment:'s_corporation',contractor_income:true,request_key:randomUUID(),...extra});
const entryData=(extra={})=>({kind:'income',entry_date:'2027-01-31',amount:'123.45',category:'4000',counterparty:'Fixture customer',purpose:'Consulting service',receipt_reference:'INV-001',request_key:randomUUID(),confirmed:true,...extra});
async function request(path='',body,method=body?'POST':'GET',actor=owner){return fetch(base+'/api/bookkeeping/businesses'+path,{method,headers:{'Content-Type':'application/json',Authorization:actor},...(body?{body:JSON.stringify(body)}:{})});}
async function json(r,status=200){const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));assert.equal(r.headers.get('cache-control'),'no-store');return data;}
const api=async(path='',body,method,actor,status=200)=>json(await request(path,body,method,actor),status);
const overview=async(month='2027-01',offset=0)=>api('/'+b.id+'/overview?month='+month+'&offset='+offset);
const post=async(extra={})=>(await api('/'+b.id+'/entries',entryData(extra),'POST',owner,201)).entry;
const reverse=async(e,extra={})=>(await api('/'+b.id+'/entries/'+e.id+'/reverse',{confirmed:true,reason:'Correct an input mistake',request_key:randomUUID(),...extra},'POST',owner,201)).entry;
const rpc=async(actor,action,business,data)=> (await db.query('select public.korlix_bookkeeping_v1($1,$2,$3,$4) r',[actor,action,business,data])).rows[0].r;
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);grant usage on schema public to anon,authenticated,service_role;alter default privileges in schema public grant all on tables to service_role;`);
 for(const u of [owner,other])await db.query('insert into auth.users values($1)',[u]);
 await db.exec(await readFile(new URL('../../supabase/migrations/'+migration,import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260925062141_bookkeeping_ledger.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260925152053_bookkeeping_reports.sql',import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const app=express();app.use(express.json());registerBookkeeping(app,{database:{rpc:async(_,p)=>{try{return {data:await rpc(p.p_actor,p.p_action,p.p_business,p.p_data)}}catch(error){return{error}}}},requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{b=(await api('',profileData(),'POST',owner,201)).business;});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

test('private profiles keep legal structure, tax treatment and contractor status separate',async()=>{
 assert.equal(b.legal_structure,'llc');assert.equal(b.tax_treatment,'s_corporation');assert.equal(b.contractor_income,true);assert.equal(b.currency,'USD');assert.equal(b.basis,'cash');assert.equal(b.request_key,undefined);
 assert((await api()).businesses.some(x=>x.id===b.id));assert(!(await api('',null,'GET',other)).businesses.some(x=>x.id===b.id));
 await api('/'+b.id+'/overview?month=2027-01',null,'GET',other,404);
 await api('/'+b.id+'/entries',entryData(),'POST',other,404);
 await api('/'+b.id+'/export?month=2027-01',null,'GET',other,404);
 await api('/'+b.id,profileData({version:1}),'PUT',other,404);
 await api('',null,'GET','invalid',401);
});
test('profile create retries are idempotent and changed reuse conflicts',async()=>{
 const payload=profileData();const a=await api('',payload,'POST',owner,201);const z=await api('',payload,'POST',owner,201);assert.equal(a.business.id,z.business.id);
 await api('',{...payload,name:'Different'},'POST',owner,409);
});
test('profile updates check version and record previous values',async()=>{
 const updated=(await api('/'+b.id,profileData({name:'Renamed',version:1}),'PUT')).business;assert.equal(updated.version,2);
 await api('/'+b.id,profileData({version:1}),'PUT',owner,409);
 const audit=(await db.query("select details from korlix_bookkeeping_audit where business_id=$1 and action='business_updated'",[b.id])).rows[0].details;
 assert.equal(audit.before.name,'Fixture LLC');assert.equal(audit.after.name,'Renamed');
 await api('/'+b.id,profileData({version:2,legal_structure:'sole_proprietor',tax_treatment:'s_corporation'}),'PUT',owner,400);
});
test('money parser preserves cents and rejects floating point, zero, negatives and exponent input',()=>{
 for(const [value,expected] of [['0.01','1'],['0.1','10'],['12','1200'],['9999999999.99','999999999999']])assert.equal(cents(value),expected);
 for(const value of [1.23,'0','-1','1e3','01.2','1.234','NaN','1,000','10000000000',' 1.00'])assert.throws(()=>cents(value));
});
test('input validation rejects invalid dates, unsupported types and unchecked submissions',()=>{
 for(const extra of [{entry_date:'2027-02-29'},{entry_date:'2027-13-01'},{entry_date:'2027-01-01T12:00Z'},{kind:'loan'},{confirmed:false},{purpose:' '},{request_key:'no'}])assert.throws(()=>entry(entryData(extra)));
 assert.equal(entry(entryData({entry_date:'2028-02-29'})).entry_date,'2028-02-29');
 for(const q of [{month:'2027-13'},{month:['2027-01']},{month:'2027-01',offset:'-1'},{month:'2027-01',offset:'1e3'}])assert.throws(()=>monthQuery(q));
 assert.throws(()=>profile(profileData({contractor_income:'true'})));
});
test('income and expense produce exact two-leg balanced journals and month totals',async()=>{
 const income=await post();const expense=await post({kind:'expense',category:'5010',amount:'23.45',purpose:'Business software'});
 const o=await overview();assert.equal(o.income_cents,'12345');assert.equal(o.expense_cents,'2345');assert.equal(o.net_cents,'10000');assert.equal(o.entry_count,2);
 const lines=(await db.query('select entry_id,count(*)::int n,sum(debit_cents)::text d,sum(credit_cents)::text c from korlix_bookkeeping_journal_lines where business_id=$1 group by entry_id',[b.id])).rows;
 assert.equal(lines.length,2);for(const row of lines){assert.equal(row.n,2);assert.equal(row.d,row.c);}
 assert.equal(income.debit_account,'1000');assert.equal(expense.credit_account,'1000');
 await api('/'+b.id+'/entries',entryData({kind:'expense',category:'4000'}),'POST',owner,400);
});
test('posting same reviewed request concurrently creates one entry and one audit',async()=>{
 const payload=entryData();const results=await Promise.all(Array.from({length:6},()=>api('/'+b.id+'/entries',payload,'POST',owner,201)));
 assert.equal(new Set(results.map(r=>r.entry.id)).size,1);assert.equal((await overview()).entry_count,1);
 assert.equal((await db.query("select count(*)::int n from korlix_bookkeeping_audit where business_id=$1 and action='post'",[b.id])).rows[0].n,1);
 await api('/'+b.id+'/entries',{...payload,amount:'123.46'},'POST',owner,409);
});
test('month boundaries and cents totals ignore other months and other businesses',async()=>{
 await post({entry_date:'2026-12-31',amount:'100'});await post({entry_date:'2027-01-01',amount:'0.10'});await post({entry_date:'2027-01-31',amount:'0.20'});await post({entry_date:'2027-02-01',amount:'200'});
 assert.equal((await overview()).income_cents,'30');assert.equal((await overview('2027-02')).income_cents,'20000');assert.equal((await overview('2027-03')).income_cents,'0');
});
test('reversal retains original, swaps exact legs and offsets original date',async()=>{
 const e=await post();const r=await reverse(e);assert.equal(r.reversal_of,e.id);assert.equal(r.amount_cents,e.amount_cents);assert.equal(r.entry_date,e.entry_date);assert.equal(r.debit_account,e.credit_account);
 const o=await overview();assert.equal(o.entry_count,2);assert.equal(o.income_cents,'0');assert.equal(o.entries.find(x=>x.id===e.id).reversed_by,r.id);
 await api('/'+b.id+'/entries/'+e.id+'/reverse',{confirmed:true,request_key:randomUUID(),reason:'Again'},'POST',owner,409);
 await api('/'+b.id+'/entries/'+r.id+'/reverse',{confirmed:true,request_key:randomUUID(),reason:'Again'},'POST',owner,409);
});
test('expense reversal, replay and cross-owner protection preserve correct totals',async()=>{
 const e=await post({kind:'expense',category:'5000',amount:'9.99'});const payload={request_key:randomUUID(),confirmed:true,reason:'Duplicate receipt'};
 const a=await api('/'+b.id+'/entries/'+e.id+'/reverse',payload,'POST',owner,201);const z=await api('/'+b.id+'/entries/'+e.id+'/reverse',payload,'POST',owner,201);assert.equal(a.entry.id,z.entry.id);
 assert.equal((await overview()).expense_cents,'0');await api('/'+b.id+'/entries/'+e.id+'/reverse',payload,'POST',other,404);
});
test('history cannot be edited or deleted even through direct privileged SQL',async()=>{
 const e=await post();
 for(const sql of ['update korlix_bookkeeping_entries set amount_cents=1 where id=$1','delete from korlix_bookkeeping_entries where id=$1'])await assert.rejects(db.query(sql,[e.id]),/permission denied/);
 await db.exec('reset role');
 try{await assert.rejects(db.query('update korlix_bookkeeping_entries set amount_cents=1 where id=$1',[e.id]),/immutable/);await assert.rejects(db.query('delete from korlix_bookkeeping_entries where id=$1',[e.id]),/immutable/);}finally{await db.exec('set role service_role');}
 assert.equal((await overview()).income_cents,'12345');
});
test('database rejects forged reversal legs and ownership bypass',async()=>{
 const e=await post();
 const sql=`insert into korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,purpose,request_key,request_data,reversal_of,created_by) values($1,'2027-01-31','reversal',1,'4000','1000','Invalid',$2,'{}',$3,$4)`;
 await assert.rejects(db.query(sql,[b.id,randomUUID(),e.id,owner]),/offset its original/);
 await assert.rejects(db.query(sql,[b.id,randomUUID(),e.id,other]),/owner required/);
});
test('browser roles cannot query private tables, journal view or invoke RPC',async()=>{
 await db.exec('reset role');
 try{
  const rows=(await db.query("select relname,relrowsecurity from pg_class where relnamespace='public'::regnamespace and relname in ('korlix_bookkeeping_businesses','korlix_bookkeeping_accounts','korlix_bookkeeping_entries','korlix_bookkeeping_audit')")).rows;
  assert.equal(rows.length,4);assert(rows.every(r=>r.relrowsecurity));
  for(const role of ['anon','authenticated']){await db.exec('set role '+role);for(const table of rows.map(r=>r.relname).concat('korlix_bookkeeping_journal_lines'))await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(rpc(owner,'list',null,{}),/permission denied/);await db.exec('reset role');}
 }finally{await db.exec('reset role; set role service_role');}
});
test('CSV includes corrections and neutralizes formulas and embedded quotes',async()=>{
 const e=await post({counterparty:' =IMPORTXML("x")',purpose:'Line 1, "quote"\nLine 2'});await reverse(e);
 const d=await api('/'+b.id+'/export?month=2027-01');assert.equal(d.count,2);assert.match(d.csv,/'=IMPORTXML\(""x""\)/);assert(d.csv.includes('Line 1, ""quote""\nLine 2'));assert(d.csv.includes(e.id));assert(d.csv.includes('reversal'));assert.match(d.filename,/2027-01\.csv$/);
 assert.equal(csv({...await overview(),entries:[]}).count,0);
});
test('paged overview returns every row exactly once with consistent totals',async()=>{
 for(let i=0;i<52;i++)await post({amount:'0.01',purpose:'Row '+i});
 const first=await overview(),second=await overview('2027-01',50);assert.equal(first.entries.length,50);assert.equal(second.entries.length,2);assert.equal(first.entry_count,52);assert.equal(second.income_cents,'52');assert.equal(new Set([...first.entries,...second.entries].map(e=>e.id)).size,52);
});
test('unauthenticated routes reject before touching persistence',async()=>{
 for(const [path,body,method] of [['',null,'GET'],['',{},'POST'],['/'+b.id,{},'PUT'],['/'+b.id+'/entries',{},'POST'],['/'+b.id+'/entries/'+randomUUID()+'/reverse',{},'POST'],['/'+b.id+'/export?month=2027-01',null,'GET']])await api(path,body,method,'',401);
});
