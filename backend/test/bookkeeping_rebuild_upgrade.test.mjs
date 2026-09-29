import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';

// Real SQL and HTTP; no live account, file, provider call or financial data.
test('rebuild upgrades existing books and preserves evidence and exact retries',async t=>{
 const db=new PGlite(),owner=randomUUID(),other=randomUUID();let server,b,reportFault=null,providerCalls=0;
 const rpc=async(name,p)=>(await db.query(`select public.${name}(${p.map((_,i)=>'$'+(i+1)).join(',')}) r`,p)).rows[0].r;
 const core=(action,data,business=b.id,actor=owner)=>rpc('korlix_bookkeeping_v1',[actor,action,business,data]);
 const receipts=(action,receipt=null,data={})=>rpc('korlix_bookkeeping_receipts_v1',[owner,action,b.id,receipt,data]);
 const cash=async(extra={})=>(await core('post',{request_key:randomUUID(),confirmed:true,kind:'income',category:'4000',entry_date:'2027-01-15',purpose:'Fixture payment',amount_cents:'10000',...extra})).entry;
 const receipt=async()=>{
  const r=await receipts('reserve_upload',null,{request_key:randomUUID(),filename:'original.pdf',mime_type:'application/pdf',byte_size:24,sha256:createHash('sha256').update(randomUUID()).digest('hex'),preview_size:0,pages:1});
  return (await receipts('ready',r.receipt.id,{upload_token:r.upload_token})).receipt;
 };
 const apply=async f=>db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 try{
  await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;grant usage on schema public,storage to anon,authenticated,service_role;');
  for(const f of ['20260925015926_bookkeeping_foundation.sql','20260925024651_bookkeeping_receipts.sql','20260925055030_bookkeeping_mileage.sql','20260925062141_bookkeeping_ledger.sql','20260925152053_bookkeeping_reports.sql','20260925163933_bookkeeping_statement_imports.sql','20260925175309_bookkeeping_repeated_statement_rows.sql'])await apply(f);
  for(const actor of [owner,other])await db.query('insert into auth.users values($1)',[actor]);
  await db.exec('set role service_role');
  b=(await core('create_business',{request_key:randomUUID(),name:'Upgrade fixture',legal_structure:'llc',tax_treatment:'unsure'},null)).business;
  const original=await receipt(),legacy=await cash({amount_cents:'12345',purpose:'Existing paid service'});
  const oldLink=(await receipts('link',original.id,{entry_id:legacy.id,confirmed:true})).link;
  const before=(await rpc('korlix_bookkeeping_reports_v1',[owner,b.id,{period:'2027',include_lines:true}]));
  await db.exec('reset role');
  for(const f of ['20260929121715_bookkeeping_statement_review_rebuild.sql','20260929121726_bookkeeping_journal_evidence_rebuild.sql','20260929121737_bookkeeping_scan_recovery_rebuild.sql'])await apply(f);
  await db.exec('set role service_role');
  const database={rpc:async(name,p)=>{try{
   if(name==='korlix_bookkeeping_reports_v1'&&reportFault)return {error:reportFault};
   const args=name==='korlix_bookkeeping_reports_v1'?[p.p_actor,p.p_business,p.p_data]:name==='korlix_bookkeeping_receipts_v1'?[p.p_actor,p.p_action,p.p_business,p.p_receipt,p.p_data]:[p.p_actor,p.p_action,p.p_business,p.p_data];
   return {data:await rpc(name,args)};
  }catch(error){return {error};}}};
  const app=express();app.use(express.json({limit:'300kb'}));registerBookkeeping(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,
   receiptOptions:{storage:{download:async()=>{providerCalls++;throw Error('Unexpected provider/storage dispatch');}},scanAccess:async()=>({available:false,reason:'No scanning credits'}),scanReceipt:async()=>{providerCalls++;},chargeScan:async()=>{providerCalls++;}}});
  server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  const api=async(path,body,status=200,actor=owner)=>{
   const r=await fetch(`http://127.0.0.1:${server.address().port}/api/bookkeeping/businesses/${b.id}${path}`,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Authorization:actor},...(body?{body:JSON.stringify(body)}:{})});
   const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));assert.equal(r.headers.get('cache-control'),'no-store');return data;
  };
  const imported=(csv,extra={})=>({csv,year:'2027',cash_account:'1000',mapping:{date:'Date',description:'Memo',amount:'Amount'},request_key:randomUUID(),confirmed:true,...extra});
  const countWrites=async()=>(await db.query('select (select count(*) from korlix_bookkeeping_entries)::int entries,(select count(*) from korlix_bookkeeping_journals)::int journals,(select count(*) from korlix_bookkeeping_audit)::int audit,(select count(*) from korlix_bookkeeping_statement_decisions)::int decisions')).rows[0];

  await t.test('upgrade leaves balances, existing associations and private grants intact',async()=>{
   const after=await rpc('korlix_bookkeeping_reports_v1',[owner,b.id,{period:'2027',include_lines:true}]);
   assert.deepEqual(after.accounts,before.accounts);assert.deepEqual(after.lines,before.lines);
   assert.equal((await receipts('entry_receipts',null,{entry_id:legacy.id})).receipts[0].link.id,oldLink.id);
   const grants=(await db.query("select has_table_privilege('anon','korlix_bookkeeping_receipt_links','SELECT') anon,has_table_privilege('authenticated','korlix_bookkeeping_receipt_links','INSERT') auth,has_function_privilege('authenticated','korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb)','EXECUTE') rpc")).rows[0];
   assert.deepEqual(grants,{anon:false,auth:false,rpc:false});
  });

  await t.test('journal evidence is reviewed once; corrected replay cannot recreate a link',async()=>{
   const j=(await api('/ledger/journals',{request_key:randomUUID(),confirmed:true,kind:'contribution',entry_date:'2027-01-12',purpose:'Owner funding',lines:[{account:'1000',side:'debit',amount:'1000'},{account:'3000',side:'credit',amount:'1000'}]},201)).journal;
   const r=await receipt(),body={journal_id:j.id,request_key:randomUUID(),confirmed:true};
   const link=(await api(`/receipts/${r.id}/journal-link`,body)).link;
   assert.equal((await api(`/receipts/${r.id}/journal-link`,body)).link.id,link.id);
   await api(`/receipts/${r.id}/link`,{entry_id:legacy.id,request_key:randomUUID(),confirmed:true},409);
   await api(`/receipts/${r.id}/journal-link`,body,404,other);
   for(const path of ['/reports/export?period=2027&kind=ledger','/ledger/export?month=2027-01']){
    const csv=(await api(path)).csv;assert(csv.includes(r.sha256));assert(csv.includes(r.id));assert(!csv.includes('/original'));
   }
   await api(`/receipts/${r.id}/unlink`,{link_id:link.id,reason:'Supporting document belongs elsewhere',confirmed:true});
   const replay=(await api(`/receipts/${r.id}/journal-link`,body)).link;
   assert(replay.unlinked_at);assert.equal(replay.id,link.id);
   assert.equal((await receipts('list')).receipts.find(x=>x.id===r.id).link,null);
   const fresh=(await api(`/receipts/${r.id}/journal-link`,{...body,request_key:randomUUID()})).link;assert.notEqual(fresh.id,link.id);
   const reversal=(await api(`/ledger/journals/${j.id}/reverse`,{request_key:randomUUID(),confirmed:true,reason:'Incorrect amount'},201)).journal;
   const history=await api(`/ledger/journals/${reversal.id}/receipts`);
   assert.equal(history.evidence_journal_id,j.id);assert.equal(history.can_attach,false);assert.equal(history.receipts.length,2);
   const extra=await receipt();await api(`/receipts/${extra.id}/journal-link`,{...body,request_key:randomUUID()},409);
   await assert.rejects(db.query('insert into korlix_bookkeeping_receipt_links(business_id,receipt_id,journal_id,linked_by) values($1,$2,$3,$4)',[b.id,extra.id,j.id,owner]),/active journal/);
   await assert.rejects(db.query('insert into korlix_bookkeeping_receipt_links(business_id,receipt_id,entry_id,linked_by) values($1,$2,$3,$4)',[b.id,extra.id,legacy.id,other]),/owner required/);
   assert((await api('/reports/export?period=2027&kind=ledger')).csv.includes(r.sha256));
  });

  await t.test('scan recovery uses the exact request and replays stored results with no credits or provider dispatch',async()=>{
   const key=randomUUID(),scan=(await receipts('scan_begin',original.id,{request_key:key,confirmed:true,daily_limit:3})).scan;
   await receipts('scan_finish',original.id,{scan_id:scan.id,suggestions:{vendor:'Fixture store'}});
   const missing=randomUUID();assert.equal((await api(`/receipts/${original.id}/scan?request_key=${missing}`)).scan,null);
   assert.equal((await api(`/receipts/${original.id}/scan?request_key=${key}`)).scan.id,scan.id);
   assert.equal((await api(`/receipts/${original.id}/scan`,{request_key:key,confirmed:true})).scan.id,scan.id);
   await api(`/receipts/${original.id}/scan?request_key=invalid`,undefined,400);
   await api(`/receipts/${original.id}/scan?request_key=${key}`,undefined,404,other);
   assert.equal(providerCalls,0);
  });

  await t.test('partial overlap requires an exact current snapshot and immutable explanation',async()=>{
   const one='Date,Memo,Amount\n2027-02-01,Fee,-1.00';
   await api('/statements/import',imported(one),201);
   const partial=imported(one+'\n2027-02-02,New fee,-2.00');
   const review=await api('/statements/preview',partial);assert.equal(review.overlap_count,1);assert.equal(review.fully_overlapping,false);
   await api('/statements/import',partial,409);
   const accepted={...partial,overlap_snapshot:review.overlap_snapshot,overlap_review_reason:'Checked the original statement and confirmed the repeated source rows.'};
   const saved=await api('/statements/import',accepted,201);
   assert.equal((await api('/statements/import',accepted,201)).statement.id,saved.statement.id);
   const csv=(await api(`/statements/${saved.statement.id}/export`)).csv;assert(csv.includes(accepted.overlap_review_reason));
   // Both previously imported transactions now make an old snapshot stale.
   const stale={...accepted,request_key:randomUUID(),csv:partial.csv+'\n2027-02-03,Third fee,-3.00'};
   await api('/statements/import',stale,409);
   const full=imported('Date,Memo,Amount\n2027-02-01,Fee,-1.0');
   const fullReview=await api('/statements/preview',full);assert.equal(fullReview.fully_overlapping,true);
   await api('/statements/import',{...full,overlap_snapshot:fullReview.overlap_snapshot,overlap_review_reason:accepted.overlap_review_reason},409);
   const split=imported('Date,Memo,Debit,Credit\n2027-03-01,Deposit,0,1.05\n2027-03-02,Fee,0.99,0.00',{mapping:{date:'Date',description:'Memo',debit:'Debit',credit:'Credit'}});
   const normalized=await api('/statements/preview',split);assert.deepEqual(normalized.entries.map(x=>x.amount_cents),['105','-99']);
   await api('/statements/import',split,201);
  });

  await t.test('all thirteen candidates are reachable without writes; snapshot changes require refresh',async()=>{
   for(let i=1;i<=13;i++)await cash({purpose:`Distinct recorded purpose ${i}`});
   const s=(await api('/statements/import',imported('Date,Memo,Amount\n2027-01-15,Bank wording,100.00'),201)).statement;
   const before=await countWrites(),detail=await api(`/statements/${s.id}`),row=detail.statement.rows[0];
   assert.equal(row.candidate_total,13);assert.equal(row.candidates.length,5);assert.equal(row.candidate_next_offset,5);
   const pages=[row.candidates];
   for(const offset of [5,10])pages.push((await api(`/statements/${s.id}/rows/2/candidates?offset=${offset}&revision=${row.candidate_revision}`)).candidates);
   const all=pages.flat();assert.equal(new Set(all.map(x=>x.entry_id)).size,13);
   assert(all.every(x=>x.purpose.startsWith('Distinct recorded purpose')));
   assert.deepEqual(Object.keys(all[0]).sort(),['entry_id','date','kind','source','purpose','amount_cents'].sort());
   assert.deepEqual(await countWrites(),before);
   await api(`/statements/${s.id}/rows/2/candidates?offset=5&revision=${row.candidate_revision}`,undefined,404,other);
   await api(`/statements/${s.id}/rows/2/candidates?offset=1&revision=${row.candidate_revision}`,undefined,400);
   const body={entry_id:all[11].entry_id,request_key:randomUUID(),confirmed:true};
   const decision=(await api(`/statements/${s.id}/rows/2/match`,body,201)).decision;
   assert.equal((await api(`/statements/${s.id}/rows/2/match`,body,201)).decision.id,decision.id);
   await core('reverse',{entry_id:all[11].entry_id,request_key:randomUUID(),confirmed:true,reason:'Wrong payment'});
   await api(`/statements/${s.id}/rows/2/candidates?offset=5&revision=${row.candidate_revision}`,undefined,409);
   const reversed=await api(`/statements/${s.id}`);assert.equal(reversed.statement.rows[0].needs_review,true);assert.equal(reversed.coverage.matched_count,0);assert.equal(reversed.coverage.open_net_cents,'10000');
   assert((await api(`/statements/${s.id}/export`)).csv.includes('needs_review'));
   assert.equal(reversed.decisions[0].id,decision.id);
   await api(`/statements/${s.id}/rows/2/match`,{...body,request_key:randomUUID()},409);
   reportFault={code:'XX000',message:'Fixture unavailable'};
   await api(`/statements/${s.id}`,undefined,503);await api(`/statements/${s.id}/export`,undefined,503);
   reportFault={code:'54000',message:'Choose a shorter period.'};await api(`/statements/${s.id}`,undefined,422);reportFault=null;
  });

  await t.test('New Year matches read adjacent months and retain recorded purposes',async()=>{
   const previous=await cash({entry_date:'2026-12-31',amount_cents:'500',purpose:'Prior year service'});
   const body=imported('Date,Memo,Amount\n2027-01-01,Bank settlement,5.00');
   assert.equal((await api('/statements/preview',body)).entries[0].candidates[0].entry_id,previous.id);
   const s=(await api('/statements/import',body,201)).statement;
   await api(`/statements/${s.id}/rows/2/match`,{entry_id:previous.id,request_key:randomUUID(),confirmed:true},201);
   const detail=await api(`/statements/${s.id}`);assert.equal(detail.coverage.matched_count,1);assert.equal(detail.statement.rows[0].candidates[0].purpose,'Prior year service');
  });
 }finally{
  server?.closeAllConnections();if(server)await new Promise(r=>server.close(r));await db.close();
 }
});
