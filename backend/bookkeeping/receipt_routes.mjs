import multer from 'multer';
import {BookkeepingError,fail,id,entry} from './core.mjs';
import {MAX_FILE,inspectReceipt,createReceiptStorage} from './receipt_files.mjs';
const parse=multer({storage:multer.memoryStorage(),limits:{fileSize:MAX_FILE,files:1,fields:0,parts:2}}).single('receipt');
export function registerReceiptRoutes(app,{route,database,storageDatabase=database,storage:providedStorage,scanAccess,scanReceipt,chargeScan}={}){
 const storage=providedStorage??(storageDatabase?.storage?createReceiptStorage(storageDatabase):null);
 const call=async(actor,action,business,receipt=null,data={})=>{
  const r=await database.rpc('korlix_bookkeeping_receipts_v1',{p_actor:actor,p_action:action,p_business:business,p_receipt:receipt,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'23505':409,'42501':403,'54000':429,P0001:400,'23514':400,'23502':400,'22P02':400}[r.error.code]??503;const safe=['P0001','P0002','40001','54000'].includes(r.error.code);fail(safe?r.error.message:'Receipt storage could not complete this request. Refresh before retrying.',status,'BOOKKEEPING_RECEIPT_ERROR');}
  return r.data;
 };
 const base='/api/bookkeeping/businesses/:id/receipts';let pendingUploads=0,pendingScans=0;
 const running=new Set();
 const available=()=>{if(!storage)fail('Receipt storage is not configured.',503);};
 const receiptId=q=>id(q.params.receipt);
 const businessId=q=>id(q.params.id);
 const access=async user=>scanAccess?scanAccess(user):{available:false,reason:'AI scanning is not configured.',daily_limit:0,credit_cost:1};
 app.get(base,route(async(q,r,u,user)=>{
  const offset=String(q.query.offset??'0');if(!/^\d{1,5}$/.test(offset)||Number(offset)>10000)fail('Invalid receipt page.');
  const result=await call(u,'list',businessId(q),null,{offset:Number(offset)});
  r.json({...result,scanning:await access(user)});
 }));
 app.post(base,route(async(q,r,u)=>{
  const business=businessId(q),key=id(q.get('X-Receipt-Request-Key'));
  available();await call(u,'list',business); // Ownership before multipart parsing.
  if(pendingUploads>=2)fail('Receipt uploads are busy. Try again shortly.',429);
  pendingUploads++;
  try{
   await new Promise((resolve,reject)=>parse(q,r,error=>error?reject(error):resolve()));
   if(!q.file)fail('Choose one receipt file.');
   const file=await inspectReceipt(q.file.buffer,q.file.originalname);
   const reserved=await call(u,'reserve_upload',business,null,{...file.metadata,request_key:key});
   if(!reserved.dispatch){r.status(reserved.receipt.state==='ready'?200:202).json({receipt:reserved.receipt,reused:true});return;}
   if(reserved.receipt.preview_sha256!==file.metadata.preview_sha256)fail('This upload needs its original preview. Wait for the upload lease to expire, delete the incomplete upload, then upload again.',409);
   await storage.upload(reserved.object_path,file.original,reserved.receipt.mime_type);
   if(file.preview)await storage.upload(reserved.preview_path,file.preview,'image/webp');
   const ready=await call(u,'ready',business,reserved.receipt.id,{upload_token:reserved.upload_token});
   r.status(201).json({receipt:ready.receipt,reused:false});
  }catch(e){if(e instanceof multer.MulterError)fail(e.code==='LIMIT_FILE_SIZE'?'Choose a receipt up to 8 MB.':'Upload one receipt at a time.');throw e;}
  finally{pendingUploads--;q.file=undefined;}
 }));
 for(const preview of [false,true])app.get(base+'/:receipt/'+(preview?'preview':'file'),route(async(q,r,u)=>{
  available();const data=await call(u,'get',businessId(q),receiptId(q));const rec=data.receipt;
  if(rec.state!=='ready')fail('This receipt is not ready. Refresh its status.',409);
  if(preview&&!rec.preview_size)fail('This PDF has no image preview. Download the original to view it.',404);
  const bytes=await storage.download(preview?data.preview_path:data.object_path,preview?rec.preview_sha256:rec.sha256,preview?rec.preview_size:rec.byte_size);
  r.set({'Content-Type':preview?'image/webp':rec.mime_type,'Content-Disposition':preview?'inline':`attachment; filename="receipt.${rec.mime_type==='application/pdf'?'pdf':rec.mime_type.split('/')[1]}"`,'X-Content-Type-Options':'nosniff','Cross-Origin-Resource-Policy':'same-origin','Content-Security-Policy':"sandbox; default-src 'none'",'X-Robots-Tag':'noindex, nofollow'});r.send(bytes);
 }));
 app.delete(base+'/:receipt',route(async(q,r,u)=>{
  available();const b=businessId(q),rid=receiptId(q);if(q.body?.confirmed!==true)fail('Confirm receipt deletion.');
  const paths=await call(u,'begin_delete',b,rid,{confirmed:true});
  await storage.remove([paths.object_path,paths.preview_path].filter(Boolean));
  r.json(await call(u,'finish_delete',b,rid,{confirmed:true}));
 }));
 app.post(base+'/:receipt/link',route(async(q,r,u)=>{
  if(q.body?.confirmed!==true)fail('Review and confirm receipt attachment.');
  r.json(await call(u,'link',businessId(q),receiptId(q),{entry_id:id(q.body.entry_id),confirmed:true}));
 }));
 app.post(base+'/:receipt/unlink',route(async(q,r,u)=>{
  if(q.body?.confirmed!==true||typeof q.body.reason!=='string'||!q.body.reason.trim()||q.body.reason.length>500)fail('Enter a reason and confirm correcting the receipt link.');
  r.json(await call(u,'unlink',businessId(q),receiptId(q),{link_id:id(q.body.link_id),reason:q.body.reason.trim(),confirmed:true}));
 }));
 app.post(base+'/:receipt/entries',route(async(q,r,u)=>{
  if(q.body?.receipt_reviewed!==true)fail('Verify the receipt amount, currency and payment date first.');
  const payload=entry(q.body);r.status(201).json(await call(u,'post_entry',businessId(q),receiptId(q),{entry:payload,confirmed:true}));
 }));
 app.get('/api/bookkeeping/businesses/:id/entries/:entry/receipts',route(async(q,r,u)=>r.json(await call(u,'entry_receipts',businessId(q),null,{entry_id:id(q.params.entry)}))));
 app.get(base+'/:receipt/scan',route(async(q,r,u)=>r.json(await call(u,'scan_status',businessId(q),receiptId(q)))));
 app.post(base+'/:receipt/scan',route(async(q,r,u,user)=>{
  const b=businessId(q),rid=receiptId(q),key=id(q.body?.request_key);
  if(q.body?.confirmed!==true)fail('Confirm AI scanning.');
  available();const file=await call(u,'get',b,rid);if(file.receipt.state!=='ready')fail('Finish uploading the receipt first.',409);
  const eligibility=await access(user);if(!eligibility.available||!scanReceipt||!chargeScan)fail(eligibility.reason||'AI scanning is not available.',422,'BOOKKEEPING_SCAN_UNAVAILABLE');
  if(pendingScans>=2||running.has(u))fail('A receipt scan is running. Refresh its status shortly.',409);
  pendingScans++;running.add(u);
  let scan;
  try{
   // Validate stored bytes before reserving an AI attempt. No provider call on a
   // missing/tampered file, denied owner or exhausted current usage budget.
   const bytes=await storage.download(file.object_path,file.receipt.sha256,file.receipt.byte_size);
   const claim=await call(u,'scan_begin',b,rid,{request_key:key,confirmed:true,daily_limit:eligibility.daily_limit});
   scan=claim.scan;if(!claim.dispatch){r.json({scan});return;}
   const suggestions=await scanReceipt({user,receipt:file.receipt,bytes});
   await chargeScan(user); // Existing daily generation/credit accounting, once per dispatch.
   const finished=await call(u,'scan_finish',b,rid,{scan_id:scan.id,suggestions});
   r.json(finished);
  }catch(e){
   if(scan?.state==='scanning'){try{await call(u,'scan_fail',b,rid,{scan_id:scan.id});}catch{/* Preserve pending state if persistence is unavailable. */}}
   if(e instanceof BookkeepingError)throw e;
   fail('AI scanning did not finish. Refresh its status, then retry explicitly or enter the details manually.',503,'BOOKKEEPING_SCAN_FAILED');
  }finally{pendingScans--;running.delete(u);}
 }));
}
