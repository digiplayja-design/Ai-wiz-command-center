import {createHash} from 'node:crypto';
import astra from '../../korlix_astra.cjs';

// Candidate identifiers are deliberately distinct from Korlix core and Brain+Voice.
// Setting a product-ready flag means an operator has checked the actual store record.
export const ESHA_BUNDLE = 'com.korlixdeveloper.esha';
export const ESHA_CATALOG_VERSION = 'esha_monthly_v1';
export const ESHA_AI_ROLE_POLICY = 'conversation_and_deep_thinking_v1';
// Owner-approved commercial allowances. Engineering token/attempt/session bounds
// remain explicit configuration and are not inferred from these quantities.
export const ESHA_APPROVED_ALLOWANCES = Object.freeze({
  trial: Object.freeze({voiceSeconds: 300, deepConsultations: 2}),
  monthly: Object.freeze({voiceSeconds: 1800, deepConsultations: 10}),
});
// Owner-selected roles use distinct APIs. Resolving Live's model does not prove
// the provider duration bound or make the prepared voice integration live.
export const ESHA_AI_ROLES = Object.freeze({
  conversation: Object.freeze({requestedModel: 'Highest live conversation model OpenAI has',
    model: 'gpt-live-1', reasoningEffort: null, api: 'live', transport: 'webrtc'}),
  deep_thinking: Object.freeze({requestedModel: 'Sol 6.1', model: 'gpt-6.1-sol',
    reasoningEffort: 'high', api: 'responses', transport: 'https'}),
});
export const ESHA_PRODUCT = Object.freeze({
  apple: 'com.korlixdeveloper.esha.monthly', google: 'esha_monthly',
  basePlanId: 'monthly', offerId: 'trial-3-days', billingPeriod: 'P1M',
  trialDays: 3, monthlyPriceCents: 499, currency: 'USD',
});
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export class EshaBillingError extends Error {
  constructor(message, status = 400, code = 'invalid_request') {
    super(message); this.name = 'EshaBillingError'; this.status = status; this.code = code;
  }
}
export function fail(message, status = 400, code = 'invalid_request') { throw new EshaBillingError(message, status, code); }
export const digest = value => createHash('sha256').update(value).digest('hex');
export function eshaAccountId(id) {
  if (!UUID.test(id || '')) fail('Sign in to your Korlix account.', 401, 'authentication_required');
  return digest(`korlix:esha:google:${id.toLowerCase()}`);
}
export function productFor(provider, id = ESHA_PRODUCT[provider]) {
  if (!['apple', 'google'].includes(provider) || id !== ESHA_PRODUCT[provider]) {
    fail('Choose the Esha monthly membership.', 400, 'invalid_product');
  }
  return {productId: id, billingPeriod: 'P1M', trialDays: 3, monthlyPriceCents: 499, currency: 'USD',
    basePlanId: provider === 'google' ? 'monthly' : null, offerId: provider === 'google' ? 'trial-3-days' : null};
}
function positiveInteger(value) {
  return typeof value === 'string' && /^[1-9]\d{0,5}$/.test(value) ? Number(value) : null;
}
export function allowanceConfiguration(env = process.env) {
  if (env.KORLIX_ESHA_AI_POLICY === ESHA_AI_ROLE_POLICY) {
    const trial = ESHA_APPROVED_ALLOWANCES.trial.deepConsultations;
    const monthly = ESHA_APPROVED_ALLOWANCES.monthly.deepConsultations;
    const configured = (env.KORLIX_ESHA_TRIAL_CONSULTATIONS === undefined || env.KORLIX_ESHA_TRIAL_CONSULTATIONS === String(trial)) &&
      (env.KORLIX_ESHA_MONTHLY_CONSULTATIONS === undefined || env.KORLIX_ESHA_MONTHLY_CONSULTATIONS === String(monthly));
    return {configured, trial: configured ? trial : null, monthly: configured ? monthly : null};
  }
  const trial = positiveInteger(env.KORLIX_ESHA_TRIAL_CONSULTATIONS);
  const monthly = positiveInteger(env.KORLIX_ESHA_MONTHLY_CONSULTATIONS);
  const configured = trial !== null && monthly !== null;
  return {configured, trial: configured ? trial : null, monthly: configured ? monthly : null};
}
function modelBudgetConfiguration(env, model, reasoningEffort, modelApproved) {
  const maxInputTokens = positiveInteger(env.KORLIX_ESHA_MAX_INPUT_TOKENS);
  const maxOutputTokens = positiveInteger(env.KORLIX_ESHA_MAX_OUTPUT_TOKENS);
  const trialAttempts = positiveInteger(env.KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS);
  const monthlyAttempts = positiveInteger(env.KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS);
  const configured = modelApproved && maxInputTokens !== null && maxInputTokens <= 922000 &&
    maxOutputTokens !== null && maxOutputTokens >= (model === astra.TEXT_MODEL ? astra.TEXT_OUTPUT_TOKENS : 256) &&
    maxOutputTokens <= (model === astra.TEXT_MODEL ? 131072 : 128000) && trialAttempts !== null && monthlyAttempts !== null;
  return {configured, model, reasoningEffort, api: 'responses', transport: 'https',
    maxInputTokens: configured ? maxInputTokens : null,
    maxOutputTokens: configured ? maxOutputTokens : null,
    trialAttempts: configured ? trialAttempts : null, monthlyAttempts: configured ? monthlyAttempts : null};
}
export function nativeAiConfiguration(env = process.env, {role} = {}) {
  if (env.KORLIX_ESHA_AI_POLICY !== undefined || role !== undefined) {
    const selectedRole = role ?? 'conversation';
    const target = env.KORLIX_ESHA_AI_POLICY === ESHA_AI_ROLE_POLICY && typeof selectedRole === 'string' && Object.hasOwn(ESHA_AI_ROLES, selectedRole)
      ? ESHA_AI_ROLES[selectedRole] : null;
    // Single-model overrides cannot silently reinterpret a two-role policy.
    const conflictingOverride = env.KORLIX_ESHA_TEXT_MODEL !== undefined || env.KORLIX_ESHA_REASONING_EFFORT !== undefined;
    return {policy: env.KORLIX_ESHA_AI_POLICY ?? null, role: selectedRole,
      requestedModel: target?.requestedModel ?? null, resolved: !!target?.model,
      ...modelBudgetConfiguration(env, target?.model ?? null, target?.reasoningEffort ?? null,
        target?.api === 'responses' && !conflictingOverride),
      api: target?.api ?? null, transport: target?.transport ?? null};
  }
  // Preserve the legacy configuration contract. Luna is historical compatibility,
  // not the owner's new conversational choice; no shared Astra policy is changed.
  const model = env.KORLIX_ESHA_TEXT_MODEL ?? astra.TEXT_MODEL;
  const reasoningEffort = env.KORLIX_ESHA_REASONING_EFFORT ?? (model === astra.TEXT_MODEL ? astra.TEXT_EFFORT : null);
  const modelApproved = model === astra.TEXT_MODEL && reasoningEffort === astra.TEXT_EFFORT ||
    model === 'gpt-6-luna' && reasoningEffort === 'low' && env.KORLIX_ESHA_ECONOMICAL_AI_APPROVED === 'true';
  return modelBudgetConfiguration(env, model, reasoningEffort, modelApproved);
}
export function nativeAiConfigured(env = process.env, options) {
  return allowanceConfiguration(env).configured && nativeAiConfiguration(env, options).configured && env.KORLIX_ESHA_NATIVE_AI_ENABLED === 'true';
}
export function publicCatalog(provider, env = process.env, storeReady = false) {
  const product = productFor(provider);
  const allowance = allowanceConfiguration(env);
  const allowanceConfigured = allowance.configured;
  const consultationEnabled = nativeAiConfigured(env);
  const storeConfigurationVerified = env[`KORLIX_ESHA_${provider.toUpperCase()}_PRODUCTS_READY`] === 'true';
  const purchasesEnabled = env.KORLIX_ESHA_BILLING_ENABLED === 'true' && storeConfigurationVerified &&
    !!storeReady && consultationEnabled;
  return {catalogVersion: ESHA_CATALOG_VERSION, provider, bundleId: ESHA_BUNDLE, product,
    purchasesEnabled, storeConfigurationVerified, allowanceConfigured,
    consultationLimits: {trial: allowance.trial, monthly: allowance.monthly}, consultationEnabled,
    state: purchasesEnabled ? 'ready' : 'planned'};
}
function testAccess(userId, test, env) {
  const allowed = new Set(String(env.KORLIX_ESHA_TEST_USER_IDS || '').toLowerCase().split(/[,;\s]+/));
  if (test && !allowed.has(userId.toLowerCase())) fail('Store testing is not enabled for this Esha account.', 403, 'test_account_required');
}
function timestamp(value, label) {
  const number = typeof value === 'number' ? value : Date.parse(value);
  if (!Number.isFinite(number) || number <= 0) fail(`The store returned an invalid ${label}.`, 502, 'invalid_store_response');
  return number;
}
const iso = number => new Date(number).toISOString();

// Only a verified JWS + freshly fetched subscription status may call this function.
export function appleFacts(value, userId, env = process.env, now = Date.now(), {status = 1, renewal} = {}) {
  productFor('apple', value?.productId);
  if (!UUID.test(userId || '') || value.bundleId !== ESHA_BUNDLE ||
      String(value.appAccountToken || '').toLowerCase() !== userId.toLowerCase() ||
      !/^\d{5,40}$/.test(String(value.transactionId || '')) ||
      !/^\d{5,40}$/.test(String(value.originalTransactionId || '')) || value.quantity !== 1 ||
      value.type !== 'Auto-Renewable Subscription' || value.inAppOwnershipType !== 'PURCHASED' ||
      !['Production', 'Sandbox'].includes(value.environment) || ![1, 2, 3, 4, 5].includes(status)) {
    fail('This App Store subscription does not belong to this Esha account.', 409, 'purchase_ownership_mismatch');
  }
  testAccess(userId, value.environment === 'Sandbox', env);
  const purchase = timestamp(value.purchaseDate, 'purchase date');
  const signed = timestamp(value.signedDate, 'signature date');
  const originalExpiry = timestamp(value.expiresDate, 'renewal date');
  if (signed > now + 300000 || purchase > now + 300000 || originalExpiry < purchase) {
    fail('The store returned inconsistent subscription dates.', 502, 'invalid_store_response');
  }
  if (value.offerType === 1 && !['FREE_TRIAL', 'PAY_AS_YOU_GO', 'PAY_UP_FRONT'].includes(value.offerDiscountType)) {
    fail('The store could not confirm the current trial phase.', 503, 'trial_phase_unverified');
  }
  let expiry = originalExpiry;
  if (status === 4) {
    if (!renewal || renewal.originalTransactionId !== value.originalTransactionId ||
        renewal.productId !== value.productId || renewal.environment !== value.environment) {
      fail('The store could not confirm the grace period.', 502, 'invalid_store_response');
    }
    expiry = Math.max(expiry, timestamp(renewal.gracePeriodExpiresDate, 'grace period'));
  }
  const revoked = !!value.revocationDate || value.isUpgraded === true || status === 5;
  return {provider: 'apple', purchase_key: digest(`esha:apple:${value.environment}:${value.originalTransactionId}`),
    provider_token: String(value.originalTransactionId), product_id: value.productId,
    period_key: digest(`esha:apple:${value.environment}:${value.transactionId}`), period_started_at: iso(purchase),
    active: !revoked && [1, 4].includes(status) && expiry > now, revoked,
    trial: value.offerType === 1 && value.offerDiscountType === 'FREE_TRIAL',
    auto_renewing: renewal?.autoRenewStatus === 1, expires_at: iso(expiry),
    test_purchase: value.environment === 'Sandbox', provider_updated_at: iso(signed), observed_at: iso(now),
    linked_purchase_key: null, pending: false};
}

// Google responses are fetched at the fixed Esha package URL by the provider.
export function googleFacts(value, userId, token, productId, env = process.env, now = Date.now()) {
  productFor('google', productId);
  if (value?.externalAccountIdentifiers?.obfuscatedExternalAccountId !== eshaAccountId(userId)) {
    fail('This Google Play subscription belongs to a different Esha account.', 409, 'purchase_ownership_mismatch');
  }
  const states = ['SUBSCRIPTION_STATE_PENDING', 'SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_PAUSED',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_ON_HOLD', 'SUBSCRIPTION_STATE_CANCELED',
    'SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'];
  if (!states.includes(value.subscriptionState)) fail('The store returned an unknown subscription state.', 502, 'invalid_store_response');
  const test = !!value.testPurchase;
  testAccess(userId, test, env);
  const lines = value.lineItems;
  if (!Array.isArray(lines) || lines.length !== 1 || lines[0].productId !== productId ||
      lines[0].offerDetails?.basePlanId !== 'monthly' || !lines[0].autoRenewingPlan ||
      (lines[0].offerDetails?.offerId && lines[0].offerDetails.offerId !== 'trial-3-days')) {
    fail('This purchase does not match the Esha monthly plan.', 409, 'invalid_product');
  }
  const line = lines[0], pending = value.subscriptionState === 'SUBSCRIPTION_STATE_PENDING';
  if (pending) return {pending: true, active: false, provider: 'google'};
  const expiry = timestamp(line.expiryTime, 'renewal date');
  const start = timestamp(value.startTime, 'purchase date');
  if (start > now + 300000 || expiry < start) fail('The store returned inconsistent subscription dates.', 502, 'invalid_store_response');
  const active = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_CANCELED', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD']
    .includes(value.subscriptionState) && expiry > now;
  if (active && !['ACKNOWLEDGEMENT_STATE_PENDING', 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(value.acknowledgementState)) {
    fail('The store has not completed this purchase.', 409, 'payment_pending');
  }
  const order = line.latestSuccessfulOrderId;
  if (active && (typeof order !== 'string' || order.length < 6 || order.length > 200)) {
    fail('The store has not confirmed this billing period.', 409, 'payment_pending');
  }
  const phase = line.offerPhase;
  const trial = phase != null && Object.hasOwn(phase, 'freeTrial');
  if (active && line.offerDetails?.offerId && !trial && !Object.hasOwn(phase || {}, 'basePrice')) {
    fail('The store could not confirm the current trial phase.', 503, 'trial_phase_unverified');
  }
  if (trial && line.offerDetails?.offerId !== 'trial-3-days') fail('This trial is not configured for Esha.', 409, 'invalid_product');
  const replacement = !!value.canceledStateContext?.replacementCancellation;
  return {provider: 'google', purchase_key: digest(`esha:google:${token}`), provider_token: token, product_id: productId,
    period_key: digest(`esha:google:order:${order || digest(token)}`), period_started_at: iso(start),
    active: active && !replacement, revoked: replacement, trial, auto_renewing: line.autoRenewingPlan.autoRenewEnabled === true,
    expires_at: iso(expiry), test_purchase: test, provider_updated_at: iso(now), observed_at: iso(now),
    linked_purchase_key: value.linkedPurchaseToken ? digest(`esha:google:${value.linkedPurchaseToken}`) : null,
    pending: false};
}
