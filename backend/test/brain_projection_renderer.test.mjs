import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCameraMessage, createCameraController, initialCameraOptions, destinationCamera} from '../brain_projection/public/camera.mjs';
import {mountProjectionRenderer, loadGoogleMapsLibrary} from '../brain_projection/public/earth.mjs';
import {headingToProperty, capturedMonth, requestPanorama} from '../brain_projection/public/street.mjs';

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


function surfaceFixture({key = 'public-fixture-key', sdkDeferred = null, maxZoom = 3, importFailure = false,
  readyWhenVisible = false, setPanoFailure = false} = {}) {
  class Element {
    constructor(tag = 'div') { this.tag = tag; this.hidden = false; this.textContent = ''; this.children = []; this.listeners = new Map(); this.attributes = {}; }
    setAttribute(name, value) { this.attributes[name] = value; }
    append(...children) { this.children.push(...children); for (const child of children) child.isConnected = true; }
    remove() { this.removed = true; this.isConnected = false; }
    addEventListener(name, fn) { if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name).add(fn); }
    removeEventListener(name, fn) { this.listeners.get(name)?.delete(fn); }
    emit(name, detail = {}) { for (const fn of [...(this.listeners.get(name) || [])]) fn({target: this, ...detail}); }
  }
  const calls = {loads: [], imports: [], queries: [], panoramas: [], maps: [], order: []};
  const posts = [], timers = new Map(), frames = new Map(), panoramas = new Map(), scripts = [];
  const root = new Element(), state = new Element(), label = new Element(), events = new Element(), documentEvents = new Element();
  let now = 0, serial = 0;
  class StreetViewService {
    getPanorama(request, callback) { calls.queries.push({request, callback}); }
  }
  class StreetViewPanorama extends Element {
    constructor(host, options) {
      super(); this.host = host; this.options = options; this.pano = ''; this.status = 'UNKNOWN_ERROR'; this.zoom = 1; this.pov = {heading: 0, pitch: 0}; this.visible = false;
      calls.panoramas.push(this);
    }
    addListener(name, fn) { this.addEventListener(name, fn); return {remove: () => this.removeEventListener(name, fn)}; }
    getPano() { return this.pano; }
    getStatus() { return this.status; }
    getPosition() { return panoramas.get(this.pano)?.location.latLng; }
    getZoom() { return this.zoom; }
    getPov() { return {...this.pov}; }
    setPov(value) { this.pov = {...value}; }
    setZoom(value) { this.zoom = Math.max(0, Math.min(maxZoom, value)); }
    setVisible(value) { this.visible = value; if (value && readyWhenVisible && this.status !== 'OK') this.ready(); }
    setPano(value) { this.pano = value; this.status = 'UNKNOWN_ERROR'; this.emit('pano_changed'); if (setPanoFailure) this.ready('UNKNOWN_ERROR'); }
    ready(status = 'OK', pano = this.pano) { this.pano = pano; this.status = status; this.emit('status_changed'); }
  }
  class Map3DElement extends Element {
    constructor(options) {
      super('gmp-map-3d');
      if ('altitudeMode' in options) throw Error('altitudeMode belongs to CameraOptions, not Map3DElementOptions.');
      this.options = options; Object.assign(this, options); this.flights = []; this.stops = 0; calls.maps.push(this);
    }
    stopCameraAnimation() { this.stops++; }
    flyCameraTo(value) {
      if (!this.isConnected) throw Error('The map must be mounted before its destination flight.');
      this.flights.push(value); Object.assign(this, value.endCamera);
    }
    steady() { this.emit('gmp-steadychange', {isSteady: true}); }
  }
  const api = {importLibrary(name) {
    calls.imports.push(name);
    if (importFailure) return Promise.reject(Error('key=secret provider body'));
    if (name === 'streetView') return Promise.resolve({StreetViewService, StreetViewPanorama});
    if (name === 'maps3d') return Promise.resolve({Map3DElement});
    throw Error('Unexpected library.');
  }};
  const win = {location: {origin}, parent: {postMessage: (message, target) => {calls.order.push(message.type); posts.push([message, target]);}},
    matchMedia: () => ({matches: false}), addEventListener: (name, fn) => events.addEventListener(name, fn),
    removeEventListener: (name, fn) => events.removeEventListener(name, fn),
    setTimeout(fn, delay) { const id = ++serial; timers.set(id, {callback: fn, milliseconds: delay}); return id; },
    clearTimeout: id => timers.delete(id),
    requestAnimationFrame(fn) { const id = ++serial; frames.set(id, fn); return id; },
    cancelAnimationFrame: id => frames.delete(id), google: {maps: api}};
  const doc = {visibilityState: 'visible',
    addEventListener: (name, fn) => documentEvents.addEventListener(name, fn),
    removeEventListener: (name, fn) => documentEvents.removeEventListener(name, fn),
    getElementById: name => ({map: root, 'map-state': state, 'imagery-label': label})[name],
    querySelector: selector => selector === 'meta[name="korlix-map-key"]' ? {content: key} : {nonce: 'fixture-csp-nonce'},
    createElement: tag => new Element(tag), head: {append: script => scripts.push(script)}};
  const send = (sequence, operation = 'flyTo', extra = {}, place = selected) => events.emit('message', {
    source: win.parent, origin: 'null', data: {type: 'korlix-projection-camera', camera: {sequence, operation, ...extra}, place}});
  const reply = (index, {pano = 'pano-' + index, position = {lat: selected.latitude - .0001, lng: selected.longitude}, date = '2026-06', status = 'OK'} = {}) => {
    const data = {location: {pano, latLng: position}, imageDate: date};
    panoramas.set(pano, data);
    calls.queries[index].callback(status === 'OK' ? data : null, status);
    return data;
  };
  return {window: win, document: doc, posts, timers, frames, calls, state, label, root, events, documentEvents, scripts, api, send, reply,
    loadLibrary(args) { calls.order.push('sdk-load'); calls.loads.push(args); return sdkDeferred ? sdkDeferred.promise : Promise.resolve(api); },
    tick(delta = 16) { now += delta; const pending = [...frames.values()]; frames.clear(); for (const fn of pending) fn(now); },
    hidden(value) { doc.visibilityState = value ? 'hidden' : 'visible'; documentEvents.emit('visibilitychange'); },
    gestures(name = 'pointerdown') { for (const host of root.children) if (!host.hidden) host.emit(name); },
    close() { events.emit('pagehide'); },
  };
}
const latestView = f => statusPosts(f).at(-1)?.[0];
async function openStreetFixture(f, sequence = 1) {
  const runtime = mountProjectionRenderer(f);
  f.send(sequence);
  await flush();
  f.reply(0); await flush();
  f.calls.panoramas[0].ready(); await flush();
  return runtime;
}
function assertSurfaceClean(f) {
  assert.equal(f.events.listeners.get('message')?.size, 0);
  assert.equal(f.events.listeners.get('pagehide')?.size, 0);
  assert.equal(f.documentEvents.listeners.get('visibilitychange')?.size, 0);
  assert.equal(f.frames.size, 0); assert.equal(f.timers.size, 0);
  assert.ok(f.root.children.every(host => host.removed));
  assert.ok(f.calls.panoramas.every(pano => !pano.visible && [...pano.listeners.values()].every(listeners => !listeners.size)));
}

test('view-mode input is bounded and optional legacy camera messages remain accepted', () => {
  const parent = {}, context = {parent, ownOrigin: origin};
  for (const viewMode of ['street', 'earth']) assert.equal(parseCameraMessage(message(parent, {data: {
    type: 'korlix-projection-camera', camera: {...camera, viewMode}, place: selected}}), context).camera.viewMode, viewMode);
  for (const viewMode of ['live', '', null, {}, ['street']]) assert.equal(parseCameraMessage(message(parent, {data: {
    type: 'korlix-projection-camera', camera: {...camera, viewMode}, place: selected}}), context), null);
  assert.equal(parseCameraMessage(message(parent), context).camera.viewMode, undefined);
});

test('SDK bootstrap preserves nonce/origin policy and defers all viewer imports', async () => {
  const f = surfaceFixture(), abort = new AbortController();
  const promise = loadGoogleMapsLibrary({...f, key: 'public-fixture-key', signal: abort.signal});
  const script = f.scripts[0], url = new URL(script.src);
  assert.equal(url.origin, 'https://maps.googleapis.com'); assert.equal(url.pathname, '/maps/api/js');
  assert.equal(url.searchParams.get('v'), 'quarterly'); assert.equal(url.searchParams.get('auth_referrer_policy'), 'origin');
  assert.equal(script.nonce, 'fixture-csp-nonce'); assert.equal(script.referrerPolicy, 'strict-origin-when-cross-origin');
  f.window.__korlixMapsReady();
  const api = await promise;
  assert.deepEqual(f.calls.imports, []);
  await api.importLibrary('streetView'); assert.deepEqual(f.calls.imports, ['streetView']);
  abort.abort();
});

test('loader errors and aborts never expose URLs/key values or revive a late load', async () => {
  for (const reason of ['script', 'abort', 'pre-abort']) {
    const f = surfaceFixture(), abort = new AbortController();
    if (reason === 'pre-abort') abort.abort();
    const loading = loadGoogleMapsLibrary({...f, key: 'secret-key', signal: abort.signal});
    const rejected = assert.rejects(loading, error => !/secret|http|provider/.test(error.message));
    const callback = f.window.__korlixMapsReady;
    if (reason === 'script') f.scripts[0].onerror();
    if (reason === 'abort') abort.abort();
    callback?.(); await rejected;
    assert.ok(f.scripts.every(script => script.removed));
  }
});

test('transport handshake precedes SDK load and legacy ready is explicitly awaiting a destination', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  assert.ok(f.calls.order.indexOf('korlix-projection-transport-ready') < f.calls.order.indexOf('sdk-load'));
  await flush();
  assert.equal(latestView(f).reason, 'awaiting-destination');
  assert.equal(f.calls.panoramas.length, 0); assert.equal(f.calls.maps.length, 0); assert.equal(f.calls.imports.length, 0);
  assert.equal(f.state.hidden, false);
  runtime.dispose(); assertSurfaceClean(f);
});

test('legacy destination defaults to bounded outdoor Street View, faces target and displays its recorded date', async () => {
  const f = surfaceFixture(), runtime = await openStreetFixture(f);
  assert.deepEqual(f.calls.imports, ['streetView']); assert.equal(f.calls.maps.length, 0);
  assert.deepEqual(f.calls.queries[0].request, {location: {lat: 40.7, lng: -73.9}, radius: 50, preference: 'nearest', sources: ['google', 'outdoor']});
  const pano = f.calls.panoramas[0];
  assert.equal(pano.pov.heading, 0); assert.equal(pano.pov.pitch, 0); assert.equal(pano.zoom, 1); assert.equal(pano.visible, true);
  assert.equal(pano.options.imageDateControl, true); assert.equal(pano.options.motionTracking, false);
  assert.match(f.label.textContent, /Captured 2026-06/); assert.match(f.label.textContent, /Not live/);
  assert.equal(latestView(f).viewMode, 'street'); assert.equal(latestView(f).sequence, 1); assert.equal(latestView(f).status, 'ready');
  assert.equal(headingToProperty({lat: 0, lng: 0}, {lat: 0, lng: 1}), 90);
  assert.equal(headingToProperty({lat: 0, lng: 0}, {lat: -1, lng: 0}), 180);
  runtime.dispose(); assertSurfaceClean(f);
});

test('a service match does not report viewer readiness before the matching panorama status', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  f.send(1); await flush(); f.reply(0); await flush();
  assert.equal(latestView(f).status, 'loading');
  const pano = f.calls.panoramas[0];
  pano.ready('OK', 'stale-id'); assert.equal(latestView(f).status, 'loading');
  pano.ready('OK', 'pano-0'); assert.equal(latestView(f).status, 'ready');
  runtime.dispose();
});

test('a panorama that waits for visibility can finish its initial and reused destination loads', async () => {
  const f = surfaceFixture({readyWhenVisible: true}), runtime = mountProjectionRenderer(f);
  f.send(1); await flush(); f.reply(0); await flush();
  assert.equal(latestView(f).status, 'ready');
  assert.equal(latestView(f).sequence, 1);
  assert.equal(f.calls.panoramas[0].visible, true);
  assert.equal(f.timers.size, 0);
  f.send(2); await flush(); f.reply(1, {pano: 'second'}); await flush();
  assert.equal(latestView(f).status, 'ready');
  assert.equal(latestView(f).sequence, 2);
  assert.equal(f.calls.panoramas.length, 1);
  assert.equal(f.calls.panoramas[0].pano, 'second');
  assert.equal(f.calls.panoramas[0].visible, true);
  assert.equal(f.timers.size, 0);
  runtime.dispose();
});

test('a synchronous setPano failure cannot be made visible by the pending open operation', async () => {
  const f = surfaceFixture({setPanoFailure: true}), runtime = mountProjectionRenderer(f);
  f.send(1); await flush(); f.reply(0); await flush();
  assert.equal(latestView(f).status, 'error');
  assert.equal(f.calls.panoramas[0].visible, false);
  assert.equal(f.calls.panoramas[0].host.hidden, true);
  assert.equal(statusPosts(f).some(([value]) => value.status === 'ready' && value.reason === 'ready'), false);
  runtime.dispose();
});

test('no coverage retries at 100m then offers explicit Earth without creating an overhead map', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  f.send(1); await flush(); f.reply(0, {status: 'ZERO_RESULTS'}); await flush();
  assert.equal(f.calls.queries[1].request.radius, 100);
  f.reply(1, {status: 'ZERO_RESULTS'}); await flush();
  assert.equal(latestView(f).reason, 'no-coverage'); assert.match(f.state.textContent, /Choose 3D Earth/);
  assert.equal(f.calls.maps.length, 0); assert.equal(f.calls.panoramas.length, 0);
  assert.deepEqual(f.calls.imports, ['streetView']); runtime.dispose();
});

test('unknown provider failures and invalid/out-of-radius metadata are not claimed as missing coverage', async () => {
  for (const result of [{status: 'UNKNOWN_ERROR'}, {position: {lat: 0, lng: 0}}, {pano: '<script>'}]) {
    const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
    f.send(1); await flush(); f.reply(0, result); await flush();
    assert.equal(latestView(f).reason, 'unavailable'); assert.equal(f.calls.queries.length, 1);
    assert.doesNotMatch(JSON.stringify(f.posts), /private-fixture-key|secret|<script>/); runtime.dispose();
  }
});

test('late A lookup cannot replace B, and invalid source/stale sequence cannot replace the selected destination', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  f.send(1); await flush();
  f.send(2, 'flyTo', {}, {...selected, id: 'B', latitude: 40.71}); await flush();
  f.reply(1, {pano: 'B', position: {lat: 40.7099, lng: -73.9}}); await flush();
  f.calls.panoramas[0].ready();
  f.reply(0, {pano: 'A'}); await flush();
  assert.equal(f.calls.panoramas[0].getPano(), 'B'); assert.equal(latestView(f).sequence, 2);
  const count = f.calls.queries.length;
  f.send(1); f.events.emit('message', message({})); await flush();
  assert.equal(f.calls.queries.length, count); runtime.dispose();
});

test('stop during SDK or panorama lookup cancels work and never shows a late destination', async () => {
  for (const phase of ['sdk', 'lookup', 'display']) {
    const pending = deferred(), f = surfaceFixture({sdkDeferred: phase === 'sdk' ? pending : null});
    const runtime = mountProjectionRenderer(f); f.send(1); await flush();
    if (phase === 'display') { f.reply(0); await flush(); }
    f.send(2, 'stopCamera', {}, null);
    if (phase === 'sdk') pending.resolve(f.api);
    if (phase === 'lookup') f.reply(0);
    if (phase === 'display') f.calls.panoramas[0].ready();
    await flush();
    assert.equal(latestView(f).reason, 'interrupted'); assert.equal(latestView(f).sequence, 2);
    assert.ok(f.calls.panoramas.every(p => !p.visible)); assert.equal(f.calls.maps.length, 0);
    assert.equal(cameraStatuses(f).at(-1).sequence, 2);
    runtime.dispose(); assertSurfaceClean(f);
  }
});

test('a newer destination can recover after stop or absent coverage and reuse a single panorama object', async () => {
  const f = surfaceFixture(), runtime = await openStreetFixture(f);
  f.send(2); await flush(); f.reply(1, {pano: 'second', date: '2025-12'}); await flush(); f.calls.panoramas[0].ready();
  assert.equal(f.calls.panoramas.length, 1); assert.equal(f.calls.panoramas[0].pano, 'second');
  assert.match(f.label.textContent, /2025-12/);
  f.send(3); await flush(); f.send(4, 'stopCamera', {}, null); f.reply(2, {pano: 'canceled'}); await flush();
  f.send(5); await flush(); f.reply(3, {pano: 'latest'}); await flush(); f.calls.panoramas[0].ready();
  assert.equal(f.calls.panoramas.length, 1); assert.equal(latestView(f).sequence, 5); assert.equal(latestView(f).status, 'ready');
  runtime.dispose();
});

test('continuous panorama zoom detects provider clamp and stops without infinite requests', async () => {
  const f = surfaceFixture({maxZoom: 2}), runtime = await openStreetFixture(f);
  f.send(2, 'zoomInContinuous', {}, null);
  for (let i = 0; i < 300; i++) f.tick();
  assert.equal(f.calls.panoramas[0].zoom, 2); assert.equal(f.frames.size, 0);
  assert.deepEqual(cameraStatuses(f).at(-1), {type: 'korlix-projection-camera-status', state: 'limit', reason: 'closest', sequence: 2, viewMode: 'street'});
  f.send(3, 'zoomOutContinuous', {}, null);
  for (let i = 0; i < 300; i++) f.tick();
  assert.equal(f.calls.panoramas[0].zoom, 0); assert.equal(cameraStatuses(f).at(-1).reason, 'farthest');
  runtime.dispose();
});

test('Stop, manual input and background cancel panorama zoom without resuming on return', async () => {
  for (const method of ['stop', 'pointerdown', 'touchstart', 'wheel', 'hidden']) {
    const f = surfaceFixture(), runtime = await openStreetFixture(f);
    f.send(2, 'zoomInContinuous', {}, null); f.tick(); f.tick();
    const stale = [...f.frames.values()][0];
    if (method === 'stop') f.send(3, 'stopCamera', {}, null);
    else if (method === 'hidden') { f.hidden(true); f.hidden(false); }
    else f.gestures(method);
    const stopped = f.calls.panoramas[0].zoom;
    stale(999); for (let i = 0; i < 20; i++) f.tick();
    assert.equal(f.calls.panoramas[0].zoom, stopped); assert.equal(f.frames.size, 0);
    assert.equal(cameraStatuses(f).at(-1).state, 'stopped');
    assert.equal(latestView(f).status, 'ready');
    runtime.dispose(); assertSurfaceClean(f);
  }
});

test('Earth loads only on explicit selection; Street return restores recorded panorama and mode-specific statuses', async () => {
  const f = surfaceFixture(), runtime = await openStreetFixture(f);
  f.send(2, 'flyTo', {viewMode: 'earth'}); await flush();
  assert.deepEqual(f.calls.imports, ['streetView', 'maps3d']); assert.equal(f.calls.maps.length, 1);
  assert.equal(latestView(f).status, 'loading');
  f.calls.maps[0].steady(); assert.equal(latestView(f).status, 'ready'); assert.equal(latestView(f).viewMode, 'earth');
  f.send(3, 'zoomInContinuous', {viewMode: 'earth'}, null); f.tick(); f.tick();
  f.send(4, 'flyTo', {viewMode: 'street'}); await flush(); assert.equal(f.frames.size, 0);
  f.reply(1, {pano: 'pano-0'}); await flush();
  assert.equal(latestView(f).status, 'ready'); assert.equal(latestView(f).viewMode, 'street');
  assert.equal(f.calls.panoramas.length, 1); assert.equal(f.calls.maps.length, 1);
  f.calls.maps[0].steady(); assert.equal(latestView(f).viewMode, 'street');
  runtime.dispose(); assertSurfaceClean(f);
});

test('Earth keeps animation altitudeMode out of its constructor and flies to a terrain-relative destination after mounting', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  f.send(1, 'flyTo', {viewMode: 'earth', height: 850, pitch: -50}); await flush();
  assert.equal(latestView(f).status, 'loading');
  assert.equal(f.calls.maps.length, 1);
  const map = f.calls.maps[0];
  assert.equal('altitudeMode' in map.options, false);
  assert.equal(map.isConnected, true);
  assert.equal(map.flights.length, 1);
  assert.deepEqual(map.flights[0].endCamera, destinationCamera({...selected, height: 850, pitch: -50}));
  assert.equal(map.flights[0].endCamera.altitudeMode, 'RELATIVE_TO_GROUND');
  Object.assign(map, map.options);
  map.steady();
  assert.equal(latestView(f).status, 'loading', 'A steady constructor scene does not establish the requested destination.');
  Object.assign(map, map.flights[0].endCamera);
  map.steady();
  assert.equal(latestView(f).status, 'ready');
  assert.equal(latestView(f).viewMode, 'earth');
  runtime.dispose();
});

test('unknown dates stay unavailable and user panorama navigation cannot leave stale capture metadata', async () => {
  assert.equal(capturedMonth('2026-13'), null); assert.equal(capturedMonth('<script>'), null);
  const f = surfaceFixture(), runtime = await openStreetFixture(f), pano = f.calls.panoramas[0];
  pano.setPano('walked-to-pano');
  assert.match(f.label.textContent, /Capture date unavailable/);
  f.reply(1, {pano: 'walked-to-pano', date: '2024-10'}); await flush();
  assert.match(f.label.textContent, /2024-10/);
  pano.setPano('unknown-date'); f.reply(2, {pano: 'unknown-date', date: 'invalid'}); await flush();
  assert.match(f.label.textContent, /Capture date unavailable/);
  runtime.dispose();
});

test('display deadline, missing configuration, imports and auth failures are sanitized and do not auto-fallback', async () => {
  for (const cause of ['deadline', 'missing', 'import', 'auth']) {
    const f = surfaceFixture({key: cause === 'missing' ? '' : 'public-fixture-key', importFailure: cause === 'import'});
    const runtime = mountProjectionRenderer(f); f.send(1); await flush();
    if (cause === 'deadline') for (const timer of [...f.timers.values()]) timer.callback();
    if (cause === 'auth') f.window.gm_authFailure();
    await flush();
    assert.equal(latestView(f).status, 'error'); assert.equal(f.calls.maps.length, 0);
    assert.doesNotMatch(JSON.stringify(f.posts), /public-fixture-key|secret|provider body/);
    runtime.dispose(); assertSurfaceClean(f);
  }
});

test('closing during a pending lookup prevents late viewer construction and restores auth callback', async () => {
  const f = surfaceFixture(), previous = () => {};
  f.window.gm_authFailure = previous;
  mountProjectionRenderer(f); f.send(1); await flush();
  const late = f.window.gm_authFailure;
  f.close(); f.reply(0); late(); await flush();
  assert.equal(f.calls.panoramas.length, 0); assert.equal(f.window.gm_authFailure, previous);
  assertSurfaceClean(f);
});

test('callback-and-promise service implementations settle once and sanitize rejected provider details', async () => {
  const answer = await requestPanorama({getPanorama(_request, callback) {
    callback(null, 'ZERO_RESULTS'); return Promise.reject(Error('secret-provider-detail'));
  }}, {location: {lat: 1, lng: 2}});
  assert.deepEqual(answer, {data: null, status: 'ZERO_RESULTS'});
});

test('current provider and controller failures after a relative move carry the newest camera sequence', async () => {
  for (const cause of ['auth', 'camera']) {
    const f = surfaceFixture(), runtime = await openStreetFixture(f);
    f.send(2, 'closer', {}, null);
    if (cause === 'auth') f.window.gm_authFailure();
    else { f.calls.panoramas[0].zoom = NaN; f.tick(); }
    assert.equal(latestView(f).status, 'error'); assert.equal(latestView(f).sequence, 2);
    runtime.dispose();
  }
});

test('explicit panorama failures after readiness disable imagery using the current sequence', async () => {
  for (const status of ['ZERO_RESULTS', 'UNKNOWN_ERROR']) {
    const f = surfaceFixture(), runtime = await openStreetFixture(f);
    f.send(2, 'closer', {}, null);
    f.calls.panoramas[0].ready(status);
    assert.equal(latestView(f).status, 'error'); assert.equal(latestView(f).sequence, 2);
    assert.equal(latestView(f).reason, status === 'ZERO_RESULTS' ? 'no-coverage' : 'unavailable');
    assert.equal(f.calls.panoramas[0].visible, false); assert.equal(f.frames.size, 0);
    runtime.dispose();
  }
});

test('a partial provider zoom clamp finishes a single step and reports the actual closest view', async () => {
  const f = surfaceFixture({maxZoom: 1.2}), runtime = await openStreetFixture(f);
  f.send(2, 'closer', {}, null);
  for (let i = 0; i < 100; i++) f.tick();
  assert.equal(f.calls.panoramas[0].zoom, 1.2); assert.equal(f.frames.size, 0);
  assert.equal(cameraStatuses(f).at(-1).reason, 'closest');
  runtime.dispose();
});

test('an Earth stop failure is bounded and cannot prevent a later Street View selection', async () => {
  const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
  f.send(1, 'flyTo', {viewMode: 'earth'}); await flush(); f.calls.maps[0].steady();
  f.calls.maps[0].stopCameraAnimation = () => { throw Error('provider failure'); };
  f.send(2, 'closer', {viewMode: 'earth'}, null);
  assert.equal(latestView(f).status, 'error');
  f.send(3, 'flyTo', {viewMode: 'street'}); await flush(); f.reply(0); await flush(); f.calls.panoramas[0].ready();
  assert.equal(latestView(f).status, 'ready'); assert.equal(latestView(f).viewMode, 'street');
  runtime.dispose();
});

test('Stop, pointer and background interrupt an Earth destination flight before its steady event', async () => {
  for (const cause of ['stop', 'pointer', 'background']) {
    const f = surfaceFixture(), runtime = mountProjectionRenderer(f);
    f.send(1, 'flyTo', {viewMode: 'earth'}); await flush(); f.calls.maps[0].steady();
    f.send(2, 'flyTo', {viewMode: 'earth'}, {...selected, latitude: 40.71}); await flush();
    const map = f.calls.maps[0], previousStops = map.stops;
    assert.equal(map.flights.length, 2); assert.equal(latestView(f).status, 'loading');
    if (cause === 'stop') f.send(3, 'stopCamera', {viewMode: 'earth'}, null);
    else if (cause === 'pointer') f.gestures();
    else f.hidden(true);
    assert.ok(map.stops > previousStops, 'The in-progress SDK flight must be stopped, not only hidden.');
    map.steady(); await flush();
    assert.equal(latestView(f).reason, 'interrupted');
    assert.equal(cameraStatuses(f).at(-1).reason, cause === 'stop' ? 'stopped' : 'interrupted');
    runtime.dispose();
  }
});
