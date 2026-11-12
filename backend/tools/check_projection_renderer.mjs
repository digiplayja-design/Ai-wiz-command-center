import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {Script} from 'node:vm';
import {registerProjectionRenderer, rendererPolicy, MAPS_JS_CHANNEL} from '../brain_projection/renderer.mjs';

// CI CONTRACT FIXTURES, NOT THE GOOGLE SDK. Google Maps JavaScript requires an
// owner-provisioned valid key. This test runs the real local renderer, headers,
// nonce CSP and camera adapter against a narrowly modeled public maps3d API.
// Every external request is fulfilled from this file or blocked. It proves no
// Google rendering, authorization, attribution layout, coverage or device claim.
const browserKey = 'korlix-maps-js-ci-fixture-not-a-real-credential';
const place = {id: 'ci-camera-contract', label: 'Camera contract fixture', latitude: 40.7, longitude: -73.9};
const scriptOrigin = 'https://maps.googleapis.com';
const scriptPath = '/maps/api/js';
// Chromium 141 reports these intentional iframe denials as console errors even
// when no permission API is called. Keep an exact diagnostic list and assert
// the effective denied capabilities; never suppress CSP/access errors broadly.
const expectedPermissionDiagnostics = new Set(['camera', 'geolocation', 'microphone'].map(capability =>
  `Potential permissions policy violation: ${capability} is not allowed in this document.`));
const modes = ['ready', 'no-coverage', 'lookup-error', 'delayed-lookup-close', 'import-error', 'loader-error', 'auth-failure', 'never-status', 'unverified', 'legacy-only'];

// A synthetic provider exercises both public SDKs. It never fetches Google
// imagery, claims a real facade, or reaches any provider network endpoint.
function installImageryContractFixture(mode) {
  const fixture = window.__projectionProviderFixture = {kind: 'synthetic-imagery-contract-fixture', liveProviderVerified: false,
    imports: [], queries: [], panoramas: 0, maps: 0, flights: [], stops: 0, pending: [],
    bootstrap: {authCallbackInstalled: typeof window.gm_authFailure === 'function',
      callbackInstalled: typeof window.__korlixMapsReady === 'function', loaderNonce: document.currentScript?.nonce,
      moduleNonce: document.querySelector('script[type="module"][nonce]')?.nonce,
      loaderReferrerPolicy: document.currentScript?.referrerPolicy}};
  const records = new Map();
  let panorama = null, map = null;
  function panel(host, title) {
    const node = document.createElement('section');
    node.className = 'contract-viewer';
    node.innerHTML = '<h1>Automated ' + title + ' fixture</h1><p>No real Google imagery or property photograph.</p><footer>Synthetic provider footer · Live provider attribution requires device verification.</footer>';
    const style = document.createElement('style');
    style.nonce = document.querySelector('style[nonce]').nonce;
    style.textContent = '.contract-viewer{height:100%;box-sizing:border-box;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:20px;background:#123343;color:#e8f6ff;font:15px system-ui;text-align:center}.contract-viewer footer{margin-top:auto;font-size:12px}.contract-viewer h1{margin-top:auto}';
    document.head.append(style); host.append(node);
  }
  class StreetViewService {
    getPanorama(request, callback) {
      fixture.queries.push(request);
      const answer = () => {
        if (mode === 'no-coverage') { callback(null, 'ZERO_RESULTS'); return; }
        if (mode === 'lookup-error') { callback(null, 'UNKNOWN_ERROR'); return; }
        let data = records.get(request.pano);
        if (!data) {
          const point = request.location || {lat: 40.7, lng: -73.9};
          const pano = request.pano || 'fixture-pano-' + point.lat;
          data = {location: {pano, latLng: {lat: () => point.lat - .0001, lng: () => point.lng}}, imageDate: '2026-06'};
          records.set(pano, data);
        }
        callback(data, 'OK');
      };
      if (mode === 'delayed-lookup-close') fixture.pending.push(answer); else queueMicrotask(answer);
    }
  }
  class StreetViewPanorama {
    constructor(host, options) { this.host = host; this.options = options; this.listeners = new Map(); this.zoom = 1; this.pov = {heading: 0, pitch: 0}; this.id = ''; this.status = 'UNKNOWN_ERROR'; this.visible = false; panorama = this; fixture.panoramas++; panel(host, 'Street View'); }
    addListener(name, callback) { if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name).add(callback); return {remove: () => this.listeners.get(name).delete(callback)}; }
    emit(name) { for (const fn of [...(this.listeners.get(name) || [])]) fn(); }
    getPano() { return this.id; } getStatus() { return this.status; }
    getPosition() { return records.get(this.id)?.location.latLng; }
    getZoom() { return this.zoom; } setZoom(value) { this.zoom = Math.max(0, Math.min(3, value)); }
    getPov() { return {...this.pov}; } setPov(value) { this.pov = {...value}; }
    setVisible(value) { this.visible = value; }
    setPano(id) { this.id = id; this.status = 'UNKNOWN_ERROR'; this.emit('pano_changed'); if (mode !== 'never-status') requestAnimationFrame(() => { if (this.id !== id) return; this.status = 'OK'; this.emit('status_changed'); }); }
  }
  class Map3DElement extends HTMLElement {
    constructor(options) { super(); Object.assign(this, options); fixture.maps++; map = this; panel(this, '3D Earth'); }
    connectedCallback() { requestAnimationFrame(() => this.steady()); }
    steady() { const event = new Event('gmp-steadychange'); Object.defineProperty(event, 'isSteady', {value: true}); this.dispatchEvent(event); }
    stopCameraAnimation() { fixture.stops++; }
    flyCameraTo(options) { fixture.flights.push(options); Object.assign(this, options.endCamera); requestAnimationFrame(() => this.steady()); }
  }
  customElements.define('gmp-map-3d', Map3DElement);
  fixture.release = () => { for (const answer of fixture.pending.splice(0)) answer(); };
  fixture.publicState = () => ({imports: [...fixture.imports], queries: fixture.queries, panoramas: fixture.panoramas, maps: fixture.maps,
    panorama: panorama ? {pano: panorama.getPano(), zoom: panorama.getZoom(), pov: panorama.getPov(), visible: panorama.visible, options: panorama.options} : null,
    earth: map ? {range: map.range, center: map.center, heading: map.heading, tilt: map.tilt, connected: map.isConnected} : null});
  window.google = {maps: {importLibrary(name) {
    fixture.imports.push(name);
    if (mode === 'import-error') return Promise.reject(Error('private-provider-fixture-details'));
    if (name === 'streetView') return Promise.resolve({StreetViewService, StreetViewPanorama});
    if (name === 'maps3d') return Promise.resolve({Map3DElement});
    return Promise.reject(Error('Unexpected fixture import'));
  }}};
  const ready = window.__korlixMapsReady;
  if (mode === 'auth-failure') window.gm_authFailure();
  ready();
}
const sdkFixture = mode => `(${installImageryContractFixture.toString()})(${JSON.stringify(mode)});`;
for (const mode of modes) new Script(sdkFixture(mode), {filename: `imagery-${mode}-fixture.js`});

// This separate synthetic page exercises the browser's own CSP enforcement.
// It does not load, replace or intercept any Google SDK code.
function installCspEnforcementFixture() {
  const fixture = window.__projectionCspFixture = {kind: 'synthetic-csp-enforcement-fixture',
    liveProviderVerified: false, trustedScriptExecuted: true, unauthorizedScriptExecuted: false,
    dynamicPadding: [], violations: [], completed: false};
  document.addEventListener('securitypolicyviolation', event => {
    fixture.violations.push({directive: event.effectiveDirective, blockedURI: event.blockedURI, disposition: event.disposition});
  });
  const attributeProbe = document.getElementById('style-attribute-probe');
  const elementProbe = document.getElementById('style-element-probe');
  fixture.baseline = {padding: getComputedStyle(attributeProbe).paddingLeft, height: getComputedStyle(elementProbe).height};
  // Individual CSSOM property assignments can bypass the attribute inline check;
  // setAttribute reproduces the operation that the real iPad CSP rejected.
  for (const padding of [37, 43]) {
    attributeProbe.setAttribute('style', `padding-left: ${padding}px`);
    fixture.dynamicPadding.push(getComputedStyle(attributeProbe).paddingLeft);
  }
  const style = document.createElement('style');
  style.id = 'unnonced-style-probe';
  style.textContent = '#style-element-probe{height:991px!important}';
  document.head.append(style);
  // The unnonced script probe follows this bootstrap in the response HTML.
  // It must be parser-inserted: strict-dynamic intentionally trusts scripts
  // constructed by trusted code, so createElement would test a permitted case.
  requestAnimationFrame(() => {
    fixture.finalStyle = {padding: getComputedStyle(attributeProbe).paddingLeft, height: getComputedStyle(elementProbe).height};
    fixture.completed = true;
  });
}

const cspFixture = `(${installCspEnforcementFixture.toString()})();`;
new Script(cspFixture, {filename: 'csp-enforcement-fixture.js'});

async function checkCspEnforcement(browser, origin, report, artifactDirectory, nonces) {
  const result = report.cspEnforcement = {validationKind: 'synthetic-csp-enforcement-fixture', fixture: true,
    liveProviderVerified: false, providerNetworkRequests: 0, unexpectedRequests: [], pageErrors: [], consoleErrors: []};
  const context = await browser.newContext({bypassCSP: false, serviceWorkers: 'block'});
  await context.routeWebSocket('**/*', socket => {
    result.unexpectedRequests.push({kind: 'websocket'}); socket.close();
  });
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.origin === origin) return route.continue();
    result.unexpectedRequests.push({kind: 'blocked', origin: url.origin});
    return route.abort('blockedbyclient');
  });
  const page = await context.newPage();
  page.on('pageerror', error => result.pageErrors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') result.consoleErrors.push(message.text()); });
  page.setDefaultTimeout(10000);
  try {
    const response = await page.goto(`${origin}/__projection_ci/csp.html`, {waitUntil: 'load'});
    assert.equal(response.status(), 200);
    const policy = (await response.allHeaders())['content-security-policy'];
    const nonce = /script-src[^;]*'nonce-([^']+)'/.exec(policy)?.[1];
    assert.ok(nonce && !nonces.has(nonce), 'The CSP fixture needs a fresh response nonce.');
    nonces.add(nonce);
    assert.equal(policy, rendererPolicy(nonce), 'The fixture must use the actual isolated renderer policy.');
    await page.waitForFunction(() => window.__projectionCspFixture?.completed && window.__projectionCspFixture.violations.length >= 2);
    result.observed = await page.evaluate(() => ({...window.__projectionCspFixture,
      unnoncedStyle: !document.getElementById('unnonced-style-probe').hasAttribute('nonce'),
      unnoncedScript: !document.getElementById('unnonced-script-probe').hasAttribute('nonce'),
      googleSdkAbsent: typeof window.google === 'undefined'}));
    const observed = result.observed;
    assert.equal(observed.kind, 'synthetic-csp-enforcement-fixture');
    assert.equal(observed.liveProviderVerified, false);
    assert.equal(observed.googleSdkAbsent, true);
    assert.equal(observed.trustedScriptExecuted, true, 'The matching nonced bootstrap must run.');
    assert.deepEqual(observed.baseline, {padding: '11px', height: '19px'}, 'The matching nonced stylesheet must apply.');
    assert.deepEqual(observed.dynamicPadding, ['37px', '43px'], 'Both dynamic style attribute updates must apply.');
    assert.deepEqual(observed.finalStyle, {padding: '43px', height: '19px'}, 'An unnonced style element must not override the baseline.');
    assert.equal(observed.unnoncedStyle, true);
    assert.equal(observed.unnoncedScript, true);
    assert.equal(observed.unauthorizedScriptExecuted, false, 'An unnonced parser-inserted inline script must not execute.');
    assert.deepEqual([...observed.violations].sort((a, b) => a.directive.localeCompare(b.directive)), [
      {directive: 'script-src-elem', blockedURI: 'inline', disposition: 'enforce'},
      {directive: 'style-src-elem', blockedURI: 'inline', disposition: 'enforce'},
    ], 'Only the two deliberately denied elements may produce CSP violations.');
    // Keep expected denials confined to this page. Ordinary renderer scenarios
    // retain their zero-CSP-violation and strict console-error checks unchanged.
    assert.ok(result.consoleErrors.every(message =>
      /^(Applying inline style violates|Refused to apply inline style because it violates) /.test(message) ||
      /^(Executing inline script violates|Refused to execute inline script because it violates) /.test(message)),
    `Unexpected CSP-fixture console errors: ${JSON.stringify(result.consoleErrors)}`);
    assert.deepEqual(result.pageErrors, []);
    assert.deepEqual(result.unexpectedRequests, [], 'The CSP fixture must not request any provider or external resource.');
    result.passed = true;
    console.log('PASS synthetic CSP enforcement fixture: style attributes apply; unnonced style and parser-inserted inline script blocked; liveProviderVerified=false; forwarded external requests=0');
  } catch (error) {
    result.error = error.stack || error.message;
    result.observed = await page.evaluate(() => window.__projectionCspFixture).catch(() => null);
    await page.screenshot({path: resolve(artifactDirectory, 'fixture-csp-enforcement-failure.png')}).catch(() => {});
    throw error;
  } finally { await context.close(); }
}

async function main() {
  const {default: express} = await import('express');
  const require = createRequire(process.env.KORLIX_PROJECTION_BROWSER_DEPS
    ? resolve(process.env.KORLIX_PROJECTION_BROWSER_DEPS, 'package.json') : import.meta.url);
  const {chromium} = require('playwright');
  assert.equal(require('playwright/package.json').version, '1.56.1');
  const artifactDirectory = resolve(process.env.PROJECTION_RENDERER_ARTIFACTS || 'projection-renderer-artifacts');
  await mkdir(artifactDirectory, {recursive: true});
  const report = {validationKind: 'recorded-imagery-contract-fixture', sdkSource: 'synthetic',
    liveProviderVerified: false, providerNetworkRequests: 0, channel: MAPS_JS_CHANNEL, scenarios: [],
    limits: ['No real Google SDK, imagery, facade, coverage, authentication or billing validation.',
      'No real Google attribution layout or native device/voice acceptance.',
      'Production renderer, CSP and public camera adapters run unchanged against labeled fixtures.']};
  const environment = {};
  const app = express();
  app.disable('x-powered-by');
  registerProjectionRenderer(app, {environment});
  app.get('/favicon.ico', (_req, res) => res.status(204).end());
  app.get('/__projection_ci/csp.html', (_req, res) => {
    const nonce = randomBytes(18).toString('base64url');
    res.set({'Content-Security-Policy': rendererPolicy(nonce), 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'})
      .type('html').send(`<!doctype html><html lang="en"><head><meta charset="utf-8">
      <link rel="icon" href="data:,"><title>Synthetic CSP enforcement fixture</title>
      <style nonce="${nonce}">body{font:16px system-ui;margin:24px}#style-attribute-probe{padding-left:11px}#style-element-probe{height:19px}</style>
      </head><body><h1>Synthetic CSP enforcement fixture</h1>
      <p>No Google SDK, credentials, geographic imagery or live provider verification.</p>
      <div id="style-attribute-probe">Dynamic style attribute probe</div><div id="style-element-probe"></div>
      <script nonce="${nonce}">${cspFixture}</script>
      <script id="unnonced-script-probe">window.__projectionCspFixture.unauthorizedScriptExecuted = true;</script></body></html>`);
  });
  app.get('/__projection_ci/host.html', (_req, res) => res.type('html').send(`<!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <link rel="icon" href="data:,"><title>Projection maps3d contract fixture</title>
    <style>html,body{margin:0;width:100%;height:100%;background:#05111b;color:#e5f2f8;font:13px system-ui}
    body{display:flex;flex-direction:column}header{box-sizing:border-box;padding:12px;flex:0 0 auto;border-bottom:1px solid #456}
    iframe{display:block;flex:1 1 auto;min-height:0;width:100%;border:0}</style></head><body>
    <header id="fixture-banner">CI fixture · No Google SDK, imagery or live provider verification</header>
    <iframe title="Projection renderer contract fixture" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox"
      allow="camera 'none'; microphone 'none'; geolocation 'none'" src="/brain-projection/earth.html"></iframe></body></html>`));
  const server = createServer(app);
  let browser;
  await new Promise((resolveListening, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolveListening);});
  const origin = `http://127.0.0.1:${server.address().port}`;
  const nonces = new Set();


  try {
    browser = await chromium.launch({headless: true, args: ['--disable-background-networking']});
    await checkCspEnforcement(browser, origin, report, artifactDirectory, nonces);
    for (const mode of modes) {
      for (const name of Object.keys(environment)) delete environment[name];
      Object.assign(environment, {BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: browserKey,
        BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: 'true', KORLIX_PUBLIC_BACKEND_URL: 'https://korlix.com'});
      if (mode === 'unverified') environment.BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED = 'false';
      if (mode === 'legacy-only') { delete environment.BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY; environment.BRAIN_PROJECTION_MAP_BROWSER_KEY = browserKey; }
      const result = {mode, fixture: true, liveProviderVerified: false, loaderRequests: [], unexpectedRequests: [], pageErrors: [], consoleErrors: [], geometry: []};
      report.scenarios.push(result);
      const context = await browser.newContext({viewport: {width: 1280, height: 800}, serviceWorkers: 'block', bypassCSP: false});
      await context.addInitScript(() => {
        window.__projectionContractObserver = {violations: [], messages: []};
        window.addEventListener('securitypolicyviolation', event => window.__projectionContractObserver.violations.push({directive: event.effectiveDirective, blockedURI: event.blockedURI}));
        window.addEventListener('message', event => {
          const frame = document.querySelector('iframe');
          if (window === window.top && event.source === frame?.contentWindow && event.origin === location.origin) window.__projectionContractObserver.messages.push(event.data);
        });
      });
      await context.routeWebSocket('**/*', socket => { result.unexpectedRequests.push({kind: 'websocket'}); socket.close(); });
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.origin === origin) return route.continue();
        if (url.origin === scriptOrigin && url.pathname === scriptPath) {
          assert.equal(url.searchParams.get('key'), browserKey);
          assert.deepEqual(Object.fromEntries([...url.searchParams].filter(([name]) => name !== 'key')),
            {v: 'quarterly', loading: 'async', callback: '__korlixMapsReady', auth_referrer_policy: 'origin'});
          result.loaderRequests.push({path: scriptPath, intercepted: true});
          return route.fulfill({status: mode === 'loader-error' ? 503 : 200, contentType: 'application/javascript', body: mode === 'loader-error' ? '' : sdkFixture(mode)});
        }
        result.unexpectedRequests.push({kind: 'blocked', origin: url.origin, path: url.pathname}); return route.abort('blockedbyclient');
      });
      const page = await context.newPage();
      page.setDefaultTimeout(40000);
      page.on('pageerror', error => result.pageErrors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') result.consoleErrors.push(message.text()); });
      let frame, response, sequence = 0;
      page.on('response', value => { if (value.url() === `${origin}/brain-projection/earth.html`) response = value; });
      const command = (operation, camera = {}, destination = undefined) => page.evaluate(value => {
        document.querySelector('iframe').contentWindow.postMessage(value, location.origin);
      }, {type: 'korlix-projection-camera', camera: {operation, sequence: ++sequence, ...camera}, ...(destination ? {place: destination} : {})});
      const waitView = (status, reason, seq = sequence) => page.waitForFunction(value => window.__projectionContractObserver.messages.some(message =>
        message.type === 'korlix-projection-status' && message.status === value.status && (!value.reason || message.reason === value.reason) &&
        (value.sequence === 0 || message.sequence === value.sequence)), {status, reason, sequence: seq});
      const waitCamera = (state, reason, seq = sequence) => page.waitForFunction(value => window.__projectionContractObserver.messages.some(message =>
        message.type === 'korlix-projection-camera-status' && message.state === value.state && message.reason === value.reason && message.sequence === value.sequence),
      {state, reason, sequence: seq});
      const snapshot = () => frame.evaluate(() => window.__projectionProviderFixture?.publicState());
      const frames = () => frame.evaluate(async () => { for (let i = 0; i < 5; i++) await new Promise(resolve => requestAnimationFrame(resolve)); });
      try {
        const started = Date.now();
        await page.goto(`${origin}/__projection_ci/host.html`, {waitUntil: 'load'});
        frame = page.frames().find(value => value.url() === `${origin}/brain-projection/earth.html`);
        assert.ok(frame && response); assert.equal(response.status(), 200);
        const headers = await response.allHeaders();
        assert.equal(headers['cache-control'], 'no-store'); assert.equal(headers['referrer-policy'], 'strict-origin-when-cross-origin');
        const nonce = /script-src[^;]*'nonce-([^']+)'/.exec(headers['content-security-policy'])?.[1];
        assert.ok(nonce && !nonces.has(nonce)); nonces.add(nonce);
        assert.equal(headers['content-security-policy'], rendererPolicy(nonce));
        const documentContract = await frame.evaluate(() => ({module: document.querySelector('script[type="module"]').nonce,
          style: document.querySelector('#korlix-sdk-style-nonce').nonce, stylesheet: document.querySelector('link[rel="stylesheet"]').nonce,
          channel: document.querySelector('meta[name="korlix-map-channel"]').content}));
        assert.deepEqual(documentContract, {module: nonce, style: nonce, stylesheet: nonce, channel: 'quarterly'});
        const capabilities = await frame.evaluate(() => {
          const policy = document.permissionsPolicy || document.featurePolicy;
          return Object.fromEntries(['camera', 'microphone', 'geolocation'].map(name => [name, policy.allowsFeature(name)]));
        });
        assert.deepEqual(capabilities, {camera: false, microphone: false, geolocation: false});
        await page.waitForFunction(() => window.__projectionContractObserver.messages.some(value => value.type === 'korlix-projection-transport-ready'));
        if (['unverified', 'legacy-only', 'loader-error', 'auth-failure'].includes(mode)) {
          await waitView('error', undefined, 0);
        } else {
          // Omit viewMode deliberately: older native clients also get Street View.
          await command('flyTo', {}, place);
          if (mode === 'delayed-lookup-close') {
            await frame.waitForFunction(() => window.__projectionProviderFixture.queries.length === 1);
            await frame.evaluate(() => { window.dispatchEvent(new PageTransitionEvent('pagehide')); window.__projectionProviderFixture.release(); });
            await frames(); assert.equal((await snapshot()).panoramas, 0); assert.equal((await snapshot()).maps, 0);
          } else if (mode !== 'ready') {
            await waitView('error', mode === 'no-coverage' ? 'no-coverage' : 'unavailable');
            const actual = await snapshot(); assert.equal(actual.maps, 0);
            if (mode === 'no-coverage') { assert.equal(actual.queries.length, 2); assert.equal(actual.panoramas, 0); }
            if (mode === 'never-status') {
              result.elapsedToDeadlineMs = Date.now() - started;
              assert.ok(result.elapsedToDeadlineMs >= 29000 && result.elapsedToDeadlineMs < 40000);
            }
          } else {
            await waitView('ready', 'ready');
            const first = await snapshot();
            assert.deepEqual(first.imports, ['streetView']); assert.equal(first.maps, 0); assert.equal(first.panoramas, 1);
            assert.equal(first.panorama.pov.heading, 0); assert.equal(first.panorama.pov.pitch, 0);
            assert.equal(first.panorama.options.imageDateControl, true); assert.equal(first.panorama.options.motionTracking, false);
            assert.match(await frame.locator('#imagery-label').innerText(), /Recorded Street View.*2026-06.*Not live/);
            await command('closer'); await frame.waitForFunction(() => window.__projectionProviderFixture.publicState().panorama.zoom > 1);
            await command('zoomInContinuous'); await frame.waitForFunction(() => window.__projectionProviderFixture.publicState().panorama.zoom > 1.6);
            await command('stopCamera'); await waitCamera('stopped', 'stopped');
            const stopped = (await snapshot()).panorama.zoom; await frames(); assert.equal((await snapshot()).panorama.zoom, stopped);
            await command('zoomOutContinuous'); await frame.waitForFunction(value => window.__projectionProviderFixture.publicState().panorama.zoom < value, stopped);
            await frame.locator('.projection-view:not([hidden])').dispatchEvent('pointerdown'); await waitCamera('stopped', 'interrupted');
            await command('zoomInContinuous'); await waitCamera('limit', 'closest'); assert.equal((await snapshot()).panorama.zoom, 3);
            await command('flyTo', {viewMode: 'earth'}, place); await waitView('ready', 'ready');
            const earth = await snapshot(); assert.equal(earth.maps, 1); assert.equal(earth.panorama.visible, false);
            assert.deepEqual(earth.earth.center, {lat: place.latitude, lng: place.longitude, altitude: 0});
            await command('zoomInContinuous', {viewMode: 'earth'});
            await frame.waitForFunction(value => window.__projectionProviderFixture.publicState().earth.range < value, earth.earth.range);
            await command('stopCamera', {viewMode: 'earth'}); await waitCamera('stopped', 'stopped');
            await command('flyTo', {viewMode: 'street'}, place); await waitView('ready', 'ready');
            const returned = await snapshot(); assert.equal(returned.panoramas, 1); assert.equal(returned.maps, 1);
            for (const [width, height] of [[1280, 800], [360, 740]]) {
              await page.setViewportSize({width, height}); await frames();
              const geometry = await frame.evaluate(() => {
                const rect = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return {x: r.x, y: r.y, width: r.width, height: r.height, right: r.right, bottom: r.bottom}; };
                return {viewport: {width: innerWidth, height: innerHeight}, map: rect('#map'), host: rect('.projection-view:not([hidden])'), label: rect('#imagery-label'), stateHidden: document.querySelector('#map-state').hidden};
              });
              assert.ok(geometry.stateHidden && geometry.host.width > 0 && geometry.host.height >= 200);
              assert.ok(geometry.label.bottom <= geometry.host.y + 1, 'App labels must not cover provider attribution or controls.');
              assert.ok(geometry.host.right <= geometry.viewport.width + 1 && geometry.host.bottom <= geometry.viewport.height + 1);
              result.geometry.push(geometry); await page.screenshot({path: resolve(artifactDirectory, `fixture-street-${width}.png`)});
            }
            result.voiceCameraAdapter = {continuousZoom: true, stopWithoutDrift: true, touchInterrupt: true, providerClamp: true, explicitEarth: true, panoramaReuse: true};
            await frame.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
            await frames(); assert.equal((await snapshot()).panorama.visible, false); assert.equal((await snapshot()).earth.connected, false);
          }
        }
        result.messages = await page.evaluate(() => window.__projectionContractObserver.messages);
        assert.doesNotMatch(JSON.stringify(result.messages), /not-a-real-credential|private-provider-fixture-details|maps\.googleapis\.com/);
        assert.ok(result.messages.every(message => {
          if (message.type === 'korlix-projection-transport-ready') return Object.keys(message).length === 1;
          if (message.type === 'korlix-projection-status') return ['loading', 'ready', 'error'].includes(message.status) && ['street', 'earth'].includes(message.viewMode) &&
            Object.keys(message).every(key => ['type', 'status', 'viewMode', 'reason', 'message', 'sequence'].includes(key));
          return message.type === 'korlix-projection-camera-status' && ['street', 'earth'].includes(message.viewMode) &&
            Object.keys(message).sort().join(',') === 'reason,sequence,state,type,viewMode';
        }));
        result.cspViolations = await frame.evaluate(() => window.__projectionContractObserver.violations);
        assert.deepEqual(result.cspViolations, []); assert.deepEqual(result.unexpectedRequests, []); assert.deepEqual(result.pageErrors, []);
        const unexpected = result.consoleErrors.filter(message => !expectedPermissionDiagnostics.has(message));
        assert.ok(unexpected.every(message => mode === 'loader-error' && /Failed to load resource.*503/.test(message)), JSON.stringify(unexpected));
        assert.equal(result.loaderRequests.length, ['unverified', 'legacy-only'].includes(mode) ? 0 : 1);
        const bootstrap = await frame.evaluate(() => window.__projectionProviderFixture?.bootstrap);
        if (bootstrap) assert.deepEqual(bootstrap, {authCallbackInstalled: true, callbackInstalled: true, loaderNonce: nonce, moduleNonce: nonce, loaderReferrerPolicy: 'strict-origin-when-cross-origin'});
        result.passed = true; console.log(`PASS recorded-imagery fixture: ${mode}; liveProviderVerified=false; external forwards=0`);
      } catch (error) {
        result.error = error.stack || error.message;
        result.messages = await page.evaluate(() => window.__projectionContractObserver?.messages).catch(() => []);
        await page.screenshot({path: resolve(artifactDirectory, `fixture-${mode}-failure.png`)}).catch(() => {});
        throw error;
      } finally { await context.close(); }
    }
    report.passed = true;
  } finally {
    await writeFile(resolve(artifactDirectory, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    await browser?.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  }
}
if (process.argv.length === 3 && process.argv[2] === '--fixture-only') {
  console.log('PASS Street View/Earth and CSP fixture syntax only; no browser or real provider requests.');
} else if (process.argv.length === 2) await main();
else throw Error('Only --fixture-only is supported for offline validation.');
