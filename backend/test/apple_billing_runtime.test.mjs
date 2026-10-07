import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {appleTransactionAccess} from '../web_billing/apple_security.mjs';
import {createAccountRequestLimiter} from '../security/account_request_limiter.mjs';

// Run the actual server functions in an isolated provider harness. No Apple
// requests or real purchase mutations occur in these regression tests.
const source = readFileSync(new URL('../server.js', import.meta.url), 'utf8');
function section(start, end) {
  const offset = source.indexOf(start), stop = source.indexOf(end, offset);
  assert(offset >= 0 && stop > offset);
  return source.slice(offset, stop);
}
const bundle = 'com.korlixdeveloper.korlixai';
const makeHttpError = (message, statusCode) => Object.assign(new Error(message), {statusCode});
function historyFixture(page) {
  let reads = 0, verifications = 0;
  const context = vm.createContext({
    makeHttpError, KORLIX_APPLE_BUILD130_BUNDLE_ID: bundle,
    korlixAppleBuild130Config: async () => ({signingConfigured: true, library: {
      Order: {DESCENDING: 'descending'}, ProductType: {AUTO_RENEWABLE: 'auto'}, GetTransactionHistoryVersion: {V2: 'v2'},
    }}),
    korlixAppleBuild130VerifierAttempts: () => [{label: 'Production',
      client: {getTransactionHistory: async () => page(++reads)},
      verifier: {verifyAndDecodeTransaction: async raw => {verifications++; return JSON.parse(raw);}},
    }],
  });
  vm.runInContext(section('async function korlixAppleBuild130TransactionFromHistory(', 'async function korlixAppleBuild130ResolveTransaction('), context);
  return {read: () => context.korlixAppleBuild130TransactionFromHistory({transactionId: 'fixture', expectedProductId: 'pro'}),
    counts: () => ({reads, verifications})};
}

test('Apple history stops pagination cycles, missing cursors and excessive history before verification', async () => {
  const cases = [
    {page: () => ({hasMore: true, revision: 'same', signedTransactions: []}), reads: 2},
    {page: () => ({hasMore: true, signedTransactions: []}), reads: 1},
    {page: n => ({hasMore: true, revision: String(n), signedTransactions: []}), reads: 20},
    {page: () => ({hasMore: false, signedTransactions: Array(401).fill('payload')}), reads: 1},
  ];
  for (const c of cases) {
    const f = historyFixture(c.page);
    await assert.rejects(f.read(), error => error.statusCode === 503);
    assert.deepEqual(f.counts(), {reads: c.reads, verifications: 0});
  }
});

test('bounded Apple history verifies signatures and selects only the matching app and product', async () => {
  const f = historyFixture(() => ({hasMore: false, signedTransactions: [
    'invalid signed item',
    JSON.stringify({bundleId: 'foreign.bundle', productId: 'pro', expiresDate: 9000}),
    JSON.stringify({bundleId: bundle, productId: 'ultra', expiresDate: 8000}),
    JSON.stringify({bundleId: bundle, productId: 'pro', expiresDate: 1000}),
    JSON.stringify({bundleId: bundle, productId: 'pro', expiresDate: 2000}),
  ]}));
  assert.equal((await f.read()).decoded.expiresDate, 2000);
  assert.deepEqual(f.counts(), {reads: 1, verifications: 5});
});

test('actual server normalization cannot grant an upgraded but unexpired transaction', () => {
  const context = vm.createContext({makeHttpError, appleTransactionAccess,
    KORLIX_APPLE_BUILD130_BUNDLE_ID: bundle,
    korlixAppleBuild130ProductTier: () => 'pro',
    korlixAppleBuild130Iso: value => value ? new Date(value).toISOString() : null,
  });
  vm.runInContext(section('function korlixAppleBuild130NormalizeTransaction(', 'async function korlixAppleBuild130ApplyEntitlement('), context);
  const value = context.korlixAppleBuild130NormalizeTransaction({decoded: {
    bundleId: bundle, productId: 'pro', isUpgraded: true, expiresDate: Date.now() + 86400000,
  }});
  assert.equal(value.active, false);
  assert.equal(value.status, 'expired');
});

test('Apple refresh and verify share the authenticated account budget before provider work', async () => {
  const routes = new Map();
  let profiles = 0, providerReads = 0;
  const context = vm.createContext({createAccountRequestLimiter,
    app: {get: (path, handler) => routes.set(path, handler), post: (path, handler) => routes.set(path, handler)},
    requireUser: async req => ({id: req.user}),
    korlixAppleBuild130StatusForUser: async () => ({profile: {tier: 'basic'}, entitlement: null}),
    getOrCreateProfile: async () => {profiles++;},
    korlixAppleBuild130ProductTier: () => 'pro',
    korlixAppleBuild130ResolveTransaction: async () => {providerReads++; throw makeHttpError('Stop fixture before mutation.', 503);},
    supabaseAdmin: {}, createWebBillingStore: () => ({command: async () => ({membership: null})}),
    getKorlixUserFacingError: error => error.message, sanitize: value => value,
    console: {error: () => {}},
  });
  vm.runInContext(section('const consumeAppleVerification =', 'async function korlixAppleBuild130TransactionFromHistory(')
    + section('app.get("/api/billing/apple/status"', 'app.post("/api/billing/apple/notifications"'), context);
  const res = () => ({statusCode: 200, headers: {}, set(k, v) {this.headers[k] = v; return this;},
    status(value) {this.statusCode = value; return this;}, json(value) {this.body = value; return this;}});
  const status = routes.get('/api/billing/apple/status'), verify = routes.get('/api/billing/apple/verify');
  for (let i = 0; i < 20; i++) {
    const r = res(); await status({user: 'owner', query: {refresh: '1'}}, r); assert.equal(r.statusCode, 200);
  }
  const exhausted = res(); await verify({user: 'owner', body: {productId: 'pro'}}, exhausted);
  assert.equal(exhausted.statusCode, 429); assert(exhausted.headers['Retry-After']);
  assert.equal(profiles, 0); assert.equal(providerReads, 0);
  const passive = res(); await status({user: 'owner', query: {}}, passive); assert.equal(passive.statusCode, 200);
  const different = res(); await verify({user: 'other', body: {productId: 'pro'}}, different);
  assert.equal(different.statusCode, 503); assert.equal(providerReads, 1);
});
