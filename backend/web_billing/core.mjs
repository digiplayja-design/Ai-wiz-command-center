export class BillingError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export const fail = (message, status = 400) => { throw new BillingError(message, status); };
export const PLAN_VERSION = 'web_monthly_20261004';
export const PLANS = Object.freeze({
  pro: Object.freeze({ tier: 'pro', name: 'Pro', amount: 3499, currency: 'usd', interval: 'month',
    features: ['30 AI requests and 60 credits per day', '2 video generations per month', 'All AI characters', 'Document and export tools'] }),
  ultra: Object.freeze({ tier: 'ultra', name: 'Ultra Premium', amount: 12499, currency: 'usd', interval: 'month',
    features: ['75 AI requests and 200 credits per day', '10 video generations per month', 'All AI characters', 'Higher personal usage allowances'] }),
});
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function uuid(value) {
  if (typeof value !== 'string' || !UUID.test(value)) fail('Invalid billing reference.');
  return value.toLowerCase();
}
export function stripeId(value, kind) {
  const result = typeof value === 'object' && value !== null ? value.id : value;
  if (typeof result !== 'string' || !new RegExp(`^${kind}_[A-Za-z0-9_]+$`).test(result)) fail('Invalid payment reference.', 409);
  return result;
}
export function safeStripeUrl(value, origin) {
  let u; try { u = new URL(value); } catch { fail('Payment link is unavailable. Please refresh billing.', 502); }
  if (u.origin !== origin || u.username || u.password) fail('Payment link could not be verified.', 502);
  return u.href;
}
export function billingStore(database) {
  return {
    async command(actor, action, payload = {}) {
      if (!database) fail('Billing storage is temporarily unavailable.', 503);
      const {data, error} = await database.rpc('korlix_web_billing_command', {p_actor: actor || null, p_action: action, p: payload});
      if (error) {
        const known = /BILL(\d{3}): (.+)/.exec(error.message || '');
        if (known) fail(known[2], Number(known[1]));
        fail('Billing storage is temporarily unavailable. Please retry.', 503);
      }
      return data;
    },
    async profile(userId) {
      const {data, error} = await database.rpc('korlix_web_billing_profile', {p_user_id: userId});
      if (error) fail('Account access could not be refreshed. Please retry.', 503);
      return data;
    },
  };
}
