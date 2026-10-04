import {Worker} from 'node:worker_threads';
import {fail} from './ai.mjs';
export const PDF_LIMIT=5*1024*1024;
export async function extractRfpPdf(buffer,{timeout=20000}={}){
 if(!Buffer.isBuffer(buffer)||buffer.length<5||buffer.length>PDF_LIMIT)fail('Upload a PDF smaller than 5 MiB.',413);
 if(buffer.subarray(0,5).toString()!=='%PDF-')fail('Choose a valid PDF file.',422);
 return new Promise((resolve,reject)=>{
  const worker=new Worker(new URL('./pdf_worker.mjs',import.meta.url),{workerData:buffer,resourceLimits:{maxOldGenerationSizeMb:192,maxYoungGenerationSizeMb:32},stdout:true,stderr:true});
  let done=false;const finish=(error,data)=>{if(done)return;done=true;clearTimeout(timer);void worker.terminate();error?reject(error):resolve(data);};
  const error=message=>Object.assign(new Error(message),{status:422});
  const timer=setTimeout(()=>finish(error('This PDF took too long to read. Split it into smaller sections.')),timeout);
  worker.once('message',value=>value.ok?finish(null,value):finish(error(value.error)));
  worker.once('error',()=>finish(error('This PDF is too complex to read. Split it into smaller sections.')));
  worker.once('exit',()=>{if(!done)finish(error('This PDF could not be read. Try a smaller text PDF.'));});
 });
}
