import {readFile} from 'node:fs/promises';
import {GoogleAuth, OAuth2Client} from 'google-auth-library';
import {ESHA_BUNDLE, ESHA_PRODUCT, fail, productFor, appleFacts, googleFacts} from './catalog.mjs';

export function eshaProviders(env = process.env, {googleAuth, googleIdentity = new OAuth2Client(), appleFactory} = {}) {
  let credentials;
  try { credentials = JSON.parse(env.KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || 'null'); } catch { /* fail closed */ }
  const google = googleAuth || (credentials?.type === 'service_account' && credentials.client_email && credentials.private_key
    ? new GoogleAuth({credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher']}) : null);
  const appleKey = env.KORLIX_APPLE_PRIVATE_KEY_BASE64
    ? Buffer.from(env.KORLIX_APPLE_PRIVATE_KEY_BASE64, 'base64').toString('utf8')
    : String(env.KORLIX_APPLE_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  const appleAppId = /^\d{5,15}$/.test(env.KORLIX_ESHA_APPLE_APP_ID || '') ? Number(env.KORLIX_ESHA_APPLE_APP_ID) : null;
  const configured = {
    apple: !!(appleKey && env.KORLIX_APPLE_ISSUER_ID && env.KORLIX_APPLE_KEY_ID && appleAppId),
    google: !!google,
  };
  const notificationsConfigured = !!(env.KORLIX_ESHA_GOOGLE_RTDN_AUDIENCE &&
    env.KORLIX_ESHA_GOOGLE_RTDN_SERVICE_ACCOUNT && env.KORLIX_ESHA_GOOGLE_RTDN_SUBSCRIPTION);
  let appleConfiguration;
  async function appleClients() {
    if (appleFactory) return appleFactory();
    if (!configured.apple) fail('App Store verification is being configured.', 503, 'store_not_configured');
    return appleConfiguration ||= (async () => {
      const lib = await import('@apple/app-store-server-library');
      const certs = await Promise.all(['AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer']
        .map(name => readFile(new URL('../../apple_root_certs/' + name, import.meta.url))));
      return [lib.Environment.PRODUCTION, lib.Environment.SANDBOX].map(environment => ({
        verifier: new lib.SignedDataVerifier(certs, true, environment, ESHA_BUNDLE,
          environment === lib.Environment.PRODUCTION ? appleAppId : undefined),
        client: new lib.AppStoreServerAPIClient(appleKey, env.KORLIX_APPLE_KEY_ID, env.KORLIX_APPLE_ISSUER_ID, ESHA_BUNDLE, environment),
      }));
    })().catch(error => { appleConfiguration = null; throw error; });
  }
  const googleRoot = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ESHA_BUNDLE}`;
  function validToken(token) {
    if (typeof token !== 'string' || token.length < 10 || token.length > 4096 || /\s/.test(token)) {
      fail('Restore a valid Google Play purchase.', 400, 'invalid_purchase_token');
    }
    return encodeURIComponent(token);
  }
  async function request(path, method = 'GET', data) {
    if (!google) fail('Google Play verification is being configured.', 503, 'store_not_configured');
    try { return (await google.request({url: googleRoot + path, method, data, timeout: 20000, retry: false})).data; }
    catch { fail('The store could not verify this purchase. Please restore again later.', 503, 'store_unavailable'); }
  }
  return {
    configured(provider) { return !!configured[provider]; },
    ready(provider) { return !!configured[provider] && (provider !== 'google' || notificationsConfigured); },
    async verify(provider, {userId, productId, purchaseId, purchaseToken}) {
      productFor(provider, productId);
      // Timestamp the start, so an older slow lookup cannot overwrite a newer result.
      const observedAt = Date.now();
      if (provider === 'google') {
        const value = await request(`/purchases/subscriptionsv2/tokens/${validToken(purchaseToken)}`);
        return googleFacts(value, userId, purchaseToken, productId, env, observedAt);
      }
      if (!/^\d{5,40}$/.test(String(purchaseId || ''))) fail('Restore a valid App Store transaction.', 400, 'invalid_transaction');
      for (const {client, verifier} of await appleClients()) {
        let records;
        try {
          const transaction = await verifier.verifyAndDecodeTransaction((await client.getTransactionInfo(String(purchaseId))).signedTransactionInfo);
          if (transaction.productId !== productId || transaction.bundleId !== ESHA_BUNDLE) {
            fail('This transaction does not match Esha.', 409, 'invalid_product');
          }
          const statuses = await client.getAllSubscriptionStatuses(String(transaction.originalTransactionId));
          records = [];
          for (const group of statuses.data || []) for (const last of group.lastTransactions || []) {
            const value = await verifier.verifyAndDecodeTransaction(last.signedTransactionInfo);
            if (value.originalTransactionId === transaction.originalTransactionId && value.productId === productId) {
              const renewal = last.signedRenewalInfo ? await verifier.verifyAndDecodeRenewalInfo(last.signedRenewalInfo) : undefined;
              records.push({value, status: last.status, renewal});
            }
          }
        } catch (error) {
          if (error?.code === 'invalid_product') throw error;
          continue;
        }
        const current = records.sort((a, b) => Number(b.value.purchaseDate) - Number(a.value.purchaseDate) ||
          Number(b.value.signedDate) - Number(a.value.signedDate))[0];
        if (current) return appleFacts(current.value, userId, env, observedAt, current);
      }
      fail('App Store verification is temporarily unavailable. Please restore again later.', 503, 'store_unavailable');
    },
    async finish(facts) {
      if (facts.provider !== 'google' || !facts.active) return;
      const token = validToken(facts.provider_token);
      const value = await request(`/purchases/subscriptionsv2/tokens/${token}`);
      if (value.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') return;
      if (value.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_PENDING') fail('The store has not completed this purchase.', 409, 'payment_pending');
      await request(`/purchases/subscriptions/${ESHA_PRODUCT.google}/tokens/${token}:acknowledge`, 'POST', {});
    },
    async appleNotification(payload) {
      if (typeof payload !== 'string' || payload.length < 20 || payload.length > 100000) fail('Invalid store notification.', 400, 'invalid_notification');
      for (const {verifier} of await appleClients()) {
        try {
          const notification = await verifier.verifyAndDecodeNotification(payload);
          if (notification.notificationType === 'TEST') return {test: true};
          if (notification.data?.signedTransactionInfo) {
            const value = await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
            if (value.bundleId !== ESHA_BUNDLE || value.productId !== ESHA_PRODUCT.apple) fail('Invalid store product.', 400, 'invalid_notification');
            return value;
          }
        } catch { /* Try the other verifier environment, never accept decoded unverified input. */ }
      }
      fail('Store notification could not be verified.', 400, 'invalid_notification');
    },
    async googleNotification(req) {
      if (!notificationsConfigured) fail('Esha store notifications are being configured.', 503, 'store_not_configured');
      const authorization = req.headers?.authorization || '';
      if (!authorization.startsWith('Bearer ')) fail('Invalid notification identity.', 401, 'invalid_notification_identity');
      let payload;
      try { payload = (await googleIdentity.verifyIdToken({idToken: authorization.slice(7), audience: env.KORLIX_ESHA_GOOGLE_RTDN_AUDIENCE})).getPayload(); }
      catch { fail('Invalid notification identity.', 401, 'invalid_notification_identity'); }
      if (payload?.email !== env.KORLIX_ESHA_GOOGLE_RTDN_SERVICE_ACCOUNT || payload.email_verified !== true ||
          !['accounts.google.com', 'https://accounts.google.com'].includes(payload.iss) ||
          req.body?.subscription !== env.KORLIX_ESHA_GOOGLE_RTDN_SUBSCRIPTION) {
        fail('Invalid notification identity.', 403, 'invalid_notification_identity');
      }
      let message;
      try {
        if (typeof req.body?.message?.data !== 'string' || req.body.message.data.length > 16384) throw new Error();
        message = JSON.parse(Buffer.from(req.body.message.data, 'base64').toString('utf8'));
      } catch { fail('Invalid Google Play notification.', 400, 'invalid_notification'); }
      if (message.packageName !== ESHA_BUNDLE) fail('Notification package does not match Esha.', 400, 'invalid_notification');
      return message;
    },
    async confirmVoided(token, orderId) {
      validToken(token);
      if (typeof orderId !== 'string' || orderId.length < 6 || orderId.length > 200) fail('Invalid refunded order.', 400, 'invalid_notification');
      let pageToken;
      for (let page = 0; page < 5; page++) {
        const query = new URLSearchParams({type: '1', 'pageSelection.maxResults': '1000'});
        if (pageToken) query.set('pageSelection.token', pageToken);
        const value = await request('/purchases/voidedpurchases?' + query);
        const match = value.voidedPurchases?.find(item => item.purchaseToken === token && item.orderId === orderId);
        if (match) return true;
        pageToken = value.tokenPagination?.nextPageToken;
        if (!pageToken) break;
      }
      fail('The store has not confirmed this refund yet.', 503, 'refund_unconfirmed');
    },
  };
}
