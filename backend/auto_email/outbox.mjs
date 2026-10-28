import {randomUUID} from 'node:crypto';
import {korlixAgentEmailNovaBinding} from '../korlix_agent_email.mjs';
import {PROVIDERS,UUID,digest,fail,strictBody,mailboxConfig,createMailboxCipher,connectionBinding} from './mailbox-security.mjs';
import {OUTBOX_ROOT,sendingReady,dailyCap,reviewProof,verifyReview,validateMessage,jobPublic} from './outbox-security.mjs';
import {createOutboxStore} from './outbox-store.mjs';
import {usableMailboxTokens,submitMailboxMessage} from './mailbox-delivery.mjs';
const activeRecipient=r=>r?.active&&['transactional_only','marketing_opt_in'].includes(r.consent_status)&&!r.suppressed_at&&!r.unsubscribed_at;
const policyReady=s=>s?.enabled===true&&s.emergency_paused===false&&['approval_required','autopilot'].includes(s.operating_mode);
function snapshotFor(d,m){return{from:m?.identity?.email||null,to:d.to_email,recipientId:d.recipient_id,subject:d.subject,textBody:d.text_body,updatedAt:d.updated_at};}
function eligible(d,r){return d&&['draft','pending_approval'].includes(d.status)&&d.message_kind==='transactional'&&!d.rule_id&&!d.scheduled_at&&d.authorization_type==='none'&&d.attempt_count===0&&!d.provider_message_id&&!d.sent_at&&activeRecipient(r)&&r.email.toLowerCase()===d.to_email.toLowerCase();}
export function registerAutoEmailOutboxRoutes(app,{requireUser,database,loadAgentProfile,store:injectedStore,environment=process.env,now=Date.now,fetcher=fetch,tokenCheck=usableMailboxTokens,submit=submitMailboxMessage,cleanup=true}){
 const store=injectedStore||createOutboxStore(database),config=()=>mailboxConfig(environment);
 async function owner(req){const u=await requireUser(req),b=korlixAgentEmailNovaBinding(environment),device=String(req.headers['x-korlix-device-id']||'');if(!b.configured||String(u?.id||'').toLowerCase()!==b.ownerUid.toLowerCase()||!/^[A-Za-z0-9_-]{16,160}$/.test(device))fail('This account is not enabled for the Auto-Email pilot.',403);const p=await loadAgentProfile({client:database,userId:u.id,agentId:b.agentId});if(!p||p.isCustom!==true||p.active===false||(p.id??p.agent_id)!==b.agentId||!(p.toolIds||p.tool_ids||[]).includes('agent_email'))fail('This email workspace is no longer available.',403);return{user_id:u.id,agent_id:b.agentId,device_hash:digest(device)};}
 async function prepare(c,draftId,provider){
  if(!UUID.test(draftId||'')||!PROVIDERS.includes(provider))fail('Choose a saved draft and a mailbox.',400);
  const{draft,mailbox,settings,recipient}=await store.context(c,draftId,provider);if(!draft)fail('Draft not found.',404);
  const snapshot=snapshotFor(draft,mailbox),blockers=[];
  if(!sendingReady(environment)||!config().providers[provider].available)blockers.push('activation_required');
  if(mailbox?.status!=='connected')blockers.push('mailbox_not_connected');
  if(!policyReady(settings))blockers.push('workspace_paused');
  if(!eligible(draft,recipient))blockers.push('draft_not_eligible');
  if(snapshot.from)validateMessage(snapshot);
  const expiresAt=now()+300000;
  return{draft,mailbox,snapshot,blockers,expiresAt,reviewToken:blockers.length?null:reviewProof(config().key,{...c,draftId,provider,generation:mailbox.generation,snapshotHash:digest(JSON.stringify(snapshot)),expiresAt})};
 }
 async function dispatch(req,c,job){
  let handedOff=false;
  try{
   if(!sendingReady(environment))fail('Sending is paused.',503,'sending_disabled');
   const m=await store.mailbox(c,job);if(!m)fail('This mailbox was disconnected or changed.',409,'mailbox_changed');
   const cfg=config(),cipher=createMailboxCipher(cfg.key),saved=cipher.decrypt(m.secrets,connectionBinding(m));
   const tokens=await tokenCheck(cfg.providers[job.provider],saved,m.scopes,m.identity,{fetcher,now});
   if(!await store.credentials(c,job,cipher.encrypt(tokens,connectionBinding(m))))fail('This mailbox was disconnected or changed.',409,'mailbox_changed');
   await owner(req);
   if(!sendingReady(environment)||!await store.submit(c,job.id))fail('Sending stopped because the mailbox, recipient or workspace changed.',409,'sending_stopped');
   // This durable handoff is deliberately not retried: the provider might accept
   // even if the HTTP response is lost. Disconnect cannot recall a handed-off email.
   handedOff=true;
   const result=await submit(job.provider,tokens.accessToken,job,{fetcher});
   await store.finish(c,job.id,result.status,result.code,result.providerMessageId||null);
  }catch(e){
   const safe=['mailbox_reconnect_required','mailbox_identity_changed','mailbox_check_failed','mailbox_changed','sending_stopped','sending_disabled'].includes(e?.code)?e.code:'preparation_failed';
   try{await store.finish(c,job.id,handedOff?'uncertain':'not_sent',handedOff?'provider_result_unknown':safe);}catch{}
  }
  const final=await store.get(c,job.id);if(!final)fail('Refresh your outbox to check this email. Do not submit another copy.',503,'outbox_result_unknown');return final;
 }
 app.use(OUTBOX_ROOT,async(req,res)=>{
  res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'});
  try{
   const url=new URL(req.originalUrl||req.url,'https://unused.invalid'),path=url.pathname.slice(OUTBOX_ROOT.length),method=req.method;
   if(url.search)fail('Outbox requests do not accept query parameters.',400);
   if(!((path===''&&method==='GET')||(path==='/review'&&method==='POST')||(path==='/submit'&&method==='POST')||(method==='GET'&&UUID.test(path.slice(1)))))fail('Outbox operation not found.',404);
   const c=await owner(req);
   if(method==='GET'){await store.cleanup();if(path==='')return res.json({ok:true,sending:sendingReady(environment),jobs:(await store.list(c)).map(jobPublic)});const j=await store.get(c,path.slice(1));if(!j)fail('Outbox email not found.',404);return res.json({ok:true,job:jobPublic(j)});}
   if(path==='/review'){strictBody(req.body,['draftId','provider']);const p=await prepare(c,req.body.draftId,req.body.provider);return res.json({ok:true,provider:req.body.provider,draftId:req.body.draftId,snapshot:p.snapshot,blockers:p.blockers,reviewToken:p.reviewToken,expiresAt:p.expiresAt});}
   strictBody(req.body,['reviewToken','confirmed']);if(req.body.confirmed!==true)fail('Review and confirm this exact email before sending.',400,'confirmation_required');
   if(!sendingReady(environment))fail('Mailbox sending is awaiting activation.',503,'sending_disabled');
   const proof=verifyReview(config().key,req.body.reviewToken,c,now());
   const existing=await store.findByDraft(c,proof.draftId);if(existing)return res.json({ok:true,replayed:true,job:jobPublic(existing)});
   const p=await prepare(c,proof.draftId,proof.provider);
   if(p.blockers.length||p.mailbox.generation!==proof.generation||digest(JSON.stringify(p.snapshot))!==proof.snapshotHash)fail('The email or mailbox changed. Review the latest version.',409,'review_changed');
   const claimed=await store.claim(c,{id:randomUUID(),draftId:proof.draftId,provider:proof.provider,generation:proof.generation,snapshot:p.snapshot,cap:dailyCap(environment)});
   const j=claimed.claimed?await dispatch(req,c,claimed.job):claimed.job;
   return res.json({ok:true,replayed:!claimed.claimed,job:jobPublic(j)});
  }catch(e){const status=[400,401,403,404,409,502,503].includes(e?.statusCode)?e.statusCode:503;return res.status(status).json({error:status===503&&e.code!=='sending_disabled'?'Your outbox could not confirm this action. Refresh its status before trying again.':e.message,code:e.code||'outbox_unavailable'});}
 });
 let timer;if(cleanup&&database){void store.cleanup().catch(()=>{});timer=setInterval(()=>{void store.cleanup().catch(()=>{});},60000);timer.unref?.();}return{close:()=>clearInterval(timer)};
}
