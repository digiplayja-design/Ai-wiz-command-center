import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createAutomatedSupportRuntime} from '../automated_support/runtime.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
const reporter = '22222222-2222-4222-8222-222222222222';
const reportId = 'korlix_report_33333333-3333-4333-8333-333333333333';
const profile = {id:'main-support',ownerUid:owner,appKeys:['korlix_ai'],displayName:'KORLIX Support',
  fromEmail:'support@example.test',replyTo:'replies@example.test',inboundAddresses:['replies@example.test'],
  senderVerified:true,receivingVerified:true,dailyCap:20};
const environment = () => ({KORLIX_SUPPORT_PROFILES_JSON:JSON.stringify([profile]),
  KORLIX_AUTOMATED_SUPPORT_ENABLED:'true',KORLIX_AUTOMATED_SUPPORT_PAUSED:'false',
  RESEND_API_KEY:'synthetic-key',KORLIX_SUPPORT_WEBHOOK_SECRET:'whsec_c3ludGhldGlj',
  KORLIX_SUPPORT_THREAD_SECRET:'synthetic-thread-secret-with-32-characters'});

// This adapter models only worker handoff/release, not the SQL claims or quotas.
// The migration tests independently verify those transaction boundaries.
function fixture(options = {}) {
  let current = Date.parse('2026-11-10T03:00:00Z');
  const report = {id:reportId,userId:reporter,userEmail:'reporter@example.test',
    userEmailVerified:true,createdAt:new Date(current).toISOString(),
    appArea:'app_wide_ai_reporting',platform:'android',details:'Cannot load a feature'};
  const calls = [], cases = [], queued = [], failures = [], sent = [];
  let intakeState = 'pending', nextAttempt = current, lookups = 0;
  const store = {
    async syncProfile() { calls.push('sync'); return {mode:'automatic'}; },
    async claimIntake() {
      calls.push('claimIntake');
      if (intakeState !== 'pending' || current < nextAttempt) return null;
      intakeState = 'processing'; return {reportId,report};
    },
    async releaseIntake() { calls.push('releaseIntake'); intakeState = 'pending'; nextAttempt = current + 60000; },
    async completeIntake(input) {
      calls.push('completeIntake'); intakeState = 'processed';
      const record = {...input.caseData,profileId:input.profile.id,ownerUid:input.profile.ownerUid};
      const message = {...input.messageData,caseId:record.id,profileId:input.profile.id,ownerUid:input.profile.ownerUid,status:'pending'};
      cases.push(record); queued.push(message); return record;
    },
    async settleStale() { calls.push('settleStale'); },
    async pendingCases() { return queued.filter(message => message.status === 'pending').map(message => message.caseId); },
    async claimMessage({caseId}) {
      const caseRecord = cases.find(row => row.id === caseId);
      const message = queued.find(row => row.caseId === caseId && row.status === 'pending');
      if (!caseRecord?.reporterVerified || !message) return null;
      message.status = 'sending'; return {caseRecord,message};
    },
    async finishMessage({messageId,status}) { queued.find(row => row.id === messageId).status = status; return true; },
    ...options.store,
  };
  const database = {auth:{admin:{async getUserById(id) {
    assert.equal(id,reporter); lookups++;
    if (options.lookup) return options.lookup(lookups);
    return {data:{user:{id:reporter,email:'reporter@example.test',email_confirmed_at:'2026-11-01T00:00:00Z'}},error:null};
  }}}};
  const provider = {async send(input) { sent.push(input); return {accepted:true,providerMessageId:'44444444-4444-4444-8444-444444444444'}; },async receive() { throw new Error('No inbound fetch expected'); }};
  const app = express();
  const runtime = createAutomatedSupportRuntime({app,database,store,provider,
    requireUser:async()=>({id:owner}),environment:options.environment || environment(),
    now:()=>current,autostart:false,onError:()=>failures.push('unavailable'),
    ...(options.resolveReporter ? {resolveReporter:options.resolveReporter} : {})});
  return {app,runtime,calls,cases,queued,sent,failures,report,
    advance:ms=>{current+=ms;},get lookupCount(){return lookups;},get intakeState(){return intakeState;}};
}

test('an installation without enrolled support profiles performs no worker, account, or send operations', async () => {
  const f = fixture({environment:{}});
  assert.equal(f.runtime.configured,false);
  await f.runtime.wake(); await f.runtime.wake(); f.runtime.close();
  assert.deepEqual(f.calls,[]); assert.equal(f.lookupCount,0); assert.deepEqual(f.sent,[]);
});

test('invalid enrollment leaves the rest of the application available and never starts delivery', async t => {
  const f = fixture({environment:{KORLIX_SUPPORT_PROFILES_JSON:'{invalid'}});
  f.app.get('/api/health',(_req,res)=>res.json({ok:true}));
  const server = f.app.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base+'/api/health')).status,200);
  const response = await fetch(base+'/api/automated-support/profiles');
  assert.equal(response.status,503); assert.equal(response.headers.get('cache-control'),'no-store');
  assert(!JSON.stringify(await response.json()).includes('{invalid'));
  await f.runtime.wake(); assert.deepEqual(f.sent,[]); assert.deepEqual(f.calls,[]);
});

test('an account lookup outage releases durable intake for a later wake without sending or losing the report', async () => {
  const f = fixture({lookup:attempt=>attempt===1
    ? {error:{status:503,message:'private auth provider diagnostic'}}
    : {data:{user:{id:reporter,email:'reporter@example.test',email_confirmed_at:'2026-11-01T00:00:00Z'}},error:null}});
  await f.runtime.wake();
  assert.equal(f.intakeState,'pending'); assert.equal(f.cases.length,0); assert.equal(f.sent.length,0);
  assert(f.calls.includes('releaseIntake'));
  f.advance(60001); await f.runtime.wake();
  assert.equal(f.intakeState,'processed'); assert.equal(f.cases.length,1); assert.equal(f.sent.length,1);
  assert.equal(f.sent[0].caseRecord.reporterEmail,'reporter@example.test');
  await f.runtime.wake(); assert.equal(f.sent.length,1);
  f.runtime.close();
});

test('disabled sending still records reports for review without handing messages to the provider', async () => {
  const f = fixture({environment:{...environment(),KORLIX_AUTOMATED_SUPPORT_ENABLED:'false'}});
  await f.runtime.wake();
  assert.equal(f.cases.length,1); assert.equal(f.queued[0].status,'pending'); assert.equal(f.sent.length,0);
  f.runtime.close();
});

test('phone-only confirmation never verifies an email recipient, even when report metadata claims verification', async () => {
  const f = fixture({lookup:()=>({data:{user:{id:reporter,email:'reporter@example.test',
    email_confirmed_at:null,phone_confirmed_at:'2026-11-01T00:00:00Z',confirmed_at:'2026-11-01T00:00:00Z'}},error:null})});
  await f.runtime.wake();
  assert.equal(f.cases[0].reporterVerified,false);
  assert.equal(f.cases[0].state,'needs_review'); assert.equal(f.sent.length,0);
  f.runtime.close();
});

test('concurrent wakes share one in-flight drain and closing prevents another drain', async () => {
  let unblock;
  const gate = new Promise(resolve=>{unblock=resolve;});
  const f = fixture({resolveReporter:async()=>{await gate;return {id:reporter,email:'reporter@example.test',emailConfirmed:true};}});
  const first = f.runtime.wake(); const second = f.runtime.wake();
  unblock(); await Promise.all([first,second]);
  assert.equal(f.cases.length,1); assert.equal(f.sent.length,1);
  f.runtime.close(); const count = f.calls.length; await f.runtime.wake(); assert.equal(f.calls.length,count);
});

test('repeated storage outages are logged once until a successful wake, without leaking provider details', async () => {
  let offline = true;
  const f = fixture({store:{async syncProfile(){if(offline)throw new Error('private database credentials');return {mode:'paused'};}}});
  await f.runtime.wake(); await f.runtime.wake(); assert.deepEqual(f.failures,['unavailable']);
  offline = false; await f.runtime.wake();
  offline = true; await f.runtime.wake(); assert.deepEqual(f.failures,['unavailable','unavailable']);
  assert(!JSON.stringify(f.failures).includes('credentials')); f.runtime.close();
});
