import {randomBytes,createHash} from 'node:crypto';
import {fail,validId} from './core.mjs';
import {createFieldProofEmailProvider,validateTransactionalEmailAddress} from '../fieldproof/email_provider.mjs';
import {verifyKorlixAgentEmailResendWebhook} from '../korlix_agent_email_delivery.mjs';
const digest=t=>createHash('sha256').update(t).digest('hex');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function crmEmailRule(body={}){
 const text=(v,max,multiline=false)=>{if(typeof v!=='string'||!v.trim()||v.trim().length>max||(multiline?/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/:/[\u0000-\u001f\u007f]/).test(v))fail('Enter a valid subject and message.');return v.trim();};
 if(!['review','automatic'].includes(body.delivery_mode)||!Number.isInteger(body.send_hour)||body.send_hour<0||body.send_hour>20)fail('Choose a delivery mode and sending hour.');
 const timezone=text(body.timezone,80);try{new Intl.DateTimeFormat('en',{timeZone:timezone});}catch{fail('Choose a valid timezone.');}
 if(body.version!=null&&(!Number.isInteger(body.version)||body.version<1))fail('Refresh this email rule.');
 return {contact_id:validId(body.contact_id),subject:text(body.subject,200),body:text(body.body,6000,true),timezone,send_hour:body.send_hour,delivery_mode:body.delivery_mode,version:body.version??0};
}
export function createCrmEmails({database,environment=process.env,provider=createFieldProofEmailProvider({environment,namespace:'crm'}),now=Date.now}={}){
 let running=false,stopped=false,timer=null,origin;
 try{const u=new URL(environment.RENDER_EXTERNAL_URL||'https://chee-chai-chee-backend.onrender.com');if(u.protocol==='https:'&&!u.username&&!u.password)origin=u.origin;}catch{}
 const command=async(user,action,p={})=>{if(!database)fail('CRM email is temporarily unavailable.',503);const {data,error}=await database.rpc('korlix_crm_email_v1',{p_actor:user,p_action:action,p});if(error){const m=/CRM(403|404|409)?: (.+)/.exec(error.message||'');fail(m?m[2]:'CRM email is temporarily unavailable. Refresh before trying again.',m?Number(m[1]||400):503);}return data;};
 const identity=async user=>{const result=await database?.auth?.admin?.getUserById(user),u=result?.data?.user;if(result?.error||u?.id!==user||!u.email_confirmed_at||u.is_anonymous||u.deleted_at||(u.banned_until&&Date.parse(u.banned_until)>now()))fail('Verify your account email before enabling CRM emails.',409);return validateTransactionalEmailAddress(u.email);};
 const capabilities=async user=>{let reply;try{reply=await identity(user);}catch{}const ready=!!reply&&!!origin&&provider.status().ready;return {ready,reply_to:reply||null,daily_limit:100,reason:ready?null:!reply?'Verify your account email before enabling CRM emails.':'Email delivery is being configured. You can save paused rules.'};};
 const action=async(user,action,body={})=>{
  if(action==='save')return command(user,'save',crmEmailRule(body));
  if(action==='state')return {...await command(user,'state'),capabilities:await capabilities(user)};
  if(action==='pause_all')return command(user,action);
  if(!['toggle','approve','cancel'].includes(action))fail('Choose a supported email action.');
  if(!Number.isInteger(body.version)||body.version<1)fail('Refresh this email rule or draft first.');
  if(action==='toggle'&&typeof body.enabled!=='boolean')fail('Choose enable or pause.');
  if(action==='approve'||action==='toggle'&&body.enabled){if(body.confirmed!==true)fail('Review and confirm this email first.');const cap=await capabilities(user);if(!cap.ready)fail(cap.reason,409);}
  return command(user,action,{id:validId(body.id),version:body.version,enabled:body.enabled,confirmed:body.confirmed===true});
 };
 async function process(job){
  const reply=await identity(job.user_id),s=provider.status();if(!s.ready||!origin)return;
  const token=randomBytes(32).toString('base64url'),pin={id:job.id,lease_token:job.lease_token,reply_to:reply,sender_fingerprint:s.senderFingerprint};
  const prepared=await command(job.user_id,'prepare',{...pin,token_hash:digest(token),unsubscribe_url:`${origin}/api/contacts/email/unsubscribe/${token}`});if(prepared.blocked)return;
  const claim=await command(job.user_id,'authorize',pin);if(!claim.email_payload)return;
  const finish=p=>command(job.user_id,'finish',{id:job.id,lease_token:job.lease_token,...p});let receipt;
  try{receipt=await provider.send(claim.email_payload);}catch(e){return finish({status:e.outcome==='not_sent'?'blocked':'unknown',code:e.outcome==='not_sent'?'provider_rejected':'provider_outcome_unknown'});}
  if(receipt?.accepted!==true||!uuid.test(receipt.providerId||''))return finish({status:'unknown',code:'provider_receipt_unknown'});
  return finish({status:'sent',code:'accepted_by_email_provider',provider_id:receipt.providerId});
 }
 const tick=async()=>{if(running||stopped||!database)return;running=true;try{await command(null,'tick');if(!provider.status().ready)return;for(let i=0;i<10&&!stopped;i++){const job=await command(null,'claim');if(!job)break;try{await process(job);}catch{console.warn('[CRM email] Delivery needs another status check.');}}}catch{console.warn('[CRM email] Scheduler temporarily unavailable.');}finally{running=false;}};
 return {action,command,capabilities,process,tick,start(){if(!timer&&database){stopped=false;timer=setInterval(()=>void tick(),60000);timer.unref?.();void tick();}},stop(){stopped=true;if(timer)clearInterval(timer);timer=null;},providerEvent:p=>command(null,'provider_event',p),unsubscribe:token=>command(null,'unsubscribe',{token_hash:digest(token)})};
}
export function registerCrmEmailPublicRoutes(app,{service,environment=process.env}){
 app.post('/api/agent-email/resend/webhook',async(req,res,next)=>{let event;try{event=verifyKorlixAgentEmailResendWebhook({rawBody:req.korlixAgentEmailRawBody,headers:req.headers,secret:environment.KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET||environment.RESEND_WEBHOOK_SECRET}).event;}catch(e){return res.status([400,401,503].includes(e.statusCode)?e.statusCode:401).json({error:'Email webhook verification failed.'});}
  if(!['email.delivered','email.bounced','email.complained','email.suppressed'].includes(event?.type)||!uuid.test(event.data?.email_id||''))return next();const tag=event.data?.tags?.crm_delivery;
  try{await service.providerEvent({provider_id:event.data.email_id,id:uuid.test(tag||'')?tag:null,event:event.type});}catch{return res.status(503).json({error:'Email delivery status could not be saved. Retry this webhook.'});}return next();});
 const path='/api/contacts/email/unsubscribe/:token',valid=t=>typeof t==='string'&&/^[A-Za-z0-9_-]{43}$/.test(t);
 const page=(res,body)=>res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; form-action 'self'; frame-ancestors 'none'"}).type('html').send(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX CRM email preferences</title><body><main><h1>KORLIX CRM emails</h1>${body}</main></body></html>`);
 app.get(path,(req,res)=>valid(req.params.token)?page(res,'<p>Stop CRM follow-up emails from this sender to your address.</p><form method="post"><button type="submit">Stop these emails</button></form>'):res.status(404).send('Link not found.'));
 app.post(path,async(req,res)=>{if(!valid(req.params.token))return res.status(404).send('Link not found.');try{await service.unsubscribe(req.params.token);return page(res,'<p>Your request has been processed. If this link was active, future CRM emails from this sender have stopped. An email already sent cannot be recalled.</p>');}catch{return res.status(503).send('Could not save preferences. Please try again.');}});
}
