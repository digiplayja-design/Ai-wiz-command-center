const operations = new Set(['closer', 'farther', 'left', 'right', 'reset', 'flyTo',
  'zoomInContinuous', 'zoomOutContinuous', 'stopCamera']);
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const numberIn = (value, low, high) => typeof value === 'number' && Number.isFinite(value) && value >= low && value <= high;
const safeText = (value, max) => typeof value === 'string' && value.length <= max && !/[\u0000-\u001f\u007f<>]/u.test(value);

// No URL, native method, credential, account or arbitrary JavaScript is accepted.
// The local bundled parent has an opaque ("null") origin; source identity is
// required, and an HTTPS parent is restricted to this document's own origin.
export function parseCameraMessage(event, {parent, ownOrigin, lastSequence = -1}) {
  if (event.source !== parent || !['null', ownOrigin].includes(event.origin)) return null;
  const value = event.data;
  if (!record(value) || value.type !== 'korlix-projection-camera' || !record(value.camera)) return null;
  const raw = value.camera;
  if (!operations.has(raw.operation) || !Number.isSafeInteger(raw.sequence) || raw.sequence < 0 || raw.sequence <= lastSequence) return null;
  const camera = {operation: raw.operation, sequence: raw.sequence};
  for (const [name, low, high] of [['latitude', -90, 90], ['longitude', -180, 180],
    ['height', 1, 40000000], ['heading', -360, 360], ['pitch', -90, 0]]) {
    if (raw[name] === undefined || raw[name] === null) continue;
    if (!numberIn(raw[name], low, high)) return null;
    camera[name] = raw[name];
  }
  let place = null;
  if (value.place !== undefined && value.place !== null) {
    const selected = value.place;
    if (!record(selected) || !safeText(selected.id, 240) || !selected.id || !safeText(selected.label, 400) ||
        !numberIn(selected.latitude, -90, 90) || !numberIn(selected.longitude, -180, 180)) return null;
    place = {id: selected.id, label: selected.label, latitude: selected.latitude, longitude: selected.longitude};
  }
  if (camera.operation === 'flyTo' && !place && (camera.latitude === undefined || camera.longitude === undefined)) return null;
  return {camera, place};
}

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const heading = value => ((value % 360) + 360) % 360;
const maxRange = 40000000;
// These are application navigation bounds, not Google imagery/detail limits.
// A positive one-metre vertical standoff avoids a zero-range camera and removes
// our previous 25 m/35 m close-view cap. Google still enforces terrain/camera
// constraints; moving nearer cannot create detail absent from its imagery.
export const MIN_CAMERA_ALTITUDE = 1;
const minimumRange = tilt => MIN_CAMERA_ALTITUDE / Math.cos(tilt * Math.PI / 180);
const start = {center: {lat: 20, lng: -25, altitude: 0}, range: 22000000, heading: 0, tilt: 0, roll: 0};

export function initialCameraOptions() {
  return {...start, center: {...start.center}};
}

// Quarterly v3.65 CameraOptions supports terrain-relative centers and range:
// https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map#CameraOptions
// https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map-draw#AltitudeMode
// Legacy "height" is a compatibility standoff hint, not a surveyed elevation.
// Center the requested place on terrain; putting the camera directly above its
// coordinates while tilting would point past the requested building.
function destination(value) {
  const tilt = clamp(90 + (value.pitch ?? -50), 0, 85);
  return {center: {lat: value.latitude, lng: value.longitude, altitude: 0},
    altitudeMode: 'RELATIVE_TO_GROUND',
    range: clamp((value.height ?? 650) / Math.cos(tilt * Math.PI / 180), minimumRange(tilt), maxRange),
    heading: heading(value.heading ?? 0), tilt, roll: 0};
}

export function createCameraController({map, reducedMotion = false, onError = () => {}, onStatus = () => {},
  requestFrame = callback => globalThis.requestAnimationFrame(callback),
  cancelFrame = id => globalThis.cancelAnimationFrame(id)}) {
  let selected = null, disposed = false, generation = 0, frame = null;
  let activeSequence = null, interruptible = false;
  const report = (state, reason, sequence = activeSequence) => {
    if (!disposed && Number.isSafeInteger(sequence) && sequence >= 0) onStatus({state, reason, sequence});
  };
  function cancelLoop() {
    if (frame !== null) cancelFrame(frame);
    frame = null;
  }
  function current() {
    const center = map.center;
    if (!center || !numberIn(center.lat, -90, 90) || !numberIn(center.lng, -180, 180) ||
        !Number.isFinite(center.altitude) || !Number.isFinite(map.range) || map.range < 0 ||
        !Number.isFinite(map.heading) || !Number.isFinite(map.tilt)) {
      throw new Error('Map camera state unavailable.');
    }
    // The SDK's current center is absolute MSL, including after touch gestures.
    return {center: {lat: center.lat, lng: center.lng, altitude: center.altitude},
      altitudeMode: 'ABSOLUTE', range: map.range,
      heading: heading(map.heading), tilt: clamp(map.tilt, 0, 85), roll: 0};
  }
  function begin(sequence, perform, canInterrupt = true) {
    if (disposed) return;
    cancelLoop();
    const token = ++generation;
    activeSequence = sequence;
    interruptible = canInterrupt;
    const rejected = () => {
      if (disposed || generation !== token) return;
      cancelLoop();
      interruptible = false;
      generation++;
      onError();
    };
    const afterStop = () => {
      if (disposed || generation !== token) return;
      try { perform(token, rejected); } catch { rejected(); }
    };
    try {
      const stopped = map.stopCameraAnimation();
      if (stopped?.then) void Promise.resolve(stopped).then(afterStop, rejected);
      else afterStop();
    } catch { rejected(); }
  }
  function move(sequence, makeCamera, durationMillis) {
    begin(sequence, (_token, rejected) => {
      const endCamera = makeCamera();
      if (!endCamera) return;
      const flight = map.flyCameraTo({endCamera, durationMillis: reducedMotion ? 0 : durationMillis});
      // Public methods may return void. Absorb asynchronous rejections without
      // allowing a superseded flight to fail a newer command.
      if (flight?.then) void Promise.resolve(flight).catch(rejected);
    });
  }
  function limit(reason) {
    cancelLoop();
    interruptible = false;
    report('limit', reason);
  }
  function stop(reason = 'interrupted', sequence = activeSequence) {
    begin(sequence, () => report('stopped', reason, sequence), false);
  }
  function interrupt() {
    // A touch can also emit pointerdown and many wheel events. Cancel our work
    // once, then leave the SDK's own gesture handling alone until a new command.
    if (interruptible) stop();
  }
  function zoomContinuously(sequence, direction) {
    begin(sequence, (token, rejected) => {
      let previousTime = null, previousRange = null, stalledMillis = 0;
      const reason = direction < 0 ? 'closest' : 'farthest';
      const speed = reducedMotion ? .45 : .8;
      function schedule() {
        const id = requestFrame(timestamp => {
          // A cancelled callback must not clear a newer command's frame ID.
          if (disposed || generation !== token) return;
          if (frame === id) frame = null;
          tick(timestamp);
        });
        frame = id;
      }
      function tick(timestamp) {
        try {
          if (!Number.isFinite(timestamp)) throw new Error('Camera clock unavailable.');
          const view = current(), minimum = minimumRange(view.tilt);
          if ((direction < 0 && view.range <= minimum) || (direction > 0 && view.range >= maxRange)) {
            limit(reason);
            return;
          }
          // Bound each frame's movement so a suspended/slow frame never jumps
          // through the scene. Visibility changes independently cancel the loop.
          const elapsed = previousTime === null ? 0 : clamp(timestamp - previousTime, 0, 64);
          previousTime = timestamp;
          if (previousRange !== null && Math.abs(view.range - previousRange) <= Math.max(1e-5, view.range * 1e-6)) {
            stalledMillis += elapsed;
          } else stalledMillis = 0;
          previousRange = view.range;
          // The SDK can clamp sooner than our navigation bound. Stop instead of
          // scheduling forever against a camera that is no longer moving.
          if (stalledMillis >= 1000) { limit(reason); return; }
          if (elapsed > 0) {
            const scaled = (view.range > 0 ? view.range : MIN_CAMERA_ALTITUDE) * Math.exp(direction * speed * elapsed / 1000);
            // A gesture may leave the public camera outside our own bounds.
            // Move smoothly back toward them instead of snapping to the far
            // bound during zoom-in or to the near bound during zoom-out.
            const range = direction < 0 ? Math.max(minimum, scaled) : Math.min(maxRange, scaled);
            // Public range setter keeps the SDK's current center/altitude,
            // heading and tilt intact; no repeated fly animations or rebasing.
            map.range = range;
            if (range === (direction < 0 ? minimum : maxRange)) { limit(reason); return; }
          }
          schedule();
        } catch { rejected(); }
      }
      schedule();
    });
  }
  function apply({camera, place}) {
    if (disposed) return;
    if (place) selected = {...place};
    switch (camera.operation) {
      case 'flyTo': {
        const target = destination({latitude: camera.latitude ?? selected?.latitude,
          longitude: camera.longitude ?? selected?.longitude, height: camera.height,
          heading: camera.heading, pitch: camera.pitch});
        move(camera.sequence, () => target, 1200);
        break;
      }
      case 'reset': {
        const target = selected ? destination(selected) : {...initialCameraOptions(), altitudeMode: 'ABSOLUTE'};
        move(camera.sequence, () => target, 1200);
        break;
      }
      case 'closer':
      case 'farther':
        move(camera.sequence, () => {
          const view = current();
          const minimum = minimumRange(view.tilt);
          if ((camera.operation === 'closer' && view.range <= minimum) ||
              (camera.operation === 'farther' && view.range >= maxRange)) {
            limit(camera.operation === 'closer' ? 'closest' : 'farthest');
            return null;
          }
          const scaled = (view.range > 0 ? view.range : MIN_CAMERA_ALTITUDE) * (camera.operation === 'closer' ? .65 : 1.35);
          const range = camera.operation === 'closer' ? Math.max(minimum, scaled) : Math.min(maxRange, scaled);
          return range === view.range ? null : {...view, range};
        }, 500);
        break;
      case 'left':
      case 'right':
        move(camera.sequence, () => {
          const view = current();
          return {...view, heading: heading(view.heading + (camera.operation === 'left' ? -18 : 18))};
        }, 500);
        break;
      case 'zoomInContinuous':
      case 'zoomOutContinuous':
        zoomContinuously(camera.sequence, camera.operation === 'zoomInContinuous' ? -1 : 1);
        break;
      case 'stopCamera':
        stop('stopped', camera.sequence);
        break;
    }
  }
  function dispose() {
    if (disposed) return;
    cancelLoop();
    disposed = true;
    interruptible = false;
    generation++;
    try {
      const stopped = map.stopCameraAnimation();
      if (stopped?.then) void Promise.resolve(stopped).catch(() => {});
    } catch { /* The document is closing; never surface provider diagnostics. */ }
  }
  return {apply, stop, interrupt, dispose};
}
