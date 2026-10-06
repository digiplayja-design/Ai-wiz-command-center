import multer from 'multer';
import {BookkeepingError,fail,id} from '../bookkeeping/core.mjs';
import {MAX_FILE,inspectReceipt,createReceiptStorage} from '../bookkeeping/receipt_files.mjs';
import {CATEGORIES,receiptDetails,csvExport} from './core.mjs';
const parse=multer({storage:multer.memoryStorage(),limits:{fileSize:MAX_FILE,files:1,fields:0,parts:2}}).single('receipt');
const present=data=>({receipt:data.receipt,integrations:data.integrations,...(data.possible_duplicate!==undefined?{possible_duplicate:data.possible_duplicate}:{})});
export function registerReceiptWiz(app,{database,storageDatabase=database,storage:providedStorage,requireUser,scanReceipt}={}){
 const storage=providedStorage??(storageDatabase?.storage?createReceiptStorage(storageDatabase,'korlix-receipt-wiz'):null);
 let uploads=0,scans=0;
 const call=async(actor,action,rid=null,data={})=>{
  const r=await database.rpc('korlix_receipt_wiz_v1',{p_actor:actor,p_action:action,p_id:rid,p_data:data});
  if(r.error){const e=r.error;fail(['P0001','P0002','40001','54000'].includes(e.code)?e.message:'The receipt vault could not complete this request. Refresh and retry.',{P0001:400,P0002:404,'40001':409,'42501':403,'54000':429,'23505':409,'22P02':400}[e.code]??503,'RECEIPT_WIZ_STORAGE');}
  if(!r.data)fail('The receipt vault returned no result.',503);return r.data;
 };
 const route=fn=>async(q,r)=>{
  r.set('Cache-Control','no-store');
  try{
   let user;try{user=await requireUser(q);}catch{fail('Sign in to use THE RECEIPT WIZ.',401);}
   if(!user?.id)fail('Sign in to use THE RECEIPT WIZ.',401);
   if(!database)fail('The receipt vault is temporarily unavailable.',503);
   await fn(q,r,user.id);
  }catch(e){r.status(e instanceof BookkeepingError?e.status:503).json({error:e instanceof BookkeepingError?e.message:'Receipt Wiz is temporarily unavailable. Refresh before retrying.',code:e instanceof BookkeepingError?e.code:'RECEIPT_WIZ_UNAVAILABLE'});}
 };
 const filters=q=>{
  const d={};for(const key of ['query','category','year','offset'])if(q.query[key]!==undefined){if(typeof q.query[key]!=='string')fail('Check receipt filters.');d[key]=q.query[key];}
  if(d.offset!==undefined&&!/^\d{1,4}$/.test(d.offset))fail('Check the receipt page.');
  if(d.category&&!CATEGORIES.includes(d.category))fail('Choose a receipt category.');
  if(q.query.needs_review==='true')d.needs_review=true;
  for(const key of ['business_id','tax_workspace_id'])if(q.query[key])d[key]=id(q.query[key]);
  return d;
 };
 const available=()=>{if(!storage)fail('Receipt file storage is temporarily unavailable.',503);};
 const base='/api/receipt-wiz';
 app.get(base,route(async(q,r,u)=>r.json({...await call(u,'list',null,filters(q)),categories:CATEGORIES,scanning_available:!!scanReceipt,credit_cost:0})));
 app.get(base+'/export',route(async(q,r,u)=>{const data=await call(u,'export',null,{...filters(q),offset:0});r.json({csv:csvExport(data.receipts),filename:'THE-RECEIPT-WIZ.csv',count:data.receipts.length});}));
 app.post(base,route(async(q,r,u)=>{
  available();const key=id(q.get('X-Receipt-Request-Key'));
  if(uploads>=2)fail('Receipt uploads are busy. Try again shortly.',429);uploads++;
  try{
   await new Promise((resolve,reject)=>parse(q,r,e=>e?reject(e):resolve()));if(!q.file)fail('Choose one receipt photo or PDF.');
   const file=await inspectReceipt(q.file.buffer,q.file.originalname);
   const reserved=await call(u,'reserve',null,{...file.metadata,request_key:key});
   if(!reserved.dispatch){r.status(reserved.receipt.state==='ready'?200:202).json({...present(reserved),reused:true});return;}
   if(reserved.receipt.preview_sha256!==file.metadata.preview_sha256)fail('Retry with the original file or remove the incomplete upload.',409);
   await storage.upload(reserved.object_path,file.original,reserved.receipt.mime_type);
   if(file.preview)await storage.upload(reserved.preview_path,file.preview,'image/webp');
   const ready=await call(u,'ready',reserved.receipt.id,{upload_token:reserved.upload_token});
   r.status(201).json({...present(ready),reused:false});
  }catch(e){if(e instanceof multer.MulterError)fail(e.code==='LIMIT_FILE_SIZE'?'Choose a receipt up to 8 MB.':'Upload one receipt at a time.');throw e;}
  finally{uploads--;q.file=undefined;}
 }));
 app.get(base+'/:id',route(async(q,r,u)=>r.json(present(await call(u,'get',id(q.params.id))))));
 app.put(base+'/:id',route(async(q,r,u)=>{
  const version=q.body?.version;if(!Number.isInteger(version)||version<1||typeof q.body?.reviewed!=='boolean')fail('Review the receipt and refresh its version.');
  const details=receiptDetails(q.body.details);
  if(q.body.reviewed&&['merchant','date','total','currency'].some(k=>!details[k]))fail('Add the merchant, date, total and currency, or save for later.');
  r.json(present(await call(u,'save',id(q.params.id),{version,reviewed:q.body.reviewed,details})));
 }));
 for(const preview of [false,true])app.get(base+'/:id/'+(preview?'preview':'file'),route(async(q,r,u)=>{
  available();const data=await call(u,'get',id(q.params.id));const rec=data.receipt;
  if(rec.state!=='ready')fail('Wait for the receipt to finish saving.',409);
  if(preview&&!rec.preview_size)fail('Download the PDF original to view it.',404);
  const bytes=await storage.download(preview?data.preview_path:data.object_path,preview?rec.preview_sha256:rec.sha256,preview?rec.preview_size:rec.byte_size);
  r.set({'Content-Type':preview?'image/webp':rec.mime_type,'Content-Disposition':preview?'inline':`attachment; filename="receipt.${rec.mime_type==='application/pdf'?'pdf':rec.mime_type.split('/')[1]}"`,'X-Content-Type-Options':'nosniff','Cross-Origin-Resource-Policy':'same-origin','Content-Security-Policy':"sandbox; default-src 'none'",'X-Robots-Tag':'noindex, nofollow'});r.send(bytes);
 }));
 app.post(base+'/:id/scan',route(async(q,r,u)=>{
  available();if(q.body?.confirmed!==true)fail('Allow receipt analysis before scanning.');
  const rid=id(q.params.id),request_key=id(q.body?.request_key);
  if(!scanReceipt)fail('Automatic reading is temporarily unavailable. You can save the receipt and add details.',503);
  if(scans>=2)fail('The scanner is busy. Your original is saved; try again shortly.',429);scans++;
  let started;
  try{
   started=await call(u,'scan_begin',rid,{request_key});
   if(!started.dispatch){r.json(present(started));return;}
   const rec=started.receipt;
   const bytes=await storage.download(rec.preview_size?started.preview_path:started.object_path,rec.preview_size?rec.preview_sha256:rec.sha256,rec.preview_size?rec.preview_size:rec.byte_size);
   const details=receiptDetails(await scanReceipt({receipt:{...rec,mime_type:rec.preview_size?'image/webp':rec.mime_type},bytes}),{ai:true});
   r.json(present(await call(u,'scan_finish',rid,{scan_id:started.scan_id,details})));
  }catch(e){if(started?.dispatch)await call(u,'scan_finish',rid,{scan_id:started.scan_id,failed:true}).catch(()=>{});throw e;}
  finally{scans--;}
 }));
 app.delete(base+'/:id',route(async(q,r,u)=>{
  available();if(q.body?.confirmed!==true)fail('Confirm removal from Receipt Wiz and connected inboxes.');
  const rid=id(q.params.id),data=await call(u,'delete_begin',rid,{confirmed:true});
  await storage.remove([data.object_path,data.preview_path].filter(Boolean));r.json(await call(u,'delete_finish',rid));
 }));
}
