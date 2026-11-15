// The verified login's stored companion binding determines this scope. Request
// headers can select an app only at sign-in; they cannot broaden an existing JWT.
const READ_PATHS = new Set([
  '/api/me', '/api/esha/catalog', '/api/esha/billing/catalog', '/api/esha/billing/status',
]);
const WRITE_PATHS = new Set([
  '/api/auth/refresh', '/api/auth/signout', '/api/account/delete-request',
  '/api/report-output',
  '/api/esha/billing/prepare', '/api/esha/billing/verify', '/api/esha/consult',
]);

export function eshaAppRouteAllowed(req) {
  const method = String(req?.method || '').toUpperCase();
  const path = String(req?.originalUrl || req?.url || req?.path || '').split('?')[0];
  if (method === 'GET' || method === 'HEAD') return READ_PATHS.has(path);
  return method === 'POST' && WRITE_PATHS.has(path);
}
