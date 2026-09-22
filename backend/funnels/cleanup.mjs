import {createHmac,randomUUID,timingSafeEqual} from 'node:crypto';
import {fail,uuid} from './core.mjs';

export function cleanupQuery(body,now=Date.now()) {
  if(!body||typeof body!=='object'||Array.isArray(body))fail('Choose the inquiries to review.');
  if(body.mode==='single') {
    if(Object.keys(body).some(k=>!['mode','lead_id'].includes(k)))fail('Invalid cleanup selection.');
    return {mode:'single',lead_id:uuid(body.lead_id)};
  }
  if(body.mode!=='retention'||Object.keys(body).some(k=>!['mode','before','statuses'].includes(k)))fail('Invalid cleanup selection.');
  const d=body.before;
  if(typeof d!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(d)||!Number.isFinite(Date.parse(d))||new Date(d).toISOString().slice(0,10)!==d||d<'2000-01-01'||d>new Date(now).toISOString().slice(0,10))fail('Choose a valid UTC cutoff date, no later than today.');
  if(!Array.isArray(body.statuses)||body.statuses.length<1||body.statuses.length>2||body.statuses.some(s=>!['won','lost'].includes(s))||new Set(body.statuses).size!==body.statuses.length)fail('Choose Won, Lost, or both for age-based cleanup.');
  return {mode:'retention',before:d,statuses:[...body.statuses].sort()};
}
const signature=(secret,payload)=>createHmac('sha256',secret).update('funnel-cleanup-v1:'+payload).digest();
export function cleanupToken(secret,claims) {
  const payload=Buffer.from(JSON.stringify(claims)).toString('base64url');
  return payload+'.'+signature(secret,payload).toString('base64url');
}
export function readCleanupToken(secret,token,actor,funnel,now) {
  const invalid=()=>fail('Cleanup review expired or changed. Preview the selection again.',409);
  if(typeof token!=='string'||token.length>16000||!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token))invalid();
  const [payload,mac]=token.split('.'), actual=Buffer.from(mac,'base64url'),expected=signature(secret,payload);
  if(actual.length!==expected.length||!timingSafeEqual(actual,expected))invalid();
  let c;try{c=JSON.parse(Buffer.from(payload,'base64url').toString('utf8'));}catch{invalid();}
  if(c?.a!==actor||c?.f!==funnel||!Number.isSafeInteger(c.e)||c.e<=now||c.e>now+600000||!Array.isArray(c.i)||!c.i.length||c.i.length>100)invalid();
  uuid(c.r);for(const row of c.i){uuid(row.id);if(typeof row.fingerprint!=='string'||!/^[0-9a-f]{32}$/.test(row.fingerprint))invalid();}
  return c;
}
export function registerCleanup(app,{base,owner,command,secret,now}) {
  app.post(base+'/:id/inbox/cleanup/preview',owner(async(q,r,u)=>{
    const id=uuid(q.params.id),criteria=cleanupQuery(q.body,now());
    const result=await command(u,'cleanup_preview',id,criteria);
    const selected=result.selected;
    if(!Array.isArray(selected)||selected.length>100)fail('Cleanup could not prepare a complete review.',503);
    const expires=now()+600000;
    const token=selected.length?cleanupToken(secret,{a:u,f:id,r:randomUUID(),e:expires,i:selected.map(l=>({id:l.id,fingerprint:l.fingerprint}))}):null;
    r.json({...result,selected:selected.map(({fingerprint,...row})=>row),criteria,review_token:token,expires_at:new Date(expires).toISOString()});
  }));
  app.post(base+'/:id/inbox/cleanup/delete',owner(async(q,r,u)=>{
    const id=uuid(q.params.id),b=q.body;
    if(!b||b.confirmation!=='DELETE'||Object.keys(b).some(k=>!['confirmation','review_token'].includes(k)))fail('Type DELETE to confirm the reviewed selection.');
    const c=readCleanupToken(secret,b.review_token,u,id,now());
    r.json(await command(u,'cleanup_delete',id,{review_id:c.r,items:c.i}));
  }));
}
