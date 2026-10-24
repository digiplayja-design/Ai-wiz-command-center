import {GoogleAuth, OAuth2Client} from 'google-auth-library';
import {PACKAGE, purchaseToken, PRODUCTS} from './core.mjs';
import {BillingError, fail} from '../web_billing/core.mjs';

export const CATALOG_FAILURES = Object.freeze(['api_disabled', 'permission_denied', 'authentication_failed',
  'product_not_found', 'temporarily_unavailable', 'provider_request_failed', 'monthly_plan_unavailable']);
function providerFailure(error) {
  const status = Number(error?.response?.status);
  const body = error?.response?.data?.error;
  if (body?.details?.some(detail => detail?.reason === 'SERVICE_DISABLED')) return 'api_disabled';
  if (status === 401 || ['invalid_grant', 'invalid_client', 'unauthorized_client'].includes(body)) return 'authentication_failed';
  if (status === 403) return 'permission_denied';
  if (status === 404) return 'product_not_found';
  if (status === 429 || status >= 500) return 'temporarily_unavailable';
  return 'provider_request_failed';
}
function catalogError(reason) {
  const error = new BillingError('Google Play could not verify this subscription. Please retry.', 503);
  error.googlePlayReason = reason;
  return error;
}

export function googlePlay(environment = process.env, {auth, identity = new OAuth2Client(), packageName = PACKAGE, products = PRODUCTS, notificationPackages = [packageName]} = {}) {
  let credentials;
  try { credentials = JSON.parse(environment.KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || 'null'); } catch { /* fail closed */ }
  const configured = !!(credentials?.client_email && credentials?.private_key && credentials?.type === 'service_account');
  const client = auth || (configured ? new GoogleAuth({credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher']}) : null);
  const root = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
  async function request(url, method = 'GET', data) {
    if (!client) fail('Google Play billing is being set up. Please try again later.', 503);
    try { return (await client.request({url, method, data, timeout: 20000, retry: false})).data; }
    catch (error) { throw catalogError(providerFailure(error)); }
  }
  return {
    configured, ready: configured && environment.KORLIX_GOOGLE_PLAY_BILLING_ENABLED === 'true',
    notificationsConfigured: !!(environment.KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE && environment.KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT && environment.KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION),
    async catalog(product) {
      if (!Object.hasOwn(products, product)) fail('Unsupported subscription.');
      const result = await request(`${root}/subscriptions/${product}`);
      const plan = result?.basePlans?.find(p => p.basePlanId === 'monthly');
      if (result?.productId !== product || plan?.state !== 'ACTIVE' ||
          plan?.autoRenewingBasePlanType?.billingPeriodDuration !== 'P1M') {
        const error = new BillingError('This Google Play monthly plan is not available yet. Please try again later.', 503);
        error.googlePlayReason = 'monthly_plan_unavailable';
        throw error;
      }
      return true;
    },
    async subscription(token) { return request(`${root}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken(token))}`); },
    async acknowledge(token, product) {
      if (!Object.hasOwn(products, product)) fail('Unsupported subscription.');
      await request(`${root}/purchases/subscriptions/${product}/tokens/${encodeURIComponent(purchaseToken(token))}:acknowledge`, 'POST', {});
    },
    async notification(req) {
      const audience = environment.KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE;
      const email = environment.KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT;
      if (!audience || !email || !environment.KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION) fail('Notifications are not configured.', 503);
      const authorization = req.headers?.authorization || '';
      if (!authorization.startsWith('Bearer ')) fail('Invalid notification identity.', 401);
      let payload;
      try { payload = (await identity.verifyIdToken({idToken: authorization.slice(7), audience})).getPayload(); }
      catch { fail('Invalid notification identity.', 401); }
      if (payload?.email !== email || payload?.email_verified !== true ||
          req.body?.subscription !== environment.KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION) fail('Invalid notification identity.', 403);
      let message;
      try {
        if (typeof req.body?.message?.data !== 'string' || req.body.message.data.length > 16384) throw new Error();
        message = JSON.parse(Buffer.from(req.body.message.data, 'base64').toString('utf8'));
      } catch { fail('Invalid Google Play notification.'); }
      if (!notificationPackages.includes(message.packageName)) fail('Notification package does not match.', 400);
      return message;
    },
  };
}
