/** Private, server-only storage. Every actor and limits object must come from verified server context. */
export const POD_USAGE_LABEL = 'Personal beta · uses your LIVE CONVO session and time allowance. AI usage limits also apply.';

export class PodStorageError extends Error {
  constructor(message, status = 503, code = 'pod_storage_unavailable') {
    super(message); this.name = 'PodStorageError'; this.status = status;
    this.statusCode = status; this.code = code;
  }
}

export function createPodStore({database, logger = console} = {}) {
  const call = async (actor, action, id = null, data = {}) => {
    if (!database || (!actor && action !== 'sweep')) throw new PodStorageError('Sign in before starting your pod.', actor ? 503 : 401);
    let response;
    try {
      response = await database.rpc('korlix_pod_v1', {p_actor:actor, p_action:action, p_id:id, p_data:data});
    } catch {
      throw new PodStorageError('Your pod could not be confirmed. Refresh before trying again.');
    }
    if (response.error) {
      const e = response.error;
      const status = {P0002:404, '40001':409, '23505':409, '54000':429, '42501':403, '22023':400, P0001:400}[e.code];
      if (status) throw new PodStorageError(e.code === '23505' ? 'A pod or request is already active. Refresh before trying again.' : e.message, status, e.code);
      logger.warn?.('Pod storage unavailable', {action, code:e.code});
      throw new PodStorageError('Your pod could not be confirmed. Refresh before trying again.');
    }
    const value = Array.isArray(response.data) ? response.data[0] : response.data;
    if (!value || typeof value !== 'object') throw new PodStorageError('Your pod could not be confirmed. Refresh before trying again.');
    return value;
  };
  return Object.freeze({
    call,
    list: actor => call(actor, 'list'),
    sweep: () => call(null, 'sweep'),
    isQuotaSession: (actor, quotaSessionId) => call(actor, 'quota_lookup', quotaSessionId).then(value => value.isPod === true),
    create: (actor, {requestId, input, limits, unlimited = false}) => call(actor, 'create', requestId, {input, limits, unlimited}),
    get: (actor, id) => call(actor, 'get', id),
    claim: (actor, id, {requestId, version, kind}) => call(actor, 'claim', id, {requestId, version, kind}),
    authorizeDispatch: (actor, id, requestId, callKey) => call(actor, 'dispatch', id, {requestId, callKey}),
    recordUsage: (actor, id, requestId, {callKey, usage = {}, evidence = {}}) => call(actor, 'receipt', id, {requestId, callKey, usage, evidence}),
    finish: (actor, id, requestId, result) => call(actor, 'finish', id, {requestId, result}),
    fail: (actor, id, requestId, {error = 'This turn could not finish. Try a new request.', uncertain = false} = {}) => call(actor, 'fail', id, {requestId, error, uncertain}),
    control: (actor, id, action) => call(actor, 'control', id, {action}),
    contribute: (actor, id, {requestId, text}) => call(actor, 'contribute', id, {requestId, text}),
    remove: (actor, id, {confirmed = false} = {}) => call(actor, 'remove', id, {confirmed}),
  });
}
