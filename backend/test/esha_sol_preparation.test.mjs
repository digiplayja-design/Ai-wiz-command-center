import test from 'node:test';
import assert from 'node:assert/strict';
import OpenAI from 'openai';
import {ESHA_AI_ROLE_POLICY, nativeAiConfiguration, nativeAiConfigured, publicCatalog} from '../esha/billing/catalog.mjs';
import {createEshaAi, eshaResponseRequest} from '../esha/billing/ai.mjs';
import {createEshaBilling} from '../esha/billing/routes.mjs';
import {consultationInput, consultationPrompt, loadEshaCatalog, ESHA_RESULT_FORMAT} from '../esha/billing/consultation.mjs';

const role = 'deep_thinking';
// Offline test values only: no commercial allowances or token budgets are defaults.
const environment = {KORLIX_ESHA_AI_POLICY: ESHA_AI_ROLE_POLICY,
  KORLIX_ESHA_MAX_INPUT_TOKENS: '8192', KORLIX_ESHA_MAX_OUTPUT_TOKENS: '4096',
  KORLIX_ESHA_TRIAL_CONSULTATIONS: '2', KORLIX_ESHA_MONTHLY_CONSULTATIONS: '4',
  KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS: '3', KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS: '6',
  KORLIX_ESHA_NATIVE_AI_ENABLED: 'true', KORLIX_ESHA_BILLING_ENABLED: 'true',
  KORLIX_ESHA_APPLE_PRODUCTS_READY: 'true', KORLIX_ESHA_GOOGLE_PRODUCTS_READY: 'true',
  OPENAI_API_KEY: 'offline-fixture-not-a-key'};
const question = {requestId: '11111111-1111-4111-8111-111111111111', question: 'Compare satin lipsticks under $20.',
  preferences: {finish: 'satin'}, history: [{role: 'user', content: 'I prefer a natural look.'}]};
function request(env = environment) {
  return eshaResponseRequest(nativeAiConfiguration(env, {role}),
    consultationPrompt(consultationInput(question).data, loadEshaCatalog()), ESHA_RESULT_FORMAT);
}

test('prepared policy resolves only Sol/high and never assigns the unresolved conversational role', () => {
  const conversation = nativeAiConfiguration(environment);
  assert.equal(conversation.role, 'conversation');
  assert.equal(conversation.requestedModel, 'GPT 2.5 conversational');
  assert.equal(conversation.model, null); assert.equal(conversation.reasoningEffort, null);
  assert.equal(conversation.resolved, false); assert.equal(conversation.configured, false);
  assert.equal(nativeAiConfigured(environment), false);
  assert.throws(() => eshaResponseRequest(conversation, {}, ESHA_RESULT_FORMAT), {code: 'native_ai_not_configured'});
  const deep = nativeAiConfiguration(environment, {role});
  assert.equal(deep.model, 'gpt-6.1-sol'); assert.equal(deep.reasoningEffort, 'high');
  assert.equal(deep.resolved, true); assert.equal(deep.configured, true);
  assert.equal(nativeAiConfigured(environment, {role}), true);
  for (const provider of ['apple', 'google']) {
    const catalog = publicCatalog(provider, environment, true);
    assert.equal(catalog.consultationEnabled, false); assert.equal(catalog.purchasesEnabled, false);
    assert.equal(catalog.state, 'planned');
  }
});

test('unknown policies, unknown roles and conflicting legacy overrides cannot select a fallback', () => {
  for (const policy of ['', 'unknown-policy', null]) {
    assert.equal(nativeAiConfiguration({...environment, KORLIX_ESHA_AI_POLICY: policy}, {role}).configured, false);
  }
  for (const selectedRole of ['conversation', 'deep-thinking', 'toString', '__proto__', '', ['deep_thinking'],
    new String('deep_thinking'), {toString: () => 'deep_thinking'}]) {
    assert.equal(nativeAiConfiguration(environment, {role: selectedRole}).configured, false);
  }
  const legacy = {...environment}; delete legacy.KORLIX_ESHA_AI_POLICY;
  assert.equal(nativeAiConfiguration(legacy, {role}).configured, false);
  assert.equal(nativeAiConfiguration({...legacy, KORLIX_ESHA_TEXT_MODEL: 'gpt-6.1-sol',
    KORLIX_ESHA_REASONING_EFFORT: 'high'}).configured, false);
  for (const change of [{KORLIX_ESHA_TEXT_MODEL: 'gpt-6-luna'}, {KORLIX_ESHA_TEXT_MODEL: 'gpt-2.5'},
    {KORLIX_ESHA_REASONING_EFFORT: 'none'}, {KORLIX_ESHA_REASONING_EFFORT: 'max'}]) {
    assert.equal(nativeAiConfiguration({...environment, ...change}, {role}).configured, false);
  }
});

test('Sol preparation chooses no allowances or budgets and requires every existing activation and cap setting', () => {
  const empty = nativeAiConfiguration({KORLIX_ESHA_AI_POLICY: ESHA_AI_ROLE_POLICY}, {role});
  assert.equal(empty.model, 'gpt-6.1-sol'); assert.equal(empty.configured, false);
  for (const field of ['maxInputTokens', 'maxOutputTokens', 'trialAttempts', 'monthlyAttempts']) assert.equal(empty[field], null);
  for (const name of ['KORLIX_ESHA_MAX_INPUT_TOKENS', 'KORLIX_ESHA_MAX_OUTPUT_TOKENS',
    'KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS', 'KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS',
    'KORLIX_ESHA_TRIAL_CONSULTATIONS', 'KORLIX_ESHA_MONTHLY_CONSULTATIONS', 'KORLIX_ESHA_NATIVE_AI_ENABLED']) {
    const missing = {...environment}; delete missing[name];
    assert.equal(nativeAiConfigured(missing, {role}), false, name);
  }
  for (const change of [{KORLIX_ESHA_MAX_INPUT_TOKENS: '922001'}, {KORLIX_ESHA_MAX_OUTPUT_TOKENS: '128001'},
    {KORLIX_ESHA_MAX_OUTPUT_TOKENS: '255'}, {KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS: '0'},
    {KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS: '1e2'}]) {
    assert.equal(nativeAiConfiguration({...environment, ...change}, {role}).configured, false);
  }
});

test('Sol counts the exact structured request context and sends one capped high-reasoning Responses request', async () => {
  const calls = [], body = request();
  const ai = createEshaAi({environment, role, clientFactory: clientOptions => ({responses: {
    inputTokens: {count: async (value, options) => {
      calls.push({kind: 'count', value, options, clientOptions});
      return {object: 'response.input_tokens', input_tokens: 8000};
    }},
    create: async (value, options) => {
      calls.push({kind: 'generate', value, options, clientOptions});
      return {status: 'completed', output_text: '{"answer":"Compare the listed satin finishes.","productIds":[]}'};
    },
  }})});
  assert.equal(await ai.countInputTokens(body), 8000);
  assert.equal((await ai.generate(body)).status, 'completed');
  assert.deepEqual(calls.map(call => call.kind), ['count', 'generate']);
  const {max_output_tokens, store, ...context} = calls[1].value;
  assert.deepEqual(calls[0].value, context);
  assert.equal(context.model, 'gpt-6.1-sol'); assert.deepEqual(context.reasoning, {effort: 'high'});
  assert.equal(max_output_tokens, 4096); assert.equal(store, false); assert.equal(context.truncation, 'disabled');
  assert.deepEqual(context.text.format, ESHA_RESULT_FORMAT);
  assert.equal(JSON.parse(context.input).serverCatalog.products.length, 12);
  assert.equal(JSON.parse(context.input).userData.preferences.finish, 'satin');
  for (const key of ['role', 'temperature', 'top_p', 'top_logprobs', 'logprobs', 'tools']) assert.equal(context[key], undefined);
  for (const call of calls) { assert.equal(call.options.maxRetries, 0); assert.equal(call.clientOptions.maxRetries, 0); }
});

test('missing server role, disabled configuration and altered Sol request contracts stop before any provider client', async () => {
  let clients = 0;
  const clientFactory = () => { clients++; throw Error('Provider client must not be reached'); };
  for (const options of [{environment}, {environment, role: 'conversation'}, {environment, role: 'unknown'},
    {environment: {...environment, KORLIX_ESHA_NATIVE_AI_ENABLED: 'false'}, role}]) {
    const ai = createEshaAi({...options, clientFactory});
    await assert.rejects(ai.countInputTokens(request()), {code: 'native_ai_not_configured'});
    await assert.rejects(ai.generate(request()), {code: 'native_ai_not_configured'});
  }
  const ai = createEshaAi({environment, role, clientFactory});
  for (const change of [{model: 'gpt-6-astra'}, {model: 'gpt-2.5'}, {reasoning: {effort: 'none'}},
    {reasoning: {effort: 'max'}}, {max_output_tokens: 4097}, {store: true}, {truncation: 'auto'},
    {text: {format: {...ESHA_RESULT_FORMAT, strict: false}}}, {text: {format: {type: 'json_object'}}}]) {
    const altered = {...request(), ...change};
    await assert.rejects(ai.countInputTokens(altered), {code: 'native_ai_not_configured'});
    await assert.rejects(ai.generate(altered), {code: 'native_ai_not_configured'});
  }
  assert.throws(() => eshaResponseRequest(nativeAiConfiguration(environment, {role}), {}, {type: 'json_object'}),
    {code: 'native_ai_not_configured'});
  assert.equal(clients, 0);
});

test('the real SDK cannot retry Sol generation or counting despite provider retry hints', async () => {
  const calls = [];
  const ai = createEshaAi({environment, role, clientFactory: options => new OpenAI({...options,
    fetch: async (url, init) => {
      calls.push({url: String(url), body: JSON.parse(init.body)});
      return new Response(JSON.stringify({error: {message: 'offline retry fixture', type: 'rate_limit_error'}}), {
        status: 429, headers: {'content-type': 'application/json', 'retry-after': '0', 'x-should-retry': 'true'},
      });
    },
  })});
  await assert.rejects(ai.generate(request()));
  assert.equal(calls.length, 1); assert.match(calls[0].url, /\/responses$/);
  await assert.rejects(ai.countInputTokens(request()));
  assert.equal(calls.length, 2); assert.match(calls[1].url, /\/responses\/input_tokens$/);
  for (const call of calls) assert.equal(call.body.model, 'gpt-6.1-sol');
});

test('incomplete Sol output fails once without repair, escalation or another model', async () => {
  const calls = [];
  const ai = createEshaAi({environment, role, clientFactory: () => ({responses: {create: async body => {
    calls.push(body); return {status: 'incomplete', output_text: '{"answer":"unfinished","productIds":[]}'};
  }}})});
  await assert.rejects(ai.generate(request()), {code: 'invalid_ai_response'});
  assert.equal(calls.length, 1); assert.equal(calls[0].model, 'gpt-6.1-sol');
});

test('the shipping consultation route cannot activate the prepared role policy or accept a client-selected deep role', async () => {
  let storageCalls = 0, providerCalls = 0;
  const billing = createEshaBilling({environment, autoStart: false, provider: {ready: () => true},
    store: async () => { storageCalls++; throw Error('Must stop before membership reservation or provider debit'); },
    countInputTokens: async () => { providerCalls++; return 100; },
    generate: async () => { providerCalls++; },
  });
  for (const extra of [{}, {role: 'deep_thinking', model: 'gpt-6.1-sol', reasoningEffort: 'high'},
    {mode: 'deep_thinking', policy: ESHA_AI_ROLE_POLICY}]) {
    await assert.rejects(billing.consult({id: question.requestId}, {...question, ...extra}), {code: 'native_ai_not_configured'});
  }
  assert.equal(billing.catalog('apple').purchasesEnabled, false);
  assert.equal(storageCalls, 0); assert.equal(providerCalls, 0);
});
