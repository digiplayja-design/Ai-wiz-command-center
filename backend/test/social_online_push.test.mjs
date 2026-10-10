import test from 'node:test';
import assert from 'node:assert/strict';
import {createECDH,randomBytes,randomUUID} from 'node:crypto';
import {createSocialPush} from '../social/push.mjs';
test('online worker sends a generic short-lived alert with silent preference and completes its lease',async()=>{
 const key=createECDH('prime256v1');key.generateKeys();const sent=[],finished=[];
 const event=randomUUID(),id=randomUUID(),lease=randomUUID();
 const push=createSocialPush({autoStart:false,env:{SOCIAL_WEB_PUSH_PUBLIC_KEY:key.getPublicKey().toString('base64url'),SOCIAL_WEB_PUSH_PRIVATE_KEY:key.getPrivateKey().toString('base64url'),SOCIAL_WEB_PUSH_SUBJECT:'https://korlixdeveloper.com'},
  sender:async(...args)=>sent.push(args),database:{rpc:async(_,p)=>{
   if(p.p_action==='claim')return {data:{items:[{id,lease}]}};
   if(p.p_action==='authorize')return {data:{delivery:{kind:'online',event_id:event,binding:randomUUID(),silent:true,expires_at:new Date(Date.now()+90000).toISOString(),subscription:{endpoint:'https://fcm.googleapis.com/fcm/send/test',keys:{p256dh:key.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')}}}}};
   finished.push(p.p_data);return {data:{ok:true}};
  }}});
 await push.tick();push.stop();
 assert.equal(sent.length,1);const data=JSON.parse(sent[0][1]);assert.equal(data.kind,'online');assert.equal(data.silent,true);
 assert.match(data.body,/selected connection is online/);assert(sent[0][2].TTL<=90);
 assert.deepEqual(finished,[{id,lease,status:'accepted'}]);
});
