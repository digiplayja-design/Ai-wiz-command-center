'use strict';
// K136S-C standalone preview server (node:http only — no express, no new dependencies).
// It does the I/O the handler deliberately avoids: read the request body (with a hard size cap),
// hand a plain request object to the pure handler, and write the JSON response. It mounts NOTHING
// into backend/server.js and opens exactly one K136S port. Run it directly for local testing:
//   K136S_GRANT_KEY=... K136S_ALLOW_DEV_GRANT=1 node backend/k136s_learning/http/preview_server.cjs
const http = require('node:http');
const { createPreviewHandler, MAX_BODY_BYTES } = require('./preview_handler.cjs');

const DEFAULT_PORT = 7461;      // K136S reserved range is 7460-7469
const DEFAULT_HOST = '127.0.0.1'; // loopback only; forwarding is opt-in via the Codespaces Ports panel

function send(res, status, obj) {
  const payload = Buffer.from(JSON.stringify(obj), 'utf8');
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': payload.length, 'cache-control': 'no-store' });
  res.end(payload);
}

// createServer returns an http.Server WITHOUT listening, so tests can bind an ephemeral port.
function createServer({ key, allowDevGrant = false, now = Date.now, maxBodyBytes = MAX_BODY_BYTES } = {}) {
  const handle = createPreviewHandler({ key, allowDevGrant, now });
  return http.createServer((req, res) => {
    const chunks = [];
    let size = 0;
    let aborted = false;
    req.on('data', (c) => {
      if (aborted) return;
      size += c.length;
      if (size > maxBodyBytes) { aborted = true; send(res, 413, { error: 'payload too large' }); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('error', () => { if (!aborted) { aborted = true; try { send(res, 400, { error: 'bad request' }); } catch { /* ignore */ } } });
    req.on('end', () => {
      if (aborted) return;
      const rawBody = Buffer.concat(chunks).toString('utf8');
      let out;
      try { out = handle({ method: req.method, path: req.url, headers: req.headers, rawBody }); }
      catch (e) { return send(res, 500, { error: 'internal error' }); }
      send(res, out.status, out.json);
    });
  });
}

function start() {
  const key = process.env.K136S_GRANT_KEY;
  if (typeof key !== 'string' || key.length < 16) {
    console.error('STOP: K136S_GRANT_KEY missing or too short (need >= 16 chars). Refusing to start.');
    process.exit(1);
  }
  const port = Number(process.env.K136S_PORT || DEFAULT_PORT);
  const host = process.env.K136S_HOST || DEFAULT_HOST;
  const allowDevGrant = process.env.K136S_ALLOW_DEV_GRANT === '1';
  const server = createServer({ key, allowDevGrant, now: Date.now });
  server.listen(port, host, () => {
    console.log(`k136s-preview listening on http://${host}:${port}  (dev-grant: ${allowDevGrant ? 'ON' : 'off'}, read-only, no DB)`);
  });
  const shutdown = (sig) => { console.log(`k136s-preview received ${sig}, closing`); server.close(() => process.exit(0)); };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  return server;
}

if (require.main === module) start();

module.exports = Object.freeze({ createServer, start, DEFAULT_PORT, DEFAULT_HOST });
