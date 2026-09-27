import {MusicError,fail,uuid,settings,entitlement,createProvider,publicJob,downloadAudio} from './core.mjs';
export function registerMusicStudio(app,{database,requireUser,provider=createProvider(),access=entitlement,fetchAudio=downloadAudio,logger=console}={}){
 const base='/api/music',active=new Set();
 const call=async(actor,action,id=null,data={})=>{
  const r=await database.rpc('korlix_music_v2',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'23505':409,'42501':403,'54000':429,P0001:400}[r.error.code];if(status)fail(['P0002','40001','54000','P0001'].includes(r.error.code)?r.error.message:'Music Studio could not save this request.',status);logger.warn('Music Studio storage unavailable',{action,code:r.error.code});fail('Music Studio could not save this change. Refresh before retrying.',503);}
  if(!r.data)fail('Music Studio is temporarily unavailable.',503);return r.data;
 };
 const route=fn=>async(q,r)=>{
  r.set('Cache-Control','no-store');
  try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use Music Studio.',401);}if(!u?.id)fail('Sign in to use Music Studio.',401);if(!database)fail('Music Studio is temporarily unavailable.',503);await fn(q,r,u);}
  catch(e){r.status(e instanceof MusicError?e.status:503).json({error:e instanceof MusicError?e.message:'Music Studio could not finish this request. Refresh before retrying.'});}
 };
 const addon=async u=>{const a=access(u),usage=await call(u.id,'usage');return {...a,providerReady:provider.ready(),usage:{...usage,monthlyLimit:a.plan?.monthlyGenerations??0,remainingThisCycle:Math.max(0,(a.plan?.monthlyGenerations??0)-usage.allocated)},version:2};};
 const list=async(u,q={})=>{
  const data=await call(u.id,'list',q.before?uuid(q.before):null,{query:String(q.query??'').slice(0,80),favorites:q.favorites==='true'});
  const jobs=data.jobs.slice(0,30);return {jobs:jobs.map(publicJob),hasMore:data.jobs.length>30,nextBefore:jobs.at(-1)?.id??null};
 };
 const status=async(u,id)=>{
  const p=await call(u.id,'poll_begin',uuid(id));let j=p.job;
  if(p.poll){try{j=await call(u.id,'result',j.id,await provider.status(j.task_id));}catch(e){return {...publicJob(j),refreshError:e instanceof MusicError?e.message:'Could not refresh this creation. Check again shortly.'};}}
  return publicJob(j);
 };
 const submit=async(u,job)=>{const id=job.id,o=job.payload;let j=job;active.add(id);try{

   let taskId;
   try{taskId=await provider.create(o);}
   catch(e){j=await call(u.id,'submission_error',id,{definite:e.definite===true,error:e.definite===true?'The music service rejected this request. Your allowance was released. Edit your idea and create a new version.':'Submission could not be confirmed. This allowance is reserved. Contact support with the reference in My tracks before submitting the same idea again.'});}
   if(taskId){
    let saved=false;
    for(let attempt=0;attempt<3;attempt++){try{j=await call(u.id,'accepted',id,{task_id:taskId});saved=true;break;}catch{if(attempt<2)await new Promise(resolve=>setTimeout(resolve,200*(attempt+1)));}}
    if(!saved)logger.warn('Music accepted status requires recovery',{requestId:id});
   }

 }catch{logger.warn('Music submission status could not be saved',{requestId:id});}finally{active.delete(id);}};
 app.get(base+'/addon',route(async(_q,r,u)=>r.json(await addon(u))));
 app.get(base+'/studio',route(async(_q,r,u)=>r.json({addon:await addon(u),...await list(u),draft:await call(u.id,'draft_get')})));
 app.get(base+'/jobs',route(async(q,r,u)=>r.json(await list(u,q.query))));
 app.get(base+'/draft',route(async(_q,r,u)=>r.json({draft:await call(u.id,'draft_get')})));
 app.put(base+'/draft',route(async(q,r,u)=>{
  if(!Number.isInteger(q.body?.version)||q.body.version<0)fail('Reload your saved draft before saving.');
  r.json({draft:await call(u.id,'draft_save',uuid(q.body?.request_key),{version:q.body.version,data:settings(q.body?.data,{draft:true})})});
 }));
 app.post(base+'/generate',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key),o=settings(q.body);
  if(q.body?.consent!==true)fail('Allow MusicAPI.ai to process your music idea and lyrics before creating.');
  const a=access(u);
  // Recover a matching request even if its monthly allowance was used by that request.
  try{const j=await call(u.id,'get',id);if(JSON.stringify(j.payload)!==JSON.stringify(o)){
    // Postgres jsonb key order differs from JavaScript; compare canonical values.
    if(Object.keys(o).some(k=>JSON.stringify(j.payload[k])!==JSON.stringify(o[k])))fail('Use a new request after changing your music idea.',409);
   }return r.json({job:publicJob(j),jobId:j.id,status:j.state,replayed:true,addon:await addon(u)});
  }catch(e){if(e.status!==404)throw e;}
  if(!a.active||!a.plan)fail('Music Production add-on required. You can still save your draft.',403);
  if(!provider.ready())fail('Music creation is temporarily unavailable. Your draft can still be saved.',503);
  const begin=await call(u.id,'begin',id,{payload:o,limit:a.plan.monthlyGenerations});
  let j=begin.job;
  if(!begin.replayed){void submit(u,j);}
  r.status(202).json({job:publicJob(j),jobId:j.id,status:j.state,replayed:begin.replayed,addon:await addon(u)});
 }));
 app.get(base+'/status/:jobId',route(async(q,r,u)=>{const j=await status(u,q.params.jobId);r.json({...j,job:j});}));
 app.put(base+'/jobs/:id/favorite',route(async(q,r,u)=>{
  if(typeof q.body?.favorite!=='boolean')fail('Choose whether to favorite this creation.');
  r.json({job:publicJob(await call(u.id,'favorite',uuid(q.params.id),{favorite:q.body.favorite}))});
 }));
 app.delete(base+'/jobs/:id',route(async(q,r,u)=>r.json(await call(u.id,'remove',uuid(q.params.id),{confirmed:q.body?.confirmed===true}))));
 app.get(base+'/jobs/:id/tracks/:index/file',route(async(q,r,u)=>{
  const j=await call(u.id,'get',uuid(q.params.id)),index=Number(q.params.index);
  if(!Number.isInteger(index)||index<0||index>=j.tracks.length)fail('Track not found.',404);
  const t=j.tracks[index];if(t.state!=='succeeded'||!t.audioUrl)fail('This track is still being finished.',409);
  const f=await fetchAudio(t.audioUrl);
  r.set('Content-Type',f.mime);r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition','attachment; filename="KORLIX-Music-'+j.id+'-'+(index+1)+'.'+f.extension+'"');r.send(f.bytes);
 }));
 // Unauthenticated callbacks never decide a job's state. This integration polls the provider.
 app.post(base+'/webhook',(_q,r)=>r.status(410).json({error:'Music status callbacks are not enabled.'}));
 app.get(base+'/content/:trackId',route(async(_q,r)=>r.status(410).json({error:'Open the track from your saved Music Studio library.'})));
 return {call,active};
}
