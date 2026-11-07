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

export function createCameraController({Cesium, viewer}) {
  let selected = null;
  const start = {latitude: 20, longitude: -25, height: 22000000, heading: 0, pitch: -90};
  function fly(value, duration = 1.2) {
    viewer.camera.cancelFlight();
    viewer.camera.flyTo({destination: Cesium.Cartesian3.fromDegrees(value.longitude, value.latitude, value.height),
      orientation: {heading: Cesium.Math.toRadians(value.heading || 0), pitch: Cesium.Math.toRadians(value.pitch ?? -50), roll: 0}, duration});
    viewer.scene.requestRender();
  }
  function apply({camera, place}) {
    if (place) selected = place;
    const position = viewer.camera.positionCartographic;
    const current = {latitude: Cesium.Math.toDegrees(position.latitude), longitude: Cesium.Math.toDegrees(position.longitude),
      height: position.height, heading: Cesium.Math.toDegrees(viewer.camera.heading), pitch: Cesium.Math.toDegrees(viewer.camera.pitch)};
    switch (camera.operation) {
      case 'flyTo':
        fly({latitude: camera.latitude ?? selected.latitude, longitude: camera.longitude ?? selected.longitude,
          height: camera.height ?? 650, heading: camera.heading ?? 0, pitch: camera.pitch ?? -50});
        break;
      case 'reset':
        fly(selected ? {...selected, height: 650, heading: 0, pitch: -50} : start);
        break;
      case 'closer':
      case 'farther': {
        // Move along the current view ray, preserving the building in view.
        viewer.camera.cancelFlight();
        const amount = Math.max(10, current.height * 0.35);
        if (camera.operation === 'closer' && current.height > 45) viewer.camera.zoomIn(Math.min(amount, current.height - 35));
        if (camera.operation === 'farther' && current.height < 40000000) viewer.camera.zoomOut(Math.min(amount, 40000000 - current.height));
        viewer.scene.requestRender();
        break;
      }
      case 'left':
      case 'right':
        fly({...current, heading: current.heading + (camera.operation === 'left' ? -18 : 18)}, .5);
        break;
    }
  }
  return {apply, reset: () => fly(start, 0)};
}
