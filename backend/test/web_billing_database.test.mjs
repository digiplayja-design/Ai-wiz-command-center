import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

let db;
const owner = '11111111-1111-4111-8111-111111111111', other = '22222222-2222-4222-8222-222222222222';
const future = () => new Date(Date.now() + 86400000 * 20).toISOString();
const rpc = async (user, action, p = {}) => (await db.query('select public.korlix_web_billing_command($1,$2,$3::jsonb) result', [user, action, JSON.stringify(p)])).rows[0].result;
const profile = async (id = owner) => (await db.query('select public.korlix_web_billing_profile($1) result', [id])).rows[0].result;
const start = (user = owner, extra = {}) => rpc(user, 'checkout_start', {tier: 'pro', price_id: 'price_pro', livemode: true, email: 'fixture@example.invalid', ...extra});
async function apply(m, extra = {}) {
  const leased = await rpc(m.user_id, 'claim');
  await rpc(m.user_id, 'apply', {generation: m.generation, sync_token: leased.sync_token,
    livemode: m.livemode, subscription_id: 'sub_' + m.user_id.slice(0,8), customer_id: 'cus_' + m.user_id.slice(0,8),
    state: 'active', tier: 'pro', amount: 3499, paid: true, paid_until: future(), invoice_id: 'in_paid', cancel_at_period_end: false, ...extra});
  return (await rpc(m.user_id, 'snapshot')).membership;
}
test.before(async () => {
  db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create table public.user_profiles(id uuid primary key references auth.users(id),tier text not null default 'basic',is_disabled boolean default false);
    create table public.subscriptions(user_id uuid,tier text,status text,current_period_end timestamptz);
    grant usage on schema public,auth to service_role;
    grant select,insert,update on public.user_profiles,public.subscriptions to service_role;`);
  await db.exec(await readFile(new URL('../../supabase/migrations/202607130001_apple_subscriptions_build130.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../../supabase/migrations/20261004203621_web_plan_subscriptions.sql', import.meta.url), 'utf8'));
  for (const id of [owner, other]) {
    await db.query('insert into auth.users values($1)', [id]);
    await db.query('insert into public.user_profiles(id) values($1)', [id]);
  }
});
test.beforeEach(async () => {
  await db.exec("reset role; delete from korlix_web_billing_events; delete from korlix_web_billing_accounts; delete from apple_subscription_entitlements; delete from subscriptions; update user_profiles set tier='basic',is_disabled=false; set role service_role;");
});
test.after(async () => db?.close());

test('browser roles cannot read or mutate billing tables or execute internal functions', async () => {
  await db.exec('reset role; set role authenticated');
  await assert.rejects(db.query('select * from korlix_web_billing_accounts'), /permission denied/);
  await assert.rejects(start(), /permission denied/);
  await assert.rejects(profile(), /permission denied/);
  await db.exec('reset role; set role anon');
  await assert.rejects(db.query('select * from korlix_web_billing_events'), /permission denied/);
  await assert.rejects(rpc(null, 'lookup', {customer_id: 'cus_foreign'}), /permission denied/);
});
test('checkout retries reuse the immutable attempt and cannot silently change plan', async () => {
  const first = await start();
  assert.equal((await start()).generation, first.generation);
  await assert.rejects(start(owner, {tier: 'ultra', price_id: 'price_ultra'}), /Finish or cancel/);
  assert.notEqual((await start(other)).generation, first.generation);
});
test('disabled accounts and existing custom access cannot start another paid subscription', async () => {
  await db.query("update user_profiles set is_disabled=true where id=$1", [owner]);
  await assert.rejects(start(), /disabled/);
  await db.query("update user_profiles set is_disabled=false,tier='enterprise' where id=$1", [owner]);
  await assert.rejects(start(), /already has paid or custom access/);
});
test('a native store subscription blocks duplicate web purchases', async () => {
  await db.query("insert into subscriptions values($1,'pro','active',$2)", [owner, future()]);
  await assert.rejects(start(), /app-store subscription/);
});
test('only a bound paid live subscription grants a plan', async () => {
  const m = await start();
  assert.equal((await profile()).tier, 'basic');
  const active = await apply(m);
  assert.equal((await profile()).tier, 'pro');
  assert.equal(active.state, 'active');
  await assert.rejects(start(), /subscription already exists/);
});
test('sandbox payment observations never grant production account access', async () => {
  const m = await start(owner, {livemode: false});
  await apply(m);
  assert.equal((await profile()).tier, 'basic');
  await assert.rejects(start(owner, {livemode: true}), /subscription already exists|environment changed/);
});
test('a lease rejects concurrent refresh and cross-account or wrong-mode observations', async () => {
  const m = await start(), lease = await rpc(owner, 'claim');
  await assert.rejects(rpc(owner, 'claim'), /updating/);
  await assert.rejects(rpc(owner, 'apply', {generation: m.generation, sync_token: other}), /changed while refreshing/);
  await assert.rejects(rpc(owner, 'apply', {generation: m.generation, sync_token: lease.sync_token,livemode:false,tier:'pro',amount:3499}), /does not match/);
  assert.equal((await profile()).tier, 'basic');
});
test('paid plan updates take effect, unpaid renewal never extends the previous paid period', async () => {
  let m = await apply(await start());
  const previous = m.paid_until;
  m = await apply(m, {state: 'past_due', paid: false, paid_until: new Date(Date.now()+86400000*60).toISOString()});
  assert.equal(m.paid_until, previous);
  assert.equal((await profile()).tier, 'pro');
  m = await apply(m, {tier: 'ultra', amount: 12499, invoice_id: 'in_proration'});
  assert.equal((await profile()).tier, 'ultra');
});
test('expiry removes only the web grant and keeps independently assigned enterprise access', async () => {
  await apply(await start());
  await db.query("update korlix_web_billing_accounts set paid_until=now()-interval '1 second' where user_id=$1", [owner]);
  assert.equal((await profile()).tier, 'basic');
  await db.query("update user_profiles set tier='enterprise' where id=$1", [owner]);
  assert.equal((await profile()).tier, 'enterprise');
  await db.query("update user_profiles set tier='basic' where id=$1", [owner]);
  assert.equal((await profile()).tier, 'basic');
});
test('scheduled cancellation keeps paid access; final cancellation removes the web grant', async () => {
  let m = await apply(await start(), {cancel_at_period_end: true});
  assert.equal((await profile()).tier, 'pro');
  assert.equal(m.cancel_at_period_end, true);
  m = await apply(m, {state: 'canceled', paid: false});
  assert.equal(m.paid_until, null);
  assert.equal((await profile()).tier, 'basic');
  assert.notEqual((await start()).generation, m.generation);
});
test('refund and dispute holds persist across later active provider responses', async () => {
  let m = await apply(await start());
  await rpc(owner, 'hold', {subscription_id: m.subscription_id, reason: 'charge.refunded'});
  assert.equal((await profile()).tier, 'basic');
  m = await apply(m);
  assert.equal(m.held, true);
  assert.equal((await profile()).tier, 'basic');
  await assert.rejects(start(), /billing review/);
});
test('old checkout receipts and foreign customers cannot overwrite the current membership', async () => {
  let m = await apply(await start());
  await assert.rejects(rpc(owner, 'checkout_saved', {generation: other, checkout_id: 'cs_foreign'}), /Checkout changed/);
  await assert.rejects(apply(m, {customer_id: 'cus_other'}), /does not match/);
});
test('Apple reconciliation preserves the independently paid web tier atomically', async () => {
  const m = await start();
  await apply(m, {tier: 'ultra', amount: 12499});
  const args=[owner,'com.korlixdeveloper.korlixai.pro.monthly','pro','expired','Production','apple_original','apple_transaction',null,
    new Date(Date.now()-86400000).toISOString(),null,owner,'PURCHASED',false,null,null,'EXPIRED','{}'];
  const placeholders=args.map((_,i)=>'$'+(i+1)).join(',');
  const result=(await db.query(`select korlix_apply_apple_subscription_entitlement(${placeholders}) result`,args)).rows[0].result;
  assert.equal(result.tier, 'ultra');
  assert.equal((await profile()).tier, 'ultra');
  assert.equal((await rpc(owner,'snapshot')).membership.base_tier,'basic');
});
test('recorded Stripe event receipts are idempotent', async () => {
  assert.equal((await rpc(null, 'seen', {event_id: 'evt_one'})).seen, false);
  for (let i=0;i<2;i++) await rpc(null,'record_event',{event_id:'evt_one',event_type:'invoice.paid',livemode:true});
  assert.equal((await rpc(null, 'seen', {event_id: 'evt_one'})).seen, true);
  assert.equal((await db.query('select count(*)::int n from korlix_web_billing_events')).rows[0].n,1);
});
