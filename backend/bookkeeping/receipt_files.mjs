import {createHash} from 'node:crypto';
import {BookkeepingError,fail} from './core.mjs';
export const RECEIPT_BUCKET='korlix-bookkeeping-receipts',MAX_FILE=8*1024*1024;
export const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
export async function inspectReceipt(buffer,filename){
 if(!Buffer.isBuffer(buffer)||!buffer.length||buffer.length>MAX_FILE)fail('Choose one JPG, PNG, WebP or PDF up to 8 MB.');
 let mime,preview=null,pages=1;
 const png=buffer.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'));
 const jpeg=buffer[0]===255&&buffer[1]===216&&buffer[2]===255;
 const webp=buffer.toString('ascii',0,4)==='RIFF'&&buffer.toString('ascii',8,12)==='WEBP';
 try{
  if(buffer.toString('ascii',0,5)==='%PDF-'){
   const {PDFDocument}=await import('pdf-lib');
   const document=await PDFDocument.load(buffer,{ignoreEncryption:false,updateMetadata:false});
   pages=document.getPageCount();if(pages<1||pages>10)fail('Choose a PDF with 1–10 pages.');
   mime='application/pdf';
  }else if(png||jpeg||webp){
   const {default:sharp}=await import('sharp');
   const image=sharp(buffer,{limitInputPixels:24000000,failOn:'warning',animated:false});
   const meta=await image.metadata();
   if(!['jpeg','png','webp'].includes(meta.format)||(meta.pages??1)!==1)fail('Choose a still JPG, PNG or WebP image.');
   mime={jpeg:'image/jpeg',png:'image/png',webp:'image/webp'}[meta.format];
   preview=await image.rotate().resize({width:2000,height:2000,fit:'inside',withoutEnlargement:true}).webp({quality:85}).timeout({seconds:10}).toBuffer();
   if(preview.length>1048576)fail('This image is too detailed. Use a smaller photo of the receipt.');
  }else fail('Unsupported file. Choose JPG, PNG, WebP or PDF.');
 }catch(e){if(e instanceof BookkeepingError)throw e;fail('This file could not be read. Use a clear still image (up to 24 megapixels) or an unlocked PDF.');}
 let name=String(filename??'Receipt').split(/[\\/]/).pop().replace(/[\x00-\x1f\x7f]/g,'').trim().slice(0,150)||'Receipt';
 const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp','application/pdf':'pdf'}[mime];
 name=name.replace(/\.[^.]{1,10}$/,'')+'.'+ext;
 return {original:buffer,preview,metadata:{filename:name,mime_type:mime,byte_size:buffer.length,sha256:digest(buffer),pages,preview_size:preview?.length??0,preview_sha256:preview?digest(preview):null}};
}
export function createReceiptStorage(database){
 const bucket=database.storage.from(RECEIPT_BUCKET);
 return {
  async upload(path,bytes,mime){
   const result=await bucket.upload(path,bytes,{contentType:mime,upsert:false,cacheControl:'0'});
   if(result.error){
    // A duplicate/lost response is safe only if the exact immutable bytes exist.
    const existing=await bucket.download(path,{}, {signal:AbortSignal.timeout(45000),cache:'no-store'});
    if(!existing.error&&existing.data){const saved=Buffer.from(await existing.data.arrayBuffer());if(saved.length===bytes.length&&digest(saved)===digest(bytes))return;}
    fail('The receipt upload did not finish. Refresh, then retry the same file when the upload is available.',503,'BOOKKEEPING_UPLOAD_INCOMPLETE');
   }
  },
  async download(path,expectedHash,expectedSize){
   const result=await bucket.download(path,{}, {signal:AbortSignal.timeout(45000),cache:'no-store'});
   if(result.error||!result.data)fail('This receipt file is unavailable. Refresh and try again.',503,'BOOKKEEPING_FILE_UNAVAILABLE');
   const bytes=Buffer.from(await result.data.arrayBuffer());
   if(bytes.length!==expectedSize||digest(bytes)!==expectedHash)fail('Receipt integrity could not be verified. Contact support.',503,'BOOKKEEPING_FILE_INTEGRITY');
   return bytes;
  },
  async remove(paths){const result=await bucket.remove(paths);if(result.error)fail('Deletion is incomplete. Refresh and retry deletion.',503,'BOOKKEEPING_DELETE_INCOMPLETE');},
 };
}
