import {parentPort,workerData} from 'node:worker_threads';
import {PDFParse} from 'pdf-parse';
let parser;
try {
 parser=new PDFParse({data:new Uint8Array(workerData),isEvalSupported:false,disableFontFace:true,verbosity:0});
 const info=await parser.getInfo();
 if(info.total>60)throw Error('PDF exceeds 60 pages. Split it into smaller sections before uploading.');
 const r=await parser.getText();const raw=r.text.replace(/\u0000/g,'').trim();
 if(raw.replace(/--\s*\d+\s*(?:of\s*\d+)?\s*--/g,'').trim().length<30)throw Error('This PDF has no usable text. Scanned pages need OCR first; paste the recognized text instead.');
 parentPort.postMessage({ok:true,text:raw.slice(0,18000),pageCount:info.total,truncated:raw.length>18000,warnings:raw.length>18000?['Only the first 18,000 characters were extracted. Review and add missing sections before AI review.']:[]});
}catch(e){parentPort.postMessage({ok:false,error:/exceeds 60|no usable text/.test(e.message)?e.message:'This PDF could not be read. Use an unlocked text PDF, or paste the RFP text.'});}
finally{await parser?.destroy().catch(()=>{});}
