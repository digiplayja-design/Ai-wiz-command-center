// Transactional transport only. Account ownership, verified reply-to, consent,
// quotas, suppression and durable dispatch claims belong to the calling service.
// Resend's idempotency keys expire after 24 hours. Persist the exact wire payload
// and stop ambiguous retries before that deadline; never give a retry a new ID.
// API contract: https://resend.com/docs/api-reference/emails/send-email
// https://resend.com/docs/dashboard/emails/idempotency-keys
import { createHash } from 'node:crypto';

const ENDPOINT = 'https://api.resend.com/emails';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CONTROLS = /[\u0000-\u001f\u007f]/;
const BODY_CONTROLS = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;
const REQUIRED_ENVIRONMENT = Object.freeze(['RESEND_API_KEY', 'KORLIX_AGENT_EMAIL_FROM']);
const MAX_PDF_BYTES = 8 * 1024 * 1024;
const MAX_BODY_BYTES = 128 * 1024;
const MAX_RESPONSE_BYTES = 32 * 1024;
const INPUT_KEYS = new Set(['id', 'to', 'subject', 'text', 'html', 'attachments', 'replyTo']);

export class FieldProofEmailProviderError extends Error {
  constructor(message, { code, statusCode = 503, outcome = 'not_sent', retryable = false, retryAfterSeconds = null } = {}) {
    super(message);
    this.name = 'FieldProofEmailProviderError';
    this.code = code;
    this.statusCode = statusCode;
    this.outcome = outcome;
    this.retryable = retryable;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

function failure(code, message, options = {}) {
  throw new FieldProofEmailProviderError(message, { code, ...options });
}

function invalid() {
  failure('fieldproof_email_payload_invalid', 'The FieldProof email is invalid. Review the saved report and recipient.', { statusCode: 400 });
}

// A deliberately narrow single-mailbox syntax: no display names, comments,
// address lists, quoted local parts or SMTP headers in recipient/reply-to input.
function address(value) {
  if (typeof value !== 'string' || CONTROLS.test(value)) invalid();
  const result = value.trim();
  if (result.length > 254) invalid();
  const match = /^([A-Za-z0-9!#$%&'*+\-/=?^_`{|}~.]+)@([A-Za-z0-9.-]+)$/.exec(result);
  if (!match || match[1].length > 64 || match[1].startsWith('.') || match[1].endsWith('.') || match[1].includes('..')) invalid();
  const labels = match[2].split('.');
  if (labels.length < 2 || labels.some(label => !/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label)) || !/[A-Za-z]/.test(labels.at(-1))) invalid();
  return `${match[1]}@${match[2].toLowerCase()}`;
}

function fromAddress(value) {
  if (typeof value !== 'string' || value.length > 500 || CONTROLS.test(value)) invalid();
  const trimmed = value.trim();
  const named = /^([^<>";,]+) <([^<>]+)>$/.exec(trimmed);
  if (!named) return address(trimmed);
  if (!named[1].trim() || named[1].length > 160) invalid();
  return `${named[1].trim()} <${address(named[2])}>`;
}

function content(value, required = false) {
  if (value == null && !required) return '';
  if (typeof value !== 'string' || BODY_CONTROLS.test(value) || Buffer.byteLength(value, 'utf8') > MAX_BODY_BYTES || (required && !value.trim())) invalid();
  return value;
}

function pdfAttachments(value) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 1) invalid();
  return value.map(file => {
    if (!file || typeof file !== 'object' || Array.isArray(file) || Object.keys(file).some(key => !['filename', 'content'].includes(key))) invalid();
    const { filename, content: encoded } = file;
    if (typeof filename !== 'string' || filename.length > 120 || !/^[A-Za-z0-9][A-Za-z0-9 ._-]*\.pdf$/i.test(filename) || filename.includes('..')) invalid();
    if (typeof encoded !== 'string' || !encoded.length || encoded.length > 4 * Math.ceil(MAX_PDF_BYTES / 3) || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) invalid();
    const bytes = Buffer.from(encoded, 'base64');
    if (bytes.length > MAX_PDF_BYTES || bytes.toString('base64') !== encoded || !/^%PDF-(?:1\.[0-9]|2\.0)[\r\n ]/.test(bytes.subarray(0, 12).toString('ascii')) || !/%%EOF\s*$/.test(bytes.subarray(-1024).toString('latin1'))) invalid();
    return { filename, content: encoded };
  });
}

function wire(input, from, namespace) {
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key => !INPUT_KEYS.has(key))) invalid();
  if (typeof input.id !== 'string' || !UUID.test(input.id)) invalid();
  if (typeof input.subject !== 'string' || !input.subject.trim() || input.subject.length > 200 || CONTROLS.test(input.subject)) invalid();
  const payload = {
    from,
    to: [address(input.to)],
    subject: input.subject.trim(),
    text: content(input.text, true),
    // Resend returns this server-owned tag in signed delivery webhooks, allowing
    // a bounce to find its authorized dispatch even before its HTTP receipt saves.
    tags: [{ name: `${namespace}_delivery`, value: input.id.toLowerCase() }],
    // The caller must derive this from fresh authenticated account data, never
    // from a job's customer email or an arbitrary user-supplied setting.
    reply_to: address(input.replyTo),
  };
  const html = content(input.html);
  if (html) payload.html = html;
  const attachments = pdfAttachments(input.attachments);
  if (attachments.length) payload.attachments = attachments;
  return { body: JSON.stringify(payload), idempotencyKey: `${namespace === 'workforce' ? 'wf' : namespace === 'crm' ? 'crm' : 'fp'}-email:${input.id.toLowerCase()}` };
}

async function responseBody(response) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('No provider response');
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_RESPONSE_BYTES) throw new Error('Provider response too large');
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally {
    await reader.cancel().catch(() => {});
  }
}

function retryAfter(response) {
  const seconds = response.headers?.get('retry-after');
  return typeof seconds === 'string' && /^\d{1,6}$/.test(seconds)
    ? Math.min(3600, Math.max(1, Number(seconds))) : null;
}

export function createFieldProofEmailProvider({ environment = process.env, fetchImpl = globalThis.fetch, namespace = 'fieldproof' } = {}) {
  if (!['fieldproof', 'workforce', 'crm'].includes(namespace)) throw new Error('Unknown transactional email namespace');
  const configuration = () => {
    const apiKey = environment.RESEND_API_KEY;
    let from = null;
    try { from = fromAddress(environment.KORLIX_AGENT_EMAIL_FROM); } catch {}
    const keyReady = typeof apiKey === 'string' && apiKey.length > 0 && apiKey.length <= 4096 && !/\s/.test(apiKey);
    return { apiKey, from, keyReady, ready: keyReady && !!from && typeof fetchImpl === 'function' };
  };
  return Object.freeze({
    status() {
      const config = configuration();
      return Object.freeze({
        provider: 'resend',
        ready: config.ready,
        reason: config.ready ? null : !config.keyReady ? 'provider_key_unavailable' : !config.from ? 'sender_unavailable' : 'transport_unavailable',
        senderFingerprint: config.from ? createHash('sha256').update(config.from).digest('hex') : null,
        requiredEnvironment: REQUIRED_ENVIRONMENT,
      });
    },
    async send(input) {
      const config = configuration();
      if (!config.ready) failure('fieldproof_email_provider_unavailable', 'FieldProof email delivery is not configured.');
      const request = wire(input, config.from, namespace);
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 30000);
      let response, body = null;
      try {
        try {
          response = await fetchImpl(ENDPOINT, {
            method: 'POST', redirect: 'error', signal: controller.signal,
            headers: { Authorization: `Bearer ${config.apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': request.idempotencyKey },
            body: request.body,
          });
        } catch {
          failure('fieldproof_email_transport_uncertain', 'The email provider outcome is not yet known. Check the saved delivery record.', { outcome: 'uncertain', retryable: true });
        }
        // Preserve definite HTTP rejection semantics even if its response body
        // is missing, malformed or oversized. Never expose provider error text.
        try { body = await responseBody(response); } catch {}
        if (response.status === 429) failure('fieldproof_email_rate_limited', 'The email provider is temporarily rate limited.', { statusCode: 429, retryable: true, retryAfterSeconds: retryAfter(response) });
        if (response.status === 409) {
          const concurrent = body?.name === 'concurrent_idempotent_requests';
          failure(concurrent ? 'fieldproof_email_dispatch_in_progress' : 'fieldproof_email_idempotency_conflict', 'This delivery requires reconciliation with its original provider request.', { statusCode: 409, outcome: 'uncertain', retryable: concurrent });
        }
        if (response.status >= 400 && response.status < 500 && response.status !== 408) {
          failure('fieldproof_email_provider_rejected', 'The email provider rejected this delivery. Review its sender and recipient settings.', { statusCode: 422 });
        }
        if (!response.ok || !body || typeof body !== 'object' || Array.isArray(body) || typeof body.id !== 'string' || !UUID.test(body.id) || body.error) {
          failure('fieldproof_email_receipt_uncertain', 'The email provider outcome is not yet known. Check the saved delivery record.', { outcome: 'uncertain', retryable: true });
        }
        return Object.freeze({ accepted: true, provider: 'resend', providerId: body.id.toLowerCase(), idempotencyKey: request.idempotencyKey });
      } finally {
        clearTimeout(timer);
      }
    },
  });
}

export { address as validateTransactionalEmailAddress };
