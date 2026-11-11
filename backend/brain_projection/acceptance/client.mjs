import {classifyObservation, sanitizeEvidence} from './evidence.mjs';

const get = id => document.getElementById(id);
const negative = document.querySelector('meta[name="acceptance-mode"]').content === 'no-referrer';
const configured = document.querySelector('meta[name="acceptance-configured"]').content === 'true';
const operations = new Set(['flyTo', 'closer', 'farther', 'left', 'right', 'reset']);
const landmark = {id: 'acceptance-ferry-building', label: 'San Francisco Ferry Building', latitude: 37.7955, longitude: -122.3937};
let frame = null, sequence = 0;
let report;
const checkboxes = [...document.querySelectorAll('.checks input')];
get('origin').textContent = location.origin;

function resetReport() {
  report = {acceptanceVersion: 1, origin: location.origin, scenario: negative ? 'no-referrer' : 'standard',
    productionActivation: false, overallVerification: 'NOT_ESTABLISHED', startedAt: null, closedAt: null,
    rendererStatus: 'not-started', observation: 'NOT_PERFORMED', cameraCommands: [], sdk: null, tester: {}};
  for (const checkbox of checkboxes) { checkbox.checked = false; checkbox.disabled = true; }
}
function render() {
  const sdk = report.sdk;
  const errors = Boolean(sdk?.mapError || sdk?.loaderError || sdk?.pageError || sdk?.cspViolations || sdk?.providerErrorCodes?.length);
  if (negative) {
    report.tester.googleSdkAndAuthorizationRequestsHadNoReferer = get('headers-confirmed').checked;
  } else {
    report.tester.imageryAndControlsConfirmed = get('imagery-confirmed').checked;
    report.tester.attributionAndLinksConfirmed = get('attribution-confirmed').checked;
  }
  report.observation = classifyObservation(report, negative);
  get('verdict').textContent = report.observation.replaceAll('_', ' ');
  get('evidence').textContent = JSON.stringify(report, null, 2);
  const ready = Boolean(frame && report.rendererStatus === 'ready' && sdk?.steady && !errors);
  for (const button of document.querySelectorAll('[data-operation]')) button.disabled = !ready;
  for (const checkbox of checkboxes) checkbox.disabled = negative ? !Boolean(sdk?.loader) : !(ready && report.cameraCommands.includes('flyTo'));
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
  frame.title = negative ? 'No-referrer map acceptance' : 'Allowed-origin map acceptance';
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox');
  frame.allow = "camera 'none'; microphone 'none'; geolocation 'none'";
  const current = frame;
  frame.addEventListener('load', () => {
    if (frame === current) current.contentWindow.postMessage({type: 'korlix-acceptance-start'}, location.origin);
  }, {once: true});
  frame.src = negative ? '/frame/no-referrer' : '/frame/standard';
  get('stage').replaceChildren(frame);
  get('start').disabled = true; get('stop').disabled = false;
  get('status').textContent = 'Running the explicit SDK check…';
  render();
});
get('stop').addEventListener('click', stop);
for (const button of document.querySelectorAll('[data-operation]')) button.addEventListener('click', () => {
  const operation = button.dataset.operation;
  if (!frame || button.disabled || !operations.has(operation)) return;
  const camera = {operation, sequence: ++sequence, ...(operation === 'flyTo' ? {height: 850, pitch: -50} : {})};
  for (const checkbox of checkboxes) checkbox.checked = false;
  frame.contentWindow.postMessage({type: 'korlix-projection-camera', camera, ...(operation === 'flyTo' ? {place: landmark} : {})}, location.origin);
  if (report.cameraCommands.length < 100) report.cameraCommands.push(operation);
  render();
});
window.addEventListener('message', event => {
  if (!frame || event.source !== frame.contentWindow || event.origin !== location.origin) return;
  const data = event.data;
  if (data?.type === 'korlix-projection-status' && ['loading', 'ready', 'error'].includes(data.status)) {
    report.rendererStatus = data.status;
    get('status').textContent = data.status === 'ready' ? 'The SDK reported a steady scene. Complete the visual checks below.'
      : data.status === 'error' ? 'The renderer reported a failure. Review the sanitized evidence below.' : 'Google SDK scene is loading…';
  } else if (data?.type === 'korlix-acceptance-evidence' && data.evidence?.mode === report.scenario) {
    report.sdk = sanitizeEvidence(data.evidence, negative);
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
