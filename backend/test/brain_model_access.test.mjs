import test from 'node:test';
import assert from 'node:assert/strict';
import {checkBrainModelAccess} from '../brain_voice/model_access.mjs';

test('model access check retrieves only Sol metadata and never generates or reveals a key', async () => {
  let calls = 0;
  const result = await checkBrainModelAccess({apiKey: 'fixture-secret', fetchImpl: async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.openai.com/v1/models/gpt-6.1-sol');
    assert.equal(options.body, undefined);
    assert.equal(options.headers.Authorization, 'Bearer fixture-secret');
    return Response.json({id: 'gpt-6.1-sol', object: 'model'});
  }});
  assert.deepEqual(result, {model: 'gpt-6.1-sol', status: 'available', providerStatus: 200});
  assert.equal(calls, 1); assert.ok(!JSON.stringify(result).includes('fixture-secret'));
});
test('missing access, mismatched metadata and network failure stay unverified without retries', async () => {
  assert.equal((await checkBrainModelAccess({apiKey: '', fetchImpl: () => assert.fail('must not fetch')})).status, 'not_configured');
  for (const response of [new Response('private provider detail', {status: 403}), Response.json({id: 'gpt-6-astra', object: 'model'}), Response.json({id: 'gpt-6.1-sol', object: 'error'})]) {
    assert.equal((await checkBrainModelAccess({apiKey: 'fixture', fetchImpl: async () => response})).status, 'unverified');
  }
  const result = await checkBrainModelAccess({apiKey: 'fixture', fetchImpl: async () => {throw Error('secret');}});
  assert.deepEqual(result, {model: 'gpt-6.1-sol', status: 'unverified'});
});
