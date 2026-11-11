const operations = new Set(['closer', 'farther', 'left', 'right', 'reset', 'flyTo']);
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
    ['height', 25, 40000000], ['heading', -360, 360], ['pitch', -90, 0]]) {
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
    range: clamp((value.height ?? 650) / Math.cos(tilt * Math.PI / 180), 35, maxRange),
    heading: heading(value.heading ?? 0), tilt, roll: 0};
}

export function createCameraController({map, reducedMotion = false, onError = () => {}}) {
  let selected = null, disposed = false, generation = 0;
  function current() {
    const center = map.center;
    if (!center || !numberIn(center.lat, -90, 90) || !numberIn(center.lng, -180, 180) ||
        !Number.isFinite(center.altitude) || !Number.isFinite(map.range) ||
        !Number.isFinite(map.heading) || !Number.isFinite(map.tilt)) {
      throw new Error('Map camera state unavailable.');
    }
    // The SDK's current center is absolute MSL, including after touch gestures.
    return {center: {lat: center.lat, lng: center.lng, altitude: center.altitude},
      altitudeMode: 'ABSOLUTE', range: clamp(map.range, 35, maxRange),
      heading: heading(map.heading), tilt: clamp(map.tilt, 0, 85), roll: 0};
  }
  function move(makeCamera, durationMillis) {
    if (disposed) return;
    const token = ++generation;
    const rejected = () => { if (!disposed && generation === token) onError(); };
    const perform = () => {
      if (disposed || generation !== token) return;
      try {
        const endCamera = makeCamera();
        if (!endCamera) return;
        const flight = map.flyCameraTo({endCamera, durationMillis: reducedMotion ? 0 : durationMillis});
        // Public methods may return void. Also absorb a rejected asynchronous
        // implementation without allowing an older flight to fail a new one.
        if (flight?.then) void Promise.resolve(flight).catch(rejected);
      } catch { rejected(); }
    };
    try {
      const stopped = map.stopCameraAnimation();
      if (stopped?.then) void Promise.resolve(stopped).then(perform, rejected);
      else perform();
    } catch { rejected(); }
  }
  function apply({camera, place}) {
    if (disposed) return;
    if (place) selected = {...place};
    switch (camera.operation) {
      case 'flyTo': {
        const target = destination({latitude: camera.latitude ?? selected?.latitude,
          longitude: camera.longitude ?? selected?.longitude, height: camera.height,
          heading: camera.heading, pitch: camera.pitch});
        move(() => target, 1200);
        break;
      }
      case 'reset': {
        const target = selected ? destination(selected) : {...initialCameraOptions(), altitudeMode: 'ABSOLUTE'};
        move(() => target, 1200);
        break;
      }
      case 'closer':
      case 'farther':
        move(() => {
          const view = current();
          const minimum = Math.max(35, 25 / Math.cos(view.tilt * Math.PI / 180));
          const range = clamp(view.range * (camera.operation === 'closer' ? .65 : 1.35), minimum, maxRange);
          return range === view.range ? null : {...view, range};
        }, 500);
        break;
      case 'left':
      case 'right':
        move(() => {
          const view = current();
          return {...view, heading: heading(view.heading + (camera.operation === 'left' ? -18 : 18))};
        }, 500);
        break;
    }
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    generation++;
    try {
      const stopped = map.stopCameraAnimation();
      if (stopped?.then) void Promise.resolve(stopped).catch(() => {});
    } catch { /* The document is closing; never surface provider diagnostics. */ }
  }
  return {apply, dispose};
}
