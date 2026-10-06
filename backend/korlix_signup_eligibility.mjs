export const KORLIX_SIGNUP_POLICY_VERSION = '2026-10-06';
export const KORLIX_MINIMUM_AGE = 16;

export function validateSignupEligibility(value, now = new Date()) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {
      code: 'SIGNUP_ELIGIBILITY_REQUIRED',
      error: 'Please confirm your age and review the policies in the latest KORLIX app. You can also sign up at https://www.korlixdeveloper.com/app/.',
    };
  }
  if (value.age_band === 'under_16') {
    return {code: 'SIGNUP_AGE_RESTRICTED', error: 'You must be at least 16 to create a KORLIX account.'};
  }
  if (!['16_17', '18_plus'].includes(value.age_band)) {
    return {code: 'SIGNUP_AGE_REQUIRED', error: 'Select your age range to continue.'};
  }
  if (value.policy_version !== KORLIX_SIGNUP_POLICY_VERSION) {
    return {code: 'SIGNUP_POLICY_CHANGED', error: 'Please refresh or update KORLIX to review the current Terms of Use and Privacy Policy.'};
  }
  if (value.terms_accepted !== true || value.privacy_acknowledged !== true) {
    return {code: 'SIGNUP_POLICIES_REQUIRED', error: 'Please agree to the Terms of Use and acknowledge the Privacy Policy.'};
  }
  if (value.age_band === '16_17' && value.parent_permission !== true) {
    return {code: 'SIGNUP_PARENT_PERMISSION_REQUIRED', error: 'Users aged 16–17 need permission from a parent or guardian.'};
  }
  return {
    declaration: {
      age_band: value.age_band,
      minimum_age: KORLIX_MINIMUM_AGE,
      terms_accepted: true,
      privacy_acknowledged: true,
      parent_permission: value.age_band === '16_17',
      policy_version: KORLIX_SIGNUP_POLICY_VERSION,
      declared_at: now.toISOString(),
      method: 'self_declaration',
    },
  };
}

// This declaration is saved as user metadata, not trusted identity or an
// authorization claim. Users can edit Supabase user metadata; never use it to
// grant permissions, bypass moderation, or assert independently verified age.
export function createKorlixSignupHandler({
  supabaseAuth,
  getRequestDeviceInfo,
  getOrCreateProfile,
  registerDeviceSession,
  getUserFacingError,
  now = () => new Date(),
}) {
  return async (req, res) => {
    try {
      const body = req.body ?? {};
      const eligibility = validateSignupEligibility(body.signup_eligibility, now());
      if (eligibility.error) return res.status(400).json(eligibility);

      if (!supabaseAuth) {
        return res.status(500).json({error: 'Supabase auth is not configured on the backend.'});
      }
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '').trim();
      if (!email || !password) {
        return res.status(400).json({error: 'Email and password are required.'});
      }
      if (password.length < 6) {
        return res.status(400).json({error: 'Password must be at least 6 characters.'});
      }

      const {data, error} = await supabaseAuth.auth.signUp({
        email,
        password,
        options: {data: {korlix_signup_declaration: eligibility.declaration}},
      });
      if (error) {
        return res.status(error.status || 400).json({error: getUserFacingError(error)});
      }

      let profile = null;
      let deviceSession = null;
      if (data.user && data.session) {
        profile = await getOrCreateProfile(data.user);
        deviceSession = await registerDeviceSession({
          userId: data.user.id,
          profile,
          deviceInfo: getRequestDeviceInfo(req),
        });
      }
      return res.json({
        success: true,
        message: data.session
          ? 'Account created and signed in.'
          : 'Account created. Check your email to confirm your account, then sign in.',
        user: data.user ? {id: data.user.id, email: data.user.email} : null,
        profile,
        deviceSession,
        session: data.session ? {
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token,
          expires_at: data.session.expires_at,
        } : null,
      });
    } catch (error) {
      return res.status(error.statusCode || 500).json({error: getUserFacingError(error)});
    }
  };
}
