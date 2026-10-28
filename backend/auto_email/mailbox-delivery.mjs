import {MAILBOX_SCOPES} from './mailbox-providers.mjs';
import {fail,UUID} from './mailbox-security.mjs';
import {validateMessage} from './outbox-security.mjs';
function scopesValid(provider,scopes){const values=scopes.map(s=>s.toLowerCase()),normal=values.map(s=>s.replace('https://graph.microsoft.com/',''));return(provider==='google'?values.includes('https://www.googleapis.com/auth/gmail.send'):normal.includes('mail.send')&&normal.includes('user.read'))&&!values.some(s=>/gmail\.(read|compose|modify|metadata)|mail\.(read|readwrite)|mail\.google\.com/.test(s));}
async function json(fetcher,url,options){let r,v;try{r=await fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(15000)});v=await r.json();}catch{fail('The mailbox could not be checked. Reconnect and review again.',502,'mailbox_check_failed');}if(!r.ok||v?.error)fail('Reconnect this mailbox before sending.',409,'mailbox_reconnect_required');return v;}
export async function usableMailboxTokens(config,tokens,storedScopes,identity,{fetcher=fetch,now=Date.now}={}){
 if(!scopesValid(config.id,storedScopes||[]))fail('Reconnect with the requested sending permissions.',409,'mailbox_reconnect_required');
 let result={...tokens};
 if(!Number.isFinite(result.expiresAt)||result.expiresAt<=now()+60000){
  if(typeof result.refreshToken!=='string'||!result.refreshToken||result.refreshToken.length>30000)fail('Reconnect this mailbox before sending.',409,'mailbox_reconnect_required');
  const form=new URLSearchParams({grant_type:'refresh_token',refresh_token:result.refreshToken,client_id:config.clientId,client_secret:config.clientSecret,...(config.id==='microsoft'?{scope:MAILBOX_SCOPES.microsoft.join(' ')}:{})});
  const value=await json(fetcher,config.id==='google'?'https://oauth2.googleapis.com/token':`https://login.microsoftonline.com/${config.tenant}/oauth2/v2.0/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form.toString()});
  if(typeof value.access_token!=='string'||!value.access_token||value.access_token.length>30000||String(value.token_type).toLowerCase()!=='bearer'||!Number.isFinite(Number(value.expires_in))||Number(value.expires_in)<90||Number(value.expires_in)>86400)fail('Reconnect this mailbox before sending.',409,'mailbox_reconnect_required');
  if(value.scope&&!scopesValid(config.id,String(value.scope).split(/\s+/)))fail('Reconnect with the requested sending permissions.',409,'mailbox_reconnect_required');
  if(value.refresh_token!==undefined&&(typeof value.refresh_token!=='string'||!value.refresh_token||value.refresh_token.length>30000))fail('Reconnect this mailbox before sending.',409,'mailbox_reconnect_required');
  result={accessToken:value.access_token,refreshToken:value.refresh_token||result.refreshToken,expiresAt:now()+Number(value.expires_in)*1000};
 }
 if(typeof result.accessToken!=='string'||!result.accessToken||result.accessToken.length>30000)fail('Reconnect this mailbox before sending.',409,'mailbox_reconnect_required');
 const profile=await json(fetcher,config.id==='google'?'https://openidconnect.googleapis.com/v1/userinfo':'https://graph.microsoft.com/v1.0/me?$select=id,mail,displayName',{headers:{Authorization:`Bearer ${result.accessToken}`}});
 const accountId=config.id==='google'?profile.sub:profile.id,address=config.id==='google'?profile.email:profile.mail;
 if(accountId!==identity.accountId||typeof address!=='string'||address.toLowerCase()!==identity.email.toLowerCase()||(config.id==='google'&&profile.email_verified!==true))fail('The sender identity changed. Reconnect and review it.',409,'mailbox_identity_changed');
 return result;
}
function encodedSubject(subject){const parts=[];let chunk='';for(const char of subject){if(Buffer.byteLength(chunk+char)>39){parts.push(chunk);chunk='';}chunk+=char;}if(chunk)parts.push(chunk);return parts.map(s=>'=?UTF-8?B?'+Buffer.from(s).toString('base64')+'?=').join('\r\n ');}
export function gmailMime(job){const s=validateMessage(job.snapshot);if(!UUID.test(job.id))fail('Invalid email reference.',400);const date=new Date(job.confirmed_at);if(!Number.isFinite(date.getTime()))fail('Invalid email date.',400);return [`From: ${s.from}`,`To: ${s.to}`,`Subject: ${encodedSubject(s.subject)}`,`Date: ${date.toUTCString()}`,`Message-ID: <korlix-${job.id}@${s.from.split('@')[1]}>`,'MIME-Version: 1.0','Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',Buffer.from(s.textBody.replace(/\r?\n/g,'\r\n')).toString('base64').match(/.{1,76}/g).join('\r\n'),''].join('\r\n');}
export async function submitMailboxMessage(provider,accessToken,job,{fetcher=fetch}={}){
 validateMessage(job.snapshot);if(!UUID.test(job.id))fail('Invalid email reference.',400);
 const google=provider==='google';if(!['google','microsoft'].includes(provider))fail('Invalid mailbox provider.',400);
 const payload=google?{raw:Buffer.from(gmailMime(job)).toString('base64url')}:{message:{subject:job.snapshot.subject,body:{contentType:'Text',content:job.snapshot.textBody},toRecipients:[{emailAddress:{address:job.snapshot.to}}],internetMessageHeaders:[{name:'x-korlix-outbox-id',value:job.id}]},saveToSentItems:true};
 let response;
 try{response=await fetcher(google?'https://gmail.googleapis.com/gmail/v1/users/me/messages/send':'https://graph.microsoft.com/v1.0/me/sendMail',{method:'POST',headers:{Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(20000)});}catch{return{status:'uncertain',code:'provider_result_unknown'};}
 if((google&&response.status===200)||(!google&&response.status===202)){
  if(!google)return{status:'accepted',code:'provider_accepted',providerMessageId:null};
  try{const v=await response.json();if(typeof v.id==='string'&&/^[a-zA-Z0-9_-]{1,240}$/.test(v.id))return{status:'accepted',code:'provider_accepted',providerMessageId:v.id};}catch{}
  return{status:'uncertain',code:'provider_result_unknown'};
 }
 return [400,401,403,404,413,422,429].includes(response.status)?{status:'not_sent',code:response.status===429?'provider_rate_limited':[401,403].includes(response.status)?'mailbox_reconnect_required':'provider_rejected'}:{status:'uncertain',code:'provider_result_unknown'};
}
