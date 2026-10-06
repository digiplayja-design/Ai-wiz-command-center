import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerReceiptWiz} from '../receipt_wiz/routes.mjs';
import {receiptDetails,scanReceiptWiz,csvExport} from '../receipt_wiz/core.mjs';
let db,server,base,owner,other,bytes,scanCalls,scanFail,uploadFail,deleteFail,scanGate;const objects=new Map();
const details=()=>({merchant:'Wiz fixture',date:'2026-10-06',total:'18.50',subtotal:'17.00',tax:'1.50',tip:'',currency:'USD',category:'Office supplies',description:'Printer paper',items:['Paper'],warnings:[]});
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_receipt_wiz_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',data,method=data?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(data?{body:JSON.stringify(data)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function upload({actor=owner,key=randomUUID(),buffer=bytes,status=201}={}){const f=new FormData();f.append('receipt',new Blob([buffer]),'receipt.png');const r=await fetch(base,{method:'POST',headers:{Authorization:actor,'X-Receipt-Request-Key':key},body:f});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));return d;}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;create policy legacy on storage.objects for all to anon,authenticated using(true) with check(true);grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;create table public.korlix_bookkeeping_businesses(id uuid primary key,owner_id uuid,name text);create table public.korlix_tax_workspaces(id uuid primary key,owner_id uuid,tax_year int);grant select on korlix_bookkeeping_businesses,korlix_tax_workspaces to service_role;`);
 for(const migration of ['20261006171056_receipt_wiz_shared_inbox.sql','20261006174957_receipt_wiz_explicit_private_policies.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+migration,import.meta.url),'utf8'));
 bytes=await sharp({create:{width:60,height:100,channels:3,background:'#ddd'}}).png().toBuffer();
 const database={rpc:async(_,p)=>{try{return{data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)}}catch(error){return{error}}}};
 const storage={upload:async(p,b)=>{if(uploadFail)throw Error('upload');objects.set(p,Buffer.from(b));},download:async p=>{if(!objects.has(p))throw Error('missing');return objects.get(p);},remove:async paths=>{if(deleteFail)throw Error('delete');paths.forEach(p=>objects.delete(p));}};
 const app=express();app.use(express.json());registerReceiptWiz(app,{database,storage,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization,tier:'basic',credits:0}:null,scanReceipt:async()=>{scanCalls++;if(scanGate)await scanGate;if(scanFail)throw Error('provider');return details();}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/receipt-wiz';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();await db.query('insert into auth.users values($1),($2)',[owner,other]);await db.exec('set role service_role');objects.clear();scanCalls=0;scanFail=uploadFail=deleteFail=false;scanGate=null;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('basic zero-credit users upload and scan free; originals and duplicate identity are preserved',async()=>{
 const a=await upload(),r=a.receipt;assert.equal(r.state,'ready');assert.equal(r.upload_token,undefined);assert.equal(a.object_path,undefined);
 const duplicate=await upload({status:200});assert.equal(duplicate.receipt.id,r.id);assert.equal(duplicate.reused,true);
 const req={confirmed:true,request_key:randomUUID()};const scan=await api('/'+r.id+'/scan',req);assert.equal(scan.receipt.details.category,'Office supplies');assert.equal(scanCalls,1);await api('/'+r.id+'/scan',req);assert.equal(scanCalls,1);
 const list=await api();assert.equal(list.credit_cost,0);assert.equal(list.scans_today,1);assert.equal(list.total,1);
 const original=await fetch(base+'/'+r.id+'/file',{headers:{Authorization:owner}});assert.deepEqual(Buffer.from(await original.arrayBuffer()),bytes);assert.equal(original.headers.get('x-content-type-options'),'nosniff');
});
test('all private paths reject unauthenticated and cross-owner requests',async()=>{
 const r=(await upload()).receipt;await api('',null,'GET','',401);await upload({actor:'',status:401});
 for(const path of ['/'+r.id,'/'+r.id+'/file','/'+r.id+'/preview'])await api(path,null,'GET',other,404);
 await api('/'+r.id,{version:1,details:details(),reviewed:true},'PUT',other,404);await api('/'+r.id+'/scan',{confirmed:true,request_key:randomUUID()},'POST',other,404);await api('/'+r.id,{confirmed:true},'DELETE',other,404);assert.equal(scanCalls,0);assert.equal((await api('',null,'GET',other)).total,0);
});
test('invalid file content and mismatched request reuse cannot create extra objects',async()=>{
 await upload({buffer:Buffer.from('<svg/>'),status:400});await upload({buffer:Buffer.alloc(8*1024*1024+1),status:400});assert.equal(objects.size,0);
 const key=randomUUID();await upload({key});await upload({key,status:200});await upload({key,buffer:await sharp(bytes).negate().png().toBuffer(),status:409});assert.equal(objects.size,2);
});
test('interrupted uploads and deletions remain visible and recoverable',async()=>{
 uploadFail=true;await upload({status:503});const pending=(await api()).receipts[0];assert.equal(pending.state,'uploading');await upload({status:202});await db.query("update korlix_receipt_wiz set upload_until=now()-interval '1 minute' where id=$1",[pending.id]);uploadFail=false;assert.equal((await upload()).receipt.id,pending.id);
 deleteFail=true;await api('/'+pending.id,{confirmed:true},'DELETE',owner,503);assert.equal((await api()).receipts[0].state,'deleting');deleteFail=false;await api('/'+pending.id,{confirmed:true},'DELETE');assert.equal((await api()).total,0);assert.equal(objects.size,0);
});
test('finance inboxes see the same owner receipt and corrections without duplicate copies',async()=>{
 await db.exec('reset role');const business=randomUUID(),tax=randomUUID(),foreign=randomUUID();await db.query('insert into korlix_bookkeeping_businesses values($1,$2,$3),($4,$5,$6)',[business,owner,'My business',foreign,other,'Other business']);await db.query('insert into korlix_tax_workspaces values($1,$2,2026)',[tax,owner]);await db.exec('set role service_role');
 const a=await upload();assert.equal(a.integrations.bookkeeping[0].id,business);assert.equal(a.integrations.tax_prep[0].id,tax);
 const id=a.receipt.id;await api('/'+id,{version:1,reviewed:true,details:details()},'PUT');
 assert.equal((await api('?business_id='+business)).receipts[0].details.description,'Printer paper');assert.equal((await api('?tax_workspace_id='+tax+'&year=2026')).receipts[0].id,id);assert.equal((await api('?year=2025')).total,0);
 await api('?business_id='+foreign,null,'GET',owner,404);await api('?tax_workspace_id='+tax,null,'GET',other,404);
 const edited={...details(),description:'Paper for client project',category:'Other'};await api('/'+id,{version:2,reviewed:true,details:edited},'PUT');assert.equal((await api('?business_id='+business+'&query=client')).receipts[0].details.description,edited.description);assert.equal(objects.size,2);
});
test('scan failure preserves original; late scan never overwrites a user correction',async()=>{
 const id=(await upload()).receipt.id;scanFail=true;await api('/'+id+'/scan',{confirmed:true,request_key:randomUUID()},'POST',owner,503);assert.equal((await api('/'+id)).receipt.scan.state,'failed');assert.equal(objects.size,2);
 const started=await rpc('scan_begin',id,{request_key:randomUUID()});const saved=await api('/'+id,{version:1,reviewed:true,details:{...details(),merchant:'Corrected merchant'}},'PUT');assert.equal(saved.receipt.version,2);
 await rpc('scan_finish',id,{scan_id:started.scan_id,details:details()});assert.equal((await api('/'+id)).receipt.details.merchant,'Corrected merchant');
 await api('/'+id,{version:1,reviewed:true,details:details()},'PUT',owner,409);
});
test('free daily limit survives deletion and stale scans recover',async()=>{
 const id=(await upload()).receipt.id;const started=await rpc('scan_begin',id,{request_key:randomUUID()});await api('/'+id+'/scan',{confirmed:true,request_key:randomUUID()},'POST',owner,409);await db.query("update korlix_receipt_wiz_scans set created_at=now()-interval '4 minutes' where id=$1",[started.scan_id]);assert.equal((await api('/'+id)).receipt.scan.state,'expired');scanFail=false;await api('/'+id+'/scan',{confirmed:true,request_key:randomUUID()});assert.equal((await api()).scans_today,2);await api('/'+id,{confirmed:true},'DELETE');assert.equal((await api()).scans_today,2);
 const next=(await upload()).receipt.id;await db.query('update korlix_receipt_wiz_usage set attempts=100 where owner_id=$1',[owner]);await api('/'+next+'/scan',{confirmed:true,request_key:randomUUID()},'POST',owner,429);await api('/'+next,{version:1,reviewed:true,details:details()},'PUT');
});
test('search filters, unknown dates, CSV and possible duplicate warnings keep review honest',async()=>{
 const a=(await upload()).receipt;await api('/'+a.id,{version:1,reviewed:true,details:details()},'PUT');
 const b=(await upload({buffer:await sharp(bytes).negate().png().toBuffer()})).receipt;const saved=await api('/'+b.id,{version:1,reviewed:false,details:{...details(),total:'18.5'}},'PUT');assert.equal(saved.possible_duplicate,true);assert.equal((await api('?needs_review=true')).total,1);assert.equal((await api('?category=Fuel%20%26%20transport')).total,0);
 const exported=await api('/export');assert.equal(exported.count,2);assert.match(exported.csv,/Printer paper/);assert.match(csvExport([{id:'x',details:{merchant:'=NOW()'}}]),/'=NOW/);
});
test('database roles cannot bypass API ownership or private storage restrictions',async()=>{
 for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(db.query('select * from public.korlix_receipt_wiz'),/permission denied/);await assert.rejects(db.query("select korlix_receipt_wiz_v1($1,'list')",[owner]),/permission denied/);await assert.rejects(db.query("insert into storage.objects values('x','korlix-receipt-wiz')"),/row-level security/);}
 await db.exec('reset role');assert.equal((await db.query("select public from storage.buckets where id='korlix-receipt-wiz'")).rows[0].public,false);
});
test('OCR rejects malformed amounts and ignores document instructions; no tools or response storage',async()=>{
 for(const value of ['NaN','-12','1e3','12.345'])assert.throws(()=>receiptDetails({...details(),total:value}));assert.throws(()=>receiptDetails({...details(),date:'2026-02-31'}));
 let request;const d=await scanReceiptWiz({client:{},model:'fixture',receipt:{mime_type:'image/png'},bytes,createResponse:async(c,r)=>{request=r;return{status:'completed',output_text:JSON.stringify(details())}}});assert.equal(d.category,'Office supplies');assert.equal(request.store,false);assert.equal(request.tools,undefined);assert.match(request.input[0].content[0].text,/untrusted/);assert.equal(request.text.format.strict,true);
});
