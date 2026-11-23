import test from 'node:test';
import assert from 'node:assert/strict';
import {checkAppleSandboxFirstPayment} from '../scripts/check_apple_sandbox_first_payment.mjs';
import {firstStoreCharge} from '../store_measurement/first_charge.mjs';

const owner = '77777777-7777-4777-8777-777777777777';
const original = '10000001';
const bundle = 'com.korlixdeveloper.korlixai';
const base = {bundleId: bundle, environment: 'Sandbox', originalTransactionId: original,
  transactionId: original, type: 'Auto-Renewable Subscription', productId: bundle + '.pro.monthly',
  inAppOwnershipType: 'PURCHASED', appAccountToken: owner, purchaseDate: 10000, price: 990, currency: 'USD'};
const trial = {...base, price: 0, offerDiscountType: 'FREE_TRIAL'};
const paid = {...base, transactionId: '10000002', purchaseDate: 20000};
const renewal = {...base, transactionId: '10000003', purchaseDate: 30000};

function fixture(pages) {
  const signed = new Map();
  const results = pages.map((page, index) => ({
    revision: String(index + 1), hasMore: index + 1 < pages.length,
    signedTransactions: page.map((tx, i) => {
      const token = 'fixture-' + index + '-' + i;
      signed.set(token, tx);
      return token;
    }),
  }));
  return async () => ({
    library: {Order: {ASCENDING: 'ASCENDING'}, ProductType: {AUTO_RENEWABLE: 'AUTO_RENEWABLE'},
      GetTransactionHistoryVersion: {V2: 'v2'}},
    sandboxClient: {getTransactionHistory: async (id, revision, options, version) => {
      assert.equal(id, original);
      assert.equal(version, 'v2');
      assert.deepEqual(options.productIds, [bundle + '.pro.monthly', bundle + '.ultra.monthly']);
      return results[Number(revision)];
    }},
    sandboxVerifier: {verifyAndDecodeTransaction: async token => {
      const tx = signed.get(token);
      if (!tx || tx === 'invalid-signature') throw new Error('Sensitive fixture must never reach stdout.');
      return tx;
    }},
  });
}

const check = pages => checkAppleSandboxFirstPayment(original, owner, fixture(pages));
const skip = {status: 'skip', freeTrials: 0, firstPayments: 0, laterPayments: 0};

test('zero-price trial stays pending until the first verified nonzero sandbox price', async () => {
  assert.deepEqual(await check([[trial]]), {status: 'pending', freeTrials: 1, firstPayments: 0, laterPayments: 0});
  assert.deepEqual(await check([[trial, paid]]), {status: 'ready', freeTrials: 1, firstPayments: 1, laterPayments: 0});
  assert.deepEqual(await check([[base]]), {status: 'ready', freeTrials: 0, firstPayments: 1, laterPayments: 0});
});

test('duplicates and subsequent renewals do not add more first payments', async () => {
  const pages = [[trial, paid], [paid, renewal]];
  const expected = {status: 'ready', freeTrials: 1, firstPayments: 1, laterPayments: 1};
  assert.deepEqual(await check(pages), expected);
  assert.deepEqual(await check(pages), expected);
  assert.deepEqual(await check([[trial, {...paid, revocationDate: 40000}, renewal]]), skip);
});

test('verifies signed source, owner, transaction chain and earliest positive amount', async () => {
  for (const tx of [
    'invalid-signature', {...base, environment: 'Production'}, {...base, bundleId: 'another.app'},
    {...base, productId: 'unrelated'}, {...base, appAccountToken: undefined}, {...base, appAccountToken: original},
    {...base, inAppOwnershipType: 'FAMILY_SHARED'}, {...base, originalTransactionId: '1111'},
    {...base, transactionId: '1112'}, {...base, price: undefined}, {...base, price: -1},
    {...base, currency: 'INVALID'}, {...base, offerDiscountType: 'FREE_TRIAL'},
  ]) assert.deepEqual(await check([[tx]]), skip);
  assert.deepEqual(await check([[trial, paid, {...paid, price: 1200}]]), skip);
  assert.deepEqual(await check([[trial, paid, {...renewal, purchaseDate: paid.purchaseDate}]]), skip);
  assert.deepEqual(await check([[trial, {...paid, purchaseDate: 5000}]]), skip);
});

test('rejects invalid identifier inputs locally and production classification still skips Sandbox', async () => {
  const noCall = () => assert.fail('The provider should not be initialized.');
  assert.deepEqual(await checkAppleSandboxFirstPayment('https://untrusted.test', owner, noCall), skip);
  assert.deepEqual(await checkAppleSandboxFirstPayment(original, '', noCall), skip);
  assert.equal(await firstStoreCharge({userId: owner, appleBindings: [{environment: 'Sandbox',
    original_transaction_id: original}], googleBindings: [], apple: noCall, play: noCall}), null);
});

test('a production binding still requires production provenance and selects the earliest charged renewal', async () => {
  const run = async pages => {
    const {library, sandboxClient, sandboxVerifier} = await fixture(pages)();
    return firstStoreCharge({userId: owner, appleBindings: [{environment: 'Production',
      original_transaction_id: original}], googleBindings: [], apple: async () => ({
      library, productionClient: sandboxClient, productionVerifier: sandboxVerifier,
    })});
  };
  await assert.rejects(run([[trial, paid]]));
  const production = tx => ({...tx, environment: 'Production'});
  assert.deepEqual(await run([[production(trial), production(renewal)], [production(paid)]]),
    {store: 'ios', time: paid.purchaseDate, value: 0.99, currency: 'USD', refunded: false});
});
