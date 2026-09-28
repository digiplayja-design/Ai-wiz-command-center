import {DefenderError,fail,uuid,normalizeInput,fingerprint,details,quickCheck,validateReview,reportExport} from './model.mjs';
import {catalog,HABITS} from './catalog.mjs';
export function registerCyberDefender(app,{database,requireUser,aiAccess,generate,logger=console}={}){
 const base='/api/cyber-defender',active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_cyber_defender_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400}[r.error.code];if(status)fail(r.error.code==='23505'?'This request is already in use. Refresh Saved reports.':r.error.message,status);logger.warn('Defender storage unavailable',{action,code:r.error.code});fail('Your change could not be confirmed. Refresh before retrying.',503);}if(!r.data)fail('Cybersecurity Defender is temporarily unavailable.',503);return r.data;};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use Cybersecurity Defender.',401);}if(!u?.id)fail('Sign in to use Cybersecurity Defender.',401);if(!database)fail('Cybersecurity Defender is temporarily unavailable.',503);await fn(q,r,u);}catch(e){r.status(e instanceof DefenderError?e.status:503).json({error:e instanceof DefenderError?e.message:'Cybersecurity Defender could not finish this request. Refresh before retrying.'});}};
 const run=async(u,id,input)=>{active.add(id);try{const review=validateReview(await generate({input}));await call(u.id,'finish',id,{review});}catch{logger.warn('Defender review failed',{requestId:id});try{await call(u.id,'fail',id);}catch{logger.warn('Defender review needs recovery',{requestId:id});}}finally{active.delete(id);}};
 app.get(base,route(async(_q,r,u)=>r.json({...await call(u.id,'list'),...catalog(),creditCost:1,maxReports:50,version:1})));
 app.post(base+'/reports',route(async(q,r,u)=>{
  const id=uuid(q.body?.request_key),input=normalizeInput(q.body||{}),request_hash=fingerprint(input);
  if(input.mode==='ai'&&q.body?.consent!==true)fail('Allow OpenAI to process this text before starting a deeper review.');
  try{return r.json({report:await call(u.id,'lookup',id,{request_hash})});}catch(e){if(e.status!==404)throw e;}
  const result=quickCheck(input),data={request_hash,details:details(input),result};
  if(input.mode==='quick')return r.json({report:await call(u.id,'create',id,data)});
  if(starting.has(id))fail('This review is starting. Refresh Saved reports to follow it.',409);
  if(active.size+starting.size>=3)fail('KORLIX is reviewing other messages. Try the free quick check or return shortly.',429);
  starting.add(id);try{const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'Your generation allowance is unavailable.',access?.status||403);
   const report=await call(u.id,'create',id,{...data,usage_id:access.usageId,credit_limit:access.creditLimit,request_limit:access.requestLimit});
   r.status(report.replayed?200:202).json({report});if(!report.replayed)void run(u,id,input);
  }finally{starting.delete(id);}
 }));
 const event=b=>{const data={request_key:uuid(b?.request_key),revision:b?.revision,key:b?.key};if(!Number.isInteger(data.revision)||data.revision<0||typeof data.key!=='string'||data.key.length>30)fail('Refresh before saving this change.');return data;};
 app.put(base+'/checklist',route(async(q,r,u)=>{const b=q.body||{},data=event(b);if(data.key==='mode'){if(!['personal','business'].includes(b.mode))fail('Choose Personal or Business.');data.mode=b.mode;}else{if(!HABITS.some(h=>h.id===data.key)||typeof b.checked!=='boolean')fail('Choose an available checklist item.');data.checked=b.checked;}r.json(await call(u.id,'checklist',null,data));}));
 app.get(base+'/reports/:id',route(async(q,r,u)=>r.json({report:await call(u.id,'get',uuid(q.params.id))})));
 app.put(base+'/reports/:id/progress',route(async(q,r,u)=>{const b=q.body||{},data=event(b);if(typeof b.checked!=='boolean')fail('Choose an action to update.');data.checked=b.checked;r.json({report:await call(u.id,'progress',uuid(q.params.id),data)});}));
 app.delete(base+'/reports/:id',route(async(q,r,u)=>r.json(await call(u.id,'remove',uuid(q.params.id),{confirmed:q.body?.confirmed===true}))));
 app.get(base+'/reports/:id/export',route(async(q,r,u)=>{const row=await call(u.id,'get',uuid(q.params.id));r.set('Content-Type','text/plain; charset=utf-8');r.set('X-Content-Type-Options','nosniff');r.set('Content-Disposition',`attachment; filename="KORLIX-Defender-${row.id}.txt"`);r.send(reportExport(row));}));
 return {call,active};
}
