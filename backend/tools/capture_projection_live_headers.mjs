import {mkdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {connect} from 'node:net';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {sanitizeEvidence} from '../brain_projection/acceptance/evidence.mjs';

// ONE LIVE SCENE ATTEMPT, not a provider acceptance gate or an iPad capture.
// Only Network.requestWillBeSentExtraInfo supplies header evidence. In CDP it
// may precede the base event; redirects reuse requestId. Never substitute the
// provisional request.headers or infer absence from a missing extra event.
// https://chromedevtools.github.io/devtools-protocol/tot/Network/
// https://github.com/microsoft/playwright/blob/v1.56.1/packages/playwright-core/src/server/chromium/crNetworkManager.ts
// https://playwright.dev/docs/api/class-cdpsession
export const limits = Object.freeze({durationMs: 100_000, navigationMs: 45_000,
  sceneMs: 35_000, drainMs: 3_000, requests: 400, events: 8_000, records: 64, hops: 16, tunnels: 80});
export const acceptanceOrigin = 'https://korlix-projection-check-20261111.onrender.com';
export const targetUrl = `${acceptanceOrigin}/no-referrer`;
const playwrightVersion = '1.56.1';
const googleDomains = ['googleapis.com', 'gstatic.com', 'google.com', 'googleusercontent.com'];
const knownOrigins = new Set([acceptanceOrigin, 'https://maps.googleapis.com',
  'https://maps.google.com', 'https://www.google.com', 'https://maps.gstatic.com']);
const endpointOrigins = new Set(['https://maps.googleapis.com', 'https://maps.google.com', 'https://www.google.com']);
const endpoints = new Map([
  ['/maps/api/js', 'sdk-bootstrap'],
  ['/maps/api/js/AuthenticationService.Authenticate', 'sdk-authentication'],
  ['/$rpc/google.internal.maps.mapsjs.v1.MapsJsInternalService/GetMap3DConfig', 'map3d-config'],
  ['/google.internal.maps.mapsjs.v1.MapsJsInternalService/GetMap3DConfig', 'map3d-config'],
]);
const method = value => ['GET', 'POST', 'HEAD', 'OPTIONS'].includes(value) ? value : 'other';
const statusCode = value => Number.isInteger(value) && value >= 100 && value <= 599 ? value : null;
const httpsUrl = value => {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port ? url : null;
  } catch { return null; }
};
const googleHost = host => googleDomains.some(domain => host === domain || host.endsWith(`.${domain}`));

export function allowedTunnel(authority) {
  if (typeof authority !== 'string' || authority.length > 260 || !/^[A-Za-z0-9.-]+:443$/.test(authority)) return null;
  const url = httpsUrl(`https://${authority}`);
  if (!url || (url.origin !== acceptanceOrigin && !googleHost(url.hostname))) return null;
  return {host: url.hostname, port: 443};
}

// A local HTTPS CONNECT boundary enforces the hostname allowlist for every
// connection, including redirects, workers and popups. TLS stays end-to-end;
// this only relays encrypted bytes and never reads/changes HTTP headers/bodies.
// Playwright 1.56.1 context.route() is deliberately NOT used: its Chromium
// routing synthesizes CORS preflight responses and skips redirect callbacks.
// https://nodejs.org/api/http.html#event-connect
// https://playwright.dev/docs/api/class-browsertype#browser-type-launch-option-proxy
export async function createNetworkBoundary(onLimit) {
  const sockets = new Set();
  const stats = {kind: 'local-https-connect-boundary', tlsIntercepted: false, httpHeadersModified: false,
    playwrightRequestInterception: false, quicDisabled: true, connections: 0, blockedConnections: 0, limited: false};
  let closed = false;
  const server = createServer((request, response) => {
    stats.blockedConnections++;
    request.resume();
    response.writeHead(403, {Connection: 'close'}); response.end();
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
  });
  server.on('connect', (request, client, head) => {
    const target = allowedTunnel(request.url);
    if (++stats.connections > limits.tunnels) { stats.limited = true; onLimit(); }
    if (closed || stats.limited || !target || head.length > 65_536) {
      stats.blockedConnections++;
      client.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      return;
    }
    const upstream = connect(target);
    sockets.add(upstream);
    upstream.on('close', () => { sockets.delete(upstream); client.destroy(); });
    upstream.on('error', () => client.destroy());
    client.on('close', () => upstream.destroy());
    upstream.once('connect', () => {
      if (closed || client.destroyed) { upstream.destroy(); return; }
      client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (head.length) upstream.write(head);
      client.pipe(upstream); upstream.pipe(client);
    });
  });
  await new Promise((done, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', done);
  });
  // Runtime errors are reported without addresses, headers or raw messages.
  server.on('error', () => { stats.limited = true; onLimit(); });
  return {url: `http://127.0.0.1:${server.address().port}`, stats, close() {
    closed = true;
    for (const socket of sockets) socket.destroy();
    server.close();
  }};
}

export function recognizedEndpoint(value) {
  const url = httpsUrl(value);
  const family = url && endpointOrigins.has(url.origin) && endpoints.get(url.pathname);
  // All output paths/origins below come from these fixed allowlists. No query,
  // fragment, arbitrary path, provider error string, or credential is retained.
  return family ? {family, origin: url.origin, path: url.pathname} : null;
}

export function refererFromExtraInfo(headers) {
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)) {
    return {refererState: 'unobserved', refererOrigin: null};
  }
  const names = Object.keys(headers).filter(name => name.toLowerCase() === 'referer');
  if (!names.length) return {refererState: 'absent', refererOrigin: null};
  // Empty/malformed/duplicated Referer values still mean a header was present.
  let origin = 'redacted-or-invalid-origin';
  if (names.length === 1 && typeof headers[names[0]] === 'string') {
    try {
      const parsed = new URL(headers[names[0]]);
      if (knownOrigins.has(parsed.origin)) origin = parsed.origin;
    } catch { /* Do not expose an invalid value. */ }
  }
  return {refererState: 'present', refererOrigin: origin};
}

const endpointKey = (endpoint, verb) => `${endpoint.origin}${endpoint.path} ${method(verb)}`;
const count = (map, key) => map.set(key, (map.get(key) || 0) + 1);

export class HeaderCollector {
  constructor() {
    this.chains = new Map();
    this.playwrightCounts = new Map();
    this.playwrightRequests = 0;
    this.networkRequests = 0;
    this.events = 0;
    this.limited = false;
    this.unmatchedResponseEvents = 0;
  }

  _chain(id) {
    if (typeof id !== 'string' || !id || this.limited) return null;
    if (!this.chains.has(id)) {
      if (this.chains.size >= limits.requests) { this.limited = true; return null; }
      this.chains.set(id, {ordinal: this.chains.size + 1, hops: [], extras: [], responseExtras: [], discontinuous: false});
    }
    return this.chains.get(id);
  }

  observePlaywrightRequest(url, verb) {
    if (++this.playwrightRequests > limits.requests) this.limited = true;
    const endpoint = recognizedEndpoint(url);
    if (endpoint) count(this.playwrightCounts, endpointKey(endpoint, verb));
  }

  event(name, value) {
    if (++this.events > limits.events) { this.limited = true; return; }
    const chain = this._chain(value?.requestId);
    if (!chain) return;
    const last = () => chain.hops.at(-1);
    const response = (hop, raw) => {
      hop.responseStatus = statusCode(raw?.status);
      hop.cacheOrServiceWorker ||= raw?.fromDiskCache === true || raw?.fromServiceWorker === true || raw?.fromPrefetchCache === true;
    };
    if (name === 'requestWillBeSent') {
      if (++this.networkRequests > limits.requests || chain.hops.length >= limits.hops) { this.limited = true; return; }
      if (value.redirectResponse && last()) {
        response(last(), value.redirectResponse);
        last().expectsExtraInfo = typeof value.redirectHasExtraInfo === 'boolean' ? value.redirectHasExtraInfo : null;
        last().completion = 'redirected';
      }
      if ((value.redirectResponse && !last()) || (!value.redirectResponse && last())) chain.discontinuous = true;
      chain.hops.push({endpoint: recognizedEndpoint(value.request?.url), method: method(value.request?.method),
        expectsExtraInfo: null, responseStatus: null, cacheOrServiceWorker: false, completion: 'pending'});
    } else if (name === 'requestWillBeSentExtraInfo') {
      if (chain.extras.length >= limits.hops) { this.limited = true; return; }
      // Reduce immediately; never retain value, headers, cookies or timing data.
      chain.extras.push(refererFromExtraInfo(value.headers));
    } else if (name === 'responseReceivedExtraInfo') {
      if (chain.responseExtras.length >= limits.hops) { this.limited = true; return; }
      chain.responseExtras.push(statusCode(value.statusCode));
    } else if (!last()) {
      this.unmatchedResponseEvents++;
    } else if (name === 'responseReceived') {
      response(last(), value.response);
      last().expectsExtraInfo = typeof value.hasExtraInfo === 'boolean' ? value.hasExtraInfo : null;
    } else if (name === 'requestServedFromCache') {
      last().cacheOrServiceWorker = true;
    } else if (name === 'loadingFinished' || name === 'loadingFailed') {
      last().completion = name === 'loadingFinished' ? 'finished' : 'failed';
    }
  }

  snapshot() {
    const requests = [], cdpCounts = new Map();
    let recognizedCount = 0, correlationIncomplete = false;
    for (const chain of this.chains.values()) {
      if (!chain.hops.some(hop => hop.endpoint)) continue;
      const single = chain.hops.length === 1;
      const known = chain.hops.every(hop => hop.expectsExtraInfo !== null);
      const eligible = chain.hops.filter(hop => hop.expectsExtraInfo === true).length;
      // For a single hop the ID alone is unambiguous. For reused IDs, require
      // complete expectation flags and exact counts before pairing in order.
      // A missing/extra event never shifts another hop's headers into its place.
      const finalized = chain.hops.at(-1)?.completion !== 'pending';
      const requestPairable = !chain.discontinuous && finalized && (single ? chain.hops[0].expectsExtraInfo === true && chain.extras.length === 1
        : known && chain.extras.length === eligible);
      const responsePairable = !chain.discontinuous && finalized && (single ? chain.hops[0].expectsExtraInfo === true && chain.responseExtras.length === 1
        : known && chain.responseExtras.length === eligible);
      let requestIndex = 0, responseIndex = 0;
      for (const [index, hop] of chain.hops.entries()) {
        const eligibleHop = hop.expectsExtraInfo === true;
        const extra = requestPairable && eligibleHop ? chain.extras[requestIndex++] : null;
        const networkStatus = responsePairable && eligibleHop ? chain.responseExtras[responseIndex++] : null;
        if (!hop.endpoint) continue;
        recognizedCount++;
        count(cdpCounts, endpointKey(hop.endpoint, hop.method));
        if (!extra || extra.refererState === 'unobserved') correlationIncomplete = true;
        if (requests.length >= limits.records) { correlationIncomplete = true; continue; }
        requests.push({request: chain.ordinal, hop: index + 1, ...hop.endpoint, method: hop.method,
          redirectChain: !single, correlation: extra ? single ? 'single-hop' : 'ordered-redirect-hops' : 'unobserved',
          extraInfoReceived: Boolean(extra), extraInfoExpected: hop.expectsExtraInfo,
          ...(extra || {refererState: 'unobserved', refererOrigin: null}),
          status: networkStatus ?? hop.responseStatus,
          statusSource: networkStatus !== null ? 'response-extra-info' : hop.responseStatus !== null ? 'response-event' : 'unobserved',
          completion: hop.completion, cacheOrServiceWorker: hop.cacheOrServiceWorker});
      }
    }
    const allKeys = new Set([...this.playwrightCounts.keys(), ...cdpCounts.keys()]);
    // CDP can expose CORS preflight requests absent from Playwright's public
    // request stream. Extra CDP requests stay in the audit; missing CDP coverage
    // for a Playwright-observed endpoint prevents an all-requests claim.
    const allPlaywrightRecognizedRequestsCovered = [...allKeys].every(key =>
      (cdpCounts.get(key) || 0) >= (this.playwrightCounts.get(key) || 0));
    const cdpOnlyRecognizedRequests = [...allKeys].reduce((sum, key) =>
      sum + Math.max(0, (cdpCounts.get(key) || 0) - (this.playwrightCounts.get(key) || 0)), 0);
    const families = Object.fromEntries(['sdk-bootstrap', 'sdk-authentication', 'map3d-config'].map(family =>
      [family, requests.filter(request => request.family === family).length]));
    const expectedFamiliesObserved = families['sdk-bootstrap'] > 0 && (families['sdk-authentication'] + families['map3d-config']) > 0;
    const complete = expectedFamiliesObserved && allPlaywrightRecognizedRequestsCovered && !this.limited && !correlationIncomplete &&
      recognizedCount === requests.length && requests.every(request => !request.cacheOrServiceWorker && request.extraInfoReceived);
    const absent = complete && requests.every(request => request.refererState === 'absent');
    return {headerCharacterization: absent ? 'ALL_OBSERVED_RECOGNIZED_REQUESTS_OMITTED_REFERER'
      : complete ? 'REFERER_PRESENT_IN_OBSERVED_REQUESTS' : 'INCONCLUSIVE',
      noRefererObservedForAllRecognizedRequests: absent,
      scope: 'Only the recognized SDK/authentication/configuration requests observed in this Chromium run; not all Google traffic or iPad headers.',
      counts: {playwrightRequests: this.playwrightRequests, cdpRequests: this.networkRequests,
        cdpEvents: this.events, recognizedRequests: recognizedCount, families, allPlaywrightRecognizedRequestsCovered, cdpOnlyRecognizedRequests,
        expectedFamiliesObserved, correlationIncomplete, unmatchedResponseEvents: this.unmatchedResponseEvents},
      limited: this.limited || recognizedCount > limits.records, requests};
  }
}

const isoTime = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ? value : null;
export function sanitizedDomEvidence(raw) {
  if (!raw || typeof raw !== 'object' || raw.origin !== acceptanceOrigin || raw.scenario !== 'no-referrer') return null;
  return {acceptanceVersion: Number.isInteger(raw.acceptanceVersion) && raw.acceptanceVersion > 0 && raw.acceptanceVersion <= 20 ? raw.acceptanceVersion : null,
    origin: acceptanceOrigin, scenario: 'no-referrer', productionActivation: false, overallVerification: 'NOT_ESTABLISHED',
    startedAt: isoTime(raw.startedAt), closedAt: isoTime(raw.closedAt),
    rendererStatus: ['not-started', 'loading', 'ready', 'error'].includes(raw.rendererStatus) ? raw.rendererStatus : 'unknown',
    sdk: raw.sdk ? sanitizeEvidence(raw.sdk, 'no-referrer') : null,
    tester: {googleSdkAndAuthorizationRequestsHadNoReferer: raw.tester?.googleSdkAndAuthorizationRequestsHadNoReferer === true}};
}

export async function runLiveOnce() {
  const started = Date.now(), collector = new HeaderCollector();
  const outputDirectory = resolve(process.env.PROJECTION_LIVE_HEADER_ARTIFACTS || 'projection-live-header-audit');
  const report = {auditVersion: 1, target: targetUrl, scenario: 'no-referrer', productionActivation: false,
    overallVerification: 'NOT_ESTABLISHED', providerVerified: false, testerAttestationPerformed: false,
    evidenceSources: {headers: 'CDP Network.requestWillBeSentExtraInfo only; not a server-side receipt.',
      dom: 'Public sanitized #evidence text; page/loader policy settings are not header evidence.'},
    playwrightVersion, browserVersion: null, startedAt: new Date(started).toISOString(),
    loadClicks: 0, retries: 0, outcome: 'not-started', limits, closedPopups: 0, transport: null,
    navigationStatus: null, sceneDomEvidence: null, closedDomEvidence: null, failureStage: null};
  let browser, context, page, boundary, stage = 'load-pinned-playwright', stopped = false, hardLimit = false;
  const close = async () => {
    stopped = true;
    boundary?.close();
    let timer;
    try {
      await Promise.race([browser?.close().catch(() => {}), new Promise(done => { timer = setTimeout(done, 5_000); })]);
    } finally { clearTimeout(timer); }
  };
  await mkdir(outputDirectory, {recursive: true});
  const watchdog = setTimeout(() => { hardLimit = true; void close(); }, limits.durationMs);
  const readEvidence = async () => {
    const text = await page.locator('#evidence').textContent({timeout: 2_000});
    if (!text || text.length > 30_000) return null;
    try { return sanitizedDomEvidence(JSON.parse(text)); } catch { return null; }
  };
  try {
    const deps = process.env.PROJECTION_LIVE_HEADER_DEPS;
    if (!deps) throw new Error('Pinned dependencies are required.');
    const require = createRequire(resolve(deps, 'package.json'));
    if (require('playwright/package.json').version !== playwrightVersion) throw new Error('Wrong Playwright version.');
    const {chromium} = require('playwright');
    stage = 'create-network-boundary';
    boundary = await createNetworkBoundary(() => { collector.limited = true; if (!stopped) void close(); });
    report.transport = boundary.stats;
    stage = 'launch-browser';
    browser = await chromium.launch({headless: true, channel: 'chromium', timeout: 20_000,
      proxy: {server: boundary.url, bypass: '<-loopback>'}, args: ['--disable-quic']});
    const version = browser.version();
    report.browserVersion = /^\d{1,3}(?:\.\d{1,6}){3}$/.test(version) ? version : 'unavailable';
    context = await browser.newContext({serviceWorkers: 'block', acceptDownloads: false,
      permissions: [], viewport: {width: 1100, height: 900}});
    // No storageState, HTTP credentials, custom Referer, HAR, tracing or video.
    context.on('request', request => {
      collector.observePlaywrightRequest(request.url(), request.method());
      if (collector.limited && !stopped) void close();
    });
    page = await context.newPage();
    page.on('popup', popup => { report.closedPopups++; void popup.close().catch(() => {}); });
    page.on('dialog', dialog => { void dialog.dismiss().catch(() => {}); });
    page.setDefaultTimeout(5_000);
    stage = 'attach-network-observer';
    const session = await context.newCDPSession(page);
    for (const name of ['requestWillBeSent', 'requestWillBeSentExtraInfo', 'responseReceived',
      'responseReceivedExtraInfo', 'requestServedFromCache', 'loadingFinished', 'loadingFailed']) {
      session.on(`Network.${name}`, event => {
        collector.event(name, event);
        if (collector.limited && !stopped) void close();
      });
    }
    await session.send('Network.enable');
    await session.send('Network.setCacheDisabled', {cacheDisabled: true});
    await session.send('Network.setBypassServiceWorker', {bypass: true});
    stage = 'navigate-approved-page';
    const response = await page.goto(targetUrl, {waitUntil: 'domcontentloaded', timeout: limits.navigationMs});
    report.navigationStatus = statusCode(response?.status());
    if (page.url() !== targetUrl || report.navigationStatus !== 200) throw new Error('Unexpected page.');
    stage = 'verify-no-referrer-page';
    if (await page.locator('meta[name="acceptance-mode"]').getAttribute('content') !== 'no-referrer' ||
        await page.locator('meta[name="acceptance-configured"]').getAttribute('content') !== 'true') throw new Error('Page is not configured.');
    const initial = await readEvidence();
    if (!initial || initial.startedAt || initial.tester.googleSdkAndAuthorizationRequestsHadNoReferer) throw new Error('Unexpected initial evidence.');
    stage = 'one-explicit-load';
    await page.getByRole('button', {name: 'Load test map', exact: true}).click();
    report.loadClicks = 1;
    stage = 'observe-single-scene';
    try {
      await page.waitForFunction(() => {
        const text = document.getElementById('evidence')?.textContent;
        if (!text || text.length > 30_000) return false;
        try { return ['ready', 'error'].includes(JSON.parse(text).rendererStatus); } catch { return false; }
      }, null, {timeout: limits.sceneMs});
      report.outcome = 'scene-terminal-state-observed';
    } catch {
      report.outcome = stopped ? 'capture-interrupted' : 'scene-observation-timeout';
    }
    if (!stopped) {
      // Preserve the observed scene before draining/closing. A late error while
      // the iframe is removed must not replace the state actually observed.
      report.sceneDomEvidence = await readEvidence();
      // Extra-info delivery is asynchronous. This is one bounded drain, not a
      // second scene attempt, refresh, or provider/network retry.
      await new Promise(done => setTimeout(done, limits.drainMs));
      stage = 'close-test-map';
      await page.getByRole('button', {name: 'Close test map', exact: true}).click();
      await new Promise(done => setTimeout(done, 300));
      report.closedDomEvidence = await readEvidence();
    }
  } catch {
    // Playwright/CDP exception messages can contain URLs or headers. Persist
    // only our fixed stage name, never the raw error, stack, console or body.
    report.outcome = 'capture-incomplete';
    report.failureStage = stage;
  } finally {
    clearTimeout(watchdog);
    await close();
    report.durationMs = Date.now() - started;
    report.hardDurationLimitReached = hardLimit;
    report.network = collector.snapshot();
    if (hardLimit || collector.limited || report.failureStage || report.loadClicks !== 1) {
      report.network.headerCharacterization = 'INCONCLUSIVE';
      report.network.noRefererObservedForAllRecognizedRequests = false;
    }
    await writeFile(resolve(outputDirectory, 'report.json'), `${JSON.stringify(report, null, 2)}\n`, {mode: 0o600});
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--run-live-once') {
    console.error('No live request made. This audit requires the explicit --run-live-once argument.');
    process.exitCode = 2;
  } else {
    try {
      const report = await runLiveOnce();
      console.log(JSON.stringify({outcome: report.outcome, headerCharacterization: report.network.headerCharacterization,
        productionActivation: false, overallVerification: 'NOT_ESTABLISHED'}));
      if (report.failureStage || report.hardDurationLimitReached || report.network.limited) process.exitCode = 1;
    } catch {
      console.error('Header audit could not write a sanitized report. No raw diagnostics are emitted.');
      process.exitCode = 1;
    }
  }
}
