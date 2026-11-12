// Explicit, one-attempt browser probe for a different API. It uses the public
// acceptance key and the browser's real referrer; it never constructs a Referer
// header, requests account credentials, loads the Maps SDK, or activates maps.
export const API_RESTRICTION_ENDPOINT = 'https://identitytoolkit.googleapis.com/v1/projects';
const service = 'identitytoolkit.googleapis.com';
const knownReasons = new Set(['API_KEY_SERVICE_BLOCKED', 'API_KEY_HTTP_REFERRER_BLOCKED',
  'API_KEY_INVALID', 'SERVICE_DISABLED', 'BILLING_DISABLED', 'API_KEY_IP_ADDRESS_BLOCKED',
  'API_KEY_ANDROID_APP_BLOCKED', 'API_KEY_IOS_APP_BLOCKED', 'CONSUMER_INVALID', 'RATE_LIMIT_EXCEEDED']);
const knownStatuses = new Set(['PERMISSION_DENIED', 'UNAUTHENTICATED', 'INVALID_ARGUMENT',
  'RESOURCE_EXHAUSTED', 'NOT_FOUND', 'INTERNAL', 'UNAVAILABLE', 'DEADLINE_EXCEEDED']);

export function summarizeApiRestriction(status, body) {
  const error = body && typeof body === 'object' && !Array.isArray(body) ? body.error : null;
  const detailsTruncated = Array.isArray(error?.details) && error.details.length > 20;
  const errorInfo = [];
  for (const item of Array.isArray(error?.details) ? error.details.slice(0, 20) : []) {
    if (item?.['@type'] !== 'type.googleapis.com/google.rpc.ErrorInfo') continue;
    errorInfo.push({type: 'type.googleapis.com/google.rpc.ErrorInfo',
      reason: knownReasons.has(item.reason) ? item.reason : 'UNRECOGNIZED',
      domain: item.domain === 'googleapis.com' ? 'googleapis.com' : null,
      service: item.metadata?.service === service ? service : null});
  }
  const response = {httpStatus: Number.isInteger(status) && status >= 100 && status <= 599 ? status : null,
    errorCode: Number.isInteger(error?.code) && error.code >= 100 && error.code <= 599 ? error.code : null,
    errorStatus: knownStatuses.has(error?.status) ? error.status : null, errorInfo, detailsTruncated};
  const denied = response.httpStatus === 403 && response.errorCode === 403 &&
    response.errorStatus === 'PERMISSION_DENIED' && !detailsTruncated && errorInfo.length === 1 &&
    errorInfo[0].reason === 'API_KEY_SERVICE_BLOCKED' && errorInfo[0].domain === 'googleapis.com' &&
    errorInfo[0].service === service;
  return {response, observation: denied ? 'DISALLOWED_API_DENIAL_OBSERVED' : 'API_RESTRICTION_CHECK_INCONCLUSIVE'};
}

async function boundedJson(response) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Response unavailable');
  const chunks = []; let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 65536) { await reader.cancel(); throw new Error('Response too large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export function createApiRestrictionProbe({browserKey, origin, fetchImpl = fetch, now = () => new Date().toISOString()} = {}) {
  let attempted = false;
  return async () => {
    if (attempted) throw new Error('This page has already attempted the check.');
    attempted = true;
    const report = {evidenceVersion: 1, check: 'other_api_restriction', origin,
      productionActivation: false, overallVerification: 'NOT_ESTABLISHED',
      startedAt: now(), closedAt: null, observation: 'NOT_PERFORMED',
      request: {method: 'GET', endpoint: API_RESTRICTION_ENDPOINT,
        authentication: 'Existing public acceptance key in X-Goog-Api-Key; value excluded',
        credentialsMode: 'omit', redirectMode: 'error', referrerPolicy: 'strict-origin-when-cross-origin',
        referrerOverridden: false, requestBodySent: false, automaticRetries: 0, providerFetchAttempts: 0,
        actualRefererHeader: 'NOT_CAPTURED_BY_PAGE'}, response: {}};
    if (typeof browserKey !== 'string' || !/^[A-Za-z0-9_-]{20,200}$/.test(browserKey)) {
      return {...report, closedAt: now(), setup: 'Acceptance key unavailable'};
    }
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 15000);
    try {
      report.request.providerFetchAttempts = 1;
      const response = await fetchImpl(API_RESTRICTION_ENDPOINT, {method: 'GET', mode: 'cors',
        headers: {Accept: 'application/json', 'X-Goog-Api-Key': browserKey},
        credentials: 'omit', cache: 'no-store', redirect: 'error',
        referrerPolicy: 'strict-origin-when-cross-origin', signal: abort.signal});
      const body = await boundedJson(response);
      Object.assign(report, summarizeApiRestriction(response.status, body));
    } catch {
      report.observation = 'API_RESTRICTION_CHECK_INCONCLUSIVE';
      report.response = {transportOrResponseUnavailable: true};
    } finally { clearTimeout(timeout); report.closedAt = now(); }
    return report;
  };
}

if (typeof document !== 'undefined') {
  const button = document.getElementById('api-check');
  const evidence = document.getElementById('api-evidence');
  const status = document.getElementById('api-status');
  const run = createApiRestrictionProbe({browserKey: document.querySelector('meta[name="korlix-map-key"]')?.content,
    origin: location.origin});
  document.getElementById('origin').textContent = location.origin;
  button.addEventListener('click', async () => {
    if (button.disabled) return;
    button.disabled = true; status.textContent = 'Checking the API restriction…';
    const report = await run();
    evidence.textContent = JSON.stringify(report, null, 2);
    status.textContent = report.observation === 'DISALLOWED_API_DENIAL_OBSERVED'
      ? 'Google rejected this API because of the key’s API restriction.'
      : 'The response did not establish an API-restriction denial. See the sanitized result below.';
  });
}
