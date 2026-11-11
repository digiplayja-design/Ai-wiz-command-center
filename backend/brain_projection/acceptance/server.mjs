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
  ['/brain-projection/earth.mjs', new URL('../public/earth.mjs', import.meta.url)],
  ['/brain-projection/camera.mjs', new URL('../public/camera.mjs', import.meta.url)],
  ['/brain-projection/earth.css', new URL('../public/earth.css', import.meta.url)],
]);

function shell({keyPresent, negative, token}) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Projection map acceptance</title><meta name="acceptance-mode" content="${negative ? 'no-referrer' : 'standard'}"><meta name="acceptance-configured" content="${keyPresent}">
<style nonce="${token}">
:root{color-scheme:dark;font:16px/1.5 system-ui,sans-serif;background:#07131e;color:#eaf5fc}*{box-sizing:border-box}body{margin:0}main{max-width:1120px;margin:auto;padding:24px}h1{font-size:clamp(26px,5vw,38px);margin:0 0 8px}h2{font-size:20px;margin:0 0 12px}p{margin:8px 0 16px}.muted{color:#b8ccdc}.tag{color:#92e7d3;font-weight:700;letter-spacing:.08em;font-size:12px;text-transform:uppercase}.panel{padding:20px;background:#102333;border:1px solid #284357;border-radius:14px;margin:18px 0}.actions{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0}button,a{font:inherit}button{padding:10px 16px;border:1px solid #4a738b;border-radius:9px;background:#17394e;color:#fff;cursor:pointer}button.primary{background:#88e7d1;color:#05251c;font-weight:700;border-color:#88e7d1}button:disabled{opacity:.45;cursor:default}a{color:#a0d9ff}button:focus-visible,a:focus-visible{outline:3px solid #ffd28a;outline-offset:3px}.stage{height:60vh;min-height:360px;max-height:760px;border:1px solid #375369;border-radius:12px;overflow:hidden;background:#030b13}.stage p{padding:24px}iframe{width:100%;height:100%;border:0;display:block}.checks label{display:block;margin:12px 0}.checks input{margin-right:8px;accent-color:#88e7d1}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.5 ui-monospace,monospace;background:#07131e;padding:16px;border-radius:8px;max-height:430px;overflow:auto}.notice{border-left:4px solid #ffd28a;padding-left:14px}#verdict{font-weight:700;color:#a4e8ff}footer{font-size:13px;color:#b8ccdc;margin-top:24px}@media(max-width:500px){main{padding:16px}.panel{padding:16px}.stage{min-height:400px}button{flex:1 1 auto}}
</style><script type="module" src="/acceptance/client.mjs" nonce="${token}"></script></head>
<body><main><div class="tag">Isolated SDK check</div><h1>Projection map acceptance</h1>
<p class="muted">Recorded geographic imagery, not live cameras. This service cannot activate the production map or change account access.</p>
<nav><a href="/">Allowed-origin check</a> · <a href="/no-referrer">No-referrer negative check</a></nav>
<section class="panel"><h2>${negative ? 'Deliberate no-referrer check' : 'Allowed-origin rendering check'}</h2>
<p>Acceptance origin: <strong id="origin"></strong></p>
${negative ? '<p class="notice">This negative view sets a no-referrer document policy and overrides the SDK loader policy immediately before insertion. Inspect the actual Google SDK and authorization request headers. A blank map or generic error is inconclusive.</p>' : '<p>Load the candidate key from this exact HTTPS origin. After the SDK finishes, inspect the landmark, controls, Google attribution and legal links. No Google SDK loads before you press the button.</p>'}
<p id="setup">${keyPresent ? 'Candidate key configured. Waiting for an explicit test.' : 'Setup required: the acceptance browser key is missing or invalid. No Google request will be made.'}</p>
<div class="actions"><button class="primary" id="start"${keyPresent ? '' : ' disabled'}>Load test map</button><button id="stop" disabled>Close test map</button></div>
<p id="status" role="status" aria-live="polite">Not started.</p></section>
<div class="stage" id="stage"><p>The map test will appear here after you press Load test map.</p></div>
<section class="panel"><h2>Camera checks</h2><p>Use the San Francisco Ferry Building, a public landmark. Confirm the scene visually; provider coverage is not assumed from a successful script load.</p>
<p id="camera-status" role="status">Load the test map to enable camera controls.</p><p id="policy-status" class="notice" role="status" hidden></p>
<div class="actions" id="camera-controls"><button data-operation="flyTo" disabled>Fly to landmark</button><button data-operation="closer" disabled>Closer</button><button data-operation="farther" disabled>Farther</button><button data-operation="left" disabled>Left</button><button data-operation="right" disabled>Right</button><button data-operation="reset" disabled>Reset</button></div></section>
<section class="panel checks"><h2>Tester observations</h2>
${negative ? '<label><input id="headers-confirmed" type="checkbox" disabled>I inspected the relevant Google SDK and authorization requests and confirmed their Referer header was absent.</label><p>A specific referrer-denial code must also be captured below. Wrong-origin testing needs a separately controlled unapproved HTTPS origin; this service does not forge an allowed Referer.</p>' : '<label><input id="imagery-confirmed" type="checkbox" disabled>I can identify real geographic imagery at the landmark and the camera controls work.</label><label><input id="attribution-confirmed" type="checkbox" disabled>Google attribution is unobscured and its legal links work, including at a narrow viewport.</label>'}
<p id="verdict" role="status">No observation recorded.</p><p>These observations do not establish all API restrictions, quotas or iPhone/Android WebView behavior. The production verification gate remains unchanged.</p></section>
<section class="panel"><h2>Sanitized evidence</h2><p>Contains public SDK/version/state information, categorized policy events and your checkboxes. It excludes keys, raw provider errors, request URLs and headers.</p><button id="copy">Copy evidence</button><span id="copy-status" aria-live="polite"></span><pre id="evidence"></pre></section>
<footer>No account sign-in, database, geocoding service, AI calls or provider proxy is used here. Reloading or closing the page clears this local evidence.</footer></main></body></html>`;
}

function frame({key, negative, token}) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="${negative ? 'no-referrer' : 'strict-origin-when-cross-origin'}"><meta name="korlix-map-key" content="${key}"><meta name="korlix-map-channel" content="quarterly">
<meta name="acceptance-mode" content="${negative ? 'no-referrer' : 'standard'}"><meta name="acceptance-configured" content="${Boolean(key)}"><title>Projection map acceptance frame</title>
<link rel="stylesheet" href="/brain-projection/earth.css" nonce="${token}"><style nonce="${token}" id="korlix-sdk-style-nonce"></style>
<script type="module" src="/acceptance/frame.mjs" nonce="${token}"></script></head>
<body><div id="imagery-label">Acceptance test · Recorded 3D imagery, not live cameras · Capture date unavailable</div>
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
      if (path === '/' || path === '/no-referrer') {
        const token = nonce();
        return send(200, 'text/html; charset=utf-8', shell({keyPresent: Boolean(key), negative: path === '/no-referrer', token}), shellPolicy(token));
      }
      if (path === '/frame/standard' || path === '/frame/no-referrer') {
        const token = nonce(), negative = path === '/frame/no-referrer';
        return send(200, 'text/html; charset=utf-8', frame({key, negative, token}), acceptanceMapPolicy(token), negative ? 'no-referrer' : 'strict-origin-when-cross-origin');
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
