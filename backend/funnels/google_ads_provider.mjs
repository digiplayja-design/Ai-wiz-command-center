import {createHash,randomBytes,createCipheriv,createDecipheriv} from 'node:crypto';
import {fail,FunnelError,text} from './core.mjs';
import {readGooglePerformance} from './google_ads_performance.mjs';
import {googlePausedMethods} from './google_paused_provider.mjs';
import {googleControlsMethods} from './google_controls_provider.mjs';

export const googleAdsCallback='/api/funnels/google-ads/callback';
export const googleAdsScope='https://www.googleapis.com/auth/adwords';
export const googleDigest=value=>createHash('sha256').update(value).digest('hex');
export const googleChallenge=value=>createHash('sha256').update(value).digest('base64url');
export const googleCustomerId=value=>{if(typeof value!=='string'||!/^\d{10}$/.test(value))fail('Choose an available Google Ads account.');return value;};
export function googleAdsConfiguration(env={}) {
  const id=env.KORLIX_GOOGLE_ADS_CLIENT_ID||'',secret=env.KORLIX_GOOGLE_ADS_CLIENT_SECRET||'',accessModel=env.KORLIX_GOOGLE_ADS_ACCESS_MODEL||'',key=env.KORLIX_GOOGLE_ADS_TOKEN_KEY||'',callback=env.KORLIX_GOOGLE_ADS_REDIRECT_URI||'',apiVersion=env.KORLIX_GOOGLE_ADS_API_VERSION||'v25';
  let validCallback=false;
  try{const u=new URL(callback);validCallback=u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname===googleAdsCallback;}catch{}
  const ready=env.KORLIX_GOOGLE_ADS_ENABLED==='true'&&/^[A-Za-z0-9_-]{10,200}\.apps\.googleusercontent\.com$/.test(id)&&/^[\x21-\x7e]{16,500}$/.test(secret)&&accessModel==='cloud_project'&&/^[A-Za-z0-9+/]{43}=$/.test(key)&&Buffer.from(key,'base64').length===32&&/^v\d{2,3}$/.test(apiVersion)&&validCallback;
  return {ready,id,secret,accessModel,key,callback,apiVersion,hash:googleDigest(JSON.stringify([id,secret,accessModel,key,callback,apiVersion]))};
}
export function googleTokenCipher(key) {
  const bytes=Buffer.from(key,'base64');if(bytes.length!==32)fail('Google Ads secure storage is not configured.',503);
  return {
    seal(value,binding){const iv=randomBytes(12),c=createCipheriv('aes-256-gcm',bytes,iv);c.setAAD(Buffer.from(binding));return {v:1,iv:iv.toString('base64url'),ciphertext:Buffer.concat([c.update(value,'utf8'),c.final()]).toString('base64url'),tag:c.getAuthTag().toString('base64url')};},
    open(value,binding){try{if(value.v!==1)throw Error();const d=createDecipheriv('aes-256-gcm',bytes,Buffer.from(value.iv,'base64url'));d.setAAD(Buffer.from(binding));d.setAuthTag(Buffer.from(value.tag,'base64url'));return Buffer.concat([d.update(Buffer.from(value.ciphertext,'base64url')),d.final()]).toString('utf8');}catch{fail('Reconnect Google Ads to renew secure access.',409);}}
  };
}
export class GoogleAdsAccessError extends FunnelError {constructor(){super('Google authorization expired or was removed. Reconnect Google Ads.',409);}}
const validToken=t=>typeof t==='string'&&t.length>0&&t.length<=12000&&!/[\x00-\x20\x7f]/.test(t);
const eligible=a=>a.manager===false&&a.status==='ENABLED';
const fields='id,descriptive_name,currency_code,time_zone,manager,status,test_account'.split(',');

export function createGoogleAdsProvider(config,{fetchImpl=fetch,now=Date.now}={}) {
  // Fixed hosts and POST bodies keep credentials out of URLs. Never follow a
  // provider redirect or a paging URL. Bound both time and response bytes.
  async function request(url,options,oauth=false) {
    let response,body;
    try{
      response=await fetchImpl(new URL(url),{...options,redirect:'error',signal:AbortSignal.timeout(10000)});
      const reader=response.body?.getReader();if(!reader)throw Error();
      let size=0;const chunks=[];
      try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>2*1024*1024)throw Error();chunks.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
      body=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!body||typeof body!=='object'||Array.isArray(body))throw Error();
    }catch{fail('Google Ads could not be reached or returned an unreadable response. Try again.',503);}
    if(!response.ok||body.error){
      if((oauth&&body.error==='invalid_grant')||(!oauth&&response.status===401))throw new GoogleAdsAccessError();
      if(!oauth&&Array.isArray(body.error?.details)&&body.error.details.some(d=>Array.isArray(d?.errors)&&d.errors.some(e=>e?.errorCode?.authorizationError==='CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION')))fail('The Google Cloud project needs approval for production Google Ads access. Ask the platform administrator to review its API access level.',409);
      if(response.status===429)fail('Google Ads is limiting requests. Please wait and try again.',429);
      if(!oauth&&response.status===403)fail('Google Ads access is unavailable. Check account permissions and KORLIX platform approval.',409);
      fail(oauth?'Google sign-in could not be completed. Start a new connection.':'Google Ads could not complete this request. Check account access and platform setup.',503);
    }
    return body;
  }
  async function token(values,initial=false) {
    const r=await request('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.id,client_secret:config.secret,...values}).toString()},true);
    if(!validToken(r.access_token)||r.token_type?.toLowerCase()!=='bearer'||!Number.isSafeInteger(r.expires_in)||r.expires_in<=60||r.expires_in>86400)fail('Google did not return valid account access.',503);
    if((initial||r.scope!==undefined)&&(typeof r.scope!=='string'||!r.scope.split(' ').includes(googleAdsScope)))fail('Approve the Google Ads permission to connect your accounts.',409);
    if(initial&&!validToken(r.refresh_token))fail('Google did not grant ongoing access. Start again and approve the connection.',409);
    if(r.refresh_token_expires_in!==undefined&&(!Number.isSafeInteger(r.refresh_token_expires_in)||r.refresh_token_expires_in<=60||r.refresh_token_expires_in>315360000))fail('Google returned invalid authorization expiry.',503);
    return r;
  }
  async function ads(path,access,root,body){
    return request(`https://googleads.googleapis.com/${config.apiVersion}/${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${access}`,...(root?{'login-customer-id':googleCustomerId(root)}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
  }
  function clean(a){
    // Protobuf JSON can omit false boolean fields.
    if(a&&typeof a==='object')a={manager:false,testAccount:false,...a};
    if(!a||typeof a.id!=='string'||!/^\d{10}$/.test(a.id)||typeof a.manager!=='boolean'||typeof a.testAccount!=='boolean'||!['ENABLED','CANCELED','SUSPENDED','CLOSED'].includes(a.status)||typeof a.currencyCode!=='string'||!/^[A-Z]{3}$/.test(a.currencyCode)||typeof a.timeZone!=='string'||!a.timeZone||a.timeZone.length>100)fail('Google returned an unreadable account.',503);
    return {id:a.id,name:text(a.descriptiveName||a.id,200),currency:a.currencyCode,timezone:a.timeZone,manager:a.manager,status:a.status,test_account:a.testAccount};
  }
  async function search(access,id,root,query,key,max){
    const accounts=new Map(),seen=new Set();let pageToken;
    for(let page=0;page<5;page++){
      const r=await ads(`customers/${googleCustomerId(id)}/googleAds:search`,access,root,{query,...(pageToken?{pageToken}:{})});
      if(r.results!==undefined&&!Array.isArray(r.results))fail('Google returned an unreadable account list.',503);
      for(const row of r.results||[]){const a=clean(row?.[key]);if(accounts.has(a.id))fail('Google returned duplicate account details. Try again.',503);accounts.set(a.id,a);}
      if(accounts.size>max)fail('This account has more than 500 active advertising clients. Choose a smaller manager account with direct access.',409);
      if(!r.nextPageToken)return [...accounts.values()];
      pageToken=r.nextPageToken;if(typeof pageToken!=='string'||pageToken.length>4000||seen.has(pageToken))fail('Google account pagination could not be completed.',503);seen.add(pageToken);
    }
    fail('Google account pagination exceeded the connection limit. Choose a smaller manager account.',409);
  }
  async function account(access,id,root){
    const rows=await search(access,id,root,`SELECT ${fields.map(f=>'customer.'+f).join(', ')} FROM customer LIMIT 1`,'customer',1);
    if(rows.length!==1||rows[0].id!==id)fail('Google did not confirm access to this account.',409);return rows[0];
  }
  return {
    ...googlePausedMethods(ads),
    ...googleControlsMethods(ads),
    authorizationUrl(state,challenge){const u=new URL('https://accounts.google.com/o/oauth2/v2/auth');u.search=new URLSearchParams({client_id:config.id,redirect_uri:config.callback,response_type:'code',scope:googleAdsScope,access_type:'offline',prompt:'consent select_account',state,code_challenge:challenge,code_challenge_method:'S256'}).toString();return u.href;},
    async exchange(code,verifier){const r=await token({grant_type:'authorization_code',code,code_verifier:verifier,redirect_uri:config.callback},true);return {refresh_token:r.refresh_token,refresh_expires_at:r.refresh_token_expires_in?new Date(now()+r.refresh_token_expires_in*1000).toISOString():null};},
    async refresh(refreshToken){return (await token({grant_type:'refresh_token',refresh_token:refreshToken})).access_token;},
    async roots(access){const r=await ads('customers:listAccessibleCustomers',access);if(r.resourceNames!==undefined&&!Array.isArray(r.resourceNames))fail('Google returned an unreadable access list.',503);const names=r.resourceNames||[];if(names.length>500)fail('More than 500 direct accounts were returned. Use a Google account with a smaller access list.',409);const ids=names.map(n=>{if(typeof n!=='string'||!/^customers\/\d{10}$/.test(n))fail('Google returned an unreadable access account.',503);return n.slice(10);});return [...new Set(ids)];},
    account,
    async performance(access,account,root,range){return readGooglePerformance(ads,access,account,root,range);},
    async campaignPerformance(access,account,root,range){return readGooglePerformance(ads,access,account,root,range,'campaign');},
    async accounts(access,root){
      const a=await account(access,root);if(!a.manager)return {root:a,accounts:eligible(a)?[a]:[]};
      const rows=await search(access,root,root,`SELECT ${fields.map(f=>'customer_client.'+f).join(', ')} FROM customer_client WHERE customer_client.manager = FALSE AND customer_client.status = 'ENABLED' LIMIT 501`,'customerClient',500);
      if(rows.some(a=>!eligible(a)))fail('Google returned an ineligible advertising account.',503);return {root:a,accounts:rows};
    }
  };
}
