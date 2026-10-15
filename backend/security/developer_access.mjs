// This marker comes only from the server-owned developer grant joined to the
// authenticated account (or returned by korlix_web_billing_profile).
// Never derive it from request JSON, email, JWT user_metadata, or a plan name.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const UNLIMITED_COMPATIBILITY_LIMIT = 2147483647;

export function hasUnlimitedAccess(account) {
  return UUID.test(account?.id || '') && account?.developer_unlimited === true
    && account?.is_disabled !== true;
}

export function authenticatedDeveloperUser(user, account) {
  const grants = account?.developer_access;
  const enabled = Array.isArray(grants) ? grants.some(g => g?.enabled === true) : grants?.enabled === true;
  return {...user, developer_unlimited: UUID.test(user?.id || '') && user?.id === account?.id && enabled && account?.is_disabled !== true};
}

// Numeric fields keep existing mobile releases compatible. Enforcement uses
// the boolean entitlement, rather than treating this large number as a quota.
export const UNLIMITED_FEATURE_LIMITS = Object.freeze({
  dailyRequestLimit: UNLIMITED_COMPATIBILITY_LIMIT,
  dailyCreditLimit: UNLIMITED_COMPATIBILITY_LIMIT,
  characterLimit: UNLIMITED_COMPATIBILITY_LIMIT,
  videoGenerationsMonthly: UNLIMITED_COMPATIBILITY_LIMIT,
  musicGenerationIncluded: true,
  unlimited: true,
  developerAccess: true,
});
