import { createNativePushSender, nativePushIssuer, socialNativePushConfig, validateSocialNativeSubscription } from './native_push_providers.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// authenticate() must verify this very bearer token first. Its subject is also
// compared with the returned user, and its issuer with the server-owned project.
// Client-supplied owner/body claims are never used to address a notification.
export function nativePushOwner(req, user, env = process.env) {
  try {
    const expected = nativePushIssuer(env);
    const authorization = String(req.headers.authorization || '');
    if (!authorization.startsWith('Bearer ') || !expected || !uuid.test(user.id || '')) throw Error();
    const parts = authorization.slice(7).split('.');
    if (parts.length !== 3 || parts[1].length > 16384) throw Error();
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (claims.sub !== user.id || claims.iss !== expected) throw Error();
    return JSON.stringify([expected, user.id]);
  } catch { throw Object.assign(Error('Sign in again to enable mobile notifications.'), { code: 'UNAUTHENTICATED' }); }
}

export function nativeDeliveryPayload(delivery) {
  if (!['peer', 'group'].includes(delivery.kind) || !['message', 'call', 'online'].includes(delivery.type)
      || !uuid.test(delivery.id || '') || !uuid.test(delivery.event_id || '') || !uuid.test(delivery.binding || '')
      || !Number.isFinite(Date.parse(delivery.expires_at))) throw Error('Invalid queued notification.');
  let owner;
  try { owner = JSON.parse(delivery.owner); } catch { throw Error('Invalid queued notification owner.'); }
  if (!Array.isArray(owner) || owner.length !== 2 || typeof owner[0] !== 'string' || !uuid.test(owner[1] || '')) throw Error('Invalid queued notification owner.');
  return { owner: delivery.owner, binding: delivery.binding, kind: delivery.kind, id: delivery.id, event_id: delivery.event_id,
    type: delivery.type, expires_at: delivery.expires_at, silent: delivery.silent === true, title: 'KORLIX Social',
    body: delivery.type === 'online' ? 'A selected connection is online. Open KORLIX Social to see who.'
      : delivery.type === 'call' ? 'You have an incoming call. Open KORLIX Social to answer.' : 'You have a new message. Open KORLIX Social to read it.' };
}

export function nativeDeliveryOutcome(error, attempted) {
  const code = Number(error.statusCode);
  if (['UNREGISTERED', 'Unregistered', 'BadDeviceToken', 'DeviceTokenNotForTopic'].includes(error.providerCode)) return 'expired';
  if (error.deliveryStarted === false) return 'retry';
  // Credential/project mistakes must not delete otherwise valid device tokens.
  if (code === 429 || code >= 500 && code <= 599) return 'retry';
  return attempted && !Number.isFinite(code) ? 'unknown' : 'failed';
}

export function createSocialNativePush({ database, authenticate, env = process.env, logger = console, sender, autoStart = true, now = Date.now } = {}) {
  const deliver = sender || createNativePushSender({ env, now });
  let timer, busy = false, stopped = false;
  const rpc = async (actor, action, data = {}) => {
    const result = await database.rpc('korlix_social_native_push_v1', { p_actor: actor, p_action: action, p_data: data });
    if (result.error) throw Object.assign(Error(result.error.message), { code: result.error.code });
    if (result.data == null) throw Error('Mobile notification storage unavailable.');
    return result.data;
  };
  const tick = async () => {
    if (busy || stopped || !database || !socialNativePushConfig(env).enabled) return;
    busy = true;
    try {
      const { items = [] } = await rpc(null, 'claim');
      await Promise.all(items.map(async item => {
        let attempted = false;
        try {
          const { delivery } = await rpc(null, 'authorize', { id: item.id, lease: item.lease });
          if (!delivery) return;
          const subscription = validateSocialNativeSubscription(delivery.subscription, env);
          const config = socialNativePushConfig(env).providers[subscription.provider];
          const payload = nativeDeliveryPayload(delivery);
          const seconds = Math.floor((Date.parse(delivery.expires_at) - now()) / 1000);
          if (!config.enabled || seconds <= 0) {
            await rpc(null, 'finish', { id: item.id, lease: item.lease, status: 'cancelled' });
            return;
          }
          attempted = true;
          await deliver(subscription, payload, { ttl: Math.min(seconds, delivery.type === 'call' ? 45 : delivery.type === 'online' ? 90 : 300) });
          await rpc(null, 'finish', { id: item.id, lease: item.lease, status: 'accepted' });
        } catch (error) {
          const status = nativeDeliveryOutcome(error, attempted);
          try { await rpc(null, 'finish', { id: item.id, lease: item.lease, status,
            ...(status === 'retry' ? { retry_after_seconds: Math.ceil(Math.max(60, Math.min(86400, Number(error.retryAfterSeconds) || 60))) } : {}),
          }); } catch { /* uncertain leases are never replayed */ }
          logger.warn?.('Social mobile notification delivery deferred', { status });
        }
      }));
    } catch { logger.warn?.('Social mobile notification queue unavailable'); }
    finally { busy = false; }
  };
  const register = app => {
    const route = action => async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        const user = await authenticate(req, res); if (!user) return;
        const data = req.method === 'GET' ? req.query : req.body;
        if (!data || typeof data !== 'object' || Array.isArray(data) || Buffer.byteLength(JSON.stringify(data)) > 6000) return res.status(400).json({ error: 'Invalid mobile notification settings.' });
        if (action === 'state') return res.json({ ...await rpc(user.id, 'state'), ...socialNativePushConfig(env) });
        if (!uuid.test(data.device || '') || !uuid.test(data.binding || '')) return res.status(400).json({ error: 'Reopen notification settings on this device.' });
        if (action === 'unsubscribe') return res.json(await rpc(user.id, 'unsubscribe', { device: data.device, binding: data.binding }));
        const config = socialNativePushConfig(env);
        if (!config.enabled) return res.status(503).json({ error: config.reason });
        if (typeof data.messages !== 'boolean' || typeof data.calls !== 'boolean' || typeof data.online !== 'boolean') return res.status(400).json({ error: 'Choose your notification preferences.' });
        let subscription;
        try { subscription = validateSocialNativeSubscription(data.subscription, env); } catch (error) { return res.status(400).json({ error: error.message }); }
        if (!config.providers[subscription.provider].enabled) return res.status(503).json({ error: config.providers[subscription.provider].reason });
        const owner_key = nativePushOwner(req, user, env);
        return res.json(await rpc(user.id, 'subscribe', { device: data.device, binding: data.binding, messages: data.messages, calls: data.calls, online: data.online, owner_key, subscription }));
      } catch (error) {
        const status = { UNAUTHENTICATED: 401, '42501': 403, P0001: 400, '54000': 429, '23505': 409, '22P02': 400, '23514': 400 }[error.code] || 503;
        return res.status(status).json({ error: status === 503 ? 'Mobile notification settings could not be confirmed. Refresh before retrying.' : error.message });
      }
    };
    app.get('/api/social/native_push_state', route('state'));
    app.post('/api/social/native_push_subscribe', route('subscribe'));
    app.post('/api/social/native_push_unsubscribe', route('unsubscribe'));
  };
  if (autoStart && database && socialNativePushConfig(env).enabled) {
    timer = setInterval(() => void tick(), 5000);
    timer.unref?.();
  }
  return { register, tick, stop() { stopped = true; clearInterval(timer); deliver.close?.(); } };
}
