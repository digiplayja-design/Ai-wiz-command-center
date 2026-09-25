import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
import {journalPayload,accountPayload} from '../bookkeeping/ledger.mjs';
const owner=randomUUID(),other=randomUUID();let db,server,base,b,legacy;
const payload=(extra={})=>({request_key:randomUUID(),confirmed:true,kind:'contribution',entry_date:'2027-01-01',purpose:'Owner cash investment',lines:[{account:'1000',side:'debit',amount:'1000'},{account:'3000',side:'credit',amount:'1000'}],...extra});
const rpc=async(name,actor,action,business,data)=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[actor,action,business,data])).rows[0].r;
async function api(path='',body,actor=owner,status=200){const r=await fetch(base+'/api/bookkeeping/businesses/'+b.id+'/ledger'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Authorization:actor},...(body?{body:JSON.stringify(body)}:{})});const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));assert.equal(r.headers.get('cache-control'),'no-store');return data;}
const post=async(extra={})=>(await api('/journals',payload(extra),owner,201)).journal;
const list=async(month='2027-01',offset=0)=>api('?month='+month+'&offset='+offset);
const reverse=async(j,p={})=>(await api('/journals/'+j.id+'/reverse',{request_key:randomUUID(),confirmed:true,reason:'Input correction',...p},owner,201)).journal;
const cash=async(extra={})=>rpc('korlix_bookkeeping_v1',owner,'post',b.id,{request_key:randomUUID(),confirmed:true,kind:'income',entry_date:'2027-01-10',purpose:'Service',category:'4000',amount_cents:'12345',...extra});
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);grant usage on schema public to anon,authenticated,service_role;');
 for(const u of [owner,other])await db.query('insert into auth.users values($1)',[u]);
 await db.exec(await readFile(new URL('../../supabase/migrations/20260925015926_bookkeeping_foundation.sql',import.meta.url),'utf8'));
 legacy=(await rpc('korlix_bookkeeping_v1',owner,'create_business',null,{name:'Pre-migration business',legal_structure:'llc',tax_treatment:'unsure',request_key:randomUUID()})).business;
 await db.exec(await readFile(new URL('../../supabase/migrations/20260925062141_bookkeeping_ledger.sql',import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const app=express();app.use(express.json());registerBookkeeping(app,{database:{rpc:async(name,p)=>{try{return{data:await rpc(name,p.p_actor,p.p_action,p.p_business,p.p_data)}}catch(error){return{error}}}},requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{b=(await rpc('korlix_bookkeeping_v1',owner,'create_business',null,{name:'Ledger fixture',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()})).business;});
test.after(async()=>{server?.closeAllConnections();if(server)await new Promise(r=>server.close(r));await db?.close();});
test('exact input rejects unbalanced, duplicates, invalid dates and unreviewed payloads',()=>{
 assert.equal(journalPayload(payload()).lines[0].debit_cents,'100000');
 for(const p of [payload({confirmed:false}),payload({entry_date:'2027-02-29'}),payload({lines:[{account:'1000',side:'debit',amount:'0.10'},{account:'3000',side:'credit',amount:'0.11'}]}),payload({lines:[{account:'1000',side:'debit',amount:'1'},{account:'1000',side:'credit',amount:'1'}]}),payload({kind:'income'})])assert.throws(()=>journalPayload(p));
 assert.throws(()=>accountPayload({confirmed:true,request_key:randomUUID(),name:'Bank',kind:'income'}));
});
test('all guided types preserve balances and do not inflate operating income',async()=>{
 await post();await post({kind:'loan_received',lines:[{account:'1000',side:'debit',amount:'500'},{account:'2000',side:'credit',amount:'500'}]});
 await post({kind:'loan_principal',lines:[{account:'2000',side:'debit',amount:'100'},{account:'1000',side:'credit',amount:'100'}]});
 await post({kind:'distribution',lines:[{account:'3100',side:'debit',amount:'50'},{account:'1000',side:'credit',amount:'50'}]});
 await post({kind:'asset_purchase',lines:[{account:'1200',side:'debit',amount:'200'},{account:'2100',side:'credit',amount:'200'}]});
 const d=await list();const amount=code=>d.accounts.find(a=>a.code===code).balance_cents;assert.equal(amount('1000'),'135000');assert.equal(amount('2000'),'-40000');assert.equal(amount('1200'),'20000');assert.equal(d.accounts.reduce((s,a)=>s+BigInt(a.balance_cents),0n),0n);
 const o=await rpc('korlix_bookkeeping_v1',owner,'overview',b.id,{month:'2027-01'});assert.equal(o.income_cents,'0');assert.equal(o.expense_cents,'0');
 await api('/journals',payload({kind:'loan_received'}),owner,400);
});
test('opening balances save atomically, include all accounts and enforce cutover for old cash entries',async()=>{
 const opening=await post({kind:'opening',entry_date:'2026-12-31',lines:[{account:'1000',side:'debit',amount:'1000'},{account:'1200',side:'debit',amount:'200'},{account:'2000',side:'credit',amount:'300'},{account:'3200',side:'credit',amount:'900'}]});
 await cash();const d=await list();assert.equal(d.opening.id,opening.id);assert.equal(d.accounts.find(a=>a.code==='1000').balance_cents,'112345');assert.equal(d.accounts.find(a=>a.code==='4000').balance_cents,'-12345');
 await api('/journals',payload({kind:'opening',entry_date:'2026-12-30'}),owner,409);
 await api('/journals',payload({entry_date:'2026-12-31'}),owner,400);
 await assert.rejects(cash({entry_date:'2026-12-31'}),/after the opening/);
 await reverse(opening);await post({kind:'opening',entry_date:'2026-12-30'});
 assert.equal((await list()).opening.entry_date,'2026-12-30');
});
test('opening cutover cannot overlap existing activity, and malformed documents leave no partial rows',async()=>{
 await cash();await api('/journals',payload({kind:'opening',entry_date:'2027-01-10'}),owner,400);
 const p=journalPayload(payload());p.lines[0].debit_cents='99999';await assert.rejects(rpc('korlix_bookkeeping_ledger_v1',owner,'post',b.id,p),/must balance/);
 assert.equal((await list()).journal_count,0);
});
test('named accounts, case-insensitive duplicates, transfer and replay',async()=>{
 const p={request_key:randomUUID(),confirmed:true,kind:'cash',name:'Business savings'};
 const a=(await api('/accounts',p,owner,201)).account;assert.equal(a.kind,'cash');assert.equal(a.request_key,undefined);assert.equal((await api('/accounts',p,owner,201)).account.code,a.code);
 await api('/accounts',{...p,name:'Changed'},owner,409);await api('/accounts',{...p,name:'BUSINESS SAVINGS',request_key:randomUUID()},owner,409);
 await post({kind:'transfer',lines:[{account:a.code,side:'debit',amount:'123.45'},{account:'1000',side:'credit',amount:'123.45'}]});
 assert.equal((await list()).accounts.find(x=>x.code===a.code).balance_cents,'12345');
});
test('concurrent replay writes one journal and one audit; changed reuse conflicts',async()=>{
 const p=payload();const r=await Promise.all(Array.from({length:5},()=>api('/journals',p,owner,201)));assert.equal(new Set(r.map(x=>x.journal.id)).size,1);
 await api('/journals',{...p,purpose:'Changed'},owner,409);
 assert.equal((await db.query("select count(*)::int n from korlix_bookkeeping_audit where business_id=$1 and action='journal_post'",[b.id])).rows[0].n,1);
});
test('reversals offset all lines at original date and preserve audit, with safe replay',async()=>{
 const j=await post();const p={request_key:randomUUID(),confirmed:true,reason:'Wrong amount'};const r=await reverse(j,p);assert.equal(r.entry_date,j.entry_date);assert.equal(r.reversal_of,j.id);assert.deepEqual((await reverse(j,p)),r);
 assert((await list()).accounts.every(a=>a.balance_cents==='0'));
 await api('/journals/'+j.id+'/reverse',{...p,request_key:randomUUID()},owner,409);
 await api('/journals/'+r.id+'/reverse',{...p,request_key:randomUUID()},owner,409);
});
test('database guards block forged ownership, nonexistent accounts, income accounts, malformed lines and reversals',async()=>{
 const p=journalPayload(payload());
 for(const lines of [[{account:'1000',debit_cents:'100000',credit_cents:'0'},{account:'9999',debit_cents:'0',credit_cents:'100000'}],[{account:'1000',debit_cents:'100000',credit_cents:'0'},{account:'4000',debit_cents:'0',credit_cents:'100000'}],[{account:'1000',debit_cents:100000,credit_cents:'0'},p.lines[1]]])await assert.rejects(rpc('korlix_bookkeeping_ledger_v1',owner,'post',b.id,{...p,lines}),/account|line/i);
 const j=await post();const insert=`insert into korlix_bookkeeping_journals(business_id,entry_date,kind,purpose,lines,request_key,request_data,reversal_of,created_by) values($1,'2027-01-01','reversal','Forged',$2,$3,'{}',$4,$5)`;
 await assert.rejects(db.query(insert,[b.id,JSON.stringify(j.lines),randomUUID(),j.id,owner]),/exactly offset/);
 await assert.rejects(db.query(insert,[b.id,JSON.stringify(j.lines),randomUUID(),j.id,other]),/owner required/);
});
test('authenticated ownership and anonymous protection cover every ledger route',async()=>{
 const j=await post();for(const actor of [other,''])for(const [path,body] of [['?month=2027-01'],['/export?month=2027-01'],['/journals',payload()],['/accounts',{request_key:randomUUID(),confirmed:true,name:'Bank',kind:'cash'}],['/journals/'+j.id+'/reverse',{request_key:randomUUID(),confirmed:true,reason:'No access'}]])await api(path,body,actor,actor?404:401);
});
test('immutable history and browser permissions protect documents and combined view',async()=>{
 const j=await post();await assert.rejects(db.query('delete from korlix_bookkeeping_journals where id=$1',[j.id]),/permission denied/);
 await db.exec('reset role');try{
  for(const sql of ['delete from korlix_bookkeeping_journals where id=$1',"update korlix_bookkeeping_journals set purpose='Changed' where id=$1"])await assert.rejects(db.query(sql,[j.id]),/immutable/);
  assert((await db.query("select relrowsecurity r from pg_class where oid='korlix_bookkeeping_journals'::regclass")).rows[0].r);
  for(const role of ['anon','authenticated']){await db.exec('set role '+role);for(const table of ['korlix_bookkeeping_journals','korlix_bookkeeping_all_lines'])await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(rpc('korlix_bookkeeping_ledger_v1',owner,'list',b.id,{month:'2027-01'}),/permission denied/);await db.exec('reset role');}
 }finally{await db.exec('reset role;set role service_role');}
});
test('combined monthly export includes legacy cash, reversals and safe text with exact cents',async()=>{
 await cash();const j=await post({purpose:'=HYPERLINK("test")'});await reverse(j);await post({entry_date:'2027-02-01'});
 const d=await api('/export?month=2027-01');assert.equal(d.count,6);assert(d.csv.includes("'=HYPERLINK("));assert(d.csv.includes('"123.45"'));assert(d.csv.includes('"cash"'));assert(d.csv.includes('"reversal"'));assert(d.csv.includes(j.id));
 assert.equal((await list()).accounts.find(a=>a.code==='1000').balance_cents,'12345');
});
test('journal pagination keeps period totals and accounts independent of page',async()=>{
 for(let i=0;i<52;i++)await post({purpose:'Entry '+i});const first=await list(),second=await list('2027-01',50);assert.equal(first.journals.length,50);assert.equal(second.journals.length,2);assert.equal(first.journal_count,52);assert.deepEqual(first.accounts,second.accounts);assert.equal(new Set([...first.journals,...second.journals].map(j=>j.id)).size,52);
});

test('existing businesses receive accounts without changing original cash categories',async()=>{
 const d=await rpc('korlix_bookkeeping_ledger_v1',owner,'list',legacy.id,{month:'2027-01'});
 assert.equal(d.accounts.find(a=>a.code==='1000').name,'Recorded cash control');assert.equal(d.accounts.filter(a=>['asset','liability','equity'].includes(a.kind)).length,8);
});
test('combined export rejects overflow instead of silently truncating history',async()=>{
 await db.query(`insert into korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,purpose,request_key,request_data,created_by)
 select $1,'2027-01-01','income',1,'1000','4000','Export cap fixture',gen_random_uuid(),'{}',$2 from generate_series(1,5001)`,[b.id,owner]);
 await api('/export?month=2027-01',undefined,owner,422);
});
