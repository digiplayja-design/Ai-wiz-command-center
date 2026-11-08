import {parseCameraMessage, createCameraController} from './camera.mjs';

// Exported runtime accepts a browser facade so lifecycle and message boundaries
// can be exercised without contacting Google or requiring a WebGL GPU in CI.
export async function mountProjectionRenderer({window: win, document: doc, Cesium}) {
  const state = doc.getElementById('map-state');
  let viewer = null, controller = null, disposed = false, lastSequence = -1, pending = null;
  const removeListeners = [];
  function status(value, message) {
    if (disposed) return;
    state.hidden = value === 'ready';
    if (message) state.textContent = message;
    // Status is public, map-only data. "*" is necessary for the opaque bundled
    // parent; inbound commands still verify Window identity and allowed origin.
    if (win.parent !== win) win.parent.postMessage({type: 'korlix-projection-status', status: value, ...(message ? {message} : {})}, '*');
  }
  function failed() {
    status('error', 'Recorded 3D imagery could not load. Check the map connection or try again later.');
    dispose();
  }
  function receive(event) {
    if (disposed) return;
    const command = parseCameraMessage(event, {parent: win.parent, ownOrigin: win.location.origin, lastSequence});
    if (!command) return;
    lastSequence = command.camera.sequence;
    if (!controller) { pending = command; return; }
    try { controller.apply(command); } catch { failed(); }
  }
  function watchAttribution() {
    const credits = doc.getElementById('map-credits');
    let lastHeight = -1;
    function publishHeight() {
      if (disposed || win.parent === win) return;
      const measured = credits?.getBoundingClientRect?.().height;
      if (!Number.isFinite(measured) || measured < 0 ||
          !Number.isFinite(win.innerHeight) || win.innerHeight <= 0) return;
      // Geometry is public presentation data only. Never forward credit HTML,
      // provider URLs, keys or arbitrary style values to the native shell.
      const height = Math.min(4096, Math.ceil(measured), Math.floor(win.innerHeight));
      if (height === lastHeight) return;
      lastHeight = height;
      win.parent.postMessage({type: 'korlix-projection-credits', height}, '*');
    }
    if (typeof win.ResizeObserver === 'function') {
      const observer = new win.ResizeObserver(publishHeight);
      observer.observe(credits);
      removeListeners.push(() => observer.disconnect());
    } else if (viewer.scene.postRender) {
      // Older WebViews still update viewport-specific provider credit changes.
      removeListeners.push(viewer.scene.postRender.addEventListener(publishHeight));
    }
    win.addEventListener('resize', publishHeight);
    removeListeners.push(() => win.removeEventListener('resize', publishHeight));
    publishHeight();
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    win.removeEventListener('message', receive);
    win.removeEventListener('pagehide', dispose);
    for (const remove of removeListeners) remove();
    pending = null;
    if (viewer && !viewer.isDestroyed()) viewer.destroy();
  }
  win.addEventListener('message', receive);
  win.addEventListener('pagehide', dispose);
  // Block links from navigating this isolated map frame or opening windows.
  // Attribution remains visible; users can read the provider credit on screen.
  const stopNavigation = event => { if (event.target?.closest?.('a')) event.preventDefault(); };
  doc.addEventListener('click', stopNavigation);
  removeListeners.push(() => doc.removeEventListener('click', stopNavigation));
  status('loading', 'Connecting recorded 3D imagery…');
  const key = doc.querySelector('meta[name="korlix-map-key"]')?.content;
  if (!key) {
    status('error', 'Geographic imagery is not connected yet.');
    return {dispose};
  }
  if (!Cesium?.Viewer || !Cesium?.createGooglePhotorealistic3DTileset) {
    failed();
    return {dispose};
  }
  try {
    Cesium.Ion.defaultAccessToken = '';
    viewer = new Cesium.Viewer('map', {
      baseLayer: false, globe: false, skyBox: false, skyAtmosphere: false,
      animation: false, timeline: false, geocoder: false, baseLayerPicker: false,
      sceneModePicker: false, navigationHelpButton: false, homeButton: false,
      fullscreenButton: false, infoBox: false, selectionIndicator: false,
      scene3DOnly: true, requestRenderMode: true, shouldAnimate: false,
      creditContainer: doc.getElementById('map-credits'),
    });
    viewer.scene.backgroundColor = Cesium.Color.fromCssColorString('#030b13');
    viewer.resolutionScale = Math.min(1, 1.5 / (win.devicePixelRatio || 1));
    const controllerBeforeLoad = createCameraController({Cesium, viewer});
    controllerBeforeLoad.reset();
    removeListeners.push(viewer.scene.renderError.addEventListener(failed));
    const loadTimeout = win.setTimeout(failed, 30000);
    removeListeners.push(() => win.clearTimeout(loadTimeout));
    const tileset = await Cesium.createGooglePhotorealistic3DTileset(
      {key, onlyUsingWithGoogleGeocoder: true},
      {showCreditsOnScreen: true, maximumScreenSpaceError: 24,
        cacheBytes: 128 * 1024 * 1024, maximumCacheOverflowBytes: 64 * 1024 * 1024});
    if (disposed) { if (!tileset.isDestroyed()) tileset.destroy(); return {dispose}; }
    win.clearTimeout(loadTimeout);
    viewer.scene.primitives.add(tileset);
    // New integrations use the full Google Maps name. Cesium separately keeps
    // the Google logo and the viewport's complete per-tile data attribution.
    viewer.creditDisplay.addStaticCredit(new Cesium.Credit('Google Maps', true));
    removeListeners.push(tileset.tileFailed.addEventListener(failed));
    controller = controllerBeforeLoad;
    if (pending) { controller.apply(pending); pending = null; }
    viewer.scene.requestRender();
    status('ready', 'Recorded 3D imagery connected. Capture date unavailable.');
    watchAttribution();
  } catch { failed(); }
  return {dispose};
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  // Both module and deferred external Cesium script have completed by this event.
  const mount = () => void mountProjectionRenderer({window, document, Cesium: window.Cesium});
  if (document.readyState === 'complete') mount();
  else window.addEventListener('load', mount, {once: true});
}
