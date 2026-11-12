import {createServer} from 'node:http';
import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const configuredKey = value => typeof value === 'string' && /^[A-Za-z0-9_-]{20,200}$/.test(value.trim()) ? value.trim() : '';
const nonce = () => randomBytes(18).toString('base64url');

// Kept equal to the released map document's policy; this standalone service
// deliberately does not import production configuration or read its keys.
export function acceptanceMapPolicy(value) {
  return ["default-src 'none'",
    `script-src 'nonce-${value}' 'strict-dynamic' 'self' https://maps.googleapis.com https://maps.gstatic.com 'unsafe-eval' blob:`,
    `style-src 'self' 'nonce-${value}' https://fonts.googleapis.com`,
    "style-src-attr 'unsafe-inline'",
    "img-src 'self' https://*.googleapis.com https://*.gstatic.com https://*.google.com https://*.googleusercontent.com data: blob:",
    "connect-src 'self' https://*.googleapis.com https://*.google.com https://*.gstatic.com data: blob:",
    "font-src https://fonts.gstatic.com", "worker-src blob:", "frame-src https://*.google.com",
    "object-src 'none'", "base-uri 'none'", "form-action 'none'"].join('; ');
}

const shellPolicy = value => `default-src 'none'; script-src 'nonce-${value}' 'strict-dynamic' 'self'; style-src 'nonce-${value}'; frame-src 'self'; connect-src 'none'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;
const assets = new Map([
  ['/acceptance/client.mjs', new URL('./client.mjs', import.meta.url)],
  ['/acceptance/frame.mjs', new URL('./frame.mjs', import.meta.url)],
  ['/acceptance/evidence.mjs', new URL('./evidence.mjs', import.meta.url)],
  ['/acceptance/api-restriction.mjs', new URL('./api-restriction.mjs', import.meta.url)],
  ['/brain-projection/earth.mjs', new URL('../public/earth.mjs', import.meta.url)],
  ['/brain-projection/camera.mjs', new URL('../public/camera.mjs', import.meta.url)],
  ['/brain-projection/street.mjs', new URL('../public/street.mjs', import.meta.url)],
  ['/brain-projection/earth.css', new URL('../public/earth.css', import.meta.url)],
]);

function apiRestrictionPage({key, token}) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin"><meta name="korlix-map-key" content="${key}">
<title>Projection API restriction check</title>
<style nonce="${token}">:root{color-scheme:dark;font:16px/1.6 system-ui,sans-serif;background:#07131e;color:#eaf5fc}body{max-width:960px;margin:32px auto;padding:20px}button{font:inherit;padding:12px 18px;border-radius:8px;background:#88e7d1;color:#05251c;border:0}button:disabled{opacity:.5}a{color:#a0d9ff}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#102333;padding:20px;border-radius:12px;font-size:13px}#api-status{font-weight:700}</style>
<script type="module" src="/acceptance/api-restriction.mjs" nonce="${token}"></script></head><body>
<h1>Projection API restriction check</h1><p>Test origin: <strong id="origin"></strong></p>
<p>This check makes one read-only request to Google’s public Identity Toolkit configuration endpoint using the existing Maps browser key. The browser sends its normal referrer. No account sign-in, user data, Maps SDK or production activation is involved.</p>
<p>Only Google’s specific API_KEY_SERVICE_BLOCKED response for Identity Toolkit establishes this observation. A missing-referrer, disabled-service, billing, network or generic error is inconclusive.</p>
<button id="api-check"${key ? '' : ' disabled'}>Check API restriction</button>
<p id="api-status" role="status" aria-live="polite">${key ? 'Ready. No provider request has been made.' : 'The acceptance browser key is not configured.'}</p>
<pre id="api-evidence">No observation recorded.</pre>
<p>The result excludes the key, raw provider messages, account configuration and response headers. Browser-generated CORS preflight may precede the single API request. Actual outgoing headers require a separate browser capture.</p>
<p><a href="/">Return to the map check</a></p></body></html>`;
}

function shell({keyPresent, mode, token}) {
  const negative = mode === 'no-referrer', wrongOrigin = mode === 'wrong-origin';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="${negative ? 'no-referrer' : 'strict-origin-when-cross-origin'}">
<title>Projection map acceptance</title><meta name="acceptance-mode" content="${mode}"><meta name="acceptance-configured" content="${keyPresent}">
<style nonce="${token}">
:root{color-scheme:dark;font:16px/1.5 system-ui,sans-serif;background:#07131e;color:#eaf5fc}*{box-sizing:border-box}body{margin:0}main{max-width:1120px;margin:auto;padding:24px}h1{font-size:clamp(26px,5vw,38px);margin:0 0 8px}h2{font-size:20px;margin:0 0 12px}p{margin:8px 0 16px}.muted{color:#b8ccdc}.tag{color:#92e7d3;font-weight:700;letter-spacing:.08em;font-size:12px;text-transform:uppercase}.panel{padding:20px;background:#102333;border:1px solid #284357;border-radius:14px;margin:18px 0}.actions{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0}button,a{font:inherit}button{padding:10px 16px;border:1px solid #4a738b;border-radius:9px;background:#17394e;color:#fff;cursor:pointer}button.primary{background:#88e7d1;color:#05251c;font-weight:700;border-color:#88e7d1}button:disabled{opacity:.45;cursor:default}a{color:#a0d9ff}button:focus-visible,a:focus-visible{outline:3px solid #ffd28a;outline-offset:3px}.stage{height:60vh;min-height:360px;max-height:760px;border:1px solid #375369;border-radius:12px;overflow:hidden;background:#030b13}.stage p{padding:24px}iframe{width:100%;height:100%;border:0;display:block}.checks label{display:block;margin:12px 0}.checks input{margin-right:8px;accent-color:#88e7d1}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.5 ui-monospace,monospace;background:#07131e;padding:16px;border-radius:8px;max-height:430px;overflow:auto}.notice{border-left:4px solid #ffd28a;padding-left:14px}#verdict{font-weight:700;color:#a4e8ff}footer{font-size:13px;color:#b8ccdc;margin-top:24px}@media(max-width:500px){main{padding:16px}.panel{padding:16px}.stage{min-height:400px}button{flex:1 1 auto}}
</style><script type="module" src="/acceptance/client.mjs" nonce="${token}"></script></head>
<body><main><div class="tag">Isolated SDK check</div><h1>Projection map acceptance</h1>
<p class="muted">Recorded geographic imagery, not live cameras. This service cannot activate the production map or change account access.</p>
<nav><a href="/">Allowed-origin check</a> · <a href="/no-referrer">No-referrer probe</a> · <a href="/wrong-origin">Wrong-origin check</a></nav>
<section class="panel"><h2>${wrongOrigin ? 'Wrong-origin restriction check' : negative ? 'No-referrer probe' : 'Allowed-origin rendering check'}</h2>
<p>Acceptance origin: <strong id="origin"></strong></p>
${wrongOrigin ? '<p class="notice">Use this check from a controlled HTTPS origin that is absent from the key\'s current website allowlist. Normal page, frame and SDK referrer policies stay unchanged. Confirm the displayed origin against the key restrictions below. Only a specific Google referrer denial can establish this observation; GPU, billing, network or generic errors are inconclusive.</p>' : negative ? '<p class="notice">This probe keeps the current page origin. On an approved host, that origin stays approved, and the Google SDK can include it in authorization data. A rendered scene here does not by itself establish an unrestricted key. The page, frame and initial SDK loader use no-referrer policies; inspect actual Google SDK and authorization request headers before confirming their absence. These policies do not guarantee a denial.</p>' : '<p>Load the candidate key from this exact HTTPS origin. After the SDK finishes, inspect the landmark, controls, Google attribution and legal links. No Google SDK loads before you press the button.</p>'}
<p id="setup">${keyPresent ? 'Candidate key configured. Waiting for an explicit test.' : 'Setup required: the acceptance browser key is missing or invalid. No Google request will be made.'}</p>
<div class="actions"><button class="primary" id="start"${keyPresent ? '' : ' disabled'}>Load test map</button><button id="stop" disabled>Close test map</button></div>
<p id="status" role="status" aria-live="polite">Not started.</p></section>
<div class="stage" id="stage"><p>The map test will appear here after you press Load test map.</p></div>
<section class="panel"><h2>Camera checks</h2><p>Street View opens at the San Francisco Ferry Building, a public landmark. Check the recorded street-level view aimed toward the building, then choose 3D Earth and repeat the checks. Coverage is not assumed from a successful script load, and an unavailable street view will not switch modes automatically.</p>
<p id="camera-status" role="status">Load the test map to enable camera controls.</p><p id="policy-status" class="notice" role="status" hidden></p>
<div class="actions" aria-label="Imagery view"><button data-view-mode="street" aria-pressed="true" disabled>Street View</button><button data-view-mode="earth" aria-pressed="false" disabled>3D Earth</button></div>
<div class="actions" id="camera-controls"><button data-operation="flyTo" disabled>Return to landmark</button><button data-operation="closer" disabled>Closer</button><button data-operation="farther" disabled>Farther</button><button data-operation="left" disabled>Left</button><button data-operation="right" disabled>Right</button><button data-operation="reset" disabled>Reset</button><button data-operation="zoomInContinuous" disabled>Keep zooming in</button><button data-operation="zoomOutContinuous" disabled>Keep zooming out</button><button data-operation="stopCamera" disabled>Stop movement</button></div></section>
<section class="panel checks"><h2>Tester observations</h2>
${wrongOrigin ? '<label><input id="origin-unapproved-confirmed" type="checkbox" disabled>I inspected the current key\'s website restrictions and confirmed that the exact origin displayed above is not allowed by any entry, including wildcards.</label><p>The renderer must report a failure with RefererNotAllowedMapError under the normal loader contract, without ever rendering a steady scene. This manual confirmation does not change any key setting.</p>' : negative ? '<label><input id="headers-confirmed" type="checkbox" disabled>I inspected the relevant Google SDK and authorization requests and confirmed their Referer header was absent.</label><p>A specific referrer-denial code must also be captured below. An unchecked box means the headers are unverified. Use the separate wrong-origin check to test a genuinely unapproved website; this service does not forge a referrer or alter SDK authorization data.</p>' : '<label><input id="imagery-confirmed" type="checkbox" disabled>I can identify real geographic imagery at the landmark and the camera controls work.</label><label><input id="attribution-confirmed" type="checkbox" disabled>Google attribution is unobscured and its legal links work, including at a narrow viewport.</label>'}
<p id="verdict" role="status">No observation recorded.</p><p>These observations do not establish all API restrictions, quotas or iPhone/Android WebView behavior. The production verification gate remains unchanged.</p></section>
<section class="panel"><h2>Sanitized evidence</h2><p>Contains public SDK/version/state information, categorized policy events and your checkboxes. It excludes keys, raw provider errors, request URLs and headers.</p><button id="copy">Copy evidence</button><span id="copy-status" aria-live="polite"></span><pre id="evidence"></pre></section>
<footer>No account sign-in, database, geocoding service, AI calls or provider proxy is used here. Reloading or closing the page clears this local evidence.</footer></main></body></html>`;
}

function frame({key, mode, token}) {
  const negative = mode === 'no-referrer';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="${negative ? 'no-referrer' : 'strict-origin-when-cross-origin'}"><meta name="korlix-map-key" content="${key}"><meta name="korlix-map-channel" content="quarterly">
<meta name="acceptance-mode" content="${mode}"><meta name="acceptance-configured" content="${Boolean(key)}"><title>Projection map acceptance frame</title>
<link rel="stylesheet" href="/brain-projection/earth.css" nonce="${token}"><style nonce="${token}" id="korlix-sdk-style-nonce"></style>
<script type="module" src="/acceptance/frame.mjs" nonce="${token}"></script></head>
<body><div id="imagery-label">Acceptance test · Recorded Street View · Capture date unavailable · Not live</div>
<button id="begin"${key ? '' : ' disabled'}>Load test map</button><div id="map-state" role="status" aria-live="polite">${key ? 'Waiting for an explicit test.' : 'Acceptance browser key is not configured.'}</div><main id="map" aria-label="Recorded geographic imagery"></main></body></html>`;
}

export function createAcceptanceServer({browserKey = ''} = {}) {
  const key = configuredKey(browserKey);
  return createServer({maxHeaderSize: 8192, requestTimeout: 15000, headersTimeout: 10000}, async (req, res) => {
    const send = (status, type, body, policy, referrer = 'strict-origin-when-cross-origin') => {
      res.writeHead(status, {'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        'Content-Security-Policy': policy || "default-src 'none'; frame-ancestors 'none'",
        'Referrer-Policy': referrer, 'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
        ...(status === 405 ? {Allow: 'GET, HEAD'} : {})});
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    req.resume();
    if (!['GET', 'HEAD'].includes(req.method)) return send(405, 'text/plain; charset=utf-8', 'Method not allowed.');
    const path = req.url || '';
    if (!/^\/[A-Za-z0-9_./-]*$/.test(path) || path.includes('//') || path.split('/').some(part => part === '..')) {
      return send(400, 'text/plain; charset=utf-8', 'Invalid request.');
    }
    try {
      if (path === '/health') return send(200, 'application/json; charset=utf-8', JSON.stringify({service: 'projection-map-acceptance', ready: true, candidateKeyConfigured: Boolean(key), productionActivation: false}));
      if (path === '/favicon.ico') return send(204, 'image/x-icon', '');
      if (path === '/api-restriction') {
        const token = nonce();
        const policy = `default-src 'none'; script-src 'nonce-${token}' 'strict-dynamic' 'self'; style-src 'nonce-${token}'; connect-src https://identitytoolkit.googleapis.com; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;
        return send(200, 'text/html; charset=utf-8', apiRestrictionPage({key, token}), policy);
      }
      if (['/', '/no-referrer', '/wrong-origin'].includes(path)) {
        const token = nonce(), mode = path === '/' ? 'standard' : path.slice(1);
        return send(200, 'text/html; charset=utf-8', shell({keyPresent: Boolean(key), mode, token}), shellPolicy(token), mode === 'no-referrer' ? 'no-referrer' : 'strict-origin-when-cross-origin');
      }
      if (['/frame/standard', '/frame/no-referrer', '/frame/wrong-origin'].includes(path)) {
        const token = nonce(), mode = path.slice('/frame/'.length);
        return send(200, 'text/html; charset=utf-8', frame({key, mode, token}), acceptanceMapPolicy(token), mode === 'no-referrer' ? 'no-referrer' : 'strict-origin-when-cross-origin');
      }
      if (assets.has(path)) return send(200, path.endsWith('.css') ? 'text/css; charset=utf-8' : 'application/javascript; charset=utf-8', await readFile(assets.get(path), 'utf8'));
      return send(404, 'text/plain; charset=utf-8', 'Not found.');
    } catch { return send(503, 'text/plain; charset=utf-8', 'Acceptance assets are temporarily unavailable.'); }
  });
}

export function acceptancePort(value) {
  if (value === undefined || value === '') return 10000;
  if (typeof value !== 'string' || !/^\d{1,5}$/.test(value) || Number(value) < 1 || Number(value) > 65535) throw new Error('PORT must be an integer from 1 to 65535.');
  return Number(value);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const server = createAcceptanceServer({browserKey: process.env.BRAIN_PROJECTION_ACCEPTANCE_BROWSER_KEY});
  server.listen(acceptancePort(process.env.PORT), '0.0.0.0', () => console.log('Projection map acceptance is listening. Production activation is unchanged.'));
  server.on('error', () => { console.error('Acceptance server could not start.'); process.exitCode = 1; });
}
