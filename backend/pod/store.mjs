/** Private, server-only storage. Every actor and limits object must come from verified server context. */
export const POD_USAGE_LABEL = 'Personal beta · uses your LIVE CONVO session and time allowance. AI usage limits also apply.';

export class PodStorageError extends Error {
  constructor(message, status = 503, code = 'pod_storage_unavailable') {
    super(message); this.name = 'PodStorageError'; this.status = status;
    this.statusCode = status; this.code = code;
  }
}

const POD_STORAGE_ACTIONS = new Set(['list','sweep','quota_lookup','create','get','claim','dispatch','receipt','discard_prepared','play_prepared','finish','fail','control','contribute','remove']);
const POD_TIMEOUT_CODES = new Set(['ETIMEDOUT','UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT']);
const storageMessage = action => action === 'contribute'
  ? 'Your comment could not be confirmed as saved. Keep your text and retry.'
  : 'Your pod could not be confirmed. Refresh before trying again.';

// SDK transport failures can arrive as resolved PostgREST results with status 0
// and an empty SQL code. Inspect only enough to classify; never log provider text.
function storageDiagnostic(action, error, response, elapsedMs) {
  const code = typeof error?.code === 'string' && /^(?:[0-9A-Z]{5}|PGRST[0-9]{3})$/.test(error.code) ? error.code : null;
  const status = response?.status ?? error?.status;
  const httpStatus = Number.isInteger(status) && status >= 100 && status <= 599 ? status : null;
  const wrappedName = typeof error?.message === 'string' ? error.message.match(/^(TimeoutError|AbortError|TypeError|FetchError):/)?.[1] : null;
  const timeout = error?.name === 'TimeoutError' || wrappedName === 'TimeoutError' ||
    POD_TIMEOUT_CODES.has(error?.code) || POD_TIMEOUT_CODES.has(error?.cause?.code) || httpStatus === 408 || httpStatus === 504;
  const transport = status === 0 || ['AbortError','TypeError','FetchError'].includes(error?.name) ||
    ['AbortError','TypeError','FetchError'].includes(wrappedName) || (!code && !httpStatus && !!error);
  return {action:POD_STORAGE_ACTIONS.has(action) ? action : 'unknown',category:timeout ? 'timeout' : transport ? 'transport' : 'database',
    elapsedMs:Number.isFinite(elapsedMs) ? Math.max(0,Math.round(elapsedMs)) : 0,code,httpStatus};
}

export function createPodStore({database, logger = console, now = Date.now} = {}) {
  const call = async (actor, action, id = null, data = {}) => {
    if (!database || (!actor && action !== 'sweep')) throw new PodStorageError('Sign in before starting your pod.', actor ? 503 : 401);
    let response;
    const startedAt = now();
    const unavailable = error => {
      try { logger.warn?.('Pod storage unavailable', storageDiagnostic(action, error, response, now()-startedAt)); } catch {}
      return new PodStorageError(storageMessage(action));
    };
    try {
      response = await database.rpc('korlix_pod_v1', {p_actor:actor, p_action:action, p_id:id, p_data:data});
    } catch (error) {
      throw unavailable(error);
    }
    if (response?.error) {
      const e = response.error;
      const status = {P0002:404, '40001':409, '23505':409, '54000':429, '42501':403, '22023':400, P0001:400}[e.code];
      if (status) throw new PodStorageError(e.code === '23505' ? 'A pod or request is already active. Refresh before trying again.' : e.message, status, e.code);
      throw unavailable(e);
    }
    const value = Array.isArray(response?.data) ? response.data[0] : response?.data;
    if (!value || typeof value !== 'object') throw unavailable(null);
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
    discardPrepared: (actor, id, {requestId, version}) => call(actor, 'discard_prepared', id, {requestId, version}),
    playPrepared: (actor, id, {requestId, version}) => call(actor, 'play_prepared', id, {requestId, version}),
    finish: (actor, id, requestId, result) => call(actor, 'finish', id, {requestId, result}),
    fail: (actor, id, requestId, {error = 'This turn could not finish. Try a new request.', uncertain = false} = {}) => call(actor, 'fail', id, {requestId, error, uncertain}),
    control: (actor, id, action) => call(actor, 'control', id, {action}),
    contribute: (actor, id, {requestId, text}) => call(actor, 'contribute', id, {requestId, text}),
    remove: (actor, id, {confirmed = false} = {}) => call(actor, 'remove', id, {confirmed}),
  });
}
