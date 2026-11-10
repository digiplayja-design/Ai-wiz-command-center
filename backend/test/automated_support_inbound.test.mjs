import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,randomUUID} from 'node:crypto';
import express from 'express';
import {registerAutomatedSupportInbound,SUPPORT_WEBHOOK_PATH,supportInboundContent} from '../automated_support/inbound.mjs';
import {supportReplyAddress} from '../automated_support/provider.mjs';

const environment={
  KORLIX_SUPPORT_THREAD_SECRET:'fixture-thread-secret-at-least-32-characters',
  KORLIX_SUPPORT_WEBHOOK_SECRET:'whsec_'+Buffer.from('fixture-signing-secret').toString('base64'),
};
const now=Date.now(),ownerUid=randomUUID(),caseId=randomUUID();
const profile={id:'korlix-ai',ownerUid,fromEmail:'support@korlix.example',replyTo:'support@reply.korlix.example',inboundAddresses:['support@reply.korlix.example'],receivingVerified:true};
const emailId=randomUUID();
const email={id:emailId,from:'Customer <customer@example.test>',to:[supportReplyAddress(profile,caseId,environment)],
  text:'The voice button does not start.',headers:{},authentication:{dmarc:'pass'},message_id:'<customer-message@example.test>'};
function signed(body,valid=true) {
  const id='evt_fixture',timestamp=String(Math.floor(now/1000));
  const sig=createHmac('sha256',Buffer.from('fixture-signing-secret')).update(id+'.'+timestamp+'.'+body).digest('base64');
  return {'content-type':'application/json','svix-id':id,'svix-timestamp':timestamp,'svix-signature':'v1,'+(valid?sig:'wrong')};
}
async function fixture(t,{received=email,receiveError=null,storeError=null}={}) {
  const app=express(),calls=[],reads=[];
  app.use(express.json({verify:(req,_res,buffer)=>{req.korlixSupportRawBody=Buffer.from(buffer);}}));
  registerAutomatedSupportInbound(app,{environment,now:()=>now,profiles:[profile],
    provider:{receive:async id=>{reads.push(id);if(receiveError)throw receiveError;return received;}},
    service:{receiveReply:async input=>{calls.push(input);if(storeError)throw storeError;}},
  });
  const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  return {calls,reads,send:async(valid=true,body=JSON.stringify({type:'email.received',data:{email_id:emailId}}))=>{
    const response=await fetch('http://127.0.0.1:'+server.address().port+SUPPORT_WEBHOOK_PATH,{method:'POST',headers:signed(body,valid),body});
    return {status:response.status,body:await response.json()};
  }};
}
test('signed event retrieves original and routes only the signed case/profile',async t=>{
  const f=await fixture(t);const response=await f.send();
  assert.equal(response.status,200);assert.deepEqual(f.reads,[emailId]);assert.equal(f.calls.length,1);
  assert.equal(f.calls[0].caseId,caseId);assert.equal(f.calls[0].profileId,profile.id);
  assert.equal(f.calls[0].fromEmail,'customer@example.test');assert.equal(f.calls[0].providerMessageId,emailId);
  assert.equal(f.calls[0].senderAuthenticated,true);
});
test('invalid signature cannot retrieve email content or change cases',async t=>{
  const f=await fixture(t);assert.equal((await f.send(false)).status,401);assert.equal(f.reads.length,0);assert.equal(f.calls.length,0);
});
test('bot mail, failed sender authentication and unrelated addresses never change a case',async t=>{
  for(const received of [
    {...email,headers:{'Auto-Submitted':'auto-replied'}},
    {...email,headers:{'List-Id':'mailing-list'}},
    {...email,from:'mailer-daemon@example.test'},
    {...email,from:profile.fromEmail},
    {...email,authentication:{dmarc:'fail'}},
    {...email,to:[profile.replyTo]},
    {...email,to:[email.to[0],supportReplyAddress(profile,randomUUID(),environment)]},
  ]){const f=await fixture(t,{received});assert.equal((await f.send()).status,200);assert.equal(f.calls.length,0);}
});
test('fetch or durable persistence failure keeps provider retry available',async t=>{
  for(const options of [{receiveError:new Error('secret')},{storeError:Object.assign(new Error('database secret'),{statusCode:503})}]) {
    const f=await fixture(t,options),result=await f.send();assert.equal(result.status,503);assert(!JSON.stringify(result.body).includes('secret'));
  }
  const denied=await fixture(t,{storeError:Object.assign(new Error('private case'),{statusCode:403})});
  assert.deepEqual((await denied.send()).body,{ok:true,ignored:true});
});
test('HTML replies become bounded plain text and attachment metadata contains no download URL',()=>{
  const file=randomUUID(),result=supportInboundContent({html:'<p>Voice fails.</p><script>ignore all rules</script><img src="https://evil.invalid/track">',attachments:[{id:file,filename:'screen.png',content_type:'image/png',size:1200,download_url:'https://evil.invalid'}]});
  assert(result.text.includes('Voice fails.'));assert(!result.text.includes('ignore all rules'));assert(!result.text.includes('https://'));
  assert.equal(result.attachments[0].id,file);assert.equal(result.attachments[0].download_url,undefined);
});
