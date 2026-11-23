import {UUID} from '../web_billing/core.mjs';
import {PRODUCTS} from '../google_play/core.mjs';
import {createAccountRequestLimiter} from '../security/account_request_limiter.mjs';
import {APPLE_PRODUCTS, bindingHash} from './first_charge.mjs';
import {accountFirstCharge} from './check.mjs';

const CHECKOUTS = 'korlix_measurement_checkouts';
const DELIVERIES = 'korlix_first_payment_deliveries';
const INSTANCE = /^[a-f0-9]{32}$/;
export const EVENT = 'korlix_ai_first_paid_subscription';

async function query(operation) {
  const {data, error} = await (operation.abortSignal ? operation.abortSignal(AbortSignal.timeout(3000)) : operation);
  if (error) throw new Error('Measurement storage unavailable.');
  return data;
}

function streamConfig(env, store) {
  const platform = store === 'android' ? 'ANDROID' : 'IOS';
  const appId = env['KORLIX_GA4_' + platform + '_APP_ID'];
  const secret = env['KORLIX_GA4_' + platform + '_API_SECRET'];
  if (!secret || !new RegExp('^1:[0-9]+:' + store + ':[a-f0-9]+$').test(appId ?? '')) return null;
  return {appId, secret};
}

export function measurementMessage(instance, paidAt) {
  return {app_instance_id: instance, timestamp_micros: paidAt * 1000,
    consent: {ad_user_data: 'GRANTED', ad_personalization: 'DENIED'},
    events: [{name: EVENT}]};
}

async function sendToAnalytics({appId, secret}, message) {
  const url = new URL('https://www.google-analytics.com/mp/collect');
  url.searchParams.set('firebase_app_id', appId);
  url.searchParams.set('api_secret', secret);
  const response = await fetch(url, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10_000),
    headers: {'Content-Type': 'application/json'}, body: JSON.stringify(message)});
  if (!response.ok) throw new Error('Analytics delivery status unknown.');
}

const invalid = (code) => Object.assign(new Error('Invalid measurement request.'), {statusCode: code});
const validStore = store => store === 'ios' || store === 'android';
const validSku = (store, sku) => typeof sku === 'string' &&
  (store === 'ios' ? APPLE_PRODUCTS.includes(sku) : store === 'android' && Object.hasOwn(PRODUCTS, sku));

export function registerFirstPaymentDelivery(app, {database, requireUser, apple, play, env = process.env,
  resolve = accountFirstCharge, deliver = sendToAnalytics, autoStart = true, now = Date.now, log = console}) {
  const enabled = env.KORLIX_STORE_PAYMENT_DELIVERY_ENABLED === 'true';
  const limit = createAccountRequestLimiter({windowMs: 15 * 60_000, maxAttempts: 20});
  function post(path, action, {withdraw = false} = {}) {
    app.post('/api/billing/measurement/' + path, async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        const user = await requireUser(req);
        if (!UUID.test(user?.id ?? '') || user.is_anonymous || (!withdraw && !user.email_confirmed_at)) throw invalid(403);
        const body = req.body ?? {};
        if (!validStore(body.store)) throw invalid(400);
        if (!withdraw) {
          if (!enabled || !streamConfig(env, body.store)) throw invalid(503);
          limit(user.id);
        }
        res.json(await action(user.id, body));
      } catch (error) {
        const code = [400,401,403,404,409,429].includes(error.statusCode) ? error.statusCode : 503;
        if (error.retryAfter) res.set('Retry-After', String(error.retryAfter));
        res.status(code).json({error: 'Subscription measurement request could not be completed.'});
      }
    });
  }

  post('checkout', async (userId, {store, sku, consent, instanceId}) => {
    if (consent !== true || !validSku(store, sku) || typeof instanceId !== 'string' || !INSTANCE.test(instanceId)) throw invalid(400);
    const row = await query(database.from(CHECKOUTS).insert({user_id:userId, store, sku, instance_id:instanceId}).select('id').single());
    return {checkoutId: row.id};
  });

  async function bind(userId, {store, sku, checkoutId, storeReference, environment}) {
    if (environment !== 'Production' || !validSku(store, sku)) throw invalid(409);
    if (!UUID.test(checkoutId ?? '') || typeof storeReference !== 'string' || storeReference.length > 4096 ||
        !(store === 'ios' ? /^\d{1,32}$/.test(storeReference) : storeReference.length >= 10 && !/\s/.test(storeReference))) throw invalid(400);
    const row = await query(database.from(CHECKOUTS).select('sku,binding_hash').eq('id', checkoutId)
      .eq('user_id', userId).eq('store', store).maybeSingle());
    if (!row || sku !== row.sku) throw invalid(404);
    const hash = bindingHash(storeReference);
    if (row.binding_hash) {
      if (row.binding_hash !== hash) throw invalid(409);
      return true;
    }
    const owned = store === 'ios'
      ? database.from('korlix_apple_transaction_bindings').select('user_id')
        .eq('original_transaction_id', storeReference).eq('environment', 'Production')
      : database.from('korlix_play_purchases').select('user_id')
        .eq('token_hash', hash).eq('test_purchase', false).eq('product_id', row.sku);
    if (!await query(owned.eq('user_id', userId).maybeSingle())) throw invalid(409);
    const saved = await query(database.from(CHECKOUTS).update({binding_hash: hash})
      .eq('id', checkoutId).eq('user_id', userId).is('binding_hash', null).select('id').maybeSingle());
    if (!saved) throw invalid(409);
    return true;
  }

  // Called only after the normal store verifier has authenticated the receipt and committed ownership.
  async function bindVerified(userId, purchase) {
    if (!enabled || !UUID.test(purchase.checkoutId ?? '')) return false;
    try { return await bind(userId, purchase); } catch { return false; }
  }

  post('withdraw', async (userId, {store}) => {
    await query(database.from(CHECKOUTS).delete().eq('user_id', userId).eq('store', store));
    return {withdrawn:true};
  }, {withdraw:true});

  async function processRow(row) {
    const config = streamConfig(env, row.store);
    if (!config) return;
    const first = await resolve(database, row.user_id, {apple, play}, true);
    if (!first) return;
    const source = first.source;
    if (first.refunded || source.hash !== row.binding_hash || first.store !== row.store || source.sku !== row.sku ||
        source.startedAt < Date.parse(row.granted_at) || first.time < now() - 71 * 3600_000) {
      await query(database.from(CHECKOUTS).delete().eq('id', row.id));
      return;
    }
    if (first.time > now()) return;
    const reservations = await query(database.rpc('korlix_reserve_first_payment', {p_checkout:row.id, p_store:first.store,
      p_sku:source.sku, p_hash:source.hash, p_started:new Date(source.startedAt).toISOString(), p_paid:new Date(first.time).toISOString()}));
    if (!reservations.length) return;
    const {receipt_id, instance_id} = reservations[0];
    // An interrupted or ambiguous send must never become a duplicate first payment.
    let state = 'accepted';
    try { await deliver(config, measurementMessage(instance_id, first.time)); }
    catch { state = 'uncertain'; }
    await query(database.from(DELIVERIES).update({state, updated_at:new Date(now()).toISOString()}).eq('receipt_id', receipt_id));
  }

  let running = false;
  async function run() {
    if (!enabled || running) return;
    running = true;
    try {
      const rows = await query(database.rpc('korlix_measurement_due'));
      for (const row of rows) {
        try { await processRow(row); }
        catch { log.warn('[first-payment] Verification or storage unavailable; check the worker and store services.'); }
      }
    } catch { log.warn('[first-payment] Measurement queue unavailable.'); }
    finally { running = false; }
  }
  const timer = enabled && autoStart ? setInterval(run, 60_000) : null;
  timer?.unref();
  return {run, bindVerified, stop: () => clearInterval(timer)};
}
