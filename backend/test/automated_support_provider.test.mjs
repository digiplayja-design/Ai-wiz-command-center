import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {
  createAutomatedSupportResendProvider, supportReplyAddress, matchSupportReplyAddress,
} from '../automated_support/provider.mjs';

const environment = {
  RESEND_API_KEY:'fixture-provider-key',
  KORLIX_AUTOMATED_SUPPORT_ENABLED:'true',KORLIX_AUTOMATED_SUPPORT_PAUSED:'false',
  KORLIX_SUPPORT_THREAD_SECRET:'fixture-thread-secret-with-at-least-32-characters',
  KORLIX_SUPPORT_WEBHOOK_SECRET:'whsec_Zml4dHVyZQ==',
};
const profile = {
  id:'korlix-ai',ownerUid:randomUUID(),displayName:'KORLIX Support',
  fromEmail:'support@korlix.example',replyTo:'support@replies.korlix.example',
  inboundAddresses:['support@replies.korlix.example'],senderVerified:true,receivingVerified:true,
};
function dispatch() {
  const caseRecord = {id:randomUUID(),profileId:profile.id,ownerUid:profile.ownerUid,reporterEmail:'customer@example.test',reporterVerified:true,subject:'Your KORLIX report'};
  const message = {id:randomUUID(),caseId:caseRecord.id,profileId:profile.id,ownerUid:profile.ownerUid,text:'Which feature were you trying to open?',subject:caseRecord.subject};
  return {profile,caseRecord,message,idempotencyKey:'korlix-support/' + message.id};
}
test('case reply tokens preserve case and isolate identities, cases and destinations', () => {
  for (let i=0;i<15;i++) {
    const id=randomUUID(),reply=supportReplyAddress(profile,id,environment);
    assert(reply.split('@')[0].length<=64);
    assert.equal(matchSupportReplyAddress(reply,[profile],environment)?.caseId,id);
    assert.equal(matchSupportReplyAddress(reply,[{...profile,id:'other-business'}],environment),null);
    assert.equal(matchSupportReplyAddress(reply.replace('replies.korlix.example','other.example'),[profile],environment),null);
    const tampered=reply.replace('+k.','+k.A');
    assert.equal(matchSupportReplyAddress(tampered,[profile],environment),null);
  }
  assert.equal(matchSupportReplyAddress(profile.replyTo,[profile],environment),null);
});
test('sends only the immutable reporter through the enrolled verified sender with a stable key', async () => {
  const requests=[],input=dispatch(),providerId=randomUUID();
  const provider=createAutomatedSupportResendProvider({environment,fetcher:async(url,options)=>{
    requests.push({url,options,body:JSON.parse(options.body)});
    return Response.json({id:providerId});
  }});
  const result=await provider.send(input);
  assert.equal(result.providerMessageId,providerId);
  const request=requests[0];
  assert.equal(request.url,'https://api.resend.com/emails');
  assert.equal(request.options.redirect,'error');
  assert.equal(request.options.headers['Idempotency-Key'],input.idempotencyKey);
  assert.deepEqual(request.body.to,['customer@example.test']);
  assert.equal(request.body.from,'KORLIX Support <support@korlix.example>');
  assert.equal(matchSupportReplyAddress(request.body.reply_to,[profile],environment).caseId,input.caseRecord.id);
  assert.equal(request.body.headers['Auto-Submitted'],'auto-replied');
  assert.equal(request.body.cc,undefined);
});
test('paused, mismatched, unverified, looping and injected deliveries make no network request', async () => {
  let calls=0;
  const fetcher=async()=>{calls++;return Response.json({id:randomUUID()});};
  for (const env of [{...environment,KORLIX_AUTOMATED_SUPPORT_ENABLED:'false'},
    {...environment,KORLIX_AUTOMATED_SUPPORT_PAUSED:'true'},
    {...environment,KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE:'true'},{}]) {
    await assert.rejects(createAutomatedSupportResendProvider({environment:env,fetcher}).send(dispatch()));
  }
  const provider=createAutomatedSupportResendProvider({environment,fetcher});
  const mutations=[
    input=>input.profile={...profile,senderVerified:false},
    input=>input.profile={...profile,receivingVerified:false},
    input=>input.caseRecord.reporterVerified=false,
    input=>input.caseRecord.reporterEmail=profile.fromEmail,
    input=>input.caseRecord.reporterEmail='victim@example.test\nBcc: victim2@example.test',
    input=>input.caseRecord.ownerUid=randomUUID(),
    input=>input.message.caseId=randomUUID(),
    input=>input.message.subject='Hello\r\nBcc: victim@example.test',
    input=>input.message.inReplyTo='<original@example.test>\r\nBcc: victim@example.test',
    input=>input.idempotencyKey='fresh-key',
  ];
  for(const mutate of mutations){const input=dispatch();mutate(input);await assert.rejects(provider.send(input));}
  assert.equal(calls,0);
});
test('reviewed replies carry the original message ID into the customer email thread', async () => {
  let payload;
  const input=dispatch();input.message.inReplyTo='<original-customer-message@example.test>';
  const provider=createAutomatedSupportResendProvider({environment,fetcher:async(_url,options)=>{
    payload=JSON.parse(options.body);return Response.json({id:randomUUID()});
  }});
  await provider.send(input);
  assert.equal(payload.headers['In-Reply-To'],input.message.inReplyTo);
  assert.equal(payload.headers.References,input.message.inReplyTo);
});
test('ambiguous provider outcomes are never described as definite failures or automatically resent', async () => {
  for(const fetcher of [
    async()=>{throw new Error('network reset with secret diagnostic');},
    async()=>new Response('bad gateway',{status:502}),
    async()=>Response.json({name:'concurrent_idempotent_requests'},{status:409}),
    async()=>new Response('not-json',{status:200}),
    async()=>Response.json({id:'invalid-receipt'}),
  ]) {
    const provider=createAutomatedSupportResendProvider({environment,fetcher});
    await assert.rejects(provider.send(dispatch()),error=>error.uncertain===true && !error.message.includes('secret'));
  }
});
test('definite 4xx and rate limits are distinguished from ambiguous delivery', async () => {
  const rejected=createAutomatedSupportResendProvider({environment,fetcher:async()=>new Response('rejected',{status:403})});
  await assert.rejects(rejected.send(dispatch()),error=>error.uncertain===false && error.statusCode===422);
  const limited=createAutomatedSupportResendProvider({environment,fetcher:async()=>Response.json({},{status:429})});
  await assert.rejects(limited.send(dispatch()),error=>error.uncertain===false && error.retryable===true);
});
test('inbound original is fetched only by a validated provider ID, without inline image expansion', async () => {
  const id=randomUUID(),requests=[];
  const provider=createAutomatedSupportResendProvider({environment,fetcher:async(url,options)=>{
    requests.push({url,options});return Response.json({id,text:'Reply'});
  }});
  assert.equal((await provider.receive(id)).text,'Reply');
  assert.equal(requests[0].url,'https://api.resend.com/emails/receiving/'+id+'?html_format=cid');
  assert.equal(requests[0].options.redirect,'error');
  await assert.rejects(provider.receive('../secrets'));
  assert.equal(requests.length,1);
});
