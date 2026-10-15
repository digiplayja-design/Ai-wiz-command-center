import {createHash} from 'node:crypto';
import {BillingError, fail, UUID} from '../web_billing/core.mjs';

export const PACKAGE = 'com.korlixdeveloper.korlixai';
export const PRODUCTS = Object.freeze({korlix_pro: 'pro', korlix_ultra: 'ultra'});
export const VERSION = 'google_play_monthly_v1';
export const accountId = id => createHash('sha256').update(`korlix:google-play:${id.toLowerCase()}`).digest('hex');
export function purchaseToken(value) {
  if (typeof value !== 'string' || value.length < 10 || value.length > 4096 || /\s/.test(value)) fail('Invalid Google Play purchase.');
  return value;
}
export const tokenHash = value => createHash('sha256').update(purchaseToken(value)).digest('hex');

// Only independently fetched Google facts may enter this function. Client
// product IDs are assertions to check, never a source of entitlement.
export function observation(data, {userId, token, expectedProduct, allowTest = false, now = Date.now()} = {}) {
  if (!UUID.test(userId || '')) fail('Sign in to verify your subscription.', 401);
  if (data?.externalAccountIdentifiers?.obfuscatedExternalAccountId !== accountId(userId)) {
    fail('This Google Play purchase belongs to a different KORLIX account.', 409);
  }
  if (data.testPurchase && !allowTest) fail('Test purchases are only enabled for designated test accounts.', 403);
  const items = data.lineItems;
  if (!Array.isArray(items) || items.length !== 1) fail('Unsupported Google Play subscription.', 409);
  const item = items[0], tier = PRODUCTS[item.productId];
  if (!tier || (expectedProduct && item.productId !== expectedProduct) ||
      item.offerDetails?.basePlanId !== 'monthly' || !item.autoRenewingPlan) {
    fail('This purchase does not match a KORLIX monthly plan.', 409);
  }
  const states = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
    'SUBSCRIPTION_STATE_CANCELED', 'SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_ON_HOLD',
    'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_PENDING', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'];
  if (!states.includes(data.subscriptionState)) fail('Google Play returned an unknown subscription state.', 502);
  const expires = Date.parse(item.expiryTime);
  const active = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'].includes(data.subscriptionState) && expires > now;
  if (active && !['ACKNOWLEDGEMENT_STATE_PENDING', 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(data.acknowledgementState)) {
    fail('Google Play has not confirmed the purchase.', 409);
  }
  return {purchase_token: purchaseToken(token), token_hash: tokenHash(token), account_id: accountId(userId),
    product_id: item.productId, tier, state: data.subscriptionState, active,
    expires_at: Number.isFinite(expires) ? new Date(expires).toISOString() : null,
    acknowledged: data.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    auto_renew: item.autoRenewingPlan.autoRenewEnabled === true, test_purchase: !!data.testPurchase,
    linked_hash: data.linkedPurchaseToken ? tokenHash(data.linkedPurchaseToken) : null};
}

export function playStore(database) {
  return {async command(actor, action, payload = {}) {
    if (!database) fail('Subscription storage is unavailable. Please retry.', 503);
    const {data, error} = await database.rpc('korlix_play_billing_command', {p_actor: actor || null, p_action: action, p: payload});
    if (error) {
      const known = /BILL(\d{3}): (.+)/.exec(error.message || '');
      if (known) throw new BillingError(known[2], Number(known[1]));
      fail('Subscription storage is unavailable. Please retry.', 503);
    }
    return data;
  }};
}
