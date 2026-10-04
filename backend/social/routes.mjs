// All social data access goes through a service-only, transactional RPC. Never
// accept an actor ID, moderation role, or email address from a request body.
import { registerSocialPhotos, socialPhotos } from './media.mjs';
import { createSocialCallConfig, socialRelayReadiness } from './calls.mjs';
import { registerDomino } from './domino.mjs';
import { registerSocialAttachments, socialAttachments } from './attachments.mjs';
import { registerSocialAlbums } from './albums.mjs';
import { createSocialPush } from './push.mjs';
export function registerSocial(app, { database, requireUser, logger = console, env = process.env, pushSender, autoStart = true } = {}) {
  const callConfig = createSocialCallConfig({env,logger});
  logger.info?.('Social calling relay readiness', socialRelayReadiness(env));
  const actions = new Set(['bootstrap', 'members', 'member', 'wall', 'connections', 'messages', 'message', 'topics', 'topic', 'blocks', 'reports',
    'save_profile', 'presence', 'request', 'accept', 'decline', 'remove', 'block', 'unblock', 'send', 'read',
    'dump_schedule', 'dump_cancel', 'delete_message', 'create_topic', 'edit_topic', 'delete_topic', 'reply', 'edit_reply', 'delete_reply', 'report', 'moderate']);
  const chatActions = new Set(['messages', 'message', 'send']);
  const groupActions = new Set(['groups','group_create','group_details','group_invite','group_accept','group_decline','group_rename','group_remove','group_leave','group_messages','group_message','group_send','group_read','group_delete_message']);
  for (const action of groupActions) actions.add(action);
  const reads = new Set(['bootstrap', 'members', 'member', 'wall', 'connections', 'messages', 'message', 'topics', 'topic', 'blocks', 'reports']);
  for (const action of ['groups','group_details','group_messages','group_message']) reads.add(action);
  const callActions = new Set(['call_config', 'call_inbox', 'call_history', 'call_restart', 'call_start', 'call_accept', 'call_end', 'call_poll', 'call_signal']);
  for (const action of callActions) actions.add(action);
  for (const action of ['call_config', 'call_inbox', 'call_poll', 'call_history']) reads.add(action);
  const authenticate = async (req, res) => {
    let user;
    try { user = await requireUser(req); } catch { res.status(401).json({ error: 'Sign in to use KORLIX Social.' }); return null; }
    if (!user?.id || user.is_anonymous || !user.email_confirmed_at) { res.status(401).json({ error: 'Confirm your KORLIX account email and sign in to use Social.' }); return null; }
    if (!database) { res.status(503).json({ error: 'KORLIX Social is temporarily unavailable.' }); return null; }
    return user;
  };
  registerSocialPhotos(app, { database, authenticate, logger });
  registerSocialAlbums(app, { database, authenticate, logger });
  registerDomino(app, { database, authenticate, env, logger });
  registerSocialAttachments(app, { database, authenticate, logger });
  const push = createSocialPush({ database, authenticate, env, logger, sender: pushSender, autoStart });
  push.register(app);
  const route = async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await authenticate(req, res);
      if (!user) return;
      const action = req.params.action;
      if (!actions.has(action) || (req.method === 'GET') !== reads.has(action)) return res.status(404).json({ error: 'Social action not found.' });
      const data = req.method === 'GET' ? req.query : req.body;
      if (!data || typeof data !== 'object' || Array.isArray(data) || Buffer.byteLength(JSON.stringify(data)) > (action === 'call_signal' ? 220000 : 24000)) return res.status(400).json({ error: 'This request is too large or incomplete.' });
      if (action === 'call_config') {
        const bootstrap = await database.rpc('korlix_social_v1', { p_actor: user.id, p_action: 'bootstrap', p_data: {} });
        if (bootstrap.error || !bootstrap.data?.profile) return res.status(403).json({ error: 'Create an active Social profile before calling.' });
        return res.json(await callConfig(user.id));
      }
      if (['call_start', 'call_accept'].includes(action) && env.SOCIAL_CALLS_ENABLED === 'false') return res.status(503).json({ error: 'Calling is temporarily unavailable. You can still send a message.' });
      // p_actor is derived exclusively from a Supabase-verified identity.
      const groupReport = action === 'report' && data.kind === 'group_message';
      const groupAction = groupActions.has(action) || groupReport || action === 'moderate';
      const mediaChat = chatActions.has(action) || ['group_messages','group_message','group_send'].includes(action);
      const result = await database.rpc(['dump_schedule','dump_cancel'].includes(action) ? 'korlix_social_dump_v1' : mediaChat ? 'korlix_social_media_chat_v1' : groupAction ? 'korlix_social_groups_v1' : callActions.has(action) ? 'korlix_social_calls_v1' : 'korlix_social_v1', { p_actor: user.id, p_action: groupReport ? 'group_report' : action, p_data: data });
      if (result.error) {
        const code = result.error.code;
        const status = { P0001: 400, P0002: 404, '42501': 403, '23505': 409, '40001': 409, '23514': 400, '22P02': 400, '22003': 400, '54000': 429 }[code];
        if (status) return res.status(status).json({ error: code === '23505' ? 'That handle or request is already in use. Refresh and try again.' : ['22P02', '22003', '23514'].includes(code) ? 'Check the fields and try again.' : result.error.message });
        logger.warn('Social storage unavailable', { action, code });
        return res.status(503).json({ error: 'This change could not be confirmed. Refresh before retrying.' });
      }
      if (result.data == null) return res.status(503).json({ error: 'KORLIX Social is temporarily unavailable.' });
      res.json(await socialPhotos(database, await socialAttachments(database, result.data)));
    } catch {
      res.status(503).json({ error: 'KORLIX Social could not finish this request. Refresh before retrying.' });
    }
  };
  app.get('/api/social/:action', route);
  app.post('/api/social/:action', route);
  return push;
}
