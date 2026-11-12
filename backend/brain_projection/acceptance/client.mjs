import {cameraControlsReady, classifyObservation, rendererObservation, sanitizeEvidence} from './evidence.mjs';

const get = id => document.getElementById(id);
const mode = document.querySelector('meta[name="acceptance-mode"]').content;
const noReferrer = mode === 'no-referrer', wrongOrigin = mode === 'wrong-origin';
const negative = noReferrer || wrongOrigin;
const configured = document.querySelector('meta[name="acceptance-configured"]').content === 'true';
const operations = new Set(['flyTo', 'closer', 'farther', 'left', 'right', 'reset', 'zoomInContinuous', 'zoomOutContinuous', 'stopCamera']);
const landmark = {id: 'acceptance-ferry-building', label: 'San Francisco Ferry Building', latitude: 37.7955, longitude: -122.3937};
let frame = null, sequence = 0;
let report;
const checkboxes = [...document.querySelectorAll('.checks input')];
get('origin').textContent = location.origin;

function resetReport() {
  report = {acceptanceVersion: 5, origin: location.origin, scenario: mode,
    productionActivation: false, overallVerification: 'NOT_ESTABLISHED', startedAt: null, closedAt: null,
    transportReady: false, viewMode: 'street', cameraSequence: 0, rendererStatus: 'not-started', rendererReason: null,
    everReady: false, cameraOutcome: null, observation: 'NOT_PERFORMED', cameraCommands: [], cameraHistory: [], sdk: null, tester: {}};
  for (const checkbox of checkboxes) { checkbox.checked = false; checkbox.disabled = true; }
}
function render() {
  const sdk = report.sdk;
  if (noReferrer) {
    report.tester.googleSdkAndAuthorizationRequestsHadNoReferer = get('headers-confirmed').checked;
  } else if (wrongOrigin) {
    report.tester.currentOriginAbsentFromKeyAllowlist = get('origin-unapproved-confirmed').checked;
  } else {
    report.tester.imageryAndControlsConfirmed = get('imagery-confirmed').checked;
    report.tester.attributionAndLinksConfirmed = get('attribution-confirmed').checked;
  }
  report.observation = classifyObservation(report, mode);
  get('verdict').textContent = report.observation.replaceAll('_', ' ');
  get('evidence').textContent = JSON.stringify(report, null, 2);
  const ready = Boolean(frame && cameraControlsReady(report));
  const transport = Boolean(frame && report.transportReady && !report.closedAt);
  for (const button of document.querySelectorAll('[data-operation]')) {
    button.disabled = ['flyTo', 'stopCamera'].includes(button.dataset.operation) ? !transport : !ready;
  }
  for (const button of document.querySelectorAll('[data-view-mode]')) {
    button.disabled = !transport;
    button.setAttribute('aria-pressed', String(button.dataset.viewMode === report.viewMode));
  }
  for (const checkbox of checkboxes) checkbox.disabled = negative ? !Boolean(sdk?.loader) : !(ready && report.cameraCommands.includes('flyTo'));
  const viewName = report.viewMode === 'street' ? 'Street View' : '3D Earth';
  get('camera-status').textContent = ready ? viewName + ' controls ready. Check movement and record this view’s visual observations.'
    : !frame ? 'Load the test map to enable camera controls.'
      : report.rendererStatus === 'error' ? report.rendererReason === 'no-coverage'
        ? 'Street-level imagery is unavailable here. Choose 3D Earth explicitly or retry the landmark.'
        : 'This view is unavailable. Retry the landmark or choose the other view.'
        : sdk?.mapError || sdk?.loaderError || sdk?.pageError || sdk?.providerErrorCodes?.length
          ? 'Camera controls unavailable. Review the recorded errors in Sanitized evidence.'
          : transport ? 'Waiting for imagery. Stop movement and view selection remain available.'
            : 'Waiting for the renderer connection before sending the public landmark.';
  get('policy-status').hidden = !sdk?.cspViolations;
  get('policy-status').textContent = sdk?.cspViolations
    ? `${sdk.cspViolations} security-policy event${sdk.cspViolations === 1 ? '' : 's'} recorded. Camera testing can continue when the scene is ready; the overall test remains pending policy review. Details are in Sanitized evidence.` : '';
}
function stop() {
  if (!frame) return;
  frame.remove(); frame = null;
  report.closedAt = new Date().toISOString();
  get('stage').textContent = 'Test map closed. Evidence remains below until the next test or page reload.';
  get('status').textContent = 'Test map closed.';
  get('stop').disabled = true; get('start').disabled = !configured;
  render();
}
get('start').addEventListener('click', () => {
  if (!configured) return;
  stop(); resetReport();
  report.startedAt = new Date().toISOString();
  frame = document.createElement('iframe');
  frame.title = wrongOrigin ? 'Wrong-origin map acceptance' : noReferrer ? 'No-referrer map acceptance' : 'Allowed-origin map acceptance';
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox');
  frame.allow = "camera 'none'; microphone 'none'; geolocation 'none'";
  frame.referrerPolicy = noReferrer ? 'no-referrer' : 'strict-origin-when-cross-origin';
  const current = frame;
  frame.addEventListener('load', () => {
    if (frame === current) current.contentWindow.postMessage({type: 'korlix-acceptance-start'}, location.origin);
  }, {once: true});
  frame.src = `/frame/${mode}`;
  get('stage').replaceChildren(frame);
  get('start').disabled = true; get('stop').disabled = false;
  get('status').textContent = 'Running the explicit SDK check…';
  render();
});
get('stop').addEventListener('click', stop);
function sendCamera(operation, viewMode = report.viewMode) {
  if (!frame || !report.transportReady || !operations.has(operation) || !['street', 'earth'].includes(viewMode)) return;
  if (!['flyTo', 'stopCamera'].includes(operation) && !cameraControlsReady(report)) return;
  const camera = {operation, sequence: ++sequence, viewMode, ...(operation === 'flyTo' ? {height: 850, pitch: -50} : {})};
  report.cameraSequence = camera.sequence;
  report.cameraOutcome = null;
  if (operation === 'flyTo') {
    report.viewMode = viewMode;
    report.rendererStatus = 'loading'; report.rendererReason = 'loading';
    report.cameraCommands = [];
  }
  for (const checkbox of checkboxes) checkbox.checked = false;
  frame.contentWindow.postMessage({type: 'korlix-projection-camera', camera, ...(operation === 'flyTo' ? {place: landmark} : {})}, location.origin);
  if (report.cameraCommands.length < 100) report.cameraCommands.push(operation);
  if (report.cameraHistory.length < 100) report.cameraHistory.push({operation, sequence: camera.sequence, viewMode});
  render();
}
for (const button of document.querySelectorAll('[data-operation]')) button.addEventListener('click', () => {
  if (!button.disabled) sendCamera(button.dataset.operation);
});
for (const button of document.querySelectorAll('[data-view-mode]')) button.addEventListener('click', () => {
  if (!button.disabled) sendCamera('flyTo', button.dataset.viewMode);
});
window.addEventListener('message', event => {
  if (!frame || event.source !== frame.contentWindow || event.origin !== location.origin) return;
  const data = event.data;
  if (data?.type === 'korlix-projection-transport-ready') {
    if (!report.transportReady) {
      report.transportReady = true;
      sendCamera('flyTo', 'street');
    }
  } else if (data?.type === 'korlix-projection-status') {
    // A queued ready response may describe imagery shown before a later mode
    // switch. Preserve that historical evidence without enabling stale controls.
    const historicalReady = data.status === 'ready' && data.reason === 'ready' &&
      ['street', 'earth'].includes(data.viewMode) && Number.isSafeInteger(data.sequence) &&
      data.sequence >= 1 && data.sequence <= report.cameraSequence;
    if (historicalReady) report.everReady = true;
    const observed = rendererObservation(report, data);
    if (!observed) { if (historicalReady) render(); return; }
    report.rendererStatus = observed.status; report.rendererReason = observed.reason;
    get('status').textContent = observed.status === 'ready' ? negative
      ? 'The renderer reported imagery ready. This check did not observe a denial.' : 'The selected view is ready. Complete its visual checks below.'
      : observed.status === 'error' ? 'The selected view reported a failure. Review the sanitized evidence below.' : 'The selected view is loading…';
    frame.contentWindow.postMessage({type: 'korlix-acceptance-refresh-evidence'}, location.origin);
  } else if (data?.type === 'korlix-projection-camera-status') {
    if (data.sequence !== report.cameraSequence || data.viewMode !== report.viewMode ||
        !((data.state === 'stopped' && ['stopped', 'interrupted'].includes(data.reason)) ||
          (data.state === 'limit' && ['closest', 'farthest'].includes(data.reason)))) return;
    report.cameraOutcome = {state: data.state, reason: data.reason, sequence: data.sequence, viewMode: data.viewMode};
  } else if (data?.type === 'korlix-acceptance-evidence' && data.evidence?.mode === report.scenario) {
    report.sdk = sanitizeEvidence(data.evidence, mode);
  }
  render();
});
for (const checkbox of checkboxes) checkbox.addEventListener('change', render);
get('copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(JSON.stringify(report, null, 2)); get('copy-status').textContent = ' Evidence copied.'; }
  catch { get('copy-status').textContent = ' Select and copy the evidence below.'; }
});
window.addEventListener('pagehide', stop, {once: true});
resetReport(); render();
