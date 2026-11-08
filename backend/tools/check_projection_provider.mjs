import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {projectionConfiguration} from '../brain_projection/core.mjs';

// OFFLINE ONLY. Configuration shape does not prove Google authorization,
// enabled services, billing, browser referrers, imagery or device compatibility.
// A deployment flag is an operator assertion, not evidence. Valid configuration
// exits 2 (not verified), never 0/PASS. No network options or key output exist.
const text = (environment, name) => typeof environment?.[name] === 'string' ? environment[name].trim() : '';
const BROWSER_KEY = 'BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY';
const VERIFIED_FLAG = 'BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED';
const documentation = Object.freeze({
  keys: 'https://developers.google.com/maps/documentation/javascript/get-api-key',
  restrictions: 'https://developers.google.com/maps/api-security-best-practices',
  loader: 'https://developers.google.com/maps/documentation/javascript/load-maps-js-api',
  errors: 'https://developers.google.com/maps/documentation/javascript/error-messages',
  readiness: 'https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map#SteadyChangeEvent',
  billing: 'https://developers.google.com/maps/documentation/javascript/usage-and-billing',
});

function requiredLiveChecks() {
  return [
    {id: 'allowed_origin_browser', status: 'NOT_PERFORMED',
      requiredObservation: 'Using the owner-provisioned key, load the actual HTTPS renderer on its permitted origin in a real browser. Confirm visible geographic 3D imagery, gmp-steadychange with isSteady=true, no authentication error, and unobscured SDK attribution with working legal links. An HTTP 200 loader, constructor or synthetic SDK fixture is not evidence.'},
    {id: 'unrelated_origin_browser', status: 'NOT_PERFORMED',
      requiredObservation: 'Run a controlled browser load from an unapproved HTTPS origin and record a specific referrer-restriction denial such as RefererNotAllowedMapError. A generic 403, failed fetch or blank map is inconclusive.'},
    {id: 'missing_referrer_browser', status: 'NOT_PERFORMED',
      requiredObservation: 'Run a controlled browser load that omits the referrer and record a specific referrer-restriction denial. Confirm the test actually omitted the header. Server requests with spoofed headers do not establish WebView behavior.'},
    {id: 'other_api_restriction', status: 'NOT_PERFORMED',
      requiredObservation: 'Inspect the key API allowlist and, in an owner-authorized negative check, record rejection by a disallowed API specifically because of API-key service restrictions (for example API_KEY_SERVICE_BLOCKED). Disabled service, billing, quota or generic REQUEST_DENIED errors are not proof.'},
    {id: 'native_devices', status: 'NOT_PERFORMED',
      requiredObservation: 'On supported iOS and Android devices, confirm the remote HTTPS iframe sends the accepted referrer, renders 3D, completes camera commands, keeps all attribution and legal links usable, and stops work when closed. Repeat an authentication-denied load and verify the sanitized fallback.'},
  ];
}

export function checkProjectionActivationConfiguration({environment = process.env} = {}) {
  const input = environment && typeof environment === 'object' ? environment : {};
  const browserKey = text(input, BROWSER_KEY);
  const geocodingKey = text(input, 'BRAIN_PROJECTION_GEOCODING_KEY');
  const browserKeyShapeValid = /^[A-Za-z0-9_-]{20,200}$/u.test(browserKey);
  const distinctFromGeocodingKey = Boolean(browserKey && browserKey !== geocodingKey);
  // Reuse production origin validation. Invalid input may contain secrets, so
  // report only its failure, never its original value.
  const {origin, browserKey: exposedBrowserKey} = projectionConfiguration(input);
  const blockers = [];
  if (!browserKeyShapeValid) blockers.push({code: 'valid_maps_js_browser_key_required', variable: BROWSER_KEY});
  if (browserKey && !distinctFromGeocodingKey) blockers.push({code: 'browser_key_must_differ_from_geocoding_key', variable: BROWSER_KEY});
  if (!origin) blockers.push({code: 'valid_public_https_origin_required', variable: 'KORLIX_PUBLIC_BACKEND_URL or RENDER_EXTERNAL_URL'});
  const valid = blockers.length === 0;
  return {
    provider: 'google-maps-javascript-3d', validationKind: 'offline-configuration-only',
    status: valid ? 'NOT_VERIFIED' : 'INVALID_CONFIGURATION', exitCode: valid ? 2 : 1,
    liveVerification: 'not_performed', liveProviderVerified: false, requestsMade: 0,
    configuration: {
      browserKeyPresent: Boolean(browserKey), browserKeyShapeValid, distinctFromGeocodingKey,
      origin, restrictionsFlagAsserted: text(input, VERIFIED_FLAG) === 'true',
      rendererConfiguredToExposeKey: Boolean(exposedBrowserKey && origin),
      geocodingKeyPresent: Boolean(geocodingKey),
      legacyTilesVariablesIgnored: Boolean(text(input, 'BRAIN_PROJECTION_MAP_BROWSER_KEY') ||
        text(input, 'BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED')),
    },
    blockers,
    requiredGoogleSetup: {
      service: 'Maps JavaScript API', serviceId: 'maps-backend.googleapis.com', channel: 'quarterly', library: 'maps3d',
      applicationRestriction: 'Websites (HTTP referrers)', permittedHttpsOrigin: origin,
      restrictionScope: 'Match the HTTPS origin without a path because auth_referrer_policy=origin is used.',
      browserKeyApiAllowlist: ['maps-backend.googleapis.com'],
      billing: 'Production requires the intended project, enabled Maps JavaScript API, linked billing, and reviewed quotas and budgets. The Immersive Maps SKU is billed per successful map load.',
      geocoding: 'Keep the private server Geocoding key separate. Legacy Map Tiles credentials do not activate this renderer.',
    },
    requiredLiveChecks: requiredLiveChecks(),
    activationRule: `Keep ${VERIFIED_FLAG}=false until the required live observations have been reviewed. This command never sets that flag and never proves its assertion.`,
    documentation,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let result;
  try {
    const args = process.argv.slice(2);
    result = args.length ? {
      validationKind: 'offline-configuration-only', status: 'INVALID_ARGUMENTS', exitCode: 1,
      reason: args.includes('--allow-provider-check') ? 'live_provider_check_option_removed' : 'unexpected_arguments',
      liveVerification: 'not_performed', liveProviderVerified: false, requestsMade: 0,
    } : checkProjectionActivationConfiguration();
  } catch {
    result = {validationKind: 'offline-configuration-only', status: 'INVALID_CONFIGURATION', exitCode: 1,
      reason: 'configuration_check_failed', liveVerification: 'not_performed', liveProviderVerified: false, requestsMade: 0};
  }
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.exitCode;
}
