import {randomUUID,createHash} from 'node:crypto';
import multer from 'multer';
import {BUCKET,CREDIT_COST,MAX_PHOTOS,TEMPLATES,TAGS,FieldProofError,fail,text,uuid,version,jobData,readiness,prepareEvidence,evidenceManifest,reportFingerprint} from './model.mjs';
import {registerFieldProofVoice} from './voice.mjs';
import {requireFieldProofEnterprise,fieldProofAccessDetails} from './access.mjs';
const base='/api/fieldproof';
export function registerFieldProof(app,{database,storageDatabase=database,requireUser,aiAccess,review,logger=console}={}){
 const active=new Set(),starting=new Set();let uploads=0;
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_fieldproof_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'54000':429,P0001:400,'42501':403}[r.error.code];if(status)fail(r.error.message,status);logger.warn('FieldProof storage unavailable',{action,code:r.error.code});fail('FieldProof could not save this change. Your entries remain here; refresh before retrying.',503);}return r.data;};
 const objects=()=>storageDatabase.storage.from(BUCKET);
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const u=await requireUser(q);if(!u?.id)fail('Sign in to use FieldProof.',401);if(!database||!storageDatabase)fail('FieldProof is temporarily unavailable.',503);await requireFieldProofEnterprise(database,u.id);await fn(q,r,u);}catch(e){const status=e instanceof FieldProofError?e.status:e.statusCode===401?401:503;r.status(status).json({error:e instanceof FieldProofError?e.message:status===401?'Sign in again to use FieldProof.':'FieldProof could not finish this request. Refresh before retrying.',...fieldProofAccessDetails(e)});}};
 const publicJob=j=>({id:j.id,data:j.data,version:j.version,state:j.state,approval:j.approval,completion:j.completion,createdAt:j.created_at,updatedAt:j.updated_at,photoCount:j.photo_count,runningReview:j.running_review});
 const publicReview=r=>({id:r.id,jobId:r.job_id,version:r.version,state:r.state,result:r.result,error:r.error,charged:r.charged,createdAt:r.created_at,completedAt:r.completed_at});
 const publicEvidence=async(rows)=>{
  const paths=rows.filter(a=>a.state==='ready').map(a=>a.preview_path);let urls=new Map();
  if(paths.length){const r=await objects().createSignedUrls(paths,600);if(r.error)fail('Photo previews are temporarily unavailable. Refresh shortly.',503);urls=new Map((r.data||[]).map(x=>[x.path,x.signedUrl]));}
  return rows.map(a=>({...evidenceManifest(a),state:a.state,previewUrl:a.state==='ready'?urls.get(a.preview_path)||null:null}));
 };
 const snapshot=async(user,id)=>{const d=await call(user,'job_get',id);const current=d.reviews.find(r=>r.state==='completed'&&r.version===d.job.version);
  return {job:publicJob(d.job),evidence:await publicEvidence(d.evidence),reviews:d.reviews.map(publicReview),events:d.events,readiness:readiness(d.job,d.evidence),fingerprint:reportFingerprint(d.job,d.evidence,current),snapshotAt:new Date().toISOString()};};
 const download=async(a,preview=false)=>{if(a.state!=='ready')fail('This photo has not finished saving.',409);const r=await objects().download(preview?a.preview_path:a.path);if(r.error||!r.data)fail('This photo could not be downloaded. Refresh and retry.',503);
  const bytes=Buffer.from(await r.data.arrayBuffer());if(createHash('sha256').update(bytes).digest('hex')!==(preview?a.preview_sha256:a.sha256))fail('This photo failed its file-integrity check. Please contact support.',503);return bytes;};
 const run=async(u,r)=>{active.add(r.id);try{const evidence=[];for(const a of r.input.evidence)evidence.push({...a,preview:await download(a,true)});
  const result=await review({job:r.input.job,evidence});await call(u.id,'review_finish',r.id,{result});
 }catch(e){logger.warn('FieldProof review failed',{errorType:e.name||'Error'});try{await call(u.id,'review_fail',r.id,{error:e instanceof FieldProofError?e.message:'KORLIX could not finish this review. No credit was charged. Please retry.'});}catch{logger.warn('FieldProof review status could not be saved');}}finally{active.delete(r.id);}};
 const confirmed=q=>{if(q.body?.confirmed!==true)fail('Confirm this action before continuing.');};
 registerFieldProofVoice(app,{route,call});
 app.get(base,route(async(_q,r,u)=>r.json({jobs:(await call(u.id,'list')).map(publicJob),templates:TEMPLATES,tags:TAGS,creditCost:CREDIT_COST,features:{voice:true,batchPhotos:true,readings:true,punchList:true,autonomousEmail:true},limits:{jobs:200,photosPerJob:MAX_PHOTOS,checks:32,readings:20,issues:16,photoBytes:10*1024*1024,storageBytes:500*1024*1024}})));
 app.post(base+'/jobs',route(async(q,r,u)=>{const id=uuid(q.body?.request_key);await call(u.id,'job_create',id,jobData(q.body?.data));r.status(201).json(await snapshot(u.id,id));}));
 app.get(base+'/jobs/:id',route(async(q,r,u)=>r.json(await snapshot(u.id,uuid(q.params.id)))));
 app.put(base+'/jobs/:id',route(async(q,r,u)=>{const id=uuid(q.params.id);await call(u.id,'job_save',id,{version:version(q.body?.version),data:jobData(q.body?.data)});r.json(await snapshot(u.id,id));}));
 app.post(base+'/jobs/:id/approval',route(async(q,r,u)=>{confirmed(q);const id=uuid(q.params.id),d=await call(u.id,'job_get',id);
  if(!d.job.data.technician)fail('Save the technician name before recording customer approval.');
  await call(u.id,'job_approve',id,{version:version(q.body?.version),name:text(q.body?.name,120,'Customer approver name'),note:text(q.body?.note,1500,'Approval note',true)});r.json(await snapshot(u.id,id));}));
 app.post(base+'/jobs/:id/complete',route(async(q,r,u)=>{confirmed(q);const id=uuid(q.params.id),d=await call(u.id,'job_get',id),check=readiness(d.job,d.evidence);
  if(!check.ready)fail('Complete the missing records: '+check.missing.slice(0,5).join('; ')+'.',409);
  await call(u.id,'job_complete',id,{version:version(q.body?.version),ready:true,name:d.job.data.technician});r.json(await snapshot(u.id,id));}));
 app.post(base+'/jobs/:id/reopen',route(async(q,r,u)=>{confirmed(q);const id=uuid(q.params.id);await call(u.id,'job_reopen',id,{version:version(q.body?.version)});r.json(await snapshot(u.id,id));}));
 app.delete(base+'/jobs/:id',route(async(q,r,u)=>{confirmed(q);const id=uuid(q.params.id),rows=await call(u.id,'job_delete_begin',id,{version:version(q.body?.version)});
  const paths=rows.flatMap(a=>[a.path,a.preview_path]);if(paths.length){const removed=await objects().remove(paths);if(removed.error)fail('Removal is incomplete. Retry removing this job to finish deleting its photos.',503);}
  await call(u.id,'job_delete_finish',id);r.json({deleted:true});}));
 const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:10*1024*1024,files:1,fields:6,fieldSize:1500}}).single('image');
 app.post(base+'/jobs/:id/photos',route(async(q,r,u)=>{
  if(uploads>=2)fail('The photo service is busy. Try again shortly.',429);uploads++;
  try{const jobId=uuid(q.params.id);await call(u.id,'job_get',jobId);
   await new Promise((resolve,reject)=>upload(q,r,e=>e?reject(new FieldProofError('Choose one JPG, PNG or WEBP photo under 10 MB.')):resolve()));
   const id=uuid(q.body?.request_key),tag=q.body?.tag;if(!Object.hasOwn(TAGS,tag))fail('Choose a photo category.');
   const name=text(q.body?.name,100,'Photo label'),note=text(q.body?.note,1000,'Photo note',true),prepared=await prepareEvidence(q.file),lease=randomUUID(),prefix=`${u.id}/${jobId}/${id}/`;
   const a=await call(u.id,'asset_begin',id,{job_id:jobId,version:version(Number(q.body?.version)),tag,name,note,lease,path:prefix+'original.'+prepared.extension,preview_path:prefix+'preview.jpg',
    ...Object.fromEntries(['mime','extension','sha256','preview_sha256','bytes','preview_bytes','width','height'].map(k=>[k,prepared[k]]))});
   if(a.state!=='ready'){
    for(const [path,bytes,mime] of [[a.path,prepared.original,a.mime],[a.preview_path,prepared.preview,'image/jpeg']]){const saved=await objects().upload(path,bytes,{contentType:mime,upsert:true,cacheControl:'0'});if(saved.error)fail('The upload was interrupted. Keep this photo selected and retry after three minutes, or remove the incomplete upload.',503);}
    await call(u.id,'asset_finish',id,{lease});
   }
   r.status(201).json(await snapshot(u.id,jobId));
  }finally{uploads--;}
 }));
 app.delete(base+'/photos/:id',route(async(q,r,u)=>{confirmed(q);const a=await call(u.id,'asset_delete_begin',uuid(q.params.id)),removed=await objects().remove([a.path,a.preview_path]);
  if(removed.error)fail('Photo removal is incomplete. Retry removing it.',503);await call(u.id,'asset_delete_finish',a.id);r.json(await snapshot(u.id,a.job_id));}));
 app.get(base+'/photos/:id/file',route(async(q,r,u)=>{const a=await call(u.id,'asset_get',uuid(q.params.id)),preview=q.query.preview==='true';const bytes=await download(a,preview);
  r.set('Content-Type',preview?'image/jpeg':a.mime);r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition',`attachment; filename="KORLIX-FieldProof-${a.id}.${preview?'jpg':a.extension}"`);r.send(bytes);}));
 app.post(base+'/jobs/:id/reviews',route(async(q,r,u)=>{
  const jobId=uuid(q.params.id),id=uuid(q.body?.request_key);if(q.body?.consent!==true)fail('Confirm AI sharing before reviewing job details and photos.');
  try{const prior=await call(u.id,'review_get',id);if(prior.job_id!==jobId)fail('Use a new review request for this job.',409);return r.json({review:publicReview(prior)});}catch(e){if(e.status!==404)throw e;}
  if(active.size+starting.size>=2)fail('KORLIX is finishing other reviews. Please retry shortly.',429);
  if(starting.has(id))fail('This review is starting. Refresh the job.',409);
  starting.add(id);try{const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'KORLIX photo review requires Enterprise.',access?.status||403);
   const job=await call(u.id,'review_begin',id,{job_id:jobId,version:version(q.body?.version),usage_id:access.usageId});r.status(202).json({review:publicReview(job)});if(!job.replayed&&!active.has(job.id))void run(u,job);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/reviews/:id',route(async(q,r,u)=>r.json({review:publicReview(await call(u.id,'review_get',uuid(q.params.id)))})));
 return {active};
}
