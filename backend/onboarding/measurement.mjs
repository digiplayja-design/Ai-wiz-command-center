import {createHash, randomUUID} from 'node:crypto';
import {hasUnlimitedAccess} from '../security/developer_access.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const USER_ID = /^[0-9a-f-]{36}$/i;
const PLATFORMS = new Set(['android', 'ios', 'web', 'linux', 'macos', 'windows']);
const CLIENT_EVENTS = new Set([
  'app_open', 'registration_screen_viewed', 'registration_submit',
  'registration_validation_error', 'registration_transport_error',
  'confirmation_screen_viewed', 'login_screen_viewed',
]);
const CLIENT_ERRORS = new Set(['required_fields', 'password_length', 'eligibility', 'network', 'response']);

export function installationContext(req) {
  const device = req.get('X-Korlix-Device-Id');
  // Do not use email, advertising IDs, device labels, IP addresses, or credentials.
  if (typeof device !== 'string' || !/^korlix_[A-Za-z0-9_-]{8,140}$/.test(device)) return null;
  const platform = req.get('X-Korlix-Platform');
  return {
    installation_hash: createHash('sha256').update(`korlix-onboarding-v1:${device}`).digest('hex'),
    platform: PLATFORMS.has(platform) ? platform : 'unknown',
  };
}

export function clientRows(req) {
  const context = installationContext(req);
  const events = req.body?.events;
  if (!context || !Array.isArray(events) || events.length < 1 || events.length > 12) return null;
  if (Object.keys(req.body).some(key => key !== 'events')) return null;
  const rows = [];
  for (const event of events) {
    if (!event || typeof event !== 'object' || Array.isArray(event)
      || Object.keys(event).some(key => !['id', 'name', 'new_setup', 'error_code'].includes(key))
      || !UUID.test(event.id || '') || !CLIENT_EVENTS.has(event.name)
      || (event.new_setup !== undefined && (event.name !== 'app_open' || typeof event.new_setup !== 'boolean'))
      || (event.error_code !== undefined && !CLIENT_ERRORS.has(event.error_code))) return null;
    rows.push({id: event.id, ...context, source: 'client', event_name: event.name,
      new_setup: event.name === 'app_open' ? event.new_setup === true : null,
      error_code: event.error_code ?? null});
  }
  return rows;
}

// Bounded per-process limiter. Forwarded-IP headers are deliberately not trusted.
function publicLimiter() {
  const entries = new Map();
  let total = {time: 0, count: 0};
  return req => {
    const now = Date.now();
    if (now - total.time > 60_000) { total = {time: now, count: 0}; entries.clear(); }
    if (++total.count > 600) return false;
    const key = `${req.socket?.remoteAddress || 'unknown'}:${installationContext(req)?.installation_hash || 'missing'}`;
    const count = (entries.get(key) || 0) + 1;
    entries.set(key, count);
    return count <= 30;
  };
}

export function createOnboardingMeasurement({database, requireUser, now = () => new Date(), warn = console.warn}) {
  const allow = publicLimiter();
  const allowAuthObservation = publicLimiter();
  let lastWarning = 0;
  let lastPrune = 0;
  function warning() {
    if (Date.now() - lastWarning > 60_000) {
      lastWarning = Date.now();
      warn('Onboarding measurement unavailable; account access is unaffected.');
    }
  }
  async function write(rows) {
    if (!database) return false;
    try {
      const {error} = await database.from('korlix_onboarding_events')
        .upsert(rows, {onConflict: 'id', ignoreDuplicates: true})
        .abortSignal(AbortSignal.timeout(4000));
      if (error) throw error;
      if (Date.now() - lastPrune > 3_600_000) {
        lastPrune = Date.now();
        // Small batches; the next hour continues cleanup if a backlog exists.
        void Promise.resolve(database.rpc('korlix_prune_onboarding_events')
          .abortSignal(AbortSignal.timeout(4000))).then(({error}) => {if (error) warning();}).catch(warning);
      }
      return true;
    } catch { warning(); return false; }
  }
  function record(req, name, {userId = null, errorCode = null} = {}) {
    const context = installationContext(req);
    if (!context) return;
    void write([{id: randomUUID(), ...context, source: 'server', event_name: name,
      user_id: USER_ID.test(userId || '') ? userId : null, error_code: errorCode}]);
  }
  function observeAuth(kind) {
    return (req, res, next) => {
      // Drop excess observations, never rate-limit authentication with analytics.
      if (!allowAuthObservation(req)) return next();
      record(req, `${kind}_attempt`);
      const send = res.json;
      let observed = false;
      res.json = function (body) {
        if (!observed) {
          observed = true;
          const success = res.statusCode < 400 && body?.success === true;
          if (!success) {
            const code = res.statusCode >= 500 ? 'server_error'
              : res.statusCode === 429 ? 'rate_limited'
              : String(body?.code || '').startsWith('SIGNUP_') ? 'eligibility' : 'auth_rejected';
            record(req, `${kind}_rejected`, {errorCode: code});
          } else {
            // A signup response with no session does NOT prove a new or confirmed
            // account: Supabase can mask an already registered email address.
            if (kind === 'signup') record(req, 'signup_accepted');
            if (body?.session?.access_token && body?.user?.id) {
              record(req, 'sign_in_succeeded', {userId: body.user.id});
            }
          }
        }
        return send.call(this, body);
      };
      next();
    };
  }
  async function ingest(req, res) {
    if (!allow(req)) return res.status(429).set('Retry-After', '60').json({error: 'Try later.'});
    const rows = clientRows(req);
    if (!rows) return res.status(400).json({error: 'Invalid event batch.'});
    if (!await write(rows)) return res.status(503).json({error: 'Measurement temporarily unavailable.'});
    return res.status(202).json({accepted: rows.length});
  }
  async function summary(req, res) {
    try {
      const user = await requireUser(req);
      if (!hasUnlimitedAccess(user)) return res.status(403).json({error: 'Administrator access required.'});
      const days = Number(req.query.days || 7);
      const platform = req.query.platform || 'android';
      if (![1, 7, 30].includes(days) || !PLATFORMS.has(platform)) {
        return res.status(400).json({error: 'Choose 1, 7 or 30 days and a supported platform.'});
      }
      if (!database) return res.status(503).json({error: 'Measurement not configured.'});
      const end = now();
      const start = new Date(end.getTime() - days * 86400_000);
      const {data, error} = await database.rpc('korlix_onboarding_summary', {
        p_start: start.toISOString(), p_end: end.toISOString(), p_platform: platform,
      }).abortSignal(AbortSignal.timeout(8000));
      if (error) throw error;
      return res.json({start: start.toISOString(), end: end.toISOString(), platform, ...data});
    } catch (error) {
      const status = [401, 403].includes(error.statusCode) ? error.statusCode : 503;
      return res.status(status).json({error: status === 401 ? 'Sign in required.' : 'Report unavailable.'});
    }
  }
  return {observeAuth, ingest, summary};
}
