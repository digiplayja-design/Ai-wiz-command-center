// Street View is recorded photography. Camera movement changes the viewer's
// field of view; it cannot invent newer imagery or additional image detail.
const finite = value => typeof value === 'number' && Number.isFinite(value);
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const wrap = value => ((value % 360) + 360) % 360;

export function panoramaPosition(value) {
  try {
    const lat = typeof value?.lat === 'function' ? value.lat() : value?.lat;
    const lng = typeof value?.lng === 'function' ? value.lng() : value?.lng;
    return finite(lat) && finite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? {lat, lng} : null;
  } catch { return null; }
}

// Same geographic bearing convention as geometry.spherical.computeHeading:
// clockwise from true north. This local calculation needs no additional API.
export function headingToProperty(from, to) {
  const radians = Math.PI / 180;
  const a = from.lat * radians, b = to.lat * radians, d = (to.lng - from.lng) * radians;
  return wrap(Math.atan2(Math.sin(d) * Math.cos(b),
    Math.cos(a) * Math.sin(b) - Math.sin(a) * Math.cos(b) * Math.cos(d)) / radians);
}

export function distanceToProperty(from, to) {
  const radians = Math.PI / 180;
  const dLat = (to.lat - from.lat) * radians, dLng = (to.lng - from.lng) * radians;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(from.lat * radians) * Math.cos(to.lat * radians) * Math.sin(dLng / 2) ** 2;
  return 6378137 * 2 * Math.atan2(Math.sqrt(clamp(h, 0, 1)), Math.sqrt(clamp(1 - h, 0, 1)));
}

export function capturedMonth(value) {
  return typeof value === 'string' && /^\d{4}-(?:0[1-9]|1[0-2])$/.test(value) ? value : null;
}

export function checkedPanorama(data, target, radius) {
  const location = data?.location, position = panoramaPosition(location?.latLng);
  const pano = location?.pano;
  if (!position || typeof pano !== 'string' || !pano || pano.length > 512 || /[\u0000-\u001f\u007f<>]/u.test(pano)) return null;
  const distance = target ? distanceToProperty(position, target) : 0;
  if (radius !== undefined && distance > radius + 1) return null;
  return {pano, position, date: capturedMonth(data.imageDate), distance};
}

// Callback status distinguishes missing coverage from a provider failure.
// Absorb the returned Promise too: SDK versions may return one with a callback.
export function requestPanorama(service, request) {
  return new Promise(resolve => {
    let settled = false;
    const finish = (data, status) => {
      if (settled) return;
      settled = true;
      resolve({data: status === 'OK' ? data : null,
        status: ['OK', 'ZERO_RESULTS'].includes(status) ? status : 'UNKNOWN_ERROR'});
    };
    try {
      const result = service.getPanorama(request, finish);
      if (result?.then) void Promise.resolve(result).then(value => {
        if (value?.data) finish(value.data, 'OK');
      }, () => finish(null, 'UNKNOWN_ERROR'));
    } catch { finish(null, 'UNKNOWN_ERROR'); }
  });
}

export function createStreetCameraController({panorama, getResetHeading, reducedMotion = false,
  onError = () => {}, onStatus = () => {},
  requestFrame = callback => globalThis.requestAnimationFrame(callback),
  cancelFrame = id => globalThis.cancelAnimationFrame(id)}) {
  let disposed = false, generation = 0, frame = null, sequence = null, interruptible = false;
  const report = (state, reason) => {
    if (!disposed && Number.isSafeInteger(sequence) && sequence >= 0) onStatus({state, reason, sequence});
  };
  function cancel() {
    generation++;
    if (frame !== null) cancelFrame(frame);
    frame = null;
    interruptible = false;
  }
  function failed() { cancel(); if (!disposed) onError(); }
  function zoom() {
    const value = panorama.getZoom();
    // Defensive numeric validation only. 64 is not an imagery or UI zoom limit.
    if (!finite(value) || value < 0 || value > 64) throw Error('Invalid camera state.');
    return value;
  }
  function schedule(token, tick) {
    const id = requestFrame(time => {
      if (disposed || token !== generation) return;
      if (frame === id) frame = null;
      try { tick(time); } catch { failed(); }
    });
    frame = id;
  }
  function limit(direction) {
    cancel();
    report('limit', direction > 0 ? 'closest' : 'farthest');
  }
  function changeZoom(direction, continuous) {
    const token = generation;
    let desired = zoom(), previous = desired, previousTime = null, stalled = 0;
    if (direction < 0 && desired === 0) { limit(direction); return; }
    if (!continuous) {
      desired = Math.max(0, desired + direction * .5);
      panorama.setZoom(desired);
    }
    const tick = timestamp => {
      if (!finite(timestamp)) throw Error('Invalid camera clock.');
      const actual = zoom();
      const elapsed = previousTime === null ? 0 : clamp(timestamp - previousTime, 0, 64);
      previousTime = timestamp;
      stalled = Math.abs(actual - previous) <= 1e-6 ? stalled + elapsed : 0;
      previous = actual;
      if (direction < 0 && actual <= 0) { limit(direction); return; }
      // No undocumented maximum or tile-level assumption: observe the zoom
      // value accepted by the actual panorama. Wait through async/quantized
      // provider updates before reporting a camera that stopped advancing.
      if (stalled >= 1000 && direction * (desired - actual) >= (continuous ? .49 : 1e-6)) { limit(direction); return; }
      if (!continuous && direction * (actual - desired) >= -1e-6) {
        cancel();
        return;
      }
      if (continuous && elapsed > 0) {
        desired = Math.max(0, desired + direction * (reducedMotion ? .55 : .9) * elapsed / 1000);
        if (!finite(desired) || desired > 64) throw Error('Invalid requested zoom.');
        panorama.setZoom(desired);
      }
      schedule(token, tick);
    };
    schedule(token, tick);
  }
  function apply({camera}) {
    if (disposed) return;
    cancel();
    sequence = camera.sequence;
    try {
      if (camera.operation === 'stopCamera') { report('stopped', 'stopped'); return; }
      interruptible = true;
      switch (camera.operation) {
        case 'closer': changeZoom(1, false); break;
        case 'farther': changeZoom(-1, false); break;
        case 'zoomInContinuous': changeZoom(1, true); break;
        case 'zoomOutContinuous': changeZoom(-1, true); break;
        case 'left':
        case 'right': {
          const pov = panorama.getPov();
          if (!finite(pov?.heading) || !finite(pov?.pitch)) throw Error('Invalid point of view.');
          panorama.setPov({heading: wrap(pov.heading + (camera.operation === 'left' ? -18 : 18)), pitch: clamp(pov.pitch, -90, 90)});
          break;
        }
        case 'reset': {
          const heading = getResetHeading();
          if (!finite(heading)) throw Error('Invalid target direction.');
          panorama.setPov({heading: wrap(heading), pitch: 0});
          panorama.setZoom(1);
          break;
        }
      }
    } catch { failed(); }
  }
  function stop(reason = 'interrupted', nextSequence = sequence) {
    if (disposed) return;
    cancel(); sequence = nextSequence; report('stopped', reason);
  }
  function interrupt() { if (interruptible) stop(); }
  function dispose() { cancel(); disposed = true; }
  return {apply, stop, interrupt, dispose};
}
