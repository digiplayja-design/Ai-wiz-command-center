import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {checkProjectionProviderRestrictions, MAX_POTENTIAL_BILLABLE_REQUESTS} from '../tools/check_projection_provider.mjs';

const key = 'candidate-browser-key-sensitive-fixture-12345';
const environment = Object.freeze({BRAIN_PROJECTION_MAP_BROWSER_KEY: key,
  KORLIX_PUBLIC_BACKEND_URL: 'https://korlix.com',
  BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED: 'false',
  BRAIN_PROJECTION_GEOCODING_KEY: 'private-geocoding-key-never-used'});
const rootBody = {asset: {version: '1.1'}, geometricError: 1000,
  root: {boundingVolume: {sphere: [0, 0, 0, 6378137]}, geometricError: 1000, children: []}};
const rootResponse = () => Response.json(rootBody);
function denied(reason, options = {}) {
  return Response.json({error: {code: 403, status: 'PERMISSION_DENIED',
    message: options.message || `Provider message containing ${key}`,
    details: [{'@type': 'type.googleapis.com/google.rpc.ErrorInfo', domain: 'googleapis.com', reason,
      metadata: {service: 'unused-for-output', consumer: 'projects/private-project'}}]}}, {status: 403});
}
const referrerDenied = () => denied('API_KEY_HTTP_REFERRER_BLOCKED');
const apiDenied = () => denied('API_KEY_SERVICE_BLOCKED');
function queuedFetch(factories) {
  const calls = [];
  return {calls, fetchImpl: async (url, options) => {
    calls.push({url, options});
    const factory = factories[calls.length - 1];
    assert.ok(factory, 'No retries or unplanned provider requests are allowed');
    return factory(url, options);
  }};
}
const run = options => checkProjectionProviderRestrictions({environment, allowProviderCheck: true, ...options});

test('explicit opt-in and valid environment are required before any provider request', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls++; throw Error('must not fetch'); };
  for (const options of [{}, {allowProviderCheck: false}, {allowProviderCheck: 'true'}]) {
    const result = await checkProjectionProviderRestrictions({environment, fetchImpl, ...options});
    assert.equal(result.status, 'FAIL');
    assert.equal(result.reason, 'explicit_opt_in_required');
    assert.equal(result.requestsMade, 0);
  }
  for (const candidate of [{}, {...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: ''},
    {...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: 'bad\nkey'},
    {...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: 'x'.repeat(201)}]) {
    assert.equal((await run({environment: candidate, fetchImpl})).reason, 'candidate_browser_key_required');
  }
  for (const origin of [undefined, '', 'http://korlix.com', 'https://127.0.0.1', 'https://localhost',
    'https://korlix.invalid', 'https://user:secret@korlix.com', 'https://korlix.com/path',
    'https://korlix.com?key=secret', 'https://korlix.com#secret', 'https://korlix.com:8443', 'https://korlix.com\n']) {
    const result = await run({environment: {...environment, KORLIX_PUBLIC_BACKEND_URL: origin}, fetchImpl});
    assert.equal(result.reason, 'valid_public_backend_origin_required');
  }
  for (const timeoutMs of [0, -1, 15001, Infinity, '1000']) {
    assert.equal((await run({fetchImpl, timeoutMs})).reason, 'invalid_check_configuration');
  }
  assert.equal(calls, 0);
});

test('all four verified outcomes pass without depending on or changing the renderer flag', async () => {
  const fake = queuedFetch([rootResponse, referrerDenied, referrerDenied, apiDenied]);
  const result = await run(fake);
  assert.equal(result.status, 'PASS');
  assert.equal(result.reason, 'four_provider_checks_verified');
  assert.equal(result.requestsMade, 4);
  assert.deepEqual(result.maxPotentialBillableRequests, {photorealistic3DRoot: 3, geocoding: 1, total: 4});
  assert.deepEqual(result.maxPotentialBillableRequests, MAX_POTENTIAL_BILLABLE_REQUESTS);
  assert.ok(result.checks.every(check => check.status === 'PASS'));
  assert.equal(environment.BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED, 'false');
  for (const [index, call] of fake.calls.entries()) {
    const url = new URL(call.url);
    assert.equal(url.protocol, 'https:');
    assert.equal(call.options.redirect, 'error');
    assert.equal(call.options.credentials, 'omit');
    assert.equal(call.options.cache, 'no-store');
    assert.equal(call.options.method, 'GET');
    assert.ok(call.options.signal instanceof AbortSignal);
    assert.equal(call.options.headers.Accept, 'application/json');
    if (index < 3) {
      assert.equal(url.origin, 'https://tile.googleapis.com');
      assert.equal(url.pathname, '/v1/3dtiles/root.json');
      assert.equal(url.searchParams.get('key'), key);
      assert.equal([...url.searchParams.keys()].length, 1);
    } else {
      assert.equal(url.origin, 'https://geocode.googleapis.com');
      assert.match(url.pathname, /^\/v4\/geocode\/address\/1600\+Amphitheatre\+Parkway/);
      assert.equal(url.search, '');
      assert.equal(call.options.headers['X-Goog-Api-Key'], key);
      assert.equal(call.options.headers['X-Goog-FieldMask'], 'results.placeId');
      assert.equal(call.options.headers.Referer, 'https://korlix.com/');
    }
  }
  assert.equal(fake.calls[0].options.headers.Referer, 'https://korlix.com/');
  assert.equal(fake.calls[1].options.headers.Referer, 'https://korlix-provider-check.invalid/');
  assert.equal(fake.calls[2].options.headers.Referer, undefined);
  assert.equal(fake.calls[2].options.headers.Origin, 'https://korlix.com');
  assert.doesNotMatch(JSON.stringify(result), /sensitive-fixture|private-project|private-geocoding|https:|Provider message/);
});

test('unrestricted, missing-referrer-permitted, and wrong API keys fail with early stop', async () => {
  for (const scenario of [
    {responses: [rootResponse, rootResponse], count: 2, reason: 'unexpected_request_accepted'},
    {responses: [rootResponse, referrerDenied, rootResponse], count: 3, reason: 'unexpected_request_accepted'},
    {responses: [rootResponse, referrerDenied, referrerDenied, () => Response.json({results: [{placeId: 'fixture'}]})],
      count: 4, reason: 'unexpected_request_accepted'},
    {responses: [() => denied('API_KEY_INVALID')], count: 1, reason: 'invalid_key'},
    {responses: [apiDenied], count: 1, reason: 'allowed_origin_not_verified'},
  ]) {
    const fake = queuedFetch(scenario.responses);
    const result = await run(fake);
    assert.equal(result.status, 'FAIL');
    assert.equal(result.reason, scenario.reason);
    assert.equal(result.requestsMade, scenario.count);
    assert.equal(fake.calls.length, scenario.count);
    assert.ok(result.checks.slice(scenario.count).every(check => check.status === 'NOT_RUN'));
  }
});

test('generic denials, unrelated restriction types, quota, billing and disabled APIs are not restriction proof', async () => {
  const ambiguous = [
    () => Response.json({error: {code: 403, status: 'PERMISSION_DENIED', message: 'Forbidden'}}, {status: 403}),
    () => Response.json({status: 'REQUEST_DENIED', error_message: 'This API project is not authorized to use this API.'}),
    () => denied('API_KEY_IP_ADDRESS_BLOCKED'),
    () => denied('API_KEY_SERVICE_BLOCKED'),
    () => denied('SERVICE_DISABLED'),
    () => denied('BILLING_DISABLED'),
    () => denied('RATE_LIMIT_EXCEEDED'),
    () => Response.json({error: {status: 'RESOURCE_EXHAUSTED'}}, {status: 429}),
    () => Response.json({error: {code: 503}}, {status: 503}),
    () => Response.json({error: {code: 403, status: 'PERMISSION_DENIED', details: [
      {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', domain: 'attacker.example', reason: 'API_KEY_HTTP_REFERRER_BLOCKED'}]}}, {status: 403}),
  ];
  for (const response of ambiguous) {
    const fake = queuedFetch([rootResponse, response]);
    const result = await run(fake);
    assert.equal(result.status, 'FAIL');
    assert.equal(result.requestsMade, 2);
    assert.equal(result.checks[1].status, 'FAIL');
  }
  for (const response of [referrerDenied, () => denied('SERVICE_DISABLED'),
    () => denied('BILLING_DISABLED'), () => denied('API_KEY_INVALID'),
    () => Response.json({status: 'REQUEST_DENIED', error_message: 'Key API restrictions might be wrong.'})]) {
    const result = await run(queuedFetch([rootResponse, referrerDenied, referrerDenied, response]));
    assert.equal(result.status, 'FAIL');
    assert.equal(result.checks[3].status, 'FAIL');
  }
});

test('malformed roots, redirects, invalid JSON and oversized bodies fail without following or retrying', async () => {
  const factories = [
    () => Response.json({asset: {version: '1.1'}, root: {}}),
    () => Response.json({error: {code: 403}, ...rootBody}),
    () => Response.json({...rootBody, geometricError: -1}),
    () => Response.json({...rootBody, root: {boundingVolume: {sphere: [0, 1]}}}),
    () => new Response('', {status: 302, headers: {Location: 'https://attacker.invalid/?key=' + key}}),
    () => { const response = rootResponse(); Object.defineProperty(response, 'redirected', {value: true}); return response; },
    () => new Response(key, {headers: {'Content-Type': 'text/html'}}),
    () => new Response('{"unclosed":', {headers: {'Content-Type': 'application/json'}}),
    () => new Response('x'.repeat(256 * 1024 + 1), {headers: {'Content-Type': 'application/json'}}),
    () => new Response('{}', {headers: {'Content-Type': 'application/json', 'Content-Length': '300000'}}),
  ];
  for (const response of factories) {
    const fake = queuedFetch([response]);
    const result = await run(fake);
    assert.equal(result.status, 'FAIL');
    assert.equal(result.requestsMade, 1);
    assert.equal(fake.calls.length, 1);
    assert.ok(!JSON.stringify(result).includes(key));
    assert.doesNotMatch(JSON.stringify(result), /attacker|unclosed|https:/);
  }
});

test('deadline covers a stalled fetch even when the fetch implementation ignores abort', async () => {
  let signal;
  const result = await run({timeoutMs: 10, fetchImpl: async (_url, options) => {
    signal = options.signal;
    return new Promise(() => {});
  }});
  assert.equal(result.status, 'FAIL');
  assert.equal(result.reason, 'timeout');
  assert.equal(result.requestsMade, 1);
  assert.equal(signal.aborted, true);
});

test('deadline also cancels a stalled response stream', async () => {
  let cancelled = false;
  const body = new ReadableStream({start(controller) { controller.enqueue(new TextEncoder().encode('{')); },
    cancel() { cancelled = true; }});
  const result = await run({timeoutMs: 10,
    fetchImpl: async () => new Response(body, {headers: {'Content-Type': 'application/json'}})});
  assert.equal(result.status, 'FAIL');
  assert.equal(result.reason, 'timeout');
  assert.equal(cancelled, true);
});

test('network exceptions and provider details cannot leak keys, full URLs, project IDs or bodies', async () => {
  const fake = queuedFetch([(_url, options) => {
    throw Error(`Request ${_url} failed; headers=${JSON.stringify(options.headers)}; private-project-id`);
  }]);
  const result = await run(fake);
  assert.equal(result.status, 'FAIL');
  assert.equal(result.reason, 'network_error');
  assert.ok(!JSON.stringify(result).includes(key));
  assert.doesNotMatch(JSON.stringify(result), /https:|private-project|headers=/);
});

test('CLI without opt-in or with forbidden arguments emits only sanitized JSON and exits unsuccessfully', () => {
  const filename = fileURLToPath(new URL('../tools/check_projection_provider.mjs', import.meta.url));
  for (const args of [[], [`--key=${key}`], ['--allow-provider-check', '--allow-provider-check']]) {
    const child = spawnSync(process.execPath, [filename, ...args], {
      env: {...process.env, ...environment}, encoding: 'utf8', timeout: 5000,
    });
    assert.equal(child.status, 1);
    assert.equal(child.stderr, '');
    const result = JSON.parse(child.stdout);
    assert.equal(result.status, 'FAIL');
    assert.equal(result.requestsMade, 0);
    assert.ok(!child.stdout.includes(key));
    assert.doesNotMatch(child.stdout, /https:|private-geocoding/);
  }
});
