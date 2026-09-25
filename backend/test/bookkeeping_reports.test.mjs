import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
import {entry} from '../bookkeeping/core.mjs';
import {journalPayload} from '../bookkeeping/ledger.mjs';
import {buildReports,reportsCsv,reportQuery} from '../bookkeeping/reports.mjs';
let db,server,base,owner,other,b,legacy;
const cashPayload=(extra={})=>({request_key:randomUUID(),confirmed:true,kind:'income',entry_date:'2027-01-15',category:'4000',amount_cents:'10000',purpose:'Service income',...extra});
const call=async(name,args)=>(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args)).rows[0].r;
const core=(action,data={},business=b.id,actor=owner)=>call('korlix_bookkeeping_v1',[actor,action,business,data]);
const ledger=(action,data)=>call('korlix_bookkeeping_ledger_v1',[owner,action,b.id,data]);
const cash=(p={})=>core('post',cashPayload(p));
const journal=(extra={})=>ledger('post',journalPayload({request_key:randomUUID(),confirmed:true,kind:'contribution',entry_date:'2027-01-01',purpose:'Owner investment',lines:[{account:'1000',side:'debit',amount:'1000'},{account:'3000',side:'credit',amount:'1000'}],...extra}));
const account=(name='Operating bank')=>ledger('account',{request_key:randomUUID(),confirmed:true,kind:'cash',name});
const receipt=(action,id,data)=>call('korlix_bookkeeping_receipts_v1',[owner,action,b.id,id,data]);
async function report(period='2027-01',kind,actor=owner,business=b.id,status=200){const r=await fetch(`${base}/api/bookkeeping/businesses/${business}/reports${kind?'/export':''}?period=${period}${kind?'&kind='+kind:''}`,{headers:{Authorization:actor}});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function readyReceipt(){const r=await receipt('reserve_upload',null,{request_key:randomUUID(),filename:'=invoice.pdf',mime_type:'application/pdf',byte_size:100,sha256:'a'.repeat(64),pages:1});await receipt('ready',r.receipt.id,{upload_token:r.upload_token});return r.receipt;}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;grant usage on schema public,storage to anon,authenticated,service_role;');
 for(const f of ['20260925015926_bookkeeping_foundation.sql','20260925024651_bookkeeping_receipts.sql','20260925062141_bookkeeping_ledger.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 owner=randomUUID();await db.query('insert into auth.users values($1)',[owner]);b=(await core('create_business',{name:'Legacy',legal_structure:'llc',tax_treatment:'unsure',request_key:randomUUID()},null)).business;
 const p=cashPayload();legacy={owner,b,p,e:(await core('post',p)).entry};
 await db.exec(await readFile(new URL('../../supabase/migrations/20260925152053_bookkeeping_reports.sql',import.meta.url),'utf8'));
 const database={rpc:async(name,p)=>{try{const args=name==='korlix_bookkeeping_reports_v1'?[p.p_actor,p.p_business,p.p_data]:[p.p_actor,p.p_action,p.p_business,p.p_data];return{data:await call(name,args)};}catch(error){return{error};}}};
 const app=express();app.use(express.json());registerBookkeeping(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const u of [owner,other])await db.query('insert into auth.users values($1)',[u]);await db.exec('set role service_role');b=(await core('create_business',{name:'=REPORT("unsafe")',legal_structure:'llc',tax_treatment:'unsure',request_key:randomUUID()},null)).business;});
test.after(async()=>{server?.closeAllConnections();if(server)await new Promise(r=>server.close(r));await db?.close();});
test('default account preserves old lost-response replay and exact request history',async()=>{
 for(const p of [legacy.p,{...legacy.p,cash_account:'1000'}])assert.equal((await core('post',p,legacy.b.id,legacy.owner)).entry.id,legacy.e.id);
 const stored=(await db.query('select request_data from korlix_bookkeeping_entries where id=$1',[legacy.e.id])).rows[0].request_data;assert.equal(stored.cash_account,undefined);
 assert.equal(entry({request_key:randomUUID(),confirmed:true,kind:'income',entry_date:'2027-01-01',category:'4000',amount:'1',purpose:'Service',cash_account:'1000'}).cash_account,undefined);
});
test('selected cash account affects both entry legs, reversal, categories and exports',async()=>{
 const a=(await account()).account;
 const p=cashPayload({cash_account:a.code});const e=(await core('post',p)).entry;
 assert.equal(e.debit_account,a.code);assert.equal((await core('post',p)).entry.id,e.id);
 await cash({kind:'expense',category:'5000',cash_account:a.code,amount_cents:'2500'});
 let d=await core('overview',{month:'2027-01'});assert.equal(d.entries.find(x=>x.id===e.id).cash_account_name,a.name);assert.equal(d.income_cents,'10000');assert(d.categories.every(x=>['income','expense'].includes(x.kind)));assert(d.cash_accounts.some(x=>x.code===a.code));
 await core('reverse',{request_key:randomUUID(),confirmed:true,entry_id:e.id,reason:'Duplicate'});
 d=await report();assert.equal(d.summary.net_cents,'-2500');assert.equal(d.accounts.find(x=>x.code===a.code).closing_cents,'-2500');assert.equal(d.summary.balance_difference_cents,'0');
 const csv=(await report('2027-01','ledger')).csv;assert(csv.includes(a.name));assert(csv.includes('reversal'));
 await assert.rejects(core('post',{...p,cash_account:'1000'}),/already been used/);
});
test('foreign, missing and noncash accounts are rejected without partial entries',async()=>{
 const foreign=(await core('create_business',{name:'Other business',legal_structure:'llc',tax_treatment:'unsure',request_key:randomUUID()},null)).business;
 const a=(await call('korlix_bookkeeping_ledger_v1',[owner,'account',foreign.id,{kind:'cash',name:'Foreign account',confirmed:true,request_key:randomUUID()}])).account;
 for(const code of [a.code,'1199','1200','4000'])await assert.rejects(cash({cash_account:code}),/cash account/);
 assert.equal((await report()).cash_entry_count,0);
 for(const code of ['1200',1000,null,'1000 OR 1=1'])assert.throws(()=>entry({cash_account:code}));
});
test('receipt posting atomically uses selected account and export references evidence on original and reversal',async()=>{
 const a=(await account()).account,r=await readyReceipt(),p=cashPayload({cash_account:a.code});
 const e=(await receipt('post_entry',r.id,{confirmed:true,entry:p})).entry;
 assert.equal((await receipt('post_entry',r.id,{confirmed:true,entry:p})).entry.id,e.id);
 await assert.rejects(receipt('post_entry',r.id,{confirmed:true,entry:cashPayload({cash_account:'1199'})}),/cash account/);
 assert.equal((await report()).cash_entry_count,1);
 await core('reverse',{request_key:randomUUID(),confirmed:true,entry_id:e.id,reason:'Incorrect posting'});
 const d=await call('korlix_bookkeeping_reports_v1',[owner,b.id,{period:'2027-01',include_lines:true}]);assert.equal(d.lines.length,4);assert(d.lines.every(l=>l.receipts[0].receipt_id===r.id));assert.equal(JSON.stringify(d).includes('object_path'),false);
 assert((await report('2027-01','ledger')).csv.includes(r.sha256));assert.equal((await report()).summary.net_cents,'0');
});
test('profit and loss excludes financing, balance sheet includes opening, earnings, debts and assets',async()=>{
 await journal({kind:'opening',entry_date:'2026-12-31',lines:[{account:'1000',side:'debit',amount:'1000'},{account:'3200',side:'credit',amount:'1000'}]});
 await cash();await cash({kind:'expense',category:'5000',amount_cents:'3000'});
 await journal({kind:'loan_received',lines:[{account:'1000',side:'debit',amount:'500'},{account:'2000',side:'credit',amount:'500'}]});
 await journal({kind:'asset_purchase',lines:[{account:'1200',side:'debit',amount:'200'},{account:'1000',side:'credit',amount:'200'}]});
 await journal({kind:'distribution',lines:[{account:'3100',side:'debit',amount:'50'},{account:'1000',side:'credit',amount:'50'}]});
 await cash({entry_date:'2027-02-01',amount_cents:'999999'});
 const d=await report();assert.deepEqual([d.summary.net_cents,d.summary.assets_cents,d.summary.liabilities_cents,d.summary.total_equity_cents,d.summary.balance_difference_cents],['7000','152000','50000','102000','0']);assert.equal(d.summary.trial_debit_cents,d.summary.trial_credit_cents);assert.equal(d.warnings.length,0);assert.equal(d.cash_entry_count,2);
 assert(d.accounts.every(a=>BigInt(a.beginning_cents)+BigInt(a.period_debit_cents)-BigInt(a.period_credit_cents)===BigInt(a.closing_cents)));
});
test('month, calendar year, leap day and empty-period balances include correct boundaries and prior earnings',async()=>{
 await cash({entry_date:'2026-12-31',amount_cents:'3000'});await cash({entry_date:'2027-01-01',amount_cents:'4000'});await cash({entry_date:'2027-12-31',amount_cents:'5000'});await cash({entry_date:'2028-02-29',amount_cents:'6000'});
 const y=await report('2027');assert.equal(y.summary.income_cents,'9000');assert.equal(y.summary.prior_earnings_cents,'3000');assert.equal(y.summary.current_earnings_cents,'9000');assert.equal(y.summary.total_equity_cents,'12000');assert.equal(y.as_of,'2027-12-31');
 const m=await report('2027-02');assert.equal(m.summary.income_cents,'0');assert.equal(m.summary.assets_cents,'7000');assert(m.warnings.some(w=>w.startsWith('No activity')));
 assert.equal((await report('2028-02')).as_of,'2028-02-29');
 for(const period of ['','1999','2100','2027-13','2027-1','2027-01-01'])await report(period,undefined,owner,b.id,400);
 await report('2027','wrong',owner,b.id,400);assert.throws(()=>reportQuery({period:['2027']}));
});
test('cutover warnings distinguish no opening, overlap and period before the opening',async()=>{
 assert((await report()).warnings.some(w=>w.startsWith('No opening')));
 await journal({kind:'opening',entry_date:'2027-01-05'});
 assert((await report()).warnings.some(w=>w.includes('initial cutover')));
 assert((await report('2026')).warnings.some(w=>w.includes('before the recorded opening')));
 await assert.rejects(cash({entry_date:'2027-01-05'}),/after the opening/);
});
test('report and export authorization, no browser RPC privilege and no writes',async()=>{
 await cash();const before=(await db.query('select count(*)::int n from korlix_bookkeeping_audit where business_id=$1',[b.id])).rows[0].n;
 for(const kind of [undefined,'profit_loss','balance_sheet','trial_balance','ledger']){await report('2027',kind);await report('2027',kind,other,b.id,404);await report('2027',kind,'',b.id,401);}
 assert.equal((await db.query('select count(*)::int n from korlix_bookkeeping_audit where business_id=$1',[b.id])).rows[0].n,before);
 await db.exec('reset role');try{for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(call('korlix_bookkeeping_reports_v1',[owner,b.id,{period:'2027'}]),/permission denied/);await db.exec('reset role');}}finally{await db.exec('reset role;set role service_role');}
});
test('CSV text formulas are neutralized while negative numeric amounts and large exact totals survive',async()=>{
 await cash({kind:'expense',category:'5000',amount_cents:'3000'});const d=await report();
 for(const kind of ['profit_loss','balance_sheet','trial_balance']){const csv=(await report('2027-01',kind)).csv;assert(csv.startsWith('\uFEFF'));assert(csv.includes("'=REPORT("));assert(csv.includes('2027-01-31'));}
 assert((await report('2027-01','profit_loss')).csv.includes('"-30.00"'));
 const n='9007199254740993123';const big=buildReports({...d,accounts:[{code:'1000',name:'Cash',kind:'cash',beginning_cents:'0',period_debit_cents:n,period_credit_cents:'0',closing_cents:n,prior_year_cents:'0'},{code:'4000',name:'@unsafe',kind:'income',beginning_cents:'0',period_debit_cents:'0',period_credit_cents:n,closing_cents:'-'+n,prior_year_cents:'0'}]});assert.equal(big.summary.net_cents,n);const csv=reportsCsv(big,'profit_loss').csv;assert(csv.includes('90071992547409931.23'));assert(csv.includes("'@unsafe"));assert.equal(big.summary.balance_difference_cents,'0');
});
test('ledger export rejects over-limit data rather than returning a partial file',async()=>{
 await db.exec('reset role');try{
  await db.query(`insert into korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,purpose,request_key,request_data,created_by) select $1,'2027-01-01','income',1,'1000','4000','Volume fixture',gen_random_uuid(),'{}',$2 from generate_series(1,25001)`,[b.id,owner]);await db.exec('set role service_role');await report('2027-01','ledger',owner,b.id,422);assert.equal((await report()).cash_entry_count,25001);
 }finally{await db.exec('reset role;set role service_role');}
});
test('statement preview uses the real owner-scoped report and exact named cash account',async()=>{
 const named=(await account()).account;
 const posted=(await cash({cash_account:named.code,amount_cents:'12345'})).entry;
 const path=`${base}/api/bookkeeping/businesses/${b.id}/statements/preview`;
 const body=JSON.stringify({csv:'Date,Memo,Amount\n2027-01-15,Service,123.45',mapping:{date:'Date',description:'Memo',amount:'Amount'},cash_account:named.code,year:'2027'});
 let r=await fetch(path,{method:'POST',headers:{'content-type':'application/json',Authorization:owner},body});
 assert.equal(r.status,200);let preview=await r.json();assert.equal(preview.entries[0].status,'suggested');assert.equal(preview.entries[0].candidates[0].entry_id,posted.id);
 assert.equal((await db.query('select count(*)::int n from korlix_bookkeeping_entries where business_id=$1',[b.id])).rows[0].n,1);
 r=await fetch(path,{method:'POST',headers:{'content-type':'application/json',Authorization:other},body});assert.equal(r.status,404);
 r=await fetch(path,{method:'POST',headers:{'content-type':'application/json'},body});assert.equal(r.status,401);
});
