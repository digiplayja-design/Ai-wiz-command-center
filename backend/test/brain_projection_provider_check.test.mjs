import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {checkProjectionActivationConfiguration} from '../tools/check_projection_provider.mjs';

const browserKey = 'sensitive-maps-js-key-fixture-12345';
const privateKey = 'sensitive-private-geocoding-fixture';
const environment = Object.freeze({BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: browserKey,
  KORLIX_PUBLIC_BACKEND_URL: 'https://korlix.com', BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: 'false',
  BRAIN_PROJECTION_GEOCODING_KEY: privateKey});
const check = overrides => checkProjectionActivationConfiguration({environment: {...environment, ...overrides}});

test('valid structural configuration remains explicitly unverified without any network', () => {
  const originalFetch = globalThis.fetch;
  let networkCalls = 0;
  globalThis.fetch = () => { networkCalls++; throw new Error('Offline preflight must never fetch.'); };
  try {
    const result = check();
    assert.equal(result.status, 'NOT_VERIFIED');
    assert.equal(result.exitCode, 2);
    assert.equal(result.liveVerification, 'not_performed');
    assert.equal(result.liveProviderVerified, false);
    assert.equal(result.requestsMade, 0);
    assert.equal(networkCalls, 0);
    assert.deepEqual(result.blockers, []);
    assert.equal(result.configuration.origin, 'https://korlix.com');
    assert.equal(result.configuration.rendererConfiguredToExposeKey, false);
    assert.equal(result.requiredGoogleSetup.serviceId, 'maps-backend.googleapis.com');
    assert.deepEqual(result.requiredGoogleSetup.browserKeyApiAllowlist, ['maps-backend.googleapis.com']);
    assert.equal(result.requiredGoogleSetup.channel, 'quarterly');
    assert.equal(result.requiredGoogleSetup.library, 'maps3d');
    assert.ok(result.requiredLiveChecks.every(item => item.status === 'NOT_PERFORMED'));
  } finally { globalThis.fetch = originalFetch; }
});

test('asserting a deployment flag is not provider verification', () => {
  for (const flag of ['true', 'false', undefined, 'TRUE', '1', ' true ']) {
    const result = check({BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: flag});
    assert.equal(result.status, 'NOT_VERIFIED');
    assert.equal(result.exitCode, 2);
    assert.equal(result.liveProviderVerified, false);
    const asserted = typeof flag === 'string' && flag.trim() === 'true';
    assert.equal(result.configuration.restrictionsFlagAsserted, asserted);
    assert.equal(result.configuration.rendererConfiguredToExposeKey, asserted);
  }
  assert.equal(environment.BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED, 'false');
});

test('legacy Tiles credentials and verification flag cannot supply the new browser key', () => {
  const result = check({BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: undefined,
    BRAIN_PROJECTION_MAP_BROWSER_KEY: browserKey, BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED: 'true'});
  assert.equal(result.status, 'INVALID_CONFIGURATION');
  assert.equal(result.exitCode, 1);
  assert.equal(result.configuration.browserKeyPresent, false);
  assert.equal(result.configuration.legacyTilesVariablesIgnored, true);
  assert.equal(result.configuration.rendererConfiguredToExposeKey, false);
  assert.deepEqual(result.blockers.map(item => item.code), ['valid_maps_js_browser_key_required']);
});

test('missing or malformed browser credentials fail structural validation', () => {
  for (const key of [undefined, '', 'short', 'bad key with spaces 1234567890', 'bad\nkey-12345678901234567890', 'x'.repeat(201), 123]) {
    const result = check({BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: key});
    assert.equal(result.status, 'INVALID_CONFIGURATION');
    assert.equal(result.exitCode, 1);
    assert.ok(result.blockers.some(item => item.code === 'valid_maps_js_browser_key_required'));
    assert.equal(result.configuration.rendererConfiguredToExposeKey, false);
  }
  assert.equal(check({BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: ` ${browserKey} `}).status, 'NOT_VERIFIED');
});

test('a reused server key is rejected but geocoding is optional for structural map preflight', () => {
  const result = check({BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: ` ${privateKey} `,
    BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: 'true'});
  assert.equal(result.status, 'INVALID_CONFIGURATION');
  assert.equal(result.configuration.distinctFromGeocodingKey, false);
  assert.equal(result.configuration.rendererConfiguredToExposeKey, false);
  assert.ok(result.blockers.some(item => item.code === 'browser_key_must_differ_from_geocoding_key'));
  assert.equal(check({BRAIN_PROJECTION_GEOCODING_KEY: undefined}).status, 'NOT_VERIFIED');
});

test('origin validation matches production and never echoes invalid origin secrets', () => {
  for (const origin of [undefined, '', 'http://korlix.com', 'https://127.0.0.1', 'https://localhost',
    'https://korlix.invalid', 'https://user:private-origin-secret@korlix.com',
    'https://korlix.com/path', 'https://korlix.com?key=private-origin-secret',
    'https://korlix.com#private-origin-secret', 'https://korlix.com:8443']) {
    const result = check({KORLIX_PUBLIC_BACKEND_URL: origin, RENDER_EXTERNAL_URL: undefined});
    assert.equal(result.status, 'INVALID_CONFIGURATION', String(origin));
    assert.equal(result.configuration.origin, null);
    assert.doesNotMatch(JSON.stringify(result), /private-origin-secret/);
  }
  assert.equal(check({KORLIX_PUBLIC_BACKEND_URL: '', RENDER_EXTERNAL_URL: 'https://korlix.onrender.com'}).configuration.origin,
    'https://korlix.onrender.com');
  assert.equal(check({RENDER_EXTERNAL_URL: 'https://other.onrender.com'}).configuration.origin, 'https://korlix.com');
});

test('manual verification demands browser and restriction-specific observations', () => {
  const result = check();
  assert.deepEqual(result.requiredLiveChecks.map(item => item.id), [
    'allowed_origin_browser', 'unrelated_origin_browser', 'missing_referrer_browser', 'other_api_restriction', 'native_devices',
  ]);
  const requirements = result.requiredLiveChecks.map(item => item.requiredObservation).join(' ');
  assert.match(requirements, /gmp-steadychange/);
  assert.match(requirements, /HTTP 200 loader.*not evidence/);
  assert.match(requirements, /RefererNotAllowedMapError/);
  assert.match(requirements, /API_KEY_SERVICE_BLOCKED/);
  assert.match(requirements, /generic.*inconclusive/);
  assert.match(requirements, /billing, quota.*not proof/);
  assert.match(requirements, /legal links/);
});

test('result never exposes keys, including when configured or duplicated', () => {
  for (const overrides of [{}, {BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: 'true'},
    {BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: privateKey}, {BRAIN_PROJECTION_MAP_BROWSER_KEY: 'legacy-sensitive-secret-12345'}]) {
    assert.doesNotMatch(JSON.stringify(check(overrides)), /sensitive-maps|sensitive-private|legacy-sensitive/);
  }
  const result = checkProjectionActivationConfiguration({environment: null});
  assert.equal(result.exitCode, 1);
  assert.equal(result.requestsMade, 0);
});

const checker = fileURLToPath(new URL('../tools/check_projection_provider.mjs', import.meta.url));
function cli(args = [], overrides = {}) {
  const child = spawnSync(process.execPath, [checker, ...args], {
    env: {PATH: process.env.PATH, ...environment, ...overrides}, encoding: 'utf8', timeout: 10000,
  });
  assert.equal(child.error, undefined);
  assert.equal(child.stderr, '');
  return {code: child.status, result: JSON.parse(child.stdout), output: child.stdout};
}

test('CLI returns exit 2 for valid-but-unverified configuration and exit 1 for missing config', () => {
  for (const flag of ['false', 'true']) {
    const result = cli([], {BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: flag});
    assert.equal(result.code, 2);
    assert.equal(result.result.status, 'NOT_VERIFIED');
    assert.equal(result.result.liveProviderVerified, false);
    assert.doesNotMatch(result.output, /sensitive-maps|sensitive-private/);
  }
  const missing = cli([], {BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: ''});
  assert.equal(missing.code, 1);
  assert.equal(missing.result.status, 'INVALID_CONFIGURATION');
});

test('CLI rejects removed live-network opt-in and all unexpected arguments without echoing them', () => {
  for (const args of [['--allow-provider-check'], ['--allow-provider-check', '--allow-provider-check'],
    ['--key=sensitive-cli-key'], ['--url=https://private.invalid/path']]) {
    const result = cli(args);
    assert.equal(result.code, 1);
    assert.equal(result.result.status, 'INVALID_ARGUMENTS');
    assert.equal(result.result.requestsMade, 0);
    assert.equal(result.result.liveVerification, 'not_performed');
    assert.doesNotMatch(result.output, /sensitive-cli-key|private\.invalid/);
    if (args.includes('--allow-provider-check')) assert.equal(result.result.reason, 'live_provider_check_option_removed');
  }
});
