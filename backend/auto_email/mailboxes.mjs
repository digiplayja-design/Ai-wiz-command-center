import {randomUUID} from 'node:crypto';
import {korlixAgentEmailNovaBinding} from '../korlix_agent_email.mjs';
import {MAILBOX_ROOT,PROVIDERS,UUID,FLOW_MS,OAUTH_COOKIE,fail,digest,opaque,mailboxConfig,createMailboxCipher,browserProof,verifyBrowserProof,cookieValue,flowBinding,connectionBinding,strictBody} from './mailbox-security.mjs';
import {authorizationUrl,exchangeMailboxCode} from './mailbox-providers.mjs';
import {createMailboxStore} from './mailbox-store.mjs';
const labels={google:'Gmail / Google Workspace',microsoft:'Microsoft 365'};
const safeIdentity=value=>value?{email:value.email,displayName:value.displayName,accountId:value.accountId}:null;
function headers(res){res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});}
const htmlEsc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function failurePage(res,appOrigin){return res.status(400).type('html').send(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX mailbox connection</title><style>body{background:#f5f3ed;color:#17251c;font:16px/1.7 system-ui;max-width:520px;margin:12vh auto;padding:28px}small{letter-spacing:3px}h1{font:38px/1.15 Georgia}a{display:inline-block;background:#17251c;color:#fff;padding:12px 20px;border-radius:6px;text-decoration:none}</style><small>KORLIX AUTO-EMAIL BY VOICE</small><h1>Let’s reconnect securely.</h1><p>This mailbox connection could not be completed. Return to your workspace and start again in the same browser tab.</p><a href="${htmlEsc(appOrigin||'https://korlix-auto-email-by-voice.silkyhinny128.chatgpt.site')}#connections">Return to KORLIX</a></html>`);}
export function registerAutoEmailMailboxRoutes(app,{requireUser,database,store:injectedStore,environment=process.env,fetcher=fetch,now=Date.now,exchange=exchangeMailboxCode,cleanup=true}){
 const store=injectedStore||createMailboxStore(database);
 const config=()=>mailboxConfig(environment);
 function provider(id){if(!PROVIDERS.includes(id))fail('Mailbox provider not found.',404);const c=config().providers[id];if(!c.available)fail('Mailbox connections are awaiting activation for this pilot.',503,'mailbox_setup_required');return c;}
 async function owner(req){const u=await requireUser(req),binding=korlixAgentEmailNovaBinding(environment);if(!binding.configured||binding.ownerUid.toLowerCase()!==String(u?.id||'').toLowerCase())fail('This account is not enabled for the Auto-Email pilot.',403);const d=String(req.headers['x-korlix-device-id']||'');if(!/^[A-Za-z0-9_-]{16,160}$/.test(d))fail('Sign in again on this device.',403);return{user_id:u.id,agent_id:binding.agentId,device_hash:digest(d)};}
 async function flowFor(c,id){if(!UUID.test(id))fail('Mailbox attempt not found.',404);const f=await store.getFlow(c,id);if(!f)fail('Mailbox attempt not found.',404);return f;}
 async function callback(req,res,id,url){
  const c=provider(id),params=url.searchParams;
  if([...params.keys()].some(k=>params.getAll(k).length!==1)||!/^[-_A-Za-z0-9]{43}$/.test(params.get('state')||''))return failurePage(res,config().appOrigin);
  const cookie=cookieValue(req.headers.cookie);if(!cookie)return failurePage(res,config().appOrigin);
  const flow=await store.claim(id,digest(params.get('state')),digest(cookie),now());if(!flow)return failurePage(res,config().appOrigin);
  res.set('Set-Cookie',`${OAUTH_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`);
  try{
   if(params.has('error'))fail('Mailbox access was not approved.',400,'mailbox_consent_declined');
   const code=params.get('code');if(!code||code.length>4096||/[\x00-\x1f]/.test(code))fail('Mailbox authorization is incomplete.',400,'mailbox_code_invalid');
   const cipher=createMailboxCipher(config().key),saved=cipher.decrypt(flow.secrets,flowBinding(flow));
   const result=await exchange(c,code,saved.verifier,{fetcher,now});
   const completed=await store.complete(flow,{status:'review',secrets:cipher.encrypt(result.tokens,flowBinding(flow)),identity:result.identity,scopes:result.scopes,browser_hash:null},now());
   if(!completed)return failurePage(res,config().appOrigin);
  }catch(e){await store.complete(flow,{status:'error',secrets:null,identity:null,browser_hash:null,error_code:e.code==='mailbox_consent_declined'?'consent_declined':'provider_failed'},now());}
  return res.redirect(303,`${config().appOrigin}/#mailbox_result=${flow.id}`);
 }
 app.use(MAILBOX_ROOT,async(req,res)=>{
  headers(res);
  const raw=String(req.originalUrl||req.url||''),url=new URL(raw,'https://unused.invalid'),path=url.pathname.slice(MAILBOX_ROOT.length),method=req.method;
  const oauth=path.match(/^\/oauth\/(google|microsoft)\/(bootstrap|callback)$/);
  try{
   if(oauth&&method==='GET'){
    const [,id,action]=oauth;
    if(action==='callback')return await callback(req,res,id,url);
    if(url.search)fail('Start this connection from your workspace.');provider(id);
    const cookie=opaque(),proof=browserProof(config().key,{provider:id,browserHash:digest(cookie),expiresAt:now()+3*60*1000});
    res.set('Set-Cookie',`${OAUTH_COOKIE}=${cookie}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=900`);
    return res.redirect(303,`${config().appOrigin}/#mailbox_start=${id}&proof=${proof}`);
   }
   if(url.search)fail('Mailbox requests do not accept query parameters.');
   const route=path.match(/^\/(google|microsoft)\/(authorize|disconnect)$/),flowRoute=path.match(/^\/flows\/([0-9a-f-]{36})(?:\/(confirm|cancel))?$/i);
   if(!((path===''||path==='/')&&method==='GET')&&!(route&&method==='POST')&&!(flowRoute&&((!flowRoute[2]&&method==='GET')||(flowRoute[2]&&method==='POST'))))fail('Mailbox operation not found.',404);
   const c=await owner(req);
   if(path===''||path==='/'){
    await store.cleanup();const rows=await store.list(c);
    return res.json({ok:true,sending:false,providers:PROVIDERS.map(id=>{const row=rows.find(r=>r.provider===id),p=config().providers[id];return{id,label:labels[id],available:p.available,bootstrapUrl:p.available?`${config().apiOrigin}${MAILBOX_ROOT}/oauth/${id}/bootstrap`:null,connection:row?.status==='connected'?{connected:true,identity:safeIdentity(row.identity),connectedAt:row.connected_at}:{connected:false}};})});
   }
   if(route){const [,id,action]=route;
    if(action==='disconnect'){strictBody(req.body,[]);await store.disconnect(c,id);return res.json({ok:true,disconnected:true,providerConsentRemoved:false});}
    strictBody(req.body,['browserProof']);const p=provider(id),browserHash=verifyBrowserProof(config().key,req.body.browserProof,id,now());
    const state=opaque(),verifier=opaque(),flow={...c,id:randomUUID(),provider:id,state_hash:digest(state),browser_hash:browserHash};flow.secrets=createMailboxCipher(config().key).encrypt({verifier},flowBinding(flow));
    await store.cleanup();const started=await store.begin(flow);
    return res.json({ok:true,flowId:flow.id,expiresAt:started.expiresAt,authorizationUrl:authorizationUrl(p,{state,verifier})});
   }
   const [,id,action]=flowRoute,f=await flowFor(c,id),expired=Date.parse(f.expires_at)<=now();
   if(!action)return res.json({ok:true,flowId:id,provider:f.provider,status:expired&&['pending','exchanging','review'].includes(f.status)?'expired':f.status,identity:!expired&&f.status==='review'?safeIdentity(f.identity):null,errorCode:f.error_code||null,sending:false});
   if(action==='cancel'){strictBody(req.body,[]);if(f.status==='confirmed')fail('This mailbox is already connected. Use Disconnect to remove it.',409,'mailbox_already_connected');await store.cancel(c,id);return res.json({ok:true,cancelled:true});}
   strictBody(req.body,['accountId']);provider(f.provider);
   if(expired||f.status!=='review'||!f.identity||req.body.accountId!==f.identity.accountId)fail('Review a fresh mailbox connection before confirming.',409,'mailbox_review_required');
   const cipher=createMailboxCipher(config().key),tokens=cipher.decrypt(f.secrets,flowBinding(f));
   const confirmed=await store.confirm(c,id,cipher.encrypt(tokens,connectionBinding(f)));
   if(!confirmed?.confirmed)fail('This connection was cancelled or replaced. Please start again.',409,'mailbox_attempt_replaced');
   return res.json({ok:true,connected:true,provider:f.provider,identity:safeIdentity(confirmed.identity),sending:false});
  }catch(error){if(oauth)return failurePage(res,config().appOrigin);const status=[400,401,403,404,409,502,503].includes(error?.statusCode)?error.statusCode:503;return res.status(status).json({error:status===503&&error.code!=='mailbox_setup_required'?'Mailbox connections are temporarily unavailable. Please retry.':error.message||'Mailbox connection could not be completed.',code:error.code||'mailbox_unavailable'});}
 });
 // Best-effort cleanup resumes after a process restart; expired flows cannot be
 // used even before cleanup runs. No tokens are sent to an email provider here.
 let timer;if(cleanup&&database){void store.cleanup().catch(()=>{});timer=setInterval(()=>{void store.cleanup().catch(()=>{});},60000);timer.unref?.();}
 return {close:()=>clearInterval(timer)};
}
