// Only known account operations share the existing handlers. On older servers
// these URLs return 404 instead of consuming/replacing a hub device session.
const routes = new Set([
  '/api/messenger/auth/signin', '/api/messenger/auth/signup',
  '/api/messenger/auth/refresh', '/api/messenger/auth/signout',
  '/api/messenger/auth/password-reset', '/api/messenger/account/delete-request',
]);

export function messengerAuthAlias(req, res, next) {
  const [path, query] = String(req.url || '').split('?', 2);
  if (!path.startsWith('/api/messenger/')) return next();
  if (req.method !== 'POST' || !routes.has(path)) {
    return res.status(404).json({error: 'Messenger account operation not found.'});
  }
  req.headers['x-korlix-app'] = 'korlix_messenger';
  req.body = {...req.body, client_app: 'korlix_messenger'};
  req.url = path.replace('/api/messenger/', '/api/') + (query ? `?${query}` : '');
  next();
}
