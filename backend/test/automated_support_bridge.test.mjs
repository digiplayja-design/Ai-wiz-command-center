import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,randomUUID} from 'node:crypto';
import express from 'express';
import {installKorlixAgentEmailDeliveryRoutes} from '../korlix_agent_email_delivery.mjs';
import {createAutomatedSupportInboundProcessor} from '../automated_support/inbound.mjs';
import {supportReplyAddress,matchSupportReplyAddress} from '../automated_support/provider.mjs';
import {supportReadiness} from '../automated_support/config.mjs';
import {supportThreadSecret,supportWebhookSecret} from '../automated_support/secrets.mjs';

const now=Date.parse('2026-11-11T03:00:00Z');
const master=Buffer.from('synthetic-existing-resend-webhook-key-32-bytes');
const webhook='whsec_'+master.toString('base64');
const ownerUid=randomUUID(),caseId=randomUUID(),emailId=randomUUID();
const profile={id:'korlix-ai',ownerUid,displayName:'KORLIX Support',appKeys:['korlix_ai'],
  fromEmail:'support@example.test',replyTo:'support@assigned.resend.app',
  inboundAddresses:['support@assigned.resend.app'],senderVerified:true,receivingVerified:true,dailyCap:20};
const environment={RESEND_API_KEY:'synthetic-full-access-key',RESEND_WEBHOOK_SECRET:webhook,
  KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK:'true',
  KORLIX_AUTOMATED_SUPPORT_ENABLED:'true',KORLIX_AUTOMATED_SUPPORT_PAUSED:'false'};
const event={type:'email.received',data:{email_id:emailId}};

function signed(body,{key=master,at=now,eventId='evt_support_bridge'}={}) {
  const timestamp=String(Math.floor(at/1000));
  const signature=createHmac('sha256',key).update(eventId+'.'+timestamp+'.'+body).digest('base64');
  return {'content-type':'application/json','svix-id':eventId,'svix-timestamp':timestamp,'svix-signature':'v1,'+signature};
}

async function fixture(t,{env=environment,received={},readError,storeError,missingCallback=false,emptyCallback=false}={}) {
  const reads=[],supportCalls=[],events=[],updates=[],recipientUpdates=[];
  const legacyMessage={id:randomUUID(),user_id:ownerUid,agent_id:'custom_nova',recipient_id:randomUUID(),
    provider:'resend',provider_message_id:'legacy-delivery-id',status:'sent',metadata:{}};
  const store={
    async findEventByProviderEventId(_provider,id){return events.find(row=>row.provider_event_id===id)||null;},
    async findMessageByProviderId(_provider,id){return id===legacyMessage.provider_message_id ? legacyMessage : null;},
    async updateMessage(userId,agentId,id,patch){
      assert.equal(userId,ownerUid);assert.equal(agentId,'custom_nova');assert.equal(id,legacyMessage.id);
      updates.push(patch);Object.assign(legacyMessage,patch);return legacyMessage;
    },
    async insertEvent(input){const row={id:randomUUID(),...input};events.push(row);return row;},
    async getRecipient(){return {id:legacyMessage.recipient_id};},
    async updateRecipient(_owner,_agent,id,patch){recipientUpdates.push({id,patch});},
  };
  const processVerifiedEvent=createAutomatedSupportInboundProcessor({environment:env,profiles:[profile],
    provider:{async receive(id){
      reads.push(id);if(readError)throw readError;
      return {id:emailId,from:'Reporter <customer@example.test>',
        to:[supportReplyAddress(profile,caseId,env)],text:'The feature still will not load.',
        authentication:{dmarc:'pass'},headers:{},...received};
    }},
    service:{async receiveReply(input){supportCalls.push(input);if(storeError)throw storeError;}},
  });
  const app=express();
  app.use(express.json({verify:(req,_res,body)=>{req.korlixAgentEmailRawBody=Buffer.from(body);}}));
  installKorlixAgentEmailDeliveryRoutes(app,{environment:env,store,requireUser:async()=>({id:ownerUid}),
    loadAgentProfile:async()=>({}),provider:{},now:()=>now,logger:{error(){}},
    onResendEmailReceived:missingCallback ? null : emptyCallback ? async()=>undefined : processVerifiedEvent});
  const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  return {reads,supportCalls,events,updates,recipientUpdates,legacyMessage,
    async post(value=event,{signing={},mutateBody,headers:overrideHeaders}={}) {
      const body=JSON.stringify(value),headers={...signed(body,signing),...overrideHeaders};
      const response=await fetch('http://127.0.0.1:'+server.address().port+'/api/agent-email/resend/webhook',{
        method:'POST',headers,body:mutateBody ? mutateBody(body) : body});
      return {status:response.status,body:await response.json()};
    }};
}

test('existing raw-body verifier dispatches received mail to the signed support case without a new secret',async t=>{
  const f=await fixture(t),response=await f.post();
  assert.equal(response.status,200);assert.equal(response.body.support,true);assert.equal(response.body.matched,true);
  assert.deepEqual(f.reads,[emailId]);assert.equal(f.supportCalls.length,1);
  assert.equal(f.supportCalls[0].caseId,caseId);assert.equal(f.supportCalls[0].profileId,profile.id);
  assert.equal(f.supportCalls[0].fromEmail,'customer@example.test');assert.equal(f.supportCalls[0].senderAuthenticated,true);
  assert.equal(f.events.length,0);assert.equal(f.updates.length,0);
});

test('missing opt-in leaves received events unmatched and never fetches support content',async t=>{
  const f=await fixture(t,{env:{...environment,KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK:'false'}});
  const response=await f.post();assert.equal(response.status,200);assert.equal(response.body.matched,false);
  assert.deepEqual(f.reads,[]);assert.deepEqual(f.supportCalls,[]);
});

test('wrong signature, altered raw bytes and expired timestamps cannot reach the support processor',async t=>{
  const f=await fixture(t);
  for(const options of [
    {signing:{key:Buffer.from('wrong-key')}},
    {mutateBody:body=>body+' '},
    {signing:{at:now-301000}},
    {signing:{at:now+301000}},
    {headers:{'svix-signature':''}},
  ]) assert.equal((await f.post(event,options)).status,401);
  assert.deepEqual(f.reads,[]);assert.deepEqual(f.supportCalls,[]);
});

test('shared endpoint retains the existing secret precedence despite an explicit support endpoint override',async t=>{
  const alternate=Buffer.from('synthetic-separate-support-webhook-secret-long');
  const env={...environment,KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET:webhook,
    RESEND_WEBHOOK_SECRET:'whsec_'+alternate.toString('base64'),
    KORLIX_SUPPORT_WEBHOOK_SECRET:'whsec_'+alternate.toString('base64')};
  const f=await fixture(t,{env});
  assert.equal((await f.post(event,{signing:{key:alternate}})).status,401);
  assert.equal((await f.post()).status,200);assert.equal(f.supportCalls.length,1);
  assert.equal(supportWebhookSecret(env),env.KORLIX_SUPPORT_WEBHOOK_SECRET);
});

test('enabled bridge with unavailable support runtime retries while legacy delivery still succeeds',async t=>{
  const f=await fixture(t,{missingCallback:true});
  assert.equal((await f.post()).status,503);assert.equal(f.reads.length,0);
  const delivery={type:'email.delivered',created_at:new Date(now).toISOString(),data:{email_id:'legacy-delivery-id'}};
  assert.equal((await f.post(delivery)).status,200);assert.equal(f.events.length,1);
  assert.equal(f.legacyMessage.metadata.deliveryStatus,'email.delivered');
  const unavailable=await fixture(t,{emptyCallback:true});
  assert.equal((await unavailable.post()).status,503);
});

test('legacy delivery, replay and suppression behavior is unchanged with the support bridge enabled',async t=>{
  const f=await fixture(t);
  const delivery={type:'email.delivered',created_at:new Date(now).toISOString(),data:{email_id:'legacy-delivery-id'}};
  const first=await f.post(delivery),replay=await f.post(delivery);
  assert.equal(first.body.matched,true);assert.equal(first.body.replayed,false);assert.equal(replay.body.replayed,true);
  assert.equal(f.updates.length,1);assert.equal(f.events.length,1);assert.deepEqual(f.reads,[]);
  const bounce={type:'email.bounced',created_at:new Date(now).toISOString(),data:{email_id:'legacy-delivery-id',bounce:{message:'Mailbox rejected'}}};
  assert.equal((await f.post(bounce,{signing:{eventId:'evt_bounce'}})).status,200);
  assert.equal(f.legacyMessage.status,'failed');assert.equal(f.recipientUpdates.length,1);
  assert.equal(f.recipientUpdates[0].patch.consent_status,'suppressed');assert.deepEqual(f.supportCalls,[]);
});

test('support transport/storage outages remain retryable and private diagnostics are redacted',async t=>{
  for(const options of [{readError:new Error('private provider credential')},{storeError:new Error('private database credential')}]) {
    const f=await fixture(t,options),response=await f.post();
    assert.equal(response.status,503);assert(!JSON.stringify(response.body).includes('credential'));
  }
  const denied=await fixture(t,{storeError:Object.assign(new Error('private case'),{statusCode:403})});
  const response=await denied.post();assert.equal(response.status,200);assert.equal(response.body.matched,false);
});

test('bridge preserves bot, sender authentication and exact signed destination rules',async t=>{
  for(const received of [
    {authentication:{dmarc:'fail',dkim:'pass'}},
    {authentication:{spf:'fail',dkim:'fail'}},
    {headers:{'Auto-Submitted':'auto-replied'}},
    {to:[profile.replyTo]},
    {to:[supportReplyAddress(profile,caseId,environment).replace('+k.','+k.A')]},
  ]) {
    const f=await fixture(t,{received});assert.equal((await f.post()).status,200);assert.equal(f.supportCalls.length,0);
  }
  const unknown=await fixture(t,{received:{authentication:null,headers:{'Authentication-Results':'dmarc=pass;dkim=pass'}}});
  assert.equal((await unknown.post()).status,200);assert.equal(unknown.supportCalls.length,1);
  assert.equal(unknown.supportCalls[0].senderAuthenticated,false);
});

test('derived thread key is domain-separated, stable, opt-in and bound to the legacy verifier identity',()=>{
  const derived=supportThreadSecret(environment);
  assert(Buffer.isBuffer(derived));assert.equal(derived.length,32);assert.notDeepEqual(derived,master);
  assert.deepEqual(supportThreadSecret({...environment}),derived);
  const reply=supportReplyAddress(profile,caseId,environment);
  assert.equal(matchSupportReplyAddress(reply,[profile],environment)?.caseId,caseId);
  const reusedRawKey=supportReplyAddress(profile,caseId,{...environment,KORLIX_SUPPORT_THREAD_SECRET:master.toString('utf8')});
  assert.equal(matchSupportReplyAddress(reusedRawKey,[profile],environment),null);
  for(const change of [
    {...profile,id:'other-profile'},
    {...profile,fromEmail:'other@example.test'},
    {...profile,replyTo:'other@assigned.resend.app',inboundAddresses:['other@assigned.resend.app']},
  ]) assert.equal(matchSupportReplyAddress(reply,[change],environment),null);
  assert.equal(supportThreadSecret({...environment,KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK:'false'}),null);
  assert.equal(supportThreadSecret({...environment,RESEND_WEBHOOK_SECRET:'whsec_'+Buffer.from('short').toString('base64')}),null);
  assert.equal(supportThreadSecret({...environment,KORLIX_SUPPORT_THREAD_SECRET:'invalid'}),null);
  const explicit='explicit-independent-thread-key-with-32-characters';
  assert.equal(supportThreadSecret({...environment,KORLIX_SUPPORT_THREAD_SECRET:explicit}),explicit);
  const rotated={...environment,RESEND_WEBHOOK_SECRET:'whsec_'+Buffer.from('different-existing-key-with-more-than-32-bytes').toString('base64')};
  assert.equal(matchSupportReplyAddress(reply,[profile],rotated),null);
  assert.equal(supportReadiness(profile,environment).ready,true);
  const missingMaster={...environment,RESEND_WEBHOOK_SECRET:'',KORLIX_SUPPORT_WEBHOOK_SECRET:webhook,KORLIX_SUPPORT_THREAD_SECRET:explicit};
  assert.equal(supportReadiness(profile,missingMaster).ready,false);
  assert(supportReadiness(profile,missingMaster).setupReasons.includes('Incoming email verification is not configured.'));
});
