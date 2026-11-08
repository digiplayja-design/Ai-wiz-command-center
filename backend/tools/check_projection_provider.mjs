import {isIP} from 'node:net';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

// Manual, opt-in provider diagnostic. It does not enable APIs, create keys,
// change environment variables, or mark the renderer as verified. Never run in
// CI with a real key. At most THREE root tileset requests and ONE basic
// Geocoding request can be billable; stop at the first failed/inconclusive check.
// It checks provider restrictions, not browser CORS/WebGL or native WebViews.
// Fixed public Geocoding fixture and field mask are documented at:
// https://developers.google.com/maps/documentation/geocoding/geocoding
// Restriction-specific ErrorInfo reasons (generic 403/REQUEST_DENIED is not proof):
// https://docs.cloud.google.com/php/docs/reference/common-protos/latest/Api.ErrorReason
const ROOT_URL = 'https://tile.googleapis.com/v1/3dtiles/root.json';
const GEOCODE_URL = 'https://geocode.googleapis.com/v4/geocode/address/1600+Amphitheatre+Parkway,+Mountain+View,+CA';
const UNRELATED_ORIGIN = 'https://korlix-provider-check.invalid';
const MAX_BODY_BYTES = 256 * 1024;
const DEFAULT_TIMEOUT_MS = 10000;
const CHECK_IDS = ['allowed_origin', 'unrelated_referrer', 'missing_referrer', 'other_api'];
export const MAX_POTENTIAL_BILLABLE_REQUESTS = Object.freeze({photorealistic3DRoot: 3, geocoding: 1, total: 4});

function initialResult() {
  return {status: 'FAIL', reason: 'not_run', requestsMade: 0,
    maxPotentialBillableRequests: {...MAX_POTENTIAL_BILLABLE_REQUESTS},
    checks: CHECK_IDS.map(id => ({id, status: 'NOT_RUN'}))};
}

function configuredOrigin(value) {
  if (typeof value !== 'string' || value.length > 2000 || /\s/u.test(value)) return null;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase(), labels = host.split('.');
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        url.pathname !== '/' || url.search || url.hash || isIP(host) || labels.length < 2 ||
        !/^[a-z]{2,63}$/iu.test(labels.at(-1)) ||
        labels.some(label => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/iu.test(label)) ||
        /(?:^|\.)(?:localhost|local|internal|test|invalid|example|lan|home|corp|onion|arpa)$/iu.test(host)) return null;
    return url.origin;
  } catch { return null; }
}

class ProbeFailure extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}

// The deadline includes response-body reading. Cancellation is best-effort and
// never awaited indefinitely. Only fixed local reason codes leave this helper.
async function fetchBoundedJson(fetchImpl, url, headers, timeoutMs) {
  const controller = new AbortController();
  let reader, timer, expired = false;
  const cancel = () => { try { void reader?.cancel().catch(() => {}); } catch {} };
  const deadline = new Promise((_resolve, reject) => {
    timer = setTimeout(() => {
      expired = true;
      controller.abort();
      cancel();
      reject(new ProbeFailure('timeout'));
    }, timeoutMs);
  });
  try {
    return await Promise.race([deadline, (async () => {
      const response = await fetchImpl(url, {method: 'GET', headers, redirect: 'error',
        credentials: 'omit', cache: 'no-store', signal: controller.signal});
      if (expired) { try { void response?.body?.cancel().catch(() => {}); } catch {} throw new ProbeFailure('timeout'); }
      if (!response || !Number.isInteger(response.status)) throw new ProbeFailure('invalid_provider_response');
      if (response.redirected || (response.status >= 300 && response.status < 400)) throw new ProbeFailure('redirect_rejected');
      const contentType = response.headers?.get('content-type') || '';
      if (!/^application\/(?:[a-z0-9.-]+\+)?json(?:\s*;|$)/iu.test(contentType)) throw new ProbeFailure('invalid_provider_response');
      const advertisedSize = Number(response.headers?.get('content-length'));
      if (Number.isFinite(advertisedSize) && advertisedSize > MAX_BODY_BYTES) throw new ProbeFailure('response_too_large');
      reader = response.body?.getReader();
      if (!reader) throw new ProbeFailure('invalid_provider_response');
      let size = 0;
      const chunks = [];
      while (true) {
        const {done, value} = await reader.read();
        if (expired) throw new ProbeFailure('timeout');
        if (done) break;
        if (!(value instanceof Uint8Array)) throw new ProbeFailure('invalid_provider_response');
        size += value.byteLength;
        if (size > MAX_BODY_BYTES) throw new ProbeFailure('response_too_large');
        chunks.push(value);
      }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks, size).toString('utf8')); }
      catch { throw new ProbeFailure('invalid_provider_response'); }
      return {httpStatus: response.status, body};
    })()]);
  } catch (error) {
    // Do not return thrown messages, response bodies, request URLs, or headers.
    throw new ProbeFailure(expired ? 'timeout' : error instanceof ProbeFailure ? error.reason : 'network_error');
  } finally {
    clearTimeout(timer);
    controller.abort();
    cancel();
    try { reader?.releaseLock(); } catch {}
  }
}

function errorReasons(body) {
  return Array.isArray(body?.error?.details) ? body.error.details
    .filter(detail => detail?.['@type'] === 'type.googleapis.com/google.rpc.ErrorInfo' &&
      detail.domain === 'googleapis.com' && typeof detail.reason === 'string')
    .map(detail => detail.reason) : [];
}

function providerProblem({body, httpStatus}) {
  const reasons = errorReasons(body);
  if (reasons.includes('API_KEY_INVALID') || reasons.includes('API_KEY_EXPIRED')) return 'invalid_key';
  if (reasons.includes('SERVICE_DISABLED')) return 'service_disabled';
  if (reasons.includes('BILLING_DISABLED')) return 'billing_disabled';
  if (httpStatus === 429 || body?.error?.status === 'RESOURCE_EXHAUSTED' ||
      reasons.some(reason => ['RATE_LIMIT_EXCEEDED', 'QUOTA_EXCEEDED'].includes(reason))) return 'quota_exhausted';
  if (httpStatus >= 500) return 'provider_unavailable';
  return null;
}

function rootSucceeded({body, httpStatus}) {
  const volume = body?.root?.boundingVolume;
  const finiteArray = (value, length) => Array.isArray(value) && value.length === length && value.every(Number.isFinite);
  return httpStatus === 200 && !body?.error && /^1\.[01]$/u.test(body?.asset?.version || '') &&
    Number.isFinite(body.geometricError) && body.geometricError >= 0 &&
    (finiteArray(volume?.box, 12) || finiteArray(volume?.sphere, 4) || finiteArray(volume?.region, 6));
}

function restrictionProven({body, httpStatus}, expectedReason) {
  const reasons = errorReasons(body);
  return httpStatus === 403 && body?.error?.code === 403 && body.error.status === 'PERMISSION_DENIED' &&
    reasons.length > 0 && reasons.every(reason => reason === expectedReason);
}

/**
 * Inject fetchImpl for deterministic tests. The key and origin are read only
 * from environment; the production restrictions-verified flag is not required.
 * PASS proves these four provider observations at this instant, not that every
 * possible Google API is excluded. Check the key's API allowlist in the console.
 */
export async function checkProjectionProviderRestrictions({environment = process.env,
  allowProviderCheck = false, fetchImpl = globalThis.fetch, timeoutMs = DEFAULT_TIMEOUT_MS} = {}) {
  const result = initialResult();
  if (allowProviderCheck !== true) return {...result, reason: 'explicit_opt_in_required'};
  const key = typeof environment?.BRAIN_PROJECTION_MAP_BROWSER_KEY === 'string'
    ? environment.BRAIN_PROJECTION_MAP_BROWSER_KEY.trim() : '';
  if (!/^[A-Za-z0-9_-]{20,200}$/u.test(key)) return {...result, reason: 'candidate_browser_key_required'};
  const origin = configuredOrigin(environment?.KORLIX_PUBLIC_BACKEND_URL);
  if (!origin) return {...result, reason: 'valid_public_backend_origin_required'};
  if (typeof fetchImpl !== 'function' || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) {
    return {...result, reason: 'invalid_check_configuration'};
  }
  const root = new URL(ROOT_URL);
  root.searchParams.set('key', key);
  const normalHeaders = {Accept: 'application/json', Origin: origin, Referer: `${origin}/`};
  const probes = [
    {id: 'allowed_origin', url: root.href, headers: normalHeaders},
    {id: 'unrelated_referrer', url: root.href,
      headers: {Accept: 'application/json', Origin: UNRELATED_ORIGIN, Referer: `${UNRELATED_ORIGIN}/`},
      expectedReason: 'API_KEY_HTTP_REFERRER_BLOCKED'},
    {id: 'missing_referrer', url: root.href, headers: {Accept: 'application/json', Origin: origin},
      expectedReason: 'API_KEY_HTTP_REFERRER_BLOCKED'},
    {id: 'other_api', url: GEOCODE_URL,
      headers: {...normalHeaders, 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'results.placeId'},
      expectedReason: 'API_KEY_SERVICE_BLOCKED'},
  ];
  for (const [index, probe] of probes.entries()) {
    result.requestsMade++;
    try {
      const response = await fetchBoundedJson(fetchImpl, probe.url, probe.headers, timeoutMs);
      const problem = providerProblem(response);
      const passed = !problem && (index === 0 ? rootSucceeded(response) : restrictionProven(response, probe.expectedReason));
      const unexpectedlyAccepted = index === 3
        ? response.httpStatus === 200 && !response.body?.error && Array.isArray(response.body?.results) && !response.body?.status
        : rootSucceeded(response);
      const reason = passed ? index === 0 ? 'root_tileset_returned' : 'expected_restriction_enforced'
        : problem || (index === 0 ? 'allowed_origin_not_verified'
          : unexpectedlyAccepted ? 'unexpected_request_accepted' : 'restriction_not_proven');
      result.checks[index] = {id: probe.id, status: passed ? 'PASS' : 'FAIL', reason, httpStatus: response.httpStatus};
      if (!passed) return {...result, reason};
    } catch (error) {
      const reason = error instanceof ProbeFailure ? error.reason : 'check_failed';
      result.checks[index] = {id: probe.id, status: 'FAIL', reason};
      return {...result, reason};
    }
  }
  return {...result, status: 'PASS', reason: 'four_provider_checks_verified'};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let result;
  try {
    const args = process.argv.slice(2);
    result = args.some(arg => arg !== '--allow-provider-check') || args.length > 1
      ? {...initialResult(), reason: 'unexpected_arguments'}
      : await checkProjectionProviderRestrictions({allowProviderCheck: args[0] === '--allow-provider-check'});
  } catch { result = {...initialResult(), reason: 'check_failed'}; }
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.status === 'PASS' ? 0 : 1;
}
