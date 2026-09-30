import {SeoError,fail,uuid,profileData,text,CREDIT_COST} from './core.mjs';
import {createSeoRunner} from './runner.mjs';

const base='/api/seo-agent';
export function registerSeoAgent(app,{database,requireUser,aiAccess,scan,autoStartScheduler=false,logger=console,runnerOptions={}}={}) {
 const call=async(actor,action,id=null,data={})=>{
  const value=await database.rpc('korlix_seo_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(value.error){
   const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400,'23514':400}[value.error.code];
   if(status)fail(value.error.code==='23505'?'This audit already exists. Refresh its status.':value.error.message,status);
   logger.warn('SEO storage unavailable',{action,code:value.error.code});fail('Your change could not be confirmed. Refresh SEO Agent before retrying.',503);
  }
  return value.data;
 };
 const publicProfile=p=>p?{data:p.data,monitoringEnabled:p.monitoring_enabled,nextRunAt:p.next_run_at,pauseReason:p.pause_reason,updatedAt:p.updated_at}:null;
 const publicRun=r=>({id:r.id,state:r.state,phase:r.phase,result:r.result,progress:r.progress,error:r.error,charged:r.charged,
  createdAt:r.created_at,completedAt:r.completed_at,source:r.source});
 const route=fn=>async(q,r)=>{
  r.set('Cache-Control','no-store');
  try{
   let u;try{u=await requireUser(q);}catch{fail('Sign in to use SEO Agent.',401);}
   if(!u?.id)fail('Sign in to use SEO Agent.',401);
   if(!database)fail('SEO Agent is temporarily unavailable.',503);
   await fn(q,r,u);
  }catch(error){r.status(error instanceof SeoError?error.status:503).json({error:error instanceof SeoError?error.message:'SEO Agent could not finish this request. Please retry.'});}
 };
 const access=async(user,reserved=false)=>{
  const value=await aiAccess(user,{reserved});
  if(!value?.allowed)fail(value?.reason||'SEO Agent requires Ultra Premium or Enterprise.',value?.status||403);
  return value;
 };
 const runner=createSeoRunner({database,call,aiAccess,scan,logger,...runnerOptions});
 app.get(base,route(async(_q,r,u)=>{const data=await call(u.id,'list');r.json({profile:publicProfile(data.profile),runs:data.runs.map(publicRun),creditCost:CREDIT_COST});}));
 app.put(base+'/profile',route(async(q,r,u)=>r.json({profile:publicProfile(await call(u.id,'profile_save',null,profileData(q.body)))})));
 app.put(base+'/monitoring',route(async(q,r,u)=>{
  if(typeof q.body?.enabled!=='boolean')fail('Choose whether weekly monitoring is enabled.');
  if(q.body.enabled){if(q.body.consent!==true)fail('Confirm weekly audits and AI data sharing.');await access(u,true);}
  r.json({profile:publicProfile(await call(u.id,'monitoring',null,{enabled:q.body.enabled,consent:q.body.consent===true}))});
 }));
 app.post(base+'/runs',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key);
  if(q.body?.consent!==true)fail('Confirm AI data sharing before auditing your website.');
  try{return r.json({run:publicRun(await call(u.id,'get',id))});}catch(error){if(error.status!==404)throw error;}
  const value=await access(u);
  const run=await call(u.id,'enqueue',id,{source:'manual',consent:true,usage_id:value.usageId,credit_limit:value.creditLimit,request_limit:value.requestLimit});
  r.status(run.replayed?200:202).json({run:publicRun(run)});runner.kick();
 }));
 app.get(base+'/runs/:id',route(async(q,r,u)=>r.json({run:publicRun(await call(u.id,'get',uuid(q.params.id)))})));
 app.patch(base+'/runs/:id',route(async(q,r,u)=>{
  const id=uuid(q.params.id),run=await call(u.id,'get',id),body=q.body||{};
  if(run.state!=='completed')fail('Wait for a completed audit before updating its actions.',409);
  const allowed=new Set((run.result.ai?.actions||run.result.actions||[]).map(x=>x.id));
  if(!Array.isArray(body.completedActions)||body.completedActions.length>30||body.completedActions.some(x=>!allowed.has(x)))fail('Choose actions from this audit.');
  const data={completedActions:[...new Set(body.completedActions)],notes:text(body.notes,2000,'Progress notes',true)};
  r.json({run:publicRun(await call(u.id,'progress',id,data))});
 }));
 app.delete(base+'/runs/:id',route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before removing this audit.');await call(u.id,'remove',uuid(q.params.id),{confirmed:true});r.json({deleted:true});}));
 app.delete(base,route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before clearing SEO Agent.');await call(u.id,'clear',null,{confirmed:true});r.json({deleted:true});}));
 if(autoStartScheduler&&database)runner.start();
 return {runner,call,start:()=>runner.start(),stop:()=>runner.stop()};
}
