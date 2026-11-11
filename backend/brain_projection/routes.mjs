import {createHash} from 'node:crypto';
import {createAccountRequestLimiter} from '../security/account_request_limiter.mjs';
import {ProjectionError, publicProjectionConfiguration, normalizeQuery, normalizeQuestion,
  normalizePlace, directProjectionAnswer, resolvePlace, researchPlace} from './core.mjs';
import {registerProjectionRenderer} from './renderer.mjs';
import {brainDirectionLinks} from './directions.mjs';

function publicFailure(error) {
  if (error instanceof ProjectionError) return {status: error.statusCode, code: error.code, error: error.message};
  // Preserve authentication/infrastructure status without echoing provider text,
  // account metadata, URLs containing API keys or database diagnostics.
  const status = [401, 403, 409, 429, 503].includes(error?.statusCode) ? error.statusCode : 503;
  const messages = {401: 'Sign in again to use Projection Mode.', 403: 'This account cannot access Projection Mode.',
    409: 'Reconnect your account and try again.', 429: 'Your request allowance is unavailable. Please try again later.',
    503: 'Projection is temporarily unavailable. Please try again.'};
  return {status, code: 'projection_unavailable', error: messages[status]};
}

export function registerBrainProjection(app, {requireUser, environment = process.env, fetchImpl = fetch,
  clientFactory, access, charge, directionsAccess = async () => false, answerCredits = 0, now = Date.now,
  resolve = options => resolvePlace(options), research = options => researchPlace(options)} = {}) {
  if (typeof requireUser !== 'function') throw new Error('Projection requires the existing authentication boundary.');
  registerProjectionRenderer(app, {environment});
  const takeGeocode = createAccountRequestLimiter({windowMs: 60000, maxAttempts: 20, now});
  const takeResearch = createAccountRequestLimiter({windowMs: 60000, maxAttempts: 6, now});
  const active = new Map(), recent = new Map();
  const credits = Number.isSafeInteger(answerCredits) && answerCredits > 0 ? answerCredits : 0;
  const cost = {answerCredits: credits, answerCostLabel: credits ? `${credits} credits per sourced answer` : 'Research allowance unavailable'};
  const researchConfigured = () => Boolean(publicProjectionConfiguration(environment).answersAvailable &&
    typeof clientFactory === 'function' && typeof access === 'function' && typeof charge === 'function' && credits);
  const route = fn => async (req, res) => {
    res.set({'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    try {
      const user = await requireUser(req);
      if (!user?.id || typeof user.id !== 'string') throw Object.assign(new Error('authentication required'), {statusCode: 401});
      // Independent of the server's global JSON parser limit. Registration also
      // installs an 8 KiB parser before that parser in production server.js.
      if (req.method === 'POST' && (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
          Buffer.byteLength(JSON.stringify(req.body)) > 8192)) {
        throw new ProjectionError('Send a shorter Projection request.', 'projection_invalid_input');
      }
      await fn({req, res, user});
    } catch (error) {
      const failure = publicFailure(error);
      if (Number.isFinite(error?.retryAfter)) res.set('Retry-After', String(Math.ceil(error.retryAfter)));
      if (!res.headersSent) res.status(failure.status).json({code: failure.code, error: failure.error});
    }
  };

  app.get('/api/brain-projection/config', route(async ({res, user}) => {
    res.json({...publicProjectionConfiguration(environment), answersAvailable: researchConfigured(),
      directionsAvailable: await directionsAccess(user) === true, ...cost});
  }));

  app.post('/api/brain-projection/directions', route(async ({req, res, user}) => {
    if (await directionsAccess(user) !== true) {
      throw new ProjectionError('Address routing is not enabled for this account.', 'directions_not_enabled', 403);
    }
    res.json(brainDirectionLinks(req.body));
  }));

  app.post('/api/brain-projection/resolve', route(async ({req, res, user}) => {
    const query = normalizeQuery(req.body.query);
    takeGeocode(user.id);
    res.json(await resolve({query, environment, fetchImpl}));
  }));

  app.post('/api/brain-projection/answer', route(async ({req, res, user}) => {
    const question = normalizeQuestion(req.body.question);
    // Availability answers are deterministic and do not invoke a model, charge
    // research credits, depend on a place, or start/stop a voice session.
    const direct = directProjectionAnswer(question);
    if (direct) return res.json(direct);
    const place = normalizePlace(req.body.place);
    if (!researchConfigured()) throw new ProjectionError('Place research is not connected yet.', 'projection_research_not_configured', 503);
    const key = createHash('sha256').update(JSON.stringify({question, place})).digest('hex');
    for (const [owner, saved] of recent) if (saved.until <= now()) recent.delete(owner);
    const cached = recent.get(user.id);
    if (cached?.key === key) return res.json({...cached.result, replayed: true});
    const inFlight = active.get(user.id);
    if (inFlight) {
      if (inFlight.key === key) return res.json({...await inFlight.promise, replayed: true});
      throw new ProjectionError('Rici is still researching your previous question. Wait for it to finish.', 'projection_research_busy', 409);
    }
    if (active.size >= 8) throw new ProjectionError('Place research is busy. Please try again shortly.', 'projection_research_busy', 503);
    takeResearch(user.id);
    const work = (async () => {
      const allowance = await access(user);
      if (!allowance?.allowed) throw new ProjectionError('Your existing search allowance is unavailable. Check your account allowance before trying again.', 'projection_allowance', 429);
      let result;
      try {
        result = await research({client: clientFactory(), question, place, now: now()});
      } catch (error) {
        if (error instanceof ProjectionError) throw error;
        throw new ProjectionError('Place research is temporarily unavailable. Please try again.', 'projection_research_unavailable', 503);
      }
      // No charge for unsupported answers, provider failures or no-source states.
      // The research function validates every source against the provider's
      // retrieved-source evidence before this boundary is reached.
      if (result.sources?.length) await charge(user, allowance);
      const payload = {...result, creditsUsed: result.sources?.length ? credits : 0};
      recent.set(user.id, {key, result: payload, until: now() + 30000});
      while (recent.size > 500) recent.delete(recent.keys().next().value);
      return payload;
    })();
    active.set(user.id, {key, promise: work});
    try { res.json(await work); }
    finally { active.delete(user.id); }
  }));
  return {version: 'projection-v1'};
}
