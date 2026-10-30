import multer from 'multer';
import sharp from 'sharp';
import {PRESETS,MAX_SOURCE,UUID,options,prepareSource,fingerprint,instructions,fail} from './core.mjs';
import {createReportSubmissionGuard} from '../security/report_submission.mjs';
import {prepareReportImageEvidence,reportImageMetadata} from '../security/report_image_evidence.mjs';
import {persistAiReport} from '../security/ai_report_persistence.mjs';
const base='/api/magic-camera';
const fields=['id','state','options','created_at','finished_at','width','height','render_ms','error'];
export const publicJob=j=>Object.fromEntries(fields.map(k=>[k,j[k]??null]));
export const paths=j=>({source:`${j.owner_id}/${j.id}/capture.jpg`,output:`${j.owner_id}/${j.id}/magic.png`});
export function magicStore(database){
 return async(actor,action,id=null,p={})=>{
  if(!database)fail('Magic Camera is being connected. Please try again shortly.',503);
  const {data,error}=await database.rpc('korlix_magic_command',{p_actor:actor,p_action:action,p_id:id,p});
  if(error){const m=/MAG(\d{3}): (.+)/.exec(error.message||'');fail(m?m[2]:'Magic storage is temporarily unavailable.',m?Number(m[1]):503);}
  return data;
 };
}
export function magicStorage(database){
 if(!database?.storage)return null;
 const bucket=database.storage.from('korlix-magic-camera');
 return {
  async upload(path,bytes,contentType){const r=await bucket.upload(path,bytes,{contentType,upsert:false,cacheControl:'0'});if(r.error)fail('Your photo could not be stored privately.',503);},
  async download(path){const r=await bucket.download(path);if(r.error)fail('This photo could not be loaded.',503);return Buffer.from(await r.data.arrayBuffer());},
  async remove(keys){const r=await bucket.remove(keys);if(r.error)fail('Photo removal is pending. Please retry.',503);},
 };
}
export function createMagicWorker({call,storage,render,now=Date.now,onEvent=()=>{}}){
 let running=false;
 async function cleanup(j){
  const p=paths(j);await storage.remove([p.source,...(['failed','deleted'].includes(j.state)?[p.output]:[])]);
  await call(j.owner_id,'purged',j.id);
 }
 async function tick(){
  if(running||!storage)return;running=true;
  try{
   for(const j of await call(null,'sweep'))await cleanup(j).catch(()=>onEvent('cleanup_pending'));
   if(!render)return;
   const j=await call(null,'claim');if(!j)return;
   const p=paths(j),start=now();
   try{
    const source=await storage.download(p.source);
    let output;
    try{output=await render(source,options(j.options));}finally{source.fill(0);}
    await storage.upload(p.output,output.bytes,'image/png');
    const finished=await call(j.owner_id,'finish',j.id,{worker_token:j.worker_token,width:output.width,height:output.height,render_ms:now()-start});
    await cleanup(finished.job);onEvent('completed',{render_ms:now()-start});
   }catch{
    // Never replay an uncertain provider request. An expired lease is failed by
    // the sweeper; a successful finish remains successful even if cleanup fails.
    const result=await call(j.owner_id,'fail',j.id,{worker_token:j.worker_token}).catch(()=>null);
    if(result?.job)await cleanup(result.job).catch(()=>onEvent('cleanup_pending'));
    onEvent('generation_failed');
   }
  }catch{onEvent('worker_unavailable');}finally{running=false;}
 }
 return {tick,cleanup};
}
export function registerMagicCamera(app,{database,storage=magicStorage(database),call=magicStore(database),requireUser,render,autoStart=true,reportPersist=(r,e)=>persistAiReport(database,r,e)}={}){
 const parse=multer({storage:multer.memoryStorage(),limits:{fileSize:MAX_SOURCE,files:1,fields:1,fieldSize:12000,parts:2}}).single('capture');
 const guard=createReportSubmissionGuard();
 const worker=createMagicWorker({call,storage,render});
 let uploads=0;
 const standalone=q=>q.korlixReceiptAppSession?.client_app==='magic_camera';
 const route=fn=>async(q,r)=>{
  r.set('Cache-Control','no-store');
  try{const user=await requireUser(q);if(!user?.id)fail('Sign in to use Magic Camera.',401);await fn(q,r,user);}
  catch(e){r.status(e.statusCode||503).json({error:e.statusCode?e.message:'Magic Camera is temporarily unavailable. Please retry.'});}
 };
 const id=value=>{if(!UUID.test(value||''))fail('Invalid generation ID.');return value;};
 app.get(base,route(async(q,r,u)=>{
  if(q.query.offset!==undefined&&(typeof q.query.offset!=='string'||!/^\d{1,7}$/.test(q.query.offset)))fail('Invalid gallery page.');
  r.json({...await call(u.id,'list',null,{standalone:standalone(q),offset:Number(q.query.offset||0)}),presets:PRESETS,available:!!render&&!!storage});
 }));
 app.post(base,route(async(q,r,u)=>{
  if(!render||!storage)fail('Magic rendering is being connected. Your allowance has not changed.',503);
  const key=id(q.get('X-Magic-Request-Key'));
  if(uploads>=3)fail('The camera is busy. Please try again shortly.',429);
  uploads++;let reserved,source;
  try{
   await new Promise((resolve,reject)=>parse(q,r,e=>e?reject(e):resolve()));
   let o;try{o=options(JSON.parse(q.body?.options||'{}'));}catch(e){if(e.statusCode)throw e;fail('Check your magic options.');}
   source=await prepareSource(q.file?.buffer);
   reserved=await call(u.id,'reserve',null,{request_key:key,fingerprint:fingerprint(source,o),options:o,standalone:standalone(q)});
   if(reserved.dispatch){
    await storage.upload(paths(reserved.job).source,source,'image/jpeg');
    reserved=await call(u.id,'uploaded',reserved.job.id);
   }
   r.status(reserved.job.state==='ready'?200:202).json({job:publicJob(reserved.job)});
   void worker.tick();
  }catch(e){
   if(reserved?.dispatch)await call(u.id,'fail',reserved.job.id).catch(()=>{});
   if(e instanceof multer.MulterError)fail(e.code==='LIMIT_FILE_SIZE'?'Use a photo under 15 MB.':'Send one photo and one set of options.');
   throw e;
  }finally{q.file?.buffer?.fill(0);q.file=undefined;source?.fill(0);uploads--;}
 }));
 app.get(base+'/:id',route(async(q,r,u)=>r.json({job:publicJob((await call(u.id,'get',id(q.params.id))).job)})));
 app.get(base+'/:id/image',route(async(q,r,u)=>{
  const {job}=await call(u.id,'get',id(q.params.id));if(job.state!=='ready'||job.deleted_at)fail('This magic photo is not available.',404);
  const bytes=await storage.download(paths(job).output);
  const preview=q.query.preview==='1';
  const image=preview?await sharp(bytes).resize({width:640,height:640,fit:'inside',withoutEnlargement:true}).jpeg({quality:80}).toBuffer():bytes;
  r.set({'Content-Type':preview?'image/jpeg':'image/png','X-Content-Type-Options':'nosniff','Content-Disposition':`inline; filename="korlix-magic.${preview?'jpg':'png'}"`,'Content-Security-Policy':"sandbox; default-src 'none'"});r.send(image);
 }));
 app.post(base+'/:id/report',route(async(q,r,u)=>{
  const {job}=await call(u.id,'get',id(q.params.id));if(job.state!=='ready'||job.deleted_at)fail('This magic photo is not available.',404);
  const allowed=['Offensive or hateful','Sexual content','Violence or harm','Distorted face or body','Other'];
  if(!allowed.includes(q.body?.reason)||typeof (q.body?.details??'')!=='string'||(q.body?.details??'').length>2000)fail('Choose a report reason and keep comments under 2,000 characters.');
  const report=guard({req:{...q,headers:q.headers,body:{reason:q.body.reason,details:q.body.details||'',contentType:'image',generationId:job.id,prompt:instructions(job.options),appArea:'magic_camera',outputSummary:'Magic Camera generated result'}},user:u});
  const bytes=await storage.download(paths(job).output);
  const small=await sharp(bytes).resize({width:960,height:960,fit:'inside',withoutEnlargement:true}).jpeg({quality:80}).toBuffer();
  const evidence=await prepareReportImageEvidence('data:image/jpeg;base64,'+small.toString('base64'));
  report.imageEvidence=reportImageMetadata(evidence);
  // Existing private support review queue; no email is sent by this module.
  await reportPersist(report,evidence);r.status(201).json({accepted:true,reportId:report.id});
 }));
 app.delete(base+'/:id',route(async(q,r,u)=>{
  if(q.body?.confirmed!==true)fail('Confirm deletion of this saved image.');
  const {job}=await call(u.id,'delete',id(q.params.id));await worker.cleanup(job);r.json({deleted:true});
 }));
 const timer=autoStart&&storage?setInterval(()=>void worker.tick(),5000):null;
 timer?.unref();return {worker,stop:()=>clearInterval(timer)};
}
