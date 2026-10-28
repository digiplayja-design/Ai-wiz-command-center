import {createHash} from 'node:crypto';
import {fail} from './mailbox-security.mjs';
const GOOGLE_SCOPE='https://www.googleapis.com/auth/gmail.send';
export const MAILBOX_SCOPES={google:['openid','email',GOOGLE_SCOPE],microsoft:['offline_access','https://graph.microsoft.com/User.Read','https://graph.microsoft.com/Mail.Send']};
export function authorizationUrl(config,{state,verifier}){
 const google=config.id==='google';
 const url=new URL(google?'https://accounts.google.com/o/oauth2/v2/auth':`https://login.microsoftonline.com/${config.tenant}/oauth2/v2.0/authorize`);
 const params={client_id:config.clientId,redirect_uri:config.redirectUri,response_type:'code',scope:MAILBOX_SCOPES[config.id].join(' '),state,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',prompt:google?'consent select_account':'select_account',...(google?{access_type:'offline',include_granted_scopes:'false'}:{response_mode:'query'})};
 for(const [key,value] of Object.entries(params))url.searchParams.set(key,value);return url.href;
}
async function jsonRequest(fetcher,url,options={}){
 let response,value;
 try{response=await fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(15000),headers:{Accept:'application/json',...options.headers}});const text=await response.text();if(text.length>100000)throw Error();value=JSON.parse(text);}catch{fail('The email provider could not confirm this connection. Please try again.',502,'mailbox_provider_unavailable');}
 if(!response.ok||value?.error)fail('The email provider did not approve this connection. Please try again.',502,'mailbox_provider_rejected');return value;
}
function email(value){if(typeof value!=='string'||value.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(value)||/[\x00-\x1f\x7f<>]/.test(value))fail('The provider did not return a usable mailbox address.',502,'mailbox_identity_unavailable');return value;}
export async function exchangeMailboxCode(config,code,verifier,{fetcher=fetch,now=Date.now}={}){
 const google=config.id==='google';
 const form=new URLSearchParams({grant_type:'authorization_code',code,code_verifier:verifier,client_id:config.clientId,client_secret:config.clientSecret,redirect_uri:config.redirectUri,...(!google?{scope:MAILBOX_SCOPES.microsoft.join(' ')}:{})});
 const token=await jsonRequest(fetcher,google?'https://oauth2.googleapis.com/token':`https://login.microsoftonline.com/${config.tenant}/oauth2/v2.0/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form.toString()});
 if(typeof token.access_token!=='string'||!token.access_token||token.access_token.length>30000||typeof token.refresh_token!=='string'||!token.refresh_token||token.refresh_token.length>30000||String(token.token_type).toLowerCase()!=='bearer'||!Number.isFinite(Number(token.expires_in))||Number(token.expires_in)<30||Number(token.expires_in)>86400)fail('The provider did not grant ongoing mailbox access. Reconnect and review the requested permissions.',502,'mailbox_access_incomplete');
 const scopes=String(token.scope||'').split(/\s+/).filter(Boolean),normalized=scopes.map(s=>s.replace(/^https:\/\/graph.microsoft.com\//,'').toLowerCase());
 if(google?!scopes.includes(GOOGLE_SCOPE):!['mail.send','user.read'].every(s=>normalized.includes(s)))fail('Approve the requested mailbox permissions to continue.',403,'mailbox_permission_missing');
 if(scopes.some(s=>/gmail\.(read|compose|modify|metadata)|mail\.(read|readwrite)|mail\.google\.com/.test(s.toLowerCase())))fail('Use a dedicated sending-only KORLIX connection. This grant includes inbox access.',403,'mailbox_scope_mismatch');
 const profile=await jsonRequest(fetcher,google?'https://openidconnect.googleapis.com/v1/userinfo':'https://graph.microsoft.com/v1.0/me?$select=id,mail,displayName',{headers:{Authorization:`Bearer ${token.access_token}`}});
 let identity;
 // Identity comes from the provider's authenticated resource endpoint. ID and
 // access tokens are opaque; unverified JWT claims are never used as identity.
 if(google){if(typeof profile.sub!=='string'||!profile.sub||profile.sub.length>255||profile.email_verified!==true)fail('Google could not verify this mailbox identity.',502,'mailbox_identity_unavailable');identity={accountId:profile.sub,email:email(profile.email),displayName:String(profile.name||profile.email).slice(0,160),authority:'google'};}
 else{if(typeof profile.id!=='string'||!/^[0-9a-f-]{36}$/i.test(profile.id))fail('Microsoft could not verify this mailbox identity.',502,'mailbox_identity_unavailable');identity={accountId:profile.id,email:email(profile.mail),displayName:String(profile.displayName||profile.mail).slice(0,160),authority:config.tenant};}
 return {identity,scopes,tokens:{accessToken:token.access_token,refreshToken:token.refresh_token,expiresAt:now()+Number(token.expires_in)*1000}};
}
