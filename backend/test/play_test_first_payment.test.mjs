import assert from 'node:assert/strict';
import test from 'node:test';
import {accountId} from '../google_play/core.mjs';
import {checkPlayTestFirstPayment} from '../scripts/check_play_test_first_payment.mjs';
import {firstStoreCharge} from '../store_measurement/first_charge.mjs';

const tester = '77777777-7777-4777-8777-777777777777';
const token = 'fixture-original-token';
const base = 'GPA.1234-5678-9012-34567';
const orderId = i => i === 0 ? base : base + '..' + (i - 1);

function fixture(values, subscriptionChanges = {}, orderChanges = {}) {
  const line = {productId: 'korlix_pro', offerDetails: {basePlanId: 'monthly'}};
  const sub = {testPurchase: {}, externalAccountIdentifiers: {obfuscatedExternalAccountId: accountId(tester)},
    lineItems: [{...line, latestSuccessfulOrderId: orderId(values.length - 1)}], ...subscriptionChanges};
  const reads = [];
  const orders = values.map((value, i) => ({
    orderId: orderId(i), purchaseToken: token, state: 'PROCESSED',
    lineItems: [{productId:'korlix_pro', subscriptionDetails: {basePlanId:'monthly'}}],
    total: {currencyCode:'USD', units:String(value)},
    orderHistory: {processedEvent: {eventTime:new Date(10000 + i * 10000).toISOString()}},
    ...orderChanges[i],
  }));
  const provider = {subscription: async supplied => { assert.equal(supplied, token); return sub; },
    order: async id => { reads.push(id); return orders.find(order => order.orderId === id); }};
  return {provider, reads};
}

const run = f => checkPlayTestFirstPayment(token, tester, async () => f.provider);
const skip = {status:'skip', zeroValueOrders:0, firstPayments:0, laterPayments:0};

test('read-only test orders distinguish zero, first positive and later positive totals', async () => {
  assert.deepEqual(await run(fixture([0])), {status:'pending', zeroValueOrders:1, firstPayments:0, laterPayments:0});
  const f = fixture([0, 5, 5]);
  const expect = {status:'ready', zeroValueOrders:1, firstPayments:1, laterPayments:1};
  assert.deepEqual(await run(f), expect);
  assert.deepEqual(f.reads, [base, base+'..0', base+'..1']);
  assert.deepEqual(await run(f), expect);
  assert.deepEqual(await run(fixture([5])), {...expect, zeroValueOrders:0, laterPayments:0});
});

test('a production purchase, different owner or linked upgrade never reads an order', async () => {
  for (const changes of [{testPurchase:undefined}, {testPurchase:null}, {testPurchase:'true'},
    {externalAccountIdentifiers:{}}, {linkedPurchaseToken:'older-unknown-token'}]) {
    const f = fixture([5], changes);
    assert.deepEqual(await run(f), skip);
    assert.equal(f.reads.length, 0);
  }
});

test('incomplete, inconsistent and refunded first orders return no counts', async () => {
  for (const changes of [{state:'REFUNDED'}, {total:{currencyCode:'??'}}, {purchaseToken:'other'},
    {lineItems:[{productId:'other',subscriptionDetails:{basePlanId:'monthly'}}]},
    {orderHistory:{processedEvent:{eventTime:new Date(10000).toISOString()}}},
    {orderId:'another-order'}]) {
    assert.deepEqual(await run(fixture([0,5,5], {}, {1:changes})), skip);
  }
  assert.deepEqual(await run(fixture([0,5,5], {}, {2:{state:'REFUNDED'}})),
    {status:'ready', zeroValueOrders:1, firstPayments:1, laterPayments:0});
});

test('invalid inputs fail before provider use and provider errors do not expose identifiers', async () => {
  const noRead = () => assert.fail('provider not expected');
  assert.deepEqual(await checkPlayTestFirstPayment('tiny',tester,noRead), skip);
  assert.deepEqual(await checkPlayTestFirstPayment(token,'invalid',noRead), skip);
  const broken = () => {throw new Error('private fixture detail');};
  assert.deepEqual(await checkPlayTestFirstPayment(token,tester,broken), skip);
});

test('production classifier still excludes test orders, and stops on first positive production charge', async () => {
  const runProduction = f => firstStoreCharge({userId:tester, googleBindings:[{purchase_token:token}],
    appleBindings:[], play:f.provider});
  const f = fixture([3]);
  assert.equal(await runProduction(f), null);
  assert.deepEqual(f.reads, []);
  const production = fixture([0,5,5], {testPurchase:undefined});
  assert.deepEqual(await runProduction(production), {store:'android', time:20000, value:5, currency:'USD', refunded:false});
  assert.deepEqual(production.reads, [base,base+'..0']);
});
