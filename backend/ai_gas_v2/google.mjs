import {createHash, createHmac, timingSafeEqual} from 'node:crypto';
export const PACKAGE_NAME = 'com.korlixdeveloper.korlixai';
export const GOOGLE_BASE = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}`;
export class GasError extends Error {
  constructor(code, status = 503) { super(code); this.name = 'GasError'; this.code = code; this.status = status; }
}
export function userId(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value)) throw new GasError('GAS_AUTH_REQUIRED',401);
  return value.toLowerCase();
}
export function token(value) {
  if (typeof value !== 'string' || !/^[\x21-\x7e]{16,2048}$/.test(value)) throw new GasError('GAS_TOKEN_INVALID',400);
  return value;
}
export function productId(value) {
  if (typeof value !== 'string' || !/^[a-z][a-z0-9_.]{0,199}$/.test(value)) throw new GasError('GAS_PRODUCT_INVALID',400);
  return value;
}
export const tokenHash = value => createHash('sha256').update(token(value)).digest('hex');
export function createAccountBinding(key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) throw new GasError('GAS_BINDING_KEY_INVALID');
  const secret = Buffer.from(key);
  // Stable for the account lifetime. Preserve this key independently of token-key rotation.
  return id => 'kg2_' + createHmac('sha256',secret).update(PACKAGE_NAME+'\0'+userId(id)).digest('base64url');
}
function equal(a,b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const x=Buffer.from(a), y=Buffer.from(b);
  return x.length===y.length && timingSafeEqual(x,y);
}
export function parseGooglePurchase(body, {expectedProductId, expectedAccountId, allowTestPurchases = false, now = Date.now()} = {}) {
  if (!Number.isFinite(now) || typeof allowTestPurchases !== 'boolean' || typeof expectedAccountId !== 'string' || !/^kg2_[A-Za-z0-9_-]{43}$/.test(expectedAccountId)) throw new GasError('GAS_VERIFIER_CONFIG_INVALID');
  productId(expectedProductId);
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new GasError('GOOGLE_RESPONSE_INVALID');
  if (!equal(body.obfuscatedExternalAccountId,expectedAccountId)) throw new GasError('GAS_ACCOUNT_MISMATCH',403);
  const items=body.productLineItem;
  if (!Array.isArray(items) || items.length!==1 || items[0]?.productId!==expectedProductId) throw new GasError('GAS_PRODUCT_MISMATCH',400);
  const state=body.purchaseStateContext?.purchaseState;
  if (!['PURCHASED','PENDING','CANCELLED'].includes(state)) throw new GasError('GOOGLE_STATE_INVALID');
  const isTest=Object.hasOwn(body,'testPurchaseContext');
  if (isTest && body.testPurchaseContext?.fopType!=='TEST') throw new GasError('GOOGLE_TEST_CONTEXT_INVALID');
  if (isTest && !allowTestPurchases) throw new GasError('GAS_TEST_PURCHASE_REJECTED',403);
  // Google can omit completed-purchase fields while payment is still pending.
  // The account and product are checked above; neither state below can grant time.
  if (state==='PENDING') return Object.freeze({state:'PENDING',isTest,productId:expectedProductId});
  if (state==='CANCELLED') return Object.freeze({state:'REVOKED',isTest,productId:expectedProductId});
  const offer=items[0].productOfferDetails;
  if (!offer || offer.quantity!==1 || !Number.isInteger(offer.refundableQuantity) || ![0,1].includes(offer.refundableQuantity) || Object.hasOwn(offer,'rentOfferDetails') || Object.hasOwn(offer,'preorderOfferDetails')) throw new GasError('GAS_OFFER_UNSUPPORTED',400);
  const consumption=offer.consumptionState;
  if (!['CONSUMPTION_STATE_YET_TO_BE_CONSUMED','CONSUMPTION_STATE_CONSUMED'].includes(consumption)) throw new GasError('GOOGLE_CONSUMPTION_INVALID');
  if (!['ACKNOWLEDGEMENT_STATE_PENDING','ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(body.acknowledgementState)) throw new GasError('GOOGLE_ACK_INVALID');
  const consumed=consumption==='CONSUMPTION_STATE_CONSUMED';
  if (offer.refundableQuantity===0) return Object.freeze({state:'REVOKED',isTest,consumed,productId:expectedProductId});
  const time=body.purchaseCompletionTime;
  const epoch=typeof time==='string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(time) ? Date.parse(time) : NaN;
  if (!Number.isFinite(epoch) || epoch>now+300000 || epoch<0) throw new GasError('GOOGLE_PURCHASE_TIME_INVALID');
  return Object.freeze({state:'PURCHASED',productId:expectedProductId,isTest,consumed,purchasedAt:new Date(epoch).toISOString()});
}
async function readJson(response) {
  // Never forward provider response text: it can contain purchase material.
  const reader=response.body?.getReader();
  if (!reader) throw new GasError('GOOGLE_RESPONSE_INVALID');
  const parts=[]; let size=0;
  try {
    for (;;) {
      const {done,value}=await reader.read(); if (done) break;
      size+=value.byteLength;
      if(size>65536) {await reader.cancel(); throw new GasError('GOOGLE_RESPONSE_INVALID');}
      parts.push(value);
    }
    return JSON.parse(Buffer.concat(parts).toString('utf8'));
  } catch {throw new GasError('GOOGLE_RESPONSE_INVALID');}
  finally {reader.releaseLock();}
}
export function createGoogleClient({getAccessToken, accountBindingKey, fetchImpl=globalThis.fetch, allowTestPurchases=false, now=Date.now}={}) {
  if (typeof getAccessToken!=='function' || typeof fetchImpl!=='function' || typeof now!=='function' || typeof allowTestPurchases!=='boolean') throw new GasError('GOOGLE_ADAPTER_REQUIRED');
  const accountId=createAccountBinding(accountBindingKey);
  async function request(path, method) {
    try {
      const access=await getAccessToken();
      if (typeof access!=='string' || !/^[\x21-\x7e]{16,8192}$/.test(access)) throw new GasError('GOOGLE_AUTH_UNAVAILABLE');
      const response=await fetchImpl(GOOGLE_BASE+path,{method,redirect:'error',headers:{Authorization:'Bearer '+access,Accept:'application/json'},signal:AbortSignal.timeout(15000)});
      if (!response.ok) {await response.body?.cancel(); throw new GasError(response.status===404?'GOOGLE_PURCHASE_NOT_FOUND':'GOOGLE_UNAVAILABLE',response.status===404?400:503);}
      if (method==='POST') {await response.body?.cancel(); return;}
      return await readJson(response);
    } catch (error) {throw error instanceof GasError?error:new GasError('GOOGLE_UNAVAILABLE');}
  }
  return Object.freeze({
    accountId,
    async verify({userId:id,productId:pid,purchaseToken}) {
      const expectedAccountId=accountId(id); productId(pid); token(purchaseToken);
      const body=await request('/purchases/productsv2/tokens/'+encodeURIComponent(purchaseToken),'GET');
      return parseGooglePurchase(body,{expectedProductId:pid,expectedAccountId,allowTestPurchases,now:now()});
    },
    async consume({productId:pid,purchaseToken}) {
      productId(pid); token(purchaseToken);
      await request('/purchases/products/'+encodeURIComponent(pid)+'/tokens/'+encodeURIComponent(purchaseToken)+':consume','POST');
    },
  });
}
