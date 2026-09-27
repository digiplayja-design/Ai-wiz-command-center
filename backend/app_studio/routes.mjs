import {AppStudioError,fail,text,uuid,template,validateSpec} from './model.mjs';
import {exportFiles,zipFiles} from './export.mjs';
export function registerAppStudio(app,{database,requireUser,aiAccess,generate,logger=console}={}){
 const base='/api/app-studio',active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_app_studio_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400}[r.error.code];if(status)fail(r.error.code==='23505'?'This request is already in use. Refresh your projects.':r.error.message,status);logger.warn('App Studio storage unavailable',{action,code:r.error.code});fail('App Studio could not save this change. Refresh before retrying.',503);}if(!r.data)fail('App Studio is temporarily unavailable.',503);return r.data;};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use App Studio.',401);}if(!u?.id)fail('Sign in to use App Studio.',401);if(!database)fail('App Studio is temporarily unavailable.',503);await fn(q,r,u);}catch(e){r.status(e instanceof AppStudioError?e.status:503).json({error:e instanceof AppStudioError?e.message:'App Studio could not finish this request. Refresh before retrying.'});}};
 const version=v=>{if(!Number.isInteger(v)||v<0)fail('Reload your project before saving.');return v;};
 const publicRun=r=>r?{id:r.id,projectId:r.project_id,state:r.state,error:r.error,charged:r.charged,version:r.version,createdAt:r.created_at,message:r.message??r.input?.request?.message??r.input?.message??null}:null;
 const run=async(u,r)=>{active.add(r.id);try{const spec=validateSpec(await generate({input:r.input}));await call(u.id,'run_finish',r.id,{spec});}catch(e){logger.warn('App Studio build failed',{errorType:e.name||'Error'});try{await call(u.id,'run_fail',r.id,{error:e instanceof AppStudioError?e.message:'KORLIX could not finish this build. Your credit was returned. Try again.'});}catch{logger.warn('App Studio build result needs recovery',{requestId:r.id});}}finally{active.delete(r.id);}};
 app.get(base,route(async(_q,r,u)=>r.json({...await call(u.id,'list'),creditCost:1,maxProjects:50,version:1})));
 app.post(base+'/projects',route(async(q,r,u)=>{const b=q.body||{},brief={idea:text(b.idea,5000,'App idea'),audience:text(b.audience,200,'Audience',true),style:text(b.style,120,'Style',true),template:b.template?text(b.template,30,'Starter'):null};const spec=brief.template?template(brief.template):{};r.json({project:await call(u.id,'create',uuid(b.request_key),{name:spec.name||'Untitled app',brief,spec})});}));
 app.get(base+'/projects/:id',route(async(q,r,u)=>{const d=await call(u.id,'get',uuid(q.params.id));r.json({...d,run:publicRun(d.run),previewHtml:d.project.version?exportFiles(validateSpec(d.project.spec),d.project.id,d.project.version,true)['index.html']:null});}));
 app.post(base+'/projects/:id/build',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key),request={projectId:uuid(q.params.id),version:version(q.body?.version),message:text(q.body?.message,5000,'Build instructions')};
  if(q.body?.consent!==true)fail('Allow OpenAI to process this app idea before building.');
  try{const old=await call(u.id,'run_get',id);if(!old.project_id||JSON.stringify(old.input.request)!==JSON.stringify(request)&&Object.keys(request).some(k=>old.input.request?.[k]!==request[k]))fail('Use a new build request after editing your instructions.',409);return r.json({run:publicRun(old)});}catch(e){if(e.status!==404)throw e;}
  if(starting.has(id))fail('This build is starting. Refresh to follow it.',409);
  if(active.size+starting.size>=3)fail('KORLIX is finishing other app builds. Try again shortly.',429);
  starting.add(id);try{const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'Your generation allowance is unavailable.',access?.status||403);
   const job=await call(u.id,'run_begin',id,{request,usage_id:access.usageId,credit_limit:access.creditLimit,request_limit:access.requestLimit});
   r.status(202).json({run:publicRun(job)});if(!job.replayed)void run(u,job);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/runs/:id',route(async(q,r,u)=>r.json({run:publicRun(await call(u.id,'run_get',uuid(q.params.id)))})));
 app.put(base+'/projects/:id/style',route(async(q,r,u)=>{const id=uuid(q.params.id),b=q.body||{},d=await call(u.id,'get',id);if(!d.project.version)fail('Build or choose a starter before styling your app.');const spec=validateSpec({...d.project.spec,name:text(b.name,80,'App name'),accent:b.accent,theme:b.theme});r.json({project:await call(u.id,'save',id,{request_key:uuid(b.request_key),version:version(b.version),spec})});}));
 app.post(base+'/projects/:id/restore',route(async(q,r,u)=>r.json({project:await call(u.id,'restore',uuid(q.params.id),{request_key:uuid(q.body?.request_key),version:version(q.body?.version),version_id:uuid(q.body?.version_id)})})));
 app.delete(base+'/projects/:id',route(async(q,r,u)=>r.json(await call(u.id,'remove',uuid(q.params.id),{confirmed:q.body?.confirmed===true}))));
 app.get(base+'/projects/:id/export',route(async(q,r,u)=>{const d=await call(u.id,'get',uuid(q.params.id));if(!d.project.version)fail('Build or choose a starter before exporting.',409);const files=exportFiles(validateSpec(d.project.spec),d.project.id,d.project.version);r.set('Content-Type','application/zip');r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition',`attachment; filename="KORLIX-App-${d.project.id}-v${d.project.version}.zip"`);r.send(zipFiles(files));}));
 return {call,active};
}
