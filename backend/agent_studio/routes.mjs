import {WorkflowError,fail,uuid,plan,revision,text} from './model.mjs';

export function registerAgentStudio(app,{database,requireUser,loadContext,aiAccess,generate,logger=console}={}){
 const base='/api/agent-studio/workflows',active=new Map(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{
  const r=await database.rpc('korlix_agent_workflow_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400,'23514':400}[r.error.code];
   if(status)fail(r.error.code==='23505'?'This request already exists. Refresh the workflow.':r.error.message,status);
   logger.warn('Agent workflow storage unavailable',{action,code:r.error.code});fail('This change could not be confirmed. Refresh the workflow before retrying.',503);}
  if(r.data==null)fail('Workflows are temporarily unavailable.',503);return r.data;
 };
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use Agent Studio.',401);}if(!u?.id)fail('Sign in to use Agent Studio.',401);if(!database)fail('Agent Studio is temporarily unavailable.',503);await fn(q,r,u);}catch(e){r.status(e instanceof WorkflowError?e.status:503).json({error:e instanceof WorkflowError?e.message:'Agent Studio could not finish this request. Refresh before retrying.'});}};
 app.get(base,route(async(_q,r,u)=>{await call(u.id,'recover');r.json(await call(u.id,'list'));}));
 app.get(base+'/:id',route(async(q,r,u)=>{await call(u.id,'recover');r.json({workflow:await call(u.id,'get',uuid(q.params.id))});}));
 app.post(base,route(async(q,r,u)=>{
  const data=plan(q.body),id=uuid(q.body?.id);
  for(const agent of new Set(data.steps.map(s=>s.agent_id)))await loadContext(u,agent,false);
  r.status(201).json({workflow:await call(u.id,'create',id,data)});
 }));
 const run=async(user,workflow,context)=>{
  const id=workflow.attempt_id,abort=new AbortController();active.set(id,abort);
  try{const output=await generate({workflow,context,signal:abort.signal});await call(user.id,'finish',workflow.id,{attempt_id:id,output});}
  catch{logger.warn('Agent workflow step failed',{workflowId:workflow.id});try{await call(user.id,'fail',workflow.id,{attempt_id:id});}catch{logger.warn('Agent workflow recovery needed',{workflowId:workflow.id});}}
  finally{active.delete(id);}
 };
 app.post(base+'/:id/run',route(async(q,r,u)=>{
  const id=uuid(q.params.id),attempt_id=uuid(q.body?.attempt_id),rev=revision(q.body);
  try{return r.json({workflow:await call(u.id,'lookup',id,{attempt_id})});}catch(e){if(e.status!==404)throw e;}
  if(starting.has(u.id)||active.size+starting.size>=3)fail('Other agent steps are running. Try again shortly.',429);
  starting.add(u.id);try{
   const workflow=await call(u.id,'get',id),step=workflow.steps[workflow.cursor];
   if(workflow.revision!==rev||!['ready','failed'].includes(workflow.state)||!step)fail('Refresh and review this workflow before running its next step.',409);
   const context=await loadContext(u,step.agent_id,workflow.use_memory);
   const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'Your generation allowance is unavailable.',access?.status||403);
   const started=await call(u.id,'start',id,{revision:rev,attempt_id,agent_version:context.version,usage_id:access.usageId,credit_limit:access.creditLimit,request_limit:access.requestLimit});
   r.status(started.replayed?200:202).json({workflow:started});
   if(!started.replayed)void run(u,started,context);
  }finally{starting.delete(u.id);}
 }));
 app.post(base+'/:id/actions',route(async(q,r,u)=>{
  const id=uuid(q.params.id),action=q.body?.action;
  if(!['approve','revise','pause','resume','cancel','delete'].includes(action))fail('Choose an available workflow action.');
  const data={revision:revision(q.body)};
  if(['approve','cancel','delete'].includes(action)&&q.body?.confirmed!==true)fail('Confirm this workflow action first.');
  if(action==='revise')data.feedback=text(q.body.feedback,2000,'Requested changes',true);
  const workflow=await call(u.id,action,id,data);
  if(action==='cancel')active.get(workflow.attempt_id)?.abort();
  r.json({workflow});
 }));
 return {call,active};
}
