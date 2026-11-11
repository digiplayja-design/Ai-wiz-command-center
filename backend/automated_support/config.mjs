import {createHash} from 'node:crypto';
import {supportWebhookConfigured, supportThreadSecret} from './secrets.mjs';

export const SUPPORT_STATES = Object.freeze(['new', 'waiting_for_customer', 'needs_review', 'resolved']);
export const SUPPORT_MODES = Object.freeze(['paused', 'draft', 'automatic']);
export const SUPPORT_ROOT = '/api/automated-support';
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PROFILE_ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;
export class AutomatedSupportError extends Error {
  constructor(message, statusCode = 400, code = 'support_invalid') {
    super(message); this.statusCode = statusCode; this.code = code;
  }
}
export function fail(message, statusCode = 400, code = 'support_invalid') {
  throw new AutomatedSupportError(message, statusCode, code);
}
export function emailAddress(value) {
  if (typeof value !== 'string' || value.length > 254 || !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$/.test(value)) {
    fail('A valid email address is required.');
  }
  return value.toLowerCase();
}
export function boundedText(value, max, name = 'Text') {
  if (typeof value !== 'string' || value.length > max || /\x00/.test(value)) fail(`${name} is invalid.`);
  return value.trim();
}
export function strictFields(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !allowed.includes(key))) {
    fail('This request contains unsupported fields.');
  }
  return value;
}
const truth = value => String(value).toLowerCase() === 'true';

/** Deployment-owned enrollment. HTTP callers cannot enroll senders or owners. */
export function parseSupportProfiles(environment = process.env) {
  const raw = environment.KORLIX_SUPPORT_PROFILES_JSON || '[]';
  let data;
  try { data = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch { fail('Automated support enrollment is invalid.', 503, 'support_configuration_invalid'); }
  if (!Array.isArray(data) || data.length > 50) fail('Automated support enrollment is invalid.', 503, 'support_configuration_invalid');
  const ids = new Set(), applications = new Set(), inboxes = new Set();
  return data.map(source => {
    if (!source || typeof source !== 'object' || !PROFILE_ID.test(source.id || '') || !UUID.test(source.ownerUid || '') || ids.has(source.id)) {
      fail('Automated support enrollment is invalid.', 503, 'support_configuration_invalid');
    }
    if (!Array.isArray(source.appKeys) || !source.appKeys.length || source.appKeys.length > 20 || source.appKeys.some(key => !PROFILE_ID.test(key) || applications.has(key)) || new Set(source.appKeys).size !== source.appKeys.length) {
      fail('Each support application must have one enrolled owner.', 503, 'support_configuration_invalid');
    }
    const inboundAddresses = Array.isArray(source.inboundAddresses) ? source.inboundAddresses.map(emailAddress) : [];
    if (inboundAddresses.length > 20 || inboundAddresses.some(address => inboxes.has(address))) fail('Each receiving address must have one support profile.', 503, 'support_configuration_invalid');
    const profile = {
      id: source.id, ownerUid: source.ownerUid.toLowerCase(),
      appKeys: [...source.appKeys], displayName: boundedText(source.displayName || 'KORLIX Support', 120, 'Support name'),
      fromEmail: emailAddress(source.fromEmail), replyTo: emailAddress(source.replyTo), inboundAddresses,
      senderVerified: source.senderVerified === true, receivingVerified: source.receivingVerified === true,
      dailyCap: Number.isInteger(source.dailyCap) ? Math.max(1, Math.min(100, source.dailyCap)) : 20,
    };
    if (!profile.displayName || /[\x00-\x1f\x7f<>\"\\]/.test(profile.displayName)) fail('Support name is invalid.', 503, 'support_configuration_invalid');
    if (!inboundAddresses.includes(profile.replyTo)) fail('The support reply address must be an enrolled receiving address.', 503, 'support_configuration_invalid');
    profile.fingerprint = createHash('sha256').update(JSON.stringify(profile)).digest('hex');
    ids.add(profile.id); profile.appKeys.forEach(key => applications.add(key)); inboundAddresses.forEach(address => inboxes.add(address));
    return Object.freeze(profile);
  });
}

export function supportReadiness(profile, environment = process.env) {
  const setupReasons = [];
  if (!truth(environment.KORLIX_AUTOMATED_SUPPORT_ENABLED)) setupReasons.push('Automated support is awaiting activation.');
  if (String(environment.KORLIX_AUTOMATED_SUPPORT_PAUSED).toLowerCase() !== 'false') setupReasons.push('Support sending is paused.');
  if (truth(environment.KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE)) setupReasons.push('The email emergency pause is active.');
  if (typeof environment.RESEND_API_KEY !== 'string' || !environment.RESEND_API_KEY || environment.RESEND_API_KEY.length > 4096 || /\s/.test(environment.RESEND_API_KEY)) setupReasons.push('The email provider is not configured.');
  if (!supportWebhookConfigured(environment)) setupReasons.push('Incoming email verification is not configured.');
  if (!supportThreadSecret(environment)) setupReasons.push('Support conversation signing is not configured.');
  if (!profile.senderVerified) setupReasons.push('The sending address needs verification.');
  if (!profile.receivingVerified) setupReasons.push('Reply delivery needs verification.');
  if (profile.replyTo.split('@')[0].length > 22) setupReasons.push('Use a shorter reply address to support signed conversation routing.');
  return {ready: setupReasons.length === 0, setupReasons};
}

export function loadAutomatedSupportConfig(environment = process.env) {
  return {enabled: truth(environment.KORLIX_AUTOMATED_SUPPORT_ENABLED), paused: String(environment.KORLIX_AUTOMATED_SUPPORT_PAUSED).toLowerCase() !== 'false' || truth(environment.KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE), profiles: parseSupportProfiles(environment)};
}
