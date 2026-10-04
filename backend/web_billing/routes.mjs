import {BillingError, PLANS, PLAN_VERSION, UUID, billingStore, fail, stripeId} from './core.mjs';
import {webStripe} from './stripe.mjs';

export function registerWebBilling(app, {database, requireUser, loadProfile, environment = process.env,
  store = billingStore(database), provider = webStripe(environment), autoStart = true, now = Date.now} = {}) {
  const root = '/api/billing/web', rates = new Map();
  function rate(user, action, maximum = 12) {
    const key = `${user}:${action}`, previous = rates.get(key), current = now();
    if (!previous || previous.until < current) rates.set(key, {until: current + 60000, count: 1});
    else if (++previous.count > maximum) fail('Too many billing requests. Please wait a minute.', 429);
    if (rates.size > 10000) for (const [k, v] of rates) if (v.until < current) rates.delete(k);
  }
  async function userFor(req) {
    let user; try { user = await requireUser(req); } catch { fail('Sign in to manage your plan.', 401); }
    if (!UUID.test(user?.id || '') || user.is_anonymous || !user.email_confirmed_at) fail('Verify your email before purchasing.', 403);
    if (loadProfile) await loadProfile(user);
    const snapshot = await store.command(user.id, 'snapshot');
    if (snapshot.profile?.is_disabled) fail('This account is disabled.', 403);
    return {user, snapshot};
  }
  function wrap(fn) {
    return async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try { const context = await userFor(req); await fn(req, res, context); }
      catch (e) { res.status(e instanceof BillingError ? e.status : 503).json({error: e instanceof BillingError ? e.message : 'Billing could not be completed. Please retry.'}); }
    };
  }
  async function sync(userId, subscriptionId = null) {
    const m = await store.command(userId, 'claim');
    if (!m) return null;
    const receipt = {generation: m.generation, sync_token: m.sync_token};
    try {
      let sub = subscriptionId || m.subscription_id, session;
      if (!sub && m.state === 'checkout') {
        if (!m.checkout_id) {
          // Recover an uncertain create with the original immutable payload.
          // Never roll its idempotency key forward when the result is unknown.
          session = await provider.checkout(m);
          await store.command(userId, 'checkout_saved', {...receipt, checkout_id: session.id});
          m.checkout_id = session.id;
        } else session = await provider.session(m);
        if (session.subscription) sub = stripeId(session.subscription, 'sub');
      }
      if (!sub) return await store.command(userId, 'empty', {...receipt, checkout_status: session?.status});
      const observation = await provider.subscription(sub, m);
      return await store.command(userId, 'apply', {...observation, ...receipt});
    } catch (e) {
      await store.command(userId, 'release', receipt).catch(() => {});
      throw e;
    }
  }
  function publicStatus(snapshot) {
    const m = snapshot.membership, native = snapshot.native_tier !== 'basic', tier = snapshot.profile?.tier || 'basic';
    const running = !!m?.subscription_id && !['canceled', 'incomplete_expired'].includes(m.state);
    return {
      version: PLAN_VERSION, tier, nativeSubscription: native, checkoutEnabled: provider.ready,
      livePayments: provider.live, plans: Object.values(PLANS), enterprise: {name: 'Enterprise', contact: 'support@korlixdeveloper.com'},
      canPurchase: provider.ready && !native && tier === 'basic' && !running && !m?.held,
      canManage: provider.configured && !!m?.customer_id,
      membership: m ? {state: m.state, requestedTier: m.requested_tier, tier: m.billed_tier,
        paidTier: m.paid_tier, paidUntil: m.paid_until, renewalCanceled: m.cancel_at_period_end,
        held: m.held, updatedAt: m.observed_at, canResume: m.state === 'checkout'} : null,
    };
  }
  app.get(root + '/health', async (_req, res) => {
    res.set('Cache-Control', 'no-store').json({version: PLAN_VERSION, configured: provider.configured,
      checkoutEnabled: provider.ready, livePayments: provider.live, apiVersion: provider.apiVersion,
      connection: await provider.checkConnection(), prices: Object.values(PLANS).map(({tier, amount, currency, interval}) => ({tier, amount, currency, interval}))});
  });
  app.get(root + '/status', wrap(async (_req, res, {snapshot}) => res.json(publicStatus(snapshot))));
  app.post(root + '/refresh', wrap(async (_req, res, {user, snapshot}) => {
    rate(user.id, 'refresh', 12);
    if (snapshot.membership && provider.configured) await sync(user.id);
    res.json(publicStatus(await store.command(user.id, 'snapshot')));
  }));
  app.post(root + '/checkout', wrap(async (req, res, {user, snapshot}) => {
    rate(user.id, 'checkout', 6);
    const tier = req.body?.tier;
    if (!Object.hasOwn(PLANS, tier) || req.body?.version !== PLAN_VERSION || req.body?.acceptRecurring !== true) fail('Review and accept the current monthly price first.');
    if (!provider.ready) fail('New web subscriptions are temporarily unavailable.', 503);
    if (snapshot.membership) await sync(user.id);
    const m = await store.command(user.id, 'checkout_start', {tier, price_id: provider.prices[tier],
      livemode: provider.live, email: user.email});
    const s = m.checkout_id ? await provider.session(m) : await provider.checkout(m);
    if (!m.checkout_id) await store.command(user.id, 'checkout_saved', {generation: m.generation, checkout_id: s.id});
    if (s.status !== 'open' || !s.url) {
      await sync(user.id);
      fail('Checkout is no longer open. Refresh billing to see its result.', 409);
    }
    res.json({url: s.url});
  }));
  app.post(root + '/portal', wrap(async (_req, res, {user, snapshot}) => {
    rate(user.id, 'portal');
    if (!snapshot.membership?.customer_id) fail('No web billing account is available yet.', 409);
    res.json({url: await provider.portal(snapshot.membership)});
  }));
  app.post(root + '/abandon-checkout', wrap(async (req, res, {user}) => {
    rate(user.id, 'abandon', 5);
    if (req.body?.confirm !== true) fail('Confirm closing the unpaid checkout.');
    await sync(user.id);
    const {membership} = await store.command(user.id, 'snapshot');
    if (membership?.state === 'checkout' && membership.checkout_id && !membership.subscription_id) {
      await provider.expire(membership);
      await sync(user.id);
    }
    res.json(publicStatus(await store.command(user.id, 'snapshot')));
  }));
  app.post(root + '/cancel', wrap(async (req, res, {user, snapshot}) => {
    rate(user.id, 'cancel', 5);
    if (req.body?.confirm !== true) fail('Confirm that you want to stop renewal.');
    if (!snapshot.membership?.subscription_id) fail('No web subscription is available.', 409);
    await provider.cancel(snapshot.membership);
    await sync(user.id);
    res.json(publicStatus(await store.command(user.id, 'snapshot')));
  }));
  const relevant = new Set(['checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed',
    'checkout.session.expired', 'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted',
    'customer.subscription.paused', 'customer.subscription.resumed', 'invoice.paid', 'invoice.payment_failed',
    'invoice.payment_action_required', 'invoice.marked_uncollectible', 'charge.refunded', 'charge.dispute.created', 'radar.early_fraud_warning.created']);
  app.post(root + '/webhook', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      if (!provider.verify(req.korlixWebBillingRawBody, req.headers['stripe-signature'])) return res.status(400).json({error: 'Invalid payment signature.'});
      const event = JSON.parse(req.korlixWebBillingRawBody.toString());
      if (event.livemode !== provider.live || !/^evt_[A-Za-z0-9]+$/.test(event.id || '')) return res.status(400).json({error: 'Payment environment mismatch.'});
      if (!relevant.has(event.type)) return res.json({received: true});
      if ((await store.command(null, 'seen', {event_id: event.id})).seen) return res.json({received: true});
      const object = event.data?.object || {};
      if (['charge.refunded', 'charge.dispute.created', 'radar.early_fraud_warning.created'].includes(event.type)) {
        const charge = event.type === 'charge.refunded' ? object.id : object.charge;
        for (const sub of await provider.chargeSubscriptions(charge)) {
          const m = await store.command(null, 'lookup', {subscription_id: sub});
          if (m) await store.command(m.user_id, 'hold', {subscription_id: sub, reason: event.type});
        }
      } else {
        let sub, lookup;
        if (event.type.startsWith('customer.subscription.')) {sub = stripeId(object.id, 'sub'); lookup = {subscription_id: sub};}
        else if (event.type.startsWith('invoice.')) {
          sub = object.parent?.subscription_details?.subscription || object.subscription;
          if (sub) {sub = stripeId(sub, 'sub'); lookup = {subscription_id: sub};}
        } else {
          lookup = {checkout_id: stripeId(object.id, 'cs')};
          if (object.subscription) sub = stripeId(object.subscription, 'sub');
        }
        let m = lookup ? await store.command(null, 'lookup', lookup) : null;
        // A provider callback can arrive before Checkout's response is saved.
        // This fallback must match our existing server-generated attempt; the
        // independent Stripe read below checks owner, generation and catalog.
        if (!m && UUID.test(object.metadata?.generation || '') && UUID.test(object.metadata?.korlix_web_user || '')) {
          m = await store.command(null, 'lookup', {generation: object.metadata.generation});
          if (m && m.user_id !== object.metadata.korlix_web_user) m = null;
        }
        if (m) await sync(m.user_id, sub);
      }
      await store.command(null, 'record_event', {event_id: event.id, event_type: event.type, livemode: event.livemode});
      res.json({received: true});
    } catch { res.status(503).json({error: 'Payment event could not be reconciled. Stripe can retry it.'}); }
  });
  let timer, running = false;
  async function tick() {
    if (running || !provider.configured) return;
    running = true;
    try {
      for (const row of await store.command(null, 'due')) await sync(row.user_id).catch(() => {});
    } catch { /* Webhooks and the next bounded reconciliation run retry. */ }
    finally { running = false; }
  }
  if (autoStart && provider.configured) { timer = setInterval(tick, 60000); timer.unref?.(); }
  return {sync, tick, stop: () => clearInterval(timer)};
}
