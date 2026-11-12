import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {projectionConfiguration, RENDERER_PATH} from './core.mjs';

// Core Map3DElement APIs are available in the supported quarterly channel.
// https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map
export const MAPS_JS_CHANNEL = 'quarterly';
const newNonce = () => randomBytes(18).toString('base64url');
const validNonce = value => typeof value === 'string' && /^[A-Za-z0-9_-]{24,128}$/.test(value);

const escapeAttribute = value => value.replace(/[&"<>']/gu, c => ({'&': '&amp;', '"': '&quot;', '<': '&lt;', '>': '&gt;', "'": '&#39;'}[c]));
export function rendererDocument(environment = process.env, {nonce = newNonce()} = {}) {
  if (!validNonce(nonce)) throw new TypeError('A valid renderer nonce is required.');
  const {browserKey, origin} = projectionConfiguration(environment);
  const key = browserKey && origin ? browserKey : '';
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="referrer" content="strict-origin-when-cross-origin"><meta name="korlix-map-key" content="${escapeAttribute(key)}">
<meta name="korlix-map-channel" content="${MAPS_JS_CHANNEL}">
<title>KORLIX property view</title>
<link rel="stylesheet" href="/brain-projection/earth.css" nonce="${nonce}">
<style nonce="${nonce}" id="korlix-sdk-style-nonce"></style>
<script type="module" src="/brain-projection/earth.mjs" nonce="${nonce}"></script></head>
<body><div id="imagery-label">Recorded Street View · Capture date unavailable · Not live</div>
<div id="map-state" role="status" aria-live="polite">${key ? 'Preparing recorded street-level imagery…' : 'Geographic imagery is not connected yet.'}</div>
<main id="map" aria-label="Recorded geographic imagery"></main></body></html>`;
}

export function rendererPolicy(nonce) {
  if (!validNonce(nonce)) throw new TypeError('A valid renderer nonce is required.');
  // Follow Google's nonce-based CSP. The trusted local module inserts the SDK
  // only after authentication/error handlers are installed; the SDK inherits
  // script/style nonces. No unsafe-inline script allowance or broad HTTPS
  // script fallback is needed. This applies only to the isolated map document.
  // The SDK also sets dynamic style attributes (observed on iPad). Nonces
  // cannot authorize attributes: allow those here, while style elements stay
  // subject to the existing style-src policy. This permits all style attributes
  // in this static document, which accepts no user-supplied HTML.
  // https://developers.google.com/maps/documentation/javascript/content-security-policy
  return [
    "default-src 'none'",
    `script-src 'nonce-${nonce}' 'strict-dynamic' 'self' https://maps.googleapis.com https://maps.gstatic.com 'unsafe-eval' blob:`,
    `style-src 'self' 'nonce-${nonce}' https://fonts.googleapis.com`,
    "style-src-attr 'unsafe-inline'",
    "img-src 'self' https://*.googleapis.com https://*.gstatic.com https://*.google.com https://*.googleusercontent.com data: blob:",
    "connect-src 'self' https://*.googleapis.com https://*.google.com https://*.gstatic.com data: blob:",
    "font-src https://fonts.gstatic.com", "worker-src blob:",
    "frame-src https://*.google.com",
    "object-src 'none'", "base-uri 'none'", "form-action 'none'",
  ].join('; ');
}

export function registerProjectionRenderer(app, {environment = process.env} = {}) {
  const headers = (res, policy = "default-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'") => res.set({
    'Cache-Control': 'no-store', 'Content-Security-Policy': policy, 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
  });
  app.get(RENDERER_PATH, (_req, res) => {
    // Public map-only document. It never consumes cookies, bearer tokens or
    // local-app bridge messages. Opaque file parents are intentionally supported.
    const nonce = newNonce();
    headers(res, rendererPolicy(nonce)).type('html').send(rendererDocument(environment, {nonce}));
  });
  for (const filename of ['earth.mjs', 'camera.mjs', 'street.mjs', 'earth.css']) {
    app.get(`/brain-projection/${filename}`, async (_req, res) => {
      try {
        const content = await readFile(new URL(`./public/${filename}`, import.meta.url), 'utf8');
        headers(res).type(filename.endsWith('.css') ? 'css' : 'application/javascript').send(content);
      } catch {
        headers(res).status(503).type('text').send('Projection renderer is temporarily unavailable.');
      }
    });
  }
}
