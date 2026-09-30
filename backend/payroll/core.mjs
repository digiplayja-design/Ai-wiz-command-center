import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export class PayrollError extends Error {
  constructor(message, status = 400, code = 'PAYROLL_INVALID') {
    super(message); this.status = status; this.code = code;
  }
}
export const fail = (message, status, code) => { throw new PayrollError(message, status, code); };
export function id(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) fail('Choose a valid payroll workspace.');
  return value.toLowerCase();
}
export function text(value, max = 100) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max || /[\x00-\x1f]/.test(value)) fail('Enter a valid name.');
  return value.trim();
}
export const FLOW_TYPES = Object.freeze({
  company_onboarding: { label: 'Company setup' },
  employee_management: { label: 'Employees', entity: true },
  contractor_management: { label: 'Contractors', entity: true },
  run_payroll: { label: 'Run payroll', onboarded: true },
  run_off_cycle_payroll: { label: 'Off-cycle payroll', onboarded: true },
  contractor_payments: { label: 'Contractor payments', onboarded: true },
  payroll_history: { label: 'Payroll history', onboarded: true },
  manage_payroll_schedule: { label: 'Pay schedules', onboarded: true },
  federal_tax_setup: { label: 'Federal tax details' },
  eoy_company_review: { label: 'Year-end tax documents', onboarded: true },
  reports_no_pii: { label: 'Payroll reports' },
  benefits: { label: 'Benefits and deductions' },
});
export function configuration(env = {}) {
  const mode = env.PAYROLL_GUSTO_ENVIRONMENT;
  const validMode = mode === 'demo' || mode === 'production';
  const encryptionKey = env.PAYROLL_TOKEN_ENCRYPTION_KEY || '';
  const validKey = /^[A-Za-z0-9+/]{43}=$/.test(encryptionKey) && Buffer.from(encryptionKey, 'base64').length === 32;
  const ready = validMode && validKey && !!env.GUSTO_CLIENT_ID && !!env.GUSTO_CLIENT_SECRET &&
    (mode !== 'production' || env.PAYROLL_GUSTO_PRODUCTION_APPROVED === 'true');
  return { ready, mode: validMode ? mode : 'unconfigured', encryptionKey,
    clientId: env.GUSTO_CLIENT_ID, clientSecret: env.GUSTO_CLIENT_SECRET,
    apiBase: mode === 'production' ? 'https://api.gusto.com' : 'https://api.gusto-demo.com',
    flowHost: mode === 'production' ? 'flows.gusto.com' : 'flows.gusto-demo.com',
    version: '2026-06-15' };
}
export function publicConfiguration(config) {
  return { ready: config.ready, environment: config.mode, provider: 'Gusto Embedded Payroll',
    message: config.ready ? (config.mode === 'demo' ? 'Demo environment. No real payments or tax filings.' : 'Production provider connected.') :
      'Payroll provider activation is pending. You can prepare your workspace; payments and tax filings are unavailable until activation.' };
}
export function seal(tokens, key, context) {
  const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', Buffer.from(key, 'base64'), iv);
  cipher.setAAD(Buffer.from(context));
  const body = Buffer.concat([cipher.update(JSON.stringify(tokens), 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64'), cipher.getAuthTag().toString('base64'), body.toString('base64')].join('.');
}
export function unseal(value, key, context) {
  const [version, iv, tag, body, extra] = String(value).split('.');
  if (version !== 'v1' || extra) fail('Payroll connection needs administrator attention.', 503);
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(key, 'base64'), Buffer.from(iv, 'base64'));
  decipher.setAAD(Buffer.from(context)); decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(body, 'base64')), decipher.final()]).toString('utf8'));
}
export function tokenPair(value) {
  if (!value || !['access_token', 'refresh_token'].every(k => typeof value[k] === 'string' && value[k].length >= 8 && value[k].length <= 4096) ||
      !Number.isInteger(value.expires_in) || value.expires_in < 120 || value.expires_in > 86400) fail('Payroll provider returned an invalid connection.', 502);
  return { access_token: value.access_token, refresh_token: value.refresh_token };
}
export function safeFlowUrl(value, config) {
  let uri; try { uri = new URL(value); } catch { fail('Payroll provider did not return a secure session.', 502); }
  if (uri.protocol !== 'https:' || uri.hostname !== config.flowHost || uri.port || uri.username || uri.password || !uri.pathname.startsWith('/flows/'))
    fail('Payroll provider did not return a secure session.', 502);
  return uri.href;
}
export function onboardingSummary(raw) {
  return { onboarding_completed: raw?.onboarding_completed === true,
    steps: (Array.isArray(raw?.onboarding_steps) ? raw.onboarding_steps : []).slice(0, 30).map(s => ({
      id: String(s.id || '').slice(0, 80), title: String(s.title || 'Setup step').slice(0, 160),
      completed: s.completed === true, required: s.required === true,
    })) };
}
