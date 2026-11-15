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
    assert.match(html, /New membership purchases and live voice are currently unavailable/);
    assert.doesNotMatch(html, /<script\b|<iframe\b|<input\b/i);
    if (path.endsWith('privacy')) {
      assert.match(html, /id="deletion"/);
      assert.match(html, /Esha%20account%20deletion/);
      assert.match(html, /does not mean deletion has already finished/);
      assert.match(html, /Hash-only records/);
      assert.match(html, /Korlix and OpenAI/);
      assert.match(html, /Optional live voice, when enabled/);
      assert.match(html, /microphone audio and conversation transcripts are processed by Korlix and OpenAI/);
      assert.match(html, /Before each call<\/strong>, you must explicitly allow audio and conversation sharing/);
      assert.match(html, /Deep thinking during a call is a separate, optional choice that starts off/);
      assert.match(html, /device permission alone does not start a call/);
      assert.match(html, /does not promise zero provider retention/);
      assert.doesNotMatch(html, /does not capture photographs, microphone recordings or location/);
    } else {
      assert.match(html, /3 days free for eligible subscribers, then \$4\.99 USD per month/);
      assert.match(html, /configured trial and monthly consultation counts before enabling a new purchase/);
      assert.match(html, /Planned launch inclusions, once enabled/);
      assert.match(html, /5 voice minutes and 2 Sol deep-thinking consultations/);
      assert.match(html, /30 voice minutes and 10 Sol deep-thinking consultations/);
      assert.match(html, /voice time includes silence and time waiting for answers/);
      assert.doesNotMatch(html, /does not provide camera analysis, medical assessment, voice consultation/);
      assert.match(html, /Restore purchases/);
      assert.match(html, /Manage subscription/);
      assert.match(html, /itunes\/dev\/stdeula/);
    }
  }
});
