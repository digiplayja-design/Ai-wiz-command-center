import {createHmac,timingSafeEqual} from 'node:crypto';
import {fail,mailboxReady} from './mailbox-security.mjs';
export const OUTBOX_ROOT='/api/auto-email/outbox';
const yes=v=>['true','1','yes','on','enabled'].includes(String(v||'').toLowerCase());
export const sendingReady=(env=process.env)=>mailboxReady(env)&&yes(env.KORLIX_AUTO_EMAIL_SENDING_ENABLED)&&yes(env.KORLIX_AGENT_EMAIL_ENABLED)&&['false','0','no','off','disabled'].includes(String(env.KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE||'').toLowerCase());
export const dailyCap=(env=process.env)=>Math.min(20,Math.max(1,Number.parseInt(env.KORLIX_AUTO_EMAIL_DAILY_SEND_CAP,10)||5));
export function reviewProof(key,value){const data=Buffer.from(JSON.stringify(value)).toString('base64url');return data+'.'+createHmac('sha256',Buffer.from(key,'hex')).update('auto-email:delivery-review:v1:'+data).digest('base64url');}
export function verifyReview(key,token,context,now){
 try{if(typeof token!=='string'||token.length>2400)throw Error();const[data,sig,...extra]=token.split('.'),actual=Buffer.from(sig||'','base64url'),expected=createHmac('sha256',Buffer.from(key,'hex')).update('auto-email:delivery-review:v1:'+data).digest();if(extra.length||actual.length!==expected.length||!timingSafeEqual(actual,expected))throw Error();const p=JSON.parse(Buffer.from(data,'base64url'));if(p.user_id!==context.user_id||p.agent_id!==context.agent_id||p.device_hash!==context.device_hash||!Number.isFinite(p.expiresAt)||p.expiresAt<=now||p.expiresAt>now+300000)throw Error();return p;}catch{fail('Review this email again before sending.',409,'review_expired');}
}
export function validateMessage(snapshot){
 for(const field of ['from','to']){const v=snapshot?.[field];if(typeof v!=='string'||v.length>254||!/^[\x21-\x7e]+$/.test(v)||/[\s<>(),;:"\\]/.test(v)||!/^([^@]+)@([a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63})$/i.test(v))fail('Review a valid sender and recipient address.',409,'address_invalid');}
 if(typeof snapshot.subject!=='string'||!snapshot.subject.trim()||snapshot.subject.length>200||/[\r\n\x00-\x1f\x7f]/.test(snapshot.subject))fail('Review a valid subject.',409,'subject_invalid');
 if(typeof snapshot.textBody!=='string'||!snapshot.textBody.trim()||snapshot.textBody.length>12000||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(snapshot.textBody))fail('Review a plain-text message of up to 12,000 characters.',409,'body_invalid');
 return snapshot;
}
export const jobPublic=j=>({id:j.id,draftId:j.draft_id,provider:j.provider,status:j.status,snapshot:j.snapshot,providerMessageId:j.provider_message_id||null,resultCode:j.result_code||null,confirmedAt:j.confirmed_at,submittedAt:j.submitted_at,finishedAt:j.finished_at});
