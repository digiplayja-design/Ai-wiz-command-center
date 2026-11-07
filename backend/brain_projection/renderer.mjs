import {readFile} from 'node:fs/promises';
import {projectionConfiguration, RENDERER_PATH} from './core.mjs';

export const CESIUM_VERSION = '1.147';
export const CESIUM_ROOT = `https://cesium.com/downloads/cesiumjs/releases/${CESIUM_VERSION}/Build/Cesium/`;
// SHA-384 of the official versioned release, checked 2026-11-07. Workers/assets
// use the same pinned directory. No Cesium ion subscription or token is used.
export const CESIUM_JS_INTEGRITY = 'sha384-MsL9BLNAnIOaKqfaH6xNODs0FmBa4Ol8wwzL5MJ+w3w+63xjOHH0MD8x1uZoKlZg';
export const CESIUM_CSS_INTEGRITY = 'sha384-ghEeMdcWWzRv/BPeUcX835vcKDGrxvROXisl/Btpv3GeekBUXTSPVcFJpI1Tcrgp';

const escapeAttribute = value => value.replace(/[&"<>']/gu, c => ({'&': '&amp;', '"': '&quot;', '<': '&lt;', '>': '&gt;', "'": '&#39;'}[c]));
export function rendererDocument(environment = process.env) {
  const {browserKey, origin} = projectionConfiguration(environment);
  const key = browserKey && origin ? browserKey : '';
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="referrer" content="strict-origin-when-cross-origin"><meta name="korlix-map-key" content="${escapeAttribute(key)}">
<title>KORLIX Projection map</title>
<link rel="stylesheet" href="/brain-projection/earth.css">
${key ? `<link rel="stylesheet" href="${CESIUM_ROOT}Widgets/widgets.css" integrity="${CESIUM_CSS_INTEGRITY}" crossorigin="anonymous">
<script defer src="${CESIUM_ROOT}Cesium.js" integrity="${CESIUM_JS_INTEGRITY}" crossorigin="anonymous"></script>` : ''}
<script type="module" src="/brain-projection/earth.mjs"></script></head>
<body><main id="map" aria-label="Recorded geographic imagery"></main>
<div id="map-state" role="status" aria-live="polite">${key ? 'Connecting recorded 3D imagery…' : 'Geographic imagery is not connected yet.'}</div>
<div id="imagery-label">Recorded 3D imagery · Capture date unavailable</div>
<div id="map-credits" aria-label="Map attribution"></div></body></html>`;
}

const csp = [
  "default-src 'none'",
  "script-src 'self' https://cesium.com 'wasm-unsafe-eval'",
  // Cesium positions its canvas and attribution with inline style properties.
  "style-src 'self' 'unsafe-inline' https://cesium.com",
  "img-src 'self' data: blob: https://cesium.com https://tile.googleapis.com https://assets.ion.cesium.com https://maps.gstatic.com",
  "connect-src 'self' https://cesium.com https://tile.googleapis.com",
  "worker-src blob: https://cesium.com",
  "font-src 'self' data: https://cesium.com",
  "frame-src 'none'", "object-src 'none'", "base-uri 'none'", "form-action 'none'",
].join('; ');

export function registerProjectionRenderer(app, {environment = process.env} = {}) {
  const headers = res => res.set({
    'Cache-Control': 'no-store', 'Content-Security-Policy': csp, 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
  });
  app.get(RENDERER_PATH, (_req, res) => {
    // Public map-only document. It never consumes cookies, bearer tokens or
    // local-app bridge messages. Opaque file parents are intentionally supported.
    headers(res).type('html').send(rendererDocument(environment));
  });
  for (const filename of ['earth.mjs', 'camera.mjs', 'earth.css']) {
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
