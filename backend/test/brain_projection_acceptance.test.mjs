import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {request as httpRequest} from 'node:http';
import {createAcceptanceServer, acceptanceMapPolicy, acceptancePort} from '../brain_projection/acceptance/server.mjs';
import {observeLoader} from '../brain_projection/acceptance/frame.mjs';
import {cameraControlsReady, classifyObservation, sanitizeEvidence, providerErrorCode, summarizeCspViolation} from '../brain_projection/acceptance/evidence.mjs';
import {rendererPolicy} from '../brain_projection/renderer.mjs';

const candidate = 'acceptance-browser-fixture-not-a-real-key';
async function serve(t, options) {
  const server = createAcceptanceServer(options);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  const request = (path, options) => fetch(`http://127.0.0.1:${server.address().port}${path}`, options);
  // Fetch normalizes encoded dot segments before sending; use raw HTTP to test
  // what this server actually rejects on the wire.
  request.rawStatus = path => new Promise((resolve, reject) => {
    const req = httpRequest({host: '127.0.0.1', port: server.address().port, path}, response => {
      response.resume(); response.on('end', () => resolve(response.statusCode));
    });
    req.on('error', reject); req.end();
  });
  return request;
}

test('missing candidate key leaves setup explicit and never reads production configuration', async t => {
  const names = ['BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY', 'BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED', 'BRAIN_PROJECTION_GEOCODING_KEY', 'OPENAI_API_KEY'];
  const saved = names.map(name => [name, process.env[name]]);
  for (const name of names) process.env[name] = name.endsWith('VERIFIED') ? 'true' : `private-${name}`;
  t.after(() => { for (const [name, value] of saved) { if (value === undefined) delete process.env[name]; else process.env[name] = value; } });
  const request = await serve(t);
  assert.deepEqual(await (await request('/health')).json(), {service: 'projection-map-acceptance', ready: true, candidateKeyConfigured: false, productionActivation: false});
  const html = await (await request('/')).text();
  assert.match(html, /Setup required/);
  assert.match(html, /id="start" disabled/);
  assert.doesNotMatch(html, /<iframe|maps\.googleapis\.com|private-/);
  const frame = await (await request('/frame/standard')).text();
  assert.match(frame, /name="korlix-map-key" content=""/);
  assert.match(frame, /id="begin" disabled/);
  assert.doesNotMatch(frame, /<script[^>]+earth\.mjs|private-/);
  const source = await readFile(new URL('../brain_projection/acceptance/server.mjs', import.meta.url), 'utf8');
  assert.deepEqual([...source.matchAll(/process\.env\.([A-Z_]+)/g)].map(match => match[1]).sort(), ['BRAIN_PROJECTION_ACCEPTANCE_BROWSER_KEY', 'PORT']);
  assert([...source.matchAll(/from ['"]([^'"]+)['"]/g)].every(match => match[1].startsWith('node:')));
});

test('configured root still waits for explicit loading and exposes no key in shell or health', async t => {
  const request = await serve(t, {browserKey: candidate});
  const health = await (await request('/health')).text();
  assert.equal(JSON.parse(health).candidateKeyConfigured, true);
  assert.equal(health.includes(candidate), false);
  const html = await (await request('/')).text();
  assert.equal(html.includes(candidate), false);
  assert.doesNotMatch(html, /<iframe|<script[^>]+earth\.mjs/);
  const response = await request('/frame/standard');
  const body = await response.text();
  assert.equal(body.includes(`content="${candidate}"`), true);
  assert.match(body, /Waiting for an explicit test/);
  assert.doesNotMatch(body, /<script[^>]+earth\.mjs/);
  const token = /script-src 'nonce-([^']+)'/.exec(response.headers.get('content-security-policy'))[1];
  assert.equal(response.headers.get('content-security-policy'), rendererPolicy(token));
  assert.match(body, new RegExp(`src="/acceptance/frame.mjs" nonce="${token}"`));
  const next = await request('/frame/standard');
  assert.notEqual(next.headers.get('content-security-policy'), response.headers.get('content-security-policy'));
});

test('negative frame sets document and header no-referrer while retaining nonce CSP and denied capabilities', async t => {
  const request = await serve(t, {browserKey: candidate});
  const response = await request('/frame/no-referrer');
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.match(await response.text(), /name="referrer" content="no-referrer"/);
  assert.equal(response.headers.get('permissions-policy'), 'camera=(), microphone=(), geolocation=(), payment=()');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(acceptanceMapPolicy('abcdefghijklmnopqrstuvwxyz'), rendererPolicy('abcdefghijklmnopqrstuvwxyz'));
});

test('released renderer assets are served byte-for-byte through a fixed allowlist', async t => {
  const request = await serve(t, {browserKey: candidate});
  for (const filename of ['earth.mjs', 'camera.mjs', 'earth.css']) {
    const response = await request(`/brain-projection/${filename}`);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), await readFile(new URL(`../brain_projection/public/${filename}`, import.meta.url), 'utf8'));
  }
  for (const path of ['/api/brain-projection/config', '/api/brain-voice/turn', '/proxy', '/.env', '/package.json', '/frame/unrecognized']) {
    assert.equal((await request(path)).status, 404, path);
  }
  for (const path of ['/?key=private-fixture', '/frame/standard?url=https://example.test', '//example.test']) {
    const response = await request(path);
    assert.equal(response.status, 400, path);
    assert.doesNotMatch(await response.text(), /private-fixture|example\.test/);
  }
  assert.equal(await request.rawStatus('/%2e%2e/server.js'), 400);
  const post = await request('/', {method: 'POST', body: 'key=private-fixture'});
  assert.equal(post.status, 405); assert.equal(post.headers.get('allow'), 'GET, HEAD');
  assert.doesNotMatch(await post.text(), /private-fixture/);
  assert.equal(await (await request('/', {method: 'HEAD'})).text(), '');
});

test('invalid candidate keys cannot inject HTML or activate a test', async t => {
  const request = await serve(t, {browserKey: '"><script>alert(1)</script>'});
  assert.equal((await (await request('/health')).json()).candidateKeyConfigured, false);
  assert.doesNotMatch(await (await request('/frame/standard')).text(), /alert\(1\)/);
  for (const value of ['0', '-1', '65536', '1.5', '3000;echo secret']) assert.throws(() => acceptancePort(value), /PORT/);
  assert.equal(acceptancePort(undefined), 10000); assert.equal(acceptancePort('43123'), 43123);
});

test('negative observer changes only the Google loader before insertion; positive observer leaves it intact', () => {
  for (const negative of [false, true]) {
    const observed = [], inserted = [];
    const head = {append(...nodes) { assert.equal(this, head); inserted.push(...nodes); },
      appendChild(node) { assert.equal(this, head); inserted.push(node); return node; }};
    const originalAppend = head.append;
    const restore = observeLoader({document: {head}, negative, onLoader: value => observed.push(value)});
    const loader = {tagName: 'SCRIPT', src: `https://maps.googleapis.com/maps/api/js?key=${candidate}&v=quarterly&loading=async&auth_referrer_policy=origin`, referrerPolicy: 'strict-origin-when-cross-origin'};
    const unrelated = {tagName: 'SCRIPT', src: 'https://unrelated.example/maps/api/js', referrerPolicy: 'strict-origin-when-cross-origin'};
    head.append(loader, unrelated); assert.equal(head.appendChild(loader), loader);
    assert.equal(loader.referrerPolicy, negative ? 'no-referrer' : 'strict-origin-when-cross-origin');
    assert.equal(unrelated.referrerPolicy, 'strict-origin-when-cross-origin');
    assert.equal(observed.length, 1); assert.equal(inserted.length, 3);
    assert.equal(JSON.stringify(observed).includes(candidate), false);
    restore(); assert.equal(head.append, originalAppend);
  }
});

function report() {
  return {startedAt: '2026-11-11T00:00:00Z', rendererStatus: 'ready', cameraCommands: ['flyTo'],
    sdk: {steady: true, everSteady: true, sdkVersion: '3.65.13a', animationEnds: 0,
      loader: {channel: 'quarterly', loading: 'async', authorizationReferrerPolicy: 'origin', scriptReferrerPolicy: 'strict-origin-when-cross-origin'}, providerErrorCodes: []},
    tester: {imageryAndControlsConfirmed: true, attributionAndLinksConfirmed: true}};
}

test('positive evidence requires current steady, exact loader contract and independent landmark/attribution review', () => {
  assert.equal(classifyObservation(report(), false), 'POSITIVE_OBSERVATION_COMPLETE');
  for (const mutate of [
    r => { r.sdk.steady = false; }, r => { r.sdk.sdkVersion = null; }, r => { r.sdk.loader = null; },
    r => { r.rendererStatus = 'loading'; }, r => { r.cameraCommands = []; },
    r => { r.tester.imageryAndControlsConfirmed = false; }, r => { r.tester.attributionAndLinksConfirmed = false; },
    ...['channel', 'loading', 'authorizationReferrerPolicy', 'scriptReferrerPolicy'].map(key => r => { r.sdk.loader[key] = 'unexpected'; }),
    ...['mapError', 'loaderError', 'pageError', 'cspViolations'].map(key => r => { r.sdk[key] = true; }),
    r => { r.sdk.providerErrorCodes = ['InvalidKeyMapError']; },
  ]) { const value = report(); mutate(value); assert.equal(classifyObservation(value, false), 'VISUAL_OR_SDK_REVIEW_PENDING'); }
});

test('the real iPad readiness case permits camera checks while one CSP violation keeps acceptance pending', () => {
  const value = report();
  value.cameraCommands = [];
  Object.assign(value.sdk, {sdkVersion: '3.65.14a', steady: true, everSteady: true, steadyEvents: 3,
    mapError: false, loaderError: false, pageError: false, cspViolations: 1, providerErrorCodes: []});
  value.tester = {imageryAndControlsConfirmed: false, attributionAndLinksConfirmed: false};
  assert.equal(cameraControlsReady(value), true);
  assert.equal(classifyObservation(value, false), 'VISUAL_OR_SDK_REVIEW_PENDING');

  // Camera and visual evidence can be gathered, but cannot waive a CSP violation.
  value.cameraCommands.push('flyTo');
  value.tester.imageryAndControlsConfirmed = true;
  value.tester.attributionAndLinksConfirmed = true;
  assert.equal(cameraControlsReady(value), true);
  assert.equal(classifyObservation(value, false), 'VISUAL_OR_SDK_REVIEW_PENDING');
  value.sdk.cspViolations = 0;
  assert.equal(classifyObservation(value, false), 'POSITIVE_OBSERVATION_COMPLETE');
});

test('camera eligibility still requires current readiness and no renderer, page or provider failure', () => {
  const cases = [
    ['missing SDK evidence', value => { value.sdk = null; }],
    ['loading renderer', value => { value.rendererStatus = 'loading'; }],
    ['failed renderer', value => { value.rendererStatus = 'error'; }],
    ['not started renderer', value => { value.rendererStatus = 'not-started'; }],
    ['currently moving despite earlier steady', value => { value.sdk.steady = false; }],
    ['truthy nonboolean steady', value => { value.sdk.steady = 'true'; }],
    ...['mapError', 'loaderError', 'pageError'].map(key => [key, value => { value.sdk[key] = true; }]),
    ['provider authorization failure', value => { value.sdk.providerErrorCodes = ['InvalidKeyMapError']; }],
    ['unclassified provider failure', value => { value.sdk.providerErrorCodes = ['GoogleMapsError']; }],
  ];
  for (const [name, mutate] of cases) {
    const value = report();
    value.sdk.cspViolations = 1;
    mutate(value);
    assert.equal(cameraControlsReady(value), false, name);
  }
  const usable = report();
  usable.sdk.cspViolations = 100;
  assert.equal(cameraControlsReady(usable), true);
  assert.equal(classifyObservation(usable, false), 'VISUAL_OR_SDK_REVIEW_PENDING');
});

test('CSP summaries classify resources without exporting URLs, credentials or raw violation details', () => {
  const ownOrigin = 'https://korlix-projection-check-20261111.onrender.com';
  const cases = [
    ['', 'unknown'], ['inline', 'inline'], ['eval', 'eval'], ['wasm-eval', 'wasm-eval'],
    [`data:text/plain,${candidate}`, 'data'], [`blob:${ownOrigin}/${candidate}`, 'blob'],
    [`${ownOrigin}/acceptance/frame.mjs?key=${candidate}#private-fragment`, 'self'],
    [`https://private-user:private-password@maps.googleapis.com/maps/api/js?key=${candidate}#private-fragment`, 'google-maps'],
    [`https://maps.gstatic.com/maps-api-v3/private-path?key=${candidate}`, 'google-static'],
    [`https://fonts.googleapis.com/css?key=${candidate}`, 'google-fonts'],
    [`https://fonts.gstatic.com/s/private-path?key=${candidate}`, 'google-fonts'],
    [`https://keyhole-pa.googleapis.com/private-path?key=${candidate}`, 'google-api'],
    [`https://maps.google.com/private-path?key=${candidate}`, 'google'],
    [`https://lh3.googleusercontent.com/private-path?key=${candidate}`, 'google'],
    [`chrome-extension://private-extension/private-path?key=${candidate}`, 'extension'],
    [`https://maps.googleapis.com.attacker.example/private-path?key=${candidate}`, 'external'],
    [`https://notgoogleapis.com/private-path?key=${candidate}`, 'external'],
    [`https://maps.googleapis.com@attacker.example/private-path?key=${candidate}`, 'external'],
    ['https://[', 'unknown'],
  ];
  for (const [resource, classification] of cases) {
    const summary = summarizeCspViolation({effectiveDirective: 'connect-src', disposition: 'enforce',
      blockedURI: resource, sourceFile: resource,
      documentURI: `${ownOrigin}/?key=${candidate}`, referrer: `https://private.example/${candidate}`,
      originalPolicy: `script-src 'nonce-${candidate}'`, sample: `private-sample-${candidate}`}, ownOrigin);
    assert.deepEqual(summary, {effectiveDirective: 'connect-src', disposition: 'enforce',
      blockedResource: classification, sourceResource: classification}, classification);
    assert.doesNotMatch(JSON.stringify(summary), /https?:|private-|nonce-|originalPolicy|sample|blockedURI|sourceFile/);
    assert.equal(JSON.stringify(summary).includes(candidate), false);
  }
});

test('CSP evidence is bounded and independently sanitized again at the frame boundary', () => {
  const valid = {effectiveDirective: 'script-src-elem', disposition: 'report',
    blockedResource: 'google-maps', sourceResource: 'self'};
  const injected = {effectiveDirective: candidate, disposition: candidate,
    blockedResource: `https://private-user:private-password@maps.googleapis.com/maps/api/js?key=${candidate}#private-fragment`,
    sourceResource: `chrome-extension://private-extension/${candidate}`,
    blockedURI: candidate, sourceFile: candidate, originalPolicy: candidate, sample: candidate};
  const clean = sanitizeEvidence({cspViolations: 100000,
    cspEvents: [valid, injected, ...Array.from({length: 10}, () => valid)]}, false);
  assert.equal(clean.cspViolations, 100);
  assert.equal(clean.cspEvents.length, 8);
  assert.deepEqual(clean.cspEvents[0], valid);
  assert.deepEqual(clean.cspEvents[1], {effectiveDirective: 'unknown', disposition: 'unknown',
    blockedResource: 'unknown', sourceResource: 'unknown'});
  assert.equal(JSON.stringify(clean).includes(candidate), false);
  assert.doesNotMatch(JSON.stringify(clean), /https?:|private-|originalPolicy|blockedURI|sourceFile|sample/);
  assert.deepEqual(sanitizeEvidence(clean, false), clean);
  assert.deepEqual(sanitizeEvidence({cspEvents: {0: valid, length: 1}}, false).cspEvents, []);
});

test('negative proof needs a specific referrer denial and observed absent headers; ToS/generic errors remain inconclusive', () => {
  const value = report();
  value.rendererStatus = 'error'; value.sdk.steady = false; value.sdk.everSteady = false;
  value.sdk.loader.scriptReferrerPolicy = 'no-referrer'; value.sdk.documentReferrerPolicy = 'no-referrer';
  value.tester.googleSdkAndAuthorizationRequestsHadNoReferer = true;
  for (const code of ['RefererDeniedMapError', 'BillingNotEnabledMapError', 'GoogleMapsError']) {
    value.sdk.providerErrorCodes = [code]; assert.equal(classifyObservation(value, true), 'INCONCLUSIVE');
  }
  value.sdk.providerErrorCodes = ['RefererNotAllowedMapError'];
  assert.equal(classifyObservation(value, true), 'NO_REFERRER_DENIAL_OBSERVED');
  value.tester.googleSdkAndAuthorizationRequestsHadNoReferer = false;
  assert.equal(classifyObservation(value, true), 'INCONCLUSIVE');
  value.sdk.everSteady = true;
  assert.equal(classifyObservation(value, true), 'NEGATIVE_CHECK_FAILED_SCENE_RENDERED');
});

test('exported evidence excludes credentials, URLs, raw errors and unexpected provider strings', () => {
  const raw = {loader: {channel: candidate, src: `https://example.test/?key=${candidate}`}, sdkVersion: candidate,
    providerErrorCodes: [candidate, 'PretendKeyMapError', 'RefererNotAllowedMapError'], rawError: candidate,
    authorization: candidate, referrer: candidate, steadyEvents: 100000};
  const clean = sanitizeEvidence(raw, false);
  assert.equal(JSON.stringify(clean).includes(candidate), false);
  assert.deepEqual(clean.providerErrorCodes, ['RefererNotAllowedMapError']);
  assert.equal(clean.steadyEvents, 100);
  assert.equal(providerErrorCode([`Google Maps JavaScript API error: RefererNotAllowedMapError https://example.test/?key=${candidate}`]), 'RefererNotAllowedMapError');
  assert.equal(providerErrorCode([`Google Maps JavaScript API error: FakeSecretMapError ${candidate}`]), 'GoogleMapsError');
  assert.equal(providerErrorCode([new Error(candidate)]), null);
});
