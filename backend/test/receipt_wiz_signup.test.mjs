import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createKorlixSignupHandler, KORLIX_SIGNUP_POLICY_VERSION} from '../korlix_signup_eligibility.mjs';
import {createReceiptSignupThrottle} from '../security/receipt_signup_throttle.mjs';

async function signup(provider, clientApp = 'receipt_wiz') {
  let profiles = 0, sessions = 0;
  const handler = createKorlixSignupHandler({
    supabaseAuth: {auth: {signUp: async () => provider}},
    getRequestDeviceInfo: () => ({}),
    getOrCreateProfile: async () => { profiles++; },
    registerDeviceSession: async () => { sessions++; },
    getUserFacingError: error => error.message,
  });
  const res = {statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; }};
  await handler({body: {
    client_app: clientApp, email: 'same@example.test', password: 'fixture-password',
    signup_eligibility: {age_band: '18_plus', terms_accepted: true,
      privacy_acknowledged: true, parent_permission: false, policy_version: KORLIX_SIGNUP_POLICY_VERSION},
  }}, res);
  return {...res, profiles, sessions};
}

test('existing account error directs Receipt Wiz to shared sign-in without changing access', async () => {
  const r = await signup({error: {status: 422, code: 'user_already_exists', message: 'User already registered'}});
  assert.equal(r.statusCode, 409);
  assert.equal(r.body.code, 'KORLIX_ACCOUNT_EXISTS');
  assert.match(r.body.error, /same email address and password/);
  assert.equal(r.profiles + r.sessions, 0);
});

test('masked duplicate signup is not reported as a new account', async () => {
  const r = await signup({data: {user: {id: 'obfuscated-user', identities: []}, session: null}});
  assert.equal(r.statusCode, 409);
  assert.equal(r.body.user, undefined);
  assert.equal(r.body.session, undefined);
  assert.equal(r.profiles + r.sessions, 0);
});

test('new email and pending confirmation keep the normal signup contract', async () => {
  const r = await signup({data: {user: {id: 'new-user', identities: [{provider: 'email'}]}, session: null}});
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.user.id, 'new-user');
  assert.equal(r.body.session, null);
});

test('main app and unknown clients retain their existing response', async () => {
  for (const client of ['korlix_ai', 'unknown']) {
    const r = await signup({data: {user: {id: 'masked', identities: []}, session: null}}, client);
    assert.equal(r.statusCode, 200);
  }
});

test('outages, weak passwords, and rate limits are not mistaken for existing accounts', async () => {
  for (const error of [{status: 429, message: 'Too many requests'}, {status: 503, message: 'Provider unavailable'}, {status: 422, code: 'weak_password', message: 'Weak password'}]) {
    const r = await signup({error});
    assert.equal(r.statusCode, error.status);
    assert.equal(r.body.code, undefined);
    assert.equal(r.profiles + r.sessions, 0);
  }
});

test('duplicate signup attempts are bounded by normalized mailbox and expire', () => {
  let now = 0;
  const consume = createReceiptSignupThrottle({now: () => now});
  for (let i = 0; i < 5; i++) consume(i % 2 ? ' SAME@example.test ' : 'same@example.test');
  assert.throws(() => consume('same@example.test'), {statusCode: 429});
  consume('different@example.test');
  now = 15 * 60 * 1000;
  assert.doesNotThrow(() => consume('same@example.test'));
});

test('anonymous signup throttle has bounded memory and fails closed when full', () => {
  const consume = createReceiptSignupThrottle({maxEntries: 1});
  consume('first@example.test');
  assert.throws(() => consume('second@example.test'), {statusCode: 429});
});
