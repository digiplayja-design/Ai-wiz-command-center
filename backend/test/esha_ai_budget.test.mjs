import test from 'node:test';
import assert from 'node:assert/strict';
import OpenAI from 'openai';
import astra from '../korlix_astra.cjs';
import {nativeAiConfiguration, nativeAiConfigured, publicCatalog} from '../esha/billing/catalog.mjs';
import {createEshaAi, eshaResponseRequest} from '../esha/billing/ai.mjs';
import {consultationInput, consultationPrompt, loadEshaCatalog, ESHA_RESULT_FORMAT} from '../esha/billing/consultation.mjs';

// These are offline fixtures for the owner's proposed option, not production
// settings or defaults. Nothing in this test contacts an OpenAI endpoint.
const proposed = {KORLIX_ESHA_TEXT_MODEL: 'gpt-6-luna', KORLIX_ESHA_REASONING_EFFORT: 'low',
  KORLIX_ESHA_ECONOMICAL_AI_APPROVED: 'true', KORLIX_ESHA_MAX_INPUT_TOKENS: '8192',
  KORLIX_ESHA_MAX_OUTPUT_TOKENS: '4096', KORLIX_ESHA_TRIAL_CONSULTATIONS: '10',
  KORLIX_ESHA_MONTHLY_CONSULTATIONS: '120', KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS: '20',
  KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS: '240', KORLIX_ESHA_NATIVE_AI_ENABLED: 'true',
  OPENAI_API_KEY: 'offline-fixture-not-a-key'};
function request(environment = proposed) {
  const input = consultationInput({requestId: '11111111-1111-4111-8111-111111111111', question: 'Pink lipstick under $20?',
    preferences: {finish: 'satin'}, history: [{role: 'user', content: 'A natural look'}, {role: 'assistant', content: 'Try a soft lip.'}]});
  return eshaResponseRequest(nativeAiConfiguration(environment), consultationPrompt(input.data, loadEshaCatalog()), ESHA_RESULT_FORMAT);
}

test('no settings retain Astra/max and fail closed; the economical option requires explicit approval and every limit', () => {
  assert.equal(nativeAiConfiguration({}).model, 'gpt-6-astra');
  assert.equal(nativeAiConfiguration({}).reasoningEffort, 'max');
  assert.equal(nativeAiConfigured({}), false);
  assert.equal(nativeAiConfigured(proposed), true);
  for (const name of ['KORLIX_ESHA_ECONOMICAL_AI_APPROVED', 'KORLIX_ESHA_REASONING_EFFORT', 'KORLIX_ESHA_MAX_INPUT_TOKENS',
    'KORLIX_ESHA_MAX_OUTPUT_TOKENS', 'KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS', 'KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS',
    'KORLIX_ESHA_TRIAL_CONSULTATIONS', 'KORLIX_ESHA_MONTHLY_CONSULTATIONS', 'KORLIX_ESHA_NATIVE_AI_ENABLED']) {
    const missing = {...proposed}; delete missing[name];
    assert.equal(nativeAiConfigured(missing), false, name);
    assert.equal(publicCatalog('apple', missing, true).purchasesEnabled, false);
  }
  for (const change of [{KORLIX_ESHA_TEXT_MODEL: 'gpt-6-sol'}, {KORLIX_ESHA_REASONING_EFFORT: 'max'},
    {KORLIX_ESHA_ECONOMICAL_AI_APPROVED: 'false'}, {KORLIX_ESHA_MAX_INPUT_TOKENS: '0'},
    {KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS: '2.4e2'}, {KORLIX_ESHA_MAX_OUTPUT_TOKENS: '128001'}]) {
    assert.equal(nativeAiConfigured({...proposed, ...change}), false);
  }
});

test('the exact model, full catalog, instructions, history, preferences and response schema are counted before the same generation', async () => {
  const calls = [], body = request();
  const ai = createEshaAi({environment: proposed, clientFactory: clientOptions => ({responses: {
    inputTokens: {count: async (value, options) => {
      calls.push({kind: 'count', value, options, clientOptions});
      return {object: 'response.input_tokens', input_tokens: 8192};
    }},
    create: async (value, options) => {
      calls.push({kind: 'generate', value, options, clientOptions});
      return {status: 'completed', output_text: '{"answer":"Try a satin lipstick.","productIds":[]}'};
    },
  }})});
  assert.equal(await ai.countInputTokens(body), 8192);
  await ai.generate(body);
  const {max_output_tokens, store, ...context} = calls[1].value;
  assert.deepEqual(calls[0].value, context);
  assert.equal(context.model, 'gpt-6-luna'); assert.deepEqual(context.reasoning, {effort: 'low'});
  assert.equal(max_output_tokens, 4096); assert.equal(store, false);
  assert.equal(context.truncation, 'disabled'); assert.deepEqual(context.text.format, ESHA_RESULT_FORMAT);
  const input = JSON.parse(context.input);
  assert.equal(input.serverCatalog.products.length, 12); assert.equal(input.userData.history.length, 2);
  assert.equal(input.userData.preferences.finish, 'satin'); assert.match(context.instructions, /serverCatalog/);
  assert.equal(calls.length, 2);
  for (const call of calls) { assert.equal(call.options.maxRetries, 0); assert.equal(call.clientOptions.maxRetries, 0); }
});

test('unapproved adapter configuration cannot send count or generation requests', async () => {
  let calls = 0;
  for (const change of [{KORLIX_ESHA_ECONOMICAL_AI_APPROVED: 'false'}, {KORLIX_ESHA_NATIVE_AI_ENABLED: 'false'},
    {KORLIX_ESHA_TRIAL_CONSULTATIONS: ''}]) {
    const ai = createEshaAi({environment: {...proposed, ...change}, clientFactory: () => { calls++; }});
    await assert.rejects(ai.countInputTokens(request()), {code: 'native_ai_not_configured'});
    await assert.rejects(ai.generate(request()), {code: 'native_ai_not_configured'});
  }
  assert.equal(calls, 0);
});

test('SDK retry hints cannot cause an uncounted paid retry or fallback', async () => {
  let calls = 0;
  const urls = [];
  const ai = createEshaAi({environment: proposed, clientFactory: options => new OpenAI({...options,
    fetch: async url => {
      calls++; urls.push(String(url));
      return new Response(JSON.stringify({error: {message: 'offline fixture rate limit', type: 'rate_limit_error'}}), {
        status: 429, headers: {'content-type': 'application/json', 'retry-after': '0', 'x-should-retry': 'true'},
      });
    },
  })});
  await assert.rejects(ai.generate(request()));
  assert.equal(calls, 1); assert.match(urls[0], /\/responses$/);
  await assert.rejects(ai.countInputTokens(request()));
  assert.equal(calls, 2); assert.match(urls[1], /\/responses\/input_tokens$/);
});

test('incomplete economical output is rejected once without Astra fallback', async () => {
  let calls = 0;
  const ai = createEshaAi({environment: proposed, clientFactory: () => ({responses: {create: async () => {
    calls++; return {status: 'incomplete', output_text: '{"answer":"partial","productIds":[]}'};
  }}})});
  await assert.rejects(ai.generate(request()), {code: 'invalid_ai_response'});
  assert.equal(calls, 1);
});

test('Astra remains max with its existing output floor, including callers outside Esha', async () => {
  const environment = {...proposed, KORLIX_ESHA_TEXT_MODEL: 'gpt-6-astra', KORLIX_ESHA_REASONING_EFFORT: 'max',
    KORLIX_ESHA_MAX_OUTPUT_TOKENS: '32768'};
  const bodies = [];
  const client = {responses: {create: async body => { bodies.push(body); return {status: 'completed'}; }}};
  await createEshaAi({environment, clientFactory: () => client}).generate(request(environment));
  await astra.createTextResponse(client, {model: 'gpt-6-luna', reasoning: {effort: 'low'}, max_output_tokens: 4096, input: 'Other Korlix app'});
  for (const body of bodies) {
    assert.equal(body.model, 'gpt-6-astra'); assert.equal(body.reasoning.effort, 'max'); assert.equal(body.max_output_tokens, 32768);
  }
});
