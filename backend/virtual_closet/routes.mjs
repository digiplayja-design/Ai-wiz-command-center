import {randomUUID,createHash} from 'node:crypto';
import multer from 'multer';
import {ClosetError,fail,text,uuid,categories,normalizeUpload} from './ai.mjs';
const bucket='korlix-virtual-closet';
const base='/api/virtual-closet';
export function registerVirtualCloset(app,{database,storageDatabase=database,requireUser,aiAccess,tryOn,style,logger=console}={}){
 const active=new Set();
 const starting=new Set();let uploads=0;
 const call=async(user,action,id=null,data={})=>{
  const r=await database.rpc('korlix_closet_v1',{p_actor:user,p_action:action,p_id:id,p_data:data});
  if(r.error){const e=r.error;const statuses={P0002:404,'40001':409,'54000':429,P0001:400,'42501':403};
   if(statuses[e.code])fail(e.message,statuses[e.code]);
   fail('Closet storage is temporarily unavailable. Refresh before retrying.',503);}
  return r.data;
 };
 const objects=()=>storageDatabase.storage.from(bucket);
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{
  const user=await requireUser(q);if(!user?.id)fail('Sign in to use Virtual Closet.',401);
  if(!database||!storageDatabase)fail('Virtual Closet is temporarily unavailable.',503);
  await fn(q,r,user);
 }catch(e){const status=e instanceof ClosetError?e.status:e.statusCode===401?401:503;
  r.status(status).json({error:e instanceof ClosetError?e.message:status===401?'Sign in again to use Virtual Closet.':'Virtual Closet is temporarily unavailable. Refresh and try again.'});}};
 const publicAssets=async(rows)=>{
  const paths=rows.filter(a=>a.state==='ready').flatMap(a=>[a.path,a.thumb_path]);
  let urls=new Map();if(paths.length){const r=await objects().createSignedUrls(paths,600);if(r.error)fail('Your photos could not be loaded. Refresh shortly.',503);urls=new Map((r.data||[]).map(x=>[x.path,x.signedUrl]));}
  return rows.map(a=>({id:a.id,kind:a.kind,name:a.name,category:a.category,state:a.state,width:a.width,height:a.height,created_at:a.created_at,
   imageUrl:a.state==='ready'?urls.get(a.path)||null:null,thumbnailUrl:a.state==='ready'?urls.get(a.thumb_path)||null:null}));
 };
 const publicJob=j=>({id:j.id,kind:j.kind,state:j.state,photo_id:j.photo_id,garment_ids:j.garment_ids,prompt:j.prompt,result:j.result,error:j.error,created_at:j.created_at,completed_at:j.completed_at});
 const download=async(asset,thumb=false)=>{
  if(asset.state!=='ready')fail('This item has not finished saving.',409);
  const r=await objects().download(thumb?asset.thumb_path:asset.path);if(r.error||!r.data)fail('This photo could not be loaded. Try again shortly.',503);
  return Buffer.from(await r.data.arrayBuffer());
 };
 const save=async(user,id,details,prepared)=>{
  const lease=randomUUID(),prefix=`${user}/${id}/`;
  let asset=await call(user,'asset_begin',id,{...details,lease,path:prefix+'image.'+prepared.extension,thumb_path:prefix+'thumb.jpg',
   digest:createHash('sha256').update(prepared.image).digest('hex'),bytes:prepared.image.length+prepared.thumb.length,width:prepared.width,height:prepared.height});
  if(asset.state==='ready')return asset;
  for(const [path,bytes,mime] of [[asset.path,prepared.image,prepared.mime],[asset.thumb_path,prepared.thumb,'image/jpeg']]){
   const r=await objects().upload(path,bytes,{contentType:mime,upsert:true,cacheControl:'0'});
   if(r.error)fail('The upload did not finish. Refresh your closet; you can remove the incomplete item after three minutes.',503);
  }
  return call(user,'asset_finish',id,{lease});
 };
 const run=async(user,job)=>{
  active.add(job.id);
  try{
   let result;
   if(job.kind==='tryon'){
    const photo=await call(user.id,'asset_get',job.photo_id);
    const garments=await Promise.all(job.garment_ids.map(id=>call(user.id,'asset_get',id)));
    const rendered=await tryOn({photo:{...photo,bytes:await download(photo)},garments:await Promise.all(garments.map(async g=>({...g,bytes:await download(g)}))),prompt:job.prompt});
    const asset=await save(user.id,randomUUID(),{kind:'look',name:'Look · '+new Date().toISOString().slice(0,10),category:'look'},rendered);
    result={asset_id:asset.id,summary:rendered.summary,model:rendered.model,quality:rendered.quality};
   }else{
    const list=await call(user.id,'list');const garments=list.assets.filter(a=>a.kind==='garment'&&a.state==='ready');
    result=await style({garments:await Promise.all(garments.map(async(g,i)=>({...g,...(i<16?{bytes:await download(g,true)}:{})}))),prompt:job.prompt});
   }
   await call(user.id,'job_finish',job.id,{result});
  }catch(e){
   logger.warn('Virtual Closet job failed',{kind:job.kind,errorType:e.name||'Error'});
   try{await call(user.id,'job_fail',job.id,{error:e instanceof ClosetError?e.message:'KORLIX could not finish this session. No generation credit was charged. Try again shortly.'});}catch{logger.warn('Virtual Closet job status could not be saved');}
  }finally{active.delete(job.id);}
 };
 app.get(base,route(async(_q,r,user)=>{const data=await call(user.id,'list');r.json({assets:await publicAssets(data.assets),jobs:data.jobs.map(publicJob),limits:{photos:5,garments:100,looks:50},creditCost:1});}));
 const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:15*1024*1024,files:1,fields:5,fieldSize:2048}}).single('image');
 app.post(base+'/assets',route(async(q,r,user)=>{
  if(uploads>=3)fail('The photo service is busy. Please try uploading again shortly.',429);
  uploads++;
  try {
  await new Promise((resolve,reject)=>upload(q,r,e=>e?reject(new ClosetError('Choose one JPG, PNG, or WEBP image under 15 MB.')):resolve()));
  const id=uuid(q.body?.request_key),kind=q.body?.kind;
  if(!['photo','garment'].includes(kind))fail('Choose a photo or a wardrobe item.');
  const name=text(q.body.name,80,'Name'),category=kind==='photo'?'photo':q.body.category;
  if(kind==='garment'&&!categories.includes(category))fail('Choose a clothing category.');
  const prepared=await normalizeUpload(q.file);
  const asset=await save(user.id,id,{kind,name,category},prepared);
  r.status(201).json({asset:(await publicAssets([asset]))[0]});
  } finally {uploads--;}
 }));
 app.delete(base+'/assets/:id',route(async(q,r,user)=>{
  if(q.body?.confirmed!==true)fail('Confirm before removing an item.');
  const id=uuid(q.params.id),a=await call(user.id,'asset_delete_begin',id);
  const removed=await objects().remove([a.path,a.thumb_path]);if(removed.error)fail('Removal did not finish. Refresh and retry removing this item.',503);
  await call(user.id,'asset_delete_finish',id);r.json({deleted:true});
 }));
 app.get(base+'/assets/:id/file',route(async(q,r,user)=>{
  const asset=await call(user.id,'asset_get',uuid(q.params.id));const bytes=await download(asset);
  const ext=asset.kind==='look'?'png':'jpg';r.set('Content-Type',ext==='png'?'image/png':'image/jpeg');
  r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition',`attachment; filename="KORLIX-${asset.kind}-${asset.id}.${ext}"`);r.send(bytes);
 }));
 app.post(base+'/jobs',route(async(q,r,user)=>{
  const id=uuid(q.body?.request_key),kind=q.body?.kind;
  if(!['tryon','style'].includes(kind))fail('Choose try-on or KORLIX styling.');
  if(q.body?.consent!==true)fail('Please confirm you want to share these photos with the AI provider.');
  const prompt=q.body.prompt===''?'':text(q.body.prompt,1500,'Styling request');
  if(kind==='style'&&!prompt)fail('Tell KORLIX what occasion you are dressing for.');
  const photo=kind==='tryon'?uuid(q.body.photo_id):null;
  const ids=kind==='tryon'?q.body.garment_ids:[];
  if(!Array.isArray(ids)||ids.length>4||(kind==='tryon'&&!ids.length))fail('Choose one to four wardrobe items.');
  ids.forEach(uuid);
  // Completed/running requests can be recovered even after their credit was used.
  try{const prior=await call(user.id,'job_get',id);return r.json({job:publicJob(prior)});}catch(e){if(e.status!==404)throw e;}
  if(active.size+starting.size>=3)fail('KORLIX is finishing other styling sessions. Please try again shortly.',429);
  starting.add(id);
  try {
  const access=await aiAccess(user);
  if(!access?.allowed)fail(access?.reason||'AI styling requires Ultra Premium or Enterprise.',access?.status||403);
  const job=await call(user.id,'job_begin',id,{kind,photo_id:photo,garment_ids:ids,prompt,usage_id:access.usageId});
  r.status(202).json({job:publicJob(job)});
  if(!job.replayed&&!active.has(job.id))void run(user,job);
  } finally {starting.delete(id);}
 }));
 app.get(base+'/jobs/:id',route(async(q,r,user)=>{
  const job=await call(user.id,'job_get',uuid(q.params.id));let asset;
  if(job.state==='completed'&&job.result?.asset_id){try{asset=(await publicAssets([await call(user.id,'asset_get',job.result.asset_id)]))[0];}catch(e){if(e.status!==404)throw e;}}
  r.json({job:publicJob(job),asset});
 }));
 return {active};
}
