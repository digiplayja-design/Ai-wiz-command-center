import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createKorlixSignupHandler, KORLIX_SIGNUP_POLICY_VERSION} from '../korlix_signup_eligibility.mjs';

const instant = new Date('2026-10-06T12:00:00Z');
const valid = {
  age_band: '18_plus', terms_accepted: true, privacy_acknowledged: true,
  parent_permission: false, policy_version: KORLIX_SIGNUP_POLICY_VERSION,
};
const credentials = {email: ' Member@Example.Test ', password: 'test-password'};

async function request(eligibility, {data = {user: {id: 'fixture-user', email: 'member@example.test'}, session: null}, error, body = credentials, throws = false} = {}) {
  const calls = [], profiles = [], sessions = [];
  const handler = createKorlixSignupHandler({
    supabaseAuth: {auth: {signUp: async (value) => {
      calls.push(value);
      if (throws) throw new Error('Provider unavailable');
      return {data, error};
    }}},
    getRequestDeviceInfo: () => ({id: 'fixture-device'}),
    getOrCreateProfile: async user => {profiles.push(user); return {id: 'fixture-profile'};},
    registerDeviceSession: async input => {sessions.push(input); return {id: 'fixture-session'};},
    getUserFacingError: error => error.message,
    now: () => instant,
  });
  const response = {statusCode: 200, status(value) {this.statusCode = value; return this;}, json(value) {this.body = value; return this;}};
  await handler({body: {...body, signup_eligibility: eligibility}}, response);
  return {response, calls, profiles, sessions};
}

for (const [label, declaration, code] of [
  ['legacy client missing declarations', undefined, 'SIGNUP_ELIGIBILITY_REQUIRED'],
  ['null declaration', null, 'SIGNUP_ELIGIBILITY_REQUIRED'],
  ['array declaration', [], 'SIGNUP_ELIGIBILITY_REQUIRED'],
  ['under 16 despite all acknowledgments', {...valid, age_band: 'under_16', parent_permission: true}, 'SIGNUP_AGE_RESTRICTED'],
  ['missing age', {...valid, age_band: undefined}, 'SIGNUP_AGE_REQUIRED'],
  ['unrecognized age', {...valid, age_band: '16'}, 'SIGNUP_AGE_REQUIRED'],
  ['unchecked terms', {...valid, terms_accepted: false}, 'SIGNUP_POLICIES_REQUIRED'],
  ['string instead of true', {...valid, terms_accepted: 'true'}, 'SIGNUP_POLICIES_REQUIRED'],
  ['missing privacy acknowledgment', {...valid, privacy_acknowledged: undefined}, 'SIGNUP_POLICIES_REQUIRED'],
  ['outdated policy', {...valid, policy_version: '2026-01-01'}, 'SIGNUP_POLICY_CHANGED'],
  ['teen without guardian permission', {...valid, age_band: '16_17'}, 'SIGNUP_PARENT_PERMISSION_REQUIRED'],
]) {
  test(`${label} never calls the account provider or creates a profile`, async () => {
    const {response, calls, profiles, sessions} = await request(declaration);
    assert.equal(response.statusCode, 400);
    assert.equal(response.body.code, code);
    assert.equal(calls.length + profiles.length + sessions.length, 0);
    assert.equal(response.body.session, undefined);
  });
}

test('adult signup saves only normalized self-declarations and retains email confirmation', async () => {
  const {response, calls, profiles, sessions} = await request({...valid, declared_at: 'forged', minimum_age: 1, verified: true, birth_date: '2000-01-01'});
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.session, null);
  assert.match(response.body.message, /Check your email/);
  assert.equal(profiles.length + sessions.length, 0);
  assert.deepEqual(calls, [{
    email: 'member@example.test', password: 'test-password',
    options: {data: {korlix_signup_declaration: {
      age_band: '18_plus', minimum_age: 16, terms_accepted: true,
      privacy_acknowledged: true, parent_permission: false,
      policy_version: '2026-10-06', declared_at: instant.toISOString(), method: 'self_declaration',
    }}},
  }]);
});

test('eligible teen with permission retains provider session and device registration', async () => {
  const data = {user: {id: 'teen-fixture', email: 'member@example.test'}, session: {access_token: 'offline-token', refresh_token: 'offline-refresh', expires_at: 1234}};
  const {response, calls, profiles, sessions} = await request({...valid, age_band: '16_17', parent_permission: true}, {data});
  assert.equal(response.statusCode, 200);
  assert.equal(calls[0].options.data.korlix_signup_declaration.parent_permission, true);
  assert.equal(calls[0].options.data.korlix_signup_declaration.age_band, '16_17');
  assert.equal(profiles[0].id, 'teen-fixture');
  assert.equal(sessions[0].deviceInfo.id, 'fixture-device');
  assert.deepEqual(response.body.session, data.session);
});

test('provider rejection and exceptions never create profiles or sessions', async () => {
  for (const options of [{error: {status: 429, message: 'Try again later'}}, {throws: true}]) {
    const {response, profiles, sessions} = await request(valid, options);
    assert.equal(response.statusCode, options.throws ? 500 : 429);
    assert.equal(profiles.length + sessions.length, 0);
    assert.equal(response.body.session, undefined);
  }
});

test('existing credential validation remains before any provider request', async () => {
  for (const body of [{}, {...credentials, password: 'short'}]) {
    const {response, calls} = await request(valid, {body});
    assert.equal(response.statusCode, 400);
    assert.equal(calls.length, 0);
  }
});
