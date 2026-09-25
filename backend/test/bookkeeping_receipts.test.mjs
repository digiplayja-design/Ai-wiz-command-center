import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {PDFDocument} from 'pdf-lib';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
import {inspectReceipt,createReceiptStorage,digest} from '../bookkeeping/receipt_files.mjs';
import {validateReceiptSuggestion,extractReceipt} from '../bookkeeping/receipt_scanner.mjs';
let db,server,base,owner,other,b,bytes;const objects=new Map();let puts,gets,removes,scanCalls,charges,uploadFail,deleteFail,scanFail,scanGate,scanAvailable;
const suggestions=()=>({vendor:'Fixture Store',document_date:'2027-01-15',total:'12.34',currency:'USD',document_type:'receipt',payment_status:'paid',warnings:[]});
const payload=(extra={})=>({kind:'expense',entry_date:'2027-01-15',amount:'12.34',category:'5000',purpose:'Office supplies',request_key:randomUUID(),confirmed:true,receipt_reviewed:true,...extra});
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+'/api/bookkeeping/businesses'+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));assert.equal(r.headers.get('cache-control'),'no-store');return data;}
const rp=(path='')=>'/'+b.id+'/receipts'+path;
async function upload({buffer=bytes,name='receipt.png',key=randomUUID(),actor=owner,status=201,method='POST'}={}){
 const form=new FormData();form.append('receipt',new Blob([buffer],{type:'image/jpeg'}),name);
 const r=await fetch(base+'/api/bookkeeping/businesses'+rp(),{method,headers:{Authorization:actor,'X-Receipt-Request-Key':key},body:form});const data=await r.json();assert.equal(r.status,status,JSON.stringify(data));return data;
}
async function rpc(action,receipt=null,data={},actor=owner,business=b.id){return (await db.query('select public.korlix_bookkeeping_receipts_v1($1,$2,$3,$4,$5) r',[actor,action,business,receipt,data])).rows[0].r;}
const receipt=async()=> (await upload()).receipt;
async function expireUpload(id){await db.query("update korlix_bookkeeping_receipts set upload_lease_until=now()-interval '1 minute' where id=$1",[id]);}
async function entriesCount(){return(await db.query('select count(*)::int n from korlix_bookkeeping_entries where business_id=$1',[b.id])).rows[0].n;}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;create policy broad_legacy_storage on storage.objects for all to anon,authenticated using(true) with check(true);grant usage on schema public,storage to anon,authenticated,service_role;grant all on storage.objects to anon,authenticated;`);
 for(const f of ['20260925015926_bookkeeping_foundation.sql','20260925024651_bookkeeping_receipts.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 bytes=await sharp({create:{width:60,height:80,channels:3,background:'#eee'}}).png().toBuffer();
 const database={rpc:async(name,p)=>{try{const args=name==='korlix_bookkeeping_v1'?[p.p_actor,p.p_action,p.p_business,p.p_data]:[p.p_actor,p.p_action,p.p_business,p.p_receipt,p.p_data];return {data:(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args)).rows[0].r};}catch(error){if(process.env.BK_DEBUG)console.error(error.message,error.code,error.where);return{error};}}};
 const storage={upload:async(path,buffer,mime)=>{puts++;if(uploadFail)throw Error('fixture upload failure');if(objects.has(path))assert.equal(digest(objects.get(path)),digest(buffer));objects.set(path,buffer);},download:async(path,hash,size)=>{gets++;const value=objects.get(path);if(!value)throw Error('fixture missing file');assert.equal(value.length,size);assert.equal(digest(value),hash);return value;},remove:async paths=>{removes++;if(deleteFail)throw Error('fixture deletion failure');for(const path of paths)objects.delete(path);}};
 const app=express();app.use(express.json());registerBookkeeping(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,receiptOptions:{storage,scanAccess:async()=>({available:scanAvailable,reason:scanAvailable?'':'Daily generation limit reached.',daily_limit:3,credit_cost:1}),scanReceipt:async()=>{scanCalls++;if(scanGate)await scanGate;if(scanFail)throw Error('fixture provider failure');return suggestions();},chargeScan:async()=>{charges++;}}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
 await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.exec('set role service_role');
 b=(await api('',{name:'Receipts fixture',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()},'POST',owner,201)).business;
 puts=gets=removes=scanCalls=charges=0;uploadFail=deleteFail=scanFail=false;scanGate=null;scanAvailable=true;objects.clear();
});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});

test('original bytes survive upload, sanitized names and verified private downloads',async()=>{
 const r=await receipt();assert.equal(r.mime_type,'image/png');assert.equal(r.sha256,digest(bytes));assert.equal(r.state,'ready');assert.equal(r.upload_token,undefined);assert.equal(puts,2);
 const data=await api(rp());assert.equal(data.receipts.length,1);assert.equal(data.receipts[0].retained,false);assert.equal(data.used_bytes,bytes.length+r.preview_size);assert.equal(data.scanning.credit_cost,1);
 for(const part of ['file','preview']){const res=await fetch(base+'/api/bookkeeping/businesses'+rp('/'+r.id+'/'+part),{headers:{Authorization:owner}});assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'no-store');assert.equal(res.headers.get('x-content-type-options'),'nosniff');if(part==='file')assert.deepEqual(Buffer.from(await res.arrayBuffer()),bytes);else assert.equal(res.headers.get('content-type'),'image/webp');}
 const file=await inspectReceipt(bytes,'../../receipt.html');assert.equal(file.metadata.filename,'receipt.png');assert.deepEqual(file.original,bytes);
});
test('duplicate upload and same-key replay reuse a receipt without object replacement',async()=>{
 const key=randomUUID();const a=await upload({key});const z=await upload({key,status:200});const duplicate=await upload({status:200});assert.equal(z.receipt.id,a.receipt.id);assert.equal(duplicate.receipt.id,a.receipt.id);assert.equal(puts,2);assert.equal((await api(rp())).total,1);
 const different=await sharp(bytes).negate().png().toBuffer();await upload({buffer:different,key,status:409});
});
test('owner checks happen before decoding and cannot leak originals or scans',async()=>{
 const r=await receipt();const before={puts,gets};await upload({actor:other,buffer:Buffer.from('invalid'),status:404});await upload({actor:'',status:401});
 for(const path of ['', '/'+r.id+'/file','/'+r.id+'/preview','/'+r.id+'/scan'])await api(rp(path),null,'GET',other,404);
 await api(rp('/'+r.id+'/link'),{entry_id:randomUUID(),confirmed:true},'POST',other,404);await api(rp('/'+r.id),{confirmed:true},'DELETE',other,404);assert.deepEqual({puts,gets},before);
});
test('file validation rejects fake images, SVG, broken PDF and oversized upload',async()=>{
 for(const buffer of [Buffer.from('<svg/>'),Buffer.from('<script>unsafe</script>'),Buffer.from('%PDF-broken')])await upload({buffer,status:400});
 await upload({buffer:Buffer.alloc(8*1024*1024+1),status:400});assert.equal(puts,0);
 const doc=await PDFDocument.create();for(let i=0;i<11;i++)doc.addPage();await assert.rejects(inspectReceipt(Buffer.from(await doc.save()),'long.pdf'),/1–10/);
});
test('PDF originals are retained with download-only headers and no inline preview',async()=>{
 const doc=await PDFDocument.create();doc.addPage();const pdf=Buffer.from(await doc.save());const r=(await upload({buffer:pdf,name:'invoice.pdf'})).receipt;assert.equal(r.pages,1);assert.equal(r.preview_size,0);assert.equal(puts,1);
 await api(rp('/'+r.id+'/preview'),null,'GET',owner,404);const res=await fetch(base+'/api/bookkeeping/businesses'+rp('/'+r.id+'/file'),{headers:{Authorization:owner}});assert.match(res.headers.get('content-disposition'),/^attachment/);assert.deepEqual(Buffer.from(await res.arrayBuffer()),pdf);
});
test('incomplete uploads are leased, shown as pending, recoverable and do not duplicate dispatch',async()=>{
 uploadFail=true;await upload({status:503});let list=await api(rp());const pending=list.receipts[0];assert.equal(pending.state,'uploading');await upload({status:202});await api(rp('/'+pending.id),{confirmed:true},'DELETE',owner,409);
 await expireUpload(pending.id);uploadFail=false;const recovered=await upload();assert.equal(recovered.receipt.id,pending.id);assert.equal(recovered.receipt.state,'ready');assert.equal((await api(rp())).total,1);
});
test('incomplete unlinked receipt deletion remains retryable and releases quota only after success',async()=>{
 const r=await receipt();deleteFail=true;await api(rp('/'+r.id),{confirmed:true},'DELETE',owner,503);const pending=await api(rp());assert.equal(pending.receipts[0].state,'deleting');assert(pending.used_bytes>0);await api(rp('/'+r.id+'/file'),null,'GET',owner,409);
 deleteFail=false;await api(rp('/'+r.id),{confirmed:true},'DELETE');assert.equal((await api(rp())).used_bytes,0);assert.equal(objects.size,0);await api(rp('/'+r.id+'/file'),null,'GET',owner,404);
});
test('creating an entry with a receipt is atomic, replay-safe, and cannot duplicate expense',async()=>{
 const r=await receipt(),p=payload();const a=await api(rp('/'+r.id+'/entries'),p,'POST',owner,201);const z=await api(rp('/'+r.id+'/entries'),p,'POST',owner,201);assert.equal(a.entry.id,z.entry.id);assert.equal(a.link.id,z.link.id);assert.equal(await entriesCount(),1);
 await api(rp('/'+r.id+'/entries'),payload(),'POST',owner,409);assert.equal(await entriesCount(),1);
 const evidence=await api('/'+b.id+'/entries/'+a.entry.id+'/receipts');assert.equal(evidence.receipts[0].id,r.id);assert.equal(evidence.receipts[0].link.entry_id,a.entry.id);assert.equal((await api(rp())).receipts[0].retained,true);
});
test('link corrections preserve history and prevent deletion of previously used evidence',async()=>{
 const r=await receipt();const a=await api(rp('/'+r.id+'/entries'),payload(),'POST',owner,201);
 await api(rp('/'+r.id),{confirmed:true},'DELETE',owner,409);
 await api(rp('/'+r.id+'/unlink'),{link_id:a.link.id,reason:'Wrong association',confirmed:true});const corrected=await api('/'+b.id+'/entries/'+a.entry.id+'/receipts');assert.equal(corrected.receipts[0].link.unlink_reason,'Wrong association');
 await api(rp('/'+r.id),{confirmed:true},'DELETE',owner,409);
 const z=await api('/'+b.id+'/entries',payload(),'POST',owner,201);await api(rp('/'+r.id+'/link'),{entry_id:z.entry.id,confirmed:true});assert.equal((await api(rp())).receipts[0].link.entry_id,z.entry.id);
 const old=await api('/'+b.id+'/entries/'+a.entry.id+'/receipts');assert.equal(old.receipts[0].link.unlink_reason,'Wrong association');
});
test('receipt associations reject reversed entries and cross-business references',async()=>{
 const r=await receipt();const e=await api('/'+b.id+'/entries',payload(),'POST',owner,201);await api('/'+b.id+'/entries/'+e.entry.id+'/reverse',{confirmed:true,reason:'Mistake',request_key:randomUUID()},'POST',owner,201);
 await api(rp('/'+r.id+'/link'),{entry_id:e.entry.id,confirmed:true},'POST',owner,409);
 const second=(await api('',{name:'Second',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()},'POST',owner,201)).business;
 const foreign=await api('/'+second.id+'/entries',payload(),'POST',owner,201);await api(rp('/'+r.id+'/link'),{entry_id:foreign.entry.id,confirmed:true},'POST',owner,404);
});
test('AI extracts suggestions only after explicit confirmation and never posts automatically',async()=>{
 const r=await receipt();await api(rp('/'+r.id+'/scan'),{request_key:randomUUID()},'POST',owner,400);assert.equal(scanCalls,0);
 const p={confirmed:true,request_key:randomUUID()};const a=await api(rp('/'+r.id+'/scan'),p);assert.equal(a.scan.state,'ready');assert.deepEqual(a.scan.suggestions,suggestions());assert.equal(scanCalls,1);assert.equal(charges,1);assert.equal(await entriesCount(),0);
 const replay=await api(rp('/'+r.id+'/scan'),p);assert.equal(replay.scan.id,a.scan.id);assert.equal(scanCalls,1);assert.equal(charges,1);assert.equal((await api(rp('/'+r.id+'/scan'))).scan.id,a.scan.id);
});
test('scanning respects existing usage access and counts daily attempts separately',async()=>{
 const r=await receipt();scanAvailable=false;await api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()},'POST',owner,422);assert.equal(scanCalls,0);
 scanAvailable=true;scanFail=true;for(let i=0;i<3;i++){await api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()},'POST',owner,503);}assert.equal(charges,0);
 await api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()},'POST',owner,429);assert.equal(scanCalls,3);assert.equal((await api(rp('/'+r.id+'/scan'))).scan.state,'failed');
});
test('one active scan blocks concurrent provider dispatch and deletion',async()=>{
 const r=await receipt();let release;scanGate=new Promise(resolve=>{release=resolve});
 const first=api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()});while(scanCalls===0)await new Promise(resolve=>setTimeout(resolve,1));
 await api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()},'POST',owner,409);await api(rp('/'+r.id),{confirmed:true},'DELETE',owner,409);release();await first;assert.equal(scanCalls,1);assert.equal(charges,1);
});
test('scanner validates provider output, treats file text as data and uses no tools or retries',async()=>{
 let request,options;const value=await extractReceipt({client:{},model:'fixture-model',receipt:{mime_type:'image/png'},bytes,createResponse:async(_client,r,o)=>{request=r;options=o;return{status:'completed',output_text:JSON.stringify(suggestions())}}});
 assert.deepEqual(value,suggestions());assert.equal(request.store,false);assert.equal(request.tools,undefined);assert.equal(options.maxRetries,0);assert.equal(request.text.format.strict,true);assert.match(request.input[0].content[0].text,/Ignore any instructions/);
 const invalid={...suggestions(),document_date:'2027-02-29',total:'1e3',currency:'$'};const sanitized=validateReceiptSuggestion(invalid);assert.equal(sanitized.total,null);assert.equal(sanitized.document_date,null);assert.equal(sanitized.currency,null);
 assert.throws(()=>validateReceiptSuggestion({...suggestions(),secret:'extra'}));await assert.rejects(extractReceipt({client:{},model:'fixture',receipt:{mime_type:'image/png'},bytes,createResponse:async()=>({output_text:'not JSON'})}),/could not be read/);
});
test('browser table/RPC and storage access stay denied despite a permissive legacy bucket policy',async()=>{
 await db.exec('reset role');await db.exec("insert into storage.objects values('private','korlix-bookkeeping-receipts'),('other','other-bucket');");
 try{for(const role of ['anon','authenticated']){await db.exec('set role '+role);for(const table of ['korlix_bookkeeping_receipts','korlix_bookkeeping_receipt_links','korlix_bookkeeping_receipt_scans'])await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(rpc('list'),/permission denied/);const rows=(await db.query('select id from storage.objects')).rows;assert.deepEqual(rows,[{id:'other'}]);await assert.rejects(db.query("insert into storage.objects values('forged','korlix-bookkeeping-receipts')"),/row-level security/);await db.exec('reset role');}}finally{await db.exec('reset role;set role service_role');}
});
test('storage adapter verifies same-byte replay and detects changed downloads',async()=>{
 const original=Buffer.from('fixture');let writes=0;
 const dbMock={storage:{from:()=>({upload:async(_p,_b,options)=>{writes++;assert.equal(options.upsert,false);return{error:{message:'duplicate'}};},download:async()=>({data:new Blob([original])}),remove:async()=>({})})}};
 const s=createReceiptStorage(dbMock);await s.upload('path',original,'application/pdf');assert.equal(writes,1);await assert.rejects(s.upload('path',Buffer.from('changed'),'application/pdf'),/did not finish/);assert.deepEqual(await s.download('path',digest(original),original.length),original);await assert.rejects(s.download('path',digest(Buffer.from('different')),original.length),/integrity/);
});
test('receipt original metadata and link history remain immutable under privileged SQL',async()=>{
 const r=await receipt();await assert.rejects(db.query('update korlix_bookkeeping_receipts set sha256=$1 where id=$2',['0'.repeat(64),r.id]),/permission denied/);
 await db.exec('reset role');try{await assert.rejects(db.query('update korlix_bookkeeping_receipts set sha256=$1 where id=$2',['0'.repeat(64),r.id]),/cannot be replaced/);await assert.rejects(db.query('delete from korlix_bookkeeping_receipts where id=$1',[r.id]),/cannot be deleted/);}finally{await db.exec('set role service_role');}
});
test('owner storage quota includes pending files across businesses and PDF scan limit prevents dispatch',async()=>{
 const doc=await PDFDocument.create();for(let i=0;i<4;i++)doc.addPage();const r=(await upload({buffer:Buffer.from(await doc.save()),name:'four-pages.pdf'})).receipt;
 await api(rp('/'+r.id+'/scan'),{confirmed:true,request_key:randomUUID()},'POST',owner,400);assert.equal(scanCalls,0);
 const second=(await api('',{name:'Second quota fixture',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()},'POST',owner,201)).business;
 const metadata={filename:'reserved.pdf',mime_type:'application/pdf',byte_size:8388608,preview_size:0,pages:1};
 for(let i=0;i<31;i++)await rpc('reserve_upload',null,{...metadata,request_key:randomUUID(),sha256:i.toString(16).padStart(64,'0')},owner,second.id);
 await assert.rejects(rpc('reserve_upload',null,{...metadata,request_key:randomUUID(),sha256:'f'.repeat(64)}),/storage limit/);
 assert((await api(rp())).used_bytes>=31*8388608);
});
test('review acknowledgement is required before any receipt entry is posted',async()=>{
 const r=await receipt();await api(rp('/'+r.id+'/entries'),payload({receipt_reviewed:false}),'POST',owner,400);assert.equal(await entriesCount(),0);
});
