// These route prefixes contain private server-owned RPCs. Check the current
// account profile before reads, writes, uploads, exports or AI/voice work.
export function registerEnterpriseBusinessAccess(app, { database, requireUser }) {
  const guard = (feature, code) => async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    let user;
    try { user = await requireUser(req); } catch { /* Return the auth response below. */ }
    if (!user?.id) {
      return res.status(401).json({ error: `Sign in to use ${feature}.`, code: 'AUTH_REQUIRED' });
    }
    try {
      if (!database) throw new Error('Profile storage unavailable');
      const { data: profile, error } = await database.from('user_profiles')
        .select('id,tier,is_disabled').eq('id', user.id).maybeSingle();
      if (error) throw error;
      if (profile?.id !== user.id || profile.is_disabled === true) {
        return res.status(403).json({
          error: 'An active account is required.', code: 'ACCOUNT_ACCESS_REQUIRED',
        });
      }
      if (String(profile.tier ?? '').trim().toLowerCase() !== 'enterprise') {
        // Existing finance clients treat 401/403 as identity/ownership failures
        // and clear their session. A paid-plan requirement must not lock the
        // same user's free personal Tax Prep organizer.
        return res.status(402).json({
          error: `${feature} is available with Enterprise. Your saved records are retained.`,
          code, requiredTier: 'enterprise', upgradeRequired: true,
        });
      }
    } catch {
      return res.status(503).json({
        error: `Your ${feature} plan access could not be checked. Please try again.`,
        code: 'ENTERPRISE_ACCESS_UNAVAILABLE',
      });
    }
    next();
  };
  const inventory = guard('Inventory Studio', 'INVENTORY_ENTERPRISE_REQUIRED');
  const bookkeeping = guard('Bookkeeping', 'BOOKKEEPING_ENTERPRISE_REQUIRED');
  app.use('/api/inventory', inventory);
  app.use('/api/bookkeeping/businesses', bookkeeping);

  // Personal Tax Prep and Receipt Wiz stay independently available. Linking or
  // refreshing business books is a Bookkeeping action; removing links is not.
  const linkedBooks = (req, res, next) =>
    Array.isArray(req.body?.business_ids) && req.body.business_ids.length > 0
      ? bookkeeping(req, res, next) : next();
  app.post('/api/bookkeeping/tax-prep', linkedBooks);
  app.post('/api/bookkeeping/tax-prep/:id/books', linkedBooks);
}
