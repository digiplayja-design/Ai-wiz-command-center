import {randomUUID,createHash} from 'node:crypto';
import {RadarError,fail,text,uuid,profileData,importData} from './ai.mjs';
const base='/api/contract-radar';
const stages=['saved','reviewing','preparing','submitted','won','closed'];
export function registerContractRadar(app,{database,requireUser,aiAccess,discover,review,logger=console}={}){
 const active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_radar_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'54000':429,P0001:400,'42501':403}[r.error.code];if(status)fail(r.error.message,status);fail('Contract Radar storage is temporarily unavailable. Refresh and retry.',503);}return r.data;};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const user=await requireUser(q);if(!user?.id)fail('Sign in to use Contract Radar.',401);if(!database)fail('Contract Radar is temporarily unavailable.',503);await fn(q,r,user);}catch(e){const status=e instanceof RadarError?e.status:e.statusCode===401?401:503;r.status(status).json({error:e instanceof RadarError?e.message:status===401?'Sign in again to use Contract Radar.':'Contract Radar is temporarily unavailable. Refresh and retry.'});}};
 const publicJob=j=>({id:j.id,kind:j.kind,state:j.state,opportunityId:j.opportunity_id,result:j.result,error:j.error,charged:j.charged,createdAt:j.created_at,completedAt:j.completed_at});
 const publicOpportunity=o=>({id:o.id,data:o.data,stage:o.stage,notes:o.notes,review:o.review,createdAt:o.created_at,updatedAt:o.updated_at});
 const run=async(user,j)=>{active.add(j.id);try{
  const result=j.kind==='discover'?await discover({...j.input}):await review({...j.input});
  await call(user.id,'job_finish',j.id,{result});
 }catch(e){logger.warn('Contract Radar job failed',{kind:j.kind,errorType:e.name||'Error'});try{await call(user.id,'job_fail',j.id,{error:e instanceof RadarError?e.message:'KORLIX could not finish this request. No credit was charged. Please retry.'});}catch{logger.warn('Contract Radar job status could not be saved');}}finally{active.delete(j.id);}};
 app.get(base,route(async(_q,r,u)=>{const d=await call(u.id,'list');r.json({profile:d.profile?{data:d.profile.data,updatedAt:d.profile.updated_at}:null,opportunities:d.opportunities.map(publicOpportunity),jobs:d.jobs.map(publicJob),coverage:'Official-source web search: SAM.gov and NYC City Record. Corporate and other RFPs can be pasted for review.',creditCost:1});}));
 app.put(base+'/profile',route(async(q,r,u)=>{const p=await call(u.id,'profile_save',null,profileData(q.body));r.json({profile:{data:p.data,updatedAt:p.updated_at}});}));
 app.post(base+'/opportunities',route(async(q,r,u)=>{
  let data,source_key;const id=uuid(q.body?.request_key);
  if(q.body.job_id){const j=await call(u.id,'job_get',uuid(q.body.job_id));const i=q.body.index;
   if(j.state!=='completed'||j.kind!=='discover'||!Number.isInteger(i)||i<0||i>=j.result.opportunities.length)fail('Choose a result from a completed search.');
   data=j.result.opportunities[i];source_key=data.sourceUrl;
  }else{data=importData(q.body||{});source_key=data.sourceUrl||'import:'+id;}
  const o=await call(u.id,'opportunity_save',id,{source_key,data});r.status(201).json({opportunity:publicOpportunity(o)});
 }));
 app.patch(base+'/opportunities/:id',route(async(q,r,u)=>{const data={};
  if(Object.hasOwn(q.body||{},'stage')){if(!stages.includes(q.body.stage))fail('Choose a valid pipeline stage.');data.stage=q.body.stage;}
  if(Object.hasOwn(q.body||{},'notes'))data.notes=text(q.body.notes,4000,'Notes',true);
  if(Object.hasOwn(q.body||{},'noticeText'))data.noticeText=text(q.body.noticeText,18000,'RFP text',true);
  if(!Object.keys(data).length)fail('Choose a field to update.');
  r.json({opportunity:publicOpportunity(await call(u.id,'opportunity_update',uuid(q.params.id),data))});
 }));
 app.delete(base+'/opportunities/:id',route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before removing this opportunity.');await call(u.id,'opportunity_delete',uuid(q.params.id));r.json({deleted:true});}));
 app.delete(base,route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before clearing your radar.');await call(u.id,'clear');r.json({deleted:true});}));
 app.post(base+'/jobs',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key),kind=q.body?.kind;if(!['discover','review'].includes(kind))fail('Choose discovery or bid review.');
  if(q.body?.consent!==true)fail('Confirm AI data sharing before asking KORLIX.');
  const query=text(q.body.query,800,'Search focus',true),opportunity_id=kind==='review'?uuid(q.body.opportunity_id):null;
  const signature=createHash('sha256').update(JSON.stringify({kind,query,opportunity_id})).digest('hex');
  try{const prior=await call(u.id,'job_get',id);if(prior.signature!==signature)fail('Use a new request for changed inputs.',409);return r.json({job:publicJob(prior)});}catch(e){if(e.status!==404)throw e;}
  if(active.size+starting.size>=3)fail('KORLIX is finishing other radar requests. Try again shortly.',429);
  // Reserve per-request dispatch across access checks; database enforces one job per actor.
  if(starting.has(id))fail('This request is starting. Refresh to follow it.',409);
  starting.add(id);try{
   const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'AI Contract Radar requires Ultra Premium or Enterprise.',access?.status||403);
   const j=await call(u.id,'job_begin',id,{kind,query,opportunity_id,signature,usage_id:access.usageId});r.status(202).json({job:publicJob(j)});
   if(!j.replayed&&!active.has(j.id))void run(u,j);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/jobs/:id',route(async(q,r,u)=>r.json({job:publicJob(await call(u.id,'job_get',uuid(q.params.id)))})));
 return {active};
}
