import {fail,FunnelError} from './core.mjs';
import {googleAdsConfiguration,googleAdsScope,googleDigest} from './google_ads_provider.mjs';
export const googleUploadCallback='/api/funnels/google-upload-access/callback';
export const googleUploadScopes=Object.freeze([googleAdsScope,'https://www.googleapis.com/auth/datamanager']);
export function googleUploadConfiguration(env={}){
 const ads=googleAdsConfiguration(env),callback=env.KORLIX_GOOGLE_UPLOAD_REDIRECT_URI||'';let valid=false;
 try{const u=new URL(callback);valid=u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname===googleUploadCallback;}catch{}
 return {ads,callback,id:ads.id,secret:ads.secret,key:ads.key,ready:ads.ready&&ads.apiVersion==='v25'&&env.KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED==='true'&&valid,hash:googleDigest(JSON.stringify(['google-upload-access-v1',ads.hash,callback,googleUploadScopes]))};
}
export class GoogleUploadAccessError extends FunnelError{constructor(){super('Google upload permission expired or was removed. Authorize upload access again.',409);}}
const validToken=t=>typeof t==='string'&&t.length>0&&t.length<=12000&&!/[\x00-\x20\x7f]/.test(t);
export function createGoogleUploadProvider(config,{fetchImpl=fetch,now=Date.now}={}){
 async function token(values,initial){
  let response,body;
  try{
   response=await fetchImpl(new URL('https://oauth2.googleapis.com/token'),{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.id,client_secret:config.secret,...values}).toString(),redirect:'error',signal:AbortSignal.timeout(10000)});
   const reader=response.body?.getReader();if(!reader)throw Error();const parts=[];let size=0;
   try{for(;;){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>128*1024)throw Error();parts.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
   body=JSON.parse(Buffer.concat(parts).toString('utf8'));if(!body||typeof body!=='object'||Array.isArray(body))throw Error();
  }catch{fail('Google upload authorization could not be reached or read. Start again.',503);}
  if(!response.ok||body.error){if(body.error==='invalid_grant')throw new GoogleUploadAccessError();if(response.status===429)fail('Google is limiting authorization requests. Wait before trying again.',429);fail('Google upload sign-in could not complete. Check platform setup and start again.',503);}
  if(!validToken(body.access_token)||body.token_type?.toLowerCase()!=='bearer'||!Number.isSafeInteger(body.expires_in)||body.expires_in<=60||body.expires_in>86400)fail('Google returned invalid upload access.',503);
  if(initial||body.scope!==undefined){if(typeof body.scope!=='string'||!googleUploadScopes.every(s=>body.scope.split(' ').includes(s)))fail('Approve both Google Ads and Data Manager permissions to continue.',409);}
  if(initial&&!validToken(body.refresh_token))fail('Google did not grant offline upload access. Start again and approve access.',409);
  if(body.refresh_token_expires_in!==undefined&&(!Number.isSafeInteger(body.refresh_token_expires_in)||body.refresh_token_expires_in<=60||body.refresh_token_expires_in>315360000))fail('Google returned invalid upload authorization expiry.',503);
  return body;
 }
 return {
  authorizationUrl(state,challenge){const u=new URL('https://accounts.google.com/o/oauth2/v2/auth');u.search=new URLSearchParams({client_id:config.id,redirect_uri:config.callback,response_type:'code',scope:googleUploadScopes.join(' '),access_type:'offline',prompt:'consent select_account',state,code_challenge:challenge,code_challenge_method:'S256'}).toString();return u.href;},
  async exchange(code,verifier){const r=await token({grant_type:'authorization_code',code,code_verifier:verifier,redirect_uri:config.callback},true);return {refresh_token:r.refresh_token,scopes:[...googleUploadScopes],refresh_expires_at:r.refresh_token_expires_in?new Date(now()+r.refresh_token_expires_in*1000).toISOString():null};},
  async refresh(refresh){return(await token({grant_type:'refresh_token',refresh_token:refresh},false)).access_token;}
 };
}
