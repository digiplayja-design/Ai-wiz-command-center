import {randomUUID,randomBytes} from 'node:crypto';
import {fail,FunnelError,uuid,text,esc} from './core.mjs';
import {googleDigest,googleChallenge,googleTokenCipher,createGoogleAdsProvider} from './google_ads_provider.mjs';
import {googleDestination,googleDestinationList} from './google_conversion_provider.mjs';
import {googleUploadCallback,googleUploadConfiguration,googleUploadScopes,createGoogleUploadProvider} from './google_upload_provider.mjs';
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const opaque=v=>{if(typeof v!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(v))fail('Start a new Google upload authorization.');return v;};
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
export function registerGoogleUploadAccess(app,{base,owner,limit,database,googleAdsProvider,googleUploadProvider,environment,now=Date.now}){
 const config=googleUploadConfiguration(environment),provider=googleUploadProvider||createGoogleUploadProvider(config,{now}),ads=googleAdsProvider||createGoogleAdsProvider(config.ads,{now});
 const baseData={ads_configured:config.ads.ready&&config.ads.apiVersion==='v25',ads_config_hash:config.ads.hash,configured:config.ready,config_hash:config.hash};
 const binding=(u,id,purpose)=>`korlix-google-upload:${purpose}:${u}:${id}`;
 const context=q=>({...baseData,campaign_id:uuid(q.params.campaign_id)});
 const configured=()=>{if(!config.ready)fail('Google upload authorization is awaiting KORLIX platform setup.',503);};
 const command=async(actor,action,funnel,data)=>{
  if(!database)fail('Google upload authorization storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_google_upload_access_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400,'22007':400,'22008':400}[error.code];fail(status?error.message:'Upload authorization storage is temporarily unavailable. Refresh before retrying.',status||503);}return out;
 };
 const noQuery=q=>{if(Object.keys(q.query).length)fail('Open upload access without extra parameters.');};
 const path=base+'/:id/campaigns/:campaign_id/google-upload-access';
 app.get(base+'/google-upload-access/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:config.ready,send_ready:false,provider_verified:false}));
 app.get(path,owner(async(q,r,u)=>{noQuery(q);r.json(await command(u,'read',uuid(q.params.id),context(q)));},{ratePrefix:'google-upload-read:',max:30}));
 app.post(path+'/begin',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['version','fingerprint','confirmed'])||!Number.isSafeInteger(b.version)||b.version<0||!hash(b.fingerprint)||b.confirmed!==true)fail('Refresh and confirm Google upload authorization first.');
  const funnel=uuid(q.params.id),data=context(q);await command(u,'read',funnel,data);configured();
  const id=randomUUID(),state=randomBytes(32).toString('base64url'),proof=randomBytes(32).toString('base64url'),verifier=randomBytes(32).toString('base64url');
  await command(u,'begin',funnel,{...data,...b,id,state_hash:googleDigest(state),proof_hash:googleDigest(proof),verifier_sealed:googleTokenCipher(config.key).seal(verifier,binding(u,id,'pkce'))});
  r.json({source:'google_upload_authorization',id,proof,authorization_url:provider.authorizationUrl(`${id}.${state}`,googleChallenge(verifier)),expires_in:600});
 },{ratePrefix:'google-upload-write:',max:10}));
 app.get(googleUploadCallback,async(q,r)=>{
  r.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",'X-Content-Type-Options':'nosniff'});
  let consumed,message='Google upload permission received. Return to the original KORLIX window and tap Finish upload authorization.';
  try{
   limit('google-upload-callback:'+q.ip,30);configured();
   if(typeof q.query.state!=='string'||q.query.state.length>100)fail('Start a new Google upload authorization.');
   const pair=q.query.state.split('.');if(pair.length!==2)fail('Start a new Google upload authorization.');
   consumed=await command(null,'consume',null,{...baseData,id:uuid(pair[0]),state_hash:googleDigest(opaque(pair[1]))});
   if(q.query.error)fail('Google upload authorization was cancelled. Return to KORLIX and start again.');
   const verifier=googleTokenCipher(config.key).open(consumed.verifier_sealed,binding(consumed.user_id,consumed.id,'pkce'));
   const result=await provider.exchange(text(q.query.code,4000,true),verifier);
   if(!Array.isArray(result.scopes)||JSON.stringify(result.scopes)!==JSON.stringify(googleUploadScopes)||typeof result.refresh_token!=='string'||result.refresh_token.length<1||result.refresh_token.length>12000||/[\x00-\x20\x7f]/.test(result.refresh_token))fail('Google upload permissions could not be verified. Start again.',409);
   await command(consumed.user_id,'candidate',consumed.funnel_id,{...baseData,campaign_id:consumed.campaign_id,id:consumed.id,scopes:result.scopes,refresh_expires_at:result.refresh_expires_at,sealed:googleTokenCipher(config.key).seal(result.refresh_token,binding(consumed.user_id,consumed.id,'refresh'))});
  }catch(e){if(consumed)try{await command(consumed.user_id,'failed',consumed.funnel_id,{...baseData,campaign_id:consumed.campaign_id,id:consumed.id});}catch{}r.status(e instanceof FunnelError?e.status:503);message=e instanceof FunnelError?e.message:'Google upload authorization could not finish. Return to KORLIX and start again.';}
  r.type('html').send(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX · Google upload access</title><body style="background:#061827;color:#e5f3f8;font:18px system-ui;padding:10vh 8vw"><h1>KORLIX · Google upload access</h1><p>${esc(message)}</p><p>You may close this window. No inquiry was uploaded.</p></body></html>`);
 });
 app.post(path+'/finish',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['id','proof','confirmed'])||b.confirmed!==true)fail('Finish Google upload authorization in its original window.');
  const funnel=uuid(q.params.id),data=context(q),id=uuid(b.id),proof_hash=googleDigest(opaque(b.proof));
  await command(u,'read',funnel,data);configured();
  const a=await command(u,'claim',funnel,{...data,id,proof_hash,confirmed:true});
  try{
   const token=await provider.refresh(googleTokenCipher(config.key).open(a.candidate,binding(u,id,'refresh'))),ctx=a.context;
   const roots=await ads.roots(token);if(!Array.isArray(roots)||!roots.includes(ctx.root_id))fail('This Google sign-in cannot access the selected advertising account. Authorize with an account that can.',409);
   const account=await ads.account(token,ctx.account.id,ctx.login_customer_id);
   if(!account||!['id','name','currency','timezone','manager','status','test_account'].every(k=>account[k]===ctx.account[k])||account.status!=='ENABLED'||account.manager!==false||account.test_account!==false)fail('The selected Google account changed. Refresh its connection and destination.',409);
   const rows=googleDestinationList(await ads.conversionDestinations(token,account,ctx.login_customer_id)),selected=googleDestination(a.destination);
   if(!rows.some(x=>JSON.stringify(x)===JSON.stringify(selected)))fail('The saved conversion action changed or is unavailable to this sign-in. Refresh the destination.',409);
   await command(u,'finish',funnel,{...data,id,checked_at:new Date(now()).toISOString()});
  }catch(e){try{await command(u,'failed',funnel,{...data,id});}catch{}throw e;}
  r.json(await command(u,'read',funnel,data));
 },{ratePrefix:'google-upload-write:',max:10}));
 app.post(path+'/disconnect',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['version','fingerprint','confirmed'])||!Number.isSafeInteger(b.version)||b.version<0||!hash(b.fingerprint)||b.confirmed!==true)fail('Refresh and confirm removing Google upload access.');
  const funnel=uuid(q.params.id),data=context(q);await command(u,'disconnect',funnel,{...data,...b});r.json(await command(u,'read',funnel,data));
 },{ratePrefix:'google-upload-write:',max:10}));
}
