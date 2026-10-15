import {BillingError, fail, UUID} from '../web_billing/core.mjs';
import {PACKAGE, PRODUCTS, VERSION, accountId, observation, playStore, purchaseToken, tokenHash} from './core.mjs';
import {googlePlay} from './provider.mjs';

export function registerGooglePlay(app, {database, requireUser, loadProfile, environment = process.env,
  store = playStore(database), provider = googlePlay(environment), autoStart = true, now = Date.now} = {}) {
  const root = '/api/billing/google', rates = new Map();
  const testUsers = new Set((environment.KORLIX_GOOGLE_PLAY_TEST_USER_IDS || '').split(',').map(x => x.trim().toLowerCase()).filter(x => UUID.test(x)));
  let catalogCheck = {checkedAt: null, ready: false};
  async function checkCatalog() {
    if (!provider.configured) return catalogCheck;
    try {
      await Promise.all(Object.keys(PRODUCTS).map(product => provider.catalog(product)));
      catalogCheck = {checkedAt: new Date(now()).toISOString(), ready: true};
    } catch {
      // Publish only readiness. Provider errors can contain credential details.
      catalogCheck = {checkedAt: new Date(now()).toISOString(), ready: false};
    }
    return catalogCheck;
  }
  function rate(id, action) {
    const key = `${id}:${action}`, previous = rates.get(key), time = now();
    if (!previous || previous.until < time) rates.set(key, {until: time + 60000, count: 1});
    else if (++previous.count > 12) fail('Too many subscription requests. Please wait a minute.', 429);
    if (rates.size > 10000) for (const [k, v] of rates) if (v.until < time) rates.delete(k);
  }
  function wrap(fn) {
    return async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        let user; try { user = await requireUser(req); } catch { fail('Sign in to manage your subscription.', 401); }
        if (!UUID.test(user?.id || '') || user.is_anonymous || !user.email_confirmed_at) fail('Verify your email before subscribing.', 403);
        await loadProfile?.(user);
        rate(user.id, req.path);
        await fn(req, res, user);
      } catch (e) { res.status(e instanceof BillingError ? e.status : 503).json({error: e instanceof BillingError ? e.message : 'Subscription verification is unavailable. Please retry.'}); }
    };
  }
  async function sync(userId, token = null, expectedProduct = null) {
    const lease = await store.command(userId, 'claim');
    let success = false, latest;
    try {
      const purchases = token ? [{purchase_token: token, product_id: expectedProduct}] : lease.purchases;
      for (const purchase of purchases) {
        const data = await provider.subscription(purchase.purchase_token);
        const facts = observation(data, {userId, token: purchase.purchase_token,
          expectedProduct: token ? expectedProduct : null, allowTest: testUsers.has(userId), now: now()});
        const receipt = {sync_token: lease.sync_token, token_hash: facts.token_hash};
        const applied = await store.command(userId, 'apply', {...facts, ...receipt});
        if (applied.active && !facts.acknowledged) {
          await provider.acknowledge(purchase.purchase_token, facts.product_id);
          await store.command(userId, 'acknowledged', receipt);
          facts.acknowledged = true;
        }
        latest = {verified: true, tier: applied.tier, active: applied.active, productId: facts.product_id,
          status: facts.state, expiresAt: facts.expires_at, environment: facts.test_purchase ? 'Test' : 'Production',
          completePurchase: facts.acknowledged};
      }
      success = true;
      return latest;
    } finally { await store.command(userId, 'release', {sync_token: lease.sync_token, success}).catch(() => {}); }
  }
  function publicStatus(snapshot, refreshWarning = null) {
    return {version: VERSION, tier: snapshot.tier, entitlement: snapshot.entitlement,
      billingEnabled: provider.ready, canPurchase: provider.ready && snapshot.canPurchase,
      webSubscriptionActive: snapshot.webSubscriptionActive,
      otherStoreSubscriptionActive: snapshot.otherStoreSubscriptionActive, refreshWarning};
  }
  app.get(root + '/health', (_req, res) => res.set('Cache-Control', 'no-store').json({version: VERSION,
    packageName: PACKAGE, products: PRODUCTS, configured: provider.configured,
    billingEnabled: provider.ready, notificationsConfigured: provider.notificationsConfigured,
    catalogCheck}));
  app.get(root + '/status', wrap(async (req, res, user) => {
    let snapshot = await store.command(user.id, 'snapshot'), warning = null;
    if (req.query?.refresh === '1' && snapshot.account_id && provider.configured) {
      try { await sync(user.id); } catch { warning = 'Google Play could not be refreshed. Please retry before changing plans.'; }
      snapshot = await store.command(user.id, 'snapshot');
    }
    res.json(publicStatus(snapshot, warning));
  }));
  app.post(root + '/prepare', wrap(async (req, res, user) => {
    if (!provider.ready) fail('Google Play billing is being set up. Please try again later.', 503);
    if (!Object.hasOwn(PRODUCTS, req.body?.productId || '')) fail('Choose an available subscription.');
    // Prove the configured server identity can read this active Play product
    // before handing the customer to the store's charge confirmation sheet.
    await provider.catalog(req.body.productId);
    const previous = await store.command(user.id, 'snapshot');
    if (previous.account_id) await sync(user.id);
    const snapshot = await store.command(user.id, 'prepare', {account_id: accountId(user.id)});
    res.json({...publicStatus(snapshot), accountId: snapshot.account_id});
  }));
  app.post(root + '/verify', wrap(async (req, res, user) => {
    if (!provider.configured) fail('Google Play verification is unavailable. Please try Restore Purchases later.', 503);
    const product = req.body?.productId;
    if (!Object.hasOwn(PRODUCTS, product || '') || req.body?.source !== 'google_play') fail('Unsupported Google Play purchase.');
    res.json(await sync(user.id, purchaseToken(req.body?.verificationData), product));
  }));
  app.post(root + '/notifications', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const event = await provider.notification(req);
      if (event.testNotification) return res.json({received: true});
      const token = event.subscriptionNotification?.purchaseToken || event.voidedPurchaseNotification?.purchaseToken;
      if (!token) return res.json({received: true});
      purchaseToken(token);
      let owner = await store.command(null, 'lookup', {token_hash: tokenHash(token)});
      if (!owner) {
        // New purchases may notify before the app receives the purchase. Only
        // Google's authenticated API result can identify their prepared owner.
        const data = await provider.subscription(token);
        owner = await store.command(null, 'lookup', {account_id: data.externalAccountIdentifiers?.obfuscatedExternalAccountId || ''});
      }
      if (owner) await sync(owner.user_id, token);
      res.json({received: true});
    } catch (e) {
      const status = e instanceof BillingError && [400,401,403].includes(e.status) ? e.status : 503;
      res.status(status).json({error: status === 503 ? 'Subscription update could not be reconciled. Please retry.' : 'Invalid subscription notification.'});
    }
  });
  let timer, running = false;
  async function tick() {
    if (running || !provider.configured) return;
    running = true;
    try {
      if (!catalogCheck.checkedAt || now() - Date.parse(catalogCheck.checkedAt) >= 300000) await checkCatalog();
      for (const row of await store.command(null, 'due')) await sync(row.user_id).catch(() => {});
    }
    catch { /* Notification delivery and subsequent reconciliation retry. */ }
    finally { running = false; }
  }
  if (autoStart && provider.configured) { void tick(); timer = setInterval(tick, 60000); timer.unref?.(); }
  return {sync, tick, checkCatalog, stop: () => clearInterval(timer)};
}
