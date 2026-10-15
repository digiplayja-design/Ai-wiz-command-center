import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {accountId, observation, tokenHash, PACKAGE} from '../google_play/core.mjs';
import {googlePlay} from '../google_play/provider.mjs';
import {registerGooglePlay} from '../google_play/routes.mjs';

const owner = '11111111-1111-4111-8111-111111111111', other = '22222222-2222-4222-8222-222222222222';
const token = 'purchase-token-one', future = () => new Date(Date.now() + 86400000).toISOString();
const google = (extra = {}) => ({externalAccountIdentifiers: {obfuscatedExternalAccountId: accountId(owner)},
  subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
  lineItems: [{productId: 'korlix_pro', expiryTime: future(), offerDetails: {basePlanId: 'monthly'}, autoRenewingPlan: {autoRenewEnabled: true}}], ...extra});
const facts = (extra = {}) => observation(google(extra), {userId: owner, token});

test('Google facts bind exact account, product and monthly base plan', () => {
  assert.equal(facts().tier, 'pro');
  assert.equal(facts().active, true);
  assert.throws(() => observation(google(), {userId: other, token}), /different KORLIX account/);
  assert.throws(() => facts({externalAccountIdentifiers: {}}), /different KORLIX account/);
  assert.throws(() => observation(google(), {userId: owner, token, expectedProduct: 'korlix_ultra'}), /monthly plan/);
  assert.throws(() => facts({lineItems: [{...google().lineItems[0], offerDetails: {basePlanId: 'annual'}}]}), /monthly plan/);
  assert.throws(() => facts({lineItems: [google().lineItems[0], google().lineItems[0]]}), /Unsupported/);
});
test('pending, paused, held, expired and canceled payments have distinct access', () => {
  for (const state of ['PENDING','PAUSED','ON_HOLD','EXPIRED','PENDING_PURCHASE_CANCELED']) {
    assert.equal(facts({subscriptionState: 'SUBSCRIPTION_STATE_' + state}).active, false);
  }
  assert.equal(facts({subscriptionState: 'SUBSCRIPTION_STATE_CANCELED'}).active, true);
  assert.equal(facts({subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'}).active, true);
  assert.equal(facts({lineItems: [{...google().lineItems[0], expiryTime: '2020-01-01T00:00:00Z'}]}).active, false);
  assert.throws(() => facts({subscriptionState: 'UNKNOWN'}), /unknown/);
  assert.throws(() => facts({testPurchase: {}}), /designated test accounts/);
  assert.equal(observation(google({testPurchase: {}}), {userId: owner, token, allowTest: true}).test_purchase, true);
});
test('Google provider uses fixed package, verified notification identity and configured audience', async () => {
  const calls = [], payload = {email:'rtdn@example.iam.gserviceaccount.com',email_verified:true};
  const environment = {KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE:'https://backend.fixture/api/billing/google/notifications',
    KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT: payload.email, KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION:'projects/test/subscriptions/korlix'};
  const provider = googlePlay(environment, {auth:{request:async req=>{calls.push(req);return {data:google()};}},
    identity:{verifyIdToken:async args=>{assert.equal(args.audience,environment.KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE);return {getPayload:()=>payload};}}});
  await provider.subscription(token);
  assert.match(calls[0].url,new RegExp(PACKAGE));
  assert.equal(provider.ready,false);
  const req={headers:{authorization:'Bearer signed-token'},body:{subscription:environment.KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION,
    message:{data:Buffer.from(JSON.stringify({packageName:PACKAGE,testNotification:{}})).toString('base64')}}};
  assert.deepEqual((await provider.notification(req)).testNotification,{});
  await assert.rejects(provider.notification({...req,headers:{}}),/identity/);
  await assert.rejects(provider.notification({...req,body:{...req.body,subscription:'foreign'}}),/identity/);
  payload.email_verified=false;
  await assert.rejects(provider.notification(req),/identity/);
});
test('server catalog preflight rejects missing, inactive or annual-only plans before charging', async () => {
  let product={productId:'korlix_pro',basePlans:[{basePlanId:'monthly',state:'ACTIVE',autoRenewingBasePlanType:{billingPeriodDuration:'P1M'}}]};
  const provider=googlePlay({}, {auth:{request:async req=>{assert.match(req.url,/applications\/com\.korlixdeveloper\.korlixai\/subscriptions\/korlix_pro$/);return {data:product};}}});
  assert.equal(await provider.catalog('korlix_pro'),true);
  product.basePlans[0].state='INACTIVE';await assert.rejects(provider.catalog('korlix_pro'),/not available/);
  product.basePlans[0].state='ACTIVE';product.basePlans[0].autoRenewingBasePlanType.billingPeriodDuration='P1Y';
  await assert.rejects(provider.catalog('korlix_pro'),/not available/);
});

test('disabled billing can verify both catalogs; public health cannot trigger API calls or leak errors', async () => {
  const calls = []; let fails = false, clock = Date.now();
  const provider = {configured: true, ready: false, notificationsConfigured: false,
    catalog: async product => { calls.push(product); if (fails) throw new Error('private-key-fixture'); }};
  const billingApp = express();
  const billing = registerGooglePlay(billingApp, {provider, autoStart: false, now: () => clock,
    store: {command: async (_user, action) => { assert.equal(action, 'due'); return []; }}});
  const server = billingApp.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const health = async () => (await fetch(`http://127.0.0.1:${server.address().port}/api/billing/google/health`)).json();
  try {
    assert.deepEqual((await health()).catalogCheck, {checkedAt: null, ready: false, reason: null});
    assert.equal(calls.length, 0);
    await billing.tick();
    assert.deepEqual(calls.sort(), ['korlix_pro', 'korlix_ultra']);
    assert.equal((await health()).catalogCheck.ready, true);
    assert.equal((await health()).billingEnabled, false);
    await billing.tick(); assert.equal(calls.length, 2);
    fails = true; clock += 300000; await billing.tick();
    const result = await health();
    assert.equal(result.catalogCheck.ready, false);
    assert.equal(result.catalogCheck.reason, 'provider_request_failed');
    assert.equal(calls.length, 4);
    assert.equal(JSON.stringify(result).includes('private-key-fixture'), false);
  } finally { billing.stop(); await new Promise(resolve => server.close(resolve)); }
});

test('provider diagnostics use fixed codes and never include credential-bearing errors', async () => {
  const failures = [
    [{response:{status:403,data:{error:{details:[{reason:'SERVICE_DISABLED'}]}}}},'api_disabled'],
    [{response:{status:403,data:{error:{message:'secret-fixture'}}}},'permission_denied'],
    [{response:{status:400,data:{error:'invalid_grant',error_description:'secret-fixture'}}},'authentication_failed'],
    [{response:{status:404}},'product_not_found'],
    [{response:{status:503}},'temporarily_unavailable'],
    [new Error('secret-fixture'),'provider_request_failed'],
  ];
  for (const [failure, expected] of failures) {
    const provider = googlePlay({}, {auth:{request: async () => { throw failure; }}});
    await assert.rejects(provider.catalog('korlix_pro'), error => {
      assert.equal(error.googlePlayReason, expected);
      assert.equal(JSON.stringify(error).includes('secret-fixture'), false);
      assert.equal(error.message.includes('secret-fixture'), false);
      return true;
    });
  }
});

let db;
const rpc = async (actor,action,p={})=>(await db.query('select korlix_play_billing_command($1,$2,$3::jsonb) result',[actor,action,JSON.stringify(p)])).rows[0].result;
const profile=async(id=owner)=>(await db.query('select korlix_web_billing_profile($1) result',[id])).rows[0].result;
async function prepare(id=owner){return rpc(id,'prepare',{account_id:accountId(id)});}
async function apply(f=facts(),id=owner){const lease=await rpc(id,'claim');const result=await rpc(id,'apply',{...f,sync_token:lease.sync_token});await rpc(id,'release',{sync_token:lease.sync_token,success:true});return result;}
test.before(async()=>{
  db=new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
   create schema auth; create table auth.users(id uuid primary key);
   create table user_profiles(id uuid primary key references auth.users(id),tier text not null default 'basic',is_disabled boolean default false);
   create table subscriptions(user_id uuid,tier text,status text,current_period_end timestamptz);
   grant usage on schema public,auth to service_role;
   grant select,insert,update on user_profiles,subscriptions to service_role;
   create function korlix_has_unlimited_access(uuid) returns boolean language sql as 'select false';`);
  for(const file of ['202607130001_apple_subscriptions_build130.sql','20261004203621_web_plan_subscriptions.sql','20261007015513_apple_billing_security.sql'])
    await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../google_play/schema.sql',import.meta.url),'utf8'));
  for(const id of [owner,other]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles(id)values($1)',[id]);}
});
test.beforeEach(async()=>{await db.exec("reset role; delete from korlix_play_purchases; delete from korlix_play_billing_accounts; delete from korlix_web_billing_accounts; delete from apple_subscription_entitlements; delete from subscriptions; update user_profiles set tier='basic',is_disabled=false; set role service_role;");});
test.after(async()=>db?.close());
test('browser roles cannot read purchase tokens or grant themselves access',async()=>{
  for(const role of ['anon','authenticated']){
    await db.exec('reset role; set role '+role);
    await assert.rejects(db.query('select * from korlix_play_purchases'),/permission denied/);
    await assert.rejects(prepare(),/permission denied/);
  }
});
test('preparation creates no paid access; account grants remain intact',async()=>{
  assert.equal((await prepare()).canPurchase,true);
  assert.equal((await profile()).tier,'basic');
  await db.query("update user_profiles set tier='enterprise' where id=$1",[other]);
  await assert.rejects(prepare(other),/already has paid/);
  assert.equal((await profile(other)).tier,'enterprise');
});
test('purchase binds once and cannot be replayed to another account',async()=>{
  await prepare();await prepare(other);
  assert.equal((await apply()).tier,'pro');
  assert.equal((await profile(other)).tier,'basic');
  await assert.rejects(apply({...facts(),account_id:accountId(other)},other),/another account/);
  assert.equal((await profile(other)).tier,'basic');
});
test('expiry and revocation remove only Play access, manual developer tier survives',async()=>{
  await prepare();await apply();
  await db.query("update korlix_play_purchases set expires_at=now()-interval '1 second'");
  assert.equal((await profile()).tier,'basic');
  await apply();await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
  assert.equal((await profile()).tier,'enterprise');
  await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_EXPIRED'}));
  assert.equal((await profile()).tier,'enterprise');
});
test('renewal, cancellation, grace and holds follow the provider state',async()=>{
  await prepare();await apply();
  await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_CANCELED'}));assert.equal((await profile()).tier,'pro');
  await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_ON_HOLD'}));assert.equal((await profile()).tier,'basic');
  await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'}));assert.equal((await profile()).tier,'pro');
});
test('superseded token cannot regrant a tier after a replacement expires',async()=>{
  await prepare();await apply();
  const replacement={...facts(),product_id:'korlix_ultra',tier:'ultra',purchase_token:'replacement-token',token_hash:tokenHash('replacement-token'),linked_hash:tokenHash(token)};
  await apply(replacement);assert.equal((await profile()).tier,'ultra');
  await apply({...replacement,active:false,state:'SUBSCRIPTION_STATE_EXPIRED'});
  await apply();assert.equal((await profile()).tier,'basic');
});
test('a database lease rejects overlapping or expired provider observations',async()=>{
  await prepare();const lease=await rpc(owner,'claim');
  await assert.rejects(rpc(owner,'claim'),/updating/);
  await assert.rejects(rpc(owner,'apply',{...facts(),sync_token:other}),/changed while verifying/);
  await db.query("update korlix_play_billing_accounts set sync_until=now()-interval '1 second'");
  await assert.rejects(rpc(owner,'apply',{...facts(),sync_token:lease.sync_token}),/changed while verifying/);
});
test('other providers block duplicate Play purchases; Play blocks duplicate web checkout',async()=>{
  await db.query("insert into subscriptions values($1,'pro','active',$2)",[owner,future()]);
  assert.equal((await rpc(owner,'snapshot')).canPurchase,false);await assert.rejects(prepare(),/original billing provider/);
  await db.exec('reset role; delete from subscriptions; set role service_role');await prepare();await apply();
  await assert.rejects(db.query("select korlix_web_billing_command($1,'checkout_start',$2::jsonb)",[owner,JSON.stringify({tier:'pro',price_id:'price_pro',livemode:true,email:'fixture@example.invalid'})]),/app-store subscription/);
});
test('Apple callbacks cannot permanently promote a Play tier or remove an active Play plan',async()=>{
  await prepare();await apply({...facts(),product_id:'korlix_ultra',tier:'ultra'});
  const apple=async(status,signed)=>{
    const args=[owner,'com.korlixdeveloper.korlixai.pro.monthly','pro',status,'Production','apple-original','apple-transaction',
      new Date(Date.now()-86400000).toISOString(),future(),status==='revoked'?new Date().toISOString():null,
      owner,'PURCHASED',true,'signed.fixture',null,null,JSON.stringify({transaction:{signedDate:signed}})];
    return (await db.query(`select korlix_apply_apple_subscription_entitlement(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;
  };
  const signed=Date.now()-1000;
  assert.equal((await apple('active',signed)).tier,'ultra');
  assert.equal((await apple('revoked',signed+1)).tier,'ultra');
  await apply({...facts(),active:false,state:'SUBSCRIPTION_STATE_EXPIRED'});
  assert.equal((await profile()).tier,'basic');
});
test('HTTP flow verifies with Google, saves access, then acknowledges; failure remains retryable',async()=>{
  let data=google(), acknowledgeFails=false;const sequence=[];
  const provider={configured:true,ready:true,catalog:async()=>true,subscription:async()=>{sequence.push('verify');return data;},
    acknowledge:async()=>{sequence.push('ack');assert.equal((await profile()).tier,'pro');if(acknowledgeFails)throw new Error('offline');},
    notification:async()=>({packageName:PACKAGE,subscriptionNotification:{purchaseToken:token}})};
  const app=express();app.use(express.json());
  const billing=registerGooglePlay(app,{store:{command:rpc},provider,autoStart:false,
    requireUser:async req=>{if(req.headers.authorization!=='Bearer fixture')throw new Error();return {id:owner,email_confirmed_at:'2026-01-01'};}});
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  const root=`http://127.0.0.1:${server.address().port}/api/billing/google`;
  const request=async(path,body,authorized=true)=>{const response=await fetch(root+path,{method:'POST',headers:{'Content-Type':'application/json',...(authorized?{Authorization:'Bearer fixture'}:{})},body:JSON.stringify(body)});return {status:response.status,body:await response.json()};};
  try{
    assert.equal((await request('/prepare',{productId:'korlix_pro'},false)).status,401);
    const prepared=await request('/prepare',{productId:'korlix_pro'});assert.equal(prepared.body.accountId,accountId(owner));
    const payload={productId:'korlix_pro',source:'google_play',verificationData:token,tier:'enterprise'};
    data=google({subscriptionState:'SUBSCRIPTION_STATE_PENDING'});
    const pending=await request('/verify',payload);assert.equal(pending.body.active,false);assert.equal(pending.body.completePurchase,false);assert.deepEqual(sequence,['verify']);
    data=google();acknowledgeFails=true;
    assert.equal((await request('/verify',payload)).status,503);
    acknowledgeFails=false;
    const verified=await request('/verify',payload);assert.equal(verified.body.tier,'pro');assert.equal(verified.body.completePurchase,true);
    assert.deepEqual(sequence,['verify','verify','ack','verify','ack']);
    const notification=await request('/notifications',{});assert.equal(notification.status,200);
    assert.equal((await profile()).tier,'pro');
  }finally{billing.stop();await new Promise(r=>server.close(r));}
});
