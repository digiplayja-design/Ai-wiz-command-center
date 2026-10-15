import {GoogleAuth, OAuth2Client} from 'google-auth-library';
import {PACKAGE, purchaseToken, PRODUCTS} from './core.mjs';
import {fail} from '../web_billing/core.mjs';

export function googlePlay(environment = process.env, {auth, identity = new OAuth2Client()} = {}) {
  let credentials;
  try { credentials = JSON.parse(environment.KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || 'null'); } catch { /* fail closed */ }
  const configured = !!(credentials?.client_email && credentials?.private_key && credentials?.type === 'service_account');
  const client = auth || (configured ? new GoogleAuth({credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher']}) : null);
  const root = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}`;
  async function request(url, method = 'GET', data) {
    if (!client) fail('Google Play billing is being set up. Please try again later.', 503);
    try { return (await client.request({url, method, data, timeout: 20000, retry: false})).data; }
    catch { fail('Google Play could not verify this subscription. Please retry.', 503); }
  }
  return {
    configured, ready: configured && environment.KORLIX_GOOGLE_PLAY_BILLING_ENABLED === 'true',
    notificationsConfigured: !!(environment.KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE && environment.KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT && environment.KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION),
    async catalog(product) {
      if (!Object.hasOwn(PRODUCTS, product)) fail('Unsupported subscription.');
      const result = await request(`${root}/subscriptions/${product}`);
      const plan = result?.basePlans?.find(p => p.basePlanId === 'monthly');
      if (result?.productId !== product || plan?.state !== 'ACTIVE' ||
          plan?.autoRenewingBasePlanType?.billingPeriodDuration !== 'P1M') {
        fail('This Google Play monthly plan is not available yet. Please try again later.', 503);
      }
      return true;
    },
    async subscription(token) { return request(`${root}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken(token))}`); },
    async acknowledge(token, product) {
      if (!Object.hasOwn(PRODUCTS, product)) fail('Unsupported subscription.');
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
      if (message.packageName !== PACKAGE) fail('Notification package does not match.', 400);
      return message;
    },
  };
}
