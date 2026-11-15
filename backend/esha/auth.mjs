// The verified login's stored companion binding determines this scope. Request
// headers can select an app only at sign-in; they cannot broaden an existing JWT.
const READ_PATHS = new Set([
  '/api/me', '/api/esha/catalog', '/api/esha/billing/catalog', '/api/esha/billing/status',
  '/api/esha/voice/status',
]);
const WRITE_PATHS = new Set([
  '/api/auth/refresh', '/api/auth/signout', '/api/account/delete-request',
  '/api/report-output',
  '/api/esha/billing/prepare', '/api/esha/billing/verify', '/api/esha/consult',
  '/api/esha/voice/sessions',
]);
const VOICE_SESSION_PATH = /^\/api\/esha\/voice\/sessions\/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VOICE_STOP_PATH = /^\/api\/esha\/voice\/sessions\/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/stop$/i;

export function eshaAppRouteAllowed(req) {
  const method = String(req?.method || '').toUpperCase();
  const path = String(req?.originalUrl || req?.url || req?.path || '').split('?')[0];
  if (method === 'GET' || method === 'HEAD') return READ_PATHS.has(path) || VOICE_SESSION_PATH.test(path);
  return method === 'POST' && (WRITE_PATHS.has(path) || VOICE_STOP_PATH.test(path));
}
