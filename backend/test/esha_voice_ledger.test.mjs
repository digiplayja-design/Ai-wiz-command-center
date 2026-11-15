import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {createEshaVoiceLedger} from '../esha/billing/voice_ledger.mjs';
import {digest, EshaBillingError} from '../esha/billing/catalog.mjs';

const owner='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const first='33333333-3333-4333-8333-333333333333', next='44444444-4444-4444-8444-444444444444';
const deepId='55555555-5555-4555-8555-555555555555';
const inputHash=digest('voice-offer-and-consent'), requestHash=digest('server-owned-live-request');
const reserve={requestId:first,inputHash,reserveSeconds:60,deepThinkingConsent:false};
// Explicit offline engineering fixtures; these are not production defaults.
const environment={KORLIX_ESHA_TRIAL_VOICE_START_ATTEMPTS:'5',KORLIX_ESHA_MONTHLY_VOICE_START_ATTEMPTS:'20'};
let db, ledger;
const facts=(overrides={})=>{
  const now=Date.now()-1000;
  return {purchase_key:digest('purchase1'),provider:'apple',provider_token:'1234567890',
    product_id:'com.korlixdeveloper.esha.monthly',period_key:digest('period1'),
    period_started_at:new Date(now-10000).toISOString(),expires_at:new Date(now+86400000).toISOString(),
    active:true,revoked:false,trial:true,auto_renewing:true,test_purchase:false,
    provider_updated_at:new Date(now).toISOString(),observed_at:new Date(now).toISOString(),allowance:2,...overrides};
};
function known(error){
  const match=/ESHA(\d{3}):([a-z_]+):([^\n]+)/.exec(error.message||'');
  return match?new EshaBillingError(match[3],Number(match[1]),match[2]):error;
}
async function billing(actor,action,p={}) {
  try{return (action==='begin_provider_attempt'
    ?await db.query('select public.korlix_esha_begin_provider_attempt($1,$2) result',[actor,JSON.stringify(p)])
    :await db.query('select public.korlix_esha_billing_command($1,$2,$3) result',[actor,action,JSON.stringify(p)])).rows[0].result;}
  catch(error){throw known(error);}
}
const database={rpc:async(name,parameters)=>{
  assert.equal(name,'korlix_esha_voice_command');
  try{return {data:(await db.query('select public.korlix_esha_voice_command($1,$2,$3) result',
    [parameters.p_actor,parameters.p_action,JSON.stringify(parameters.p)])).rows[0].result,error:null};}
  catch(error){return {data:null,error:{message:error.message}};}
}};
async function start(options={},target=ledger){
  await target.reserve(owner,{...reserve,...options});
  assert.equal((await target.begin(owner,{requestId:options.requestId||first,inputHash,requestHash})).started,true);
  return target.attach(owner,{requestId:options.requestId||first,sessionId:options.sessionId||'live_fixture',
    expiresAt:new Date(Date.now()+3600000).toISOString()});
}
const final=(overrides={})=>({requestId:first,sessionId:'live_fixture',eventId:'evt_final',reason:'close_requested',seconds:20,...overrides});
test.before(async()=>{
  db=new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key);');
  const files=(await readdir(new URL('../../supabase/migrations/',import.meta.url))).filter(file=>
    /_esha_(store_billing|provider_attempt_budget|live_voice_ledger|sol_deep_attempts)\.sql$/.test(file)).sort();
  assert.equal(files.length,4);
  for(const file of files){
    try{await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));}
    catch(error){throw new Error(`${file}: ${error.message} at SQL character ${error.position}`);}
  }
  await db.query('insert into auth.users values($1),($2)',[owner,other]);
  ledger=createEshaVoiceLedger({database,environment});
});
test.beforeEach(async()=>{
  await db.exec('reset role; truncate korlix_esha_billing_accounts,korlix_esha_voided_periods cascade; set role service_role;');
  await billing(owner,'apply',facts());
});
test.after(async()=>db?.close());

test('approved grants reserve voice separately from deep counts, reject changed identity and serialize one unfinished session',async()=>{
  const before=await ledger.snapshot(owner);
  assert.equal(before.usage.voice.limitSeconds,300);assert.equal(before.usage.deep.limit,2);
  const held=await ledger.reserve(owner,reserve);
  assert.equal(held.created,true);assert.equal(held.finalizationConfirmed,false);assert.equal(held.closeRequired,false);
  assert.equal(held.usage.voice.reservedSeconds,60);assert.equal(held.usage.voice.remainingSeconds,240);
  assert.equal(held.usage.deep.remaining,2);
  const concurrent=await Promise.all([ledger.reserve(owner,reserve),ledger.reserve(owner,reserve)]);
  assert(concurrent.every(x=>x.created===false));
  assert.equal((await ledger.snapshot(owner)).usage.voice.reservedSeconds,60);
  await assert.rejects(ledger.reserve(owner,{...reserve,inputHash:digest('changed')}),{code:'idempotency_mismatch'});
  await assert.rejects(ledger.reserve(owner,{...reserve,requestId:next}),{code:'voice_session_in_progress'});
});

test('only an unstarted cancellation releases time; it becomes an idempotent confirmed zero-use closure',async()=>{
  await ledger.reserve(owner,reserve);
  for(let n=0;n<2;n++){
    const result=await ledger.requestClose(owner,{requestId:first,reason:'paused'});
    assert.equal(result.state,'closed');assert.equal(result.finalizationConfirmed,true);assert.equal(result.settledSeconds,0);
    assert.equal(result.usage.voice.reservedSeconds,0);assert.equal(result.usage.voice.remainingSeconds,300);
    assert.equal(result.usage.voiceStarts.used,0);
  }
  assert.equal((await ledger.begin(owner,{requestId:first,inputHash,requestHash})).started,false);
  assert.equal((await ledger.reserve(owner,{...reserve,requestId:next})).created,true);
});

test('a lost committed begin response never authorizes a retry or refunds uncertain provider time',async()=>{
  await ledger.reserve(owner,reserve);
  let failed=false,providerCalls=0;
  const fault=createEshaVoiceLedger({environment,database:{rpc:async(name,p)=>{
    const result=await database.rpc(name,p);
    if(p.p_action==='begin'&&!failed){failed=true;return {error:{message:'Lost reply after transaction commit'}};}
    return result;
  }}});
  await assert.rejects((async()=>{
    const authorization=await fault.begin(owner,{requestId:first,inputHash,requestHash});
    if(authorization.started)providerCalls++;
  })(),{code:'storage_unavailable'});
  assert.equal(providerCalls,0);
  assert.equal((await ledger.begin(owner,{requestId:first,inputHash,requestHash})).started,false);
  const uncertain=await ledger.markUncertain(owner,{requestId:first,reason:'create_unconfirmed'});
  assert.equal(uncertain.finalizationConfirmed,false);assert.equal(uncertain.usage.voice.reservedSeconds,60);
  assert.equal(uncertain.usage.voiceStarts.used,1);assert.equal(uncertain.usage.voiceStarts.remaining,4);
  await db.query("update korlix_esha_voice_sessions set authorized_until=now()-interval '1 hour' where user_id=$1",[owner]);
  const closing=await ledger.requestClose(owner,{requestId:first,reason:'transport_error'});
  assert.equal(closing.state,'closing');assert.equal(closing.finalizationConfirmed,false);
  assert.equal(closing.usage.voice.reservedSeconds,60);
  assert.equal(closing.usage.voiceStarts.used,1);
  await assert.rejects(ledger.reserve(owner,{...reserve,requestId:next}),{code:'voice_session_in_progress'});
});

test('missing start caps block only new work; reserved and started UUID replays and finalization remain recoverable',async()=>{
  const disabled=createEshaVoiceLedger({database,environment:{}});
  const empty=await disabled.snapshot(owner);
  assert.equal(empty.usage.voiceStarts.configured,false);assert.equal(empty.usage.voiceStarts.limit,null);
  await assert.rejects(disabled.reserve(owner,reserve),{code:'voice_start_attempts_not_configured'});
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_sessions')).rows[0].count,0);
  await ledger.reserve(owner,reserve);
  assert.equal((await disabled.reserve(owner,reserve)).replay,true);
  await assert.rejects(disabled.begin(owner,{requestId:first,inputHash,requestHash}),{code:'voice_start_attempts_not_configured'});
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_start_budgets')).rows[0].count,0);
  assert.equal((await disabled.requestClose(owner,{requestId:first,reason:'paused'})).finalizationConfirmed,true);
  await start({requestId:next});
  assert.equal((await disabled.reserve(owner,{...reserve,requestId:next})).replay,true);
  assert.equal((await disabled.begin(owner,{requestId:next,inputHash,requestHash})).started,false);
  await disabled.recordUsage(owner,{requestId:next,sessionId:'live_fixture',seconds:5.8});
  await disabled.requestClose(owner,{requestId:next,reason:'user_stop'});
  const closed=await disabled.settle(owner,final({requestId:next,seconds:5.8}));
  assert.equal(closed.finalizationConfirmed,true);assert.equal(closed.usage.voice.usedSeconds,5.8);
  assert.equal(closed.usage.voiceStarts.configured,false);assert.equal(closed.usage.voiceStarts.limit,5);
  assert.equal(closed.usage.voiceStarts.used,1);assert.equal(closed.usage.voiceStarts.remaining,0);
  assert.equal((await disabled.status(owner,next)).state,'closed');
});

test('the first committed begin pins the start cap and concurrent duplicate begins consume exactly one attempt',async()=>{
  await ledger.reserve(owner,reserve);
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_start_budgets')).rows[0].count,0);
  const selected=createEshaVoiceLedger({database,environment:{...environment,KORLIX_ESHA_TRIAL_VOICE_START_ATTEMPTS:'2'}});
  const replies=await Promise.all([selected.begin(owner,{requestId:first,inputHash,requestHash}),
    selected.begin(owner,{requestId:first,inputHash,requestHash})]);
  assert.equal(replies.filter(result=>result.started).length,1);
  const status=await selected.status(owner,first);
  assert.equal(status.usage.voiceStarts.limit,2);assert.equal(status.usage.voiceStarts.used,1);
  assert.equal(status.usage.voiceStarts.remaining,1);
  // Changing the setting cannot alter an existing debit or authorize a retry.
  assert.equal((await ledger.begin(owner,{requestId:first,inputHash,requestHash})).started,false);
  assert.equal((await ledger.status(owner,first)).usage.voiceStarts.configured,false);
  await selected.attach(owner,{requestId:first,sessionId:'live_fixture',expiresAt:null});
  await selected.settle(owner,final({seconds:0}));
  await selected.reserve(owner,{...reserve,requestId:next});
  await assert.rejects(ledger.begin(owner,{requestId:next,inputHash,requestHash}),{code:'voice_start_budget_conflict'});
  const blocked=await ledger.status(owner,next);
  assert.equal(blocked.state,'reserved');assert.equal(blocked.usage.voiceStarts.used,1);
  // Conflict does not hide the reservation or prevent safe unstarted cleanup.
  assert.equal((await ledger.reserve(owner,{...reserve,requestId:next})).replay,true);
  const cancelled=await ledger.requestClose(owner,{requestId:next,reason:'paused'});
  assert.equal(cancelled.finalizationConfirmed,true);assert.equal(cancelled.usage.voiceStarts.used,1);
});

test('zero-duration initialized sessions exhaust independent start limits; restore or configuration changes never refill them',async()=>{
  const bounded=createEshaVoiceLedger({database,environment:{...environment,KORLIX_ESHA_TRIAL_VOICE_START_ATTEMPTS:'2'}});
  for(const [requestId,sessionId] of [[first,'live_first_zero'],[next,'live_next_zero']]){
    await start({requestId,sessionId},bounded);
    await bounded.requestClose(owner,{requestId,reason:'paused'});
    const closed=await bounded.settle(owner,final({requestId,sessionId,seconds:0}));
    assert.equal(closed.settledSeconds,0);assert.equal(closed.usage.voice.usedSeconds,0);
    assert.equal(closed.usage.voice.remainingSeconds,300);
  }
  let snapshot=await bounded.snapshot(owner);
  assert.equal(snapshot.usage.voiceStarts.limit,2);assert.equal(snapshot.usage.voiceStarts.used,2);
  assert.equal(snapshot.usage.voiceStarts.remaining,0);
  // A replay precedes all cap checks, so a prior UUID is never misreported as
  // an absent, pre-reservation no-provider-work rejection.
  for(const target of [bounded,ledger,createEshaVoiceLedger({database,environment:{}})]){
    assert.equal((await target.reserve(owner,reserve)).replay,true);
    assert.equal((await target.begin(owner,{requestId:first,inputHash,requestHash})).started,false);
  }
  await assert.rejects(bounded.reserve(owner,{...reserve,requestId:deepId}),{code:'voice_start_attempts_exhausted'});
  await billing(owner,'apply',facts({allowance:999}));
  await assert.rejects(bounded.reserve(owner,{...reserve,requestId:deepId}),{code:'voice_start_attempts_exhausted'});
  for(const value of ['1','5']){
    const changed=createEshaVoiceLedger({database,environment:{...environment,KORLIX_ESHA_TRIAL_VOICE_START_ATTEMPTS:value}});
    await assert.rejects(changed.reserve(owner,{...reserve,requestId:deepId}),{code:'voice_start_budget_conflict'});
    snapshot=await changed.snapshot(owner);
    assert.equal(snapshot.usage.voiceStarts.configured,false);assert.equal(snapshot.usage.voiceStarts.limit,2);
    assert.equal(snapshot.usage.voiceStarts.used,2);assert.equal(snapshot.usage.voiceStarts.remaining,0);
  }
  assert.equal((await bounded.snapshot(owner)).usage.voiceStarts.remaining,0);
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_sessions')).rows[0].count,2);
});

test('provider identity persists before startup without invented expiry; later verified expiry cannot change or disappear',async()=>{
  await ledger.reserve(owner,reserve);
  await ledger.begin(owner,{requestId:first,inputHash,requestHash});
  const identity={requestId:first,sessionId:'live_fixture',expiresAt:null};
  let result=await ledger.attach(owner,identity);
  assert.equal(result.sessionId,'live_fixture');assert.equal(result.providerExpiresAt,null);assert.equal(result.state,'starting');
  const expiresAt=new Date(Date.now()+3600000).toISOString();
  result=await ledger.attach(owner,{...identity,expiresAt});
  assert.equal(Date.parse(result.providerExpiresAt),Date.parse(expiresAt));assert.equal(result.state,'active');
  assert.equal(Date.parse((await ledger.attach(owner,identity)).providerExpiresAt),Date.parse(expiresAt));
  await assert.rejects(ledger.attach(owner,{...identity,expiresAt:new Date(Date.now()+7200000).toISOString()}),{code:'idempotency_mismatch'});
});

test('cumulative fractional usage settles exactly once without inventing a startup-duration floor',async()=>{
  await start();
  for(const seconds of [12,15,13,15])await ledger.recordUsage(owner,{requestId:first,sessionId:'live_fixture',seconds});
  assert.equal((await ledger.status(owner,first)).observedSeconds,15);
  let result=await ledger.settle(owner,final({seconds:45.8}));
  assert.equal(result.state,'closed');assert.equal(result.finalizationConfirmed,true);
  assert.equal(result.usage.voice.usedSeconds,45.8);assert.equal(result.usage.voice.remainingSeconds,254.2);
  result=await ledger.settle(owner,final({seconds:45.8}));assert.equal(result.duplicate,true);
  assert.equal(result.usage.voice.usedSeconds,45.8);
  await ledger.recordUsage(owner,{requestId:first,sessionId:'live_fixture',seconds:40});
  assert.equal((await ledger.snapshot(owner)).usage.voice.usedSeconds,45.8);
  await assert.rejects(ledger.settle(owner,final({seconds:50})),{code:'voice_final_usage_conflict'});
  await start({requestId:next,sessionId:'live_second'});
  result=await ledger.settle(owner,final({requestId:next,sessionId:'live_second',eventId:'evt_second',seconds:5.8}));
  assert.equal(result.settledSeconds,5.8);assert.equal(result.usage.voice.usedSeconds,51.6);
});

test('final duration below a prior observation retains an uncertain hold; consistent90s and zero durations settle exactly',async()=>{
  await start({reserveSeconds:120});
  await ledger.recordUsage(owner,{requestId:first,sessionId:'live_fixture',seconds:90});
  await assert.rejects(ledger.settle(owner,final({seconds:80})),{code:'voice_final_usage_conflict'});
  let status=await ledger.status(owner,first);
  assert.equal(status.state,'uncertain');assert.equal(status.finalizationConfirmed,false);
  assert.equal(status.usage.voice.reservedSeconds,120);assert.equal(status.usage.voice.usedSeconds,0);
  status=await ledger.settle(owner,final({seconds:90}));assert.equal(status.settledSeconds,90);
  await start({requestId:next,sessionId:'live_zero'});
  status=await ledger.settle(owner,final({requestId:next,sessionId:'live_zero',eventId:'evt_zero',seconds:0}));
  assert.equal(status.settledSeconds,0);assert.equal(status.usage.voice.usedSeconds,90);
});

test('a lost committed settlement response reconciles as closed without consuming time twice',async()=>{
  await start();
  let failed=false;
  const fault=createEshaVoiceLedger({environment,database:{rpc:async(name,p)=>{
    const result=await database.rpc(name,p);
    if(p.p_action==='settle'&&!failed){failed=true;return {error:{message:'Lost reply after settlement commit'}};}
    return result;
  }}});
  await assert.rejects(fault.settle(owner,final({seconds:5.8})),{code:'storage_unavailable'});
  const recovered=await ledger.status(owner,first);
  assert.equal(recovered.state,'closed');assert.equal(recovered.finalizationConfirmed,true);
  assert.equal(recovered.usage.voice.usedSeconds,5.8);assert.equal(recovered.usage.voice.reservedSeconds,0);
  assert.equal((await ledger.settle(owner,final({seconds:5.8}))).usage.voice.usedSeconds,5.8);
});

test('provider overshoot is accounted honestly, demands closure, and cannot grant another session',async()=>{
  await start({reserveSeconds:300});
  const observed=await ledger.recordUsage(owner,{requestId:first,sessionId:'live_fixture',seconds:301.25});
  assert.equal(observed.overrun,true);assert.equal(observed.closeRequired,true);
  assert.equal(observed.usage.voice.remainingSeconds,0);assert.equal(observed.usage.voice.reservedSeconds,301.25);
  const closed=await ledger.settle(owner,final({seconds:301.25}));
  assert.equal(closed.usage.voice.usedSeconds,301.25);assert.equal(closed.usage.voice.remainingSeconds,0);
  await assert.rejects(ledger.reserve(owner,{...reserve,requestId:next}),{code:'voice_allowance_exhausted'});
});

test('refund, stale verification and account ownership are checked before start; settlement remains possible after revocation',async()=>{
  await ledger.reserve(owner,reserve);
  await db.query("update korlix_esha_purchases set observed_at=now()-interval '16 minutes'");
  await assert.rejects(ledger.begin(owner,{requestId:first,inputHash,requestHash}),{code:'verification_stale'});
  await billing(owner,'apply',facts());
  assert.equal((await ledger.begin(owner,{requestId:first,inputHash,requestHash})).started,true);
  await ledger.attach(owner,{requestId:first,sessionId:'live_fixture',expiresAt:new Date(Date.now()+3600000).toISOString()});
  await billing(null,'record_void',{purchase_key:facts().purchase_key,period_key:facts().period_key});
  assert.equal((await ledger.status(owner,first)).closeRequired,true);
  await ledger.snapshot(other);
  await assert.rejects(ledger.status(other,first),{code:'voice_session_not_found'});
  await assert.rejects(ledger.begin(other,{requestId:first,inputHash,requestHash}),{code:'voice_session_not_found'});
  await assert.rejects(ledger.settle(other,final()),{code:'voice_session_not_found'});
  assert.equal((await ledger.status(owner,first)).usage.voiceStarts.used,1);
  assert.equal((await ledger.snapshot(other)).usage.voiceStarts.used,0);
  await assert.rejects(ledger.settle(owner,final({sessionId:'live_other'})),{code:'invalid_voice_usage'});
  assert.equal((await ledger.settle(owner,final())).usage.voice.usedSeconds,20);
  await assert.rejects(ledger.reserve(owner,{...reserve,requestId:next}),{code:'membership_required'});
});

test('renewal creates the approved monthly budget without rollover and restores never refill the current period',async()=>{
  await start();await ledger.settle(owner,final({seconds:45}));
  await billing(owner,'apply',facts({allowance:999}));
  assert.equal((await ledger.snapshot(owner)).usage.voice.remainingSeconds,255);
  assert.equal((await ledger.snapshot(owner)).usage.voiceStarts.used,1);
  await billing(owner,'apply',facts({trial:false,allowance:10,period_key:digest('renewal'),
    period_started_at:new Date(Date.now()-500).toISOString(),expires_at:new Date(Date.now()+30*86400000).toISOString()}));
  const newPeriod=await ledger.snapshot(owner);
  assert.equal(newPeriod.usage.voice.limitSeconds,1800);assert.equal(newPeriod.usage.voice.remainingSeconds,1800);
  assert.equal(newPeriod.usage.deep.remaining,10);
  assert.equal(newPeriod.usage.voiceStarts.limit,20);assert.equal(newPeriod.usage.voiceStarts.used,0);
  assert.equal(newPeriod.usage.voiceStarts.remaining,20);
  await start({requestId:next,sessionId:'live_renewal'});
  assert.equal((await ledger.status(owner,first)).usage.voice.remainingSeconds,0);
  assert.equal((await ledger.status(owner,first)).usage.voiceStarts.limit,5);
  assert.equal((await ledger.status(owner,first)).usage.voiceStarts.used,1);
  assert.equal((await ledger.status(owner,first)).usage.voiceStarts.remaining,0);
  assert.equal((await ledger.status(owner,next)).usage.voiceStarts.used,1);
  assert.equal((await ledger.status(owner,next)).usage.voiceStarts.remaining,19);
});

test('consented delegation maps one immutable consultation identity; cancelled voice cannot authorize a later Sol debit',async()=>{
  await start();
  const mapping={requestId:first,sessionId:'live_fixture',delegationId:'item_deep',inputHash:digest('question'),consultationRequestId:deepId};
  await assert.rejects(ledger.delegation(owner,mapping),{code:'deep_thinking_consent_required'});
  await ledger.settle(owner,final());
  await start({requestId:next,sessionId:'live_consent',deepThinkingConsent:true});
  const allowed={...mapping,requestId:next,sessionId:'live_consent'};
  assert.equal((await ledger.delegation(owner,allowed)).consultationRequestId,deepId);
  const duplicate=await ledger.delegation(owner,{...allowed,consultationRequestId:first});
  assert.equal(duplicate.created,false);assert.equal(duplicate.consultationRequestId,deepId);
  await assert.rejects(ledger.delegation(owner,{...allowed,inputHash:digest('different')}),{code:'idempotency_mismatch'});
  await billing(owner,'reserve',{request_id:deepId,input_hash:mapping.inputHash});
  await ledger.requestClose(owner,{requestId:next,reason:'background'});
  await assert.rejects(billing(owner,'begin_provider_attempt',solAttempt(deepId,mapping.inputHash)),{code:'voice_session_finished'});
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_provider_attempts')).rows[0].count,0);
});

function solAttempt(id,hash){return {request_id:id,input_hash:hash,request_hash:digest('sol-request'),model:'gpt-6.1-sol',
  reasoning_effort:'high',input_tokens:1000,max_input_tokens:8192,max_output_tokens:4096,trial_limit:3,monthly_limit:6};}

test('a paid Sol response completed after voice closes remains recoverable only through its owning session',async()=>{
  await start({deepThinkingConsent:true});
  const hash=digest('validated consultation context');
  await ledger.delegation(owner,{requestId:first,sessionId:'live_fixture',delegationId:'item_result',inputHash:hash,consultationRequestId:deepId});
  await billing(owner,'reserve',{request_id:deepId,input_hash:hash});
  assert.equal((await billing(owner,'begin_provider_attempt',solAttempt(deepId,hash))).started,true);
  await ledger.settle(owner,final());
  const result={answer:'Compare the listed satin finishes.',productIds:['elf-o-face-dirty-talk']};
  await billing(owner,'commit',{request_id:deepId,input_hash:hash,result});
  const status=await ledger.status(owner,first);
  assert.equal(status.state,'closed');assert.equal(status.usage.deep.used,1);
  assert.deepEqual(status.deepResults,[{requestId:deepId,...result}]);
  assert.equal((await ledger.snapshot(owner)).deepResults,undefined);
  await ledger.snapshot(other);
  await assert.rejects(ledger.status(other,first),{code:'voice_session_not_found'});
  await start({requestId:next,sessionId:'live_unrelated',deepThinkingConsent:true});
  assert.deepEqual((await ledger.status(owner,next)).deepResults,[]);
});

test('additive Sol ledger permits only high with approved successful counts, preserves irreversible debit and rejects Live',async()=>{
  const hash=digest('standalone question');
  await billing(owner,'reserve',{request_id:deepId,input_hash:hash});
  const body=solAttempt(deepId,hash);
  for(const change of [{reasoning_effort:'low'},{max_output_tokens:128001},{model:'gpt-live-1'}]){
    await assert.rejects(billing(owner,'begin_provider_attempt',{...body,...change}),{code:'provider_budget_unconfigured'});
  }
  assert.equal((await billing(owner,'begin_provider_attempt',body)).started,true);
  assert.equal((await billing(owner,'begin_provider_attempt',body)).started,false);
  await billing(owner,'release',{request_id:deepId,input_hash:hash});
  assert.equal((await db.query('select used from korlix_esha_provider_budgets')).rows[0].used,1);
  assert.equal((await ledger.snapshot(owner)).usage.deep.remaining,2);
  // Verify the additive model change did not remove the original table-level
  // input<=cap guard, independently of the RPC's own input validation.
  await billing(owner,'reserve',{request_id:next,input_hash:hash});
  await assert.rejects(db.query(`insert into korlix_esha_provider_attempts(user_id,request_id,period_key,input_hash,request_hash,
    model,reasoning_effort,input_tokens,max_input_tokens,max_output_tokens)
    select user_id,$1,period_key,input_hash,request_hash,model,reasoning_effort,2,1,max_output_tokens
    from korlix_esha_provider_attempts where user_id=$2 and request_id=$3`,[next,owner,deepId]),/check constraint/);
});

test('voice RPC/tables are inaccessible to public clients and owning-account deletion removes voice/delegation records',async()=>{
  await start({deepThinkingConsent:true});
  await ledger.delegation(owner,{requestId:first,sessionId:'live_fixture',delegationId:'item_delete',inputHash:digest('question'),consultationRequestId:deepId});
  await db.exec('reset role');
  const security=await db.query("select relname,relrowsecurity from pg_class where relname in ('korlix_esha_voice_budgets','korlix_esha_voice_start_budgets','korlix_esha_voice_sessions','korlix_esha_voice_delegations')");
  assert.equal(security.rows.length,4);assert(security.rows.every(x=>x.relrowsecurity));
  for(const role of ['anon','authenticated']){
    await db.exec(`set role ${role}`);
    await assert.rejects(db.query('select * from korlix_esha_voice_sessions'),/permission denied/);
    await assert.rejects(db.query('select * from korlix_esha_voice_start_budgets'),/permission denied/);
    await assert.rejects(db.query('select korlix_esha_voice_command($1,$2,$3)',[owner,'snapshot','{}']),/permission denied/);
    await db.exec('reset role');
  }
  await db.query('delete from auth.users where id=$1',[owner]);
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_sessions')).rows[0].count,0);
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_delegations')).rows[0].count,0);
  assert.equal((await db.query('select count(*)::integer count from korlix_esha_voice_start_budgets')).rows[0].count,0);
  await db.query('insert into auth.users values($1)',[owner]);
});
