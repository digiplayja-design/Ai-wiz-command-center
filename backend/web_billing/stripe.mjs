import {stripeSignature} from '../scheduling/stripe_provider.mjs';
import {PLANS, PLAN_VERSION, fail, stripeId, safeStripeUrl, uuid} from './core.mjs';

export const WEB_STRIPE_VERSION = '2026-09-30.endive';
export function webStripe(env, {fetcher = fetch, now = Date.now} = {}) {
  const key = String(env.KORLIX_WEB_STRIPE_SECRET_KEY || (env.KORLIX_WEB_STRIPE_USE_DIRECTORY_CREDENTIAL === 'true' ? env.KORLIX_DIRECTORY_STRIPE_SECRET_KEY : '') || '').trim();
  const secret = String(env.KORLIX_WEB_STRIPE_WEBHOOK_SECRET || '').trim();
  const configuration = String(env.KORLIX_WEB_STRIPE_PORTAL_CONFIGURATION_ID || '').trim();
  const prices = {pro: String(env.KORLIX_WEB_STRIPE_PRO_PRICE_ID || '').trim(), ultra: String(env.KORLIX_WEB_STRIPE_ULTRA_PRICE_ID || '').trim()};
  const live = /^(sk|rk)_live_/.test(key);
  const configured = /^(sk|rk)_(live|test)_[A-Za-z0-9_]+$/.test(key) && /^whsec_[A-Za-z0-9_]+$/.test(secret)
    && /^bpc_[A-Za-z0-9]+$/.test(configuration) && Object.values(prices).every(p => /^price_[A-Za-z0-9_]+$/.test(p)) && prices.pro !== prices.ultra;
  const enabled = env.KORLIX_WEB_STRIPE_ENABLED === 'true';
  let checking, checkedAt = 0, connection = 'unchecked';
  async function api(path, {method = 'GET', body, idem} = {}) {
    if (!configured) fail('Web billing is being prepared. Please try again later.', 503);
    let response, data;
    try {
      response = await fetcher('https://api.stripe.com/v1' + path, {
        method, redirect: 'error', signal: AbortSignal.timeout(25000),
        headers: {Authorization: 'Bearer ' + key, 'Stripe-Version': WEB_STRIPE_VERSION,
          ...(body ? {'Content-Type': 'application/x-www-form-urlencoded'} : {}), ...(idem ? {'Idempotency-Key': idem} : {})},
        ...(body ? {body: new URLSearchParams(body).toString()} : {}),
      });
      data = await response.json();
    } catch { fail('Stripe is temporarily unavailable. Retry without starting another purchase.', 503); }
    if (!response.ok) fail('Stripe could not complete this request. Please retry or contact support.', 502);
    return data;
  }
  async function checkConnection() {
    if (!configured) return 'configuration_missing';
    if (checking) return checking;
    if (connection !== 'unchecked' && now() - checkedAt < 60000) return connection;
    checking = (async () => {
      try {
        const p = await api('/billing_portal/configurations/' + configuration + '?expand[]=features.subscription_update.products');
        const allowed = new Set((p.features?.subscription_update?.products || []).flatMap(x => x.prices || []));
        connection = p.id === configuration && p.active === true && p.livemode === live
          && p.metadata?.korlix_feature === 'web_subscriptions'
          && p.features?.subscription_cancel?.enabled === true
          && p.features?.subscription_cancel?.mode === 'at_period_end'
          && p.features?.subscription_update?.enabled === true
          && p.features?.subscription_update?.proration_behavior === 'always_invoice'
          && Object.values(prices).every(x => allowed.has(x)) ? 'verified' : 'configuration_mismatch';
      } catch { connection = 'unavailable'; }
      checkedAt = now(); return connection;
    })().finally(() => {checking = null;});
    return checking;
  }
  function sessionValue(s, m) {
    if (s.livemode !== live || s.mode !== 'subscription' || s.client_reference_id !== m.user_id
        || s.metadata?.korlix_web_user !== m.user_id || s.metadata?.generation !== m.generation
        || s.metadata?.plan_version !== PLAN_VERSION) fail('Checkout does not match this account.', 409);
    stripeId(s.id, 'cs');
    if (s.customer && m.customer_id && stripeId(s.customer, 'cus') !== m.customer_id) fail('Checkout customer mismatch.', 409);
    if (s.amount_subtotal !== PLANS[m.requested_tier]?.amount || s.currency !== 'usd') fail('Checkout price could not be verified.', 409);
    const lines = s.line_items?.data || [];
    if (lines.length !== 1 || lines[0].quantity !== 1 || lines[0].price?.id !== m.requested_price) fail('Checkout items could not be verified.', 409);
    if (s.url) safeStripeUrl(s.url, 'https://checkout.stripe.com');
    return s;
  }
  function subscriptionValue(s, m) {
    const sub = stripeId(s.id, 'sub'), customer = stripeId(s.customer, 'cus');
    if (s.livemode !== live || s.livemode !== m.livemode || s.metadata?.korlix_web_user !== m.user_id
        || s.metadata?.generation !== m.generation || s.metadata?.plan_version !== PLAN_VERSION
        || (m.subscription_id && sub !== m.subscription_id) || (m.customer_id && customer !== m.customer_id)) fail('Subscription does not match this account.', 409);
    const items = s.items?.data || [], item = items[0], price = item?.price;
    const tier = Object.keys(PLANS).find(t => prices[t] === price?.id), plan = PLANS[tier];
    if (items.length !== 1 || s.items?.has_more || item.quantity !== 1 || !plan || price.currency !== 'usd'
        || price.unit_amount !== plan.amount || price.recurring?.interval !== 'month' || price.recurring?.interval_count !== 1
        || price.recurring?.usage_type !== 'licensed') fail('Subscription price could not be verified.', 409);
    const end = item.current_period_end ?? s.current_period_end, invoice = s.latest_invoice;
    const invoiceSub = invoice?.parent?.subscription_details?.subscription || invoice?.subscription;
    const sameInvoice = invoice && typeof invoice === 'object' && invoice.livemode === live
      && invoice.currency === 'usd' && stripeId(invoice.customer, 'cus') === customer
      && invoiceSub && stripeId(invoiceSub, 'sub') === sub;
    // A paid proration invoice can be smaller than the full monthly price.
    // Stripe's current, independently read subscription must match our catalog.
    const paid = s.status === 'active' && !s.pause_collection && !!sameInvoice && invoice.status === 'paid'
      && invoice.amount_remaining === 0 && Number.isSafeInteger(invoice.amount_paid) && invoice.amount_paid >= invoice.amount_due;
    if (paid && (!Number.isSafeInteger(end) || end <= 0)) fail('The paid subscription period could not be verified.', 409);
    return {user_id: m.user_id, generation: m.generation, livemode: live, subscription_id: sub, customer_id: customer,
      state: s.pause_collection ? 'paused' : s.status, tier, amount: plan.amount, paid,
      paid_until: paid ? new Date(end * 1000).toISOString() : null,
      invoice_id: invoice && typeof invoice === 'object' ? stripeId(invoice.id, 'in') : null,
      cancel_at_period_end: s.cancel_at_period_end === true || (Number.isSafeInteger(end) && s.cancel_at === end)};
  }
  return {
    configured, enabled, ready: configured && enabled, live, prices, checkConnection, apiVersion: WEB_STRIPE_VERSION,
    verify: (raw, signature) => configured && stripeSignature(raw, signature, secret, now()),
    async checkout(m) {
      if (!configured || !enabled) fail('New web subscriptions are temporarily unavailable.', 503);
      const plan = PLANS[m.requested_tier];
      if (!plan || m.requested_price !== prices[m.requested_tier] || m.livemode !== live) fail('Plan configuration changed. Contact support before retrying.', 409);
      uuid(m.user_id); uuid(m.generation);
      if (await checkConnection() !== 'verified') fail('The billing connection is not ready. Please try again later.', 503);
      const s = await api('/checkout/sessions', {method: 'POST', idem: 'web-plan-' + m.generation, body: {
        mode: 'subscription', integration_identifier: 'korlix_web_plans_qhmvtxza',
        'subscription_data[billing_mode][type]': 'flexible', client_reference_id: m.user_id,
        'metadata[korlix_web_user]': m.user_id, 'metadata[generation]': m.generation, 'metadata[plan_version]': PLAN_VERSION,
        'subscription_data[metadata][korlix_web_user]': m.user_id, 'subscription_data[metadata][generation]': m.generation,
        'subscription_data[metadata][plan_version]': PLAN_VERSION,
        ...(m.customer_id ? {customer: m.customer_id} : {customer_email: m.checkout_email}),
        'line_items[0][price]': m.requested_price, 'line_items[0][quantity]': '1', 'expand[0]': 'line_items',
        expires_at: String(Math.floor(Date.parse(m.checkout_expires) / 1000)),
        success_url: 'https://www.korlixdeveloper.com/app/?billing=return', cancel_url: 'https://www.korlixdeveloper.com/app/?billing=cancel',
        'custom_text[submit][message]': `${plan.name}: USD ${(plan.amount / 100).toFixed(2)} per month, renewed automatically until canceled. Manage or cancel renewal in KORLIX Settings → Plans & Billing. AI GAS and Music Studio are separate purchases.`,
      }});
      return sessionValue(s, m);
    },
    async session(m) { return sessionValue(await api('/checkout/sessions/' + stripeId(m.checkout_id, 'cs') + '?expand[]=line_items'), m); },
    async subscription(sub, m) { return subscriptionValue(await api('/subscriptions/' + stripeId(sub, 'sub') + '?expand[]=latest_invoice'), m); },
    async cancel(m) {
      await api('/subscriptions/' + stripeId(m.subscription_id, 'sub'), {method: 'POST',
        body: {cancel_at_period_end: 'true'}});
    },
    async expire(m) {
      const current = await this.session(m);
      if (current.status !== 'open') return current;
      return sessionValue(await api('/checkout/sessions/' + stripeId(m.checkout_id, 'cs') + '/expire',
        {method: 'POST', body: {'expand[0]': 'line_items'}}), m);
    },
    async portal(m) {
      if (await checkConnection() !== 'verified') fail('Billing management is temporarily unavailable.', 503);
      const s = await api('/billing_portal/sessions', {method: 'POST', body: {
        customer: stripeId(m.customer_id, 'cus'), configuration, return_url: 'https://www.korlixdeveloper.com/app/?billing=return',
      }});
      return safeStripeUrl(s.url, 'https://billing.stripe.com');
    },
    async chargeSubscriptions(chargeId) {
      const c = await api('/charges/' + stripeId(chargeId, 'ch'));
      if (c.livemode !== live) fail('Payment environment mismatch.', 409);
      const invoices = [];
      if (c.invoice) invoices.push(await api('/invoices/' + stripeId(c.invoice, 'in')));
      else if (c.payment_intent) {
        const query = new URLSearchParams({'payment[type]': 'payment_intent', 'payment[payment_intent]': stripeId(c.payment_intent, 'pi'),
          'expand[]': 'data.invoice', limit: '100'});
        const payments = await api('/invoice_payments?' + query);
        if (payments.has_more) fail('Payment review requires support.', 503);
        for (const p of payments.data || []) if (p.invoice && typeof p.invoice === 'object') invoices.push(p.invoice);
      }
      return [...new Set(invoices.filter(i => i.livemode === live).map(i => i.parent?.subscription_details?.subscription || i.subscription)
        .filter(Boolean).map(i => stripeId(i, 'sub')))];
    },
    sessionValue, subscriptionValue,
  };
}
