import {fail,UUID} from '../../web_billing/core.mjs';
import {BRAIN_CATALOG,brainAccountId,productFor} from './catalog.mjs';
import {brainProviders} from './providers.mjs';

export function createBrainBilling({database,requireUser,environment=process.env,provider=brainProviders(environment),fetcher=fetch,autoStart=true,store}={}) {
  const enabled=()=>environment.KORLIX_BRAIN_BILLING_ENABLED==='true';
  const call=store||async function(actor,action,p={}) {
    if(!database)fail('Your minute balance is temporarily unavailable. Please retry.',503);
    const result=await database.rpc('korlix_brain_billing_command',{p_actor:actor||null,p_action:action,p});
    if(result.error){const m=/BILL(\d{3}): (.+)/.exec(result.error.message||'');fail(m?m[2]:'Your minute balance is temporarily unavailable. Please retry.',m?Number(m[1]):503);}
    return result.data;
  };
  async function sync(userId,details) {
    const facts=await provider.verify(details.provider,{...details,userId});
    if(facts.pending)fail('The store is still confirming payment. Tap Restore / retry later.',409);
    const balance=await call(userId,'apply',facts);
    // Durable, idempotent entitlement first; store acknowledgement/consumption second.
    await provider.finish(facts);
    return {verified:true,completePurchase:true,active:facts.active,balance};
  }
  async function refresh(userId) {
    const purchases=await call(userId,'purchases');let warning=null;
    const current=['apple','google'].flatMap(providerName=>purchases.filter(p=>p.kind==='subscription'&&p.provider===providerName).sort((a,b)=>Date.parse(b.expires_at)-Date.parse(a.expires_at)).slice(0,2));
    await Promise.all(current.map(async row => {
      try{await sync(userId,{provider:row.provider,productId:row.product_id,purchaseId:row.provider_token,purchaseToken:row.provider_token});}
      catch{warning='The store could not refresh every purchase. Retry before buying another subscription.';}
    }));
    return warning;
  }
  const rate=new Map();
  const route=fn=>async(req,res)=>{
    res.set('Cache-Control','no-store');
    try{
      const user=await requireUser(req);
      if(!UUID.test(user?.id||'')||!user.email_confirmed_at)fail('Verify your KORLIX email before purchasing.',403);
      const now=Date.now(),previous=rate.get(user.id);
      if(previous&&now<previous.until){if(++previous.n>30)fail('Please wait a minute before retrying.',429);}else rate.set(user.id,{n:1,until:now+60000});
      if(rate.size>10000)for(const[k,v]of rate)if(v.until<now)rate.delete(k);
      await fn(req,res,user);
    }catch(error){res.status(error.statusCode||503).json({error:error.statusCode?error.message:'Store verification is temporarily unavailable. Please retry.'});}
  };
  function register(app) {
    app.get('/api/brain/billing/health',(_req,res)=>res.json({enabled:enabled(),appleReady:!!provider.ready('apple'),googleReady:!!provider.ready('google'),catalogVersion:'brain_monthly_60_gas_60_120_180_v1'}));
    app.get('/api/brain/billing/status',route(async(req,res,u)=>{
      if(!['apple','google'].includes(req.query.provider))fail('Choose your app store.',400);
      const providerName=req.query.provider;
      if(!enabled())return res.json({enabled:false,products:[],balance:null});
      const warning=req.query.refresh==='1'?await refresh(u.id):null;
      res.json({enabled:provider.ready(providerName),products:BRAIN_CATALOG.map(p=>({key:p.key,productId:p[providerName],kind:p.kind,seconds:p.seconds,name:p.name})),balance:await call(u.id,'snapshot'),warning});
    }));
    app.post('/api/brain/billing/prepare',route(async(req,res,u)=>{
      const {provider:providerName,productId}=req.body||{},item=productFor(providerName,productId);
      if(!provider.ready(providerName))fail('Store purchases are being set up. Please try again later.',503);
      if(item.kind==='subscription'){
        const warning=await refresh(u.id);if(warning)fail(warning,503);
        if((await call(u.id,'snapshot')).subscriptionActive)fail('Your Brain+Voice plan is already active. Use Manage subscription.',409);
      }
      res.json({canPurchase:true,accountId:providerName==='apple'?u.id:brainAccountId(u.id)});
    }));
    app.post('/api/brain/billing/verify',route(async(req,res,u)=>{
      const details=req.body||{};productFor(details.provider,details.productId);
      // Existing paid purchases remain verifiable if new purchases are paused.
      res.json(await sync(u.id,details));
    }));
    app.post('/api/brain/billing/apple/notifications',async(req,res)=>{
      try{
        const decoded=await provider.appleNotification(req.body?.signedPayload);
        if(!UUID.test(decoded.appAccountToken||''))fail('Unknown store account.',409);
        await sync(decoded.appAccountToken,{provider:'apple',productId:decoded.productId,purchaseId:decoded.transactionId});
        res.json({accepted:true});
      }catch(error){res.status(error.statusCode||503).json({error:'Store notification could not be applied.'});}
    });
  }
  async function hangup(session) {
    if(!/^rtc_[a-zA-Z0-9_-]{1,160}$/.test(session.call_id||''))return;
    const response=await fetcher(`https://api.openai.com/v1/realtime/calls/${session.call_id}/hangup`,{method:'POST',headers:{Authorization:`Bearer ${environment.OPENAI_API_KEY}`},signal:AbortSignal.timeout(10000),redirect:'error'});
    if(!response.ok&&![404,409,410].includes(response.status))fail('Could not confirm that voice stopped. Please retry.',502);
    if(session.id&&session.user_id)await call(session.user_id,'stopped',{sessionId:session.id});
  }
  async function end(userId,sessionId) {
    const s=await call(userId,'session',{sessionId});
    // Retry provider termination before releasing held minutes. A failed hangup
    // leaves the persistent session visible to the worker, including after restart.
    await hangup(s);
    return call(userId,'end',{sessionId});
  }
  async function reserve(req,user) {
    const reservation=await call(user.id,'reserve');
    req.korlixBrainMeter={userId:user.id,sessionId:reservation.sessionId};
    return {sessionId:reservation.sessionId,reservation,limits:{tier:'brain',monthlySeconds:3600,maxSessionSeconds:reservation.maxSessionSeconds,maxResponses:10000}};
  }
  async function started(req,providerResponse) {
    const meter=req.korlixBrainMeter;if(!meter)return;
    const location=String(providerResponse.headers.get('location')||'');
    const match=location.match(/^(?:https:\/\/api\.openai\.com)?\/v1\/realtime\/calls\/(rtc_[a-zA-Z0-9_-]{1,160})$/);
    if(!match)fail('Could not verify this Live Conversation. Please reconnect.',502);
    try{await call(meter.userId,'start',{sessionId:meter.sessionId,callId:match[1]});}
    catch(e){await hangup({call_id:match[1]}).catch(()=>{});throw e;}
  }
  async function usage(userId,body) {
    let session;
    try{session=await call(userId,'session',{sessionId:body.sessionId});}
    catch(e){
      // BillingError uses status; a non-Brain session continues to its own meter.
      if((e.statusCode ?? e.status)===404)return null;
      throw e;
    }
    if(body.ended===true || Date.parse(session.deadline)<=Date.now())return end(userId,session.id);
    const result=await call(userId,'usage',{sessionId:session.id});
    if(result.limitReached)await hangup(session);
    return result;
  }
  let ticking=false,syncing=false;
  async function tick(){
    if(ticking||!enabled())return;ticking=true;
    try{for(const session of await call(null,'stale_sessions'))await end(session.user_id,session.id).catch(()=>{});}catch{}finally{ticking=false;}
  }
  async function syncDue(){
    if(syncing||!enabled())return;syncing=true;
    try{for(const row of await call(null,'due')){
      try{await sync(row.user_id,{provider:row.provider,productId:row.product_id,purchaseId:row.provider_token,purchaseToken:row.provider_token});}
      catch{await call(row.user_id,'retry_later',{purchase_key:row.purchase_key}).catch(()=>{});}
    }}catch{}finally{syncing=false;}
  }
  const meterTimer=autoStart?setInterval(()=>void tick(),5000):null;meterTimer?.unref();
  const storeTimer=autoStart?setInterval(()=>void syncDue(),60000):null;storeTimer?.unref();
  return {enabled,register,reserve,started,usage,end,sync,tick,syncDue,stop(){clearInterval(meterTimer);clearInterval(storeTimer);}};
}
