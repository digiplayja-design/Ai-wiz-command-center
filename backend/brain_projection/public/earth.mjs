import {parseCameraMessage, createCameraController, initialCameraOptions, MIN_CAMERA_ALTITUDE} from './camera.mjs';
import {checkedPanorama, panoramaPosition, headingToProperty, requestPanorama, createStreetCameraController} from './street.mjs';

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
        finish(false, {importLibrary: name => win.google.maps.importLibrary(name)});
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

// One first-party renderer owns both recorded views. Street View is the default;
// a missing panorama never silently changes into an overhead Earth scene.
export function mountProjectionRenderer({window: win, document: doc, loadLibrary = loadGoogleMapsLibrary}) {
  const state = doc.getElementById('map-state'), container = doc.getElementById('map');
  const imagery = doc.getElementById('imagery-label');
  const key = doc.querySelector('meta[name="korlix-map-key"]')?.content;
  const streetHost = doc.createElement('div'), earthHost = doc.createElement('div');
  streetHost.className = earthHost.className = 'projection-view';
  streetHost.setAttribute('aria-label', 'Recorded street-level imagery');
  earthHost.setAttribute('aria-label', 'Recorded 3D Earth imagery');
  streetHost.hidden = earthHost.hidden = true;
  container.append(streetHost, earthHost);
  let disposed = false, lastSequence = -1, viewGeneration = 0, viewSequence = -1;
  let viewMode = 'street', phase = 'awaiting-destination', target = null;
  let api = null, sdkPromise = null, sdkAbort = null, sdkDeadline = null, viewDeadline = null;
  let panorama = null, service = null, streetController = null, map = null, earthController = null;
  let pendingStreet = null, pendingEarth = null, metadataGeneration = 0, previousStatus = '', failingView = false;
  const libraries = new Map(), removers = [];
  const previousAuthFailure = win.gm_authFailure;
  const current = token => !disposed && token === viewGeneration;
  const reducedMotion = win.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;

  function post(value) { if (!disposed && win.parent !== win) win.parent.postMessage(value, '*'); }
  function label(date = null) {
    imagery.textContent = viewMode === 'street'
      ? `Recorded Street View · ${date ? 'Captured ' + date : 'Capture date unavailable'} · Not live`
      : 'Recorded 3D Earth imagery · Capture date unavailable · Not live';
  }
  function status(value, reason, message) {
    if (disposed) return;
    phase = reason === 'awaiting-destination' ? reason : value;
    state.hidden = value === 'ready' && reason !== 'awaiting-destination';
    state.textContent = message;
    const payload = {type: 'korlix-projection-status', status: value, viewMode, reason, message,
      ...(viewSequence >= 0 ? {sequence: viewSequence} : {})};
    const serialized = JSON.stringify(payload);
    if (serialized !== previousStatus) { previousStatus = serialized; post(payload); }
  }
  function cameraStatus(mode, {state: value, reason, sequence}) {
    if (disposed || !Number.isSafeInteger(sequence) || sequence < 0) return;
    if ((value !== 'stopped' || !['stopped', 'interrupted'].includes(reason)) &&
        (value !== 'limit' || !['closest', 'farthest'].includes(reason))) return;
    post({type: 'korlix-projection-camera-status', state: value, reason, sequence, viewMode: mode});
  }
  function hideViews() {
    streetHost.hidden = earthHost.hidden = true;
    try { panorama?.setVisible(false); } catch { /* No provider diagnostics. */ }
  }
  function stopControllers(reason = 'interrupted', sequence) {
    streetController?.stop(reason, sequence);
    earthController?.stop(reason, sequence);
  }
  function clearViewDeadline() { win.clearTimeout(viewDeadline); viewDeadline = null; }
  function failView(token, reason = 'unavailable') {
    if (!current(token) || failingView) return;
    failingView = true;
    clearViewDeadline();
    ++viewGeneration; ++metadataGeneration;
    pendingStreet = pendingEarth = null;
    stopControllers(); hideViews(); label();
    // Relative camera commands also advance the native sequence. A current
    // provider failure must not be discarded as an earlier destination reply.
    viewSequence = lastSequence;
    status('error', reason, reason === 'no-coverage'
      ? 'Street-level imagery is not available near this address. Choose 3D Earth or try another address.'
      : `${viewMode === 'street' ? 'Street View' : '3D Earth imagery'} could not load. Try again or choose another view.`);
    failingView = false;
  }
  function armViewDeadline(token) {
    clearViewDeadline();
    viewDeadline = win.setTimeout(() => failView(token), 30000);
  }
  function ensureSDK() {
    if (api) return Promise.resolve(api);
    if (sdkPromise) return sdkPromise;
    if (!key) return Promise.reject(Error('Imagery is not configured.'));
    sdkAbort = new AbortController();
    const abort = sdkAbort;
    sdkPromise = new Promise((resolve, reject) => {
      let finished = false;
      const finish = (value, error = false) => {
        if (finished) return;
        finished = true;
        win.clearTimeout(sdkDeadline); sdkDeadline = null;
        if (disposed || abort.signal.aborted || error || typeof value?.importLibrary !== 'function') {
          if (sdkAbort === abort) sdkPromise = null;
          reject(Error('Imagery library unavailable.')); return;
        }
        api = value; resolve(api);
      };
      sdkDeadline = win.setTimeout(() => { abort.abort(); finish(null, true); }, 30000);
      try {
        Promise.resolve(loadLibrary({window: win, document: doc, key, signal: abort.signal})).then(
          value => finish(value), () => finish(null, true));
      } catch { finish(null, true); }
    });
    const pending = sdkPromise;
    void pending.catch(() => { if (sdkPromise === pending) sdkPromise = null; });
    return pending;
  }
  function library(name) {
    if (libraries.has(name)) return libraries.get(name);
    const promise = ensureSDK().then(value => value.importLibrary(name)).catch(() => {
      libraries.delete(name); throw Error('Imagery library unavailable.');
    });
    libraries.set(name, promise);
    return promise;
  }
  function addInputListeners(host) {
    for (const name of ['pointerdown', 'touchstart', 'wheel']) {
      host.addEventListener(name, interruptCamera, {capture: true, passive: true});
      removers.push(() => host.removeEventListener(name, interruptCamera, {capture: true}));
    }
  }
  function finishStreet() {
    const pending = pendingStreet;
    if (!pending || !current(pending.token) || viewMode !== 'street') return;
    try {
      if (panorama.getPano() !== pending.data.pano) return;
      if (panorama.getStatus() !== 'OK') { failView(pending.token); return; }
      panorama.setPov({heading: headingToProperty(pending.data.position, target), pitch: 0});
      panorama.setZoom(1);
      pendingStreet = null;
      clearViewDeadline();
      streetHost.hidden = false; earthHost.hidden = true;
      panorama.setVisible(true);
      label(pending.data.date);
      status('ready', 'ready', 'Recorded street-level imagery is available. The view is aimed toward the selected location.');
    } catch { failView(pending.token); }
  }
  function refreshStreetMetadata() {
    if (disposed || pendingStreet || phase !== 'ready' || viewMode !== 'street') return;
    streetController?.interrupt();
    const token = viewGeneration, metadata = ++metadataGeneration;
    let pano;
    try { pano = panorama.getPano(); } catch { return; }
    label();
    if (typeof pano !== 'string' || !pano || pano.length > 512) return;
    void requestPanorama(service, {pano}).then(result => {
      if (!current(token) || metadata !== metadataGeneration || pendingStreet || viewMode !== 'street') return;
      try {
        if (panorama.getPano() !== pano) return;
        const checked = result.status === 'OK' ? checkedPanorama(result.data) : null;
        if (checked?.pano === pano) label(checked.date);
      } catch { /* Keep the explicit date-unavailable label. */ }
    });
  }
  function streetStatusChanged() {
    if (pendingStreet) { finishStreet(); return; }
    if (disposed || viewMode !== 'street' || phase !== 'ready') return;
    try {
      const value = panorama.getStatus();
      if (value === 'ZERO_RESULTS') failView(viewGeneration, 'no-coverage');
      else if (value === 'UNKNOWN_ERROR') failView(viewGeneration);
    } catch { failView(viewGeneration); }
  }
  function createPanorama(lib) {
    if (panorama) return;
    // Google owns its attribution, legal links and panorama contents. Only
    // public APIs are used; our labels live outside the entire SDK surface.
    panorama = new lib.StreetViewPanorama(streetHost, {visible: false,
      imageDateControl: true, motionTracking: false, motionTrackingControl: false,
      enableCloseButton: false, fullscreenControl: false, zoomControl: true, linksControl: true});
    const observed = panorama;
    for (const [name, handler] of [['status_changed', streetStatusChanged], ['pano_changed', refreshStreetMetadata]]) {
      const listener = observed.addListener(name, handler);
      removers.push(() => listener.remove());
    }
    streetController = createStreetCameraController({panorama, reducedMotion,
      getResetHeading: () => {
        const position = panoramaPosition(panorama.getPosition());
        if (!position || !target) throw Error('Street position unavailable.');
        return headingToProperty(position, target);
      },
      onError: () => { if (viewMode === 'street') failView(viewGeneration); },
      onStatus: value => cameraStatus('street', value),
      requestFrame: callback => win.requestAnimationFrame(callback), cancelFrame: id => win.cancelAnimationFrame(id)});
  }
  async function openStreet(command, token) {
    try {
      const lib = await library('streetView');
      if (!current(token)) return;
      if (typeof lib?.StreetViewService !== 'function' || typeof lib?.StreetViewPanorama !== 'function') throw Error('Street View unavailable.');
      service ||= new lib.StreetViewService();
      let found = null;
      for (const radius of [50, 100]) {
        const result = await requestPanorama(service, {location: {...target}, radius,
          preference: 'nearest', sources: ['google', 'outdoor']});
        if (!current(token)) return;
        if (result.status === 'ZERO_RESULTS') continue;
        if (result.status !== 'OK') throw Error('Street lookup unavailable.');
        found = checkedPanorama(result.data, target, radius);
        if (!found) throw Error('Street lookup invalid.');
        break;
      }
      if (!found) { failView(token, 'no-coverage'); return; }
      streetHost.hidden = false;
      createPanorama(lib);
      if (!current(token)) return;
      const alreadyCurrent = panorama.getPano() === found.pano && panorama.getStatus() === 'OK';
      pendingStreet = {token, data: found};
      if (alreadyCurrent) finishStreet();
      else {
        panorama.setPano(found.pano);
        // Start the visible viewer before waiting for its lookup status. A
        // hidden panorama can defer that work. A synchronous provider failure
        // may already have cancelled this generation inside setPano().
        if (current(token) && pendingStreet?.token === token) panorama.setVisible(true);
      }
    } catch { failView(token); }
  }
  function steady(event) {
    const pending = pendingEarth;
    if (!pending || !current(pending.token) || viewMode !== 'earth' || event.target !== map || event.isSteady !== true) return;
    // A stale steady event for an earlier place must not complete a new flight.
    if (!map.center || Math.abs(map.center.lat - target.lat) > 1e-6 || Math.abs(map.center.lng - target.lng) > 1e-6) return;
    pendingEarth = null; clearViewDeadline();
    earthHost.hidden = false; streetHost.hidden = true;
    label(); status('ready', 'ready', 'Recorded 3D Earth imagery is available. Capture date unavailable.');
  }
  async function openEarth(command, token) {
    try {
      const lib = await library('maps3d');
      if (!current(token)) return;
      if (typeof lib?.Map3DElement !== 'function') throw Error('Earth view unavailable.');
      pendingEarth = {token};
      earthHost.hidden = false;
      if (!map) {
        // altitudeMode belongs to animation CameraOptions, not the element's
        // constructor options. Mount a valid map, then send the destination
        // through flyCameraTo so its center remains relative to local terrain.
        map = new lib.Map3DElement({...initialCameraOptions(), mode: 'SATELLITE',
          defaultUIHidden: true, description: 'Recorded 3D geographic imagery, not a live camera feed.',
          minAltitude: MIN_CAMERA_ALTITUDE, maxAltitude: 40000000, maxTilt: 85});
        earthController = createCameraController({map, selectedPlace: {latitude: target.lat, longitude: target.lng}, reducedMotion,
          onError: () => { if (viewMode === 'earth') failView(viewGeneration); },
          onStatus: value => cameraStatus('earth', value),
          requestFrame: callback => win.requestAnimationFrame(callback), cancelFrame: id => win.cancelAnimationFrame(id)});
        const observed = map;
        const error = () => { if (viewMode === 'earth') failView(viewGeneration); };
        observed.addEventListener('gmp-steadychange', steady);
        observed.addEventListener('gmp-error', error);
        removers.push(() => observed.removeEventListener('gmp-steadychange', steady),
          () => observed.removeEventListener('gmp-error', error));
        earthHost.append(observed);
      }
      if (current(token)) earthController.apply(command);
    } catch { failView(token); }
  }
  function beginView(command) {
    stopControllers(); hideViews();
    const token = ++viewGeneration;
    ++metadataGeneration;
    pendingStreet = pendingEarth = null;
    viewMode = command.camera.viewMode ?? 'street';
    viewSequence = command.camera.sequence;
    target = {lat: command.camera.latitude ?? command.place?.latitude, lng: command.camera.longitude ?? command.place?.longitude};
    label(); status('loading', 'loading', viewMode === 'street' ? 'Finding recorded street-level imagery…' : 'Connecting recorded 3D Earth imagery…');
    armViewDeadline(token);
    if (viewMode === 'street') void openStreet(command, token);
    else void openEarth(command, token);
  }
  function cancelPending(reason, sequence) {
    if (phase !== 'loading') return false;
    ++viewGeneration; ++metadataGeneration;
    pendingStreet = pendingEarth = null;
    clearViewDeadline(); hideViews();
    viewSequence = sequence;
    status('error', 'interrupted', 'View loading stopped. Choose the address again when you are ready.');
    // A reused Earth viewer may already be animating its new destination while
    // awaiting a steady scene. Invalidate lookup work AND stop that SDK flight.
    const activeController = viewMode === 'street' ? streetController : earthController;
    stopControllers(reason, sequence);
    if (!activeController) cameraStatus(viewMode, {state: 'stopped', reason, sequence});
    return true;
  }
  function interruptCamera() {
    if (disposed) return;
    if (cancelPending('interrupted', lastSequence)) return;
    if (viewMode === 'street') streetController?.interrupt();
    else earthController?.interrupt();
  }
  function visibilityChanged() { if (doc.visibilityState === 'hidden') interruptCamera(); }
  function receive(event) {
    if (disposed) return;
    const command = parseCameraMessage(event, {parent: win.parent, ownOrigin: win.location.origin, lastSequence});
    if (!command) return;
    lastSequence = command.camera.sequence;
    if (command.camera.operation === 'stopCamera') {
      if (cancelPending('stopped', lastSequence)) return;
      const controller = viewMode === 'street' ? streetController : earthController;
      if (controller) controller.stop('stopped', lastSequence);
      else cameraStatus(viewMode, {state: 'stopped', reason: 'stopped', sequence: lastSequence});
      return;
    }
    if (doc.visibilityState === 'hidden') {
      cancelPending('interrupted', lastSequence);
      cameraStatus(viewMode, {state: 'stopped', reason: 'interrupted', sequence: lastSequence});
      return;
    }
    if (command.camera.operation === 'flyTo') { beginView(command); return; }
    if (phase !== 'ready' || (command.camera.viewMode !== undefined && command.camera.viewMode !== viewMode)) {
      if (target) cameraStatus(viewMode, {state: 'stopped', reason: 'interrupted', sequence: lastSequence});
      return;
    }
    const controller = viewMode === 'street' ? streetController : earthController;
    controller?.apply(command);
  }
  function authFailed() {
    if (disposed) return;
    api = null; libraries.clear(); sdkAbort?.abort(); sdkPromise = null;
    failView(viewGeneration);
  }
  function dispose() {
    if (disposed) return;
    disposed = true; ++viewGeneration; ++metadataGeneration;
    clearViewDeadline(); win.clearTimeout(sdkDeadline);
    pendingStreet = pendingEarth = null;
    sdkAbort?.abort(); streetController?.dispose(); earthController?.dispose();
    win.removeEventListener('message', receive);
    win.removeEventListener('pagehide', dispose);
    doc.removeEventListener('visibilitychange', visibilityChanged);
    for (const remove of removers) remove();
    try { panorama?.setVisible(false); } catch { /* Closing the document. */ }
    map?.remove(); streetHost.remove(); earthHost.remove();
    if (win.gm_authFailure === authFailed) win.gm_authFailure = previousAuthFailure ?? noop;
  }
  win.addEventListener('message', receive);
  win.addEventListener('pagehide', dispose);
  doc.addEventListener('visibilitychange', visibilityChanged);
  addInputListeners(streetHost); addInputListeners(earthHost);
  win.gm_authFailure = authFailed;
  post({type: 'korlix-projection-transport-ready'});
  label(); status('loading', 'loading', 'Preparing recorded street-level imagery…');
  void ensureSDK().then(() => {
    if (disposed || target || phase === 'error') return;
    // Older shells wait for ready before sending their first destination. This
    // is transport readiness only; new shells use the separate handshake.
    status('ready', 'awaiting-destination', 'Enter and confirm an address to open Street View.');
  }, () => { if (!disposed && !target) failView(viewGeneration); });
  return {dispose};
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  mountProjectionRenderer({window, document});
}
