import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {once} from 'node:events';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {ESHA_AI_ROLE_POLICY, ESHA_BUNDLE, ESHA_PRODUCT, EshaBillingError, appleFacts} from '../esha/billing/catalog.mjs';
import {createEshaBilling} from '../esha/billing/routes.mjs';
import {createEshaVoiceLedger} from '../esha/billing/voice_ledger.mjs';
import {createEshaVoice} from '../esha/billing/voice_routes.mjs';
import {voiceConfiguration} from '../esha/billing/voice.mjs';
import {eshaAppRouteAllowed} from '../esha/auth.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const id = '33333333-3333-4333-8333-333333333333';
const nextId = '44444444-4444-4444-8444-444444444444';
const user = {id: owner, email_confirmed_at: new Date().toISOString()};
const environment = {KORLIX_ESHA_AI_POLICY: ESHA_AI_ROLE_POLICY, KORLIX_ESHA_NATIVE_AI_ENABLED: 'true',
  KORLIX_ESHA_VOICE_ENABLED: 'true', KORLIX_ESHA_BILLING_ENABLED: 'true', KORLIX_ESHA_APPLE_PRODUCTS_READY: 'true',
  KORLIX_ESHA_MAX_INPUT_TOKENS: '8192', KORLIX_ESHA_MAX_OUTPUT_TOKENS: '4096',
  KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS: '4', KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS: '12',
  OPENAI_API_KEY: 'offline-test-not-a-key'};
const input = (changes = {}) => ({requestId: id, sdpOffer: 'v=0\r\na=sendrecv\r\n', audioSharingConsent: true, ...changes});
const answer = {answer: 'Consider the satin lipstick and choose a shade on the manufacturer page.', productIds: ['elf-o-face-dirty-talk']};
let db;
const runtimes = new Set();
async function sqlCall(name, actor, action, data) {
  try {
    return (await db.query(name === 'voice'
      ? 'select public.korlix_esha_voice_command($1,$2,$3) result'
      : action === 'begin_provider_attempt'
        ? 'select public.korlix_esha_begin_provider_attempt($1,$2) result'
        : 'select public.korlix_esha_billing_command($1,$2,$3) result',
    name !== 'voice' && action === 'begin_provider_attempt' ? [actor, JSON.stringify(data)] : [actor, action, JSON.stringify(data)])).rows[0].result;
  } catch (error) {
    const known = /ESHA(\d{3}):([a-z_]+):([^\n]+)/.exec(error.message || '');
    if (known) throw new EshaBillingError(known[3], Number(known[1]), known[2]);
    throw error;
  }
}
const billingStore = (actor, action, data = {}) => sqlCall('billing', actor, action, data);
const voiceStore = (actor, action, data = {}) => sqlCall('voice', actor, action, data);
async function waitFor(check) {
  const until = Date.now() + 3000;
  while (!(await check())) {if (Date.now() >= until) assert.fail('Expected asynchronous result did not arrive.'); await new Promise(resolve => setTimeout(resolve, 5));}
}
function harness(options = {}) {
  const calls = {create: [], close: [], commentary: [], generate: [], attach: 0};
  const observers = new Map();
  const transport = {available: () => true,
    async create(request) {calls.create.push(request); if (options.createFailure) throw new Error('fixture timeout');
      return {sessionId: `live_fixture_${calls.create.length}`, sdpAnswer: 'v=0\r\na=sendrecv\r\n'};},
    async attach(sessionId, observer) {calls.attach++; if (options.attachFailure?.()) throw new Error('fixture sideband failure');
      if (options.disconnectDuringAttach && calls.attach === 1) await observer.onDisconnect();
      observers.set(sessionId, observer); return {closeSession: eventId => calls.close.push(eventId),
        commentary: (...args) => calls.commentary.push(args), dispose() {}};},
  };
  let settleFailures = options.settleFailures || 0;
  const ledger = createEshaVoiceLedger({store: async (actor, action, data) => {
    if (action === 'settle' && settleFailures-- > 0) throw new EshaBillingError('Fixture storage outage.', 503, 'storage_unavailable');
    return voiceStore(actor, action, data);
  }});
  if (options.lostBegin) {
    const begin = ledger.begin;
    ledger.begin = async (...args) => {await begin(...args); throw new Error('lost committed begin reply');};
  }
  const billing = createEshaBilling({environment, store: billingStore, aiRole: 'deep_thinking', autoStart: false,
    provider: {ready: () => true}, countInputTokens: options.countInputTokens || (async () => 100),
    generate: async request => {calls.generate.push(request); return {output_text: JSON.stringify(answer)};},
    voiceReady: () => runtime.ready()});
  // The injectable fixture represents a separately proven provider bound. No
  // environment variable can turn the production configuration into this value.
  const runtime = createEshaVoice({environment, ledger, billing, transport, watchdogMs: options.watchdogMs || 5000,
    requireUser: options.requireUser || (async () => user),
    configuration: options.productionConfiguration ? undefined : () => ({...voiceConfiguration(environment),
      configured: true, voiceEnabled: true, hardDurationBoundVerified: true, maxSessionSeconds: 60})});
  runtimes.add(runtime);
  return {runtime, billing, ledger, calls,
    emit: (event, sessionId = 'live_fixture_1') => observers.get(sessionId).onEvent(event),
    disconnect: (sessionId = 'live_fixture_1') => observers.get(sessionId).onDisconnect(),
  };
}
const started = () => ({type: 'session.started', event_id: 'started_1', session: {id: 'live_fixture_1', model: 'gpt-live-1', expires_at: Math.floor(Date.now() / 1000) + 30}});
const closed = (seconds, eventId = 'closed_1') => ({type: 'session.closed', event_id: eventId, reason: 'close_requested',
  session: {id: 'live_fixture_1', model: 'gpt-live-1', expires_at: Math.floor(Date.now() / 1000) + 30}, usage: {seconds}});

test.before(async () => {
  db = new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key); create table public.user_profiles(id uuid primary key,tier text);');
  const files = (await readdir(new URL('../../supabase/migrations/', import.meta.url)))
    .filter(file => /_esha_(store_billing|provider_attempt_budget|live_voice_ledger|sol_deep_attempts)\.sql$/.test(file)).sort();
  assert.equal(files.length, 4);
  for (const file of files) await db.exec(await readFile(new URL('../../supabase/migrations/' + file, import.meta.url), 'utf8'));
  await db.query('insert into auth.users values($1),($2)', [owner, other]);
  await db.query("insert into user_profiles values($1,'basic'),($2,'ultra')", [owner, other]);
});
test.beforeEach(async () => {
  await db.exec('reset role; truncate korlix_esha_billing_accounts,korlix_esha_voided_periods cascade; set role service_role;');
  const now = Date.now();
  const facts = appleFacts({bundleId: ESHA_BUNDLE, productId: ESHA_PRODUCT.apple, appAccountToken: owner,
    transactionId: '1234567890', originalTransactionId: '1234567890', quantity: 1, inAppOwnershipType: 'PURCHASED',
    type: 'Auto-Renewable Subscription', environment: 'Production', purchaseDate: now - 10000,
    signedDate: now, expiresDate: now + 3 * 86400000, offerType: 1, offerDiscountType: 'FREE_TRIAL'}, owner, {}, now);
  await billingStore(owner, 'apply', {...facts, allowance: 2});
});
test.afterEach(async () => {for (const runtime of runtimes) await runtime.dispose(); runtimes.clear();});
test.after(async () => {await db?.close();});

test('production creation stays disabled before reservation even with all flags set', async () => {
  const h = harness({productionConfiguration: true});
  await assert.rejects(h.runtime.start(user, input()), {code: 'voice_not_configured'});
  assert.equal(h.calls.create.length, 0);
  assert.equal((await db.query('select count(*) n from korlix_esha_voice_sessions')).rows[0].n, 0);
  assert.equal(h.billing.catalog('apple').purchasesEnabled, false);
  assert.equal(h.billing.catalog('apple').consultationEnabled, true);
});
test('one durable authorization precedes create; identity is recoverable before session.started', async () => {
  const h = harness();
  const result = await h.runtime.start(user, input({model: 'client-model', instructions: 'client override'}));
  assert.equal(result.state, 'starting'); assert.equal(result.finalizationConfirmed, false);
  assert.equal(result.usage.voice.reservedSeconds, 60); assert.equal(result.usage.voice.remainingSeconds, 240);
  assert.equal(h.calls.create[0].session.model, 'gpt-live-1');
  assert(!h.calls.create[0].session.instructions.includes('client override'));
  assert.equal((await h.runtime.session(user, id)).sdpAnswer, undefined);
  await assert.rejects(h.runtime.start(user, input()), {code: 'voice_request_pending'});
  await assert.rejects(h.runtime.session({...user, id: other}, id), {code: 'voice_session_not_found'});
  assert.equal(h.calls.create.length, 1);
  await h.emit(started());
  assert.equal((await h.runtime.session(user, id)).state, 'active');
});
test('audio consent and SDP validation happen before reserving or contacting OpenAI', async () => {
  const h = harness();
  for (const invalid of [input({audioSharingConsent: false}), input({sdpOffer: 'not SDP'}), input({deepThinkingConsent: 'yes'})]) {
    await assert.rejects(h.runtime.start(user, invalid));
  }
  assert.equal(h.calls.create.length, 0);
  assert.equal((await db.query('select count(*) n from korlix_esha_voice_sessions')).rows[0].n, 0);
});
test('a timed-out paid create keeps its hold and prevents a second UUID from starting', async () => {
  const h = harness({createFailure: true});
  await assert.rejects(h.runtime.start(user, input()));
  const status = await h.runtime.session(user, id);
  assert.equal(status.state, 'uncertain'); assert.equal(status.usage.voice.reservedSeconds, 60);
  await assert.rejects(h.runtime.start(user, input({requestId: nextId})), {code: 'voice_session_in_progress'});
  assert.equal(h.calls.create.length, 1);
});
test('a lost database begin reply cannot trigger a paid request or release its committed hold', async () => {
  const h = harness({lostBegin: true});
  await assert.rejects(h.runtime.start(user, input()));
  assert.equal(h.calls.create.length, 0);
  const status = await h.runtime.stopSession(user, id, 'transport_error');
  assert.equal(status.finalizationConfirmed, false); assert.equal(status.usage.voice.reservedSeconds, 60);
  await assert.rejects(h.runtime.start(user, input({requestId: nextId})), {code: 'voice_session_in_progress'});
});
test('sideband failure preserves provider identity and recovery sends close without another create', async () => {
  let failAttach = true;
  const h = harness({attachFailure: () => failAttach});
  await assert.rejects(h.runtime.start(user, input()));
  assert.equal((await h.runtime.session(user, id)).sessionId, 'live_fixture_1');
  failAttach = false;
  const stopping = await h.runtime.stopSession(user, id, 'transport_error');
  assert.equal(stopping.finalizationConfirmed, false); assert(h.calls.close.length > 0);
  assert.equal(h.calls.create.length, 1);
  await h.emit(closed(5.8));
  const final = await h.runtime.session(user, id);
  assert.equal(final.finalizationConfirmed, true); assert.equal(final.usage.voice.usedSeconds, 5.8);
});
test('an attachment-time disconnect does not install a stale observer that blocks recovery', async () => {
  const h = harness({disconnectDuringAttach: true});
  await assert.rejects(h.runtime.start(user, input()), {code: 'voice_sideband_unavailable'});
  assert.equal(h.calls.create.length, 1); assert.equal(h.calls.attach, 2);
  assert(h.calls.close.length > 0);
  await h.emit(closed(5.8));
  assert.equal((await h.runtime.session(user, id)).finalizationConfirmed, true);
});
test('pause and stop remain pending until trusted final cumulative usage arrives exactly once', async () => {
  const h = harness(); await h.runtime.start(user, input()); await h.emit(started());
  const stopping = await h.runtime.stopSession(user, id, 'paused');
  assert.equal(stopping.state, 'closing'); assert.equal(stopping.finalizationConfirmed, false);
  assert.equal(stopping.usage.voice.reservedSeconds, 60);
  await h.emit(closed(5.8)); await h.emit(closed(5.8));
  const final = await h.runtime.session(user, id);
  assert.equal(final.usage.voice.usedSeconds, 5.8); assert.equal(final.usage.voice.reservedSeconds, 0);
  assert.equal(final.finalizationConfirmed, true);
});
test('provider errors during closure cannot cause an error-close feedback loop', async () => {
  const h = harness(); await h.runtime.start(user, input()); await h.emit(started());
  await h.runtime.stopSession(user, id, 'user_stop');
  for (let index = 0; index < 5; index++) await h.emit({type: 'error', event_id: `error_${index}`, error: {message: 'fixture rejection'}});
  assert.equal(h.calls.close.length, 1);
  assert.equal((await h.runtime.session(user, id)).finalizationConfirmed, false);
  await h.emit(closed(8.25));
});
test('inconsistent final usage retains the hold until consistent terminal evidence arrives', async () => {
  const h = harness(); await h.runtime.start(user, input()); await h.emit(started());
  await h.emit({type: 'session.usage.updated', event_id: 'usage_1', usage: {seconds: 10.5}});
  await h.emit(closed(5.8, 'bad_final'));
  let status = await h.runtime.session(user, id);
  assert.equal(status.finalizationConfirmed, false); assert.equal(status.usage.voice.reservedSeconds, 60);
  await h.emit(closed(12.75, 'good_final'));
  status = await h.runtime.session(user, id);
  assert.equal(status.usage.voice.usedSeconds, 12.75); assert.equal(status.finalizationConfirmed, true);
});
test('an expiry beyond the asserted provider bound closes the call and disables further creation', async () => {
  const h = harness(); await h.runtime.start(user, input());
  const event = started(); event.session.expires_at += 3600;
  await h.emit(event);
  assert.equal(h.runtime.ready(), false); assert(h.calls.close.length > 0);
  assert.equal((await h.runtime.session(user, id)).finalizationConfirmed, false);
});
for (const consent of [false, true]) test(`no spoken question cannot spend a consultation; consent=${consent}`, async () => {
  const h = harness(); await h.runtime.start(user, input({deepThinkingConsent: consent})); await h.emit(started());
  await h.emit({type: 'session.delegation.created', event_id: 'delegation_1', delegation: {id: 'del_1', target: 'client'}});
  await waitFor(() => h.calls.commentary.length === 1);
  assert.equal(h.calls.generate.length, 0);
  await h.emit(closed(0));
});

test('failed initial observation still recovers and retries a transient final-settlement write', async () => {
  let failAttach = true;
  const h = harness({attachFailure: () => failAttach, settleFailures: 1, watchdogMs: 25});
  await assert.rejects(h.runtime.start(user, input()));
  failAttach = false;
  await waitFor(() => h.calls.close.length > 0);
  await h.emit(closed(5.8));
  await waitFor(async () => (await h.runtime.session(user, id)).finalizationConfirmed);
  assert.equal((await h.runtime.session(user, id)).usage.voice.usedSeconds, 5.8);
  assert.equal(h.calls.create.length, 1);
});

test('status after a process restart recovers closing sessions without a new paid create', async () => {
  const before = harness(); await before.runtime.start(user, input()); await before.emit(started());
  await before.runtime.dispose();
  const after = harness({settleFailures: 1, watchdogMs: 25});
  const resumed = await after.runtime.session(user, id);
  assert.equal(resumed.finalizationConfirmed, false); assert(after.calls.close.length > 0);
  await after.emit(closed(8.25));
  await waitFor(async () => (await after.runtime.session(user, id)).finalizationConfirmed);
  assert.equal(after.calls.create.length, 0);
  assert.equal((await after.runtime.session(user, id)).usage.voice.usedSeconds, 8.25);
});
test('a consented delegation uses Sol/high once and records the successful consultation', async () => {
  const h = harness(); await h.runtime.start(user, input({deepThinkingConsent: true})); await h.emit(started());
  await h.emit({type: 'session.input_transcript.delta', event_id: 'transcript_1', delta: 'Which satin lipstick can I consider?'});
  const event = {type: 'session.delegation.created', event_id: 'delegation_1', delegation: {id: 'del_1', target: 'client'}};
  await h.emit(event); await h.emit({...event, event_id: 'replayed_delegation'});
  await waitFor(() => h.calls.commentary.length === 1);
  assert.equal(h.calls.generate.length, 1);
  assert.equal(h.calls.generate[0].model, 'gpt-6.1-sol'); assert.equal(h.calls.generate[0].reasoning.effort, 'high');
  const status = await h.runtime.session(user, id);
  assert.equal(status.usage.deep.used, 1); assert.equal(status.usage.deep.remaining, 1);
});
test('closing during input counting prevents a voice-linked Sol spend at the final debit', async () => {
  let releaseCount, counting = false;
  const gate = new Promise(resolve => {releaseCount = resolve;});
  const h = harness({countInputTokens: async () => {counting = true; await gate; return 100;}});
  await h.runtime.start(user, input({deepThinkingConsent: true})); await h.emit(started());
  await h.emit({type: 'session.input_transcript.delta', event_id: 'transcript_1', delta: 'Help compare a lipstick.'});
  await h.emit({type: 'session.delegation.created', event_id: 'delegation_1', delegation: {id: 'del_1', target: 'client'}});
  await waitFor(() => counting);
  await h.runtime.stopSession(user, id, 'user_stop');
  releaseCount();
  await waitFor(async () => (await billingStore(owner, 'snapshot')).allowance.reserved === 0);
  assert.equal(h.calls.generate.length, 0);
  assert.equal((await billingStore(owner, 'snapshot')).allowance.used, 0);
});
test('Sol is selected only by the server role; client role fields cannot activate it', async () => {
  let generated = 0;
  const billing = createEshaBilling({environment, store: billingStore, autoStart: false,
    provider: {ready: () => true}, generate: async () => {generated++;}, countInputTokens: async () => 10});
  await assert.rejects(billing.consult(user, {requestId: id, question: 'Help me.', role: 'deep_thinking', model: 'gpt-6.1-sol'}), {code: 'native_ai_not_configured'});
  assert.equal(generated, 0);
  assert.equal(harness().billing.catalog('apple').purchasesEnabled, true, 'The test-only proven bound permits the combined readiness gate.');
});
test('companion authentication exposes only exact voice paths and verified account routes', async t => {
  assert.equal(eshaAppRouteAllowed({method: 'POST', originalUrl: '/api/esha/voice/sessions'}), true);
  assert.equal(eshaAppRouteAllowed({method: 'GET', originalUrl: `/api/esha/voice/sessions/${id}`}), true);
  assert.equal(eshaAppRouteAllowed({method: 'POST', originalUrl: `/api/esha/voice/sessions/${id}/stop`}), true);
  for (const path of ['/api/esha/voice/sessions/all', `/api/esha/voice/sessions/${id}/settle`, '/api/admin', '/api/esha/voice/sessions/../admin']) {
    assert.equal(eshaAppRouteAllowed({method: 'POST', originalUrl: path}), false);
    assert.equal(eshaAppRouteAllowed({method: 'GET', originalUrl: path}), false);
  }
  const h = harness({requireUser: async () => ({id: owner})});
  const app = express(); app.use(express.json()); h.runtime.register(app);
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/api/esha/voice/status?provider=apple`);
  assert.equal(response.status, 403); assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal((await response.json()).code, 'email_confirmation_required');
});
