import test from 'node:test';
import assert from 'node:assert/strict';
import {appleTransactionAccess, assertAppleAccountBinding, assertAppleSandboxAccess, refreshSignedAppleTransaction} from '../web_billing/apple_security.mjs';

const alice = '9fa257ac-9a3a-4f75-ae90-e058081a0390';
const bob = 'a3f1b7f4-2b2e-4e18-a981-2cd50b560270';
const transaction = {originalTransactionId: '100000000000001'};
test('upgraded Apple transactions never grant their replaced plan even before its old expiry', () => {
  const decoded = {expiresDate: 2000};
  assert.deepEqual(appleTransactionAccess(decoded, () => 1000), {active: true, status: 'active'});
  assert.deepEqual(appleTransactionAccess({...decoded, isUpgraded: true}, () => 1000), {active: false, status: 'expired'});
  assert.deepEqual(appleTransactionAccess({...decoded, revocationDate: 900}, () => 1000), {active: false, status: 'revoked'});
  assert.deepEqual(appleTransactionAccess(decoded, () => 2000), {active: false, status: 'expired'});
  assert.equal(appleTransactionAccess({...decoded, revocationDate: 'invalid'}, () => 1000).active, false);
});
function db(result) {
  return {from(table) {
    assert.equal(table, 'korlix_apple_transaction_bindings');
    return {select(columns) {
      assert.equal(columns, 'user_id');
      return {eq(column, value) {
        assert.equal(column, 'original_transaction_id');
        assert.equal(value, transaction.originalTransactionId);
        return {async maybeSingle() {return result;}};
      }};
    }};
  }};
}
const rejection = status => error => error.statusCode === status;
test('a signed account token grants only its account, with UUID case normalization', async () => {
  await assertAppleAccountBinding({userId: alice, transaction: {...transaction, appAccountToken: alice.toUpperCase()}});
  await assert.rejects(assertAppleAccountBinding({userId: bob, transaction: {...transaction, appAccountToken: alice}}), rejection(409));
});
test('transaction ID alone cannot claim an unbound purchase', async () => {
  await assert.rejects(assertAppleAccountBinding({userId: alice, transaction, database: db({data: null})}), rejection(409));
});
test('legacy restores require the existing server-owned account binding', async () => {
  await assertAppleAccountBinding({userId: alice, transaction, database: db({data: {user_id: alice}})});
  await assert.rejects(assertAppleAccountBinding({userId: bob, transaction, database: db({data: {user_id: alice}})}), rejection(409));
});
test('legacy ownership check fails closed when storage is unavailable', async () => {
  for (const database of [undefined, db({error: {message: 'offline'}}), {from() {throw new Error('offline');}}]) {
    await assert.rejects(assertAppleAccountBinding({userId: alice, transaction, database}), rejection(503));
  }
});
const signed = {environment: 'Production', decoded: {transactionId: '100000000000002', originalTransactionId: transaction.originalTransactionId,
  productId: 'pro', expiresDate: Date.now() + 86400000}};
function refresh(options = {}) {
  return refreshSignedAppleTransaction({signedTransactionInfo: 'signed.jws.data', expectedProductId: 'pro',
    verifyTransaction: async () => signed, fetchHistory: async () => signed, ...options});
}
test('replaying an active signed receipt returns the independently refreshed revoked state', async () => {
  const revoked = {...signed, decoded: {...signed.decoded, revocationDate: Date.now()}};
  let checked = false;
  const result = await refresh({fetchHistory: async input => {
    checked = true;
    assert.deepEqual(input, {transactionId: signed.decoded.transactionId, expectedProductId: 'pro'});
    return revoked;
  }});
  assert.equal(checked, true);
  assert.equal(result, revoked);
});
test('signed receipt cannot grant access when current provider state is unavailable', async () => {
  await assert.rejects(refresh({fetchHistory: async () => {throw new Error('provider unavailable');}}), /provider unavailable/);
});
test('signed receipt refresh cannot cross an original purchase, product or environment', async () => {
  for (const current of [
    {...signed, decoded: {...signed.decoded, originalTransactionId: 'different'}},
    {...signed, decoded: {...signed.decoded, productId: 'ultra'}},
    {...signed, environment: 'Sandbox'},
  ]) await assert.rejects(refresh({fetchHistory: async () => current}), rejection(409));
});
test('mismatched or incomplete signed purchases stop before provider history', async () => {
  let calls = 0;
  for (const decoded of [{...signed.decoded, productId: 'ultra'}, {...signed.decoded, transactionId: ''}, {...signed.decoded, originalTransactionId: ''}]) {
    await assert.rejects(refresh({verifyTransaction: async () => ({...signed, decoded}), fetchHistory: async () => {calls++;}}), rejection(400));
  }
  assert.equal(calls, 0);
});
const sandbox = {...transaction, appAccountToken: alice, environment: 'Sandbox', status: 'active',
  expiresAt: new Date(Date.now() + 86400000).toISOString()};
test('genuine active sandbox receipts cannot grant ordinary production accounts paid access', async () => {
  await assert.rejects(assertAppleAccountBinding({userId: alice, transaction: sandbox, environment: {}}),
    error => error.statusCode === 403 && /Sandbox test purchases are not enabled/.test(error.message));
  await assert.rejects(assertAppleAccountBinding({userId: alice, transaction: sandbox,
    environment: {APPLE_SANDBOX_ALLOWED_USER_IDS: bob}}), rejection(403));
});
test('only exact server allowlisted UUIDs may use paid sandbox testing', async () => {
  await assertAppleAccountBinding({userId: alice, transaction: sandbox,
    environment: {APPLE_SANDBOX_ALLOWED_USER_IDS: bob + ', ' + alice.toUpperCase()}});
  await assert.rejects(assertAppleAccountBinding({userId: alice, transaction: sandbox,
    environment: {APPLE_SANDBOX_ALLOWED_USER_IDS: '* ' + alice + '-suffix'}}), rejection(403));
  await assert.rejects(assertAppleAccountBinding({userId: alice, transaction: {...sandbox, app_metadata: {tester: true}, user_metadata: {tester: true}},
    environment: {}}), rejection(403));
});
test('sandbox grace-period grants require allowlisting; expired and revoked cleanup still works', () => {
  assert.throws(() => assertAppleSandboxAccess({userId: alice, transaction: {...sandbox, status: 'grace_period'}, environment: {}}), rejection(403));
  for (const update of [{status: 'expired'}, {status: 'revoked', revokedAt: new Date().toISOString()},
    {expiresAt: new Date(Date.now()-1000).toISOString()}]) {
    assertAppleSandboxAccess({userId: alice, transaction: {...sandbox, ...update}, environment: {}});
  }
  assertAppleSandboxAccess({userId: alice, transaction: {...sandbox, environment: 'Production'}, environment: {}});
});
