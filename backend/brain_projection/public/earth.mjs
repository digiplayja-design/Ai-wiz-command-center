import {parseCameraMessage, createCameraController, initialCameraOptions, MIN_CAMERA_ALTITUDE} from './camera.mjs';

const noop = () => {};

// Install callbacks before inserting the SDK, including on a warm browser cache.
// https://developers.google.com/maps/documentation/javascript/load-maps-js-api
// The key is a public website-restricted Maps JavaScript key, never an account
// token or the private geocoding key. Provider errors/URLs are never forwarded.
export function loadGoogleMapsLibrary({window: win, document: doc, key, signal}) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) { reject(new Error('Map loading cancelled.')); return; }
    const script = doc.createElement('script');
    const previous = win.__korlixMapsReady;
    let finished = false, callbackStarted = false;
    function finish(error, library) {
      if (finished) return;
      finished = true;
      signal.removeEventListener('abort', aborted);
      script.onerror = null;
      if (win.__korlixMapsReady === ready) win.__korlixMapsReady = previous ?? noop;
      if (error) { script.remove(); reject(new Error('Map library unavailable.')); }
      else resolve(library);
    }
    function aborted() { finish(true); }
    function ready() {
      if (finished || callbackStarted || signal.aborted) return;
      callbackStarted = true;
      try {
        if (typeof win.google?.maps?.importLibrary !== 'function') { finish(true); return; }
        Promise.resolve(win.google.maps.importLibrary('maps3d')).then(
          library => finish(false, library), () => finish(true));
      } catch { finish(true); }
    }
    win.__korlixMapsReady = ready;
    const url = new URL('https://maps.googleapis.com/maps/api/js');
    url.search = new URLSearchParams({key, v: 'quarterly', loading: 'async',
      callback: '__korlixMapsReady', auth_referrer_policy: 'origin'}).toString();
    script.src = url.href;
    script.async = true;
    script.nonce = doc.querySelector('script[nonce]')?.nonce || '';
    script.referrerPolicy = 'strict-origin-when-cross-origin';
    script.onerror = () => finish(true);
    signal.addEventListener('abort', aborted, {once: true});
    try { doc.head.append(script); } catch { finish(true); }
  });
}

// Exported browser facade/library loader allows deterministic lifecycle tests
// without Google requests or a WebGL GPU. This returns its disposer immediately.
export function mountProjectionRenderer({window: win, document: doc, loadLibrary = loadGoogleMapsLibrary}) {
  const state = doc.getElementById('map-state');
  const container = doc.getElementById('map');
  const loading = new AbortController();
  let map = null, controller = null, disposed = false, ready = false, lastSequence = -1, pending = null;
  let deadline = null;
  const removeListeners = [];
  const previousAuthFailure = win.gm_authFailure;
  function status(value, message) {
    if (disposed) return;
    state.hidden = value === 'ready';
    if (message) state.textContent = message;
    // Only public map status crosses the opaque bundled parent boundary.
    if (win.parent !== win) win.parent.postMessage({type: 'korlix-projection-status', status: value,
      ...(message ? {message} : {})}, '*');
  }
  function failed() {
    if (disposed) return;
    status('error', 'Recorded 3D imagery could not load. Check the map connection or try again later.');
    dispose();
  }
  function cameraStatus({state: value, reason, sequence}) {
    if (disposed || win.parent === win || !Number.isSafeInteger(sequence) || sequence < 0) return;
    if ((value !== 'stopped' || !['stopped', 'interrupted'].includes(reason)) &&
        (value !== 'limit' || !['closest', 'farthest'].includes(reason))) return;
    // No geometry, labels, provider errors or arbitrary data crosses this path.
    win.parent.postMessage({type: 'korlix-projection-camera-status', state: value, reason, sequence}, '*');
  }
  function interruptCamera() {
    if (disposed) return;
    if (pending) {
      const sequence = pending.camera.sequence;
      pending = null;
      if (controller) controller.stop('interrupted', sequence);
      else cameraStatus({state: 'stopped', reason: 'interrupted', sequence});
    } else controller?.interrupt();
  }
  function visibilityChanged() {
    if (doc.visibilityState === 'hidden') interruptCamera();
  }
  function receive(event) {
    if (disposed) return;
    const command = parseCameraMessage(event, {parent: win.parent, ownOrigin: win.location.origin, lastSequence});
    if (!command) return;
    lastSequence = command.camera.sequence;
    // A stop is valid with no selected place and before SDK readiness. It must
    // remove a queued command so a late import/steady event cannot restart it.
    if (command.camera.operation === 'stopCamera') {
      pending = null;
      if (controller) controller.apply(command);
      else cameraStatus({state: 'stopped', reason: 'stopped', sequence: lastSequence});
      return;
    }
    if (doc.visibilityState === 'hidden') {
      pending = null;
      if (controller) controller.stop('interrupted', lastSequence);
      else cameraStatus({state: 'stopped', reason: 'interrupted', sequence: lastSequence});
      return;
    }
    if (!ready || !controller) { pending = command; return; }
    controller.apply(command);
  }
  function steady(event) {
    // importLibrary/constructor/animation end are not evidence of rendered data.
    // Current quarterly event means all rendering for this scene has completed:
    // https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map#SteadyChangeEvent
    if (disposed || ready || event.target !== map || event.isSteady !== true) return;
    ready = true;
    win.clearTimeout(deadline);
    if (pending) { const command = pending; pending = null; controller.apply(command); }
    if (!disposed) status('ready', 'Recorded 3D imagery connected. Capture date unavailable.');
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    ready = false;
    win.clearTimeout(deadline);
    win.removeEventListener('message', receive);
    win.removeEventListener('pagehide', dispose);
    doc.removeEventListener('visibilitychange', visibilityChanged);
    for (const remove of removeListeners) remove();
    pending = null;
    loading.abort();
    controller?.dispose();
    // Map3DElement exposes no destroy method. Stop camera work, unregister our
    // listeners and detach it; the parent also removes this entire iframe.
    map?.remove();
    map = null;
    if (win.gm_authFailure === failed) win.gm_authFailure = previousAuthFailure ?? noop;
  }
  win.addEventListener('message', receive);
  win.addEventListener('pagehide', dispose);
  doc.addEventListener('visibilitychange', visibilityChanged);
  // Official authentication callback must exist before the SDK is requested.
  // https://developers.google.com/maps/documentation/javascript/events#auth-errors
  win.gm_authFailure = failed;
  status('loading', 'Connecting recorded 3D imagery…');
  const key = doc.querySelector('meta[name="korlix-map-key"]')?.content;
  if (!key) {
    status('error', 'Geographic imagery is not connected yet.');
    dispose();
    return {dispose};
  }
  deadline = win.setTimeout(failed, 30000);
  try {
    Promise.resolve(loadLibrary({window: win, document: doc, key, signal: loading.signal})).then(library => {
      if (disposed) return;
      if (typeof library?.Map3DElement !== 'function') { failed(); return; }
      map = new library.Map3DElement({...initialCameraOptions(), mode: 'SATELLITE',
        defaultUIHidden: true, description: 'Recorded 3D geographic imagery, not a live camera feed.',
        minAltitude: MIN_CAMERA_ALTITUDE, maxAltitude: 40000000, maxTilt: 85});
      controller = createCameraController({map, onError: failed, onStatus: cameraStatus,
        requestFrame: callback => win.requestAnimationFrame(callback),
        cancelFrame: id => win.cancelAnimationFrame(id),
        reducedMotion: win.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true});
      map.addEventListener('gmp-steadychange', steady);
      map.addEventListener('gmp-error', failed);
      const mounted = map;
      removeListeners.push(() => mounted.removeEventListener('gmp-steadychange', steady),
        () => mounted.removeEventListener('gmp-error', failed));
      // Observe input on the public element without preventing Google's own
      // gestures, attribution clicks or access to its internal UI.
      for (const eventName of ['pointerdown', 'touchstart', 'wheel']) {
        mounted.addEventListener(eventName, interruptCamera, {capture: true, passive: true});
        removeListeners.push(() => mounted.removeEventListener(eventName, interruptCamera, {capture: true}));
      }
      // Attribution, legal links and all internal map UI remain owned by Google.
      // Do not inspect/modify its Shadow DOM or intercept its link clicks.
      container.append(map);
    }).catch(failed);
  } catch { failed(); }
  return {dispose};
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  mountProjectionRenderer({window, document});
}
