import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {request as httpRequest} from 'node:http';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {HeaderCollector, acceptanceOrigin, allowedTunnel, createNetworkBoundary, limits, recognizedEndpoint,
  refererFromExtraInfo, sanitizedDomEvidence, targetUrl} from '../tools/capture_projection_live_headers.mjs';

// Synthetic protocol fixtures only. No browser, credential or provider request.
const sdk = 'https://maps.googleapis.com/maps/api/js';
const auth = 'https://maps.googleapis.com/maps/api/js/AuthenticationService.Authenticate';
const config = 'https://maps.googleapis.com/$rpc/google.internal.maps.mapsjs.v1.MapsJsInternalService/GetMap3DConfig';
const secret = 'fixture-do-not-persist-key-cookie-query-or-fragment';
function base(collector, id, url, options = {}) {
  collector.event('requestWillBeSent', {requestId: id, request: {url: `${url}?key=${secret}#${secret}`,
    method: options.method || 'GET', headers: {Referer: `${acceptanceOrigin}/provisional?${secret}`}}, ...options});
}
function extra(collector, id, headers = {}) {
  collector.event('requestWillBeSentExtraInfo', {requestId: id, headers, associatedCookies: [{cookie: {value: secret}}]});
}
function response(collector, id, status = 200, flags = {}) {
  collector.event('responseReceived', {requestId: id, hasExtraInfo: true, response: {status, ...flags}});
  collector.event('responseReceivedExtraInfo', {requestId: id, statusCode: status, headers: {'set-cookie': secret}});
  collector.event('loadingFinished', {requestId: id});
}
function completed(collector, id, url, headers = {}, flags = {}) {
  collector.observePlaywrightRequest(url, 'GET');
  base(collector, id, url);
  extra(collector, id, headers);
  response(collector, id, 200, flags);
}

test('the navigation target is the fixed approved no-referrer probe', () => {
  assert.equal(targetUrl, `${acceptanceOrigin}/no-referrer`);
});

test('recognized endpoint output uses fixed paths and never retains URL parameters', () => {
  assert.deepEqual(recognizedEndpoint(`${auth}?key=${secret}#${secret}`), {
    family: 'sdk-authentication', origin: 'https://maps.googleapis.com', path: '/maps/api/js/AuthenticationService.Authenticate'});
  assert.equal(recognizedEndpoint(`https://example.com/maps/api/js?${secret}`), null);
  assert.equal(recognizedEndpoint(`https://maps.googleapis.com/${secret}`), null);
  assert.equal(recognizedEndpoint(`https://${secret}.googleapis.com/maps/api/js`), null);
});

test('the TLS tunnel boundary checks every target and rejects production, IPs and credential syntax', () => {
  for (const host of ['korlix-projection-check-20261111.onrender.com', 'maps.googleapis.com', 'maps.gstatic.com', 'www.google.com']) {
    assert.deepEqual(allowedTunnel(`${host}:443`), {host, port: 443});
  }
  for (const target of ['chee-chai-chee-backend.onrender.com:443', 'example.com:443', '127.0.0.1:443', '[::1]:443',
    'maps.googleapis.com.example.com:443', 'maps.googleapis.com:80', 'user@maps.googleapis.com:443',
    'maps.googleapis.com:443/path', 'maps.googleapis.com:443?key=secret', 'maps.googleapis.com.:443']) {
    assert.equal(allowedTunnel(target), null);
  }
});

test('the real local boundary rejects a production CONNECT and plaintext HTTP without forwarding', async () => {
  const boundary = await createNetworkBoundary(() => assert.fail('Unexpected connection limit.'));
  const rejected = (method, path) => new Promise((done, reject) => {
    const request = httpRequest(boundary.url, {method, path}, response => {
      response.resume(); done(response.statusCode);
    });
    request.on('connect', (response, socket) => { socket.destroy(); done(response.statusCode); });
    request.on('error', reject);
    request.setTimeout(2_000, () => request.destroy(new Error('Local boundary test timed out.')));
    request.end();
  });
  try {
    assert.equal(await rejected('CONNECT', 'chee-chai-chee-backend.onrender.com:443'), 403);
    assert.equal(await rejected('GET', 'http://example.invalid/private'), 403);
    assert.equal(boundary.stats.connections, 1);
    assert.equal(boundary.stats.blockedConnections, 2);
  } finally { boundary.close(); }
});

test('missing extra-info headers remain unobserved; actual empty headers establish absence', () => {
  for (const invalid of [undefined, null, [], secret]) assert.equal(refererFromExtraInfo(invalid).refererState, 'unobserved');
  assert.deepEqual(refererFromExtraInfo({Cookie: secret}), {refererState: 'absent', refererOrigin: null});
  for (const present of ['', secret, null, `${acceptanceOrigin}/path?key=${secret}#${secret}`]) {
    assert.equal(refererFromExtraInfo({rEfErEr: present}).refererState, 'present');
  }
});

test('Referer origin strips userinfo, path, query and fragment and redacts unknown hosts', () => {
  const value = refererFromExtraInfo({Referer: `https://${secret}:${secret}@korlix-projection-check-20261111.onrender.com/path?${secret}#${secret}`,
    Cookie: secret, Authorization: secret});
  assert.deepEqual(value, {refererState: 'present', refererOrigin: acceptanceOrigin});
  assert.equal(JSON.stringify(value).includes(secret), false);
  assert.deepEqual(refererFromExtraInfo({Referer: `https://${secret}.example.com/private`}),
    {refererState: 'present', refererOrigin: 'redacted-or-invalid-origin'});
  assert.equal(refererFromExtraInfo({Referer: acceptanceOrigin, referer: secret}).refererOrigin, 'redacted-or-invalid-origin');
});

test('extra info arriving before its base request is correlated without provisional-header fallback', () => {
  const collector = new HeaderCollector();
  collector.observePlaywrightRequest(sdk, 'GET');
  extra(collector, 'sdk');
  base(collector, 'sdk', sdk);
  response(collector, 'sdk');
  completed(collector, 'config', config);
  const result = collector.snapshot();
  assert.equal(result.noRefererObservedForAllRecognizedRequests, true);
  assert.equal(result.requests[0].refererState, 'absent');
  assert.equal(result.requests[0].statusSource, 'response-extra-info');
  assert.equal(JSON.stringify(result).includes(secret), false);
});

test('missing extra info never becomes an absent header even when a response succeeds', () => {
  const collector = new HeaderCollector();
  collector.observePlaywrightRequest(sdk, 'GET'); base(collector, 'sdk', sdk); response(collector, 'sdk');
  completed(collector, 'auth', auth);
  const result = collector.snapshot();
  assert.equal(result.requests[0].extraInfoReceived, false);
  assert.equal(result.requests[0].refererState, 'unobserved');
  assert.equal(result.headerCharacterization, 'INCONCLUSIVE');
});

test('contradictory false extra-info flags and pending single-hop chains stay inconclusive', () => {
  for (const state of ['contradiction', 'pending', 'unknown-expectation']) {
    const collector = new HeaderCollector(); completed(collector, 'sdk', sdk);
    collector.observePlaywrightRequest(config, 'GET'); base(collector, 'config', config); extra(collector, 'config');
    if (state === 'contradiction') {
      collector.event('responseReceived', {requestId: 'config', hasExtraInfo: false, response: {status: 200}});
      collector.event('loadingFinished', {requestId: 'config'});
    } else if (state === 'unknown-expectation') collector.event('loadingFailed', {requestId: 'config'});
    const result = collector.snapshot();
    assert.equal(result.headerCharacterization, 'INCONCLUSIVE', state);
    assert.equal(result.requests[1].refererState, 'unobserved', state);
  }
});

test('a bootstrap alone cannot characterize authentication/configuration requests', () => {
  const collector = new HeaderCollector(); completed(collector, 'sdk', sdk);
  assert.equal(collector.snapshot().headerCharacterization, 'INCONCLUSIVE');
  assert.equal(collector.snapshot().counts.expectedFamiliesObserved, false);
});

test('redirect flags skip an earlier no-extra hop without attaching later headers to it', () => {
  const collector = new HeaderCollector(); completed(collector, 'sdk', sdk);
  base(collector, 'chain', 'https://maps.googleapis.com/unrecorded-redirect');
  extra(collector, 'chain');
  collector.observePlaywrightRequest(config, 'GET');
  base(collector, 'chain', config, {redirectResponse: {status: 302}, redirectHasExtraInfo: false});
  response(collector, 'chain');
  const request = collector.snapshot().requests.find(item => item.family === 'map3d-config');
  assert.equal(request.hop, 2);
  assert.equal(request.correlation, 'ordered-redirect-hops');
  assert.equal(request.refererState, 'absent');
  assert.equal(collector.snapshot().noRefererObservedForAllRecognizedRequests, true);
});

test('redirect hops retain separate headers and actual network response statuses', () => {
  const collector = new HeaderCollector();
  collector.observePlaywrightRequest(sdk, 'GET'); collector.observePlaywrightRequest(config, 'GET');
  extra(collector, 'chain', {Referer: `${acceptanceOrigin}/?${secret}`});
  collector.event('responseReceivedExtraInfo', {requestId: 'chain', statusCode: 302});
  base(collector, 'chain', sdk);
  base(collector, 'chain', config, {redirectResponse: {status: 302}, redirectHasExtraInfo: true});
  extra(collector, 'chain'); response(collector, 'chain');
  const result = collector.snapshot();
  assert.deepEqual(result.requests.map(item => [item.family, item.refererState, item.status]),
    [['sdk-bootstrap', 'present', 302], ['map3d-config', 'absent', 200]]);
  assert.equal(result.headerCharacterization, 'REFERER_PRESENT_IN_OBSERVED_REQUESTS');
  assert.equal(result.noRefererObservedForAllRecognizedRequests, false);
});

test('missing or ambiguous redirect extras never shift another hop into place', () => {
  for (const known of [true, false]) {
    const collector = new HeaderCollector();
    collector.observePlaywrightRequest(sdk, 'GET'); collector.observePlaywrightRequest(config, 'GET');
    base(collector, 'chain', sdk);
    base(collector, 'chain', config, {redirectResponse: {status: 302}, ...(known ? {redirectHasExtraInfo: true} : {})});
    extra(collector, 'chain'); response(collector, 'chain');
    const result = collector.snapshot();
    assert.equal(result.headerCharacterization, 'INCONCLUSIVE');
    assert.deepEqual(result.requests.map(item => item.refererState), ['unobserved', 'unobserved']);
  }
});

test('Playwright-observed requests missing from the page CDP target prevent a complete claim', () => {
  const collector = new HeaderCollector(); completed(collector, 'sdk', sdk); completed(collector, 'config', config);
  collector.observePlaywrightRequest(config, 'GET');
  const result = collector.snapshot();
  assert.equal(result.counts.allPlaywrightRecognizedRequestsCovered, false);
  assert.equal(result.noRefererObservedForAllRecognizedRequests, false);
});

test('CDP-only preflight is included and must have its own correlated header event', () => {
  const collector = new HeaderCollector(); completed(collector, 'sdk', sdk); completed(collector, 'config', config);
  base(collector, 'preflight', config, {method: 'OPTIONS'}); extra(collector, 'preflight'); response(collector, 'preflight', 204);
  const result = collector.snapshot();
  assert.equal(result.counts.cdpOnlyRecognizedRequests, 1);
  assert.equal(result.counts.allPlaywrightRecognizedRequestsCovered, true);
  assert.equal(result.noRefererObservedForAllRecognizedRequests, true);
});

test('cache/service-worker results remain inconclusive even with header events', () => {
  for (const flag of ['fromDiskCache', 'fromServiceWorker', 'fromPrefetchCache']) {
    const collector = new HeaderCollector(); completed(collector, 'sdk', sdk, {}, {[flag]: true}); completed(collector, 'config', config);
    assert.equal(collector.snapshot().headerCharacterization, 'INCONCLUSIVE');
  }
});

test('report and event caps prevent a truncated all-requests claim', () => {
  const collector = new HeaderCollector(); completed(collector, 'sdk', sdk);
  for (let i = 0; i < limits.records; i++) completed(collector, `config-${i}`, config);
  const result = collector.snapshot();
  assert.equal(result.requests.length, limits.records);
  assert.equal(result.limited, true);
  assert.equal(result.noRefererObservedForAllRecognizedRequests, false);
  const events = new HeaderCollector();
  for (let i = 0; i <= limits.events; i++) events.event('loadingFinished', {requestId: 'one'});
  assert.equal(events.snapshot().limited, true);
});

test('DOM evidence is double sanitized and does not grant a tester/provider pass', () => {
  const result = sanitizedDomEvidence({acceptanceVersion: 4, origin: acceptanceOrigin, scenario: 'no-referrer',
    startedAt: '2026-11-12T00:51:12.919Z', rendererStatus: 'ready', productionActivation: true,
    overallVerification: secret, observation: secret, key: secret, sdk: {sdkVersion: '3.65.14a', steady: true,
      loader: {channel: 'quarterly', loading: 'async', authorizationReferrerPolicy: 'origin', scriptReferrerPolicy: 'no-referrer', key: secret},
      providerErrorCodes: [secret], cspEvents: [{effectiveDirective: secret, sourceResource: secret}], rawHeaders: {Cookie: secret}},
    tester: {googleSdkAndAuthorizationRequestsHadNoReferer: false}});
  assert.equal(result.productionActivation, false);
  assert.equal(result.overallVerification, 'NOT_ESTABLISHED');
  assert.equal(result.tester.googleSdkAndAuthorizationRequestsHadNoReferer, false);
  assert.equal(result.sdk.steady, true);
  assert.equal(JSON.stringify(result).includes(secret), false);
  assert.equal(sanitizedDomEvidence({origin: 'https://example.com', scenario: 'no-referrer'}), null);
});

test('running without the explicit live argument makes no browser/provider attempt', () => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../tools/capture_projection_live_headers.mjs', import.meta.url))],
    {encoding: 'utf8', timeout: 5_000});
  assert.equal(result.status, 2);
  assert.match(result.stderr, /No live request made/);
  assert.equal(result.stdout, '');
});
