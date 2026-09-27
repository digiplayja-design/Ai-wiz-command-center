import {VisibilityError,fail,text,uuid,profileData,CREDIT_COST} from './ai.mjs';
const base='/api/ai-visibility';
export function registerAiVisibility(app,{database,requireUser,aiAccess,scan,logger=console}={}){
 const active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_visibility_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'54000':429,P0001:400,'42501':403}[r.error.code];if(status)fail(r.error.message,status);logger.warn('AI Visibility storage unavailable',{action,code:r.error.code});fail('AI Visibility storage is temporarily unavailable. Your entries remain here; retry shortly.',503);}return r.data;};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const u=await requireUser(q);if(!u?.id)fail('Sign in to use AI Visibility.',401);if(!database)fail('AI Visibility is temporarily unavailable.',503);await fn(q,r,u);}catch(e){const status=e instanceof VisibilityError?e.status:e.statusCode===401?401:503;r.status(status).json({error:e instanceof VisibilityError?e.message:status===401?'Sign in again to use AI Visibility.':'AI Visibility could not finish this request. Please retry.'});}};
 const publicRun=r=>({id:r.id,state:r.state,phase:r.phase,result:r.result,progress:r.progress,error:r.error,charged:r.charged,createdAt:r.created_at,completedAt:r.completed_at});
 const run=async(u,r)=>{active.add(r.id);try{const result=await scan({...r.input,onPhase:phase=>call(u.id,'run_phase',r.id,{phase})});await call(u.id,'run_finish',r.id,{result});}
  catch(e){logger.warn('AI Visibility scan failed',{errorType:e.name||'Error'});try{await call(u.id,'run_fail',r.id,{error:e instanceof VisibilityError?e.message:'KORLIX could not finish this scan. No credits were charged. Please retry.'});}catch{logger.warn('AI Visibility failure status could not be saved');}}finally{active.delete(r.id);}};
 app.get(base,route(async(_q,r,u)=>{const d=await call(u.id,'list');r.json({profile:d.profile?{data:d.profile.data,updatedAt:d.profile.updated_at}:null,runs:d.runs.map(publicRun),creditCost:CREDIT_COST});}));
 app.put(base+'/profile',route(async(q,r,u)=>{const p=await call(u.id,'profile_save',null,profileData(q.body));r.json({profile:{data:p.data,updatedAt:p.updated_at}});}));
 app.post(base+'/runs',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key);if(q.body?.consent!==true)fail('Confirm AI data sharing before running a visibility scan.');
  try{return r.json({run:publicRun(await call(u.id,'run_get',id))});}catch(e){if(e.status!==404)throw e;}
  if(active.size+starting.size>=2)fail('KORLIX is finishing other visibility scans. Please retry shortly.',429);
  if(starting.has(id))fail('This scan is starting. Refresh to follow it.',409);
  starting.add(id);try{const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'AI Visibility scans require Ultra Premium or Enterprise.',access?.status||403);
   const job=await call(u.id,'run_begin',id,{usage_id:access.usageId});r.status(202).json({run:publicRun(job)});if(!job.replayed&&!active.has(job.id))void run(u,job);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/runs/:id',route(async(q,r,u)=>r.json({run:publicRun(await call(u.id,'run_get',uuid(q.params.id)))})));
 app.patch(base+'/runs/:id',route(async(q,r,u)=>{
  const id=uuid(q.params.id),run=await call(u.id,'run_get',id),v=q.body||{};
  if(run.state!=='completed')fail('Wait for a completed report before updating progress.',409);
  const ids=new Set((run.result.actions||[]).map(x=>x.id));
  if(!Array.isArray(v.completedActions)||v.completedActions.length>6||v.completedActions.some(x=>!ids.has(x)))fail('Choose actions from this report.');
  if(!Number.isInteger(v.inquiries)||v.inquiries<0||v.inquiries>1000000||!Number.isInteger(v.bookings)||v.bookings<0||v.bookings>1000000)fail('Enter whole-number inquiries and bookings between 0 and 1,000,000.');
  const data={completedActions:[...new Set(v.completedActions)],inquiries:v.inquiries,bookings:v.bookings,notes:text(v.notes,2000,'Progress notes',true)};
  r.json({run:publicRun(await call(u.id,'progress',id,data))});
 }));
 app.delete(base+'/runs/:id',route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before removing this report.');await call(u.id,'remove',uuid(q.params.id));r.json({deleted:true});}));
 app.delete(base,route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before clearing AI Visibility.');await call(u.id,'clear');r.json({deleted:true});}));
 return {active};
}
