import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {readFile} from 'node:fs/promises';
import {ProjectionError, publicProjectionConfiguration, projectionConfiguration, normalizeQuery, normalizePlace,
  normalizeQuestion, parseGeocodingResponse, resolvePlace, directProjectionAnswer, parsePlaceAnswer, researchPlace} from '../brain_projection/core.mjs';
import {registerBrainProjection} from '../brain_projection/routes.mjs';
import {rendererDocument, CESIUM_VERSION, CESIUM_JS_INTEGRITY, CESIUM_CSS_INTEGRITY} from '../brain_projection/renderer.mjs';

const environment = {BRAIN_PROJECTION_GEOCODING_KEY: 'server-only-geocoding-test-key',
  BRAIN_PROJECTION_MAP_BROWSER_KEY: 'browser-restricted-test-key-12345',
  BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED: 'true',
  RENDER_EXTERNAL_URL: 'https://chee-chai-chee-backend.onrender.com', OPENAI_API_KEY: 'server-only-openai-test-key'};
const place = {id: 'confirmed-place', label: 'Confirmed address', address: '10 Test Street, Example City',
  latitude: 40.7, longitude: -73.9, userQuery: '10 Test Street, Example City', provider: 'google'};
const source = {title: 'Official census source', url: 'https://www.census.gov/quickfacts/newyorkcitynewyork', date: '2024'};
const answer = {supported: true, text: 'The official source reports the population for the city for 2024. [1]',
  sources: [source], scope: 'City boundary', date: '2024'};
function providerAnswer(value = answer, output = []) {
  return {status: 'completed', output_text: JSON.stringify(value), output: [
    {type: 'web_search_call', status: 'completed', action: {type: 'search', sources: [source]}}, ...output]};
}
function geocode(patch = {}) {
  return {place_id: 'place-1', formatted_address: '10 Test Street, Example City, NY 10001, USA',
    geometry: {location: {lat: 40.7, lng: -73.9}}, address_components: [
      {long_name: '10', types: ['street_number']}, {long_name: '10001', types: ['postal_code']}], ...patch};
}

test('public configuration exposes only readiness, not private or public API keys', () => {
  assert.deepEqual(publicProjectionConfiguration({}), {version: 'projection-v1', mapAvailable: false,
    geocodingAvailable: false, answersAvailable: false, rendererUrl: null});
  const configured = publicProjectionConfiguration(environment);
  assert.equal(configured.rendererUrl, environment.RENDER_EXTERNAL_URL + '/brain-projection/earth.html');
  assert.equal(configured.answersAvailable, true);
  assert.doesNotMatch(JSON.stringify(configured), /test-key|geocoding-test/);
  assert.equal(publicProjectionConfiguration({...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: environment.BRAIN_PROJECTION_GEOCODING_KEY}).mapAvailable, false);
  assert.equal(publicProjectionConfiguration({...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: ''}).mapAvailable, false);
  assert.equal(publicProjectionConfiguration({...environment, BRAIN_PROJECTION_GEOCODING_KEY: ''}).mapAvailable, true);
});

test('renderer origin and explicitly public key fail closed', () => {
  for (const origin of ['http://example.com', 'javascript:alert(1)', 'https://user:password@korlix.com',
    'https://127.0.0.1', 'https://localhost', 'https://korlix.com/path', 'https://korlix.com?key=secret', 'https://korlix.com#token']) {
    assert.equal(publicProjectionConfiguration({...environment, KORLIX_PUBLIC_BACKEND_URL: origin}).mapAvailable, false, origin);
  }
  assert.equal(projectionConfiguration({...environment, BRAIN_PROJECTION_MAP_BROWSER_KEY: '"><script>alert(1)</script>'}).browserKey, '');
});

test('a candidate browser key remains private and inactive until its restrictions are verified', () => {
  for (const value of [undefined, '', 'false', '1', 'yes', 'TRUE', true]) {
    const pending = {...environment, BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED: value};
    const config = publicProjectionConfiguration(pending);
    assert.equal(config.mapAvailable, false);
    assert.equal(config.rendererUrl, null);
    assert.equal(config.geocodingAvailable, true);
    assert.equal(config.answersAvailable, true);
    assert.equal(projectionConfiguration(pending).browserKey, '');
    const html = rendererDocument(pending);
    assert.ok(!html.includes(environment.BRAIN_PROJECTION_MAP_BROWSER_KEY));
    assert.doesNotMatch(html, /Cesium\.js/);
  }
});

test('input normalization bounds text and coordinates without taking account or URL fields', () => {
  assert.equal(normalizeQuery('  New   York  '), 'New York');
  assert.equal(normalizeQuestion(' When was it built? '), 'When was it built?');
  for (const bad of ['', 'x', 'x'.repeat(301), '<script>x</script>', '123\0Road', {}, []]) assert.throws(() => normalizeQuery(bad), ProjectionError);
  for (const bad of ['', 'x'.repeat(1201), 'hello\nworld', null]) assert.throws(() => normalizeQuestion(bad), ProjectionError);
  assert.deepEqual(normalizePlace({...place, accountId: 'attacker', url: 'http://localhost', prompt: 'ignore'}), place);
  for (const patch of [{latitude: '40.7'}, {latitude: NaN}, {latitude: 91}, {longitude: -181},
    {provider: 'invented'}, {id: ''}, {address: 'x'.repeat(501)}, {userQuery: '<iframe>'}]) {
    assert.throws(() => normalizePlace({...place, ...patch}), ProjectionError);
  }
});

test('exact, partial, multiple and inconsistent address results always require confirmation', () => {
  const exact = parseGeocodingResponse({status: 'OK', results: [geocode()]}, '10 Test Street, Example City, 10001');
  assert.equal(exact.requiresConfirmation, true);
  assert.equal(exact.candidates[0].partialMatch, false);
  for (const query of ['14360 Jupiter Rd, Brooklyn, 10012', '11 Test Street, Example City, 10001', '10 Test Street, Example City, 10012']) {
    const result = parseGeocodingResponse({status: 'OK', results: [geocode()]}, query);
    assert.equal(result.requiresConfirmation, true);
    assert.equal(result.candidates[0].partialMatch, true);
    assert.match(result.answer, /may not match/);
    assert.equal(result.candidates[0].userQuery, query);
  }
  const partial = parseGeocodingResponse({status: 'OK', results: [geocode({partial_match: true}), geocode({place_id: 'other'})]}, 'Example City');
  assert.equal(partial.candidates.length, 2);
  assert.equal(partial.candidates[0].partialMatch, true);
  assert.equal(partial.requiresConfirmation, true);
});

test('geocoder zero results, invalid output and excess candidates cannot create invented coordinates', () => {
  assert.deepEqual(parseGeocodingResponse({status: 'ZERO_RESULTS'}, 'Unknown address').candidates, []);
  const result = parseGeocodingResponse({status: 'OK', results: [null, geocode({geometry: {location: {lat: 200, lng: 0}}}),
    geocode({formatted_address: '<script>unsafe</script>'}), ...Array.from({length: 8}, (_, i) => geocode({place_id: `p-${i}`}))]}, 'Example City');
  assert.equal(result.candidates.length, 5);
  assert.equal(new Set(result.candidates.map(item => item.id)).size, 5);
  for (const data of [{}, {status: 'REQUEST_DENIED', error_message: 'secret key'}, {status: 'OK', results: {}}]) {
    assert.throws(() => parseGeocodingResponse(data, 'Example City'), error => error instanceof ProjectionError && !/secret key/.test(error.message));
  }
});

test('geocoding fetch uses one fixed HTTPS provider, bounded body, timeout and no redirects', async () => {
  const requests = [];
  const result = await resolvePlace({query: 'http://127.0.0.1/private', environment,
    fetchImpl: async (url, options) => {requests.push({url, options}); return Response.json({status: 'OK', results: [geocode()]});}});
  const url = new URL(requests[0].url);
  assert.equal(url.origin, 'https://maps.googleapis.com');
  assert.equal(url.searchParams.get('address'), 'http://127.0.0.1/private');
  assert.equal(requests[0].options.redirect, 'error');
  assert.ok(requests[0].options.signal instanceof AbortSignal);
  assert.equal(result.candidates.length, 1);
  assert.doesNotMatch(JSON.stringify(result), /server-only/);
  await assert.rejects(resolvePlace({query: 'Example City', environment: {}, fetchImpl: () => {throw Error('must not fetch');}}), {code: 'projection_geocoding_not_configured'});
  for (const fetchImpl of [async () => new Response('secret-key', {status: 403}), async () => {throw Error(environment.BRAIN_PROJECTION_GEOCODING_KEY);},
    async () => new Response('x'.repeat(270000)), async () => new Response('{malformed')]) {
    await assert.rejects(resolvePlace({query: 'Example City', environment, fetchImpl}), error =>
      error.code === 'projection_geocoding_unavailable' && !/secret|test-key|server-only/.test(error.message));
  }
});

test('live footage and imagery capture dates get honest deterministic availability answers', () => {
  for (const question of ['show me a LIVE view of the address', 'show real-time satellite imagery', 'Can I watch the webcam?', 'Show CCTV']) {
    const result = directProjectionAnswer(question);
    assert.deepEqual(result.sources, []);
    assert.match(result.text, /not connected/);
    assert.match(result.text, /recorded imagery/);
  }
  assert.match(directProjectionAnswer('When was this imagery captured?').text, /cannot verify/);
  assert.equal(directProjectionAnswer('Who is the mayor?'), null);
  assert.equal(directProjectionAnswer('How many people live in this city?'), null);
});

test('sourced answers retain geographic scope, reference date and numbered links', () => {
  assert.deepEqual(parsePlaceAnswer(providerAnswer(), 'How many people live in this city?'),
    {text: answer.text, sources: [source], scope: answer.scope, date: answer.date});
  const paragraphs = {...answer, text: 'A scoped answer. [1]\n\nAn additional sourced qualification. [1]'};
  assert.equal(parsePlaceAnswer(providerAnswer(paragraphs), 'Tell me about this area').text, paragraphs.text);
  const unsupported = parsePlaceAnswer(providerAnswer({...answer, supported: false}), 'Year built?');
  assert.deepEqual(unsupported.sources, []);
  assert.match(unsupported.text, /could not verify/);
});

test('source URLs must occur in completed research evidence and use a safe public HTTPS host', () => {
  for (const url of ['https://unknown-city.gov/unretrieved', 'http://www.census.gov', 'javascript:alert(1)',
    'https://127.0.0.1/secret', 'https://[::1]/secret', 'https://localhost/secret', 'https://account:secret@city.gov/',
    'https://example.internal/private', 'https://city.gov:8443/', 'https://city.gov/with space']) {
    const forged = {...answer, sources: [{...source, url}]};
    assert.throws(() => parsePlaceAnswer(providerAnswer(forged), 'Who is mayor?'), {code: 'projection_sources_unavailable'}, url);
  }
  const onlyAnnotation = providerAnswer(answer, [{type: 'message', content: [{type: 'output_text', annotations: [{type: 'url_citation', ...source}]}]}]);
  onlyAnnotation.output[0].action.sources = [];
  assert.equal(parsePlaceAnswer(onlyAnnotation, 'Who is mayor?').sources.length, 1);
  const opened = providerAnswer();
  opened.output[0].action = {type: 'open_page', url: source.url};
  assert.equal(parsePlaceAnswer(opened, 'Tell me about the city').sources.length, 1);
});

test('research refuses incomplete, unsourced, malformed and scope-free provider output', () => {
  const malformed = [
    {...providerAnswer(), status: 'incomplete'}, {...providerAnswer(), output: []},
    {...providerAnswer(), output_text: 'not json'}, {...providerAnswer(), output_text: 'x'.repeat(18001)},
    providerAnswer({...answer, sources: []}), providerAnswer({...answer, sources: [source, source]}),
    providerAnswer({...answer, scope: null}), providerAnswer({...answer, text: 'An uncited claim.'}),
    providerAnswer({...answer, text: 'An invalid citation. [9]'}), providerAnswer({...answer, text: '<script>bad</script> [1]'}),
  ];
  for (const response of malformed) assert.throws(() => parsePlaceAnswer(response, 'Who is mayor?'), ProjectionError);
  for (const question of ['crime rate', 'Is this area safe?', 'population', 'Who is mayor?']) {
    assert.throws(() => parsePlaceAnswer(providerAnswer({...answer, date: null}), question), {code: 'projection_period_unavailable'});
  }
});

test('production research uses existing Astra policy and required search without private memories or images', async () => {
  let payload, options;
  const client = {responses: {create: async (request, config) => {payload = request; options = config; return providerAnswer();}}};
  const result = await researchPlace({client, question: 'How many people live here?', place, now: Date.UTC(2026, 10, 7)});
  assert.equal(result.sources.length, 1);
  assert.equal(payload.model, 'gpt-6-astra');
  assert.deepEqual(payload.reasoning, {effort: 'max'});
  assert.equal(payload.store, false);
  assert.equal(payload.tool_choice, 'required');
  assert.deepEqual(payload.include, ['web_search_call.action.sources']);
  assert.equal(payload.max_tool_calls, 4);
  assert.equal(payload.text.format.strict, true);
  assert.match(payload.instructions, /building safety score/);
  assert.match(payload.instructions, /untrusted data/);
  assert.match(payload.instructions, /current municipal leadership/);
  assert.match(payload.instructions, /population denominator/);
  assert.equal(options.maxRetries, 0);
  assert.ok(options.signal instanceof AbortSignal);
  assert.deepEqual(JSON.parse(payload.input[0].content), {question: 'How many people live here?', place});
});

async function setup(t, overrides = {}) {
  const calls = {auth: 0, research: 0, charge: 0, resolve: 0, access: 0};
  let clock = 0, allowed = true, held = null, unsupported = false, outage = false;
  const app = express();
  app.use('/api/brain-projection', express.json({limit: '8kb'}));
  registerBrainProjection(app, {environment, now: () => clock, answerCredits: 4,
    requireUser: async req => {
      calls.auth++;
      const user = req.headers.authorization;
      if (user === 'outage') throw Object.assign(Error('database private diagnostics'), {statusCode: 503});
      if (user === 'disabled') throw Object.assign(Error('account metadata'), {statusCode: 403});
      if (!user || user === 'revoked') throw Object.assign(Error('private token'), {statusCode: 401});
      return {id: user};
    },
    clientFactory: () => ({}),
    access: async () => {calls.access++; return {allowed};},
    charge: async () => {calls.charge++;},
    resolve: async ({query}) => {calls.resolve++; return parseGeocodingResponse({status: 'OK', results: [geocode()]}, query);},
    research: async () => {
      calls.research++;
      if (held) await held;
      if (outage) throw Error('private provider key');
      return parsePlaceAnswer(providerAnswer({...answer, supported: !unsupported}), 'population');
    }, ...overrides});
  app.use((error, _req, res, _next) => res.status(error.status || 500).json({error: 'Request unavailable'}));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const send = async (path, body, user = 'user-a') => {
    const response = await fetch(base + path, {method: body === undefined ? 'GET' : 'POST',
      headers: {'Content-Type': 'application/json', ...(user ? {Authorization: user} : {})},
      ...(body !== undefined ? {body: JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json(), headers: response.headers};
  };
  return {calls, base, send, advance: ms => {clock += ms;}, allow: value => {allowed = value;},
    hold: value => {held = value;}, unsupported: value => {unsupported = value;}, outage: value => {outage = value;}};
}
const questionBody = {question: 'What is the population?', place};

test('all API endpoints use existing auth and preserve revoked, disabled and service-unavailable statuses', async t => {
  const f = await setup(t);
  for (const [user, status] of [['', 401], ['revoked', 401], ['disabled', 403], ['outage', 503]]) {
    for (const [path, body] of [['config', undefined], ['resolve', {query: 'New York'}], ['answer', questionBody]]) {
      const response = await f.send(`/api/brain-projection/${path}`, body, user);
      assert.equal(response.status, status);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      assert.doesNotMatch(JSON.stringify(response.body), /database|metadata|private|token/);
    }
  }
  assert.equal(f.calls.research, 0);
  assert.equal(f.calls.resolve, 0);
});

test('config advertises existing research cost and disables answers without every dependency', async t => {
  const f = await setup(t);
  const response = await f.send('/api/brain-projection/config');
  assert.equal(response.body.answerCredits, 4);
  assert.equal(response.body.answerCostLabel, '4 credits per sourced answer');
  assert.equal(response.body.answersAvailable, true);
  const missing = await setup(t, {environment: {}});
  const config = (await missing.send('/api/brain-projection/config')).body;
  assert.equal(config.rendererUrl, null);
  assert.equal(config.answersAvailable, false);
  assert.equal(config.geocodingAvailable, false);
  assert.equal((await missing.send('/api/brain-projection/answer', questionBody)).status, 503);
});

test('allowance is checked before research; successful sourced answers charge once per account-bound retry', async t => {
  const f = await setup(t);
  f.allow(false);
  assert.equal((await f.send('/api/brain-projection/answer', questionBody)).status, 429);
  assert.equal(f.calls.research, 0);
  f.allow(true);
  const first = await f.send('/api/brain-projection/answer', questionBody);
  assert.equal(first.status, 200);
  assert.equal(first.body.creditsUsed, 4);
  const retry = await f.send('/api/brain-projection/answer', questionBody);
  assert.equal(retry.body.replayed, true);
  assert.equal(f.calls.research, 1);
  assert.equal(f.calls.charge, 1);
  await f.send('/api/brain-projection/answer', questionBody, 'user-b');
  assert.equal(f.calls.charge, 2);
  f.advance(31000);
  await f.send('/api/brain-projection/answer', questionBody);
  assert.equal(f.calls.charge, 3);
});

test('concurrent duplicate research coalesces; a different question cannot race the account charge', async t => {
  const f = await setup(t);
  let release;
  f.hold(new Promise(resolve => {release = resolve;}));
  const first = f.send('/api/brain-projection/answer', questionBody);
  while (!f.calls.research) await new Promise(resolve => setTimeout(resolve, 1));
  const retry = f.send('/api/brain-projection/answer', questionBody);
  const another = await f.send('/api/brain-projection/answer', {...questionBody, question: 'What is next door?'});
  assert.equal(another.status, 409);
  release();
  const results = await Promise.all([first, retry]);
  assert.equal(results[0].status, 200);
  assert.equal(results[1].body.replayed, true);
  assert.equal(f.calls.research, 1);
  assert.equal(f.calls.charge, 1);
});

test('direct availability, no-source answers and failures never charge research credits', async t => {
  const f = await setup(t);
  f.allow(false);
  const live = await f.send('/api/brain-projection/answer', {question: 'Show a LIVE view of the address'});
  assert.equal(live.status, 200);
  assert.equal(f.calls.access, 0);
  f.allow(true);
  f.unsupported(true);
  const unsupported = await f.send('/api/brain-projection/answer', questionBody);
  assert.equal(unsupported.body.creditsUsed, 0);
  assert.equal(f.calls.charge, 0);
  f.outage(true);
  const failed = await f.send('/api/brain-projection/answer', {...questionBody, question: 'Who is the mayor?'});
  assert.equal(failed.status, 503);
  assert.doesNotMatch(JSON.stringify(failed.body), /private|provider key/);
  assert.equal(f.calls.charge, 0);
});

test('malformed requests and abuse budgets stop before provider requests', async t => {
  const f = await setup(t);
  for (const body of [{}, [], {query: 'x'.repeat(301)}, {query: '<script>'}]) {
    assert.equal((await f.send('/api/brain-projection/resolve', body)).status, 400);
  }
  assert.equal((await f.send('/api/brain-projection/answer', {...questionBody, place: {...place, latitude: 999}})).status, 400);
  assert.equal((await f.send('/api/brain-projection/resolve', {query: 'New York', junk: 'x'.repeat(9000)})).status, 413);
  assert.equal(f.calls.resolve, 0);
  for (let i = 0; i < 20; i++) assert.equal((await f.send('/api/brain-projection/resolve', {query: 'New York'})).status, 200);
  const limited = await f.send('/api/brain-projection/resolve', {query: 'New York'});
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('retry-after'), '60');
  assert.equal(f.calls.resolve, 20);
});

test('hosted renderer is public and map-only, with pinned integrity, attribution and restricted CSP', async t => {
  const f = await setup(t);
  const response = await fetch(f.base + '/brain-projection/earth.html');
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.equal(f.calls.auth, 0);
  assert.match(html, new RegExp(CESIUM_VERSION.replace('.', '\\.')));
  assert.ok(html.includes(CESIUM_JS_INTEGRITY));
  assert.ok(html.includes(CESIUM_CSS_INTEGRITY));
  assert.ok(html.includes(environment.BRAIN_PROJECTION_MAP_BROWSER_KEY));
  assert.ok(!html.includes(environment.BRAIN_PROJECTION_GEOCODING_KEY));
  assert.ok(!html.includes(environment.OPENAI_API_KEY));
  assert.match(html, /map-credits/);
  assert.match(html, /Capture date unavailable/);
  const policy = response.headers.get('content-security-policy');
  assert.match(policy, /frame-src 'none'/);
  const scriptPolicy = policy.split('; ').find(directive => directive.startsWith('script-src '));
  assert.equal(scriptPolicy, "script-src 'self' https://cesium.com 'unsafe-eval'",
    'The pinned Cesium bundle requires string evaluation; only the isolated renderer receives this exception');
  assert.doesNotMatch(scriptPolicy, /unsafe-inline|https:\/\/\*|data:|blob:/);
  assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin');
  assert.match(response.headers.get('permissions-policy'), /microphone=\(\)/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const unconfigured = rendererDocument({});
  assert.doesNotMatch(unconfigured, /Cesium\.js/);
  assert.match(unconfigured, /not connected/);
  for (const filename of ['earth.mjs', 'camera.mjs', 'earth.css']) {
    assert.equal((await fetch(f.base + '/brain-projection/' + filename)).status, 200);
  }
  assert.equal((await fetch(f.base + '/brain-projection/unknown.js')).status, 404);
});

test('production integration reuses existing auth and search policy without modifying voice or purchases', async () => {
  const server = await readFile(new URL('../server.js', import.meta.url), 'utf8');
  assert.match(server, /app\.use\('\/api\/brain-projection', express\.json\(\{limit: '8kb'\}\)\)/);
  assert.match(server, /registerBrainProjection\(app, \{requireUser, environment: process\.env/);
  assert.match(server, /projectionSearchCredits = calculateCredits\(\{liveSearchNeeded: true, fileRequested: false\}\)/);
  const integration = server.slice(server.indexOf('registerBrainProjection(app,'), server.indexOf("app.get('/api/brain-voice/health'"));
  assert.match(integration, /incrementUsage/);
  assert.doesNotMatch(integration, /brainBilling\.|reserve\(|korlixRecordVoiceUsage|purchase/);
});
