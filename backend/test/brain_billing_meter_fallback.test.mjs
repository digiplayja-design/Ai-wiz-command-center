import test from 'node:test';
import assert from 'node:assert/strict';
import {createBrainBilling} from '../brain_voice/billing/routes.mjs';
import {BillingError} from '../web_billing/core.mjs';

const userId='11111111-1111-4111-8111-111111111111';
const sessionId='33333333-3333-4333-8333-333333333333';
const session=()=>({
  id:sessionId,
  user_id:userId,
  call_id:'rtc_meter_regression',
  deadline:new Date(Date.now()+3600000).toISOString(),
});
const command=action=>({p_actor:userId,p_action:action,p:{sessionId}});

function fixture(t,reply,fetcher=async()=>assert.fail('Unexpected provider request')) {
  const calls=[];
  const billing=createBrainBilling({
    // Exercise the production RPC adapter: injecting `store` bypasses BillingError.
    database:{rpc:async(name,args)=>{
      assert.equal(name,'korlix_brain_billing_command');
      calls.push(args);
      return reply(args.p_action);
    }},
    provider:{},
    environment:{KORLIX_BRAIN_BILLING_ENABLED:'true',OPENAI_API_KEY:'test-only'},
    autoStart:false,
    fetcher,
  });
  t.after(()=>billing.stop());
  return {billing,calls};
}

for(const ended of [false,true]) {
  test(`ordinary session missing from Brain ledger returns null (${ended?'final':'periodic'} report)`,async t=>{
    const {billing,calls}=fixture(t,()=>({error:{message:'BILL404: Voice session not found.'}}));
    assert.equal(await billing.usage(userId,{sessionId,ended}),null);
    assert.deepEqual(calls,[command('session')]);
  });
}

test('legacy statusCode 404 from the session lookup still permits ordinary metering',async t=>{
  const legacyError=Object.assign(new Error('Voice session not found.'),{statusCode:404});
  const {billing,calls}=fixture(t,()=>{throw legacyError;});
  assert.equal(await billing.usage(userId,{sessionId}),null);
  assert.deepEqual(calls,[command('session')]);
});

test('an unavailable database remains a 503 failure rather than permitting ordinary metering',async t=>{
  const {billing,calls}=fixture(t,()=>({error:{message:'Database connection unavailable'}}));
  await assert.rejects(billing.usage(userId,{sessionId}),error=>{
    assert(error instanceof BillingError);
    assert.equal(error.status,503);
    assert.equal(error.message,'Your minute balance is temporarily unavailable. Please retry.');
    return true;
  });
  assert.deepEqual(calls,[command('session')]);
});

test('a denied Brain session remains a 403 failure rather than permitting ordinary metering',async t=>{
  const {billing,calls}=fixture(t,()=>({error:{message:'BILL403: Session access denied.'}}));
  await assert.rejects(billing.usage(userId,{sessionId}),error=>{
    assert(error instanceof BillingError);
    assert.equal(error.status,403);
    assert.equal(error.message,'Session access denied.');
    return true;
  });
  assert.deepEqual(calls,[command('session')]);
});

test('an existing Brain session continues through the Brain usage meter',async t=>{
  const active=session();
  const usage={allowed:true,chargedSeconds:15,limitReached:false};
  const {billing,calls}=fixture(t,action=>{
    if(action==='session')return {data:active};
    assert.equal(action,'usage');
    return {data:usage};
  });
  assert.equal(await billing.usage(userId,{sessionId,durationSeconds:999999}),usage);
  // Brain charging remains server-authoritative; no client duration enters the RPC.
  assert.deepEqual(calls,[command('session'),command('usage')]);
});

test('a failure after a successful Brain lookup does not fall through to ordinary metering',async t=>{
  const {billing,calls}=fixture(t,action=>{
    if(action==='session')return {data:session()};
    assert.equal(action,'usage');
    return {error:{message:'BILL404: Voice session not found.'}};
  });
  await assert.rejects(billing.usage(userId,{sessionId}),error=>{
    assert(error instanceof BillingError);
    assert.equal(error.status,404);
    return true;
  });
  assert.deepEqual(calls,[command('session'),command('usage')]);
});

test('ending an existing Brain session still stops the provider before finalizing usage',async t=>{
  const active=session();
  const ended={allowed:false,ended:true,chargedSeconds:15};
  const operations=[];
  const {billing,calls}=fixture(t,action=>{
    operations.push(action);
    if(action==='session')return {data:active};
    if(action==='stopped')return {data:{}};
    assert.equal(action,'end');
    return {data:ended};
  },async(url,options)=>{
    operations.push('hangup');
    assert.equal(url,'https://api.openai.com/v1/realtime/calls/rtc_meter_regression/hangup');
    assert.equal(options.method,'POST');
    return {ok:true,status:200};
  });
  assert.equal(await billing.usage(userId,{sessionId,ended:true}),ended);
  assert.deepEqual(operations,['session','session','hangup','stopped','end']);
  assert.deepEqual(calls,[command('session'),command('session'),command('stopped'),command('end')]);
});
