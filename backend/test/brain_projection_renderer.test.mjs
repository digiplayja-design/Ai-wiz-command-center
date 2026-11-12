import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCameraMessage, createCameraController, initialCameraOptions} from '../brain_projection/public/camera.mjs';
import {mountProjectionRenderer, loadGoogleMapsLibrary} from '../brain_projection/public/earth.mjs';

const origin = 'https://chee-chai-chee-backend.onrender.com';
const selected = {id: 'place-1', label: 'Confirmed place', latitude: 40.7, longitude: -73.9};
const camera = {sequence: 1, operation: 'flyTo', latitude: 40.7, longitude: -73.9, height: 650, heading: 0, pitch: -50};
function message(parent, patch = {}) {
  return {source: parent, origin: 'null', data: {type: 'korlix-projection-camera', camera, place: selected}, ...patch};
}

test('camera messages require the actual parent and opaque-local or same origin', () => {
  const parent = {};
  const context = {parent, ownOrigin: origin};
  assert.deepEqual(parseCameraMessage(message(parent), context), {camera, place: selected});
  assert.ok(parseCameraMessage(message(parent, {origin}), context));
  for (const event of [message({}), message(parent, {origin: 'https://untrusted.site'}),
    message(parent, {origin: 'file://'}), message(parent, {data: {type: 'BrainWorkspace'}}),
    message(parent, {data: 'execute some code'})]) {
    assert.equal(parseCameraMessage(event, context), null);
  }
});

test('camera input excludes arbitrary operations, non-finite values and stale sequences', () => {
  const parent = {}, context = {parent, ownOrigin: origin};
  for (const patch of [{sequence: -1}, {sequence: 1.2}, {sequence: Number.MAX_SAFE_INTEGER + 1},
    {operation: 'openURL'}, {latitude: NaN}, {latitude: 91}, {longitude: -181},
    {height: 0}, {height: Infinity}, {height: 40000001}, {heading: 361}, {pitch: 5}]) {
    assert.equal(parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera', camera: {...camera, ...patch}}}), context), null);
  }
  assert.equal(parseCameraMessage(message(parent), {...context, lastSequence: 1}), null);
  const clean = parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera',
    camera: {...camera, token: 'never forward', url: 'http://localhost'}, place: {...selected, account: 'ignore'}}}), context);
  assert.deepEqual(clean, {camera, place: selected});
  assert.equal(parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera', camera: {sequence: 2, operation: 'flyTo'}}}), context), null);
  for (const place of [{...selected, latitude: 100}, {...selected, label: '<script>'}, {id: 'missing-coordinates'}]) {
    assert.equal(parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera', camera, place}}), context), null);
  }
});

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
}
async function flush() {
  for (let index = 0; index < 8; index++) await Promise.resolve();
}
function fakeBrowser({key = 'public-test-key', loadLibrary, constructorThrows = false, reducedMotion = false} = {}) {
  const posts = [], events = new Map(), documentEvents = new Map(), timers = new Map(), frames = new Map(), scripts = [];
  const state = {hidden: false, textContent: ''};
  let nextTimer = 0, nextFrame = 0, frameTime = 0;
  const calls = {maps: [], loads: [], flights: [], stops: 0, order: []};
  class Map3DElement {
    constructor(options) {
      if (constructorThrows) throw Error('key=private-provider-diagnostics');
      Object.assign(this, options);
      this.options = options;
      this.listeners = new Map();
      this.removed = false;
      calls.maps.push(this);
    }
    get shadowRoot() { throw Error('Provider internals must not be inspected.'); }
    addEventListener(name, callback) {
      if (!this.listeners.has(name)) this.listeners.set(name, new Set());
      this.listeners.get(name).add(callback);
    }
    removeEventListener(name, callback) { this.listeners.get(name)?.delete(callback); }
    emit(name, detail = {}) {
      for (const callback of [...(this.listeners.get(name) || [])]) callback({target: this, ...detail});
    }
    stopCameraAnimation() { calls.stops++; calls.order.push('stop'); return this.stopResult?.(); }
    flyCameraTo(input) { calls.flights.push(input); calls.order.push('fly'); return this.flightResult?.(); }
    remove() { this.removed = true; this.isConnected = false; }
  }
  const library = {Map3DElement};
  const container = {children: [], append(map) { this.children.push(map); map.isConnected = true; }};
  const win = {location: {origin},
    parent: {postMessage: (...args) => posts.push(args)},
    matchMedia: () => ({matches: reducedMotion}),
    addEventListener(name, callback) {
      if (!events.has(name)) events.set(name, new Set());
      events.get(name).add(callback);
    },
    removeEventListener: (name, callback) => events.get(name)?.delete(callback),
    requestAnimationFrame(callback) { const id = ++nextFrame; frames.set(id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout(callback, milliseconds) { const id = ++nextTimer; timers.set(id, {callback, milliseconds}); return id; },
    clearTimeout: id => timers.delete(id)};
  const doc = {
    visibilityState: 'visible',
    addEventListener(name, callback) {
      if (!documentEvents.has(name)) documentEvents.set(name, new Set());
      documentEvents.get(name).add(callback);
    },
    removeEventListener: (name, callback) => documentEvents.get(name)?.delete(callback),
    getElementById(name) {
      if (name === 'map-state') return state;
      if (name === 'map') return container;
      throw Error('Unexpected provider DOM access: ' + name);
    },
    querySelector(selector) {
      if (selector === 'meta[name="korlix-map-key"]') return {content: key};
      if (selector === 'script[nonce]') return {nonce: 'document-csp-nonce'};
      throw Error('Unexpected selector: ' + selector);
    },
    createElement(name) {
      assert.equal(name, 'script');
      return {removed: false, remove() { this.removed = true; }};
    },
    head: {append(script) { scripts.push(script); }},
  };
  const emit = (name, value) => { for (const callback of [...(events.get(name) || [])]) callback(value); };
  const emitDocument = (name, value) => { for (const callback of [...(documentEvents.get(name) || [])]) callback(value); };
  const advanceFrame = (milliseconds = 16) => {
    frameTime += milliseconds;
    const callbacks = [...frames.values()];
    frames.clear();
    for (const callback of callbacks) callback(frameTime);
  };
  return {window: win, document: doc, posts, state, container, calls, events, documentEvents, timers, frames, scripts,
    library, emit, emitDocument, advanceFrame,
    loadLibrary(args) { calls.loads.push(args); return loadLibrary ? loadLibrary(args) : Promise.resolve(library); }};
}
const statusPosts = fixture => fixture.posts.filter(post => post[0].type === 'korlix-projection-status');
const statuses = fixture => statusPosts(fixture).map(post => post[0].status);
function assertClean(f) {
  assert.equal(f.events.get('message')?.size, 0);
  assert.equal(f.events.get('pagehide')?.size, 0);
  assert.equal(f.documentEvents.get('visibilitychange')?.size, 0);
  assert.equal(f.timers.size, 0);
  assert.equal(f.frames.size, 0);
  assert.ok(f.calls.maps.every(map => map.removed));
  assert.ok(f.calls.maps.every(map => [...map.listeners.values()].every(listeners => listeners.size === 0)));
}

test('SDK loader registers its callback first, loads only Maps JavaScript quarterly and propagates the CSP nonce', async () => {
  const f = fakeBrowser(), abort = new AbortController();
  let imports = 0, callback;
  f.window.google = {maps: {importLibrary(name) { imports++; assert.equal(name, 'maps3d'); return Promise.resolve(f.library); }}};
  f.document.head.append = script => {
    assert.equal(typeof f.window.__korlixMapsReady, 'function', 'Warm cache cannot beat callback registration');
    f.scripts.push(script);
    callback = f.window.__korlixMapsReady;
  };
  const loading = loadGoogleMapsLibrary({...f, key: 'public-test-key', signal: abort.signal});
  const script = f.scripts[0], url = new URL(script.src);
  assert.equal(url.origin, 'https://maps.googleapis.com');
  assert.equal(url.pathname, '/maps/api/js');
  assert.deepEqual(Object.fromEntries(url.searchParams), {key: 'public-test-key', v: 'quarterly',
    loading: 'async', callback: '__korlixMapsReady', auth_referrer_policy: 'origin'});
  assert.equal(script.nonce, 'document-csp-nonce');
  assert.equal(script.referrerPolicy, 'strict-origin-when-cross-origin');
  assert.equal(script.async, true);
  assert.equal(imports, 0);
  callback();
  callback();
  assert.equal(await loading, f.library);
  assert.equal(imports, 1, 'A duplicate SDK callback never starts another import or map');
  assert.equal(script.onerror, null);
  abort.abort();
});

test('SDK import errors, failed scripts and cancellation are sanitized; late imports cannot revive the loader', async () => {
  for (const failure of ['import', 'script', 'abort', 'aborted']) {
    const f = fakeBrowser(), abort = new AbortController(), pending = deferred();
    f.window.google = {maps: {importLibrary: () => pending.promise}};
    if (failure === 'aborted') abort.abort();
    const loading = loadGoogleMapsLibrary({...f, key: 'public-test-key', signal: abort.signal});
    const rejected = assert.rejects(loading, error => {
      assert.doesNotMatch(error.message, /secret|public-test-key|https:|provider body/);
      return true;
    });
    const callback = f.window.__korlixMapsReady;
    if (failure === 'import') {
      callback();
      pending.reject(Error('https://provider.invalid/?key=secret provider body'));
    } else if (failure === 'script') {
      f.scripts[0].onerror({message: 'key=secret provider body'});
    } else if (failure === 'abort') {
      callback();
      abort.abort();
      pending.resolve(f.library);
      callback();
    }
    await rejected;
    assert.equal(f.scripts.length, failure === 'aborted' ? 0 : 1);
    assert.ok(f.scripts.every(script => script.removed));
  }
});

test('renderer remains loading until its own documented steady event reports completed rendering', async () => {
  const f = fakeBrowser();
  const runtime = mountProjectionRenderer(f);
  assert.equal(typeof runtime.dispose, 'function');
  assert.deepEqual(statuses(f), ['loading']);
  assert.equal([...f.timers.values()][0].milliseconds, 30000);
  assert.equal(typeof f.window.gm_authFailure, 'function');
  await flush();
  const map = f.calls.maps[0];
  assert.equal(map.options.mode, 'SATELLITE');
  assert.equal(map.options.defaultUIHidden, true);
  assert.deepEqual(map.options.center, initialCameraOptions().center);
  assert.equal(map.options.minAltitude, 1);
  assert.equal(map.options.maxAltitude, 40000000);
  assert.deepEqual(statuses(f), ['loading'], 'SDK import and construction do not imply imagery loaded');
  map.emit('gmp-steadystate', {isSteady: true});
  map.emit('gmp-animationend');
  map.emit('gmp-steadychange', {isSteady: false});
  map.emit('gmp-steadychange', {isSteady: 'true'});
  map.emit('gmp-steadychange', {isSteady: true, target: {}});
  assert.deepEqual(statuses(f), ['loading']);
  map.emit('gmp-steadychange', {isSteady: true});
  assert.deepEqual(statuses(f), ['loading', 'ready']);
  map.emit('gmp-steadychange', {isSteady: false});
  map.emit('gmp-steadychange', {isSteady: true});
  assert.deepEqual(statuses(f), ['loading', 'ready'], 'Camera movement does not repeatedly reinitialize the shell');
  assert.equal(f.state.hidden, true);
  assert.equal(f.timers.size, 0);
  assert.ok(f.posts.every(post => post[0].type === 'korlix-projection-status' && post[1] === '*'));
  assert.doesNotMatch(JSON.stringify(f.posts), /public-test-key|Authorization|nonce|provider/);
  runtime.dispose();
  assertClean(f);
  runtime.dispose();
});

test('only the latest valid queued camera command runs after steady; source and sequence checks survive SDK migration', async () => {
  const pending = deferred();
  const f = fakeBrowser({loadLibrary: () => pending.promise});
  const runtime = mountProjectionRenderer(f);
  f.emit('message', message(f.window.parent));
  f.emit('message', message(f.window.parent, {data: {type: 'korlix-projection-camera',
    camera: {...camera, sequence: 2, latitude: 41, longitude: -72}, place: selected}}));
  pending.resolve(f.library);
  await flush();
  const map = f.calls.maps[0];
  assert.equal(f.calls.flights.length, 0);
  map.emit('gmp-steadychange', {isSteady: true});
  assert.equal(f.calls.flights.length, 1);
  assert.deepEqual(f.calls.flights[0].endCamera.center, {lat: 41, lng: -72, altitude: 0});
  assert.equal(f.calls.flights[0].endCamera.altitudeMode, 'RELATIVE_TO_GROUND');
  f.emit('message', message(f.window.parent));
  f.emit('message', message({}, {data: {type: 'korlix-projection-camera', camera: {...camera, sequence: 3}}}));
  assert.equal(f.calls.flights.length, 1);
  f.emit('message', message(f.window.parent, {data: {type: 'korlix-projection-camera',
    camera: {sequence: 3, operation: 'closer'}}}));
  assert.equal(f.calls.flights.length, 2);
  assert.deepEqual(f.calls.order, ['stop', 'fly', 'stop', 'fly']);
  runtime.dispose();
});

test('missing configuration never loads the SDK and an unavailable constructor never reports readiness', async () => {
  const missing = fakeBrowser({key: ''});
  mountProjectionRenderer(missing);
  assert.deepEqual(statuses(missing), ['loading', 'error']);
  assert.equal(missing.calls.loads.length, 0);
  assertClean(missing);
  for (const badLibrary of [undefined, {}, {Map3DElement: null}]) {
    const f = fakeBrowser({loadLibrary: async () => badLibrary});
    mountProjectionRenderer(f);
    await flush();
    assert.deepEqual(statuses(f), ['loading', 'error']);
    assert.equal(f.calls.maps.length, 0);
    assertClean(f);
  }
});

test('SDK, constructor, initialization and authentication failures release resources without provider details', async () => {
  for (const failure of ['sdk', 'constructor', 'map', 'auth-before', 'auth-after']) {
    const f = fakeBrowser({constructorThrows: failure === 'constructor',
      ...(failure === 'sdk' ? {loadLibrary: async () => {throw Error('key=secret provider body');}} : {})});
    mountProjectionRenderer(f);
    if (failure === 'auth-before') f.window.gm_authFailure();
    await flush();
    const map = f.calls.maps[0];
    if (failure === 'map') map.emit('gmp-error', {message: 'key=secret provider body'});
    if (failure === 'auth-after') {
      map.emit('gmp-steadychange', {isSteady: true});
      f.window.gm_authFailure();
    }
    assert.deepEqual(statuses(f), failure === 'auth-after' ? ['loading', 'ready', 'error'] : ['loading', 'error']);
    assert.equal(f.state.hidden, false);
    assert.doesNotMatch(JSON.stringify(f.posts), /secret|private|provider body|public-test-key/);
    assertClean(f);
    const count = f.posts.length;
    f.window.gm_authFailure();
    map?.emit('gmp-steadychange', {isSteady: true});
    assert.equal(f.posts.length, count);
  }
});

test('closing during SDK import aborts pending work, ignores late resolution and restores an earlier auth handler', async () => {
  const pending = deferred(), f = fakeBrowser({loadLibrary: () => pending.promise});
  const previous = () => {};
  f.window.gm_authFailure = previous;
  mountProjectionRenderer(f);
  const lateAuth = f.window.gm_authFailure;
  f.emit('pagehide');
  assert.equal(f.calls.loads[0].signal.aborted, true);
  pending.resolve(f.library);
  await flush();
  lateAuth();
  assert.equal(f.calls.maps.length, 0);
  assert.deepEqual(statuses(f), ['loading']);
  assert.equal(f.window.gm_authFailure, previous);
  assertClean(f);
});

test('deadline covers both SDK download and imagery rendering, preventing late readiness in either phase', async () => {
  for (const phase of ['sdk', 'imagery']) {
    const pending = deferred(), f = fakeBrowser({loadLibrary: () => phase === 'sdk' ? pending.promise : Promise.resolve(f.library)});
    mountProjectionRenderer(f);
    await flush();
    const map = f.calls.maps[0];
    const lateSteady = map ? [...map.listeners.get('gmp-steadychange')][0] : null;
    [...f.timers.values()][0].callback();
    pending.resolve(f.library);
    await flush();
    lateSteady?.({target: map, isSteady: true});
    assert.deepEqual(statuses(f), ['loading', 'error']);
    assert.equal(f.calls.loads[0].signal.aborted, true);
    assertClean(f);
  }
});

test('camera targets terrain under the confirmed address and preserves actual center while zooming and orbiting', () => {
  const f = fakeBrowser(), map = new f.library.Map3DElement(initialCameraOptions());
  const controller = createCameraController({map});
  controller.apply({camera, place: selected});
  const target = f.calls.flights.at(-1).endCamera;
  assert.deepEqual(target.center, {lat: 40.7, lng: -73.9, altitude: 0});
  assert.equal(target.altitudeMode, 'RELATIVE_TO_GROUND');
  assert.equal(target.tilt, 40);
  assert.ok(Math.abs(target.range - 650 / Math.cos(40 * Math.PI / 180)) < 1e-9);
  assert.equal('cameraPosition' in target, false);
  // Model subsequent direct map exploration at a high terrain elevation.
  Object.assign(map, {center: {lat: 39.1, lng: -106.4, altitude: 4395}, range: 1000, heading: 5, tilt: 50});
  controller.apply({camera: {operation: 'closer'}, place: null});
  assert.deepEqual(f.calls.flights.at(-1).endCamera, {center: map.center, altitudeMode: 'ABSOLUTE',
    range: 650, heading: 5, tilt: 50, roll: 0});
  controller.apply({camera: {operation: 'farther'}, place: null});
  assert.equal(f.calls.flights.at(-1).endCamera.range, 1350);
  controller.apply({camera: {operation: 'left'}, place: null});
  assert.equal(f.calls.flights.at(-1).endCamera.heading, 347);
  assert.deepEqual(f.calls.flights.at(-1).endCamera.center, map.center);
  controller.apply({camera: {operation: 'right'}, place: null});
  assert.equal(f.calls.flights.at(-1).endCamera.heading, 23);
  controller.apply({camera: {operation: 'reset'}, place: null});
  assert.deepEqual(f.calls.flights.at(-1).endCamera.center, target.center);
  assert.equal(f.calls.flights.at(-1).endCamera.altitudeMode, 'RELATIVE_TO_GROUND');
  assert.equal(f.calls.stops, f.calls.flights.length);
  controller.dispose();
});

test('camera ranges, horizon tilt and headings are bounded, with instant motion when requested', () => {
  const f = fakeBrowser(), map = new f.library.Map3DElement(initialCameraOptions());
  const controller = createCameraController({map, reducedMotion: true});
  controller.apply({camera: {...camera, height: 40000000, pitch: 0, heading: -360}, place: selected});
  assert.equal(f.calls.flights.at(-1).endCamera.range, 40000000);
  assert.equal(f.calls.flights.at(-1).endCamera.tilt, 85);
  assert.equal(f.calls.flights.at(-1).endCamera.heading, 0);
  assert.equal(f.calls.flights.at(-1).durationMillis, 0);
  Object.assign(map, {range: 1, tilt: 0});
  const count = f.calls.flights.length;
  controller.apply({camera: {operation: 'closer'}, place: null});
  assert.equal(f.calls.flights.length, count);
  map.range = 40000000;
  controller.apply({camera: {operation: 'farther'}, place: null});
  assert.equal(f.calls.flights.length, count);
  Object.assign(map, {range: 400, tilt: 85});
  controller.apply({camera: {operation: 'closer'}, place: null});
  assert.ok(f.calls.flights.at(-1).endCamera.range >= 1 / Math.cos(85 * Math.PI / 180));
  controller.dispose();
  controller.apply({camera, place: selected});
  assert.equal(f.calls.flights.length, count + 1);
});

test('latest camera command wins asynchronous cancellation; disposal invalidates pending commands', async () => {
  const f = fakeBrowser(), map = new f.library.Map3DElement(initialCameraOptions());
  const cancellations = [], errors = [];
  map.stopResult = () => { const pending = deferred(); cancellations.push(pending); return pending.promise; };
  const controller = createCameraController({map, onError: () => errors.push('failed')});
  controller.apply({camera, place: selected});
  controller.apply({camera: {...camera, longitude: -72, sequence: 2}, place: selected});
  cancellations[0].resolve();
  await flush();
  assert.equal(f.calls.flights.length, 0);
  cancellations[1].resolve();
  await flush();
  assert.equal(f.calls.flights.length, 1);
  assert.equal(f.calls.flights[0].endCamera.center.lng, -72);
  controller.apply({camera: {...camera, sequence: 3}, place: selected});
  controller.dispose();
  cancellations[2].resolve();
  cancellations[3].reject(Error('secret disposal error'));
  await flush();
  assert.equal(f.calls.flights.length, 1);
  assert.deepEqual(errors, []);
});

test('superseded flight errors are ignored; current flight failures fail the renderer without details', async () => {
  const f = fakeBrowser();
  mountProjectionRenderer(f);
  await flush();
  const map = f.calls.maps[0], flights = [];
  map.flightResult = () => {const pending = deferred(); flights.push(pending); return pending.promise;};
  map.emit('gmp-steadychange', {isSteady: true});
  f.emit('message', message(f.window.parent));
  f.emit('message', message(f.window.parent, {data: {type: 'korlix-projection-camera', camera: {...camera, sequence: 2}, place: selected}}));
  flights[0].reject(Error('https://provider.invalid/?key=secret'));
  await flush();
  assert.deepEqual(statuses(f), ['loading', 'ready']);
  flights[1].reject(Error('https://provider.invalid/?key=secret'));
  await flush();
  assert.deepEqual(statuses(f), ['loading', 'ready', 'error']);
  assert.doesNotMatch(JSON.stringify(f.posts), /secret|provider.invalid/);
  assertClean(f);
});

const cameraStatuses = f => f.posts.filter(post => post[0].type === 'korlix-projection-camera-status').map(post => post[0]);
function sendCamera(f, sequence, operation, extra = {}) {
  f.emit('message', message(f.window.parent, {data: {type: 'korlix-projection-camera',
    camera: {sequence, operation, ...extra}, place: null}}));
}
function controllerFixture(options = {}) {
  const f = fakeBrowser(), map = new f.library.Map3DElement(initialCameraOptions());
  const notices = [], errors = [];
  const controller = createCameraController({map, requestFrame: callback => f.window.requestAnimationFrame(callback),
    cancelFrame: id => f.window.cancelAnimationFrame(id), onStatus: value => notices.push(value),
    onError: () => errors.push('failed'), ...options});
  const apply = (sequence, operation, extra = {}) => controller.apply({camera: {sequence, operation, ...extra}, place: null});
  return {...f, map, controller, notices, errors, apply};
}

test('continuous and stop operations preserve the source/sequence protocol; a stop needs no place', () => {
  const parent = {}, context = {parent, ownOrigin: origin};
  for (const operation of ['zoomInContinuous', 'zoomOutContinuous', 'stopCamera']) {
    const event = message(parent, {data: {type: 'korlix-projection-camera', camera: {sequence: 9, operation}, place: null}});
    assert.deepEqual(parseCameraMessage(event, context), {camera: {sequence: 9, operation}, place: null});
    assert.equal(parseCameraMessage(event, {...context, lastSequence: 9}), null);
    assert.equal(parseCameraMessage({...event, source: {}}, context), null);
  }
  assert.ok(parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera', camera: {...camera, height: 1}}}), context));
  assert.equal(parseCameraMessage(message(parent, {data: {type: 'korlix-projection-camera', camera: {...camera, height: .99}}}), context), null);
});

test('continuous zoom keeps actual geography, changes only range, and stops with no queued camera work', () => {
  const f = controllerFixture();
  const view = {center: {lat: 39.1, lng: -106.4, altitude: 4395}, range: 1000, heading: 5, tilt: 50, roll: 0};
  Object.assign(f.map, view);
  f.apply(1, 'zoomInContinuous');
  assert.equal(f.frames.size, 1);
  f.advanceFrame();
  f.advanceFrame(1000);
  assert.ok(Math.abs(f.map.range - 1000 * Math.exp(-.8 * .064)) < 1e-9,
    'A suspended frame advances at most 64 ms of motion, without a large jump.');
  for (let step = 0; step < 30; step++) f.advanceFrame();
  assert.ok(f.map.range < 1000);
  assert.deepEqual({...f.map.center}, view.center);
  assert.equal(f.map.heading, view.heading);
  assert.equal(f.map.tilt, view.tilt);
  assert.equal(f.calls.flights.length, 0, 'Continuous motion does not stack flyCameraTo animations.');
  const stoppedRange = f.map.range;
  f.apply(2, 'stopCamera');
  assert.equal(f.frames.size, 0);
  for (let step = 0; step < 20; step++) f.advanceFrame();
  assert.equal(f.map.range, stoppedRange);
  assert.deepEqual(f.notices, [{state: 'stopped', reason: 'stopped', sequence: 2}]);
  assert.deepEqual(f.errors, []);
  f.controller.dispose();
});

test('superseded rAF callbacks cannot move the camera or lose a newer cancellable frame', () => {
  const f = controllerFixture();
  f.map.range = 1000;
  f.apply(1, 'zoomInContinuous');
  f.advanceFrame();
  const staleFrame = [...f.frames.values()][0];
  f.apply(2, 'zoomOutContinuous');
  staleFrame(100);
  assert.equal(f.map.range, 1000);
  assert.equal(f.frames.size, 1);
  f.advanceFrame();
  f.advanceFrame();
  assert.ok(f.map.range > 1000);
  f.apply(3, 'stopCamera');
  assert.equal(f.frames.size, 0, 'The newer frame remains cancellable after a stale callback fires.');
  const stoppedRange = f.map.range;
  staleFrame(200);
  assert.equal(f.map.range, stoppedRange);
  assert.deepEqual(f.notices, [{state: 'stopped', reason: 'stopped', sequence: 3}]);
  f.controller.dispose();
});

test('late asynchronous animation cancellation cannot restart continuous zoom after stop or disposal', async () => {
  const f = controllerFixture(), pending = [];
  f.map.stopResult = () => {const task = deferred(); pending.push(task); return task.promise;};
  f.apply(1, 'zoomInContinuous');
  f.apply(2, 'stopCamera');
  pending[0].resolve();
  await flush();
  assert.equal(f.frames.size, 0);
  pending[1].resolve();
  await flush();
  assert.deepEqual(f.notices, [{state: 'stopped', reason: 'stopped', sequence: 2}]);
  f.apply(3, 'zoomOutContinuous');
  f.apply(4, 'stopCamera');
  pending[3].resolve();
  pending[2].reject(Error('key=private stale SDK rejection'));
  await flush();
  assert.equal(f.frames.size, 0);
  assert.deepEqual(f.errors, []);
  assert.deepEqual(f.notices.at(-1), {state: 'stopped', reason: 'stopped', sequence: 4});
  f.apply(5, 'zoomInContinuous');
  f.controller.dispose();
  pending[4].resolve();
  pending[5].reject(Error('ignored close rejection'));
  await flush();
  assert.equal(f.frames.size, 0);
  assert.deepEqual(f.errors, []);
});

test('continuous zoom reaches finite close/far bounds and never pulls a closer SDK camera outward', () => {
  for (const tilt of [0, 40, 85]) {
    const f = controllerFixture(), minimum = 1 / Math.cos(tilt * Math.PI / 180);
    Object.assign(f.map, {range: minimum * 2, tilt});
    f.apply(1, 'zoomInContinuous');
    for (let step = 0; step < 100 && f.frames.size; step++) {
      const previous = f.map.range;
      f.advanceFrame(32);
      assert.ok(f.map.range <= previous && f.map.range >= minimum);
    }
    assert.equal(f.frames.size, 0);
    assert.equal(f.map.range, minimum);
    assert.deepEqual(f.notices, [{state: 'limit', reason: 'closest', sequence: 1}]);
    Object.assign(f.map, {range: 39999999, tilt: 0});
    f.apply(2, 'zoomOutContinuous');
    f.advanceFrame(); f.advanceFrame();
    assert.equal(f.map.range, 40000000);
    assert.equal(f.frames.size, 0);
    assert.deepEqual(f.notices.at(-1), {state: 'limit', reason: 'farthest', sequence: 2});
    f.map.range = .5;
    f.apply(3, 'zoomInContinuous');
    f.advanceFrame();
    assert.equal(f.map.range, .5, 'Reaching our bound cannot force an outward camera jump.');
    assert.equal(f.frames.size, 0);
    f.controller.dispose();
  }
});

test('a stricter SDK camera clamp stops continuous requests instead of spinning indefinitely', () => {
  const f = controllerFixture();
  Object.defineProperty(f.map, 'range', {configurable: true, get: () => 100, set: () => {}});
  f.apply(1, 'zoomInContinuous');
  for (let step = 0; step < 100 && f.frames.size; step++) f.advanceFrame(16);
  assert.equal(f.frames.size, 0);
  assert.deepEqual(f.notices, [{state: 'limit', reason: 'closest', sequence: 1}]);
  assert.deepEqual(f.errors, []);
  f.controller.dispose();
});

test('gesture-created ranges outside app bounds return smoothly instead of snapping across the scene', () => {
  const f = controllerFixture();
  Object.assign(f.map, {range: 50000000, tilt: 0});
  f.apply(1, 'zoomInContinuous');
  f.advanceFrame(); f.advanceFrame();
  assert.ok(f.map.range < 50000000 && f.map.range > 40000000);
  f.apply(2, 'stopCamera');
  f.map.range = .5;
  f.apply(3, 'zoomOutContinuous');
  f.advanceFrame(); f.advanceFrame();
  assert.ok(f.map.range > .5 && f.map.range < 1);
  f.apply(4, 'stopCamera');
  f.map.range = 0;
  f.apply(5, 'zoomOutContinuous');
  f.advanceFrame(); f.advanceFrame();
  assert.ok(f.map.range >= 1 && f.map.range < 2, 'A zero-range SDK camera can recover to a positive standoff.');
  f.controller.dispose();
});

test('each discrete camera command cancels continuous motion while retaining its existing flight behavior', () => {
  for (const operation of ['closer', 'farther', 'left', 'right', 'reset', 'flyTo']) {
    const f = controllerFixture();
    Object.assign(f.map, {range: 1000, heading: 5, tilt: 40});
    f.apply(1, 'zoomInContinuous');
    f.advanceFrame(); f.advanceFrame();
    const range = f.map.range;
    f.apply(2, operation, operation === 'flyTo' ? {latitude: 40.7, longitude: -73.9} : {});
    assert.equal(f.frames.size, 0);
    assert.equal(f.calls.flights.length, 1);
    const flight = f.calls.flights[0];
    if (operation === 'closer') assert.equal(flight.endCamera.range, range * .65);
    if (operation === 'farther') assert.equal(flight.endCamera.range, range * 1.35);
    if (operation === 'left') assert.equal(flight.endCamera.heading, 347);
    if (operation === 'right') assert.equal(flight.endCamera.heading, 23);
    if (operation === 'flyTo') assert.deepEqual(flight.endCamera.center, {lat: 40.7, lng: -73.9, altitude: 0});
    if (operation === 'reset') assert.deepEqual(flight.endCamera.center, initialCameraOptions().center);
    f.controller.dispose();
  }
});

test('pointer, touch and wheel cancel motion once, with sanitized sequence-aware statuses and full cleanup', async () => {
  for (const input of ['pointerdown', 'touchstart', 'wheel']) {
    const f = fakeBrowser(), runtime = mountProjectionRenderer(f);
    await flush();
    const map = f.calls.maps[0];
    map.emit('gmp-steadychange', {isSteady: true});
    Object.assign(map, {range: 1000, tilt: 40});
    sendCamera(f, 1, 'zoomInContinuous');
    f.advanceFrame(); f.advanceFrame();
    map.emit(input);
    assert.equal(f.frames.size, 0);
    const stopCount = f.calls.stops;
    map.emit(input); map.emit('pointerdown');
    assert.equal(f.calls.stops, stopCount, 'Repeated native input must not repeatedly stop SDK gesture handling.');
    assert.deepEqual(cameraStatuses(f), [{type: 'korlix-projection-camera-status', state: 'stopped', reason: 'interrupted', sequence: 1}]);
    sendCamera(f, 2, 'zoomOutContinuous');
    f.advanceFrame(); f.advanceFrame();
    assert.equal(f.frames.size, 1);
    f.document.visibilityState = 'hidden';
    f.emitDocument('visibilitychange');
    assert.equal(f.frames.size, 0);
    assert.equal(cameraStatuses(f).at(-1).sequence, 2);
    f.document.visibilityState = 'visible';
    f.emitDocument('visibilitychange');
    assert.equal(f.frames.size, 0, 'Showing the document cannot resume a cancelled voice command.');
    sendCamera(f, 3, 'zoomInContinuous');
    f.advanceFrame(); f.advanceFrame();
    f.emit('pagehide');
    assertClean(f);
    runtime.dispose();
    assert.doesNotMatch(JSON.stringify(cameraStatuses(f)), /center|latitude|longitude|label|key|http/);
  }
});

test('stop and hidden-document commands remove queued motion before a late SDK or steady event', async () => {
  for (const phase of ['import', 'steady']) {
    for (const cause of ['stopCamera', 'visibility']) {
      const pending = deferred(), f = fakeBrowser({loadLibrary: () => pending.promise});
      const runtime = mountProjectionRenderer(f);
      if (phase === 'steady') { pending.resolve(f.library); await flush(); }
      sendCamera(f, 1, 'zoomInContinuous');
      if (cause === 'stopCamera') sendCamera(f, 2, 'stopCamera');
      else {
        f.document.visibilityState = 'hidden';
        f.emitDocument('visibilitychange');
        sendCamera(f, 2, 'zoomOutContinuous');
        f.document.visibilityState = 'visible';
        f.emitDocument('visibilitychange');
      }
      pending.resolve(f.library);
      await flush();
      f.calls.maps[0].emit('gmp-steadychange', {isSteady: true});
      assert.equal(f.frames.size, 0);
      assert.equal(f.calls.flights.length, 0);
      assert.deepEqual(cameraStatuses(f).at(-1), {type: 'korlix-projection-camera-status', state: 'stopped',
        reason: cause === 'stopCamera' ? 'stopped' : 'interrupted', sequence: 2});
      runtime.dispose();
      assertClean(f);
    }
  }
});

test('invalid public camera state during continuous movement fails once and releases the frame', async () => {
  const f = fakeBrowser();
  mountProjectionRenderer(f);
  await flush();
  const map = f.calls.maps[0];
  map.emit('gmp-steadychange', {isSteady: true});
  sendCamera(f, 1, 'zoomInContinuous');
  map.range = NaN;
  f.advanceFrame();
  assert.deepEqual(statuses(f), ['loading', 'ready', 'error']);
  assertClean(f);
});
