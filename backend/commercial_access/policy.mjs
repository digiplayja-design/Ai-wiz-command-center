// TIER-GAS-01: commercial eligibility only, not resource authorization or metering.
// Facts MUST come from a server-owned resolver, never a request body or JWT user_metadata.
export const POLICY_VERSION = '2026-09-29.v1';
export const TIERS = Object.freeze(['basic', 'pro', 'ultra', 'enterprise']);
const ALIASES = new Map([
  ['basic', 'basic'], ['pro', 'pro'], ['ultra', 'ultra'],
  ['ultra premium', 'ultra'], ['ultra_premium', 'ultra'],
  ['ultra-premium', 'ultra'], ['enterprise', 'enterprise'],
]);
export function normalizeTier(value) {
  return typeof value === 'string' ? ALIASES.get(value.trim().toLowerCase()) ?? null : null;
}
const rows = [
  ['account.controls', 'basic', null, 'personal'],
  ['social.core', 'basic', 'social_limits', 'personal'],
  ['social.calls', 'basic', 'social_limits', 'personal'],
  ['social.games', 'basic', 'social_limits', 'personal'],
  ['chat', 'basic', 'ai_allowance', 'personal'],
  ['resume', 'basic', 'ai_allowance', 'personal'],
  ['email_enhancer', 'basic', 'ai_allowance', 'personal'],
  ['study', 'basic', 'ai_allowance', 'personal'],
  ['locator', 'basic', 'utility_allowance', 'personal'],
  ['camera_ask', 'basic', 'ai_allowance', 'personal'],
  ['cyber_defender', 'basic', 'ai_allowance', 'personal'],
  ['imagine_picture', 'basic', 'image_allowance', 'personal'],
  ['improve_picture', 'basic', 'image_allowance', 'personal'],
  ['logo', 'basic', 'image_allowance', 'personal'],
  ['virtual_closet', 'basic', 'image_allowance', 'personal'],
  ['babyblend', 'basic', 'image_allowance', 'personal'],
  ['chat_memory', 'basic', 'memory_capacity', 'personal'],
  ['agents.personal', 'pro', 'agent_capacity', 'personal'],
  ['agents.advanced', 'ultra', 'agent_capacity', 'personal'],
  ['brain_vault', 'pro', 'memory_capacity', 'personal'],
  ['app_studio', 'pro', 'app_allowance', 'personal'],
  ['live_convo', 'basic', 'included_voice_then_gas', 'personal'],
  ['music_production', 'basic', 'music_allowance', 'addon'],
  ['video_generation', 'ultra', 'video_allowance', 'personal'],
  ['bookkeeping.core', 'pro', 'bookkeeping_capacity', 'personal'],
  ['bookkeeping.advanced', 'ultra', 'bookkeeping_capacity', 'personal'],
  ['tax_prep.organizer', 'pro', 'tax_organizer_capacity', 'personal'],
  ['tax_prep.linked_books', 'ultra', 'tax_organizer_capacity', 'personal'],
  ['inventory', 'ultra', 'inventory_capacity', 'personal'],
  ['fieldproof', 'ultra', 'fieldproof_capacity', 'personal'],
  ['contract_radar', 'ultra', 'ai_allowance', 'personal'],
  ['ai_visibility', 'ultra', 'ai_allowance', 'personal'],
  ['crm', 'enterprise', 'crm_capacity', 'personal'],
  ['funnels', 'enterprise', 'funnel_capacity', 'personal'],
  ['meeting_copilot', 'enterprise', 'meeting_allowance', 'personal'],
  ['autonomous_outreach', 'enterprise', 'delivery_allowance', 'personal'],
  ['workforce.employee', 'enterprise', 'workforce_seats', 'workspace'],
  ['workforce.admin', 'enterprise', 'workforce_seats', 'workspace'],
];
export const FEATURES = Object.freeze(rows.map(([key, minimumTier, meter, scope]) =>
  Object.freeze({key, minimumTier, meter, scope})));
const BY_KEY = new Map(FEATURES.map(feature => [feature.key, feature]));
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isAccountId = value => typeof value === 'string' && UUID.test(value);
export class AccessPolicyError extends Error {
  constructor(code, status = 503) {
    super(code); this.name = 'AccessPolicyError'; this.code = code; this.status = status;
  }
}
function current(record, at) {
  if (!record || record.verified !== true || record.status !== 'active') return false;
  if (record.expiresAt === null) return record.nonExpiring === true;
  if (typeof record.expiresAt !== 'string' || !/T.*(?:Z|[+-]\d{2}:\d{2})$/.test(record.expiresAt)) return false;
  const end = Date.parse(record.expiresAt);
  return Number.isFinite(end) && end > at;
}
export function effectiveTier(plan, at = Date.now()) {
  if (!Number.isFinite(at)) throw new AccessPolicyError('ACCESS_CLOCK_INVALID');
  return current(plan, at) ? normalizeTier(plan.tier) ?? 'basic' : 'basic';
}
function result(feature, eligible, reason, extra = {}) {
  return Object.freeze({
    policyVersion: POLICY_VERSION, featureKey: feature?.key ?? null,
    eligible, reason, minimumTier: feature?.minimumTier ?? null,
    meter: feature?.meter ?? null,
    requiresResourceAuthorization: true,
    requiresUsageCheck: eligible && feature?.meter !== null,
    ...extra,
  });
}
// A positive result says only that the commercial gate is satisfied. Existing
// ownership, tenant, consent, moderation, quota and provider checks still apply.
export function evaluateAccess({userId, facts, featureKey, availableFeatures, workspaceId = null, at = Date.now()} = {}) {
  if (!Number.isFinite(at)) throw new AccessPolicyError('ACCESS_CLOCK_INVALID');
  if (!isAccountId(userId) || facts?.userId !== userId) throw new AccessPolicyError('ACCESS_IDENTITY_MISMATCH', 401);
  const feature = typeof featureKey === 'string' ? BY_KEY.get(featureKey) : null;
  if (!feature) return result(null, false, 'UNKNOWN_FEATURE');
  // Account/privacy controls cannot be sold as a premium entitlement. Authentication
  // and ownership still apply, even to this non-paywalled commercial decision.
  if (feature.key === 'account.controls') return result(feature, true, 'ACCOUNT_CONTROL');
  if (facts.accountStatus !== 'active') return result(feature, false, 'ACCOUNT_RESTRICTED');
  if (!Array.isArray(availableFeatures) || !availableFeatures.includes(feature.key)) return result(feature, false, 'FEATURE_NOT_AVAILABLE');
  if (workspaceId !== null && !isAccountId(workspaceId)) return result(feature, false, 'WORKSPACE_REQUIRED');
  const workspace = facts.workspace;
  if (feature.scope === 'workspace' && workspaceId === null) return result(feature, false, 'WORKSPACE_REQUIRED');
  if (workspaceId !== null) {
    if (workspace?.id !== workspaceId || workspace.memberUserId !== userId ||
        !current(workspace.membership, at)) return result(feature, false, 'WORKSPACE_MEMBERSHIP_REQUIRED');
    if (!Array.isArray(workspace.permissions) || !workspace.permissions.includes(feature.key)) return result(feature, false, 'WORKSPACE_PERMISSION_REQUIRED');
  }
  const plan = workspaceId === null ? facts.plan : workspace.plan;
  const tier = effectiveTier(plan, at);
  if (feature.scope === 'addon') {
    const addon = Array.isArray(facts.addons) && facts.addons.some(grant =>
      grant.userId === userId && grant.featureKey === feature.key &&
      grant.workspaceId === workspaceId && current(grant, at));
    return result(feature, Boolean(addon), addon ? 'ADDON_GRANTED' : 'ADDON_REQUIRED');
  }
  if (TIERS.indexOf(tier) >= TIERS.indexOf(feature.minimumTier)) return result(feature, true, 'PLAN_ELIGIBLE', {tier});
  // Grandfather grants are exact, audited entitlements from an existing paid offer;
  // no wildcard, cross-user, cross-workspace or expired grants are accepted.
  const grandfathered = Array.isArray(facts.legacyGrants) && facts.legacyGrants.some(grant =>
    grant.source === 'legacy_paid_offer' && typeof grant.offerId === 'string' &&
    grant.offerId.trim().length > 0 && grant.userId === userId &&
    grant.featureKey === feature.key && grant.workspaceId === workspaceId && current(grant, at));
  return result(feature, Boolean(grandfathered), grandfathered ? 'LEGACY_PAID_BENEFIT' : 'UPGRADE_REQUIRED');
}
// This endpoint is read-only and is NOT mounted by this first milestone.
// loadFacts must verify the effective subscription independently of editable profile
// fields. It must return normalized, current, server-owned entitlement facts.
export function registerAccessPreview(app, {requireUser, loadFacts, loadAvailability, now = Date.now} = {}) {
  if (!app || typeof app.get !== 'function' || [requireUser, loadFacts, loadAvailability, now].some(fn => typeof fn !== 'function')) {
    throw new AccessPolicyError('ACCESS_ADAPTER_REQUIRED');
  }
  app.get('/api/commercial-access/preview', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      let user;
      try { user = await requireUser(req); } catch { throw new AccessPolicyError('AUTH_REQUIRED', 401); }
      if (!isAccountId(user?.id)) throw new AccessPolicyError('AUTH_REQUIRED', 401);
      // No tier, balance, grant, role, userId or availability is taken from req.
      const facts = await loadFacts(user.id);
      const availableFeatures = await loadAvailability();
      const at = now();
      const decisions = FEATURES.filter(feature => feature.scope !== 'workspace').map(feature =>
        evaluateAccess({userId: user.id, facts, featureKey: feature.key, availableFeatures, at}));
      res.json({policyVersion: POLICY_VERSION, previewOnly: true, enforcesLiveRoutes: false, decisions});
    } catch (error) {
      const status = error instanceof AccessPolicyError && error.status === 401 ? 401 : 503;
      res.status(status).json({code: status === 401 ? 'AUTH_REQUIRED' : 'ACCESS_UNAVAILABLE'});
    }
  });
}
