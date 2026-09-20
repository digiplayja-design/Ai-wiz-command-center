'use strict';

// Public, synthetic-audio diagnostic. No credentials, capture, or meeting data.
const fs = require('node:fs');
const path = require('node:path');
const PREFIX = '/k135z/audio-output-test/';
const FILES = {'':'index.html','probe.mjs':'probe.mjs','page.mjs':'page.mjs','style.css':'style.css'};
function registerAudioProbe(app) {
  for (const [suffix, file] of Object.entries(FILES)) {
    const body = fs.readFileSync(path.join(__dirname, 'audio_probe', file));
    app.get(PREFIX + suffix, (_req, res) => {
      res.setHeader('Cache-Control', 'no-store');
      res.setHeader('Strict-Transport-Security', 'max-age=31536000');
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.setHeader('Referrer-Policy', 'no-referrer');
      res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self' https://appssdk.zoom.us; style-src 'self'; connect-src 'self' https://appssdk.zoom.us; img-src 'self'; media-src 'self' blob:; base-uri 'none'; form-action 'none'; frame-ancestors 'self' https://*.zoom.us");
      res.setHeader('Content-Type', file.endsWith('.html') ? 'text/html; charset=utf-8' :
        file.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/javascript; charset=utf-8');
      res.status(200).end(body);
    });
  }
}
module.exports = {registerAudioProbe, PREFIX};
