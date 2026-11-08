import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCameraMessage, createCameraController} from '../brain_projection/public/camera.mjs';
import {mountProjectionRenderer} from '../brain_projection/public/earth.mjs';

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

function eventBus() {
  const listeners = new Set();
  return {addEventListener: callback => {listeners.add(callback); return () => listeners.delete(callback);},
    emit: (...args) => {for (const callback of [...listeners]) callback(...args);}, size: () => listeners.size};
}
function fakeBrowser({key = 'public-test-key', loadTiles, viewerThrows = false} = {}) {
  const posts = [], events = new Map(), documentEvents = new Map(), timers = new Map(), observers = [];
  const state = {hidden: false, textContent: ''};
  const credits = {height: 32, getBoundingClientRect() {return {height: this.height};}};
  const add = (map, name, callback) => {
    if (!map.has(name)) map.set(name, new Set());
    map.get(name).add(callback);
  };
  const remove = (map, name, callback) => map.get(name)?.delete(callback);
  const win = {location: {origin}, devicePixelRatio: 2, innerHeight: 600,
    parent: {postMessage: (...args) => posts.push(args)},
    ResizeObserver: class {
      constructor(callback) {this.callback = callback; this.disconnected = false; observers.push(this);}
      observe(target) {this.target = target;}
      disconnect() {this.disconnected = true;}
    },
    addEventListener: (name, callback) => add(events, name, callback),
    removeEventListener: (name, callback) => remove(events, name, callback),
    setTimeout: callback => {const id = timers.size + 1; timers.set(id, callback); return id;},
    clearTimeout: id => timers.delete(id)};
  const doc = {getElementById: name => name === 'map-state' ? state : credits,
    querySelector: () => ({content: key}),
    addEventListener: (name, callback) => add(documentEvents, name, callback),
    removeEventListener: (name, callback) => remove(documentEvents, name, callback)};
  const tiles = {tileFailed: eventBus(), destroyed: false,
    isDestroyed() {return this.destroyed;}, destroy() {this.destroyed = true;}};
  const calls = {viewers: [], tiles: [], flights: [], zooms: [], cancellations: 0, credits: []};
  const C = {
    Ion: {defaultAccessToken: 'default-should-be-cleared'},
    Viewer: class {
      constructor(id, options) {
        if (viewerThrows) throw Error('private WebGL diagnostics');
        this.id = id; this.options = options; this.destroyed = false;
        this.camera = {positionCartographic: {latitude: .7, longitude: -1.2, height: 1000}, heading: 0, pitch: -.8,
          cancelFlight: () => {calls.cancellations++;}, flyTo: input => calls.flights.push(input),
          zoomIn: distance => calls.zooms.push(['in', distance]), zoomOut: distance => calls.zooms.push(['out', distance])};
        this.scene = {backgroundColor: null, renderError: eventBus(), postRender: eventBus(),
          primitives: {add: value => calls.tiles.push(value)}, requestRender: () => {}};
        this.creditDisplay = {addStaticCredit: value => calls.credits.push(value)};
        calls.viewers.push(this);
      }
      isDestroyed() {return this.destroyed;}
      destroy() {this.destroyed = true;}
    },
    Credit: class {constructor(text, onScreen) {this.text = text; this.onScreen = onScreen;}},
    createGooglePhotorealistic3DTileset: (...args) => loadTiles ? loadTiles(...args) : Promise.resolve(tiles),
    Cartesian3: {fromDegrees: (longitude, latitude, height) => ({longitude, latitude, height})},
    Math: {toRadians: degrees => degrees * Math.PI / 180, toDegrees: radians => radians * 180 / Math.PI},
    Color: {fromCssColorString: css => css},
  };
  const emit = (name, value) => {for (const callback of [...(events.get(name) || [])]) callback(value);};
  return {window: win, document: doc, Cesium: C, posts, state, credits, calls, tiles, events, documentEvents, timers, observers, emit};
}
const statusPosts = fixture => fixture.posts.filter(post => post[0].type === 'korlix-projection-status');
const creditPosts = fixture => fixture.posts.filter(post => post[0].type === 'korlix-projection-credits');

test('real renderer lifecycle reports loading then ready, uses Google-only base and preserves credits', async () => {
  let providerArguments;
  const f = fakeBrowser();
  f.Cesium.createGooglePhotorealistic3DTileset = async (...args) => {providerArguments = args; return f.tiles;};
  const runtime = await mountProjectionRenderer(f);
  assert.deepEqual(statusPosts(f).map(post => post[0].status), ['loading', 'ready']);
  assert.ok(f.posts.every(post => ['korlix-projection-status', 'korlix-projection-credits'].includes(post[0].type) && post[1] === '*'));
  assert.doesNotMatch(JSON.stringify(f.posts), /public-test-key|Authorization|nonce/);
  assert.equal(f.Cesium.Ion.defaultAccessToken, '');
  const viewer = f.calls.viewers[0];
  assert.equal(viewer.options.globe, false);
  assert.equal(viewer.options.baseLayer, false);
  assert.equal(viewer.options.geocoder, false);
  assert.equal(viewer.options.creditContainer, f.document.getElementById('map-credits'));
  assert.equal(providerArguments[0].onlyUsingWithGoogleGeocoder, true);
  assert.equal(providerArguments[1].showCreditsOnScreen, true);
  assert.equal(f.calls.credits[0].text, 'Google Maps');
  assert.equal(f.calls.credits[0].onScreen, true);
  assert.equal(f.state.hidden, true);
  assert.equal(f.timers.size, 0);
  runtime.dispose();
  assert.equal(viewer.isDestroyed(), true);
  assert.equal(f.events.get('message').size, 0);
  assert.equal(f.documentEvents.get('click').size, 0);
  assert.equal(f.events.get('resize').size, 0);
  assert.ok(f.observers.every(observer => observer.disconnected));
  runtime.dispose();
});

test('wrapping attribution reports only bounded changed geometry and disconnects on disposal', async () => {
  const f = fakeBrowser();
  const runtime = await mountProjectionRenderer(f);
  const observer = f.observers[0];
  assert.equal(observer.target, f.credits);
  assert.deepEqual(creditPosts(f).map(post => post[0]), [{type: 'korlix-projection-credits', height: 32}]);
  f.credits.height = 104.25;
  observer.callback();
  assert.deepEqual(creditPosts(f).at(-1)[0], {type: 'korlix-projection-credits', height: 105});
  observer.callback();
  assert.equal(creditPosts(f).length, 2, 'Unchanged heights do not flood the parent');
  for (const height of [-1, NaN, Infinity]) {
    f.credits.height = height;
    observer.callback();
  }
  assert.equal(creditPosts(f).length, 2, 'Malformed measurements are never forwarded');
  f.credits.height = 100000;
  observer.callback();
  assert.equal(creditPosts(f).at(-1)[0].height, 600, 'Height cannot exceed the current renderer viewport');
  f.window.innerHeight = 420;
  f.emit('resize');
  assert.equal(creditPosts(f).at(-1)[0].height, 420);
  f.window.innerHeight = 100000;
  f.emit('resize');
  assert.equal(creditPosts(f).at(-1)[0].height, 4096, 'Geometry has an absolute protocol bound as well');
  const count = f.posts.length;
  runtime.dispose();
  assert.equal(observer.disconnected, true);
  assert.equal(f.events.get('resize').size, 0);
  f.credits.height = 20;
  observer.callback();
  f.emit('resize');
  assert.equal(f.posts.length, count, 'Already queued observer callbacks cannot revive a closed frame');
});

test('older WebViews observe credit changes after rendering and release the fallback listener', async () => {
  const f = fakeBrowser();
  delete f.window.ResizeObserver;
  const runtime = await mountProjectionRenderer(f);
  const event = f.calls.viewers[0].scene.postRender;
  f.credits.height = 88;
  event.emit();
  assert.equal(creditPosts(f).at(-1)[0].height, 88);
  runtime.dispose();
  assert.equal(event.size(), 0);
});

test('queued valid flyTo applies once ready; wrong source and replayed sequence do not move camera', async () => {
  let release;
  const f = fakeBrowser({loadTiles: () => new Promise(resolve => {release = resolve;})});
  const mounting = mountProjectionRenderer(f);
  f.emit('message', message(f.window.parent));
  assert.deepEqual(statusPosts(f).map(post => post[0].status), ['loading']);
  release(f.tiles);
  const runtime = await mounting;
  assert.deepEqual(f.calls.flights.at(-1).destination, {longitude: -73.9, latitude: 40.7, height: 650});
  const flights = f.calls.flights.length;
  f.emit('message', message(f.window.parent));
  f.emit('message', message({}, {data: {type: 'korlix-projection-camera', camera: {...camera, sequence: 2}}}));
  assert.equal(f.calls.flights.length, flights);
  f.emit('message', message(f.window.parent, {data: {type: 'korlix-projection-camera', camera: {sequence: 2, operation: 'closer'}}}));
  assert.equal(f.calls.zooms[0][0], 'in');
  runtime.dispose();
});

test('missing key or unavailable Cesium never claims a connected map', async () => {
  for (const f of [fakeBrowser({key: ''}), {...fakeBrowser(), Cesium: undefined}]) {
    const runtime = await mountProjectionRenderer(f);
    assert.deepEqual(statusPosts(f).map(post => post[0].status), ['loading', 'error']);
    assert.equal(f.state.hidden, false);
    assert.equal(f.calls.viewers.length, 0);
    runtime.dispose();
  }
});

test('failed provider, WebGL or tile error does not leak details and releases renderer resources', async () => {
  for (const f of [fakeBrowser({loadTiles: async () => {throw Error('key=secret-private-provider-url');}}),
    fakeBrowser({viewerThrows: true})]) {
    await mountProjectionRenderer(f);
    assert.deepEqual(statusPosts(f).map(post => post[0].status), ['loading', 'error']);
    assert.doesNotMatch(JSON.stringify(f.posts), /secret|private|WebGL diagnostics/);
    assert.equal(f.events.get('message').size, 0);
    assert.equal(f.timers.size, 0);
    assert.ok(f.calls.viewers.every(viewer => viewer.isDestroyed()));
  }
  const f = fakeBrowser();
  await mountProjectionRenderer(f);
  f.tiles.tileFailed.emit({message: 'private provider response'});
  assert.equal(f.posts.at(-1)[0].status, 'error');
  assert.equal(f.calls.viewers[0].isDestroyed(), true);
});

test('closing during tile load destroys late tiles and cannot emit a stale ready event', async () => {
  let release;
  const f = fakeBrowser({loadTiles: () => new Promise(resolve => {release = resolve;})});
  const mounting = mountProjectionRenderer(f);
  f.emit('pagehide');
  release(f.tiles);
  await mounting;
  assert.equal(f.calls.viewers[0].isDestroyed(), true);
  assert.equal(f.tiles.isDestroyed(), true);
  assert.deepEqual(statusPosts(f).map(post => post[0].status), ['loading']);
  assert.equal(f.events.get('message').size, 0);
});

test('tile connection deadline stops invisible provider work and blocks late readiness', async () => {
  let release;
  const f = fakeBrowser({loadTiles: () => new Promise(resolve => {release = resolve;})});
  const mounting = mountProjectionRenderer(f);
  [...f.timers.values()][0]();
  assert.equal(f.posts.at(-1)[0].status, 'error');
  release(f.tiles);
  await mounting;
  assert.equal(f.tiles.isDestroyed(), true);
  assert.equal(f.calls.viewers[0].isDestroyed(), true);
  assert.equal(f.posts.some(post => post[0].status === 'ready'), false);
});

test('camera controls preserve view direction, bounded zoom and reset to the confirmed place', () => {
  const f = fakeBrowser();
  const viewer = new f.Cesium.Viewer('map', {});
  const controller = createCameraController({Cesium: f.Cesium, viewer});
  controller.apply({camera, place: selected});
  controller.apply({camera: {operation: 'left'}, place: null});
  assert.ok(f.calls.flights.at(-1).orientation.heading < 0);
  controller.apply({camera: {operation: 'right'}, place: null});
  assert.ok(f.calls.flights.at(-1).orientation.heading > 0);
  controller.apply({camera: {operation: 'closer'}, place: null});
  controller.apply({camera: {operation: 'farther'}, place: null});
  assert.deepEqual(f.calls.zooms, [['in', 350], ['out', 350]]);
  viewer.camera.positionCartographic.height = 35;
  controller.apply({camera: {operation: 'closer'}, place: null});
  assert.equal(f.calls.zooms.length, 2);
  controller.apply({camera: {operation: 'reset'}, place: null});
  assert.deepEqual(f.calls.flights.at(-1).destination, {longitude: -73.9, latitude: 40.7, height: 650});
});
