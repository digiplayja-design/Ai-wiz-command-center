import {randomUUID} from 'node:crypto';
import {SeoError, CREDIT_COST} from './core.mjs';

export function createSeoRunner({database, call, aiAccess, scan, logger=console, intervalMs=60000, timeoutMs=240000}={}) {
 const active=new Map();
 let stopped=true,timer=null,ticking=false;
 const pause=async(owner,reason)=>{try{await call(owner,'pause',null,{reason});}catch{logger.warn('SEO monitoring pause could not be saved.');}};
 const userFor=async owner=>{
  const value=await database.auth.admin.getUserById(owner);
  if(value.error||!value.data?.user?.id)throw new SeoError('The account could not be checked. Try again later.',503);
  if(Date.parse(value.data.user.banned_until)>Date.now())throw new SeoError('Monitoring is paused because this account is unavailable.',403);
  return value.data.user;
 };
 const allowance=async(user,reserved=false)=>{
  const access=await aiAccess(user,{reserved});
  if(!access?.allowed)throw new SeoError(access?.reason||'SEO Agent is not currently available for this account.',access?.status||403);
  return access;
 };
 async function processRun(owner,id,abort) {
  let lease;
  try {
   const existing=await call(owner,'get',id);
   if(existing.state!=='queued')return;
   await allowance(await userFor(owner),true);
   lease=randomUUID();
   const job=await call(owner,'claim',id,{lease_token:lease});
   let deadline;
   try {
    const result=await Promise.race([
     Promise.resolve().then(()=>scan({profile:job.input.profile,signal:abort.signal,
      onPhase:phase=>call(owner,'phase',id,{phase,lease_token:lease})})),
     new Promise((_,reject)=>{deadline=setTimeout(()=>{
      abort.abort();reject(new SeoError('The audit took too long. Reserved credits were returned; please retry.',504));
     },timeoutMs);deadline.unref?.();}),
    ]);
    if(abort.signal.aborted)throw new SeoError('The audit was interrupted. Reserved credits were returned.',503);
    await call(owner,'finish',id,{result,lease_token:lease});
   } finally {clearTimeout(deadline);}
  } catch(error) {
   // Another process can win a claim; it alone owns the lease and its result.
   if(error.status===409)return;
   if(error.status===403)await pause(owner,error.message);
   try {await call(owner,'fail',id,{...(lease?{lease_token:lease}:{}),error:error instanceof SeoError?error.message:'The audit could not finish. Reserved credits were returned; please retry.'});}
   catch {logger.warn('SEO audit needs recovery after an interrupted attempt.',{runId:id});}
  }
 }
 function dispatch(owner,id) {
  if(active.has(id)||active.size>=2)return;
  const abort=new AbortController();
  const task=Promise.resolve().then(()=>processRun(owner,id,abort)).finally(()=>active.delete(id));
  active.set(id,{abort,task});
 }
 async function tick() {
  if(ticking||!database)return;
  ticking=true;
  try {
   const found=await database.rpc('korlix_seo_due_v1');
   if(found.error)throw Error('SEO queue unavailable');
   const due=found.data||{};
   for(const row of due.profiles||[]) {
    try {
     const access=await allowance(await userFor(row.user_id));
     await call(row.user_id,'enqueue',randomUUID(),{source:'weekly',usage_id:access.usageId,
      credit_limit:access.creditLimit,request_limit:access.requestLimit});
    } catch(error) {
     if([403,429].includes(error.status))await pause(row.user_id,error.message);
     else if(error.status!==409)logger.warn('SEO weekly audit is waiting for account or storage availability.');
    }
   }
   // Include jobs just enqueued above; each claim is transactional in Postgres.
   const pending=await database.rpc('korlix_seo_due_v1');
   if(pending.error)throw Error('SEO queue unavailable');
   for(const row of pending.data?.runs||[]) {
    if(active.has(row.id))continue;
    await call(row.user_id,'recover');
    if(active.size<2)dispatch(row.user_id,row.id);
   }
  } catch {logger.warn('SEO queue scan unavailable. Stored audits remain queued.');}
  finally {ticking=false;}
 }
 const wake=async()=>{
  if(stopped)return;
  await tick();
  if(!stopped){timer=setTimeout(wake,intervalMs);timer.unref?.();}
 };
 return {
  active, tick,
  kick(){void tick();},
  start(){if(!stopped)return;stopped=false;timer=setTimeout(wake,1000);timer.unref?.();},
  stop(){stopped=true;clearTimeout(timer);timer=null;for(const job of active.values())job.abort.abort();},
  async idle(){await Promise.allSettled([...active.values()].map(job=>job.task));},
  creditCost:CREDIT_COST,
 };
}
