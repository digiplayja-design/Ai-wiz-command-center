import {FieldProofError} from './model.mjs';

const fail = (message, status, code) => {
  throw Object.assign(new FieldProofError(message, status), {code});
};

// Read the current server-owned plan. JWT metadata and caller-supplied tiers
// cannot grant access, and a downgrade takes effect on the next operation.
export async function requireFieldProofEnterprise(database, userId) {
  let profile;
  try {
    const result = await database.from('user_profiles')
      .select('id,tier,is_disabled').eq('id', userId).maybeSingle();
    if (result.error) throw result.error;
    profile = result.data;
  } catch {
    fail('Your FieldProof plan access could not be checked. Please try again.',
      503, 'fieldproof_access_unavailable');
  }
  if (!userId || profile?.id !== userId || profile.is_disabled === true) {
    fail('An active account is required to use FieldProof.',
      403, 'fieldproof_account_required');
  }
  if (String(profile.tier ?? '').trim().toLowerCase() !== 'enterprise') {
    fail('FieldProof is available with Enterprise. Your saved records are retained.',
      402, 'fieldproof_enterprise_required');
  }
  return profile;
}

export function fieldProofAccessDetails(error) {
  if (!['fieldproof_access_unavailable', 'fieldproof_account_required',
    'fieldproof_enterprise_required'].includes(error?.code)) return {};
  return {code: error.code, ...(error.code === 'fieldproof_enterprise_required'
    ? {requiredTier: 'enterprise', upgradeRequired: true} : {})};
}
