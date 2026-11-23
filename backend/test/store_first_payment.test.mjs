import test from 'node:test';
import assert from 'node:assert/strict';
import {accountId, PACKAGE} from '../google_play/core.mjs';
import {googlePlay} from '../google_play/provider.mjs';
import {firstStoreCharge} from '../store_measurement/first_charge.mjs';
import {registerStorePaymentCheck} from '../store_measurement/check.mjs';

const userId = '13bfc220-693b-4851-8137-9f27524d3248';
const appleId = '1111111111111111';
const token = 'test_purchase_token';
const googleId = 'GPA.1234-5678-9012-34567';
const day = 86_400_000, start = Date.parse('2026-11-01T10:00:00Z');
const empty = {userId, appleBindings: [], googleBindings: []};

function appleTransaction(overrides = {}) {
  return {bundleId: PACKAGE, environment: 'Production', type: 'Auto-Renewable Subscription',
    productId: PACKAGE + '.pro.monthly', originalTransactionId: appleId, transactionId: appleId,
    inAppOwnershipType: 'PURCHASED', appAccountToken: userId, purchaseDate: start,
    price: 24990, currency: 'USD', ...overrides};
}

function appleFixture(pages) {
  return {appleBindings: [{original_transaction_id: appleId, environment: 'Production'}], apple: async () => ({
    library: {Order: {ASCENDING: 'ASCENDING'}, ProductType: {AUTO_RENEWABLE: 'AUTO_RENEWABLE'}, GetTransactionHistoryVersion: {V2: 'v2'}},
    productionClient: {getTransactionHistory: async (id, cursor, options) => {
      assert.equal(id, appleId);
      assert.equal(options.revoked, undefined);
      const i = Number(cursor ?? 0);
      return {signedTransactions: pages[i], hasMore: i + 1 < pages.length, revision: String(i + 1)};
    }},
    productionVerifier: {verifyAndDecodeTransaction: async signed => {
      if (signed === 'invalid-signature') throw new Error('Invalid signature.');
      return signed;
    }},
  })};
}

function playOrder(orderId, total, time = start, extras = {}) {
  return {orderId, purchaseToken: token, state: 'PROCESSED', total: {currencyCode: 'USD', ...total},
    orderHistory: {processedEvent: {eventTime: new Date(time).toISOString()}},
    lineItems: [{productId: 'korlix_pro', subscriptionDetails: {basePlanId: 'monthly'}}], ...extras};
}

function playFixture(orders, extras = {}) {
  const calls = [];
  return {googleBindings: [{purchase_token: token}], calls, play: {
    subscription: async t => {
      assert.equal(t, token);
      return {externalAccountIdentifiers: {obfuscatedExternalAccountId: accountId(userId)},
        lineItems: [{productId: 'korlix_pro', offerDetails: {basePlanId: 'monthly'},
          latestSuccessfulOrderId: orders.at(-1)?.orderId}], ...extras};
    },
    order: async id => {
      calls.push(id);
      const order = orders.find(o => o.orderId === id);
      if (!order) throw new Error('Missing order evidence.');
      return order;
    },
  }};
}

test('direct Apple first charge uses the signed price and original date despite a later renewal', async () => {
  const later = appleTransaction({transactionId: 'renewal', purchaseDate: start + 30 * day, price: 99000});
  const result = await firstStoreCharge({...empty, ...appleFixture([[later], [appleTransaction()]])});
  assert.deepEqual(result, {store: 'ios', time: start, value: 24.99, currency: 'USD', refunded: false});
});

test('a free Apple trial becomes a payment only at its first positive charge', async () => {
  const trial = appleTransaction({price: 0, offerDiscountType: 'FREE_TRIAL'});
  const paid = appleTransaction({transactionId: 'converted', purchaseDate: start + 3 * day, price: 4990});
  assert.equal(await firstStoreCharge({...empty, ...appleFixture([[trial]])}), null);
  assert.equal((await firstStoreCharge({...empty, ...appleFixture([[trial, paid]])})).time, paid.purchaseDate);
});

test('an invalid Apple signature or missing price on historical receipts withholds the result', async () => {
  for (const ent of ['invalid-signature', appleTransaction({price: undefined}), appleTransaction({appAccountToken: 'different'})]) {
    await assert.rejects(firstStoreCharge({...empty, ...appleFixture([[ent]])}));
  }
  assert.equal(await firstStoreCharge({...empty, appleBindings: [{environment: 'Sandbox'}]}), null);
});

test('Play reads the amount actually charged, follows a free trial to payment and stops before later renewals', async () => {
  const initial = playOrder(googleId, {units: '0'});
  const first = playOrder(googleId + '..0', {units: '9', nanos: 990_000_000}, start + 3 * day);
  const second = playOrder(googleId + '..1', {units: '100'}, start + 33 * day);
  const g = playFixture([initial, first, second]);
  const result = await firstStoreCharge({...empty, ...g});
  assert.deepEqual(g.calls, [initial.orderId, first.orderId]);
  assert.deepEqual(result, {store: 'android', time: start + 3 * day, value: 9.99, currency: 'USD', refunded: false});
  assert.equal(await firstStoreCharge({...empty, ...playFixture([initial])}), null);
});

test('a direct Play subscription payment outranks every later renewal', async () => {
  const g = playFixture([playOrder(googleId, {units:'20'}), playOrder(googleId + '..0', {units:'50'}, start + 30 * day)]);
  assert.equal((await firstStoreCharge({...empty, ...g})).value, 20);
  assert.deepEqual(g.calls, [googleId]);
});

test('pending signups, test purchases, one-offs and broken store linkages cannot qualify', async () => {
  const pending = playFixture([], {subscriptionState: 'SUBSCRIPTION_STATE_PENDING'});
  assert.equal(await firstStoreCharge({...empty, ...pending}), null);
  const base = playOrder(googleId, {units: '10'});
  assert.equal(await firstStoreCharge({...empty, ...playFixture([base], {testPurchase:{}})}), null);
  assert.equal(await firstStoreCharge({...empty, ...appleFixture([[appleTransaction({inAppOwnershipType:'FAMILY_SHARED'})]])}), null);
  for (const g of [playFixture([base], {linkedPurchaseToken:'missing'}),
    playFixture([base], {externalAccountIdentifiers:{}}), playFixture([{...base, state:'PENDING'}]),
    playFixture([{...base, purchaseToken:'wrong'}]), playFixture([{...base, total:null}]),
    playFixture([{...base, lineItems:[{productId:'ai_gas', oneTimePurchaseDetails:{}}]}])]) {
    await assert.rejects(firstStoreCharge({...empty, ...g}));
  }
});

test('a historical first purchase on either store prevents a new subscription or refund from becoming a new customer', async () => {
  const g = playFixture([playOrder(googleId, {units:'20'}, start + day)]);
  const both = {...empty, ...appleFixture([[appleTransaction({revocationDate:start+5000})]]), ...g};
  assert.deepEqual(await firstStoreCharge(both), {store:'ios', value:24.99, currency:'USD', time:start, refunded:true});
  await assert.rejects(firstStoreCharge({...both, appleBindings:[{environment:null, original_transaction_id:appleId}]}));
});

test('missing original, ambiguous simultaneous cross-store receipts, or missing Play order history stay unverified', async () => {
  await assert.rejects(firstStoreCharge({...empty, ...appleFixture([[appleTransaction({transactionId:'renewal'})]])}));
  await assert.rejects(firstStoreCharge({...empty, ...playFixture([playOrder(googleId+'..0', {units:'18'})])}));
  await assert.rejects(firstStoreCharge({...empty, ...appleFixture([[appleTransaction()]]),
    ...playFixture([playOrder(googleId, {units:'20'})])}));
});

test('the Play order lookup requests only receipt fields used for measurement', async () => {
  let requested;
  const play = googlePlay({}, {auth:{request: async options => {requested = new URL(options.url); return {data:{orderId:googleId}};}}});
  assert.deepEqual(await play.order(googleId), {orderId:googleId});
  assert.equal(requested.pathname, '/androidpublisher/v3/applications/'+PACKAGE+'/orders/'+googleId);
  assert.match(requested.searchParams.get('fields'), /processedEvent/);
  assert.doesNotMatch(requested.searchParams.get('fields'), /buyerAddress|tax|listingPrice/);
});

test('the gated, authenticated check derives the account from the session and returns only verified payment facts', async () => {
  let handler;
  const app = {get: (_path, fn) => {handler = fn;}};
  registerStorePaymentCheck(app, {});
  assert.equal(handler, undefined);
  const g = playFixture([playOrder(googleId, {units:'5'})]);
  const database = {from(table) {
    return {select() {return this;}, eq(column, val) {
      assert.equal(val, column === 'user_id' ? userId : false);
      return this;
    }, limit: async () => ({data: table === 'korlix_play_purchases' ? g.googleBindings : []})};
  }};
  registerStorePaymentCheck(app, {database, requireUser: async () => ({id:userId, email_confirmed_at:'confirmed'}),
    enabled:true, play:g.play});
  let result;
  const res = {set() {return this;}, status() {return this;}, json(value) {result=value;}};
  await handler({query:{user_id:'somebody-else'}}, res);
  assert.deepEqual(result, {status:'verified', store:'android', value:5, currency:'USD', paidAt:new Date(start).toISOString()});
});
