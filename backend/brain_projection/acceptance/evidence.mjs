const authCodes = new Set(['RefererNotAllowedMapError', 'RefererDeniedMapError', 'InvalidKeyMapError', 'MissingKeyMapError', 'ExpiredKeyMapError',
  'ApiNotActivatedMapError', 'ApiTargetBlockedMapError', 'BillingNotEnabledMapError', 'ClientBillingNotEnabledMapError', 'ProjectDeniedMapError', 'OverQuotaMapError']);
const cspDirectives = new Set(['default-src', 'script-src', 'script-src-elem', 'script-src-attr', 'style-src', 'style-src-elem', 'style-src-attr',
  'connect-src', 'img-src', 'font-src', 'worker-src', 'child-src', 'frame-src', 'frame-ancestors', 'media-src', 'manifest-src',
  'object-src', 'base-uri', 'form-action', 'require-trusted-types-for', 'trusted-types']);
const resourceKinds = new Set(['unknown', 'inline', 'eval', 'wasm-eval', 'data', 'blob', 'self', 'google-maps', 'google-static',
  'google-fonts', 'google-api', 'google', 'extension', 'external']);
const dispositionKinds = new Set(['enforce', 'report']);
const acceptanceModes = new Set(['standard', 'no-referrer', 'wrong-origin']);
// Preserve existing callers while browser reports use explicit scenario names.
const acceptanceMode = value => value === true ? 'no-referrer' : value === false || value === undefined ? 'standard' : value;

function resourceKind(value, ownOrigin) {
  if (typeof value !== 'string' || !value || value.length > 8192) return 'unknown';
  if (['inline', 'eval', 'wasm-eval'].includes(value)) return value;
  let url;
  try { url = new URL(value); } catch { return 'unknown'; }
  if (url.protocol === 'blob:') return 'blob';
  if (url.protocol === 'data:') return 'data';
  if (['chrome-extension:', 'moz-extension:', 'safari-web-extension:'].includes(url.protocol)) return 'extension';
  if (!['https:', 'http:'].includes(url.protocol)) return 'unknown';
  if (url.origin === ownOrigin) return 'self';
  const host = url.hostname;
  const inDomain = domain => host === domain || host.endsWith(`.${domain}`);
  if (host === 'maps.googleapis.com') return 'google-maps';
  if (host === 'fonts.googleapis.com' || host === 'fonts.gstatic.com') return 'google-fonts';
  if (inDomain('gstatic.com')) return 'google-static';
  if (inDomain('googleapis.com')) return 'google-api';
  if (inDomain('google.com') || inDomain('googleusercontent.com')) return 'google';
  return 'external';
}

function sanitizeCspEvent(value) {
  return {effectiveDirective: cspDirectives.has(value?.effectiveDirective) ? value.effectiveDirective : 'unknown',
    disposition: dispositionKinds.has(value?.disposition) ? value.disposition : 'unknown',
    blockedResource: resourceKinds.has(value?.blockedResource) ? value.blockedResource : 'unknown',
    sourceResource: resourceKinds.has(value?.sourceResource) ? value.sourceResource : 'unknown'};
}

// Only fixed labels leave the frame: never URL paths, origins, credentials,
// snippets, the nonce-bearing policy, or browser/referrer metadata.
export function summarizeCspViolation(event, ownOrigin) {
  return sanitizeCspEvent({effectiveDirective: event?.effectiveDirective, disposition: event?.disposition,
    blockedResource: resourceKind(event?.blockedURI, ownOrigin), sourceResource: resourceKind(event?.sourceFile, ownOrigin)});
}

// Interaction gathers evidence; it is not an acceptance verdict. A CSP event
// stays blocking in classifyObservation without locking a usable map's controls.
export function cameraControlsReady(report) {
  const sdk = report?.sdk;
  return Boolean(report && !report.closedAt && report.rendererStatus === 'ready' && sdk?.steady === true &&
    !sdk.mapError && !sdk.loaderError && !sdk.pageError && !sdk.providerErrorCodes?.length);
}

export const sdkVersion = value => typeof value === 'string' && /^\d{1,3}(?:\.\d{1,4}){1,3}[a-z]?$/.test(value) ? value : null;
export function providerErrorCode(values) {
  for (const value of values) {
    if (typeof value !== 'string' || !value.includes('Google Maps JavaScript API error')) continue;
    const code = /Google Maps JavaScript API error:\s*([A-Za-z]+MapError)\b/.exec(value)?.[1];
    return authCodes.has(code) ? code : 'GoogleMapsError';
  }
  return null;
}

export function sanitizeEvidence(value, mode) {
  if (!value || typeof value !== 'object') return null;
  const count = v => Number.isInteger(v) && v >= 0 ? Math.min(100, v) : 0;
  const loader = value.loader;
  return {started: value.started === true,
    loader: loader ? {channel: loader.channel === 'quarterly' ? 'quarterly' : 'unexpected', loading: loader.loading === 'async' ? 'async' : 'unexpected',
      authorizationReferrerPolicy: loader.authorizationReferrerPolicy === 'origin' ? 'origin' : 'unexpected',
      scriptReferrerPolicy: ['no-referrer', 'strict-origin-when-cross-origin'].includes(loader.scriptReferrerPolicy) ? loader.scriptReferrerPolicy : 'unexpected'} : null,
    sdkVersion: sdkVersion(value.sdkVersion), steady: value.steady === true, everSteady: value.everSteady === true,
    steadyEvents: count(value.steadyEvents), animationEnds: count(value.animationEnds),
    mapError: value.mapError === true, loaderError: value.loaderError === true, pageError: value.pageError === true,
    cspViolations: count(value.cspViolations),
    cspEvents: Array.isArray(value.cspEvents) ? value.cspEvents.slice(0, 8).map(sanitizeCspEvent) : [],
    providerErrorCodes: Array.isArray(value.providerErrorCodes) ? value.providerErrorCodes.filter(code => authCodes.has(code) || code === 'GoogleMapsError').slice(0, 12) : [],
    documentReferrerPolicy: acceptanceMode(mode) === 'no-referrer' ? 'no-referrer' : 'strict-origin-when-cross-origin'};
}

export function classifyObservation(report, mode) {
  const sdk = report.sdk, tester = report.tester;
  if (!report.startedAt) return 'NOT_PERFORMED';
  const scenario = acceptanceMode(mode ?? report.scenario);
  if (!acceptanceModes.has(scenario)) return 'INCONCLUSIVE';
  if (scenario === 'wrong-origin') {
    if (sdk?.everSteady || sdk?.steady) return 'WRONG_ORIGIN_CHECK_FAILED_SCENE_RENDERED';
    // The page origin must actually be unapproved. Suppressing a header on an
    // approved origin is a separate probe and cannot supply this confirmation.
    return report.rendererStatus === 'error' && sdk?.steady === false && sdk?.everSteady === false &&
      Array.isArray(sdk?.providerErrorCodes) && sdk.providerErrorCodes.length === 1 && sdk.providerErrorCodes[0] === 'RefererNotAllowedMapError' &&
      sdk?.loader?.channel === 'quarterly' && sdk.loader.loading === 'async' &&
      sdk.loader.authorizationReferrerPolicy === 'origin' && sdk.loader.scriptReferrerPolicy === 'strict-origin-when-cross-origin' &&
      sdk.documentReferrerPolicy === 'strict-origin-when-cross-origin' && tester?.currentOriginAbsentFromKeyAllowlist === true
      ? 'WRONG_ORIGIN_DENIAL_OBSERVED' : 'INCONCLUSIVE';
  }
  if (scenario === 'no-referrer') {
    if (sdk?.everSteady || sdk?.steady) return 'NEGATIVE_CHECK_FAILED_SCENE_RENDERED';
    // RefererDeniedMapError is a terms-of-service block, not referrer proof.
    return report.rendererStatus === 'error' && sdk?.providerErrorCodes?.includes('RefererNotAllowedMapError') &&
      sdk?.loader?.scriptReferrerPolicy === 'no-referrer' && sdk.documentReferrerPolicy === 'no-referrer' &&
      tester.googleSdkAndAuthorizationRequestsHadNoReferer === true
      ? 'NO_REFERRER_DENIAL_OBSERVED' : 'INCONCLUSIVE';
  }
  const errors = Boolean(sdk?.mapError || sdk?.loaderError || sdk?.pageError || sdk?.cspViolations || sdk?.providerErrorCodes?.length);
  return sdk?.steady && sdkVersion(sdk.sdkVersion) && sdk?.loader?.channel === 'quarterly' && sdk.loader.loading === 'async' &&
    sdk.loader.authorizationReferrerPolicy === 'origin' && sdk.loader.scriptReferrerPolicy === 'strict-origin-when-cross-origin' &&
    report.rendererStatus === 'ready' && !errors && report.cameraCommands.includes('flyTo') &&
    tester.imageryAndControlsConfirmed === true && tester.attributionAndLinksConfirmed === true
    ? 'POSITIVE_OBSERVATION_COMPLETE' : 'VISUAL_OR_SDK_REVIEW_PENDING';
}
