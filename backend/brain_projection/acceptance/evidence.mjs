const authCodes = new Set(['RefererNotAllowedMapError', 'RefererDeniedMapError', 'InvalidKeyMapError', 'MissingKeyMapError', 'ExpiredKeyMapError',
  'ApiNotActivatedMapError', 'ApiTargetBlockedMapError', 'BillingNotEnabledMapError', 'ClientBillingNotEnabledMapError', 'ProjectDeniedMapError', 'OverQuotaMapError']);
export const sdkVersion = value => typeof value === 'string' && /^\d{1,3}(?:\.\d{1,4}){1,3}[a-z]?$/.test(value) ? value : null;
export function providerErrorCode(values) {
  for (const value of values) {
    if (typeof value !== 'string' || !value.includes('Google Maps JavaScript API error')) continue;
    const code = /Google Maps JavaScript API error:\s*([A-Za-z]+MapError)\b/.exec(value)?.[1];
    return authCodes.has(code) ? code : 'GoogleMapsError';
  }
  return null;
}

export function sanitizeEvidence(value, negative) {
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
    providerErrorCodes: Array.isArray(value.providerErrorCodes) ? value.providerErrorCodes.filter(code => authCodes.has(code) || code === 'GoogleMapsError').slice(0, 12) : [],
    documentReferrerPolicy: negative ? 'no-referrer' : 'strict-origin-when-cross-origin'};
}

export function classifyObservation(report, negative) {
  const sdk = report.sdk, tester = report.tester;
  if (!report.startedAt) return 'NOT_PERFORMED';
  if (negative) {
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
