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
const modes = ['ready', 'map-error', 'auth-failure', 'import-error', 'loader-error',
  'delayed-import-close', 'never-steady', 'unverified', 'legacy-only'];

// Deliberately self-contained so its source can be delivered at the intercepted
// loader URL. The closed shadow tree belongs to this synthetic test fixture;
// the test/renderer only observe public element geometry, events and methods.
function installMaps3dContractFixture(mode) {
  const copy = value => JSON.parse(JSON.stringify(value));
  const fixture = window.__maps3dContractFixture = {
    kind: 'synthetic-maps3d-contract-fixture', liveProviderVerified: false,
    imports: [], constructors: [], flights: [], stops: 0, connected: 0, disconnected: 0,
    bootstrap: {
      authCallbackInstalled: typeof window.gm_authFailure === 'function',
      callbackInstalled: typeof window.__korlixMapsReady === 'function',
      loaderNonce: document.currentScript?.nonce,
      moduleNonce: document.querySelector('script[type="module"][nonce]')?.nonce,
      loaderReferrerPolicy: document.currentScript?.referrerPolicy,
    },
  };
  let currentMap = null, releaseImport = null;
  class Map3DElement extends HTMLElement {
    constructor(options) {
      super();
      fixture.constructors.push(copy(options));
      Object.assign(this, copy(options));
      currentMap = this;
      const shadow = this.attachShadow({mode: 'closed'});
      const style = document.createElement('style');
      style.nonce = document.querySelector('style[nonce]')?.nonce || '';
      style.textContent = ':host{display:block;background:#092535;color:#d5f7ff;font:14px system-ui}' +
        '.fixture{box-sizing:border-box;height:100%;display:flex;flex-direction:column;justify-content:center;text-align:center;padding:24px;' +
        'background:linear-gradient(140deg,#123746,#061926)}h1{font-size:22px;margin:0 0 14px}p{line-height:1.6;margin:8px 0}' +
        '.disclaimer{margin-top:auto;border-top:1px solid #6694a4;padding-top:14px;font-size:12px}' +
        '.space{flex:1;min-height:0}.badge{color:#f7cd7c;font-weight:700;letter-spacing:.06em}';
      const panel = document.createElement('section');
      panel.className = 'fixture';
      panel.innerHTML = '<div class="space"></div><p class="badge">AUTOMATED CONTRACT FIXTURE</p>' +
        '<h1>maps3d API integration</h1><p>No Google SDK or geographic imagery is loaded.<br>Camera events and methods are simulated.</p>' +
        '<div class="space"></div><p class="disclaimer">Fixture footer only. Real Google attribution, links and rendering require live verification.</p>';
      shadow.append(style, panel);
    }
    connectedCallback() { fixture.connected++; }
    disconnectedCallback() { fixture.disconnected++; }
    stopCameraAnimation() { fixture.stops++; }
    flyCameraTo(options) {
      fixture.flights.push(copy(options));
      Object.assign(this, copy(options.endCamera));
      this.dispatchEvent(new Event('gmp-animationend'));
    }
  }
  customElements.define('gmp-map-3d', Map3DElement);
  const library = {Map3DElement};
  fixture.emitSteady = isSteady => {
    const event = new Event('gmp-steadychange');
    Object.defineProperty(event, 'isSteady', {value: isSteady});
    currentMap?.dispatchEvent(event);
  };
  fixture.emitMapError = () => currentMap?.dispatchEvent(new Event('gmp-error'));
  fixture.releaseImport = () => releaseImport?.(library);
  fixture.publicState = () => currentMap ? {connected: currentMap.isConnected,
    center: copy(currentMap.center), range: currentMap.range, heading: currentMap.heading, tilt: currentMap.tilt} : null;
  window.google = {maps: {importLibrary(name) {
    fixture.imports.push(name);
    if (name !== 'maps3d') return Promise.reject(new Error('Unexpected fixture library.'));
    if (mode === 'import-error') return Promise.reject(new Error('private-provider-fixture-details'));
    if (mode === 'delayed-import-close') return new Promise(resolveLibrary => { releaseImport = resolveLibrary; });
    return Promise.resolve(library);
  }}};
  const ready = window.__korlixMapsReady;
  if (mode === 'auth-failure') window.gm_authFailure();
  // The captured callback also exercises cancellation of a late loader response.
  ready();
}

const sdkFixture = mode => `(${installMaps3dContractFixture.toString()})(${JSON.stringify(mode)});`;
for (const mode of modes) new Script(sdkFixture(mode), {filename: `maps3d-${mode}-fixture.js`});

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
  assert.equal(require('playwright/package.json').version, '1.56.1', 'Use the CI-pinned Playwright version.');
  const artifactDirectory = resolve(process.env.PROJECTION_RENDERER_ARTIFACTS || 'projection-renderer-artifacts');
  await mkdir(artifactDirectory, {recursive: true});
  const report = {validationKind: 'maps3d-contract-fixture', sdkSource: 'synthetic',
    liveProviderVerified: false, providerNetworkRequests: 0, channel: MAPS_JS_CHANNEL, scenarios: [],
    limits: ['No real Google SDK, imagery, WebGL rendering or provider credential validation.',
      'No live website/API restriction or billing validation.',
      'No real SDK attribution/link layout or iOS/Android WebView/voice verification.',
      'Production local routes, nonce CSP, lifecycle and public camera adapter run unchanged against labeled fixtures.']};
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
    async function scenario(mode) {
      for (const name of Object.keys(environment)) delete environment[name];
      Object.assign(environment, {BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY: browserKey,
        BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED: 'true', KORLIX_PUBLIC_BACKEND_URL: 'https://korlix.com'});
      if (mode === 'unverified') environment.BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED = 'false';
      if (mode === 'legacy-only') {
        delete environment.BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY;
        delete environment.BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED;
        environment.BRAIN_PROJECTION_MAP_BROWSER_KEY = browserKey;
        environment.BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED = 'true';
      }
      const result = {mode, fixture: true, liveProviderVerified: false,
        loaderRequests: [], routeErrors: [], unexpectedRequests: [], pageErrors: [], consoleErrors: [], geometry: []};
      report.scenarios.push(result);
      const context = await browser.newContext({viewport: {width: 1280, height: 800}, serviceWorkers: 'block'});
      await context.addInitScript(() => {
        window.__projectionContractObserver = {violations: [], messages: []};
        window.addEventListener('securitypolicyviolation', event => {
          window.__projectionContractObserver.violations.push({directive: event.effectiveDirective, blockedURI: event.blockedURI});
        });
        window.addEventListener('message', event => {
          const frame = document.querySelector('iframe');
          if (window === window.top && event.source === frame?.contentWindow && event.origin === window.location.origin) {
            window.__projectionContractObserver.messages.push(event.data);
          }
        });
      });
      await context.routeWebSocket('**/*', socket => {
        result.unexpectedRequests.push({kind: 'websocket'});
        socket.close();
      });
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.origin === origin) return route.continue();
        if (url.origin === scriptOrigin && url.pathname === scriptPath) {
          try {
            assert.equal(url.searchParams.get('key'), browserKey);
            assert.deepEqual(Object.fromEntries([...url.searchParams].filter(([name]) => name !== 'key')), {
              v: 'quarterly', loading: 'async', callback: '__korlixMapsReady', auth_referrer_policy: 'origin',
            });
            assert.equal([...url.searchParams].length, 5);
          } catch (error) {
            result.routeErrors.push(error.message);
            return route.abort('blockedbyclient');
          }
          result.loaderRequests.push({path: scriptPath, channel: url.searchParams.get('v'), intercepted: true});
          return route.fulfill({status: mode === 'loader-error' ? 503 : 200, contentType: 'application/javascript',
            body: mode === 'loader-error' ? '' : sdkFixture(mode)});
        }
        result.unexpectedRequests.push({kind: 'blocked', origin: url.origin, path: url.pathname});
        return route.abort('blockedbyclient');
      });
      const page = await context.newPage();
      page.on('pageerror', error => result.pageErrors.push(error.message));
      page.on('console', message => {if (message.type() === 'error') result.consoleErrors.push(message.text());});
      page.setDefaultTimeout(40000);
      let frame, documentResponse, sequence = 0;
      page.on('response', response => {
        if (response.url() === `${origin}/brain-projection/earth.html`) documentResponse = response;
      });
      const statuses = () => page.evaluate(() => window.__projectionContractObserver.messages
        .filter(message => message.type === 'korlix-projection-status').map(message => message.status));
      const waitStatus = status => page.waitForFunction(expected => window.__projectionContractObserver.messages
        .some(message => message.type === 'korlix-projection-status' && message.status === expected), status);
      const waitCameraStatus = (state, reason, cameraSequence = sequence) => page.waitForFunction(expected =>
        window.__projectionContractObserver.messages.some(message => message.type === 'korlix-projection-camera-status' &&
          message.state === expected.state && message.reason === expected.reason && message.sequence === expected.sequence),
      {state, reason, sequence: cameraSequence});
      const command = (operation, camera = {}, selected = undefined) => page.evaluate(value => {
        document.querySelector('iframe').contentWindow.postMessage(value, window.location.origin);
      }, {type: 'korlix-projection-camera', camera: {operation, sequence: ++sequence, ...camera}, ...(selected ? {place: selected} : {})});
      const snapshot = () => frame.evaluate(() => {
        const fixture = window.__maps3dContractFixture;
        return fixture ? {imports: fixture.imports, constructors: fixture.constructors, flights: fixture.flights,
          stops: fixture.stops, connected: fixture.connected, disconnected: fixture.disconnected,
          bootstrap: fixture.bootstrap, camera: fixture.publicState()} : null;
      });
      try {
        const started = Date.now();
        await page.goto(`${origin}/__projection_ci/host.html`, {waitUntil: 'load'});
        frame = page.frames().find(candidate => candidate.url() === `${origin}/brain-projection/earth.html`);
        assert.ok(frame && documentResponse, 'The actual renderer route must load.');
        const headers = await documentResponse.allHeaders();
        assert.equal(headers['cache-control'], 'no-store');
        assert.equal(headers['referrer-policy'], 'strict-origin-when-cross-origin');
        assert.match(headers['permissions-policy'], /camera=\(\), microphone=\(\)/);
        const policy = headers['content-security-policy'];
        const nonce = /script-src[^;]*'nonce-([^']+)'/.exec(policy)?.[1];
        assert.ok(nonce && nonce.length >= 24);
        assert.equal(nonces.has(nonce), false, 'Each document response needs a fresh nonce.');
        nonces.add(nonce);
        assert.match(policy, /'strict-dynamic'/);
        assert.doesNotMatch(policy.split(';').find(directive => directive.trim().startsWith('script-src')), /'unsafe-inline'/);
        const documentContract = await frame.evaluate(() => ({
          scriptNonce: document.querySelector('script[type="module"]')?.nonce,
          styleNonce: document.querySelector('#korlix-sdk-style-nonce')?.nonce,
          stylesheetNonce: document.querySelector('link[rel="stylesheet"]')?.nonce,
          channel: document.querySelector('meta[name="korlix-map-channel"]')?.content,
          keyPresent: Boolean(document.querySelector('meta[name="korlix-map-key"]')?.content),
        }));
        assert.deepEqual(documentContract, {scriptNonce: nonce, styleNonce: nonce, stylesheetNonce: nonce,
          channel: 'quarterly', keyPresent: !['unverified', 'legacy-only'].includes(mode)});
        result.deniedCapabilities = await frame.evaluate(() => {
          const policy = document.permissionsPolicy || document.featurePolicy;
          return Object.fromEntries(['camera', 'geolocation', 'microphone'].map(capability =>
            [capability, policy?.allowsFeature(capability) === false]));
        });
        assert.deepEqual(result.deniedCapabilities, {camera: true, geolocation: true, microphone: true},
          'The iframe must actually deny camera, microphone and geolocation.');
        result.productionNonceCsp = true;
        await waitStatus('loading');

        if (['unverified', 'legacy-only', 'loader-error', 'auth-failure', 'import-error'].includes(mode)) {
          await waitStatus('error');
        } else {
          await frame.waitForFunction(() => window.__maps3dContractFixture?.imports.length === 1);
          if (mode === 'delayed-import-close') {
            assert.equal((await snapshot()).constructors.length, 0);
            await frame.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
            await frame.evaluate(async () => {window.__maps3dContractFixture.releaseImport(); await Promise.resolve(); await Promise.resolve();});
            assert.equal((await snapshot()).constructors.length, 0, 'Late import resolution must not create a map after close.');
            assert.deepEqual(await statuses(), ['loading']);
          } else {
            await frame.waitForFunction(() => document.querySelector('gmp-map-3d')?.isConnected);
            const beforeSteady = await snapshot();
            assert.equal(beforeSteady.constructors.length, 1);
            assert.equal(beforeSteady.constructors[0].mode, 'SATELLITE');
            assert.equal(beforeSteady.constructors[0].defaultUIHidden, true);
            await frame.evaluate(() => window.__maps3dContractFixture.emitSteady(false));
            assert.deepEqual(await statuses(), ['loading'], 'Library and false steady events must not report readiness.');
            if (mode === 'map-error') {
              await frame.evaluate(() => window.__maps3dContractFixture.emitMapError());
              await waitStatus('error');
              await frame.evaluate(() => window.__maps3dContractFixture.emitSteady(true));
            } else if (mode === 'never-steady') {
              await waitStatus('error');
              result.elapsedToDeadlineMs = Date.now() - started;
              assert.ok(result.elapsedToDeadlineMs >= 29000 && result.elapsedToDeadlineMs < 40000,
                'The combined production loading deadline must fire around 30 seconds.');
            } else {
              await command('flyTo', {height: 850}, place);
              await frame.evaluate(() => new Promise(resolveFrame => requestAnimationFrame(resolveFrame)));
              assert.equal((await snapshot()).flights.length, 0, 'Camera commands wait for a steady scene.');
              await frame.evaluate(() => window.__maps3dContractFixture.emitSteady(true));
              await waitStatus('ready');
              await frame.waitForFunction(() => window.__maps3dContractFixture.flights.length === 1);
              const first = (await snapshot()).flights[0].endCamera;
              assert.deepEqual(first.center, {lat: place.latitude, lng: place.longitude, altitude: 0});
              assert.equal(first.altitudeMode, 'RELATIVE_TO_GROUND');
              assert.ok(Number.isFinite(first.range) && first.range > 850);
              assert.equal(first.tilt, 40);
              const expected = {closer: value => value.range < first.range,
                farther: value => value.range > first.range * .65, left: value => value.heading === 342,
                right: value => value.heading === 0, reset: value => value.center.lat === place.latitude && value.center.lng === place.longitude};
              for (const operation of ['closer', 'farther', 'left', 'right', 'reset']) {
                const count = (await snapshot()).flights.length;
                await command(operation);
                await frame.waitForFunction(previous => window.__maps3dContractFixture.flights.length > previous, count);
                assert.ok(expected[operation]((await snapshot()).flights.at(-1).endCamera), `${operation} must use the public camera API.`);
              }
              result.cameraContract = (await snapshot()).flights;
              const waitFrames = () => frame.evaluate(async () => {
                for (let index = 0; index < 5; index++) await new Promise(resolveFrame => requestAnimationFrame(resolveFrame));
              });
              const beforeZoom = (await snapshot()).camera;
              await command('zoomInContinuous');
              await frame.waitForFunction(previous => window.__maps3dContractFixture.publicState().range < previous * .95, beforeZoom.range);
              await command('stopCamera');
              await waitCameraStatus('stopped', 'stopped');
              const afterZoom = (await snapshot()).camera;
              await waitFrames();
              assert.equal((await snapshot()).camera.range, afterZoom.range, 'Stop must cancel the continuous rAF loop.');
              assert.deepEqual(afterZoom.center, beforeZoom.center);
              assert.equal(afterZoom.heading, beforeZoom.heading);
              assert.equal(afterZoom.tilt, beforeZoom.tilt);
              assert.equal((await snapshot()).flights.length, result.cameraContract.length,
                'Continuous zoom must update public range without queuing SDK fly animations.');
              await command('zoomOutContinuous');
              await frame.waitForFunction(previous => window.__maps3dContractFixture.publicState().range > previous * 1.05, afterZoom.range);
              await frame.evaluate(() => document.querySelector('gmp-map-3d').dispatchEvent(new PointerEvent('pointerdown', {bubbles: true})));
              await waitCameraStatus('stopped', 'interrupted');
              const afterPointer = (await snapshot()).camera.range;
              await waitFrames();
              assert.equal((await snapshot()).camera.range, afterPointer, 'A user gesture takes over from voice zoom.');
              await frame.evaluate(() => Object.assign(document.querySelector('gmp-map-3d'), {range: 1, tilt: 0}));
              await command('zoomInContinuous');
              await waitCameraStatus('limit', 'closest');
              assert.equal((await snapshot()).camera.range, 1);
              result.continuousCameraContract = {rangeMovedIn: afterZoom.range < beforeZoom.range,
                rangeMovedOut: afterPointer > afterZoom.range, stoppedWithoutDrift: true,
                pointerInterrupted: true, closestBoundReported: true, statusSequenceChecked: true};
              await command('reset');
              await frame.waitForFunction(() => window.__maps3dContractFixture.publicState().range > 1);
              for (const [width, height] of [[1280, 800], [360, 740]]) {
                await page.setViewportSize({width, height});
                await frame.evaluate(() => new Promise(resolveFrame => requestAnimationFrame(resolveFrame)));
                const geometry = await frame.evaluate(() => {
                  const rect = selector => {
                    const bounds = document.querySelector(selector).getBoundingClientRect();
                    return {x: bounds.x, y: bounds.y, right: bounds.right, bottom: bounds.bottom, width: bounds.width, height: bounds.height};
                  };
                  const host = document.querySelector('gmp-map-3d');
                  return {viewport: {width: innerWidth, height: innerHeight}, map: rect('#map'), host: rect('gmp-map-3d'),
                    label: rect('#imagery-label'), stateHidden: document.querySelector('#map-state').hidden,
                    hostShadowOpaque: host.shadowRoot === null};
                });
                assert.ok(geometry.hostShadowOpaque, 'The adapter must work without inspecting provider internals.');
                assert.ok(geometry.stateHidden && geometry.host.width > 0 && geometry.host.height > 0);
                assert.ok(geometry.label.bottom <= geometry.host.y + 1, 'Our imagery label must remain outside the entire SDK viewport.');
                assert.ok(geometry.host.x >= 0 && geometry.host.y >= 0 &&
                  geometry.host.right <= geometry.viewport.width + 1 && geometry.host.bottom <= geometry.viewport.height + 1);
                assert.ok(Math.abs(geometry.host.width - geometry.map.width) <= 1 && Math.abs(geometry.host.height - geometry.map.height) <= 1);
                result.geometry.push(geometry);
                await page.screenshot({path: resolve(artifactDirectory, `fixture-ready-${width}.png`)});
              }
              const flights = (await snapshot()).flights.length;
              const beforeClose = (await snapshot()).camera.range;
              await command('zoomOutContinuous');
              await frame.waitForFunction(previous => window.__maps3dContractFixture.publicState().range > previous, beforeClose);
              await frame.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
              assert.equal((await snapshot()).disconnected, 1);
              const closedRange = (await snapshot()).camera.range;
              await waitFrames();
              assert.equal((await snapshot()).camera.range, closedRange, 'Closing the frame cancels continuous work.');
              await command('closer');
              await frame.evaluate(() => window.__maps3dContractFixture.emitSteady(true));
              assert.equal((await snapshot()).flights.length, flights);
              assert.deepEqual(await statuses(), ['loading', 'ready']);
            }
          }
        }

        const final = await snapshot();
        if (final) {
          assert.deepEqual(final.bootstrap, {authCallbackInstalled: true, callbackInstalled: true,
            loaderNonce: nonce, moduleNonce: nonce, loaderReferrerPolicy: 'strict-origin-when-cross-origin'});
        }
        if (!['ready', 'delayed-import-close'].includes(mode)) {
          assert.deepEqual(await statuses(), ['loading', 'error']);
          assert.equal(await frame.locator('gmp-map-3d').count(), 0);
          assert.equal(await frame.locator('#map-state').isVisible(), true);
          assert.match(await frame.locator('#map-state').innerText(), /could not load|not connected yet/);
          if (mode === 'map-error') await page.screenshot({path: resolve(artifactDirectory, 'fixture-sanitized-error.png')});
        }
        assert.equal(result.loaderRequests.length, ['unverified', 'legacy-only'].includes(mode) ? 0 : 1);
        result.messages = await page.evaluate(() => window.__projectionContractObserver.messages);
        assert.doesNotMatch(JSON.stringify(result.messages), /not-a-real-credential|private-provider-fixture-details|maps\.googleapis\.com/);
        assert.ok(result.messages.every(message => {
          if (message.type === 'korlix-projection-status') return ['loading', 'ready', 'error'].includes(message.status) &&
            Object.keys(message).every(key => ['type', 'status', 'message'].includes(key));
          if (message.type !== 'korlix-projection-camera-status') return false;
          return Object.keys(message).sort().join(',') === 'reason,sequence,state,type' &&
            Number.isSafeInteger(message.sequence) && message.sequence >= 0 &&
            ((message.state === 'stopped' && ['stopped', 'interrupted'].includes(message.reason)) ||
             (message.state === 'limit' && ['closest', 'farthest'].includes(message.reason)));
        }), 'Only allowlisted public map/camera statuses cross the frame boundary.');
        result.cspViolations = await frame.evaluate(() => window.__projectionContractObserver.violations);
        assert.deepEqual(result.cspViolations, [], 'Production nonce CSP must permit the adapter and nonced fixture without violations.');
        assert.deepEqual(result.pageErrors, []);
        assert.deepEqual(result.routeErrors, [], 'The production loader must use the reviewed URL and parameters.');
        assert.deepEqual(result.unexpectedRequests, [], 'No unexpected external destinations may be required.');
        result.permissionPolicyDiagnostics = result.consoleErrors.filter(message => expectedPermissionDiagnostics.has(message));
        const otherConsoleErrors = result.consoleErrors.filter(message => !expectedPermissionDiagnostics.has(message));
        assert.ok(otherConsoleErrors.every(message => mode === 'loader-error' && /Failed to load resource.*503/.test(message)),
          `Unexpected browser console errors: ${JSON.stringify(result.consoleErrors)}`);
        result.statuses = await statuses();
        result.fixtureCalls = final;
        result.passed = true;
        console.log(`PASS maps3d contract fixture: ${mode}; liveProviderVerified=false; forwarded external requests=0`);
      } catch (error) {
        result.error = error.stack || error.message;
        result.messages = await page.evaluate(() => window.__projectionContractObserver?.messages).catch(() => []);
        result.cspViolations = frame ? await frame.evaluate(() => window.__projectionContractObserver?.violations).catch(() => []) : [];
        result.fixtureCalls = frame ? await snapshot().catch(() => null) : null;
        await page.screenshot({path: resolve(artifactDirectory, `fixture-${mode}-failure.png`)}).catch(() => {});
        throw error;
      } finally { await context.close(); }
    }
    for (const mode of modes) await scenario(mode);
    report.passed = true;
  } finally {
    await writeFile(resolve(artifactDirectory, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    await browser?.close();
    server.closeAllConnections();
    await new Promise(resolveClosed => server.close(resolveClosed));
  }
}

if (process.argv.length === 3 && process.argv[2] === '--fixture-only') {
  console.log('PASS maps3d and CSP fixture syntax only; no browser, real SDK or provider requests; liveProviderVerified=false.');
} else if (process.argv.length === 2) {
  await main();
} else {
  throw new Error('Only --fixture-only is supported for offline validation.');
}
