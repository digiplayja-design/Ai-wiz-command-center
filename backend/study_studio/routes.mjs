import {StudyError,fail,uuid,normalizeInput,validateLesson,studyExport} from './model.mjs';
import {starter} from './starters.mjs';

export function registerStudyStudio(app,{database,requireUser,aiAccess,generate,logger=console}={}){
 const base='/api/study-studio',active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_study_studio_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400}[r.error.code];if(status)fail(r.error.code==='23505'?'This request is already in use. Refresh My learning.':r.error.message,status);logger.warn('Study Studio storage unavailable',{action,code:r.error.code});fail('Your progress could not be confirmed. Refresh before retrying.',503);}if(!r.data)fail('Study Studio is temporarily unavailable.',503);return r.data;};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use Study Studio.',401);}if(!u?.id)fail('Sign in to use Study Studio.',401);if(!database)fail('Study Studio is temporarily unavailable.',503);await fn(q,r,u);}catch(e){r.status(e instanceof StudyError?e.status:503).json({error:e instanceof StudyError?e.message:'Study Studio could not finish this request. Refresh before retrying.'});}};
 const run=async(u,id,input)=>{active.add(id);try{const lesson=validateLesson(await generate({input}));await call(u.id,'finish',id,{lesson});}catch(e){logger.warn('Study Studio generation failed',{errorType:e.name||'Error'});try{await call(u.id,'fail',id,{error:(e instanceof StudyError?e.message:'KORLIX could not finish this study pack.')+' Your credit was returned.'});}catch{logger.warn('Study Studio result needs recovery',{requestId:id});}}finally{active.delete(id);}};
 app.get(base,route(async(_q,r,u)=>r.json({...await call(u.id,'list'),creditCost:1,maxSets:50,version:1})));
 app.post(base+'/sets',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key),input=normalizeInput(q.body||{});
  if(!input.starter&&q.body?.consent!==true)fail('Allow OpenAI to process the topic and pasted notes before creating a study pack.');
  try{return r.json({set:await call(u.id,'lookup',id,{input})});}catch(e){if(e.status!==404)throw e;}
  if(input.starter)return r.json({set:await call(u.id,'create',id,{input,lesson:starter(input.starter)})});
  if(starting.has(id))fail('This pack is starting. Refresh My learning to follow it.',409);
  if(active.size+starting.size>=3)fail('KORLIX is preparing other study packs. Try again shortly.',429);
  starting.add(id);try{const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'Your generation allowance is unavailable.',access?.status||403);
   const set=await call(u.id,'create',id,{input,usage_id:access.usageId,credit_limit:access.creditLimit,request_limit:access.requestLimit});
   r.status(set.replayed?200:202).json({set});if(!set.replayed)void run(u,id,input);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/sets/:id',route(async(q,r,u)=>r.json({set:await call(u.id,'get',uuid(q.params.id))})));
 app.put(base+'/sets/:id/progress',route(async(q,r,u)=>{
  const b=q.body||{},data={request_key:uuid(b.request_key),revision:b.revision,event:b.event};
  if(!Number.isInteger(data.revision)||data.revision<0||!['read','card','answer','resetQuiz'].includes(data.event))fail('Refresh this study pack before saving progress.');
  if(data.event!=='resetQuiz'){if(!Number.isInteger(b.index)||b.index<0||b.index>11)fail('Choose an available study item.');data.index=b.index;}
  if(data.event==='card'){if(!['again','known'].includes(b.rating))fail('Choose a flashcard rating.');data.rating=b.rating;}
  if(data.event==='answer'){if(!Number.isInteger(b.choice)||b.choice<0||b.choice>3)fail('Choose an available answer.');data.choice=b.choice;}
  if(data.event==='resetQuiz')data.confirmed=b.confirmed===true;
  r.json({set:await call(u.id,'progress',uuid(q.params.id),data)});
 }));
 app.delete(base+'/sets/:id',route(async(q,r,u)=>r.json(await call(u.id,'remove',uuid(q.params.id),{confirmed:q.body?.confirmed===true}))));
 app.get(base+'/sets/:id/export',route(async(q,r,u)=>{const s=await call(u.id,'get',uuid(q.params.id));if(s.state!=='ready')fail('Wait until this study pack is ready.',409);r.set('Content-Type','text/plain; charset=utf-8');r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition',`attachment; filename="KORLIX-Study-${s.id}.txt"`);r.send(studyExport(s));}));
 return {call,active};
}
