import {createHash} from 'node:crypto';
import {accountId, PACKAGE, PRODUCTS as GOOGLE_PRODUCTS} from '../google_play/core.mjs';

export const APPLE_PRODUCTS = [
  'com.korlixdeveloper.korlixai.pro.monthly',
  'com.korlixdeveloper.korlixai.ultra.monthly',
];
const CURRENCY = /^[A-Z]{3}$/;
const MAX_HISTORY_REQUESTS = 20;

function incomplete() {
  throw new Error('Store payment history could not be verified.');
}

function earliest(charges) {
  let first = null;
  for (const charge of charges) {
    if (!charge) continue;
    if (!first || charge.time < first.time) first = charge;
    else if (charge.time === first.time && charge.store !== first.store) incomplete();
    else if (charge.time === first.time && charge.refunded) first = charge;
  }
  return first;
}

async function firstAppleCharge(originalId, userId, apple) {
  const {library, productionClient, productionVerifier} = await apple();
  if (!productionClient || !productionVerifier) incomplete();
  const options = {sort: library.Order.ASCENDING, productIds: APPLE_PRODUCTS,
    productTypes: [library.ProductType.AUTO_RENEWABLE]};
  let revision = null;
  const revisions = new Set();
  const charges = [];
  let sawOriginal = false;
  let original;
  for (let page = 0; page < MAX_HISTORY_REQUESTS; page++) {
    const history = await productionClient.getTransactionHistory(originalId, revision, options, library.GetTransactionHistoryVersion.V2);
    if (!Array.isArray(history?.signedTransactions) || typeof history.hasMore !== 'boolean') incomplete();
    for (const signed of history.signedTransactions) {
      const tx = await productionVerifier.verifyAndDecodeTransaction(signed);
      if (tx.bundleId !== PACKAGE || tx.environment !== 'Production') incomplete();
      if (tx.originalTransactionId !== originalId || !APPLE_PRODUCTS.includes(tx.productId)) continue;
      if (tx.transactionId === originalId) sawOriginal = true;
      if (tx.inAppOwnershipType === 'FAMILY_SHARED') continue;
      if (tx.inAppOwnershipType !== 'PURCHASED' || tx.type !== 'Auto-Renewable Subscription' ||
          (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== userId.toLowerCase())) incomplete();
      if (!tx.transactionId || !Number.isSafeInteger(tx.purchaseDate) || tx.purchaseDate <= 0) incomplete();
      if (tx.transactionId === originalId) original = {startedAt: tx.purchaseDate, sku: tx.productId};
      // An older payload may omit price. Only an explicit free trial proves a zero charge in that case.
      if (tx.offerDiscountType === 'FREE_TRIAL' && (tx.price == null || tx.price === 0)) continue;
      if (!Number.isSafeInteger(tx.price) || tx.price < 0 || tx.offerDiscountType === 'FREE_TRIAL') incomplete();
      if (tx.price === 0) continue;
      if (!CURRENCY.test(tx.currency ?? '')) incomplete();
      charges.push({store: 'ios', time: tx.purchaseDate, value: tx.price / 1000, currency: tx.currency,
        refunded: tx.revocationDate != null});
    }
    if (!history.hasMore) {
      if (!sawOriginal) incomplete();
      const charge = earliest(charges);
      if (charge && !original) incomplete();
      return charge && {...charge, source: {...original, hash: bindingHash(originalId)}};
    }
    revision = history.revision;
    if (!revision || revisions.has(revision)) incomplete();
    revisions.add(revision);
  }
  incomplete();
}

function orderTotal(money) {
  if (!money || !CURRENCY.test(money.currencyCode ?? '')) incomplete();
  const units = String(money.units ?? 0);
  const nanos = money.nanos ?? 0;
  if (!/^\d+$/.test(units) || !Number.isSafeInteger(Number(units)) ||
      !Number.isInteger(nanos) || nanos < 0 || nanos >= 1e9) incomplete();
  return Number(units) + nanos / 1e9;
}

async function firstGoogleCharge(token, userId, knownTokens, play) {
  const sub = await play.subscription(token);
  if (sub.externalAccountIdentifiers?.obfuscatedExternalAccountId !== accountId(userId) ||
      (sub.linkedPurchaseToken && !knownTokens.has(sub.linkedPurchaseToken))) incomplete();
  if (sub.testPurchase != null) return null;
  if (!Array.isArray(sub.lineItems) || sub.lineItems.length !== 1) incomplete();
  const item = sub.lineItems[0];
  if (!Object.hasOwn(GOOGLE_PRODUCTS, item.productId) || item.offerDetails?.basePlanId !== 'monthly') incomplete();
  if (!item.latestSuccessfulOrderId && ['SUBSCRIPTION_STATE_PENDING','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'].includes(sub.subscriptionState)) return null;
  const match = /^(GPA\.\d{4}-\d{4}-\d{4}-\d{5})(?:\.\.(\d+))?$/.exec(item.latestSuccessfulOrderId ?? '');
  if (!match) incomplete();
  const baseId = match[1], latest = match[2] === undefined ? -1 : Number(match[2]);
  // Google numbers the original order separately, then renewals starting with ..0.
  // Always read the original charge first, even for a current paid renewal.
  let original;
  for (let cycle = -1; cycle <= latest; cycle++) {
    if (cycle + 1 >= MAX_HISTORY_REQUESTS) incomplete();
    const orderId = cycle < 0 ? baseId : baseId + '..' + cycle;
    const order = await play.order(orderId);
    if (order.orderId !== orderId || order.purchaseToken !== token || order.lineItems?.length !== 1) incomplete();
    const line = order.lineItems[0];
    if (!Object.hasOwn(GOOGLE_PRODUCTS, line.productId) || line.subscriptionDetails?.basePlanId !== 'monthly') incomplete();
    const processed = order.orderHistory?.processedEvent?.eventTime;
    if (order.state === 'CANCELED' && !processed) continue;
    if (!['PROCESSED','PENDING_REFUND','PARTIALLY_REFUNDED','REFUNDED'].includes(order.state) || !processed) incomplete();
    const time = Date.parse(processed), value = orderTotal(order.total);
    if (!Number.isFinite(time) || time <= 0) incomplete();
    if (cycle === -1) original = {startedAt: time, sku: line.productId};
    if (value > 0 && !original) incomplete();
    if (value > 0) return {store: 'android', time, value, currency: order.total.currencyCode,
      refunded: order.state !== 'PROCESSED', source: {...original, hash: bindingHash(token)}};
  }
  return null;
}

// The database supplies every store binding owned by the authenticated KORLIX account.
// An unavailable older binding must block attribution on either store.
export function bindingHash(value) {
  return createHash('sha256').update(value).digest('hex');
}

export async function firstStoreCharge({userId, appleBindings, googleBindings, apple, play, withSource = false}) {
  const charges = [];
  for (const binding of appleBindings) {
    if (binding.environment === 'Sandbox') continue;
    if (binding.environment !== 'Production' || !binding.original_transaction_id) incomplete();
    charges.push(await firstAppleCharge(binding.original_transaction_id, userId, apple));
  }
  const knownTokens = new Set(googleBindings.map(binding => binding.purchase_token));
  for (const token of knownTokens) charges.push(await firstGoogleCharge(token, userId, knownTokens, play));
  const first = earliest(charges);
  if (!first || withSource) return first;
  const {source, ...payment} = first;
  return payment;
}
