import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createBrainBilling} from '../brain_voice/billing/routes.mjs';
import {createBrainVoice} from '../brain_voice/core.mjs';
import {brainProfile} from '../brain_voice/models.mjs';
import {authenticatedDeveloperUser, hasUnlimitedAccess} from '../security/developer_access.mjs';
import {BillingError} from '../web_billing/core.mjs';

const owner = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
const paidSession = '20000000-0000-4000-8000-000000000001';
const developerSession = '20000000-0000-4000-8000-000000000002';
const source = readFileSync(new URL('../server.js', import.meta.url), 'utf8');
function section(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert(from >= 0 && to > from, `Missing production section: ${start}`);
  return source.slice(from, to);
}
// Run the production middleware and entitlement helpers, so changing their
// ordering or trusting client input is exercised rather than reimplemented.
const runtime = [
  section('// KORLIX_LIVE_CONVO_BUILD131_ENTITLEMENT_BEGIN', 'function korlixLiveConvoBuild131UserFingerprint('),
  section('function korlixLiveConvoBuild131LimitsForEntitlement(', 'async function korlixLiveConvoBuild131UnlimitedUsage('),
  section('function korlixLiveConvoErrorStatusV1(', 'function korlixLiveConvoAgentErrorV1('),
  section('async function korlixRecordVoiceUsage(', 'app.post("/api/live-convo/usage"'),
  section('app.use("/api/live-convo/session", async (req, res, next) => {', '// KORLIX_LIVE_CONVO_BUILD129_LIMITS_END'),
  'return {recordUsage: korlixRecordVoiceUsage, entitlement: korlixLiveConvoBuild131EntitlementForUser};',
].join('\n');

function fixture(t, {account = {id: owner, is_disabled: false}, rawUser = {}, headers = {},
  body = {}, environmentOnly = false, noMinutes = false} = {}) {
  const events = [];
  const user = authenticatedDeveloperUser({id: owner, email_confirmed_at: '2026-01-01', ...rawUser}, account);
  const billing = createBrainBilling({
    environment: {KORLIX_BRAIN_BILLING_ENABLED: 'true', OPENAI_API_KEY: 'test-only'},
    autoStart: false,
    provider: {},
    store: async (actor, action, data = {}) => {
      assert.equal(actor, owner);
      events.push(`billing.${action}`);
      if (action === 'reserve') {
        if (noMinutes) throw new BillingError('Your Live minutes have run out. Open Plan & AI GAS to add more.', 402);
        return {allowed: true, sessionId: paidSession, maxSessionSeconds: 3600};
      }
      if (action === 'session') {
        if (data.sessionId !== paidSession) throw new BillingError('Voice session not found.', 404);
        return {id: paidSession, user_id: owner, call_id: 'rtc_paid', deadline: new Date(Date.now() + 60000).toISOString()};
      }
      assert.equal(data.sessionId, paidSession);
      if (action === 'usage') return {allowed: true, chargedSeconds: 15, limitReached: false};
      if (action === 'end') return {allowed: false, chargedSeconds: 15, limitReached: true};
      assert(['start', 'stopped'].includes(action), `Unexpected billing action: ${action}`);
      return {ok: true};
    },
    fetcher: async (url, options) => {
      assert.equal(url, 'https://api.openai.com/v1/realtime/calls/rtc_paid/hangup');
      assert.equal(options.method, 'POST');
      events.push('provider.hangup');
      return {ok: true, status: 200};
    },
  });
  t.after(() => billing.stop());
  let middleware;
  const dependencies = {
    app: {use: (path, handler) => { assert.equal(path, '/api/live-convo/session'); middleware = handler; }},
    process: {env: {KORLIX_LIVE_CONVO_UNLIMITED_USER_IDS: environmentOnly ? owner : ''}},
    hasUnlimitedAccess,
    brainProfile,
    brainBilling: billing,
    requireUser: async () => user,
    getOrCreateProfile: async () => ({id: owner, tier: 'enterprise'}),
    korlixLiveConvoBuild129LimitsForTier: tier => ({tier, maxSessionSeconds: 1800, maxResponses: 200}),
    korlixLiveConvoBuild131ReserveUnlimited: async ({user: authenticated, limits}) => {
      assert.equal(authenticated.id, owner);
      events.push('unlimited.reserve');
      return {sessionId: developerSession, limits,
        reservation: {allowed: true, sessionId: developerSession, ...limits}};
    },
    korlixLiveConvoBuild131ReportUnlimitedUsage: async ({user: authenticated, body: report}) => {
      assert.equal(authenticated.id, owner);
      assert.equal(report.sessionId, developerSession);
      events.push('unlimited.usage');
      return {allowed: !report.ended, limitReached: report.ended === true};
    },
    korlixLiveConvoBuild131CancelUnlimited: async ({sessionId, userId}) => {
      assert.equal(sessionId, developerSession);
      assert.equal(userId, owner);
      events.push('unlimited.cancel');
    },
    korlixLiveConvoBuild129Reserve: async () => assert.fail('Brain Live must not use the ordinary allowance'),
    korlixLiveConvoBuild129Cancel: async () => assert.fail('Wrong session cleanup'),
    korlixLiveConvoBuild129ExposeHeaders: (res, reservation) => { res.reservation = reservation; },
    autoEmailVoiceBridge: {limits: (_req, reservation) => reservation},
    korlixLiveConvoBuild129LogError: () => {},
    getKorlixUserFacingError: error => error.message,
    supabaseAdmin: {rpc: async () => assert.fail('Unexpected ordinary usage RPC')},
  };
  const helpers = Function(...Object.keys(dependencies), runtime)(...Object.values(dependencies));
  const listeners = new Map();
  const req = {method: 'POST', headers: {'x-korlix-brain-voice': 'rici-live-v1', ...headers}, body};
  const res = {statusCode: 200, writableFinished: true,
    once(event, callback) { listeners.set(event, callback); },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; return this; },
  };
  let nextCalls = 0;
  return {events, user, req, res, billing, listeners,
    get nextCalls() { return nextCalls; },
    run: () => middleware(req, res, () => { nextCalls++; }),
    usage: (sessionId, ended = false) => helpers.recordUsage({user, body: {sessionId, ended},
      limits: req.korlixLiveConvoBuild129?.limits, entitlement: helpers.entitlement(user)}),
  };
}

test('verified existing developer access reserves Live without buying or granting minutes', async t => {
  const f = fixture(t, {account: {id: owner, is_disabled: false, developer_access: [{enabled: true}]}, noMinutes: true});
  await f.run();
  assert.equal(f.nextCalls, 1);
  assert.deepEqual(f.events, ['unlimited.reserve']);
  assert.equal(f.req.korlixBrainMeter, undefined);
  assert.equal(f.req.korlixLiveConvoBuild129.sessionId, developerSession);
  assert.equal(f.req.korlixLiveConvoBuild129.unlimited, true);
  // Retain the existing per-session bounds and ordinary usage logging.
  assert.equal(f.res.reservation.maxSessionSeconds, 1800);
  assert.equal(f.res.reservation.maxResponses, 200);
  await f.billing.started(f.req, {headers: new Headers()});
  assert.deepEqual(f.events, ['unlimited.reserve']);
  assert.deepEqual(await f.usage(developerSession), {allowed: true, limitReached: false});
  assert.deepEqual(await f.usage(developerSession, true), {allowed: false, limitReached: true});
  assert.deepEqual(f.events, ['unlimited.reserve', 'billing.session', 'unlimited.usage', 'billing.session', 'unlimited.usage']);
  f.res.statusCode = 502;
  f.listeners.get('finish')();
  assert.equal(f.events.at(-1), 'unlimited.cancel');
});

test('ordinary Brain Live still reserves, starts and closes through the paid ledger', async t => {
  const f = fixture(t);
  await f.run();
  assert.equal(f.nextCalls, 1);
  assert.deepEqual(f.events, ['billing.reserve']);
  assert.deepEqual(f.req.korlixBrainMeter, {userId: owner, sessionId: paidSession});
  await f.billing.started(f.req, {headers: new Headers({location: '/v1/realtime/calls/rtc_paid'})});
  assert.equal(f.events.at(-1), 'billing.start');
  assert.equal((await f.usage(paidSession)).chargedSeconds, 15);
  f.res.statusCode = 502;
  f.listeners.get('finish')();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.events, ['billing.reserve', 'billing.start', 'billing.session', 'billing.usage',
    'billing.session', 'provider.hangup', 'billing.stopped', 'billing.end']);
});

const spoofing = [
  ['editable user metadata', {rawUser: {user_metadata: {developer_unlimited: true, unlimited: true}}}],
  ['app metadata without the database grant', {rawUser: {app_metadata: {developer_unlimited: true}}}],
  ['an unverified top-level marker', {rawUser: {developer_unlimited: true}}],
  ['request headers', {headers: {'x-korlix-developer-unlimited': 'true', 'x-korlix-live-convo-entitlement': 'developer_unlimited'}}],
  ['request body', {body: {developer_unlimited: true, unlimited: true, user: {id: owner, developer_unlimited: true}}}],
  ['a disabled grant', {account: {id: owner, developer_access: {enabled: false}}}],
  ['another account grant', {account: {id: other, developer_access: {enabled: true}}}],
  ['a grant on a disabled account', {account: {id: owner, is_disabled: true, developer_access: {enabled: true}}}],
];
for (const [label, options] of spoofing) {
  test(`${label} cannot bypass Brain Live billing`, async t => {
    const f = fixture(t, options);
    await f.run();
    assert.equal(f.user.developer_unlimited, false);
    assert.equal(f.nextCalls, 1);
    assert.deepEqual(f.events, ['billing.reserve']);
    assert.equal(f.req.korlixBrainMeter.sessionId, paidSession);
  });
}

test('legacy environment-only unlimited access remains metered for Brain Live', async t => {
  const f = fixture(t, {environmentOnly: true});
  await f.run();
  assert.equal(f.user.developer_unlimited, false);
  assert.deepEqual(f.events, ['billing.reserve']);
  assert.equal(f.req.korlixBrainMeter.sessionId, paidSession);
});

test('ordinary zero-minute accounts still receive the actionable 402', async t => {
  const f = fixture(t, {noMinutes: true});
  await f.run();
  assert.equal(f.nextCalls, 0);
  assert.equal(f.res.statusCode, 402);
  assert.match(f.res.body.error, /Open Plan & AI GAS/);
  assert.equal(f.req.korlixBrainMeter, undefined);
  assert.deepEqual(f.events, ['billing.reserve']);
});

test('a pre-existing paid session remains billed after developer access is enabled', async t => {
  const f = fixture(t, {account: {id: owner, developer_access: {enabled: true}}});
  const result = await f.usage(paidSession);
  assert.equal(result.chargedSeconds, 15);
  assert.deepEqual(f.events, ['billing.session', 'billing.usage']);
});

function coreFixture(t, {protocol = 'rici-live-v1', paid = false} = {}) {
  const f = fixture(t);
  const observations = {lookups: 0, ordinaryReports: 0, unlimitedReports: 0, saves: 0, providerCalls: 0};
  let account = {id: owner, is_disabled: false, developer_access: [{enabled: true}]};
  let lookupError = null;
  const database = {
    from(table) {
      assert.equal(table, 'user_profiles');
      return {
        select(columns) {
          assert.equal(columns, 'id,is_disabled,developer_access:korlix_developer_access(enabled)');
          return this;
        },
        eq(column, value) { assert.equal(column, 'id'); assert.equal(value, owner); return this; },
        async maybeSingle() { observations.lookups++; return {data: account, error: lookupError}; },
      };
    },
    async rpc(name) {
      assert.equal(name, 'korlix_live_convo_report_usage');
      observations.ordinaryReports++;
      return {data: {allowed: true}};
    },
  };
  const dependencies = {
    process: {env: {}},
    console: {log() {}},
    hasUnlimitedAccess,
    authenticatedDeveloperUser,
    supabaseAdmin: database,
    brainBilling: f.billing,
    createBrainVoice: options => createBrainVoice({...options, fetchImpl: async (_url, request) => {
      observations.providerCalls++;
      const payload = JSON.parse(request.body);
      return Response.json({status: 'completed', model: payload.model,
        usage: {total_tokens: 5}, output: [{type: 'message', content: [{type: 'output_text', text: 'A checked response.'}]}]});
    }}),
    korlixLiveConvoBuild129RpcValue: value => value,
    korlixLiveConvoBuild131ReportUnlimitedUsage: async ({user}) => {
      assert.equal(user.developer_unlimited, true);
      observations.unlimitedReports++;
      return {allowed: true};
    },
    korlixLiveConvoEnvStringV1: () => 'test-only',
    korlixLiveConvoBuildAgentRuntimeV1: async () => ({context: '{}'}),
    korlixLiveConvoAgentPersistenceClientV1: () => ({}),
    korlixAgentSaveMemoryV1: async ({userId, body}) => {
      assert.equal(userId, owner);
      observations.saves++;
      return {id: `saved-${observations.saves}`, ...body};
    },
  };
  const code = [
    section('function makeHttpError(', 'async function registerDeviceSession('),
    section('// KORLIX_LIVE_CONVO_BUILD131_ENTITLEMENT_BEGIN', 'function korlixLiveConvoBuild131UserFingerprint('),
    section('async function korlixRecordVoiceUsage(', 'app.post("/api/live-convo/usage"'),
    section('async function korlixRecordBrainVoiceUsage(', '// Brain+Voice Live answers directly'),
    section('const brainVoice = createBrainVoice({', '// Projection research reuses'),
    'return brainVoice;',
  ].join('\n');
  const voice = Function(...Object.keys(dependencies), code)(...Object.values(dependencies));
  const sessionId = paid ? paidSession : developerSession;
  const limits = {tier: paid ? 'brain' : 'developer_unlimited', maxSessionSeconds: 1800,
    maxResponses: 200, monthlySeconds: 2147483647, monthlyTokens: Number.MAX_SAFE_INTEGER};
  voice.register({userId: owner, sessionId, protocol, limits});
  return {observations, limits,
    setAccount(value) { account = value; },
    failLookup() { lookupError = {message: 'private database failure'}; },
    turn(turnId = 'first') {
      return voice.turn({userId: owner, sessionId, turnId,
        transcript: protocol === 'rici-live-v1' ? 'Rici remember this: Use metric units.' : 'Explain why the sky is blue.'});
    },
  };
}

for (const protocol of ['rici-live-v1', 'sol-6.1-max-v1']) {
  test(`${protocol} core callback uses the current verified grant for usage`, async t => {
    const f = coreFixture(t, {protocol});
    await f.turn();
    assert.equal(f.observations.lookups, 2);
    assert.equal(f.observations.unlimitedReports, 2);
    assert.equal(f.observations.ordinaryReports, 0);
    assert.equal(f.observations.saves, protocol === 'rici-live-v1' ? 1 : 0);
    assert.equal(f.observations.providerCalls, protocol === 'rici-live-v1' ? 0 : 1);
  });

  test(`${protocol} core callback rejects a revoked grant despite cached unlimited limits`, async t => {
    const f = coreFixture(t, {protocol});
    await f.turn();
    const before = {...f.observations};
    f.setAccount({id: owner, is_disabled: false, developer_access: [{enabled: false}]});
    await assert.rejects(f.turn('after-revocation'), error => {
      assert.equal(error.statusCode, 403);
      assert.match(error.message, /account access changed/);
      return true;
    });
    assert.equal(f.limits.tier, 'developer_unlimited');
    assert.deepEqual(f.observations, {...before, lookups: before.lookups + 1});
  });
}

for (const [name, account] of [
  ['disabled account', {id: owner, is_disabled: true, developer_access: [{enabled: true}]}],
  ['missing account', null],
  ['metadata-only grant', {id: owner, is_disabled: false, user_metadata: {developer_unlimited: true},
    app_metadata: {developer_unlimited: true}, developer_unlimited: true}],
]) {
  test(`core usage fails closed for ${name} before a memory save`, async t => {
    const f = coreFixture(t);
    f.setAccount(account);
    await assert.rejects(f.turn(), {statusCode: 403});
    assert.deepEqual(f.observations, {lookups: 1, ordinaryReports: 0, unlimitedReports: 0, saves: 0, providerCalls: 0});
  });
}

test('core usage fails closed on a grant lookup failure', async t => {
  const f = coreFixture(t);
  f.failLookup();
  await assert.rejects(f.turn(), error => {
    assert.equal(error.statusCode, 503);
    assert.doesNotMatch(error.message, /private database/);
    return true;
  });
  assert.deepEqual(f.observations, {lookups: 1, ordinaryReports: 0, unlimitedReports: 0, saves: 0, providerCalls: 0});
});

test('ordinary paid core turns remain on their existing Brain minute ledger', async t => {
  const f = coreFixture(t, {paid: true});
  f.setAccount({id: owner, is_disabled: false});
  assert.equal((await f.turn()).saved, true);
  assert.deepEqual(f.observations, {lookups: 2, ordinaryReports: 0, unlimitedReports: 0, saves: 1, providerCalls: 0});
});
