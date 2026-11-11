import {createHmac} from 'node:crypto';

const THREAD_KEY_CONTEXT = 'korlix/automated-support/reply-address-key/v1';

// Match the existing Agent Email verifier's environment normalization. Never
// return any of these values through an API, readiness response, or log.
const webhookSetting = value => String(value ?? '')
  .replace(/[\u0000-\u001F\u007F]/g, ' ').replace(/\s+/g, ' ').trim().slice(0,1000);

export function supportLegacyWebhookEnabled(environment = process.env) {
  return String(environment.KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK).toLowerCase() === 'true';
}

export function legacyResendWebhookSecret(environment = process.env) {
  return webhookSetting(environment.KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET) ||
    webhookSetting(environment.RESEND_WEBHOOK_SECRET);
}

export function supportWebhookSecret(environment = process.env) {
  const explicit = environment.KORLIX_SUPPORT_WEBHOOK_SECRET;
  if (explicit !== undefined && explicit !== null && explicit !== '') return webhookSetting(explicit);
  return supportLegacyWebhookEnabled(environment) ? legacyResendWebhookSecret(environment) : '';
}

function webhookKey(value) {
  if (typeof value !== 'string' || !value.startsWith('whsec_')) return null;
  const encoded = value.slice(6);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) return null;
  const bytes = Buffer.from(encoded,'base64');
  if (!bytes.length || bytes.toString('base64').replace(/=+$/,'') !== encoded.replace(/=+$/,'')) return null;
  return bytes;
}

export function supportWebhookConfigured(environment = process.env) {
  // The shared endpoint must use its existing verifier key, even when a separate
  // support endpoint has an explicit secret. An unrelated override cannot make
  // a missing shared verifier appear ready.
  const value = supportLegacyWebhookEnabled(environment)
    ? legacyResendWebhookSecret(environment) : supportWebhookSecret(environment);
  return Boolean(webhookKey(value));
}

export function supportThreadSecret(environment = process.env) {
  const explicit = environment.KORLIX_SUPPORT_THREAD_SECRET;
  if (explicit !== undefined && explicit !== null && explicit !== '') {
    return typeof explicit === 'string' && explicit.length >= 32 && explicit.length <= 4096 ? explicit : null;
  }
  if (!supportLegacyWebhookEnabled(environment)) return null;
  const master = webhookKey(legacyResendWebhookSecret(environment));
  if (!master || master.length < 32) return null;
  // Domain separation keeps reply-address signatures independent of Svix
  // signatures without copying or exposing the durable webhook key. Rotating
  // the master still invalidates old reply addresses; deployment docs cover it.
  return createHmac('sha256',master).update(THREAD_KEY_CONTEXT,'utf8').digest();
}
