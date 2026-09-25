import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {parseStatementCsv,previewStatement} from '../bookkeeping/statement_preview.mjs';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
const account={code:'1001',name:'Operating bank',kind:'cash'};
const line={entry_id:'22222222-2222-4222-8222-222222222222',entry_date:'2027-01-15',kind:'income',source:'cash',account_code:'1001',debit_cents:'12345',credit_cents:'0'};
const report={accounts:[account],lines:[line]};
const input=(csv,extra={})=>({csv,year:'2027',cash_account:'1001',mapping:{date:'Date',description:'Memo',amount:'Amount'},...extra});
test('CSV quoting, CRLF, BOM and quoted newlines preserve row boundaries',()=>{
 const d=parseStatementCsv('\uFEFFDate,Memo,Amount\r\n2027-01-15,"Service, Jan\nretainer",123.45\r\n');
 assert.deepEqual(d.header,['Date','Memo','Amount']);assert.deepEqual(d.rows,[['2027-01-15','Service, Jan\nretainer','123.45']]);
 for(const bad of ['Date,Date\na,b','Date,Memo,Amount\n2027-01-15,"oops,12','Date,Memo,Amount\n2027-01-15,x','Date,Memo,Amount\n2027-01-15,"x"broken,1'])assert.throws(()=>parseStatementCsv(bad));
});
test('explicit mapping and exact signed cents give read-only suggestions',()=>{
 const p=previewStatement(input('Date,Memo,Amount\n2027-01-15,"Office, service",123.45\n2027-01-16,Fee,-1.05'),report);
 assert.equal(p.entries[0].status,'suggested');assert.equal(p.entries[0].candidates[0].entry_id,line.entry_id);
 assert.equal(p.entries[1].amount_cents,'-105');assert.equal(p.entries[1].status,'unmatched');assert.equal(p.invalid_count,0);
 assert.match(p.scope,/Nothing is imported/);assert(!JSON.stringify(p).includes('fingerprint'));
});
test('duplicates, ambiguous ledger lines and malformed rows cannot auto-match',()=>{
 const p=previewStatement(input('Date,Memo,Amount\n2027-01-15,Service,123.45\n2027-01-15,Service,123.45\n2027-02-29,Wrong,1\n2028-01-01,Outside,1'),{...report,lines:[line,{...line,entry_id:'33333333-3333-4333-8333-333333333333'}]});
 assert.equal(p.duplicate_count,2);assert.equal(p.invalid_count,2);assert(p.entries.slice(0,2).every(e=>e.status==='duplicate_in_file'));
 const a=previewStatement(input('Date,Memo,Amount\n2027-01-15,Service,123.45'),{...report,lines:[line,{...line,entry_id:'33333333-3333-4333-8333-333333333333'}]});assert.equal(a.entries[0].status,'ambiguous');
});
test('separate debit and credit columns, invalid values and cross-business account selection',()=>{
 const mapping={date:'Date',description:'Memo',debit:'Debit',credit:'Credit'};
 const d=previewStatement(input('Date,Memo,Debit,Credit\n2027-01-15,Deposit,,123.45\n2027-01-16,Fee,0.99,\n2027-01-17,Both,1,1\n2027-01-18,Symbol,$2,', {mapping}),report);
 assert.equal(d.entries[0].amount_cents,'12345');assert.equal(d.entries[1].amount_cents,'-99');assert.equal(d.invalid_count,2);
 assert.throws(()=>previewStatement(input('Date,Memo,Amount\n2027-01-15,Service,123.45',{cash_account:'1002'}),report));
 assert.throws(()=>previewStatement(input('Date,Memo,Amount\n2027-01-15,Service,123.45',{mapping:{date:'Date',description:'Date',amount:'Amount'}}),report));
});
test('owner authentication precedes preview parsing and repository access',async()=>{
 let calls=0;const app=express();app.use(express.json({limit:'300kb'}));registerBookkeeping(app,{database:{rpc:async()=>{calls++;return{data:report};}},requireUser:async q=>q.headers.authorization==='owner'?{id:'11111111-1111-4111-8111-111111111111'}:null});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 try{
  const url=`http://127.0.0.1:${server.address().port}/api/bookkeeping/businesses/11111111-1111-4111-8111-111111111111/statements/preview`;
  const body=JSON.stringify(input('Date,Memo,Amount\n2027-01-15,Service,123.45'));
  const req=(authorization)=>fetch(url,{method:'POST',headers:{'content-type':'application/json',authorization},body});
  const denied=await req('');assert.equal(denied.status,401);assert.equal(denied.headers.get('cache-control'),'no-store');assert.equal(calls,0);
  const allowed=await req('owner');assert.equal(allowed.status,200);assert.equal((await allowed.json()).entries[0].status,'suggested');assert.equal(calls,1);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
});
