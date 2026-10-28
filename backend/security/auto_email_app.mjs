import {sendingReady} from '../auto_email/outbox-security.mjs';
import {mailboxReady} from '../auto_email/mailbox-security.mjs';
import {autoEmailVoiceReady} from '../auto_email/voice.mjs';
import {korlixAgentEmailNovaBinding} from '../korlix_agent_email.mjs';

const ACCOUNT_ROUTES = new Set(['signin', 'refresh', 'signout']);
const AGENT = '[a-z][a-z0-9_]{0,95}';
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

// Original URLs remain intact for authorization. Older deployments fail closed
// at this app-specific URL rather than consuming a KORLIX AI device allowance.
export function autoEmailAuthAlias(req, res, next) {
  const [path, query] = String(req.url || '').split('?', 2);
  if (!path.startsWith('/api/auto-email/auth/')) return next();
  const operation = path.slice('/api/auto-email/auth/'.length);
  if (req.method !== 'POST' || !ACCOUNT_ROUTES.has(operation)) {
    return res.status(404).json({error: 'Auto-Email account operation not found.'});
  }
  req.headers['x-korlix-app'] = 'auto_email';
  req.body = {...req.body, client_app: 'auto_email'};
  req.url = `/api/auth/${operation}${query ? `?${query}` : ''}`;
  next();
}

export function autoEmailAppRouteAllowed(req) {
  const method = String(req?.method || '').toUpperCase();
  const path = String(req?.originalUrl || req?.url || req?.path || '').split('?')[0];
  if (method==='GET' && (path==='/api/auto-email/outbox'||new RegExp(`^/api/auto-email/outbox/${UUID}$`,'i').test(path))) return true;
  if (method==='POST' && ['/api/auto-email/outbox/review','/api/auto-email/outbox/submit'].includes(path)) return true;
  if (method==='GET' && (/^\/api\/auto-email\/mailboxes$/.test(path)||new RegExp(`^/api/auto-email/mailboxes/flows/${UUID}$`,'i').test(path))) return true;
  if (method==='POST' && (/^\/api\/auto-email\/mailboxes\/(google|microsoft)\/(authorize|disconnect)$/.test(path)||new RegExp(`^/api/auto-email/mailboxes/flows/${UUID}/(confirm|cancel)$`,'i').test(path))) return true;
  if (['GET', 'HEAD'].includes(method)) {
    if (['/api/auto-email/session','/api/auto-email/voice/status','/api/auto-email/voice/usage'].includes(path)) return true;
    return new RegExp(`^/api/live-convo/agents/${AGENT}/email/(status|settings|recipients|drafts|delivery/status|events|rules)$`, 'i').test(path)
      || new RegExp(`^/api/live-convo/agents/${AGENT}/email/drafts/${UUID}$`, 'i').test(path);
  }
  if (method === 'POST' && ['/api/auto-email/voice/session','/api/auto-email/voice/usage','/api/auto-email/voice/end'].includes(path)) return true;
  if (method === 'POST' && ['/api/auto-email/auth/refresh', '/api/auto-email/auth/signout'].includes(path)) return true;
  // This pilot can save correspondence, but cannot send, approve messages,
  // change consent, alter settings, or activate any sending rule.
  if (method === 'POST') return new RegExp(`^/api/live-convo/agents/${AGENT}/email/drafts$`, 'i').test(path);
  if (method === 'PATCH') return new RegExp(`^/api/live-convo/agents/${AGENT}/email/drafts/${UUID}$`, 'i').test(path);
  return false;
}

export function registerAutoEmailAppRoutes(app, {requireUser, loadProfile, environment = process.env}) {
  app.get('/api/auto-email/status', (_req, res) => {
    res.set('Cache-Control', 'no-store');
    res.json({ok: true, version: 4, app: 'auto_email', sharedAccount: true,
      draftSync: true, liveVoice: autoEmailVoiceReady(environment), mailboxOAuth: mailboxReady(environment), sending: sendingReady(environment)});
  });
  app.get('/api/auto-email/session', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await requireUser(req);
      const profile = await loadProfile(user);
      const binding = korlixAgentEmailNovaBinding(environment);
      const ownsWorkspace = binding.configured && binding.ownerUid.toLowerCase() === user.id.toLowerCase();
      res.json({ok: true, user: {id: user.id, email: user.email},
        profile: {name: String(profile?.full_name || profile?.display_name || '').slice(0,160), tier: profile?.tier || 'basic'},
        workspace: ownsWorkspace ? {agentId: binding.agentId} : null,
        capabilities: {draftSync: ownsWorkspace, sending: ownsWorkspace && sendingReady(environment), liveVoice: ownsWorkspace && autoEmailVoiceReady(environment), mailboxOAuth: ownsWorkspace && mailboxReady(environment)}});
    } catch (error) {
      const status = [401,403].includes(error?.statusCode) ? error.statusCode : 503;
      res.status(status).json({error: status === 503 ? 'Your email workspace could not be loaded. Please retry.' : 'Sign in to your KORLIX account to continue.'});
    }
  });
}
