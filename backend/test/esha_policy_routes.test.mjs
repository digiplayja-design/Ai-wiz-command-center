import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {registerEshaPolicyRoutes} from '../esha/policies.mjs';

test('Esha policy and deletion notices are public, readable HTML without account access', async t => {
  const app = express();
  registerEshaPolicyRoutes(app);
  const server = await new Promise(resolve => {
    const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
  });
  t.after(() => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())));
  const origin = `http://127.0.0.1:${server.address().port}`;
  for (const path of ['/esha/privacy', '/esha/terms']) {
    const result = await fetch(origin + path);
    assert.equal(result.status, 200);
    assert.match(result.headers.get('content-type'), /text\/html.*charset=utf-8/i);
    assert.equal(result.headers.get('cache-control'), 'no-store');
    assert.equal(result.headers.get('x-content-type-options'), 'nosniff');
    assert.match(result.headers.get('content-security-policy'), /default-src 'none'/);
    assert.match(result.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    const html = await result.text();
    assert.match(html, /<html lang="en">/);
    assert.match(html, /<meta name="viewport"/);
    assert.match(html, /Esha by Korlix/);
    assert.match(html, /support@korlixdeveloper\.com/);
    assert.match(html, /href="\/esha\/privacy#deletion"/);
    assert.doesNotMatch(html, /<script\b|<iframe\b|<input\b/i);
    assert.match(html, /November 16, 2026/);
    assert.match(html, /existing developer access grant/);
    assert.match(html, /New membership purchases and live voice are currently unavailable/);
    assert.doesNotMatch(html, /illustrated looks do not request photos|illustrated looks do not analyze a face|does not capture photographs/);
    if (path.endsWith('privacy')) {
      assert.match(html, /id="deletion"/);
      assert.match(html, /Esha%20account%20deletion/);
      assert.match(html, /does not mean deletion has already finished/);
      assert.match(html, /Hash-only records/);
      assert.match(html, /Korlix and OpenAI/);
      assert.match(html, /Optional selfie try-on/);
      assert.match(html, /photo picker so you can select one image/);
      assert.match(html, /does not open the camera, request full photo metadata or request device location/);
      assert.match(html, /Apple Vision on iOS or bundled Google ML Kit on Android/);
      assert.match(html, /does not send them to Korlix or OpenAI, include them in an AI consultation or add them to vanity sync/);
      assert.match(html, /only for the current app session and clears them when you remove the photo, sign out or switch accounts/);
      assert.match(html, /During normal operation, Esha removes its app-owned temporary picker copy after reading or discarding it; your original library photo is unchanged/);
      assert.match(html, /If the app stops unexpectedly or the device cannot delete the file/);
      assert.match(html, /temporary copy can remain in the app's cache until the device clears that cache or the app is removed/);
      assert.match(html, /picker results retrieved from an interrupted previous app process are discarded/);
      assert.match(html, /attempts to remove their app-owned temporary copies and never restores those photos into a new session/);
      assert.match(html, /Google ML Kit sends SDK diagnostics and usage metrics to Google/);
      assert.match(html, /per-installation identifiers/);
      assert.match(html, /https:\/\/developers\.google\.com\/ml-kit\/android-data-disclosure/);
      assert.match(html, /does not mean the SDK sends no diagnostic data/);
      assert.match(html, /Saving a look stores your shade, finish and lash choices, not the selfie or facial landmarks/);
    } else {
      assert.match(html, /one existing photo through the device photo picker for a local selfie preview/);
      assert.match(html, /does not identify a person, infer skin tone or perform a medical assessment/);
      assert.match(html, /No camera capture is offered/);
      assert.match(html, /does not save or sync your photo or facial landmarks/);
      assert.match(html, /Colors, finishes and effect placement are approximate/);
      assert.match(html, /3 days free for eligible subscribers, then \$4\.99 USD per month/);
      assert.match(html, /configured trial and monthly consultation counts before enabling a new purchase/);
      assert.match(html, /Restore purchases/);
      assert.match(html, /Manage subscription/);
      assert.match(html, /itunes\/dev\/stdeula/);
    }
  }
});
