import {ESHA_BUNDLE, ESHA_PRODUCT, UUID, EshaBillingError, allowanceConfiguration, nativeAiConfiguration, nativeAiConfigured,
  publicCatalog, productFor, eshaAccountId, digest, fail} from './catalog.mjs';
import {eshaProviders} from './providers.mjs';
import {loadEshaCatalog, consultationInput, consultationPrompt, consultationResult, ESHA_RESULT_FORMAT} from './consultation.mjs';

function statusCode(error) {
  const value = error?.statusCode ?? error?.status;
  return Number.isInteger(value) && value >= 400 && value < 600 ? value : 503;
}
export function createEshaBilling({database, requireUser, environment = process.env,
  provider = eshaProviders(environment), store, generate, catalog, autoStart = true} = {}) {
  let serverCatalog = catalog;
  if (!serverCatalog) { try { serverCatalog = loadEshaCatalog(); } catch { /* Fail closed in catalog and AI readiness. */ } }
  const storageReady = !!(store || database);
  const aiReady = () => nativeAiConfigured(environment) && !!environment.OPENAI_API_KEY &&
    typeof generate === 'function' && storageReady && !!serverCatalog;
  const call = store || async function(actor, action, data = {}) {
    if (!database) fail('Esha membership storage is temporarily unavailable.', 503, 'storage_unavailable');
    const result = await database.rpc('korlix_esha_billing_command', {p_actor: actor || null, p_action: action, p: data});
    if (result.error) {
      const known = /ESHA(\d{3}):([a-z_]+):([^\n]+)/.exec(result.error.message || '');
      fail(known ? known[3] : 'Esha membership storage is temporarily unavailable.', known ? Number(known[1]) : 503,
        known ? known[2] : 'storage_unavailable');
    }
    return result.data;
  };
  function catalogFor(providerName) {
    const result = publicCatalog(providerName, environment, provider.ready(providerName));
    result.consultationEnabled = aiReady();
    result.purchasesEnabled = result.purchasesEnabled && aiReady();
    result.state = result.purchasesEnabled ? 'ready' : 'planned';
    return result;
  }
  async function snapshot(userId, providerName, warning = null) {
    const result = await call(userId, 'snapshot');
    const configured = allowanceConfiguration(environment).configured;
    const allowance = {...result.allowance, configured: configured && result.allowance.configured};
    if (!configured) { allowance.limit = null; allowance.remaining = null; }
    return {...catalogFor(providerName), membership: result.membership, allowance, warning};
  }
  async function sync(userId, details, {voidedOrderId} = {}) {
    if (typeof details.productId !== 'string') fail('Choose the Esha monthly membership.', 400, 'invalid_product');
    productFor(details.provider, details.productId);
    let facts = await provider.verify(details.provider, {userId, productId: details.productId,
      purchaseId: details.purchaseId, purchaseToken: details.purchaseToken});
    if (facts.pending) fail('The store is still confirming this purchase. Restore again shortly.', 409, 'payment_pending');
    if (voidedOrderId && facts.provider === 'google') {
      await provider.confirmVoided(facts.provider_token, voidedOrderId);
      await call(null, 'record_void', {purchase_key: facts.purchase_key, period_key: digest(`esha:google:order:${voidedOrderId}`)});
      // Refunds of an older order do not revoke a separate, later paid renewal.
      if (facts.period_key === digest(`esha:google:order:${voidedOrderId}`)) facts = {...facts, active: false, revoked: true, voided: true};
    }
    const config = allowanceConfiguration(environment);
    const applied = await call(userId, 'apply', {...facts, allowance: config.configured ? (facts.trial ? config.trial : config.monthly) : null});
    // Persist entitlement idempotently before acknowledging with Google or finishing in native StoreKit.
    await provider.finish({...facts, active: facts.active && applied.membership.active});
    const status = await snapshot(userId, details.provider);
    return {verified: true, completePurchase: true, active: status.membership.active, status};
  }
  async function refresh(userId) {
    const purchases = await call(userId, 'purchases');
    let warning = null;
    const current = ['apple', 'google'].flatMap(providerName => purchases.filter(row => row.provider === providerName &&
      Date.parse(row.expires_at) > Date.now() - 60 * 86400000).sort((a, b) => Date.parse(b.expires_at) - Date.parse(a.expires_at)).slice(0, 2));
    await Promise.all(current.map(async row => {
      try { await sync(userId, {provider: row.provider, productId: row.product_id,
        purchaseId: row.provider_token, purchaseToken: row.provider_token}); }
      catch { warning = 'The store could not refresh every membership. Please restore again before purchasing.'; }
    }));
    return warning;
  }
  const rate = new Map();
  const protectedRoute = handler => async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = typeof requireUser === 'function' ? await requireUser(req) : null;
      if (!UUID.test(user?.id || '')) fail('Sign in to your Korlix account.', 401, 'authentication_required');
      if (!user.email_confirmed_at) fail('Verify your Korlix email before using Esha membership.', 403, 'email_confirmation_required');
      const now = Date.now(), previous = rate.get(user.id);
      if (previous && now < previous.until) { if (++previous.count > 30) fail('Wait a minute before retrying.', 429, 'rate_limited'); }
      else rate.set(user.id, {count: 1, until: now + 60000});
      if (rate.size > 10000) for (const [key, value] of rate) if (value.until < now) rate.delete(key);
      await handler(req, res, user);
    } catch (error) {
      const status = statusCode(error);
      res.status(status).json({error: error instanceof EshaBillingError || status < 500 ? error.message : 'Esha is temporarily unavailable. Please retry.',
        code: error instanceof EshaBillingError ? error.code : status === 401 ? 'authentication_required' : 'temporarily_unavailable'});
    }
  };
  async function consult(user, body) {
    if (!aiReady()) fail('Esha consultations are being configured. Your membership has not been charged for a consultation.', 503, 'native_ai_not_configured');
    const input = consultationInput(body);
    let balance = await call(user.id, 'snapshot');
    if (!balance.membership.verificationFresh) {
      await refresh(user.id);
      balance = await call(user.id, 'snapshot');
    }
    // The database reserves atomically and rejects stale, expired, revoked or exhausted membership.
    const reservation = await call(user.id, 'reserve', {request_id: input.requestId, input_hash: input.inputHash});
    if (reservation.replay) return {requestId: input.requestId, ...reservation.result,
      usage: (await call(user.id, 'snapshot')).allowance};
    const configuration = nativeAiConfiguration(environment);
    try {
      const prompt = consultationPrompt(input.data, serverCatalog);
      const response = await generate({...prompt, maxOutputTokens: configuration.maxOutputTokens,
        textFormat: ESHA_RESULT_FORMAT, signal: AbortSignal.timeout(180000)});
      const result = consultationResult(response, serverCatalog);
      const committed = await call(user.id, 'commit', {request_id: input.requestId, input_hash: input.inputHash, result});
      return {requestId: input.requestId, ...committed.result, usage: (await call(user.id, 'snapshot')).allowance};
    } catch (error) {
      // A commit may have succeeded before the network failed. release never reverses a committed request.
      await call(user.id, 'release', {request_id: input.requestId, input_hash: input.inputHash}).catch(() => {});
      if (error instanceof EshaBillingError) throw error;
      fail('Esha could not complete this consultation. Please try again.', 503, 'consultation_unavailable');
    }
  }
  function register(app) {
    app.get('/api/esha/catalog', (_req, res) => {
      res.set('Cache-Control', 'no-store');
      if (!serverCatalog) return res.status(503).json({error: 'Esha catalog is being configured.', code: 'catalog_unavailable'});
      res.json(serverCatalog);
    });
    app.get('/api/esha/billing/catalog', (req, res) => {
      res.set('Cache-Control', 'no-store');
      try { res.json(catalogFor(req.query.provider)); }
      catch (error) { res.status(statusCode(error)).json({error: error.message, code: error.code || 'invalid_request'}); }
    });
    app.get('/api/esha/billing/status', protectedRoute(async (req, res, user) => {
      productFor(req.query.provider);
      const warning = req.query.refresh === '1' ? await refresh(user.id) : null;
      res.json(await snapshot(user.id, req.query.provider, warning));
    }));
    app.post('/api/esha/billing/prepare', protectedRoute(async (req, res, user) => {
      const {provider: providerName, productId} = req.body || {};
      if (typeof productId !== 'string') fail('Choose the Esha monthly membership.', 400, 'invalid_product');
      const product = productFor(providerName, productId);
      if (!catalogFor(providerName).purchasesEnabled) fail('Esha store membership is being set up. Please try again later.', 503, 'purchases_disabled');
      const warning = await refresh(user.id);
      if (warning) fail(warning, 503, 'store_unavailable');
      if ((await call(user.id, 'snapshot')).membership.active) fail('Your Esha membership is already active. Open Manage subscription.', 409, 'membership_already_active');
      res.json({canPurchase: true, accountId: providerName === 'apple' ? user.id.toLowerCase() : eshaAccountId(user.id),
        bundleId: ESHA_BUNDLE, productId, basePlanId: product.basePlanId, offerId: product.offerId});
    }));
    app.post('/api/esha/billing/verify', protectedRoute(async (req, res, user) => {
      // Existing purchases remain restorable when new sales or AI are paused.
      res.json(await sync(user.id, req.body || {}));
    }));
    app.post('/api/esha/consult', protectedRoute(async (req, res, user) => res.json(await consult(user, req.body || {}))));
    app.post('/api/esha/billing/apple/notifications', async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        const decoded = await provider.appleNotification(req.body?.signedPayload);
        if (decoded.test) return res.json({accepted: true});
        if (!UUID.test(decoded.appAccountToken || '')) fail('Unknown Esha store account.', 409, 'unknown_store_account');
        await sync(decoded.appAccountToken.toLowerCase(), {provider: 'apple', productId: decoded.productId, purchaseId: decoded.transactionId});
        res.json({accepted: true});
      } catch (error) { res.status(statusCode(error)).json({error: 'Store notification could not be applied.', code: error.code || 'notification_unavailable'}); }
    });
    app.post('/api/esha/billing/google/notifications', async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        const message = await provider.googleNotification(req);
        if (message.testNotification) return res.json({accepted: true});
        const notification = message.subscriptionNotification || message.voidedPurchaseNotification;
        if (!notification?.purchaseToken) fail('Invalid Esha store notification.', 400, 'invalid_notification');
        const purchaseKey = digest(`esha:google:${notification.purchaseToken}`);
        if (message.voidedPurchaseNotification) {
          const orderId = message.voidedPurchaseNotification.orderId;
          await provider.confirmVoided(notification.purchaseToken, orderId);
          await call(null, 'record_void', {purchase_key: purchaseKey, period_key: digest(`esha:google:order:${orderId}`)});
        }
        const row = await call(null, 'lookup', {purchase_key: purchaseKey});
        // Unknown tokens must first be linked by the signed-in purchaser. Confirmed
        // refunds above are retained before ownership exists; events never choose an account.
        if (!row) return res.json({accepted: true, ownershipPending: true, refundRecorded: !!message.voidedPurchaseNotification});
        await sync(row.user_id, {provider: 'google', productId: ESHA_PRODUCT.google, purchaseToken: notification.purchaseToken});
        res.json({accepted: true});
      } catch (error) { res.status(statusCode(error)).json({error: 'Store notification could not be applied.', code: error.code || 'notification_unavailable'}); }
    });
  }
  let syncing = false;
  async function syncDue() {
    // Refund/expiry reconciliation continues when new sales are paused.
    if (syncing || !storageReady) return;
    syncing = true;
    try {
      for (const row of await call(null, 'due')) {
        try { await sync(row.user_id, {provider: row.provider, productId: row.product_id,
          purchaseId: row.provider_token, purchaseToken: row.provider_token}); }
        catch { await call(row.user_id, 'retry_later', {purchase_key: row.purchase_key}).catch(() => {}); }
      }
    } catch { /* No receipts or secrets are logged. A future worker/status refresh retries. */ }
    finally { syncing = false; }
  }
  const timer = autoStart ? setInterval(() => void syncDue(), 60000) : null;
  timer?.unref();
  return {register, catalog: catalogFor, snapshot, sync, refresh, consult, syncDue, stop() { clearInterval(timer); }};
}
