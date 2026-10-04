import { randomBytes, createHash } from 'node:crypto';
import { fail, id, text, integer } from './core.mjs';
import { createFieldProofEmailProvider, validateTransactionalEmailAddress } from '../fieldproof/email_provider.mjs';
import { verifyKorlixAgentEmailResendWebhook } from '../korlix_agent_email_delivery.mjs';

const digest = token => createHash('sha256').update(token).digest('hex');
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function workforceEmailAddress(value) {
  try { return validateTransactionalEmailAddress(value).toLowerCase(); }
  catch { fail('Enter one valid email address.'); }
}
export function createWorkforceEmails({database, environment=process.env, provider=createFieldProofEmailProvider({environment,namespace:'workforce'}), now=Date.now}={}) {
  let origin;
  try { const url=new URL(environment.RENDER_EXTERNAL_URL || 'https://chee-chai-chee-backend.onrender.com'); if(url.protocol==='https:'&&!url.username&&!url.password) origin=url.origin; } catch {}
  const cmd=async(actor,action,org,p={})=>{
    if(!database) fail('Workforce email is unavailable.',503,'WORKFORCE_EMAIL_UNAVAILABLE');
    const {data,error}=await database.rpc('korlix_workforce_email_v1',{p_actor:actor,p_action:action,p_org:org,p});
    if(error){const match=/WF(403|404|409)?: (.+)/.exec(error.message||''); if(match) fail(match[2],Number(match[1]||400),'WORKFORCE_EMAIL_INVALID'); fail('Workforce email is temporarily unavailable. Refresh before trying again.',503,'WORKFORCE_EMAIL_UNAVAILABLE');}
    return data;
  };
  const identity=async user=>{
    const result=await database?.auth?.admin?.getUserById(user), account=result?.data?.user;
    if(result?.error||!account||account.id!==user||!account.email_confirmed_at||account.is_anonymous||account.deleted_at||(account.banned_until&&Date.parse(account.banned_until)>now())) fail('Verify your account email before sending Workforce emails.',403,'WORKFORCE_EMAIL_IDENTITY_REQUIRED');
    return workforceEmailAddress(account.email);
  };
  async function capabilities(user){
    let reply=null;try{reply=await identity(user);}catch{}
    const ready=provider.status().ready && !!reply && !!origin;
    return {ready,reply_to:reply,reason:!reply?'Verify your account email before sending Workforce emails.':ready?null:'Email delivery is being configured. You can save paused rules.',daily_limit:100};
  }
  async function process(rule,job,done){
    const user=rule.owner_id,org=rule.org_id,reply=await identity(user),status=provider.status();
    const token=randomBytes(32).toString('base64url');
    let prepared=await cmd(user,'prepare',org,{job_id:job.id,lease_token:job.lease_token,reply_to:reply,sender_fingerprint:status.senderFingerprint,
      token_hash:digest(token),unsubscribe_url:`${origin}/api/workforce/email/unsubscribe/${token}`});
    if(prepared.status==='draft') return;
    if(!status.ready||!origin) return done('pending','email_provider_unavailable',{retry_seconds:300});
    // This is the final database authorization before the provider request. The
    // exact payload, recipient/version, owner approval, window and quota are pinned.
    const claim=await cmd(user,'authorize',org,{job_id:job.id,lease_token:job.lease_token,reply_to:reply,sender_fingerprint:status.senderFingerprint});
    if(claim.deferred) return done('pending','outside_sending_window_or_daily_limit',{retry_seconds:300});
    const finish=p=>cmd(user,'finish',org,{job_id:job.id,lease_token:job.lease_token,...p});
    let receipt;
    try {receipt=await provider.send(claim.email_payload);}
    catch(e){
      const uncertain=e.outcome!=='not_sent';
      return finish({status:uncertain?'unknown':e.retryable&&job.attempts<5?'pending':'blocked',code:uncertain?'provider_outcome_unknown':'provider_rejected',retry_seconds:e.retryAfterSeconds||300});
    }
    // A lost persistence response must never turn a successful provider call into
    // a new send. A stale sending lease becomes unknown, requiring reconciliation.
    if(receipt?.accepted!==true||!uuid.test(receipt.providerId||'')) return finish({status:'unknown',code:'provider_receipt_unknown'});
    return finish({status:'sent',code:'accepted_by_email_provider',provider_id:receipt.providerId});
  }
  const recipientAction=async(user,org,action,body={})=>{
    if(action==='add')return cmd(user,'add',org,{id:id(body.id),name:text(body.name,100,true),email:workforceEmailAddress(body.email),confirmed:body.confirmed===true});
    if(action==='revoke')return cmd(user,'revoke',org,{id:id(body.id)});
    return cmd(user,'recipients',org);
  };
  const review=async(user,org,body={})=>{
    if(!['approve','cancel'].includes(body.action))fail('Choose approve or cancel.');
    if(body.action==='approve') {const cap=await capabilities(user);if(!cap.ready)fail(cap.reason,409,'WORKFORCE_EMAIL_UNAVAILABLE');}
    return cmd(user,body.action,org,{job_id:id(body.job_id),version:integer(body.version,1,2147483646),confirmed:body.confirmed===true});
  };
  return {capabilities,process,recipientAction,review,
    providerEvent:p=>cmd(null,'provider_event',null,p),
    unsubscribe:token=>cmd(null,'unsubscribe',null,{token_hash:digest(token)}),
    providerReady:()=>provider.status().ready,
  };
}

// Must be registered before the shared Agent Email webhook handler.
export function registerWorkforceEmailPublicRoutes(app,{service,environment=process.env}={}){
  app.post('/api/agent-email/resend/webhook',async(req,res,next)=>{
    let event;
    try{event=verifyKorlixAgentEmailResendWebhook({rawBody:req.korlixAgentEmailRawBody,headers:req.headers,
      secret:environment.KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET||environment.RESEND_WEBHOOK_SECRET}).event;}
    catch(e){return res.status([400,401,503].includes(e.statusCode)?e.statusCode:401).json({error:'Email webhook verification failed.'});}
    if(!['email.delivered','email.bounced','email.complained','email.suppressed'].includes(event?.type)||!uuid.test(event.data?.email_id||''))return next();
    const tag=event.data?.tags?.workforce_delivery;
    try{await service.providerEvent({provider_id:event.data.email_id,job_id:uuid.test(tag||'')?tag:null,event:event.type});}
    catch{return res.status(503).json({error:'Email delivery status could not be saved. Retry this webhook.'});}
    return next();
  });
  const path='/api/workforce/email/unsubscribe/:token';
  const valid=t=>typeof t==='string'&&/^[A-Za-z0-9_-]{43}$/.test(t);
  const page=(res,body)=>res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; form-action 'self'; frame-ancestors 'none'"}).type('html').send(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX email preferences</title><body><main><h1>KORLIX Workforce emails</h1>${body}</main></body></html>`);
  app.get(path,(req,res)=>valid(req.params.token)?page(res,'<p>Stop Workforce emails from this workspace to your address.</p><form method="post"><button type="submit">Stop these emails</button></form>'):res.status(404).send('Link not found.'));
  app.post(path,async(req,res)=>{
    if(!valid(req.params.token))return res.status(404).send('Link not found.');
    try{await service.unsubscribe(req.params.token);return page(res,'<p>Your request has been processed. If this link was active, future emails from this workspace have stopped. An email already sent cannot be recalled.</p>');}
    catch{return res.status(503).send('Could not save email preferences. Please try again.');}
  });
}
