import {SUPPORT_ROOT, strictFields, fail} from './config.mjs';

export function registerAutomatedSupportRoutes(app, {requireUser, service}) {
  if (!app?.use || typeof requireUser !== 'function' || !service) throw new TypeError('Support routes require authenticated access and a service.');
  app.use(SUPPORT_ROOT, async (req, res) => {
    res.set({'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    try {
      const user = await requireUser(req);
      if (!user?.id) fail('Sign in required.', 401, 'support_sign_in_required');
      const ownerUid = user.id;
      const url = new URL(req.originalUrl || req.url, 'https://unused.invalid');
      const path = url.pathname.slice(SUPPORT_ROOT.length).replace(/\/$/, '');
      const method = req.method;
      if (path !== '/cases' && url.search) fail('This operation does not accept query parameters.');
      let result;
      if (path === '/profiles' && method === 'GET') result = await service.listProfiles({ownerUid});
      else if (/^\/profiles\/[a-z0-9_-]+$/.test(path) && method === 'PATCH') {
        strictFields(req.body, ['mode']);
        result = await service.setProfileMode({ownerUid, profileId: path.split('/')[2], mode: req.body.mode});
      } else if (path === '/cases' && method === 'GET') {
        if ([...url.searchParams.keys()].some(key => !['profileId', 'state'].includes(key) || url.searchParams.getAll(key).length !== 1)) fail('This query contains unsupported filters.');
        result = await service.listCases({ownerUid, profileId: url.searchParams.get('profileId'), state: url.searchParams.get('state')});
      } else {
        const match = path.match(/^\/cases\/([0-9a-f-]{36})(?:\/(replies|process))?$/i);
        if (!match) fail('Support operation not found.', 404, 'support_not_found');
        const [, caseId, action] = match;
        if (!action && method === 'GET') result = await service.getCase({ownerUid, caseId});
        else if (!action && method === 'PATCH') {
          strictFields(req.body, ['state', 'automationPaused', 'resolutionNote']);
          result = await service.updateCase({ownerUid, caseId, ...req.body});
        } else if (action === 'replies' && method === 'POST') {
          strictFields(req.body, ['text', 'confirmed']);
          result = await service.queueOwnerReply({ownerUid, caseId, ...req.body});
        } else if (action === 'process' && method === 'POST') {
          strictFields(req.body || {}, []);
          result = await service.processCase({ownerUid, caseId});
        } else fail('Support operation not found.', 404, 'support_not_found');
      }
      return res.json({ok: true, ...result});
    } catch (error) {
      const status = [400,401,403,404,409,429,503].includes(error?.statusCode) ? error.statusCode : 503;
      return res.status(status).json({ok: false, error: status === 503 ? 'Automated support is temporarily unavailable.' : error.message, code: error?.code || 'support_unavailable'});
    }
  });
}
