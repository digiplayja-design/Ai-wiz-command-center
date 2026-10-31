import test from 'node:test';
import assert from 'node:assert/strict';
import {createBrainVoice} from '../brain_voice/core.mjs';
import {readAnswerStream, streamBrainTurn} from '../brain_voice/stream.mjs';

const model = 'gpt-6-astra-2026-10-01';
const complete = {model, status: 'completed', usage: {total_tokens: 50},
  output: [{type: 'message', content: [{type: 'output_text', text: 'Hello, José.'}]}]};
function provider() {
  let controller;
  const response = new Response(new ReadableStream({start(c) {controller = c;}}));
  return {response, send: event => {
    const bytes = new TextEncoder().encode(`data: ${JSON.stringify(event)}\r\n\r\n`);
    // Split UTF-8 and SSE boundaries to exercise actual network framing.
    for (const byte of bytes) controller.enqueue(Uint8Array.of(byte));
  }, end: () => controller.close()};
}
const tick = () => new Promise(resolve => setImmediate(resolve));
function voiceSetup(p, overrides = {}) {
  const meters = [], timings = [], calls = [];
  const voice = createBrainVoice({apiKey: () => 'fixture',
    loadRuntime: async () => ({instructions: 'Current memories'}),
    saveMemory: async () => ({id: 'saved'}),
    reportUsage: async value => {meters.push(value); return {allowed: true};},
    onTiming: value => timings.push(value),
    fetchImpl: async (_, options) => {calls.push(JSON.parse(options.body)); return p.response;}, ...overrides});
  voice.register({userId: 'u', sessionId: 's', limits: {maxSessionSeconds: 600, maxResponses: 10}});
  const turn = (onEvent, transcript = 'Hello') => voice.turn({userId: 'u', sessionId: 's', turnId: 't', transcript, onEvent});
  return {voice, turn, meters, timings, calls};
}
test('speech text arrives before completion, max reasoning retained, private reasoning excluded', async () => {
  const p = provider(), c = voiceSetup(p), events = [];
  let done = false;
  const result = c.turn(event => events.push(event)).then(value => {done = true; return value;});
  p.send({type: 'response.created', response: {model}});
  p.send({type: 'response.reasoning_text.delta', delta: 'private reasoning'});
  p.send({type: 'response.output_text.delta', delta: 'Hello, José.'});
  await tick();
  assert.equal(events[0].text, 'Hello, José.'); assert.equal(events.length, 1);
  assert.equal(done, false); assert.equal(c.calls[0].stream, true);
  assert.deepEqual(c.calls[0].reasoning, {effort: 'max'});
  p.send({type: 'response.completed', response: complete}); p.end();
  assert.equal((await result).answer, 'Hello, José.');
  assert.equal(c.meters.at(-1).body.totalTokens, 50);
  assert.ok(c.timings[0].firstTextMs <= c.timings[0].totalMs);
  assert.ok(!JSON.stringify(c.timings).includes('José'));
});
test('a concurrent retry shares one provider request and one usage charge', async () => {
  const p = provider(), c = voiceSetup(p);
  const a = c.turn(() => {}), b = c.turn(() => {});
  p.send({type: 'response.created', response: {model}});
  p.send({type: 'response.completed', response: complete}); p.end();
  assert.deepEqual(await a, await b); assert.equal(c.calls.length, 1);
  assert.equal(c.meters.at(-1).body.totalTokens, 50);
});
test('truncated stream does not become a successful answer', async () => {
  const p = provider(); p.send({type: 'response.created', response: {model}}); p.end();
  await assert.rejects(readAnswerStream(p.response, () => {}), /without completion/);
});
test('unverified model text is never released', async () => {
  const p = provider(), events = [];
  p.send({type: 'response.created', response: {model: 'gpt-6-luna'}});
  p.send({type: 'response.output_text.delta', delta: 'wrong'}); p.end();
  await assert.rejects(readAnswerStream(p.response, x => events.push(x)), /Unverified/);
  assert.deepEqual(events, []);
});
test('incomplete provider result is metered and rejected', async () => {
  const p = provider(), c = voiceSetup(p);
  const result = c.turn(() => {});
  p.send({type: 'response.incomplete', response: {...complete, status: 'incomplete'}}); p.end();
  await assert.rejects(result, {code: 'brain_incomplete_answer'});
  assert.equal(c.meters.at(-1).body.totalTokens, 50);
});
test('save path never streams a speculative acknowledgment or invokes inference', async () => {
  const p = provider(), events = [];
  let resolveSave;
  const c = voiceSetup(p, {saveMemory: () => new Promise(resolve => resolveSave = resolve)});
  const result = c.turn(e => events.push(e), 'Rici remember this: gold');
  await tick(); assert.deepEqual(events, []); assert.equal(c.calls.length, 0);
  resolveSave({id: 'persisted'});
  assert.equal((await result).saved, true);
});
test('runtime loading overlaps allowance check but provider waits for approval', async () => {
  const p = provider(); let allow, loaded = false;
  const c = voiceSetup(p, {reportUsage: () => new Promise(resolve => allow = resolve),
    loadRuntime: async () => {loaded = true; return {instructions: 'fresh'};}});
  const result = c.turn(() => {});
  await tick(); assert.equal(loaded, true); assert.equal(c.calls.length, 0);
  allow({allowed: false}); await assert.rejects(result, {code: 'brain_allowance'});
  assert.equal(c.calls.length, 0);
});
test('HTTP stream flushes deltas and sends exactly one terminal result', async () => {
  const writes = [], headers = {};
  const res = {setHeader: (k,v) => headers[k] = v, flushHeaders: () => {},
    write: x => writes.push(JSON.parse(x)), end: () => res.writableEnded = true};
  await streamBrainTurn({res, run: async emit => {emit({type: 'answer.delta', text: 'hello'}); return {ok: true, answer: 'hello'};}});
  assert.match(headers['Content-Type'], /ndjson/);
  assert.deepEqual(writes.map(x => x.type), ['answer.delta', 'turn.completed']);
  assert.equal(res.writableEnded, true);
});
test('HTTP stream fails explicitly after partial text; disconnected writes do not replay work', async () => {
  const writes = [];
  const res = {setHeader() {}, flushHeaders() {}, write: x => writes.push(JSON.parse(x)), end() {}};
  await streamBrainTurn({res, run: async emit => {emit({type: 'answer.delta', text: 'hello'}); throw Error('private detail');}});
  assert.equal(writes.at(-1).type, 'turn.error'); assert.ok(!JSON.stringify(writes).includes('private detail'));
  res.destroyed = true; let count = 0;
  await streamBrainTurn({res, run: async emit => {count++; emit({type:'answer.delta'}); return {};}});
  assert.equal(count, 1); assert.equal(writes.length, 2);
});
