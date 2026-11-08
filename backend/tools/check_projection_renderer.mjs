import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import express from 'express';
import {registerProjectionRenderer, CESIUM_VERSION, CESIUM_ROOT,
  CESIUM_JS_INTEGRITY, CESIUM_CSS_INTEGRITY} from '../brain_projection/renderer.mjs';

// Run in CI with Playwright installed in a separate temporary directory. This
// loads the unmodified official SDK through the real renderer routes and CSP.
// Google/Ion requests NEVER leave the browser: synthetic tiles and a labelled
// credit-logo fixture are fulfilled locally; all other upstreams fail closed.
// This checks Chromium bootstrap/rendering, not Google keys, coverage, imagery,
// provider referrer enforcement, native WebViews, or the native voice session.
const attribution = 'KORLIX synthetic CI building geometry — deterministic fixture, not geographic imagery';
const place = {id: 'ci-synthetic-building', label: 'Synthetic CI building', latitude: 40.7, longitude: -73.9};
const browserKey = 'korlix-browser-ci-fake-key-not-a-credential';
const jsUrl = `${CESIUM_ROOT}Cesium.js`;
const cssUrl = `${CESIUM_ROOT}Widgets/widgets.css`;
const sha384 = body => `sha384-${createHash('sha384').update(body).digest('base64')}`;

function tileFixture() {
  // Uncompressed, unlit glTF cube in a local east/north/up frame. Its asset
  // copyright exercises Cesium's actual per-tile on-screen attribution path.
  const positions = [-100, 0, -100, 100, 0, -100, 100, 0, 100, -100, 0, 100,
    -100, 150, -100, 100, 150, -100, 100, 150, 100, -100, 150, 100];
  const indices = [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1,
    1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0];
  const binary = Buffer.alloc(positions.length * 4 + indices.length * 2);
  positions.forEach((value, index) => binary.writeFloatLE(value, index * 4));
  indices.forEach((value, index) => binary.writeUInt16LE(value, positions.length * 4 + index * 2));
  const gltf = {
    asset: {version: '2.0', generator: 'KORLIX deterministic renderer CI', copyright: attribution},
    scene: 0, scenes: [{nodes: [0]}], nodes: [{mesh: 0}],
    meshes: [{primitives: [{attributes: {POSITION: 0}, indices: 1, material: 0}]}],
    materials: [{doubleSided: true, pbrMetallicRoughness: {baseColorFactor: [0.05, 0.85, 0.7, 1],
      metallicFactor: 0, roughnessFactor: 1}, extensions: {KHR_materials_unlit: {}}}],
    extensionsUsed: ['KHR_materials_unlit'], buffers: [{byteLength: binary.length}],
    bufferViews: [{buffer: 0, byteOffset: 0, byteLength: positions.length * 4, target: 34962},
      {buffer: 0, byteOffset: positions.length * 4, byteLength: indices.length * 2, target: 34963}],
    accessors: [{bufferView: 0, componentType: 5126, count: positions.length / 3, type: 'VEC3',
      min: [-100, 0, -100], max: [100, 150, 100]},
    {bufferView: 1, componentType: 5123, count: indices.length, type: 'SCALAR', min: [0], max: [7]}],
  };
  const json = Buffer.from(JSON.stringify(gltf));
  const jsonChunk = Buffer.alloc(Math.ceil(json.length / 4) * 4, 0x20);
  json.copy(jsonChunk);
  const glb = Buffer.alloc(12 + 8 + jsonChunk.length + 8 + binary.length);
  glb.write('glTF'); glb.writeUInt32LE(2, 4); glb.writeUInt32LE(glb.length, 8);
  glb.writeUInt32LE(jsonChunk.length, 12); glb.write('JSON', 16); jsonChunk.copy(glb, 20);
  const binaryHeader = 20 + jsonChunk.length;
  glb.writeUInt32LE(binary.length, binaryHeader); glb.writeUInt32LE(0x004e4942, binaryHeader + 4);
  binary.copy(glb, binaryHeader + 8);

  const latitude = place.latitude * Math.PI / 180, longitude = place.longitude * Math.PI / 180;
  const sinLat = Math.sin(latitude), cosLat = Math.cos(latitude);
  const sinLon = Math.sin(longitude), cosLon = Math.cos(longitude);
  const eccentricitySquared = 6.6943799901413165e-3;
  const normal = 6378137 / Math.sqrt(1 - eccentricitySquared * sinLat ** 2);
  const transform = [-sinLon, cosLon, 0, 0, -sinLat * cosLon, -sinLat * sinLon, cosLat, 0,
    cosLat * cosLon, cosLat * sinLon, sinLat, 0,
    normal * cosLat * cosLon, normal * cosLat * sinLon, normal * (1 - eccentricitySquared) * sinLat, 1];
  // Tileset-level error describes the error without loading its root. Cesium
  // intentionally skips the entire tileset when this is zero; only the exact
  // leaf geometry below has zero error. A positive coarse error lets the real
  // traversal request this building when the camera arrives over the fixture.
  const tileset = {asset: {version: '1.1', gltfUpAxis: 'Y'}, geometricError: 2000,
    root: {boundingVolume: {sphere: [0, 0, 75, 200]}, transform, geometricError: 0,
      refine: 'ADD', content: {uri: 'fixture.glb'}}};
  return {glb, tileset};
}

const fixture = tileFixture();
// Validate binary framing without starting a browser (also usable in restricted
// local environments with: node tools/check_projection_renderer.mjs --fixture-only).
assert.equal(fixture.glb.readUInt32LE(8), fixture.glb.length);
const fixtureJsonLength = fixture.glb.readUInt32LE(12);
const fixtureJson = JSON.parse(fixture.glb.subarray(20, 20 + fixtureJsonLength).toString());
assert.equal(fixtureJson.asset.version, '2.0');
assert.equal(fixtureJson.buffers[0].byteLength, fixture.glb.readUInt32LE(20 + fixtureJsonLength));
assert.equal(fixture.tileset.root.transform.length, 16);
assert.ok(fixture.tileset.root.transform.every(Number.isFinite));

async function main() {
  const require = createRequire(process.env.KORLIX_PROJECTION_BROWSER_DEPS
    ? resolve(process.env.KORLIX_PROJECTION_BROWSER_DEPS, 'package.json') : import.meta.url);
  const {chromium} = require('playwright');
  assert.equal(require('playwright/package.json').version, '1.56.1', 'Use the CI-pinned Playwright version.');
  const artifactDirectory = resolve(process.env.PROJECTION_RENDERER_ARTIFACTS || 'projection-renderer-artifacts');
  await mkdir(artifactDirectory, {recursive: true});
  const report = {cesiumVersion: CESIUM_VERSION, providerNetworkRequests: 0, officialAssets: [], scenarios: [],
    limits: 'Real Cesium/Chromium, synthetic 3D Tiles and logo. No Google credentials, coverage, referrer-policy enforcement, native device or voice validation.'};
  const app = express();
  app.disable('x-powered-by');
  registerProjectionRenderer(app, {environment: {
    BRAIN_PROJECTION_MAP_BROWSER_KEY: browserKey,
    BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED: 'true',
    KORLIX_PUBLIC_BACKEND_URL: 'https://chee-chai-chee-backend.onrender.com',
  }});
  // Only the test parent is synthetic. The iframe document, JS, CSS and headers
  // come from the production registerProjectionRenderer implementation above.
  app.get('/__projection_ci/host.html', (_req, res) => res.type('html').send(`<!doctype html>
    <html lang="en"><meta charset="utf-8"><link rel="icon" href="data:,"><title>Projection configured renderer CI</title>
    <style>html,body{margin:0;width:100%;height:100%;background:#030b13}iframe{border:0;width:100%;height:100%}
    #fixture-label{position:absolute;top:0;right:0;z-index:9;font:11px system-ui;color:white;background:#542100;padding:4px;pointer-events:none}</style>
    <div id="fixture-label">CI fixture · synthetic building · provider traffic blocked</div>
    <iframe id="projection" title="Production Projection renderer" src="/brain-projection/earth.html"></iframe></html>`));
  const server = createServer(app);
  await new Promise((resolveListening, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolveListening);
  });
  const origin = `http://127.0.0.1:${server.address().port}`;
  const assetCache = new Map();
  let browser;
  try {
    browser = await chromium.launch({headless: true, args: [
      '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage',
    ]});

    async function scenario(mode) {
      const result = {mode, providerFixtures: [], unexpectedRequests: [], pageErrors: [], consoleErrors: []};
      report.scenarios.push(result);
      const context = await browser.newContext({viewport: {width: 1280, height: 800},
        deviceScaleFactor: 1, serviceWorkers: 'block'});
      // Install before navigation. This observes the genuine Viewer instance
      // after the full SDK has initialized; it does not stub any Cesium API or
      // alter SDK bytes, CSP, provider factory, WebGL, or camera implementation.
      await context.addInitScript(() => {
        const observed = window.__projectionCi = {messages: [], violations: [], visibleTiles: 0};
        document.addEventListener('securitypolicyviolation', event => observed.violations.push({
          directive: event.violatedDirective, blockedURI: event.blockedURI, disposition: event.disposition,
        }));
        window.addEventListener('message', event => {
          if (event.source === document.getElementById('projection')?.contentWindow && event.origin === location.origin) {
            observed.messages.push(event.data);
          }
        });
        window.addEventListener('load', () => {
          const actualSdk = window.Cesium;
          if (!actualSdk?.Viewer) return;
          observed.sdk = actualSdk;
          const viewerConstructor = new Proxy(actualSdk.Viewer, {construct(target, args) {
            observed.viewer = Reflect.construct(target, args, target);
            return observed.viewer;
          }});
          window.Cesium = new Proxy(actualSdk, {get(target, property) {
            return property === 'Viewer' ? viewerConstructor : Reflect.get(target, property);
          }});
        }, {once: true});
      });
      await context.routeWebSocket('**/*', async socket => {
        result.unexpectedRequests.push({kind: 'websocket', url: socket.url()});
        await socket.close();
      });
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.origin === origin) return route.continue();
        if (url.href.startsWith(CESIUM_ROOT) && url.origin === 'https://cesium.com' && !url.search) {
          try {
            if (!assetCache.has(url.href)) assetCache.set(url.href, (async () => {
              // No redirects: an SDK URL cannot become an unreviewed upstream.
              const response = await route.fetch({maxRedirects: 0, maxRetries: 0, timeout: 45000});
              assert.equal(response.status(), 200, `Official Cesium asset failed: ${url.pathname}`);
              const body = await response.body();
              const integrity = sha384(body);
              if (url.href === jsUrl) assert.equal(integrity, CESIUM_JS_INTEGRITY);
              if (url.href === cssUrl) assert.equal(integrity, CESIUM_CSS_INTEGRITY);
              const headers = response.headers();
              // Preserve the real CDN's CORS/CORP headers; fabricating '*' here
              // could hide an official-asset integration regression. Body bytes
              // are already decoded by Playwright, so remove transport headers.
              for (const name of ['content-encoding', 'content-length', 'transfer-encoding', 'connection']) delete headers[name];
              if (url.href === jsUrl || url.href === cssUrl) {
                assert.ok(['*', origin].includes(headers['access-control-allow-origin']), 'Official SRI assets require CDN CORS permission.');
              }
              report.officialAssets.push({url: url.href, integrity, bytes: body.length,
                cors: headers['access-control-allow-origin'] || null});
              return {body, headers};
            })());
            const asset = await assetCache.get(url.href);
            return route.fulfill({status: 200, body: asset.body, headers: asset.headers});
          } catch (error) {
            result.unexpectedRequests.push({kind: 'sdk-fetch-failed', path: url.pathname, error: error.message});
            return route.abort('failed');
          }
        }
        // The real Google factory chooses these URLs. All provider responses,
        // including the denied-key case, are generated here with no network.
        if (url.origin === 'https://tile.googleapis.com' && url.pathname === '/v1/3dtiles/root.json') {
          assert.equal(url.searchParams.get('key'), browserKey);
          result.providerFixtures.push({path: url.pathname, status: mode === 'denied-key' ? 403 : 200});
          return route.fulfill({status: mode === 'denied-key' ? 403 : 200, contentType: 'application/json',
            headers: {'access-control-allow-origin': '*'}, body: JSON.stringify(mode === 'denied-key'
              ? {error: {message: 'CI provider denied fake key; private diagnostic must not reach the parent'}} : fixture.tileset)});
        }
        if (mode === 'ready' && url.origin === 'https://tile.googleapis.com' && url.pathname === '/v1/3dtiles/fixture.glb') {
          result.providerFixtures.push({path: url.pathname, status: 200});
          return route.fulfill({status: 200, contentType: 'model/gltf-binary', body: fixture.glb,
            headers: {'access-control-allow-origin': '*'}});
        }
        if (url.href === 'https://assets.ion.cesium.com/google-credit.png') {
          result.providerFixtures.push({path: url.pathname, status: 200});
          return route.fulfill({status: 200, contentType: 'image/svg+xml',
            body: '<svg xmlns="http://www.w3.org/2000/svg" width="95" height="22"><rect width="95" height="22" fill="white"/><text x="4" y="16" fill="#174ea6" font-size="15">Google</text><text x="55" y="16" fill="#444" font-size="9">CI fixture</text></svg>'});
        }
        result.unexpectedRequests.push({kind: 'blocked', origin: url.origin, path: url.pathname});
        return route.abort('blockedbyclient');
      });

      const page = await context.newPage();
      page.on('pageerror', error => result.pageErrors.push(error.message));
      page.on('console', message => {if (message.type() === 'error') result.consoleErrors.push(message.text());});
      page.setDefaultTimeout(30000);
      let frame, documentResponse;
      page.on('response', response => {
        if (response.url() === `${origin}/brain-projection/earth.html`) documentResponse = response;
      });
      try {
        await page.goto(`${origin}/__projection_ci/host.html`, {waitUntil: 'load', timeout: 90000});
        frame = page.frames().find(candidate => candidate.url() === `${origin}/brain-projection/earth.html`);
        assert.ok(frame, 'The actual production renderer document must load in its parent iframe.');
        assert.ok(documentResponse, 'The production renderer response must be observed.');
        result.rendererHeaders = await documentResponse.allHeaders();
        assert.match(result.rendererHeaders['content-security-policy'], /default-src 'none'/);
        assert.match(result.rendererHeaders['permissions-policy'], /microphone=\(\)/);
        assert.equal(result.rendererHeaders['cache-control'], 'no-store');
        const scriptAttributes = await frame.locator(`script[src="${jsUrl}"]`).evaluate(node => ({
          integrity: node.integrity, crossOrigin: node.crossOrigin,
        }));
        assert.deepEqual(scriptAttributes, {integrity: CESIUM_JS_INTEGRITY, crossOrigin: 'anonymous'});
        assert.equal(await frame.locator(`link[href="${cssUrl}"]`).getAttribute('integrity'), CESIUM_CSS_INTEGRITY);
        await page.waitForFunction(() => window.__projectionCi.messages.some(message =>
          message.type === 'korlix-projection-status' && ['ready', 'error'].includes(message.status)));
        const statuses = () => page.evaluate(() => window.__projectionCi.messages
          .filter(message => message.type === 'korlix-projection-status').map(message => message.status));
        assert.deepEqual(await statuses(), ['loading', mode === 'ready' ? 'ready' : 'error']);
        result.sdk = await frame.evaluate(() => ({version: window.__projectionCi.sdk?.VERSION,
          realViewer: window.__projectionCi.viewer instanceof window.__projectionCi.sdk.Viewer,
          ionToken: window.__projectionCi.sdk.Ion.defaultAccessToken}));
        assert.deepEqual(result.sdk, {version: `${CESIUM_VERSION}.0`, realViewer: true, ionToken: ''});

        let sequence = 0;
        async function command(operation, values = {}) {
          sequence++;
          await page.evaluate(payload => document.getElementById('projection').contentWindow.postMessage(payload, location.origin),
            {type: 'korlix-projection-camera', camera: {sequence, operation, ...values}, place});
        }
        const position = () => frame.evaluate(() => {
          const {viewer, sdk} = window.__projectionCi, camera = viewer.camera, location = camera.positionCartographic;
          return {latitude: sdk.Math.toDegrees(location.latitude), longitude: sdk.Math.toDegrees(location.longitude),
            height: location.height, heading: sdk.Math.toDegrees(camera.heading)};
        });

        if (mode === 'ready') {
          assert.equal(await frame.locator('#map-state').isVisible(), false);
          assert.equal(await frame.locator('#map canvas').count(), 1);
          await frame.evaluate(() => {
            const observed = window.__projectionCi;
            observed.tileset = observed.viewer.scene.primitives.get(0);
            observed.tileset.tileVisible.addEventListener(() => {observed.visibleTiles++;});
          });
          await command('flyTo', {latitude: place.latitude, longitude: place.longitude, height: 850, heading: 0, pitch: -90});
          await frame.waitForFunction(expected => {
            const {viewer, sdk} = window.__projectionCi, current = viewer.camera.positionCartographic;
            return !viewer.camera._currentFlight && Math.abs(sdk.Math.toDegrees(current.latitude) - expected.latitude) < 0.00001 &&
              Math.abs(sdk.Math.toDegrees(current.longitude) - expected.longitude) < 0.00001 && Math.abs(current.height - 850) < 1;
          }, place);
          await frame.waitForFunction(() => window.__projectionCi.tileset.root.contentReady &&
            window.__projectionCi.tileset.tilesLoaded && window.__projectionCi.visibleTiles > 0);
          result.rendered = await frame.evaluate(() => new Promise((resolvePixels, reject) => {
            const {viewer, tileset, visibleTiles} = window.__projectionCi, scene = viewer.scene;
            const timer = setTimeout(() => {remove(); reject(Error('No rendered WebGL frame arrived.'));}, 10000);
            const remove = scene.postRender.addEventListener(() => {
              remove(); clearTimeout(timer);
              const canvas = scene.canvas;
              const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
              const width = Math.min(160, gl.drawingBufferWidth), height = Math.min(160, gl.drawingBufferHeight);
              // Cesium binds its default framebuffer before reading. Sampling
              // in postRender avoids the browser clearing an unpreserved buffer.
              const pixels = scene.context.readPixels({x: Math.floor((gl.drawingBufferWidth - width) / 2),
                y: Math.floor((gl.drawingBufferHeight - height) / 2), width, height});
              let coloredPixels = 0;
              for (let index = 0; index < pixels.length; index += 4) {
                if (pixels[index + 1] > 70 && pixels[index + 2] > 60 && pixels[index + 3] > 0) coloredPixels++;
              }
              resolvePixels({webgl: gl instanceof WebGLRenderingContext || gl instanceof WebGL2RenderingContext,
                lost: gl.isContextLost(), width: canvas.width, height: canvas.height,
                contentReady: tileset.root.contentReady, visibleTiles, coloredPixels, glError: gl.getError()});
            });
            scene.requestRender();
          }));
          assert.equal(result.rendered.webgl, true);
          assert.equal(result.rendered.lost, false);
          assert.equal(result.rendered.glError, 0);
          assert.ok(result.rendered.width > 0 && result.rendered.height > 0);
          assert.ok(result.rendered.coloredPixels > 100, 'Decoded synthetic geometry must produce visible pixels in the real WebGL canvas.');
          assert.ok(result.providerFixtures.some(request => request.path.endsWith('/fixture.glb')), 'The real tile loader must request binary model content.');

          result.credits = [];
          async function creditsAtViewport(width, height) {
            await page.setViewportSize({width, height});
            await frame.waitForFunction(expected => document.getElementById('map-credits').innerText.includes(expected), attribution);
            await page.waitForFunction(() => window.__projectionCi.messages.some(message => message.type === 'korlix-projection-credits'));
            await frame.waitForFunction(() => [...document.querySelectorAll('#map-credits img')].every(image => image.complete && image.naturalWidth > 0));
            const credits = await frame.locator('#map-credits').evaluate(element => {
              const box = element.getBoundingClientRect(), style = getComputedStyle(element);
              const visible = node => {const bounds = node.getBoundingClientRect(); return bounds.width > 0 && bounds.height > 0;};
              // A positioned Cesium credit child can overflow a tiny outer
              // container while that container itself is inside the viewport.
              // Verify every visible credit descendant fits the measured strip
              // that the app uses to reserve space, including real SDK logos.
              const descendants = [...element.querySelectorAll('*')].filter(node => visible(node) &&
                getComputedStyle(node).visibility !== 'hidden').map(node => {
                const bounds = node.getBoundingClientRect();
                return {tag: node.tagName, className: node.className, alt: node.getAttribute('alt'),
                  x: bounds.x, y: bounds.y, right: bounds.right, bottom: bounds.bottom,
                  contained: bounds.x >= box.x - 1 && bounds.y >= box.y - 1 &&
                    bounds.right <= box.right + 1 && bounds.bottom <= box.bottom + 1};
              });
              return {text: element.innerText, x: box.x, y: box.y, width: box.width, height: box.height,
                bottom: box.bottom, right: box.right, viewport: {width: innerWidth, height: innerHeight},
                visible: style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) > 0,
                descendants,
                googleLogo: [...element.querySelectorAll('img')].some(image => image.alt === 'Google' && visible(image)),
                cesiumCredit: [...element.querySelectorAll('a')].some(link => /cesium/i.test(link.href) && visible(link))};
            });
            result.credits.push(credits);
            assert.match(credits.text, /Google Maps/);
            assert.ok(credits.text.includes(attribution));
            assert.ok(credits.visible && credits.googleLogo && credits.cesiumCredit);
            assert.ok(credits.height > 0 && credits.x >= 0 && credits.y >= 0);
            assert.ok(credits.bottom <= credits.viewport.height + 1 && credits.right <= credits.viewport.width + 1);
            assert.ok(credits.descendants.length > 0 && credits.descendants.every(node => node.contained),
              `All visible credit content must fit the reported footer: ${JSON.stringify(credits.descendants.filter(node => !node.contained))}`);
            await page.waitForFunction(expected => {
              const latest = window.__projectionCi.messages.filter(message => message.type === 'korlix-projection-credits').at(-1);
              return latest && Number.isInteger(latest.height) && Math.abs(latest.height - expected) <= 1;
            }, Math.ceil(credits.height));
            await page.screenshot({path: resolve(artifactDirectory, `ready-${width}.png`)});
            return credits;
          }
          await creditsAtViewport(1280, 800);
          await creditsAtViewport(360, 740);
          result.camera = {flyTo: await position()};
          const initialHeight = result.camera.flyTo.height;
          await command('closer');
          await frame.waitForFunction(before => window.__projectionCi.viewer.camera.positionCartographic.height < before - 50, initialHeight);
          result.camera.closer = await position();
          await command('farther');
          await frame.waitForFunction(before => window.__projectionCi.viewer.camera.positionCartographic.height > before + 50, result.camera.closer.height);
          result.camera.farther = await position();
          await command('left');
          await frame.waitForFunction(() => {
            const {sdk, viewer} = window.__projectionCi;
            return !viewer.camera._currentFlight && Math.abs(sdk.Math.toDegrees(viewer.camera.heading) - 342) < 1;
          });
          result.camera.left = await position();
          await command('right');
          await frame.waitForFunction(() => {
            const {sdk, viewer} = window.__projectionCi, heading = sdk.Math.toDegrees(viewer.camera.heading);
            return !viewer.camera._currentFlight && Math.min(Math.abs(heading), Math.abs(heading - 360)) < 1;
          });
          result.camera.right = await position();
          await command('reset');
          await frame.waitForFunction(() => !window.__projectionCi.viewer.camera._currentFlight &&
            Math.abs(window.__projectionCi.viewer.camera.positionCartographic.height - 650) < 1);
          result.camera.reset = await position();
          assert.ok(Math.abs(result.camera.reset.latitude - place.latitude) < 0.00001);
          assert.ok(Math.abs(result.camera.reset.longitude - place.longitude) < 0.00001);
          // Exercise the same pagehide listener used by frame close/navigation.
          await frame.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
          assert.equal(await frame.evaluate(() => window.__projectionCi.viewer.isDestroyed()), true);
          assert.equal(await frame.locator('#map canvas').count(), 0);
          await command('closer');
          assert.deepEqual(await statuses(), ['loading', 'ready']);
          assert.deepEqual(result.consoleErrors, []);
        } else {
          assert.equal(await frame.locator('#map-state').isVisible(), true);
          assert.match(await frame.locator('#map-state').innerText(), /could not load/);
          assert.equal(await frame.evaluate(() => window.__projectionCi.viewer.isDestroyed()), true);
          assert.equal(await frame.locator('#map canvas').count(), 0);
          await command('flyTo', {latitude: place.latitude, longitude: place.longitude, height: 850});
          assert.deepEqual(await statuses(), ['loading', 'error']);
          const messages = await page.evaluate(() => window.__projectionCi.messages);
          assert.doesNotMatch(JSON.stringify(messages), /fake-key|private diagnostic|CI provider denied/);
          assert.ok(result.consoleErrors.every(message => /Failed to load resource.*403/.test(message)),
            `Only the expected denied-provider HTTP console error is permitted: ${JSON.stringify(result.consoleErrors)}`);
          await page.screenshot({path: resolve(artifactDirectory, 'denied-key.png')});
        }
        result.cspViolations = await frame.evaluate(() => window.__projectionCi.violations);
        assert.deepEqual(result.cspViolations, [], 'The real SDK must initialize/render without CSP violations.');
        assert.deepEqual(result.pageErrors, [], 'SDK/bootstrap must not produce uncaught browser errors.');
        assert.deepEqual(result.unexpectedRequests, [], 'Unreviewed network destinations must never be required.');
        result.statuses = await statuses();
        result.passed = true;
        console.log(`PASS configured renderer: ${mode}; real Cesium ${CESIUM_VERSION}; provider network requests=0`);
      } catch (error) {
        result.error = error.stack || error.message;
        result.messages = await page.evaluate(() => window.__projectionCi?.messages).catch(() => []);
        result.cspViolations = frame ? await frame.evaluate(() => window.__projectionCi?.violations).catch(() => []) : [];
        result.rendererState = frame ? await frame.evaluate(() => {
          const observed = window.__projectionCi, viewer = observed?.viewer, tileset = observed?.tileset;
          if (!viewer) return {viewer: false};
          if (viewer.isDestroyed()) return {viewer: true, destroyed: true};
          const camera = viewer.camera.positionCartographic;
          return {viewer: true, destroyed: false, camera: {latitude: camera.latitude, longitude: camera.longitude,
            height: camera.height, flight: Boolean(viewer.camera._currentFlight)}, visibleTiles: observed.visibleTiles,
            tileset: tileset && {tilesLoaded: tileset.tilesLoaded, geometricError: tileset.geometricError,
              rootVisible: tileset.root.isVisible, contentReady: tileset.root.contentReady,
              contentFailed: tileset.root.contentFailed, requested: tileset._statistics?.numberOfPendingRequests},
            credits: document.getElementById('map-credits')?.innerText};
        }).catch(() => null) : null;
        await page.screenshot({path: resolve(artifactDirectory, `${mode}-failure.png`)}).catch(() => {});
        throw error;
      } finally {
        await context.close();
      }
    }

    await scenario('ready');
    await scenario('denied-key');
    assert.ok(report.officialAssets.some(asset => asset.url === jsUrl && asset.integrity === CESIUM_JS_INTEGRITY));
    assert.ok(report.officialAssets.some(asset => asset.url === cssUrl && asset.integrity === CESIUM_CSS_INTEGRITY));
    report.passed = true;
  } finally {
    await writeFile(resolve(artifactDirectory, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    await browser?.close();
    server.closeAllConnections();
    await new Promise(resolveClosed => server.close(resolveClosed));
  }
}

if (process.argv.includes('--fixture-only')) {
  console.log(`PASS deterministic 3D Tiles/glTF fixture: ${fixture.glb.length} bytes; no browser or provider requests.`);
} else {
  await main();
}
