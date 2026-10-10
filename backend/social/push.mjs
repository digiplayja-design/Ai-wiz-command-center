import { createHash, createECDH } from 'node:crypto';
import webpush from 'web-push';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const decode = (s, n) => typeof s === 'string' && /^[A-Za-z0-9_-]+$/.test(s) && Buffer.from(s, 'base64url').length === n;
export function validateSocialPushSubscription(value) {
  if (!value || typeof value !== 'object') throw Error('Choose a supported browser notification subscription.');
  let url;
  try { url = new URL(value.endpoint); } catch { throw Error('Invalid notification endpoint.'); }
  // Never fetch arbitrary client URLs. Only browser vendors' push services are
  // accepted; https.request in web-push does not follow redirects.
  const host = url.hostname;
  const allowed = ['fcm.googleapis.com', 'updates.push.services.mozilla.com', 'web.push.apple.com'].includes(host) || /^[a-z0-9-]+\.notify\.windows\.com$/.test(host);
  if (!allowed || url.protocol !== 'https:' || url.port && url.port !== '443' || url.username || url.password || url.hash || url.href.length > 2048 || url.pathname.length < 2) throw Error('This browser notification service is not supported.');
  if (!decode(value.keys?.auth, 16) || !decode(value.keys?.p256dh, 65)) throw Error('Invalid browser notification keys.');
  try { const e = createECDH('prime256v1'); e.generateKeys(); e.computeSecret(Buffer.from(value.keys.p256dh, 'base64url')); } catch { throw Error('Invalid browser notification keys.'); }
  return { endpoint: url.href, keys: { auth: value.keys.auth, p256dh: value.keys.p256dh } };
}

export function socialPushConfig(env = process.env) {
  const publicKey = env.SOCIAL_WEB_PUSH_PUBLIC_KEY || '';
  const privateKey = env.SOCIAL_WEB_PUSH_PRIVATE_KEY || '';
  const subject = env.SOCIAL_WEB_PUSH_SUBJECT || '';
  let valid = decode(publicKey, 65) && decode(privateKey, 32) && /^(https:\/\/[^\s]+|mailto:[^\s@]+@[^\s@]+)$/.test(subject);
  if (valid) {
    try { const e = createECDH('prime256v1'); e.setPrivateKey(Buffer.from(privateKey, 'base64url')); valid = e.getPublicKey().equals(Buffer.from(publicKey, 'base64url')); } catch { valid = false; }
  }
  const enabled = valid && env.SOCIAL_WEB_PUSH_ENABLED !== 'false';
  return { enabled, publicKey: enabled ? publicKey : null, native: false, reason: enabled ? null : 'Background browser notifications are not configured yet.' };
}

export function createSocialPush({ database, authenticate, env = process.env, logger = console, sender = webpush.sendNotification.bind(webpush), autoStart = true, now = Date.now } = {}) {
  let timer, busy = false, stopped = false;
  const rpc = async (actor, action, data = {}) => {
    const r = await database.rpc('korlix_social_push_v1', { p_actor: actor, p_action: action, p_data: data });
    if (r.error) throw Object.assign(Error(r.error.message), { code: r.error.code });
    if (r.data == null) throw Error('Notification storage unavailable');
    return r.data;
  };
  const tick = async () => {
    if (busy || stopped || !database || !socialPushConfig(env).enabled) return;
    busy = true;
    try {
      const { items = [] } = await rpc(null, 'claim');
      await Promise.all(items.map(async item => {
        let attempted = false;
        try {
          const { delivery } = await rpc(null, 'authorize', { id: item.id, lease: item.lease });
          if (!delivery) return;
          const subscription = validateSocialPushSubscription(delivery.subscription);
          const seconds = Math.floor((Date.parse(delivery.expires_at) - now()) / 1000);
          if (seconds <= 0) { await rpc(null, 'finish', { id: item.id, lease: item.lease, status: 'cancelled' }); return; }
          const payload = JSON.stringify({ kind: delivery.kind, binding: delivery.binding, eventId: delivery.event_id,
            expiresAt: delivery.expires_at, silent: delivery.silent === true, url: '/app/?social=1', title: 'KORLIX Social',
            body: delivery.kind === 'online' ? 'A selected connection is online. Open KORLIX Social to see who.' : delivery.kind === 'call' ? 'You have an incoming call. Open KORLIX Social to answer.' : 'You have a new message. Open KORLIX Social to read it.' });
          attempted = true;
          await sender(subscription, payload, { TTL: Math.min(seconds, delivery.kind === 'call' ? 45 : 300), urgency: delivery.kind === 'call' ? 'high' : 'normal',
            topic: createHash('sha256').update(`${delivery.kind}:${delivery.event_id}`).digest('base64url').slice(0, 32), timeout: 8000,
            vapidDetails: { publicKey: env.SOCIAL_WEB_PUSH_PUBLIC_KEY, privateKey: env.SOCIAL_WEB_PUSH_PRIVATE_KEY, subject: env.SOCIAL_WEB_PUSH_SUBJECT } });
          await rpc(null, 'finish', { id: item.id, lease: item.lease, status: 'accepted' });
        } catch (error) {
          // No retry after an uncertain network result: push providers do not
          // support idempotency keys. Provider 429/5xx explicitly reject sends.
          const code = Number(error.statusCode);
          const status = [404, 410].includes(code) ? 'expired' : code === 429 || code >= 500 && code <= 599 ? 'retry' : attempted && !Number.isFinite(code) ? 'unknown' : 'failed';
          try { await rpc(null, 'finish', { id: item.id, lease: item.lease, status }); } catch { /* lease expiry remains uncertain, never replayed */ }
          logger.warn?.('Social notification delivery deferred', { status });
        }
      }));
    } catch { logger.warn?.('Social notification queue unavailable'); }
    finally { busy = false; }
  };
  const register = app => {
    const route = action => async (req, res) => {
      res.set('Cache-Control', 'no-store');
      try {
        const user = await authenticate(req, res); if (!user) return;
        const data = req.method === 'GET' ? req.query : req.body;
        if (!data || typeof data !== 'object' || Array.isArray(data) || Buffer.byteLength(JSON.stringify(data)) > 6000) return res.status(400).json({ error: 'Invalid notification settings.' });
        if (action === 'push_config') {
          await rpc(user.id, 'state');
          return res.json(socialPushConfig(env));
        }
        if (action === 'push_state') return res.json({ ...await rpc(user.id, 'state'), ...socialPushConfig(env) });
        if (!uuid.test(data.device || '')) return res.status(400).json({ error: 'Reopen notification settings on this browser.' });
        if (action === 'push_unsubscribe') return res.json(await rpc(user.id, 'unsubscribe', { device: data.device }));
        if (!socialPushConfig(env).enabled) return res.status(503).json({ error: socialPushConfig(env).reason });
        if (data.online !== undefined && typeof data.online !== 'boolean') return res.status(400).json({ error: 'Choose your online notification preference.' });
        if (!uuid.test(data.binding || '') || typeof data.messages !== 'boolean' || typeof data.calls !== 'boolean') return res.status(400).json({ error: 'Choose your notification preferences.' });
        let subscription;
        try { subscription = validateSocialPushSubscription(data.subscription); } catch (error) { return res.status(400).json({ error: error.message }); }
        return res.json(await rpc(user.id, 'subscribe', { device: data.device, binding: data.binding, messages: data.messages, calls: data.calls, ...(data.online === undefined ? {} : {online: data.online}), subscription }));
      } catch (error) {
        const status = { '42501': 403, P0001: 400, '54000': 429, '23505': 409 }[error.code] || 503;
        return res.status(status).json({ error: status === 503 ? 'Notification settings could not be confirmed. Refresh before retrying.' : error.message });
      }
    };
    for (const action of ['push_config', 'push_state']) app.get(`/api/social/${action}`, route(action));
    for (const action of ['push_subscribe', 'push_unsubscribe']) app.post(`/api/social/${action}`, route(action));
  };
  if (autoStart && database && socialPushConfig(env).enabled) { timer = setInterval(() => void tick(), 5000); timer.unref?.(); }
  return { register, tick, stop() { stopped = true; clearInterval(timer); } };
}
