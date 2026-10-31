import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createBrainVoice, rememberCommand, brainSpeechConfig} from '../brain_voice/core.mjs';

const sessionId = 'voice-session', userId = 'signed-in-user';
function setup(overrides = {}) {
  const requests = [], saves = [], meters = [];
  let clock = 10000;
  const voice = createBrainVoice({now: () => clock, apiKey: () => 'test-only',
    loadRuntime: async () => ({instructions: `Current account memories: ${saves.map(s => s.body.content).join(';')}`}),
    saveMemory: async value => {saves.push(value); return {id: 'memory-1', ...value.body};},
    reportUsage: async value => {meters.push(value); return {allowed: true};},
    fetchImpl: async (url, options) => {requests.push({url, ...JSON.parse(options.body)}); return Response.json({model: 'gpt-6-astra-2026-10-01', status: 'completed',
      usage: {total_tokens: 200, input_tokens: 150, output_tokens: 50},
      output: [{type: 'message', content: [{type: 'output_text', text: 'Here is the answer.'}]}]});}, ...overrides});
  voice.register({userId, sessionId, limits: {maxSessionSeconds: 600, maxResponses: 8}});
  const turn = (transcript, turnId = 'item_1', who = userId) => voice.turn({userId: who, sessionId, turnId, transcript});
  return {voice, turn, requests, saves, meters, advance: ms => clock += ms};
}

test('Astra Max is pinned, no sampling or provider fallback; microphone answers disabled', async () => {
  const c = setup(); await c.turn('Explain the tradeoffs.');
  assert.equal(c.requests.length, 1); assert.equal(c.requests[0].model, 'gpt-6-astra');
  assert.deepEqual(c.requests[0].reasoning, {effort: 'max'}); assert.equal(c.requests[0].store, false);
  assert.equal(c.requests[0].temperature, undefined); assert.equal(c.saves.length, 0);
  const config = brainSpeechConfig({audio: {input: {transcription: {model:'asr'}, turn_detection: {type:'semantic_vad'}}, output: {voice:'marin'}}});
  assert.equal(config.audio.input.turn_detection.create_response, false);
  assert.equal(config.audio.input.turn_detection.interrupt_response, true);
  assert.equal(config.tool_choice, 'none'); assert.deepEqual(config.tools, []);
});
test('explicit memory and instruction save exact content, without another password or model call', async () => {
  const c = setup(); const a = await c.turn('Rici, remember this: My dog is called Joy.');
  assert.equal(a.saved, true); assert.equal(c.saves[0].body.content, 'My dog is called Joy.');
  assert.equal(c.saves[0].userId, userId); assert.equal(c.saves[0].body.confirmed, true);
  assert.equal(c.saves[0].body.password, undefined); assert.equal(c.requests.length, 0);
  const b = await c.turn('Rici remember this instruction: Always use metric units.', 'item_2');
  assert.equal(b.kind, 'instruction'); assert.equal(c.saves[1].body.content, 'Always use metric units.');
  await c.turn('What units should you use?', 'item_3');
  assert.match(c.requests[0].instructions, /Always use metric units/);
});
test('quoted, negated, hypothetical and ordinary statements never authorize saves', async () => {
  for (const text of ['Do not remember this.', 'What does Rici remember this mean?', 'If I say Rici remember this, will you save?', '“Rici remember this: x”', 'Rici, do not remember this: x', 'My favourite colour is purple.']) {
    const c = setup(); await c.turn(text); assert.equal(c.saves.length, 0, text);
  }
  assert.equal(rememberCommand('Rici remember this: use gold').content, 'use gold');
});
test('bare command captures only the next utterance and permits cancel; authorization expires', async () => {
  const c = setup(); assert.equal((await c.turn('Rici remember this')).awaitingMemory, true);
  await c.turn('I prefer short answers.', 'item_2'); assert.equal(c.saves[0].body.content, 'I prefer short answers.');
  await c.turn('Rici remember this', 'item_3'); await c.turn('Never mind.', 'item_4'); assert.equal(c.saves.length, 1);
  await c.turn('Rici remember this', 'item_5'); c.advance(61000);
  await c.turn('Ordinary conversation', 'item_6'); assert.equal(c.saves.length, 1);
});
test('duplicate ASR/retry events share one acknowledged write; reused id cannot replace content', async () => {
  const c = setup(); const results = await Promise.all([c.turn('Rici remember this: x'), c.turn('Rici remember this: x')]);
  assert.equal(c.saves.length, 1); assert.deepEqual(results[0], results[1]);
  await assert.rejects(c.turn('Rici remember this: different'), {code:'brain_turn_conflict'});
});
test('save failure or missing persistence acknowledgment never returns saved', async () => {
  for (const saveMemory of [async () => {throw Error('db failed');}, async () => ({})]) {
    const c = setup({saveMemory}); await assert.rejects(c.turn('Rici remember this: x'));
  }
});
test('account/session ownership, lifetime and allowance enforced before inference or writes', async () => {
  const c = setup(); await assert.rejects(c.turn('Rici remember this: x', 'a', 'another-user'), {code: 'brain_session_ended'});
  c.advance(600001); await assert.rejects(c.turn('Hello'), {code:'brain_session_ended'});
  const limited = setup({reportUsage: async () => ({allowed:false})});
  await assert.rejects(limited.turn('Rici remember this: x'), {code:'brain_allowance'}); assert.equal(limited.saves.length, 0);
  assert.equal(c.requests.length, 0);
});
test('server counts reasoning tokens even when client reports zero; usage is not counted twice', async () => {
  const c = setup(); await c.turn('Hello');
  assert.equal(c.meters.at(-1).body.totalTokens, 200);
  assert.equal(c.voice.mergeUsage(userId, {sessionId, totalTokens: 20}).totalTokens, 220);
  assert.equal(c.voice.mergeUsage(userId, {sessionId, totalTokens: 0}).totalTokens, 220);
  c.voice.mergeUsage(userId, {sessionId, ended: true});
  await assert.rejects(c.turn('Hello again', 'item_2'), {code:'brain_session_ended'});
});
test('provider errors or a different returned model do not silently downgrade', async () => {
  let calls = 0;
  const c = setup({fetchImpl: async () => {calls++; return new Response('', {status: 403});}});
  await assert.rejects(c.turn('Hello'), {code:'brain_astra_unavailable'}); assert.equal(calls, 1);
  const wrong = setup({fetchImpl: async () => Response.json({model:'gpt-6-luna',status:'completed',output:[]})});
  await assert.rejects(wrong.turn('Hello'), {code:'brain_incomplete_answer'});
});
test('production routes authenticate first and register only scoped successful voice calls', async () => {
  const source = await readFile(new URL('../server.js', import.meta.url), 'utf8');
  assert.match(source, /app\.post\('\/api\/brain-voice\/turn', korlixLiveConvoAgentRouteV1/);
  assert.match(source, /brainVoice\.turn\(\{userId: user\.id, sessionId, turnId, transcript\}\)/);
  assert.match(source, /if \(isBrainVoice\(req\)\) \{\s*brainVoice\.register\(req\.korlixLiveConvoBuild129\)/);
});
