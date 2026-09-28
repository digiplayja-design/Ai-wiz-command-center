// All social data access goes through a service-only, transactional RPC. Never
// accept an actor ID, moderation role, or email address from a request body.
export function registerSocial(app, { database, requireUser, logger = console } = {}) {
  const actions = new Set(['bootstrap', 'members', 'connections', 'messages', 'topics', 'topic', 'blocks', 'reports',
    'save_profile', 'presence', 'request', 'accept', 'decline', 'remove', 'block', 'unblock', 'send', 'read',
    'delete_message', 'create_topic', 'edit_topic', 'delete_topic', 'reply', 'edit_reply', 'delete_reply', 'report', 'moderate']);
  const reads = new Set(['bootstrap', 'members', 'connections', 'messages', 'topics', 'topic', 'blocks', 'reports']);
  const route = async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      let user;
      try { user = await requireUser(req); } catch { return res.status(401).json({ error: 'Sign in to use KORLIX Social.' }); }
      if (!user?.id || user.is_anonymous || !user.email_confirmed_at) return res.status(401).json({ error: 'Confirm your KORLIX account email and sign in to use Social.' });
      if (!database) return res.status(503).json({ error: 'KORLIX Social is temporarily unavailable.' });
      const action = req.params.action;
      if (!actions.has(action) || (req.method === 'GET') !== reads.has(action)) return res.status(404).json({ error: 'Social action not found.' });
      const data = req.method === 'GET' ? req.query : req.body;
      if (!data || typeof data !== 'object' || Array.isArray(data) || Buffer.byteLength(JSON.stringify(data)) > 24000) return res.status(400).json({ error: 'This request is too large or incomplete.' });
      // p_actor is derived exclusively from a Supabase-verified identity.
      const result = await database.rpc('korlix_social_v1', { p_actor: user.id, p_action: action, p_data: data });
      if (result.error) {
        const code = result.error.code;
        const status = { P0001: 400, P0002: 404, '42501': 403, '23505': 409, '23514': 400, '22P02': 400, '22003': 400, '54000': 429 }[code];
        if (status) return res.status(status).json({ error: code === '23505' ? 'That handle or request is already in use. Refresh and try again.' : ['22P02', '22003', '23514'].includes(code) ? 'Check the fields and try again.' : result.error.message });
        logger.warn('Social storage unavailable', { action, code });
        return res.status(503).json({ error: 'This change could not be confirmed. Refresh before retrying.' });
      }
      if (result.data == null) return res.status(503).json({ error: 'KORLIX Social is temporarily unavailable.' });
      res.json(result.data);
    } catch {
      res.status(503).json({ error: 'KORLIX Social could not finish this request. Refresh before retrying.' });
    }
  };
  app.get('/api/social/:action', route);
  app.post('/api/social/:action', route);
}
