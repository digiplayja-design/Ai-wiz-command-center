import { createHash, createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { connect } from 'node:http2';

const appId = /^[A-Za-z0-9][A-Za-z0-9_.-]{2,199}$/;
const projectId = /^[a-z][a-z0-9-]{4,62}$/;
const issuer = env => {
  try {
    const url = new URL(env.SUPABASE_URL);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) return null;
    return `${url.origin}/auth/v1`;
  } catch { return null; }
};
export const nativePushIssuer = issuer;
const configured = (enabled, reason) => ({ enabled, reason: enabled ? null : reason });

// Only configuration status is returned to clients. Never return key material,
// tokens, project credentials, or a caller-controlled provider endpoint.
export function socialNativePushConfig(env = process.env) {
  const active = env.SOCIAL_NATIVE_PUSH_ENABLED === 'true' && !!issuer(env);
  const fcm = active && env.SOCIAL_NATIVE_FCM_ENABLED === 'true' && projectId.test(env.SOCIAL_NATIVE_FCM_PROJECT_ID || '')
    && appId.test(env.SOCIAL_NATIVE_FCM_APP_ID || '') && !!env.SOCIAL_NATIVE_FCM_SERVICE_ACCOUNT_FILE;
  const apns = active && env.SOCIAL_NATIVE_APNS_ENABLED === 'true' && appId.test(env.SOCIAL_NATIVE_APNS_APP_ID || '')
    && /^[A-Z0-9]{10}$/.test(env.SOCIAL_NATIVE_APNS_TEAM_ID || '') && /^[A-Z0-9]{10}$/.test(env.SOCIAL_NATIVE_APNS_KEY_ID || '')
    && !!env.SOCIAL_NATIVE_APNS_PRIVATE_KEY_FILE;
  const providers = { fcm: configured(!!fcm, 'Android notifications are not configured yet.'), apns: configured(!!apns, 'iPhone and iPad notifications are not configured yet.') };
  const enabled = !!(fcm || apns);
  return { enabled, native: true, providers, reason: enabled ? null : 'Background mobile notifications are not configured yet.' };
}

export function validateSocialNativeSubscription(value, env = process.env) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Choose a supported mobile notification subscription.');
  const { provider, token, app_id, environment } = value;
  if (!['fcm', 'apns'].includes(provider) || !['production', 'sandbox'].includes(environment) || !appId.test(app_id || '')) throw Error('Invalid mobile notification application.');
  const expected = provider === 'fcm' ? env.SOCIAL_NATIVE_FCM_APP_ID : env.SOCIAL_NATIVE_APNS_APP_ID;
  if (app_id !== expected) throw Error('This application is not configured for KORLIX notifications.');
  if (typeof token !== 'string' || (provider === 'apns' ? !/^[0-9a-f]{64,200}$/i.test(token) || token.length % 2 !== 0 : !/^[A-Za-z0-9_:.-]{20,2048}$/.test(token))) throw Error('Invalid mobile notification token.');
  if (provider === 'fcm' && environment !== 'production') throw Error('Invalid Android notification environment.');
  if (provider === 'apns' && environment === 'sandbox' && env.SOCIAL_NATIVE_APNS_ALLOW_SANDBOX !== 'true') throw Error('Development notifications are not enabled.');
  return { provider, token: provider === 'apns' ? token.toLowerCase() : token, app_id, environment };
}

const providerError = (statusCode, providerCode, retryAfterSeconds) => Object.assign(Error('Mobile notification provider rejected the request.'), { statusCode, providerCode, retryAfterSeconds });
export function nativeRetryAfter(value, now = Date.now()) {
  if (typeof value !== 'string' || !value.trim()) return 60;
  const seconds = /^\d+$/.test(value.trim()) ? Number(value) : Math.ceil((Date.parse(value) - now) / 1000);
  return Number.isFinite(seconds) ? Math.max(60, Math.min(86400, seconds)) : 60;
}
async function providerErrorBody(response) {
  const reader = response.body?.getReader?.();
  if (!reader) return {};
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 16384) return {};
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  } catch { return {}; }
  finally { await reader.cancel().catch(() => {}); }
}

// APNs expects persistent HTTP/2 sessions, not rapid connection churn. Keep at
// most one reusable session per Apple environment; retire GOAWAY sessions after
// their in-flight streams finish. No token is used as a connection/cache key.
export function createApnsHttp2Transport({ connector = connect, idleMs = 60000 } = {}) {
  const sessions = new Map(), all = new Set();
  const retire = entry => {
    if (sessions.get(entry.origin) === entry) sessions.delete(entry.origin);
    entry.retiring = true;
    clearTimeout(entry.idle);
    if (!entry.pending.size) entry.client.close();
  };
  const get = origin => {
    if (!['https://api.push.apple.com', 'https://api.sandbox.push.apple.com'].includes(origin)) throw Error('Invalid Apple notification endpoint.');
    let entry = sessions.get(origin);
    if (entry && !entry.client.destroyed && !entry.client.closed && !entry.retiring) { clearTimeout(entry.idle); return entry; }
    entry = { origin, client: connector(origin), pending: new Set(), retiring: false, idle: null };
    sessions.set(origin, entry); all.add(entry);
    entry.client.on('error', error => { for (const fail of [...entry.pending]) fail(error); retire(entry); entry.client.destroy(); });
    entry.client.on('goaway', () => retire(entry));
    entry.client.on('close', () => {
      entry.retiring = true; clearTimeout(entry.idle);
      for (const fail of [...entry.pending]) fail(Error('Apple notification connection closed.'));
      if (sessions.get(origin) === entry) sessions.delete(origin);
      all.delete(entry);
    });
    return entry;
  };
  const send = ({ origin, headers, body, timeout = 8000 }) => new Promise((resolve, reject) => {
    let entry;
    try { entry = get(origin); } catch (error) { reject(Object.assign(error, { deliveryStarted: false })); return; }
    let done = false, status = 0, response = '', responseHeaders = {}, request;
    const finish = (error, value) => {
      if (done) return;
      done = true; clearTimeout(timer); entry.pending.delete(fail);
      if (error) request?.close();
      if (!entry.pending.size) {
        if (entry.retiring) entry.client.close();
        else { entry.idle = setTimeout(() => retire(entry), idleMs); entry.idle.unref?.(); }
      }
      if (error) reject(error); else resolve(value);
    };
    const fail = error => finish(error);
    const timer = setTimeout(() => fail(Error('Mobile notification delivery timeout.')), timeout);
    entry.pending.add(fail);
    try { request = entry.client.request(headers); } catch (error) { fail(Object.assign(error, { deliveryStarted: false })); return; }
    request.setEncoding('utf8');
    request.on('response', values => { responseHeaders = values; status = Number(values[':status']); });
    request.on('data', chunk => { response += chunk; if (response.length > 16384) fail(Error('Mobile notification response too large.')); });
    request.on('error', fail);
    request.on('end', () => {
      let data = {};
      try { data = JSON.parse(response || '{}'); } catch { /* never expose provider response */ }
      if (status !== 200) finish(providerError(status, data.reason, nativeRetryAfter(responseHeaders['retry-after'])));
      else finish(null, { statusCode: status });
    });
    request.end(body);
  });
  send.close = () => {
    for (const entry of all) {
      entry.retiring = true;
      clearTimeout(entry.idle);
      for (const fail of [...entry.pending]) fail(Error('Mobile notification worker stopped.'));
      entry.client.destroy();
    }
    sessions.clear(); all.clear();
  };
  return send;
}

export function createNativePushSender({ env = process.env, fetcher = fetch, apnsRequest, googleToken, now = Date.now } = {}) {
  const appleRequest = apnsRequest || createApnsHttp2Transport();
  let auth, tokenRequest, appleToken, appleIssued = 0;
  const accessToken = async () => {
    if (!tokenRequest) {
      tokenRequest = (async () => {
        if (googleToken) return googleToken();
        auth ||= import('google-auth-library').then(({ GoogleAuth }) => new GoogleAuth({
          keyFilename: env.SOCIAL_NATIVE_FCM_SERVICE_ACCOUNT_FILE, scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
          clientOptions: { transporterOptions: { timeout: 8000, retry: false, retryConfig: { retry: 0 } } },
        }));
        return (await auth).getAccessToken();
      })().finally(() => { tokenRequest = null; });
    }
    let timeout;
    const token = await Promise.race([tokenRequest, new Promise((_, reject) => {
      timeout = setTimeout(() => reject(Error('Mobile notification authorization timeout.')), 9000);
    })]).finally(() => clearTimeout(timeout));
    if (!token) throw Error('Mobile notification credentials unavailable.');
    return token;
  };
  const apnsToken = () => {
    const seconds = Math.floor(now() / 1000);
    if (appleToken && seconds - appleIssued < 3000 && seconds >= appleIssued) return appleToken;
    const key = createPrivateKey(readFileSync(env.SOCIAL_NATIVE_APNS_PRIVATE_KEY_FILE, 'utf8'));
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw Error('Invalid Apple push key.');
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const input = `${encode({ alg: 'ES256', kid: env.SOCIAL_NATIVE_APNS_KEY_ID })}.${encode({ iss: env.SOCIAL_NATIVE_APNS_TEAM_ID, iat: seconds })}`;
    appleToken = `${input}.${sign('sha256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
    appleIssued = seconds;
    return appleToken;
  };
  const send = async (subscription, payload, { ttl }) => {
    const sub = validateSocialNativeSubscription(subscription, env);
    if (!socialNativePushConfig(env).providers[sub.provider].enabled) throw providerError(503, 'DISABLED');
    const collapse = createHash('sha256').update(`${payload.type}:${payload.kind}:${payload.id}`).digest('hex');
    if (sub.provider === 'fcm') {
      let token;
      try { token = await accessToken(); } catch (error) { throw Object.assign(error, { deliveryStarted: false }); }
      const response = await fetcher(`https://fcm.googleapis.com/v1/projects/${env.SOCIAL_NATIVE_FCM_PROJECT_ID}/messages:send`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(12000),
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: sub.token, data: Object.fromEntries(Object.entries(payload).map(([key, value]) => [key, String(value)])),
          android: { priority: 'HIGH', ttl: `${ttl}s`, restricted_package_name: sub.app_id } } }),
      });
      if (!response.ok) {
        const data = await providerErrorBody(response);
        const details = Array.isArray(data?.error?.details) ? data.error.details : [];
        const code = details.find(item => item?.['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError')?.errorCode;
        throw providerError(response.status, code || data?.error?.status, nativeRetryAfter(response.headers?.get?.('retry-after'), now()));
      }
      try { await response.body?.cancel?.(); } catch { /* acceptance is already confirmed */ }
      return { statusCode: response.status };
    }
    let token;
    try { token = apnsToken(); } catch (error) { throw Object.assign(error, { deliveryStarted: false }); }
    return appleRequest({ origin: sub.environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com',
      headers: { ':method': 'POST', ':path': `/3/device/${sub.token}`, authorization: `bearer ${token}`, 'apns-topic': sub.app_id,
        'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(now() / 1000) + ttl), 'apns-collapse-id': collapse },
      body: JSON.stringify({ ...payload, aps: { alert: { title: payload.title, body: payload.body },
        ...(payload.silent === true ? {} : { sound: 'default' }), 'thread-id': `${payload.kind}:${payload.id}`,
        category: payload.type === 'message' ? 'KORLIX_SOCIAL_MESSAGE' : 'KORLIX_SOCIAL_OPEN' } }),
    });
  };
  send.close = () => appleRequest.close?.();
  return send;
}
