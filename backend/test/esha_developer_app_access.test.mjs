import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createEshaBilling} from '../esha/billing/routes.mjs';
import {ESHA_PRODUCT} from '../esha/billing/catalog.mjs';
import {authenticatedDeveloperUser} from '../security/developer_access.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const user = {id: owner, email: 'support@example.test', email_confirmed_at: '2026-01-01T00:00:00Z'};
const emptyMembership = {active: false, trial: false, verificationFresh: false, expiresAt: null, provider: null, autoRenewing: false};
const allowance = {configured: false, limit: null, remaining: null, used: 0, reserved: 0, periodEndsAt: null};
const activeMembership = () => ({active: true, trial: false, verificationFresh: true,
  expiresAt: new Date(Date.now() + 86400000).toISOString(), provider: 'apple', autoRenewing: true});

async function fixture(t, {grant = true, authUser = user, membership = emptyMembership} = {}) {
  const state = {account: {id: owner, is_disabled: false, developer_access: [{enabled: grant}]}, authUser,
    membership: {...membership}, actions: [], verified: 0, finished: 0, generated: 0};
  const billing = createEshaBilling({autoStart: false, environment: {},
    requireUser: async req => req.headers.authorization === 'Bearer fixture' && state.authUser
      ? authenticatedDeveloperUser(state.authUser, state.account) : null,
    provider: {ready: () => false, verify: async (_provider, details) => {
      assert.equal(details.userId, owner); state.verified++;
      return {provider: 'apple', active: true, trial: false};
    }, finish: async () => { state.finished++; }},
    generate: async () => { state.generated++; throw new Error('Paid AI must remain gated.'); },
    store: async (actor, action) => {
      assert.equal(actor, owner); state.actions.push(action);
      if (action === 'purchases') return [];
      if (action === 'apply') state.membership = activeMembership();
      else assert.equal(action, 'snapshot');
      return {membership: {...state.membership}, allowance: {...allowance}};
    }});
  const app = express(); app.use(express.json()); billing.register(app);
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (path = '/api/esha/billing/status?provider=apple&refresh=1', body, authenticated = true) => {
    const response = await fetch(base + path, {method: body ? 'POST' : 'GET',
      headers: {'content-type': 'application/json', ...(authenticated ? {authorization: 'Bearer fixture'} : {})},
      ...(body ? {body: JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json(), cache: response.headers.get('cache-control')};
  };
  return {state, billing, request};
}

test('an existing authenticated developer grant opens app access without inventing a store membership', async t => {
  const {state, request} = await fixture(t);
  const result = await request();
  assert.equal(result.status, 200);
  assert.equal(result.cache, 'no-store');
  assert.deepEqual(result.body.appAccess, {active: true, source: 'developer'});
  assert.deepEqual(result.body.membership, emptyMembership);
  assert.deepEqual(result.body.allowance, allowance);
  assert.equal(result.body.purchasesEnabled, false);
  assert.equal(result.body.consultationEnabled, false);
  assert.deepEqual(state.actions, ['purchases', 'snapshot']);
  assert.equal(state.verified, 0); assert.equal(state.generated, 0);
});

test('an ordinary account stays gated even with developer-looking email, profile metadata, query and body claims', async t => {
  const {state, request} = await fixture(t, {grant: false, authUser: {...user,
    developer_unlimited: true, user_metadata: {developer_unlimited: true, role: 'developer'}}});
  const result = await request('/api/esha/billing/status?provider=apple&developer_unlimited=true&role=developer');
  assert.deepEqual(result.body.appAccess, {active: false, source: null});
  const prepare = await request('/api/esha/billing/prepare', {provider: 'apple', productId: ESHA_PRODUCT.apple,
    developer_unlimited: true, appAccess: {active: true, source: 'developer'}});
  assert.equal(prepare.status, 503); assert.equal(prepare.body.code, 'purchases_disabled');
  assert.equal(state.verified, 0);
});

test('revoking the server-owned grant removes access on the next authenticated status response', async t => {
  const {state, request} = await fixture(t);
  assert.equal((await request()).body.appAccess.active, true);
  state.account.developer_access[0].enabled = false;
  assert.deepEqual((await request()).body.appAccess, {active: false, source: null});
});

test('disabled, mismatched and nonboolean grants cannot open developer access', async t => {
  const {state, request, billing} = await fixture(t);
  for (const account of [
    {id: owner, is_disabled: true, developer_access: [{enabled: true}]},
    {id: other, is_disabled: false, developer_access: [{enabled: true}]},
    {id: owner, is_disabled: false, developer_access: [{enabled: 'true'}]},
  ]) {
    state.account = account;
    assert.deepEqual((await request()).body.appAccess, {active: false, source: null});
  }
  const mismatched = await billing.snapshot(owner, 'apple', null,
    {authenticatedUser: {...user, id: other, developer_unlimited: true}});
  assert.deepEqual(mismatched.appAccess, {active: false, source: null});
  const disabled = await billing.snapshot(owner, 'apple', null,
    {authenticatedUser: {...user, is_disabled: true, developer_unlimited: true}});
  assert.deepEqual(disabled.appAccess, {active: false, source: null});
});

test('authentication and confirmed email are still required; the public catalog carries no developer access', async t => {
  const {state, request} = await fixture(t);
  assert.equal((await request(undefined, undefined, false)).status, 401);
  state.authUser = {...user, email_confirmed_at: null};
  const unconfirmed = await request();
  assert.equal(unconfirmed.status, 403); assert.equal(unconfirmed.body.code, 'email_confirmation_required');
  const catalog = await request('/api/esha/billing/catalog?provider=apple', undefined, false);
  assert.equal(catalog.status, 200); assert.equal('appAccess' in catalog.body, false);
  assert.deepEqual(state.actions, []);
});

test('fresh real store membership keeps ordinary app access; stale or expired membership does not', async t => {
  const {state, request} = await fixture(t, {grant: false, membership: activeMembership()});
  assert.deepEqual((await request()).body.appAccess, {active: true, source: 'store'});
  state.membership.verificationFresh = false;
  assert.deepEqual((await request()).body.appAccess, {active: false, source: null});
  state.membership = {...activeMembership(), expiresAt: new Date(Date.now() - 1000).toISOString()};
  assert.deepEqual((await request()).body.appAccess, {active: false, source: null});
});

test('a developer cannot begin a redundant checkout and no store work is performed', async t => {
  const {state, request} = await fixture(t);
  const result = await request('/api/esha/billing/prepare', {provider: 'apple', productId: ESHA_PRODUCT.apple});
  assert.equal(result.status, 409); assert.equal(result.body.code, 'developer_access_active');
  assert.deepEqual(state.actions, []); assert.equal(state.verified, 0);
});

test('verified purchase responses retain separate developer access and truthful store verification', async t => {
  const {state, request, billing} = await fixture(t);
  const result = await request('/api/esha/billing/verify', {provider: 'apple', productId: ESHA_PRODUCT.apple, purchaseId: 'fixture'});
  assert.equal(result.status, 200); assert.equal(result.body.verified, true); assert.equal(result.body.completePurchase, true);
  assert.deepEqual(result.body.status.appAccess, {active: true, source: 'developer'});
  assert.equal(result.body.status.membership.active, true);
  assert.equal(state.verified, 1); assert.equal(state.finished, 1);
  // Background reconciliation without an authenticated principal cannot manufacture a developer grant.
  state.membership = {...emptyMembership};
  assert.deepEqual((await billing.snapshot(owner, 'apple')).appAccess, {active: false, source: null});
});

test('developer app access does not enable unconfigured paid AI or consume a consultation', async t => {
  const {state, request} = await fixture(t);
  const result = await request('/api/esha/consult', {requestId: '33333333-3333-4333-8333-333333333333', question: 'A look?'});
  assert.equal(result.status, 503); assert.equal(result.body.code, 'native_ai_not_configured');
  assert.deepEqual(state.actions, []); assert.equal(state.generated, 0);
});
