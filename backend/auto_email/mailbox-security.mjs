import {randomBytes,createHash,createHmac,createCipheriv,createDecipheriv,timingSafeEqual} from 'node:crypto';
export const MAILBOX_ROOT='/api/auto-email/mailboxes';
export const OAUTH_COOKIE='__Host-korlix-auto-email-oauth';
export const PROVIDERS=['google','microsoft'];
export const FLOW_MS=10*60*1000;
export const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const fail=(message,statusCode=400,code='mailbox_unavailable')=>{throw Object.assign(new Error(message),{statusCode,code});};
export const digest=value=>createHash('sha256').update(String(value)).digest('hex');
export const opaque=()=>randomBytes(32).toString('base64url');
const PREFIX='KORLIX_AUTO_EMAIL_';
function origin(value,fallback){try{const u=new URL(value||fallback);if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash||u.pathname!=='/'||u.port)return null;return u.origin;}catch{return null;}}
export function mailboxConfig(env=process.env){
 const appOrigin=origin(env[`${PREFIX}APP_ORIGIN`],'https://korlix-auto-email-by-voice.silkyhinny128.chatgpt.site');
 const apiOrigin=origin(env[`${PREFIX}API_ORIGIN`],'https://chee-chai-chee-backend.onrender.com');
 const key=String(env[`${PREFIX}TOKEN_KEY`]||'');
 const enabled=['true','1'].includes(String(env[`${PREFIX}MAILBOX_OAUTH_ENABLED`]||'').trim().toLowerCase());
 const tenant=String(env[`${PREFIX}MICROSOFT_TENANT`]||'organizations');
 const baseReady=enabled&&!!appOrigin&&!!apiOrigin&&/^[a-f0-9]{64}$/i.test(key);
 return {appOrigin,apiOrigin,key,providers:Object.fromEntries(PROVIDERS.map(id=>{
  const clientId=String(env[`${PREFIX}${id.toUpperCase()}_CLIENT_ID`]||'').trim(),clientSecret=String(env[`${PREFIX}${id.toUpperCase()}_CLIENT_SECRET`]||'').trim();
  return [id,{id,clientId,clientSecret,tenant,available:baseReady&&!!clientId&&!!clientSecret&&(id==='google'||tenant==='organizations'||UUID.test(tenant)),redirectUri:apiOrigin?`${apiOrigin}${MAILBOX_ROOT}/oauth/${id}/callback`:null}];
 }))};
}
export const mailboxReady=env=>Object.values(mailboxConfig(env).providers).some(p=>p.available);
export function createMailboxCipher(key){
 if(!/^[a-f0-9]{64}$/i.test(key||''))fail('Mailbox connections are awaiting activation.',503,'mailbox_setup_required');
 const bytes=Buffer.from(key,'hex');
 return {
  encrypt(value,binding){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',bytes,iv);cipher.setAAD(Buffer.from(`auto-email:mailbox:v1:${binding}`));const data=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);return{v:1,iv:iv.toString('base64url'),tag:cipher.getAuthTag().toString('base64url'),data:data.toString('base64url')};},
  decrypt(value,binding){try{if(value?.v!==1||typeof value.data!=='string'||value.data.length>100000)throw Error();const iv=Buffer.from(value.iv,'base64url'),tag=Buffer.from(value.tag,'base64url');if(iv.length!==12||tag.length!==16)throw Error();const decipher=createDecipheriv('aes-256-gcm',bytes,iv);decipher.setAAD(Buffer.from(`auto-email:mailbox:v1:${binding}`));decipher.setAuthTag(tag);return JSON.parse(Buffer.concat([decipher.update(Buffer.from(value.data,'base64url')),decipher.final()]).toString());}catch{fail('This mailbox connection needs to be restarted.',503,'mailbox_vault_unavailable');}},
 };
}
export function browserProof(key,{provider,browserHash,expiresAt}){const data=Buffer.from(JSON.stringify({provider,browserHash,expiresAt})).toString('base64url');return data+'.'+createHmac('sha256',Buffer.from(key,'hex')).update('auto-email:browser-proof:v1:'+data).digest('base64url');}
export function verifyBrowserProof(key,proof,provider,now){
 try{if(typeof proof!=='string'||proof.length>1200)throw Error();const [data,sig,...rest]=proof.split('.'),expected=createHmac('sha256',Buffer.from(key,'hex')).update('auto-email:browser-proof:v1:'+data).digest(),actual=Buffer.from(sig||'','base64url');if(rest.length||actual.length!==expected.length||!timingSafeEqual(actual,expected))throw Error();const p=JSON.parse(Buffer.from(data,'base64url'));if(p.provider!==provider||!Number.isFinite(p.expiresAt)||p.expiresAt<=now||p.expiresAt>now+3*60*1000||!/^[a-f0-9]{64}$/.test(p.browserHash))throw Error();return p.browserHash;}catch{fail('Start this mailbox connection again in the same browser tab.',400,'mailbox_browser_mismatch');}
}
export function cookieValue(header){const matches=String(header||'').split(';').map(s=>s.trim()).filter(s=>s.startsWith(OAUTH_COOKIE+'='));if(matches.length!==1)return '';const value=matches[0].slice(OAUTH_COOKIE.length+1);return /^[A-Za-z0-9_-]{43}$/.test(value)?value:'';}
export const flowBinding=f=>`flow:${f.user_id}:${f.agent_id}:${f.provider}:${f.id}:${f.device_hash}`;
export const connectionBinding=f=>`connection:${f.user_id}:${f.agent_id}:${f.provider}`;
export function strictBody(body,keys){if(!body||Array.isArray(body)||Object.keys(body).some(k=>!keys.includes(k)))fail('This mailbox request could not be verified.');}
