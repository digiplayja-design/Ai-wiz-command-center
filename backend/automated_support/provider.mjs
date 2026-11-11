import {createHmac, timingSafeEqual} from 'node:crypto';
import {validateTransactionalEmailAddress} from '../fieldproof/email_provider.mjs';
import {supportThreadSecret} from './secrets.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const API = 'https://api.resend.com';
const truthy = value => ['1','true','yes','on','enabled'].includes(String(value ?? '').toLowerCase());
const address = value => validateTransactionalEmailAddress(value).toLowerCase();

export class SupportProviderError extends Error {
  constructor(code, {uncertain = false, statusCode = 503, retryable = false} = {}) {
    super('Support email delivery could not be completed. Check the delivery record.');
    this.code = code;
    this.statusCode = statusCode;
    this.uncertain = uncertain;
    this.retryable = retryable;
  }
}
const fail = (code, options) => {throw new SupportProviderError(code, options);};

function secret(environment) {
  const key = supportThreadSecret(environment);
  if (!key) fail('support_reply_routing_unavailable');
  return key;
}
function compactId(id) {
  if (!UUID.test(id || '')) fail('support_case_invalid', {statusCode:400});
  return Buffer.from(id.replaceAll('-', ''), 'hex').toString('base64url');
}
function expandId(token) {
  if (!/^[A-Za-z0-9_-]{22}$/.test(token || '')) return null;
  const bytes = Buffer.from(token, 'base64url');
  if (bytes.length !== 16 || bytes.toString('base64url') !== token) return null;
  const hex = bytes.toString('hex');
  const id = [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
  return UUID.test(id) ? id : null;
}
function signature(profile, caseId, environment) {
  return createHmac('sha256', secret(environment))
    .update(JSON.stringify([profile.id, caseId, address(profile.fromEmail), address(profile.replyTo)]))
    .digest('base64url').slice(0,16);
}

// The token binds both the case and the enrolled support identity. A report ID
// or a customer-controlled subject is never sufficient to select a case.
export function supportReplyAddress(profile, caseId, environment = process.env) {
  const [local, domain] = address(profile.replyTo).split('@');
  const result = local + '+k.' + compactId(caseId) + '.' + signature(profile, caseId.toLowerCase(), environment) + '@' + domain;
  // Keep the case-sensitive base64url token in the local part intact.
  return validateTransactionalEmailAddress(result);
}

export function matchSupportReplyAddress(value, profiles, environment = process.env) {
  let recipient;
  try {recipient = address(value);} catch {return null;}
  const match = /^(.+)\+k\.([A-Za-z0-9_-]{22})\.([A-Za-z0-9_-]{16})@([^@]+)$/.exec(value);
  if (!match) return null;
  const caseId = expandId(match[2]);
  if (!caseId) return null;
  const base = (match[1] + '@' + match[4]).toLowerCase();
  const candidates = profiles.filter(profile => profile.receivingVerified === true &&
    address(profile.replyTo) === base &&
    (profile.inboundAddresses || []).some(candidate => address(candidate) === base));
  for (const profile of candidates) {
    const expected = signature(profile, caseId, environment);
    const actual = match[3];
    if (actual.length === expected.length &&
        timingSafeEqual(Buffer.from(actual), Buffer.from(expected))) {
      return {profile, caseId, recipient};
    }
  }
  return null;
}

async function readJson(response, maximum) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Provider response missing');
  const chunks = [];
  let bytes = 0;
  try {
    for (;;) {
      const item = await reader.read();
      if (item.done) break;
      bytes += item.value.byteLength;
      if (bytes > maximum) throw new Error('Provider response exceeds limit');
      chunks.push(Buffer.from(item.value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally {
    await reader.cancel().catch(() => {});
  }
}

function apiKey(environment) {
  const key = environment.RESEND_API_KEY;
  if (typeof key !== 'string' || !key || key.length > 4096 || /\s/.test(key)) fail('support_provider_unavailable');
  return key;
}
function oneLine(value, maximum) {
  if (typeof value !== 'string' || !value.trim() || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    fail('support_message_invalid', {statusCode:400});
  }
  return value.trim();
}

export function createAutomatedSupportResendProvider({environment = process.env, fetcher = globalThis.fetch} = {}) {
  return Object.freeze({
    async send({profile, caseRecord, message, idempotencyKey}) {
      if (!truthy(environment.KORLIX_AUTOMATED_SUPPORT_ENABLED) ||
          String(environment.KORLIX_AUTOMATED_SUPPORT_PAUSED).toLowerCase() !== 'false' ||
          truthy(environment.KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE)) fail('support_delivery_paused');
      if (profile.senderVerified !== true || profile.receivingVerified !== true ||
          caseRecord.reporterVerified !== true) fail('support_identity_unverified');
      if (profile.fingerprint && message.profileFingerprint !== profile.fingerprint) {
        fail('support_sender_configuration_changed', {statusCode:409});
      }
      if (message.caseId !== caseRecord.id || message.profileId !== profile.id ||
          message.ownerUid !== profile.ownerUid || caseRecord.profileId !== profile.id ||
          caseRecord.ownerUid !== profile.ownerUid || !UUID.test(message.id || '')) {
        fail('support_dispatch_mismatch', {statusCode:400});
      }
      const from = address(profile.fromEmail);
      const to = address(caseRecord.reporterEmail);
      if (to === from || to === address(profile.replyTo) ||
          (profile.inboundAddresses || []).some(value => address(value) === to)) fail('support_reply_loop');
      const subject = oneLine(message.subject || caseRecord.subject, 200);
      if (typeof message.text !== 'string' || !message.text.trim() ||
          Buffer.byteLength(message.text) > 64000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(message.text)) {
        fail('support_message_invalid', {statusCode:400});
      }
      // The provider accepts only the deterministic key chosen for this durable
      // dispatch. A retry cannot choose a new identity or recipient.
      const stableKey = 'korlix-support/' + message.id;
      if (idempotencyKey && idempotencyKey !== stableKey) fail('support_dispatch_key_mismatch', {statusCode:400});
      const displayName = oneLine(profile.displayName || 'KORLIX Support', 120);
      if (/[<>"\\]/.test(displayName)) fail('support_sender_invalid', {statusCode:400});
      const payload = {
        from: displayName + ' <' + from + '>',
        to: [to],
        reply_to: supportReplyAddress(profile, caseRecord.id, environment),
        subject,
        text: message.text,
        headers: {'Auto-Submitted':'auto-replied', 'X-Auto-Response-Suppress':'All'},
        tags: [{name:'support_delivery',value:message.id}],
      };
      if (message.inReplyTo) {
        if (typeof message.inReplyTo !== 'string' || message.inReplyTo.length > 998 ||
            !/^<[^<>\s\x00-\x1f\x7f]+>$/.test(message.inReplyTo)) {
          fail('support_thread_header_invalid', {statusCode:400});
        }
        payload.headers['In-Reply-To'] = message.inReplyTo;
        payload.headers.References = message.inReplyTo;
      }
      const key = apiKey(environment);
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 15000);
      try {
        let response;
        try {
          response = await fetcher(API + '/emails', {
            method:'POST', redirect:'error', signal:controller.signal,
            headers:{Authorization:'Bearer ' + key,'Content-Type':'application/json','Idempotency-Key':stableKey},
            body:JSON.stringify(payload),
          });
        } catch {fail('support_provider_outcome_unknown', {uncertain:true});}
        let result;
        try {result = await readJson(response, 32768);} catch {}
        if (response.status === 429) fail('support_provider_rate_limited', {statusCode:429,retryable:true});
        if (response.status >= 400 && response.status < 500 && ![408,409].includes(response.status)) {
          fail('support_provider_rejected', {statusCode:422});
        }
        if (!response.ok || !UUID.test(result?.id || '') || result?.error) {
          fail('support_provider_outcome_unknown', {uncertain:true});
        }
        return {accepted:true, providerMessageId:result.id.toLowerCase()};
      } finally {
        clearTimeout(timer);
      }
    },
    async receive(emailId) {
      if (!UUID.test(emailId || '')) fail('support_inbound_id_invalid', {statusCode:400});
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 15000);
      try {
        const response = await fetcher(API + '/emails/receiving/' + emailId + '?html_format=cid', {
          redirect:'error', signal:controller.signal,
          headers:{Authorization:'Bearer ' + apiKey(environment),Accept:'application/json'},
        });
        if (!response.ok) fail('support_inbound_fetch_unavailable');
        const result = await readJson(response, 2 * 1024 * 1024);
        if (result?.id?.toLowerCase() !== emailId.toLowerCase()) fail('support_inbound_receipt_mismatch');
        return result;
      } catch (error) {
        if (error instanceof SupportProviderError) throw error;
        fail('support_inbound_fetch_unavailable');
      } finally {
        clearTimeout(timer);
      }
    },
  });
}
