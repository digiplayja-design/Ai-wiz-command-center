import {createHash} from 'node:crypto';
import {fail} from '../../web_billing/core.mjs';

export const BRAIN_BUNDLE = 'com.korlix.brain';
export const BRAIN_APPLE_ID = 6829319523;
export const BRAIN_CATALOG = Object.freeze([
  {key:'monthly', name:'Brain+Voice Monthly', kind:'subscription', seconds:3600, usdCents:3499,
    apple:'com.korlix.brain.monthly', google:'korlix_brain_monthly'},
  ...[[1,3000],[2,5500],[3,8000]].map(([hours,usdCents]) => ({
    key:`gas_${hours}h`, name:`AI GAS · ${hours * 60} minutes`, kind:'consumable', seconds:hours*3600, usdCents,
    apple:`com.korlix.brain.ai_gas.${hours}h`, google:`korlix_brain_ai_gas_${hours}h`,
  })),
].map(Object.freeze));
export const brainAccountId = id => createHash('sha256').update(`korlix:brain:google:${id.toLowerCase()}`).digest('hex');
export const digest = value => createHash('sha256').update(value).digest('hex');
export function productFor(provider,id) {
  const item = ['apple','google'].includes(provider) && BRAIN_CATALOG.find(p => p[provider] === id);
  if (!item) fail('Choose a Brain+Voice plan or AI GAS package.',400);
  return item;
}
function allowTest(userId,test,env) {
  const allowed = new Set(`${env.APPLE_SANDBOX_ALLOWED_USER_IDS||''},${env.KORLIX_GOOGLE_PLAY_TEST_USER_IDS||''}`.toLowerCase().split(/[,;\s]+/));
  if(test && !allowed.has(userId.toLowerCase())) fail('Store testing is not enabled for this KORLIX account.',403);
}
export function appleFacts(value,userId,env=process.env,now=Date.now()) {
  const item=productFor('apple',value?.productId);
  if(value.bundleId!==BRAIN_BUNDLE || String(value.appAccountToken||'').toLowerCase()!==userId.toLowerCase() ||
    !/^\d{5,40}$/.test(String(value.transactionId||'')) || !/^\d{5,40}$/.test(String(value.originalTransactionId||'')) ||
    !['Production','Sandbox'].includes(value.environment) || value.quantity!==1 ||
    value.type!==(item.kind==='subscription'?'Auto-Renewable Subscription':'Consumable')) fail('This App Store purchase does not belong to this Brain+Voice account.',409);
  allowTest(userId,value.environment==='Sandbox',env);
  const revoked=!!value.revocationDate || value.isUpgraded===true;
  const expires=item.kind==='subscription'?Number(value.expiresDate):null;
  if(item.kind==='subscription' && (!Number.isFinite(expires)||expires<=0)) fail('App Store returned an invalid renewal date.',502);
  const active=!revoked && (expires===null || expires>now);
  return {provider:'apple',purchase_key:digest(`apple:${value.environment}:${value.originalTransactionId}`),
    provider_token:String(value.originalTransactionId), product_id:value.productId, kind:item.kind,
    grant_key:`apple:${value.environment}:${value.transactionId}`, seconds:item.seconds,
    active, revoked, expires_at:expires?new Date(expires).toISOString():null,
    test_purchase:value.environment==='Sandbox', observed_at:new Date(now).toISOString()};
}
export function googleFacts(value,userId,token,productId,env=process.env,now=Date.now()) {
  const item=productFor('google',productId);
  const account=item.kind==='subscription'?value?.externalAccountIdentifiers?.obfuscatedExternalAccountId:value?.obfuscatedExternalAccountId;
  if(account!==brainAccountId(userId)) fail('This Google Play purchase belongs to a different KORLIX account.',409);
  const test=!!value.testPurchase || !!value.testPurchaseContext;
  allowTest(userId,test,env);
  let active,revoked=false,expires=null,order,complete=false;
  if(item.kind==='subscription') {
    const lines=value.lineItems;
    if(!Array.isArray(lines)||lines.length!==1||lines[0].productId!==productId||lines[0].offerDetails?.basePlanId!=='monthly'||!lines[0].autoRenewingPlan) fail('This is not the Brain+Voice monthly plan.',409);
    expires=Date.parse(lines[0].expiryTime);
    if(!Number.isFinite(expires)) fail('Google Play returned an invalid renewal date.',502);
    active=['SUBSCRIPTION_STATE_ACTIVE','SUBSCRIPTION_STATE_CANCELED','SUBSCRIPTION_STATE_IN_GRACE_PERIOD'].includes(value.subscriptionState)&&expires>now;
    // Grace preserves the existing allowance; it does not mint a new monthly grant.
    order=lines[0].latestSuccessfulOrderId;
    if(!order && active) fail('Google Play has not confirmed the billing period.',409);
    complete=['ACKNOWLEDGEMENT_STATE_PENDING','ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(value.acknowledgementState);
  } else {
    const lines=value.productLineItem;
    if(!Array.isArray(lines)||lines.length!==1||lines[0].productId!==productId||lines[0].productOfferDetails?.quantity!==1) fail('This purchase does not match an AI GAS package.',409);
    const state=value.purchaseStateContext?.purchaseState;
    if(!['PURCHASED','CANCELLED','PENDING'].includes(state)) fail('Google Play returned an unknown purchase state.',502);
    revoked=state==='CANCELLED'||lines[0].productOfferDetails.refundableQuantity===0;
    active=state==='PURCHASED'&&!revoked;order=value.orderId;
    complete=active;
  }
  if(active&&!complete) fail('The store has not completed this purchase.',409);
  return {provider:'google',purchase_key:digest(`google:${token}`),provider_token:token,product_id:productId,kind:item.kind,
    grant_key:`google:${item.kind==='subscription'?order||digest(token):digest(token)}`,seconds:item.seconds,
    active,revoked,pending:value.subscriptionState==='SUBSCRIPTION_STATE_PENDING'||value.purchaseStateContext?.purchaseState==='PENDING',
    expires_at:expires?new Date(expires).toISOString():null,test_purchase:test,
    observed_at:new Date(now).toISOString()};
}
