import {providerErrorCode, sdkVersion} from './evidence.mjs';

// Observe the public loader insertion. Only the explicitly labeled negative
// document changes its referrer policy, immediately before native insertion.
export function observeLoader({document: doc, negative, onLoader}) {
  const head = doc.head;
  const originalAppend = head.append, originalAppendChild = head.appendChild;
  const seen = new WeakSet();
  const inspect = node => {
    if (!node || node.tagName !== 'SCRIPT' || seen.has(node)) return;
    let url;
    try { url = new URL(node.src); } catch { return; }
    if (url.origin !== 'https://maps.googleapis.com' || url.pathname !== '/maps/api/js') return;
    seen.add(node);
    if (negative) node.referrerPolicy = 'no-referrer';
    onLoader({channel: url.searchParams.get('v') === 'quarterly' ? 'quarterly' : 'unexpected',
      loading: url.searchParams.get('loading') === 'async' ? 'async' : 'unexpected',
      authorizationReferrerPolicy: url.searchParams.get('auth_referrer_policy') === 'origin' ? 'origin' : 'unexpected',
      scriptReferrerPolicy: node.referrerPolicy === 'no-referrer' ? 'no-referrer' : node.referrerPolicy === 'strict-origin-when-cross-origin' ? 'strict-origin-when-cross-origin' : 'unexpected'}, node);
  };
  head.append = function (...nodes) { for (const node of nodes) inspect(node); return Reflect.apply(originalAppend, this, nodes); };
  head.appendChild = function (node) { inspect(node); return Reflect.apply(originalAppendChild, this, [node]); };
  return () => { head.append = originalAppend; head.appendChild = originalAppendChild; };
}

function runFrame() {
  const negative = document.querySelector('meta[name="acceptance-mode"]').content === 'no-referrer';
  const configured = document.querySelector('meta[name="acceptance-configured"]').content === 'true';
  const evidence = {mode: negative ? 'no-referrer' : 'standard', started: false, loader: null, sdkVersion: null,
    steady: false, everSteady: false, steadyEvents: 0, animationEnds: 0, mapError: false, loaderError: false, pageError: false,
    cspViolations: 0, providerErrorCodes: [], documentReferrerPolicy: negative ? 'no-referrer' : 'strict-origin-when-cross-origin'};
  let closed = false, restoreLoader = () => {};
  const publish = () => {
    evidence.sdkVersion = sdkVersion(window.google?.maps?.version);
    if (!closed && parent !== window) parent.postMessage({type: 'korlix-acceptance-evidence', evidence}, location.origin);
  };
  const originalError = console.error;
  console.error = function (...values) {
    const code = providerErrorCode(values);
    if (code && !evidence.providerErrorCodes.includes(code)) evidence.providerErrorCodes.push(code);
    publish();
    return Reflect.apply(originalError, this, values);
  };
  const map = document.getElementById('map');
  map.addEventListener('gmp-steadychange', event => {
    const current = map.querySelector('gmp-map-3d');
    if (current && event.target === current && typeof event.isSteady === 'boolean') {
      evidence.steady = event.isSteady;
      evidence.everSteady ||= event.isSteady;
      evidence.steadyEvents = Math.min(100, evidence.steadyEvents + 1); publish();
    }
  }, true);
  map.addEventListener('gmp-animationend', event => {
    if (event.target === map.querySelector('gmp-map-3d')) { evidence.animationEnds = Math.min(100, evidence.animationEnds + 1); publish(); }
  }, true);
  map.addEventListener('gmp-error', () => { evidence.mapError = true; publish(); }, true);
  window.addEventListener('error', () => { evidence.pageError = true; publish(); });
  window.addEventListener('unhandledrejection', () => { evidence.pageError = true; publish(); });
  document.addEventListener('securitypolicyviolation', () => { evidence.cspViolations = Math.min(100, evidence.cspViolations + 1); publish(); });
  async function start() {
    if (closed || evidence.started || !configured) return;
    evidence.started = true;
    document.getElementById('begin').hidden = true;
    restoreLoader = observeLoader({document, negative, onLoader: (loader, script) => {
      evidence.loader = loader;
      script.addEventListener('error', () => { evidence.loaderError = true; publish(); }, {once: true});
      script.addEventListener('load', publish, {once: true});
      publish();
    }});
    publish();
    try { await import('/brain-projection/earth.mjs'); }
    catch { evidence.pageError = true; publish(); document.getElementById('map-state').textContent = 'The acceptance map could not start.'; }
  }
  document.getElementById('begin').addEventListener('click', start);
  window.addEventListener('message', event => {
    if (event.source === parent && event.origin === location.origin && event.data?.type === 'korlix-acceptance-start') void start();
  });
  window.addEventListener('pagehide', () => { closed = true; restoreLoader(); console.error = originalError; }, {once: true});
  publish();
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') runFrame();
