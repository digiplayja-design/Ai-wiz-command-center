import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {request as httpRequest} from 'node:http';
import {createAcceptanceServer, acceptanceMapPolicy, acceptancePort} from '../brain_projection/acceptance/server.mjs';
import {observeLoader} from '../brain_projection/acceptance/frame.mjs';
import {cameraControlsReady, classifyObservation, sanitizeEvidence, providerErrorCode, summarizeCspViolation} from '../brain_projection/acceptance/evidence.mjs';
import {rendererPolicy} from '../brain_projection/renderer.mjs';
import {API_RESTRICTION_ENDPOINT, createApiRestrictionProbe, summarizeApiRestriction} from '../brain_projection/acceptance/api-restriction.mjs';

const candidate = 'acceptance-browser-fixture-not-a-real-key';
const apiDenied = (reason = 'API_KEY_SERVICE_BLOCKED', service = 'identitytoolkit.googleapis.com') => ({
  error: {code: 403, status: 'PERMISSION_DENIED', message: 'private-provider-message', details: [{
    '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason, domain: 'googleapis.com',
    metadata: {service, consumer: 'private-consumer', key: candidate},
  }]},
});

test('API restriction observation requires a specific service denial and excludes raw provider content', () => {
  const positive = summarizeApiRestriction(403, apiDenied());
  assert.equal(positive.observation, 'DISALLOWED_API_DENIAL_OBSERVED');
  assert.doesNotMatch(JSON.stringify(positive), /private-|consumer|acceptance-browser-fixture/);
  for (const body of [apiDenied('SERVICE_DISABLED'), apiDenied('API_KEY_HTTP_REFERRER_BLOCKED'),
    apiDenied('API_KEY_INVALID'), apiDenied('BILLING_DISABLED'), apiDenied('API_KEY_SERVICE_BLOCKED', 'other.googleapis.com'),
    {error: {...apiDenied().error, status: 'UNAUTHENTICATED'}}, {error: {...apiDenied().error, code: 401}},
    {error: {...apiDenied().error, details: [...apiDenied().error.details, ...apiDenied('SERVICE_DISABLED').error.details]}},
    {error: {...apiDenied().error, details: [...apiDenied().error.details, ...Array(19).fill({}), ...apiDenied('SERVICE_DISABLED').error.details]}},
    {error: {...apiDenied().error, details: [{...apiDenied().error.details[0], domain: 'example.test'}]}},
    {error: {...apiDenied().error, details: [{...apiDenied().error.details[0], '@type': 'arbitrary'}]}},
    {error: {...apiDenied().error, details: [{...apiDenied().error.details[0], reason: candidate}]}},
    {authorizedDomains: ['private-fixture']}, null]) {
    const result = summarizeApiRestriction(403, body);
    assert.equal(result.observation, 'API_RESTRICTION_CHECK_INCONCLUSIVE');
    assert.doesNotMatch(JSON.stringify(result), /private-|consumer|acceptance-browser-fixture/);
  }
  for (const status of [200, 302, 401, 429, 503, undefined]) {
    assert.equal(summarizeApiRestriction(status, apiDenied()).observation, 'API_RESTRICTION_CHECK_INCONCLUSIVE');
  }
});

test('browser API probe makes only one fixed read-only attempt with normal referrer policy', async () => {
  const requests = [];
  const run = createApiRestrictionProbe({browserKey: candidate, origin: 'https://acceptance.example',
    fetchImpl: async (url, options) => { requests.push({url, options}); return Response.json(apiDenied(), {status: 403}); }});
  assert.equal(requests.length, 0);
  const report = await run();
  assert.equal(report.observation, 'DISALLOWED_API_DENIAL_OBSERVED');
  assert.equal(report.productionActivation, false);
  assert.equal(report.overallVerification, 'NOT_ESTABLISHED');
  assert.equal(report.request.actualRefererHeader, 'NOT_CAPTURED_BY_PAGE');
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, API_RESTRICTION_ENDPOINT);
  assert.equal(requests[0].options.method, 'GET');
  assert.equal(requests[0].options.credentials, 'omit');
  assert.equal(requests[0].options.redirect, 'error');
  assert.equal(requests[0].options.referrerPolicy, 'strict-origin-when-cross-origin');
  assert.deepEqual(Object.keys(requests[0].options.headers).sort(), ['Accept', 'X-Goog-Api-Key']);
  assert.equal(requests[0].options.headers['X-Goog-Api-Key'], candidate);
  assert.equal(requests[0].options.body, undefined);
  assert.equal(requests[0].options.referrer, undefined);
  assert.doesNotMatch(JSON.stringify(report), /private-|consumer|acceptance-browser-fixture/);
  await assert.rejects(run(), /already attempted/);
  assert.equal(requests.length, 1);
});

test('API probe setup, transport, malformed and oversized responses remain inconclusive without retries', async () => {
  let calls = 0;
  const missing = await createApiRestrictionProbe({browserKey: '', fetchImpl: () => { calls++; throw Error('must not fetch'); }})();
  assert.equal(missing.observation, 'NOT_PERFORMED');
  assert.equal(calls, 0);
  for (const fetchImpl of [async () => {throw Error(candidate);}, async () => new Response('malformed-private-response'),
    async () => new Response('x'.repeat(65537)), async () => new Response(null)]) {
    const run = createApiRestrictionProbe({browserKey: candidate, origin: 'https://acceptance.example',
      fetchImpl: async (...args) => {calls++; return fetchImpl(...args);}});
    const before = calls;
    const report = await run();
    assert.equal(calls, before + 1);
    assert.equal(report.observation, 'API_RESTRICTION_CHECK_INCONCLUSIVE');
    assert.equal(report.request.providerFetchAttempts, 1);
    assert.doesNotMatch(JSON.stringify(report), /private-response|acceptance-browser-fixture/);
  }
});
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

test('API probe page has only the fixed Google endpoint in its connection policy and waits for a click', async t => {
  const request = await serve(t, {browserKey: candidate});
  const response = await request('/api-restriction');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin');
  const policy = response.headers.get('content-security-policy');
  assert.match(policy, /connect-src https:\/\/identitytoolkit\.googleapis\.com;/);
  assert.doesNotMatch(policy, /unsafe-inline|unsafe-eval|\*|https:\/\/maps/);
  const token = /script-src 'nonce-([^']+)'/.exec(policy)[1];
  const html = await response.text();
  assert.match(html, new RegExp(`src="/acceptance/api-restriction.mjs" nonce="${token}"`));
  assert.match(html, /id="api-check">Check API restriction/);
  assert.doesNotMatch(html, /<iframe|<script[^>]+(?:earth\.mjs|maps\.googleapis\.com)/);
  assert.match(html, /actual outgoing headers|Actual outgoing headers/);
  assert.equal((await request('/acceptance/api-restriction.mjs')).status, 200);
  const missing = await serve(t);
  assert.match(await (await missing('/api-restriction')).text(), /id="api-check" disabled/);
});

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

test('scenario shells and frames deliver matching referrer policies and mode metadata', async t => {
  // These are actual local HTTP response checks with a synthetic key. Reading
  // the HTML starts no SDK and makes no claim about Google's authorization.
  const request = await serve(t, {browserKey: candidate});
  for (const [path, policy, mode] of [
    ['/no-referrer', 'no-referrer', 'no-referrer'], ['/frame/no-referrer', 'no-referrer', 'no-referrer'],
    ['/', 'strict-origin-when-cross-origin', 'standard'], ['/frame/standard', 'strict-origin-when-cross-origin', 'standard'],
    ['/wrong-origin', 'strict-origin-when-cross-origin', 'wrong-origin'], ['/frame/wrong-origin', 'strict-origin-when-cross-origin', 'wrong-origin'],
  ]) {
    const response = await request(path);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get('referrer-policy'), policy, path);
    assert.equal(response.headers.get('cache-control'), 'no-store', path);
    const html = await response.text();
    const metaPolicies = [...html.matchAll(/<meta\s+name="referrer"\s+content="([^"]+)"/g)].map(match => match[1]);
    assert.deepEqual(metaPolicies, [policy], `${path} must contain one matching document policy`);
    const metaModes = [...html.matchAll(/<meta\s+name="acceptance-mode"\s+content="([^"]+)"/g)].map(match => match[1]);
    assert.deepEqual(metaModes, [mode], `${path} must identify its own acceptance scenario`);
    assert.doesNotMatch(html, /<iframe|<script[^>]+(?:earth\.mjs|maps\.googleapis\.com)/, path);
    if (!path.startsWith('/frame/')) assert.equal(html.includes(candidate), false, 'The shell must not expose the candidate key');
  }
});

test('wrong-origin check requires the allowlist observation and waits for explicit map loading', async t => {
  const request = await serve(t, {browserKey: candidate});
  const shell = await (await request('/wrong-origin')).text();
  assert.match(shell, /<input\b(?=[^>]*\bid="origin-unapproved-confirmed")(?=[^>]*\btype="checkbox")[^>]*>/);
  assert.doesNotMatch(shell, /<input\b[^>]*\bid="(?:headers|imagery)-confirmed"/);
  assert.equal(shell.includes(candidate), false);
  assert.doesNotMatch(shell, /<iframe|maps\.googleapis\.com|<script[^>]+earth\.mjs/);
  assert.match(shell, /id="start"/);

  const response = await request('/frame/wrong-origin');
  const frame = await response.text();
  assert.match(frame, /Waiting for an explicit test/);
  assert.equal(frame.includes(`content="${candidate}"`), true);
  assert.doesNotMatch(frame, /<script[^>]+(?:earth\.mjs|maps\.googleapis\.com)/);
  const token = /script-src 'nonce-([^']+)'/.exec(response.headers.get('content-security-policy'))[1];
  assert.equal(response.headers.get('content-security-policy'), rendererPolicy(token));
  assert.equal(response.headers.get('permissions-policy'), 'camera=(), microphone=(), geolocation=(), payment=()');

  const unconfigured = await serve(t);
  const unconfiguredShell = await (await unconfigured('/wrong-origin')).text();
  assert.match(unconfiguredShell, /id="start" disabled/);
  assert.doesNotMatch(unconfiguredShell, /<iframe|maps\.googleapis\.com|<script[^>]+earth\.mjs/);
  const unconfiguredFrame = await (await unconfigured('/frame/wrong-origin')).text();
  assert.match(unconfiguredFrame, /name="korlix-map-key" content=""/);
  assert.match(unconfiguredFrame, /id="begin" disabled/);
});

test('style-attribute compatibility is confined to map documents; shell and element protections remain strict', async t => {
  const request = await serve(t, {browserKey: candidate});
  for (const path of ['/frame/standard', '/frame/no-referrer', '/frame/wrong-origin', '/', '/no-referrer', '/wrong-origin']) {
    const response = await request(path);
    const directives = response.headers.get('content-security-policy').split('; ');
    const script = directives.find(value => value.startsWith('script-src '));
    const style = directives.find(value => value.startsWith('style-src '));
    assert.match(script, /'nonce-[A-Za-z0-9_-]+' 'strict-dynamic'/, path);
    assert.match(style, /'nonce-[A-Za-z0-9_-]+'/, path);
    assert.doesNotMatch(script, /'unsafe-inline'/, path);
    assert.doesNotMatch(style, /'unsafe-inline'/, path);
    const attributes = directives.find(value => value.startsWith('style-src-attr '));
    if (path.startsWith('/frame/')) {
      assert.equal(attributes, "style-src-attr 'unsafe-inline'", path);
    } else {
      assert.equal(attributes, undefined, 'The shell retains its nonce-only style policy');
    }
  }
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

function wrongOriginReport() {
  const value = report();
  value.rendererStatus = 'error';
  value.cameraCommands = [];
  Object.assign(value.sdk, {steady: false, everSteady: false, mapError: true,
    documentReferrerPolicy: 'strict-origin-when-cross-origin', providerErrorCodes: ['RefererNotAllowedMapError']});
  value.tester = {currentOriginAbsentFromKeyAllowlist: true};
  return value;
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
  for (const mode of [true, 'no-referrer']) {
    const value = report();
    value.rendererStatus = 'error'; value.sdk.steady = false; value.sdk.everSteady = false;
    value.sdk.loader.scriptReferrerPolicy = 'no-referrer'; value.sdk.documentReferrerPolicy = 'no-referrer';
    value.tester.googleSdkAndAuthorizationRequestsHadNoReferer = true;
    for (const code of ['RefererDeniedMapError', 'BillingNotEnabledMapError', 'GoogleMapsError']) {
      value.sdk.providerErrorCodes = [code]; assert.equal(classifyObservation(value, mode), 'INCONCLUSIVE', String(mode));
    }
    value.sdk.providerErrorCodes = ['RefererNotAllowedMapError'];
    assert.equal(classifyObservation(value, mode), 'NO_REFERRER_DENIAL_OBSERVED', String(mode));
    value.tester.googleSdkAndAuthorizationRequestsHadNoReferer = false;
    assert.equal(classifyObservation(value, mode), 'INCONCLUSIVE', String(mode));
    value.sdk.everSteady = true;
    assert.equal(classifyObservation(value, mode), 'NEGATIVE_CHECK_FAILED_SCENE_RENDERED', String(mode));
  }
});

test('wrong-origin denial requires the complete loader contract, no steady scene and explicit allowlist confirmation', () => {
  assert.equal(classifyObservation(wrongOriginReport(), 'wrong-origin'), 'WRONG_ORIGIN_DENIAL_OBSERVED');
  const cases = [
    ['missing SDK evidence', value => { value.sdk = null; }],
    ['missing loader', value => { value.sdk.loader = null; }],
    ...['loading', 'ready', 'not-started', undefined].map(status => [`renderer status ${status}`, value => { value.rendererStatus = status; }]),
    ...['steady', 'everSteady'].flatMap(key => [
      [`missing ${key}`, value => { delete value.sdk[key]; }],
      [`null ${key}`, value => { value.sdk[key] = null; }],
      [`nonboolean ${key}`, value => { value.sdk[key] = 0; }],
    ]),
    ...['channel', 'loading', 'authorizationReferrerPolicy', 'scriptReferrerPolicy'].flatMap(key => [
      [`unexpected loader ${key}`, value => { value.sdk.loader[key] = 'unexpected'; }],
      [`missing loader ${key}`, value => { delete value.sdk.loader[key]; }],
    ]),
    ['no-referrer loader policy', value => { value.sdk.loader.scriptReferrerPolicy = 'no-referrer'; }],
    ['no-referrer document policy', value => { value.sdk.documentReferrerPolicy = 'no-referrer'; }],
    ['missing document policy', value => { delete value.sdk.documentReferrerPolicy; }],
    ['missing tester evidence', value => { value.tester = null; }],
    ['missing allowlist confirmation', value => { delete value.tester.currentOriginAbsentFromKeyAllowlist; }],
    ['unchecked allowlist confirmation', value => { value.tester.currentOriginAbsentFromKeyAllowlist = false; }],
    ['truthy nonboolean confirmation', value => { value.tester.currentOriginAbsentFromKeyAllowlist = 'true'; }],
    ['other scenario confirmations', value => { value.tester = {googleSdkAndAuthorizationRequestsHadNoReferer: true,
      imageryAndControlsConfirmed: true, attributionAndLinksConfirmed: true}; }],
  ];
  for (const [name, mutate] of cases) {
    const value = wrongOriginReport(); mutate(value);
    assert.equal(classifyObservation(value, 'wrong-origin'), 'INCONCLUSIVE', name);
  }
  const notStarted = wrongOriginReport(); delete notStarted.startedAt;
  assert.equal(classifyObservation(notStarted, 'wrong-origin'), 'NOT_PERFORMED');
});

test('wrong-origin blank maps, unrelated provider errors and mixed denial codes remain inconclusive', () => {
  const cases = [
    ['GL-only map error', []], ['missing codes', undefined], ['null codes', null],
    ['generic SDK error', ['GoogleMapsError']], ['terms-of-service denial', ['RefererDeniedMapError']],
    ...['BillingNotEnabledMapError', 'ClientBillingNotEnabledMapError', 'InvalidKeyMapError', 'MissingKeyMapError',
      'ExpiredKeyMapError', 'ApiNotActivatedMapError', 'ApiTargetBlockedMapError'].map(code => [code, [code]]),
    ['mixed billing and referrer denial', ['RefererNotAllowedMapError', 'BillingNotEnabledMapError']],
    ['mixed invalid key and referrer denial', ['InvalidKeyMapError', 'RefererNotAllowedMapError']],
    ['mixed generic and referrer denial', ['RefererNotAllowedMapError', 'GoogleMapsError']],
    ['duplicate referrer denials', ['RefererNotAllowedMapError', 'RefererNotAllowedMapError']],
    ['raw string instead of code array', 'RefererNotAllowedMapError'],
    ['array-like object instead of code array', {0: 'RefererNotAllowedMapError', length: 1}],
  ];
  for (const [name, codes] of cases) {
    const value = wrongOriginReport(); value.sdk.providerErrorCodes = codes;
    assert.equal(classifyObservation(value, 'wrong-origin'), 'INCONCLUSIVE', name);
  }
  for (const error of ['loaderError', 'pageError']) {
    const value = wrongOriginReport(); value.sdk.providerErrorCodes = []; value.sdk[error] = true;
    assert.equal(classifyObservation(value, 'wrong-origin'), 'INCONCLUSIVE', error);
  }
});

test('any current or earlier steady scene fails the wrong-origin control even with other incomplete evidence', () => {
  for (const [steady, everSteady] of [[true, false], [false, true], [true, true]]) {
    for (const incomplete of [false, true]) {
      const value = wrongOriginReport(); Object.assign(value.sdk, {steady, everSteady});
      if (incomplete) {
        value.sdk.loader = null; value.sdk.providerErrorCodes = [];
        value.tester.currentOriginAbsentFromKeyAllowlist = false;
      }
      assert.equal(classifyObservation(value, 'wrong-origin'), 'WRONG_ORIGIN_CHECK_FAILED_SCENE_RENDERED',
        `steady=${steady}, everSteady=${everSteady}, incomplete=${incomplete}`);
    }
  }
});

test('wrong-origin evidence keeps standard referrer metadata and excludes unsanitized fields', () => {
  const loader = report().sdk.loader;
  const raw = {started: true, loader: {...loader, src: `https://example.test/?key=${candidate}`, key: candidate},
    sdkVersion: '3.65.14a', steady: false, everSteady: false, documentReferrerPolicy: candidate,
    providerErrorCodes: [candidate, 'RefererNotAllowedMapError', 'PretendKeyMapError'],
    rawError: candidate, authorization: candidate, referrer: candidate, origin: candidate,
    requestHeaders: {Referer: candidate}, tester: {currentOriginAbsentFromKeyAllowlist: true}};
  const clean = sanitizeEvidence(raw, 'wrong-origin');
  assert.equal(clean.documentReferrerPolicy, 'strict-origin-when-cross-origin');
  assert.deepEqual(clean.loader, loader);
  assert.equal(clean.sdkVersion, '3.65.14a');
  assert.deepEqual(clean.providerErrorCodes, ['RefererNotAllowedMapError']);
  for (const key of ['rawError', 'authorization', 'referrer', 'origin', 'requestHeaders', 'tester']) {
    assert.equal(Object.hasOwn(clean, key), false, key);
  }
  assert.equal(JSON.stringify(clean).includes(candidate), false);
  assert.doesNotMatch(JSON.stringify(clean), /https?:|example\.test/);
  assert.deepEqual(sanitizeEvidence(clean, 'wrong-origin'), clean);
  for (const [mode, policy] of [[false, 'strict-origin-when-cross-origin'], [true, 'no-referrer'], ['no-referrer', 'no-referrer']]) {
    assert.equal(sanitizeEvidence(raw, mode).documentReferrerPolicy, policy, String(mode));
  }
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
