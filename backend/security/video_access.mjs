/** Server-only video ownership and atomic quota reservation boundary. */
export class VideoAccessError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}

const denied = () => new VideoAccessError(404, 'video_not_found', 'Video not found.');
const unavailable = () => new VideoAccessError(503, 'video_access_unavailable', 'Video access could not be verified. Please try again.');
const identity = user => {
  if (!user?.id || typeof user.id !== 'string') {
    throw new VideoAccessError(401, 'sign_in_required', 'Sign in required.');
  }
  return user.id;
};
const validId = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const providers = new Set(['openai', 'kling', 'generic']);
const kinds = new Set(['text_to_video', 'image_to_video']);

export function createVideoAccess({database}) {
  const rpc = async (name, args) => {
    if (!database?.rpc) throw unavailable();
    let response;
    try { response = await database.rpc(name, args); } catch { throw unavailable(); }
    if (response?.error || !response?.data) throw unavailable();
    const data = Array.isArray(response.data) ? response.data[0] : response.data;
    if (!data || typeof data !== 'object') throw unavailable();
    return data;
  };

  return {
    async reserve({user, kind, provider}) {
      const userId = identity(user);
      if (!kinds.has(kind) || !providers.has(provider)) throw new VideoAccessError(400, 'video_request_invalid', 'Invalid video request.');
      // Tier, remaining allowance, and credit balance are resolved atomically in SQL.
      const data = await rpc('korlix_video_reserve', {p_user_id:userId, p_kind:kind, p_provider:provider});
      if (data.ok !== true) {
        if (kind === 'image_to_video') throw new VideoAccessError(429, 'monthly_video_limit_reached', 'You have reached your monthly Create a Video limit for your plan.');
        throw new VideoAccessError(402, 'video_quota_exhausted', 'No video generations remaining. Buy video credits to continue.');
      }
      if (!validId(data.reservation_id)) throw unavailable();
      return {id:data.reservation_id, userId, provider, kind, spentPurchasedCredit:data.spent_purchased_credit === true};
    },

    async attach({user, reservation, jobId}) {
      const userId = identity(user);
      if (!reservation || reservation.userId !== userId || !validId(reservation.id) || !validId(jobId)) throw denied();
      const data = await rpc('korlix_video_attach', {p_user_id:userId, p_reservation_id:reservation.id, p_job_id:jobId});
      if (data.ok !== true) throw unavailable();
      return data;
    },

    async requireOwnedJob({user, jobId, provider}) {
      const userId = identity(user);
      if (!validId(jobId) || !providers.has(provider)) throw denied();
      if (!database?.from) throw unavailable();
      let result;
      try {
        result = await database.from('korlix_video_jobs')
          .select('id,provider_job_id,provider,kind,status')
          .eq('user_id', userId).eq('provider', provider).eq('provider_job_id', jobId)
          .maybeSingle();
      } catch { throw unavailable(); }
      if (result?.error) throw unavailable();
      if (!result?.data || result.data.provider_job_id !== jobId || result.data.provider !== provider || result.data.status !== 'submitted') throw denied();
      return result.data;
    },

    async summary({user}) {
      return rpc('korlix_video_credit_summary', {p_user_id:identity(user)});
    },
  };
}
