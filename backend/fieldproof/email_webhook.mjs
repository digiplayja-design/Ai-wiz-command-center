import { verifyKorlixAgentEmailResendWebhook } from '../korlix_agent_email_delivery.mjs';

const PATH = '/api/agent-email/resend/webhook';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SUPPRESSION_EVENTS = new Set(['email.bounced', 'email.complained', 'email.suppressed']);
const object = value => value && typeof value === 'object' && !Array.isArray(value);

// Register before the existing Agent Email handler. Both consumers must finish
// before the shared endpoint acknowledges an event. Repeated suppression must
// be idempotent in persistence; never cache webhook completion in this process.
export function registerFieldProofEmailWebhook(app, { emailService, environment = process.env, logger = console } = {}) {
  app.post(PATH, async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    let verified;
    try {
      verified = verifyKorlixAgentEmailResendWebhook({
        rawBody: req.korlixAgentEmailRawBody,
        headers: req.headers,
        secret: environment.KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET || environment.RESEND_WEBHOOK_SECRET,
      });
    } catch (error) {
      const status = [400, 401, 503].includes(error?.statusCode) ? error.statusCode : 401;
      return res.status(status).json({ ok: false, error: status === 503 ? 'Email webhook verification is unavailable.' : 'Invalid email webhook.', code: 'fieldproof_email_webhook_unverified' });
    }
    const event = verified.event;
    if (!object(event) || !SUPPRESSION_EVENTS.has(event.type) || !object(event.data)) return next();
    const providerId = event.data.email_id;
    if (typeof providerId !== 'string' || !UUID.test(providerId)) return next();
    const tag = object(event.data.tags) ? event.data.tags.fieldproof_delivery : null;
    const deliveryId = typeof tag === 'string' && UUID.test(tag) ? tag.toLowerCase() : null;
    try {
      if (typeof emailService?.suppressProviderEvent !== 'function') throw new Error('Persistence unavailable');
      // Only verified IDs and a fixed event kind cross into persistence. It must
      // derive account/email from the known dispatch row, never from webhook to,
      // From, metadata, provider diagnostic messages or client-selected accounts.
      // The signed tag permits matching an already-authorized dispatch before
      // its send response has persisted the provider ID; IDs may never conflict.
      await emailService.suppressProviderEvent({ providerId: providerId.toLowerCase(), deliveryId, reason: event.type });
    } catch {
      try { logger?.warn?.('FieldProof email webhook persistence is unavailable.'); } catch {}
      return res.status(503).json({ ok: false, error: 'Email delivery status could not be saved. Retry this webhook.', code: 'fieldproof_email_webhook_persistence_unavailable' });
    }
    return next();
  });
  return { path: PATH };
}
