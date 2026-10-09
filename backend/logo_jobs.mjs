import crypto from 'node:crypto';
import studio from './logo_studio.cjs';
import quality from './chat_quality.cjs';

const TTL_MS = 30 * 60 * 1000;
const MAX_RESULT_BYTES = 96 * 1024 * 1024;
const fail = (message, statusCode = 400) => Object.assign(new Error(message), {statusCode});
const active = job => ['queued', 'processing'].includes(job.status);

function normalize(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw fail('Send a valid logo brief.');
  const brief = studio.logoBriefOptions(body);
  if (!brief) throw fail('Add your Logo Studio brand brief.');
  const requestId = body.clientRequestId;
  if (typeof requestId !== 'string' || !/^[A-Za-z0-9_-]{8,100}$/.test(requestId)) throw fail('A logo request ID is required.');
  if (typeof body.prompt !== 'string' || !body.prompt.trim() || body.prompt.length > 12000) throw fail('Add a logo description under 12,001 characters.');
  if (body.language != null && (typeof body.language !== 'string' || body.language.length > 32)) throw fail('Choose a supported language.');
  const {size} = quality.imageSettings(body);
  return {requestId, payload: {logoBrief: brief, prompt: body.prompt, imageSize: size,
    imageStyle: 'design', language: body.language || 'en'}};
}

export function registerLogoJobs(app, {requireUser, execute, log = () => {},
  now = Date.now, schedule = setImmediate} = {}) {
  const jobs = new Map();
  function clean() {
    for (const [id, job] of jobs) {
      if (!active(job) && now() - job.updatedAt > TTL_MS) jobs.delete(id);
    }
    let bytes = [...jobs.values()].reduce((n, job) => n + job.resultBytes, 0);
    for (const [id, job] of jobs) {
      if ((bytes <= MAX_RESULT_BYTES && jobs.size <= 128) || active(job)) continue;
      bytes -= job.resultBytes;
      jobs.delete(id);
    }
  }
  function view(job) {
    return {jobId: job.id, status: job.status, stage: job.stage,
      createdAt: new Date(job.createdAt).toISOString(), error: job.error || null,
      ...(job.status === 'completed' ? {result: job.result} : {})};
  }
  async function run(job, user, payload) {
    job.status = 'processing';
    job.stage = 'planning';
    try {
      const result = await execute({user, body: payload, onStage(stage) {
        if (['planning', 'rendering', 'finishing'].includes(stage)) job.stage = stage;
        job.updatedAt = now();
      }});
      job.result = result;
      job.resultBytes = Buffer.byteLength(JSON.stringify(result));
      job.stage = job.status = 'completed';
    } catch (error) {
      job.stage = job.status = 'failed';
      // Only planner errors and local validation have reviewed user-facing text.
      job.error = error?.logoDiagnostic || [400, 401, 403, 422, 429].includes(error?.statusCode)
        ? String(error.message).slice(0, 1000)
        : 'Logo completion could not be confirmed. Please check your results before starting another concept.';
      log({jobId: job.id, elapsedMs: now() - job.createdAt,
        httpStatus: error?.statusCode || 500, ...error?.logoDiagnostic});
    } finally {
      job.updatedAt = now();
      clean();
    }
  }

  app.post('/api/logo/jobs', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await requireUser(req);
      const {requestId, payload} = normalize(req.body);
      clean();
      const fingerprint = crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
      const owned = [...jobs.values()].filter(job => job.ownerId === user.id);
      const same = owned.find(job => job.requestId === requestId);
      if (same) {
        if (same.fingerprint !== fingerprint) throw fail('This request ID belongs to a different logo brief.', 409);
        return res.status(active(same) ? 202 : 200).json(view(same));
      }
      const pending = owned.find(active);
      if (pending) {
        if (pending.fingerprint === fingerprint) return res.status(202).json(view(pending));
        throw fail('Another logo is still processing. Let it finish before creating a different concept.', 409);
      }
      if ([...jobs.values()].filter(active).length >= 8) throw fail('Logo Studio is busy. Please try again shortly.', 503);
      const job = {id: `logo_${crypto.randomUUID()}`, ownerId: user.id, requestId, fingerprint,
        createdAt: now(), updatedAt: now(), status: 'queued', stage: 'queued', resultBytes: 0};
      jobs.set(job.id, job);
      res.status(202).json(view(job));
      schedule(() => { void run(job, user, payload); });
    } catch (error) {
      res.status(error.statusCode || 500).json({error: error.statusCode ? error.message : 'The logo job could not be started.'});
    }
  });

  app.get('/api/logo/jobs/:jobId', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await requireUser(req);
      clean();
      const job = jobs.get(req.params.jobId);
      if (!job || job.ownerId !== user.id) throw fail('This logo result is no longer available. It may have expired or the service restarted.', 404);
      res.json(view(job));
    } catch (error) {
      res.status(error.statusCode || 500).json({error: error.statusCode ? error.message : 'The logo status could not be checked.'});
    }
  });
}
