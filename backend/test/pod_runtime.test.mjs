import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodRuntime} from '../pod/runtime.mjs';
import {PodError, podUsage} from '../pod/core.mjs';

const OWNER = '10000000-0000-4000-8000-000000000001';
const OTHER = '10000000-0000-4000-8000-000000000002';
const ID = '20000000-0000-4000-8000-000000000001';
const REQUEST = '30000000-0000-4000-8000-000000000001';
const SECOND = '30000000-0000-4000-8000-000000000002';
const THIRD = '30000000-0000-4000-8000-000000000003';
const NOW = Date.parse('2026-10-01T12:00:00.000Z');
const BRIEF = {text: 'A verified research brief.', checkedAt: new Date(NOW).toISOString(), sources: [{id: 'source-1', title: 'Source', url: 'https://www.nasa.gov/'}]};
const TURN = {speaker: 'host', text: 'Welcome. Let’s look at the evidence.', sourceIds: ['source-1']};
const AUDIO = Buffer.from('synthetic audio fixture');
const evidence = (kind, inputTokens, outputTokens) => ({kind, model: 'mock-provider', inputTokens, outputTokens,
  totalTokens: inputTokens == null || outputTokens == null ? null : inputTokens + outputTokens,
  usageKnown: inputTokens != null && outputTokens != null, status: 'completed'});

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
}
async function within(promise, milliseconds = 1000) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {timer = setTimeout(() => reject(new Error('Mock operation did not settle in time.')), milliseconds);})]);
  } finally {clearTimeout(timer);}
}

function fixture(options = {}) {
  const f = {
    time: NOW, events: [], receipts: [], finishes: [], failures: [], results: new Map(),
    episode: {id: ID, category: 'technology', topic: 'What does the evidence tell us?', style: 'balanced',
      durationSeconds: 300, hostCount: 2, state: 'ready', version: 0, turns: [], deadlineAt: null},
    brief: options.brief === undefined ? BRIEF : options.brief,
    hooks: options.hooks || {},
  };
  const note = (name, data) => {f.events.push({name, data});};
  const copy = value => structuredClone(value);
  f.store = {
    async claim(actor, id, input) {
      note('claim', {actor, id, ...input});
      if (f.hooks.claim) return f.hooks.claim(actor, id, input);
      const old = f.results.get(input.requestId);
      return old ? {dispatch: false, episode: copy(f.episode), result: copy(old)} :
        {dispatch: true, episode: copy(f.episode), brief: copy(f.brief)};
    },
    async authorizeDispatch(actor, id, requestId, callKey) {
      note('authorize:' + callKey, {actor, id, requestId});
      if (f.hooks.authorize) {
        const value = await f.hooks.authorize(callKey, {actor, id, requestId});
        if (value !== undefined) return value;
      }
      return {allowed: true};
    },
    async recordUsage(actor, id, requestId, receipt) {
      note('receipt:' + receipt.callKey, {actor, id, requestId});
      f.receipts.push(copy(receipt));
      if (f.hooks.receipt) {
        const value = await f.hooks.receipt(receipt);
        if (value !== undefined) return value;
      }
      return {recorded: true, allowed: true};
    },
    async finish(actor, id, requestId, result) {
      note('finish', {actor, id, requestId});
      f.finishes.push(copy(result));
      if (f.hooks.finish) return f.hooks.finish(result);
      let turn;
      if (result.turn) {
        turn = {...copy(result.turn), id: `turn-${f.episode.turns.length + 1}`, seq: f.episode.turns.length, createdAt: new Date(f.time).toISOString()};
        f.episode = {...f.episode, state: 'active', turns: [...f.episode.turns, turn]};
      }
      const value = {turn, ...(result.text !== undefined ? {text: result.text} : {})};
      f.results.set(requestId, value);
      return {committed: true, episode: copy(f.episode), ...value};
    },
    async get(actor, id) {
      note('get', {actor, id});
      if (f.hooks.get) return f.hooks.get(actor, id);
      return {episode: copy(f.episode)};
    },
    async fail(actor, id, requestId, result) {
      note('fail', {actor, id, requestId});
      f.failures.push(copy(result));
      if (f.hooks.fail) return f.hooks.fail(result);
      return {failed: true};
    },
  };
  const defaults = {
    research: {brief: BRIEF, usage: evidence('research', 20, 10)},
    turn: {...TURN, usage: evidence('turn', 80, 20)},
    speak: {wav: AUDIO, durationSeconds: 2, mime: 'audio/wav', usage: {...evidence('speech', null, null), inputCharacters: TURN.text.length, audioSeconds: 2}},
    transcribe: {text: 'What about the cost?', usage: {...evidence('transcription', 40, 10), inputAudioTokens: 35, audioSeconds: 3}},
  };
  f.providers = Object.fromEntries(Object.entries(defaults).map(([name, result]) => [name, async args => {
    note('provider:' + name, args);
    return f.hooks[name] ? f.hooks[name](args, result) : result;
  }]));
  f.accessCalls = 0;
  f.access = async user => {
    f.accessCalls++;
    note('access', {user});
    return f.hooks.access ? f.hooks.access(user, f.accessCalls) : {allowed: true};
  };
  f.runtime = createPodRuntime({store: f.store, providers: f.providers, access: f.access, now: () => f.time,
    logger: {warn: (...args) => note('warn', args)}, watchdogMs: 100000, ...options.runtimeOptions});
  f.run = (extra = {}) => f.runtime.run({user: {id: OWNER}, id: ID, requestId: REQUEST, version: 0, kind: 'next', ...extra});
  f.names = () => f.events.map(event => event.name);
  f.providerCalls = () => f.events.filter(event => event.name.startsWith('provider:'));
  return f;
}

test('construction and replay perform no paid calls, access checks, or new dispatch authorization', async t => {
  const f = fixture(); t.after(() => f.runtime.stop());
  assert.equal(f.providerCalls().length, 0);
  f.results.set(REQUEST, {turn: {...TURN, id: 'saved-turn'}});
  const replay = await f.run();
  assert.equal(replay.replayed, true);
  assert.equal(replay.audio, null);
  assert.equal(replay.audioUnavailable, true);
  assert.equal(replay.turn.id, 'saved-turn');
  assert.deepEqual(f.names(), ['claim']);
  assert.equal(f.runtime.activeCount, 0);
});

test('each research, turn and speech call requires its own entitlement check and durable authorization before dispatch', async t => {
  const f = fixture({brief: null}); t.after(() => f.runtime.stop());
  const result = await f.run();
  assert.deepEqual(f.names(), ['claim', 'access', 'authorize:research', 'provider:research', 'receipt:research',
    'access', 'authorize:turn', 'provider:turn', 'receipt:turn', 'access', 'authorize:speak', 'provider:speak', 'receipt:speak', 'finish']);
  assert.equal(f.accessCalls, 3);
  assert.equal(result.turn.text, TURN.text);
  assert.equal(result.audio.base64, AUDIO.toString('base64'));
  assert.equal(result.audio.durationSeconds, 2);
  assert.equal(f.finishes[0].brief.text, BRIEF.text);
  assert.equal(f.finishes[0].usage, undefined);
  for (const event of f.events.filter(event => event.name.startsWith('authorize:') || event.name.startsWith('receipt:'))) {
    assert.equal(event.data.actor, OWNER);
    assert.equal(event.data.id, ID);
    assert.equal(event.data.requestId, REQUEST);
  }
  assert.deepEqual(f.receipts.map(receipt => receipt.usage.totalTokens), [30, 100, 0]);
  assert.equal(f.receipts[2].evidence.usageKnown, false);
  assert.equal(f.receipts[2].evidence.totalTokens, null);
});

test('completed request replay reuses transient audio without a second provider call; missing cache never regenerates audio', async t => {
  const f = fixture(); t.after(() => f.runtime.stop());
  const first = await f.run();
  const count = f.providerCalls().length;
  const second = await f.run();
  assert.equal(second.replayed, true);
  assert.deepEqual(second.audio, first.audio);
  assert.equal(second.audioUnavailable, false);
  assert.equal(f.providerCalls().length, count);
  f.runtime.abort(OWNER, ID);
  const third = await f.run();
  assert.equal(third.audio, null);
  assert.equal(third.audioUnavailable, true);
  assert.equal(f.providerCalls().length, count);
});

test('replay after cache expiry or a runtime restart returns existing text and explicit audio unavailability', async t => {
  const f = fixture(); t.after(() => f.runtime.stop());
  await f.run();
  f.time += 120001;
  assert.equal((await f.run()).audioUnavailable, true);
  const restarted = createPodRuntime({store: f.store, providers: f.providers, access: f.access});
  t.after(() => restarted.stop());
  const result = await restarted.run({user: {id: OWNER}, id: ID, requestId: REQUEST, version: 0, kind: 'next'});
  assert.equal(result.turn.text, TURN.text);
  assert.equal(result.audio, null);
  assert.equal(result.audioUnavailable, true);
  assert.equal(f.providerCalls().length, 2);
});

test('revoked entitlement between steps prevents speech and preserves already-paid turn usage', async t => {
  const f = fixture({hooks: {access: async (_user, count) => ({allowed: count === 1, reason: 'Plan access ended.', status: 403})}});
  t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), error => error.code === 'pod_access_denied' && error.status === 403);
  assert.deepEqual(f.providerCalls().map(call => call.name), ['provider:turn']);
  assert.deepEqual(f.receipts.map(receipt => receipt.callKey), ['turn']);
  assert(!f.names().includes('authorize:speak'));
  assert.equal(f.finishes.length, 0);
  assert.equal(f.failures.length, 1);
});

test('durable dispatch denial blocks that provider call and all subsequent paid work', async t => {
  const f = fixture({brief: null, hooks: {authorize: async callKey => {
    if (callKey === 'turn') throw new PodError('The episode allowance ended.', 429, 'pod_budget');
  }}});
  t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), error => error.code === 'pod_budget');
  assert.deepEqual(f.providerCalls().map(call => call.name), ['provider:research']);
  assert.deepEqual(f.receipts.map(receipt => receipt.callKey), ['research']);
  assert.equal(f.finishes.length, 0);
});

test('accounting failure immediately stops later paid steps and prevents committing or caching output', async t => {
  const f = fixture({hooks: {receipt: async () => {throw new Error('ledger unavailable');}}});
  t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), /ledger unavailable/);
  assert.deepEqual(f.providerCalls().map(call => call.name), ['provider:turn']);
  assert.equal(f.receipts.length, 1);
  assert.equal(f.finishes.length, 0);
  assert.equal(f.failures.length, 1);
  assert.equal(f.runtime.activeCount, 0);
});

test('a false durable authorization or receipt allowance prevents later provider work', async t => {
  for (const stage of ['authorize', 'receipt']) {
    const f = fixture({hooks: {[stage]: async () => ({allowed: false})}});
    t.after(() => f.runtime.stop());
    await assert.rejects(f.run(), error => error.code === 'pod_interrupted');
    assert.equal(f.providerCalls().length, stage === 'authorize' ? 0 : 1);
    assert.equal(f.receipts.length, stage === 'authorize' ? 0 : 1);
    assert.equal(f.finishes.length, 0);
  }
});

test('successful research, turn and transcription with missing or invalid token totals record uncertainty and stop', async t => {
  const invalid = [undefined, null, -1, NaN, Infinity, 1.5, '50', Number.MAX_SAFE_INTEGER + 1];
  for (const method of ['research', 'turn', 'transcribe']) {
    for (const totalTokens of invalid) {
      const f = fixture({brief: method === 'research' ? null : BRIEF, hooks: {
        [method]: async (_args, result) => ({...result, usage: {...result.usage, totalTokens, usageKnown: true}}),
      }});
      t.after(() => f.runtime.stop());
      await assert.rejects(f.run({kind: method === 'transcribe' ? 'transcribe' : 'next', wav: Buffer.from('validated WAV fixture')}),
        error => error.code === 'pod_usage_unknown' && error.status === 503,
        `${method}: ${String(totalTokens)}`);
      assert.deepEqual(f.providerCalls().map(call => call.name), ['provider:' + method], 'no retry or later paid step');
      assert.equal(f.receipts.length, 1);
      assert.equal(f.receipts[0].callKey, method);
      assert.equal(f.receipts[0].evidence.status, 'uncertain');
      assert.equal(f.receipts[0].evidence.usageKnown, false);
      assert.equal(f.receipts[0].evidence.totalTokens, totalTokens, 'preserve the provider evidence without inventing a total');
      assert.equal(f.finishes.length, 0);
      assert.equal(f.failures.length, 1);
      assert(f.names().indexOf('receipt:' + method) < f.names().indexOf('fail'));
      assert.equal(f.runtime.activeCount, 0);
    }
    const f = fixture({brief: method === 'research' ? null : BRIEF, hooks: {
      [method]: async (_args, result) => {const {usage: _usage, ...withoutUsage} = result; return withoutUsage;},
    }});
    t.after(() => f.runtime.stop());
    await assert.rejects(f.run({kind: method === 'transcribe' ? 'transcribe' : 'next', wav: Buffer.from('validated WAV fixture')}),
      error => error.code === 'pod_usage_unknown');
    assert.deepEqual(f.receipts[0].evidence, {kind: method, status: 'uncertain', usageKnown: false});
    assert.equal(f.providerCalls().length, 1);
    assert.equal(f.finishes.length, 0);
  }
});

test('binary speech alone may finish with unknown token usage while retaining explicit unknown evidence', async t => {
  for (const usage of [undefined, {...evidence('speech', null, null), audioSeconds: 2, inputCharacters: TURN.text.length}]) {
    const f = fixture({hooks: {speak: async (_args, result) => ({...result, usage})}});
    t.after(() => f.runtime.stop());
    const result = await f.run();
    assert.equal(result.audio.base64, AUDIO.toString('base64'));
    assert.equal(f.receipts.length, 2);
    assert.equal(f.receipts[1].callKey, 'speak');
    assert.equal(f.receipts[1].evidence.status, 'completed');
    assert.equal(f.receipts[1].evidence.usageKnown, false);
    assert.equal(f.receipts[1].usage.totalTokens, 0);
    assert.equal(f.finishes.length, 1);
    assert.equal(f.failures.length, 0);
  }
});

test('transcription totals are recorded once in the transcription counter, separately from text and research totals', async t => {
  const f = fixture(); t.after(() => f.runtime.stop());
  const result = await f.run({kind: 'transcribe', wav: Buffer.from('validated WAV fixture')});
  assert.equal(result.text, 'What about the cost?');
  assert.deepEqual(f.names(), ['claim', 'access', 'authorize:transcribe', 'provider:transcribe', 'receipt:transcribe', 'finish']);
  assert.deepEqual(f.receipts[0].usage, {inputTokens: 0, outputTokens: 0, totalTokens: 0, transcriptionTokens: 50, inputAudioTokens: 35, outputAudioTokens: 0});
  assert.equal(f.receipts[0].evidence.totalTokens, 50);
  assert.equal(f.receipts[0].evidence.kind, 'transcription');
  assert.deepEqual(f.finishes[0], {text: 'What about the cost?'});
  assert.equal(result.audio, undefined);
  const replay = await f.run({kind: 'transcribe', wav: Buffer.from('validated WAV fixture')});
  assert.equal(replay.text, result.text);
  assert.equal(replay.replayed, true);
  assert.equal(f.providerCalls().length, 1);
});

test('usage normalization never invents unknown tokens or double-counts transcription', () => {
  assert.deepEqual(podUsage({inputTokens: null, outputTokens: null, totalTokens: null}, 'speak'),
    {inputTokens: 0, outputTokens: 0, totalTokens: 0, transcriptionTokens: 0, inputAudioTokens: 0, outputAudioTokens: 0});
  assert.deepEqual(podUsage({inputTokens: 10, outputTokens: 3, totalTokens: 13}, 'transcribe'),
    {inputTokens: 0, outputTokens: 0, totalTokens: 0, transcriptionTokens: 13, inputAudioTokens: 0, outputAudioTokens: 0});
  assert.deepEqual(podUsage({inputTokens: -1, outputTokens: Infinity, totalTokens: '100', inputAudioTokens: NaN}, 'turn'),
    {inputTokens: 0, outputTokens: 0, totalTokens: 0, transcriptionTokens: 0, inputAudioTokens: 0, outputAudioTokens: 0});
});

test('late successful provider usage after interrupt is receipted while its speech and transcript are discarded', async t => {
  const started = deferred(), release = deferred();
  let speechSignal;
  const f = fixture({hooks: {speak: async (args, result) => {speechSignal = args.signal; started.resolve(); await release.promise; return result;}}});
  t.after(() => f.runtime.stop());
  const operation = f.run();
  const rejected = assert.rejects(operation, error => error.code === 'pod_interrupted');
  await within(started.promise);
  f.runtime.abort(OWNER, ID);
  assert.equal(speechSignal.aborted, true);
  assert.equal(f.runtime.activeCount, 1, 'the lane stays occupied until late usage can be settled');
  release.resolve();
  await within(rejected);
  assert.deepEqual(f.receipts.map(receipt => receipt.callKey), ['turn', 'speak']);
  assert.equal(f.receipts[1].evidence.status, 'completed');
  assert.equal(f.receipts[1].evidence.audioSeconds, 2);
  assert.equal(f.finishes.length, 0);
  assert.equal(f.failures.length, 1);
  assert.equal(f.runtime.activeCount, 0);
  f.results.set(REQUEST, {turn: TURN});
  assert.equal((await f.run()).audioUnavailable, true);
});

test('late transcription after interrupt is charged to transcription only and never submitted', async t => {
  const started = deferred(), release = deferred();
  const f = fixture({hooks: {transcribe: async (_args, result) => {started.resolve(); await release.promise; return result;}}});
  t.after(() => f.runtime.stop());
  const operation = f.run({kind: 'transcribe', wav: Buffer.from('validated WAV fixture')});
  const rejected = assert.rejects(operation, error => error.code === 'pod_interrupted');
  await within(started.promise);
  f.runtime.abort(OWNER, ID);
  release.resolve();
  await within(rejected);
  assert.equal(f.receipts[0].usage.transcriptionTokens, 50);
  assert.equal(f.receipts[0].usage.totalTokens, 0);
  assert.equal(f.finishes.length, 0);
});

test('transcription interrupted during durable finish cannot return a stale transcript', async t => {
  const finishing = deferred(), release = deferred();
  const f = fixture({hooks: {finish: async result => {
    finishing.resolve(); await release.promise;
    return {committed: true, episode: f.episode, text: result.text};
  }}});
  t.after(() => f.runtime.stop());
  const operation = f.run({kind: 'transcribe', wav: Buffer.from('validated WAV fixture')});
  const rejected = assert.rejects(operation, error => error.code === 'pod_interrupted');
  await within(finishing.promise);
  f.runtime.abort(OWNER, ID);
  release.resolve();
  await within(rejected);
  assert.equal(f.receipts[0].usage.transcriptionTokens, 50);
  assert.equal(f.receipts[0].usage.totalTokens, 0);
});

test('cancellation after a durable dispatch marker but before provider invocation records uncertainty without paid work', async t => {
  const f = fixture(); t.after(() => f.runtime.stop());
  f.hooks.authorize = async () => {f.runtime.abort(OWNER, ID);};
  await assert.rejects(f.run(), error => error.code === 'pod_interrupted');
  assert.equal(f.providerCalls().length, 0);
  assert.equal(f.receipts.length, 1);
  assert.equal(f.receipts[0].evidence.status, 'uncertain');
  assert.equal(f.receipts[0].evidence.usageKnown, false);
  assert.equal(f.receipts[0].usage.totalTokens, 0);
  assert.equal(f.finishes.length, 0);
});

test('provider failures preserve real partial usage without automatic retries', async t => {
  const partial = {...evidence('turn', 30, 6), status: 'failed'};
  const f = fixture({hooks: {turn: async () => {throw Object.assign(new Error('upstream private diagnostics'), {usage: partial});}}});
  t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), /upstream private diagnostics/);
  assert.equal(f.providerCalls().length, 1);
  assert.deepEqual(f.receipts[0].evidence, partial);
  assert.equal(f.receipts[0].usage.totalTokens, 36);
  assert(!f.failures[0].error.includes('upstream private diagnostics'));
  assert.equal(f.finishes.length, 0);
});

test('transport errors without usage receive an explicit uncertain receipt and do not retry', async t => {
  const f = fixture({hooks: {turn: async () => {throw new Error('socket disconnected');}}});
  t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), /socket disconnected/);
  assert.equal(f.providerCalls().length, 1);
  assert.deepEqual(f.receipts[0].evidence, {kind: 'turn', status: 'uncertain', usageKnown: false});
  assert.equal(f.receipts[0].usage.totalTokens, 0);
});

test('an uncommitted durable finish cannot return or cache generated audio', async t => {
  const f = fixture({hooks: {finish: async () => ({committed: false})}}); t.after(() => f.runtime.stop());
  await assert.rejects(f.run(), error => error.code === 'pod_interrupted');
  assert.equal(f.receipts.length, 2);
  assert.equal(f.failures.length, 1);
  f.results.set(REQUEST, {turn: TURN});
  assert.equal((await f.run()).audioUnavailable, true);
});

test('a same-process episode lane is reserved before an asynchronous claim and rejects overlapping generation', async t => {
  const claimed = deferred(), release = deferred();
  const f = fixture({hooks: {claim: async () => {claimed.resolve(); await release.promise; return {dispatch: false, episode: f.episode, result: {}};}}});
  t.after(() => f.runtime.stop());
  const first = f.run();
  await within(claimed.promise);
  assert.equal(f.runtime.activeCount, 1);
  await assert.rejects(f.run({requestId: SECOND}), error => error.code === 'pod_request_active');
  assert.equal(f.names().filter(name => name === 'claim').length, 1);
  release.resolve();
  await first;
  assert.equal(f.runtime.activeCount, 0);
  assert.equal(f.providerCalls().length, 0);
});

test('global concurrency limit rejects a new lane before a store claim or paid provider call', async t => {
  const started = deferred(), release = deferred();
  const f = fixture({runtimeOptions: {maxConcurrent: 1}, hooks: {turn: async (_args, result) => {started.resolve(); await release.promise; return result;}}});
  t.after(() => f.runtime.stop());
  const first = f.run();
  await within(started.promise);
  await assert.rejects(f.run({user: {id: OTHER}, requestId: SECOND}), error => error.code === 'pod_busy');
  assert.equal(f.names().filter(name => name === 'claim').length, 1);
  release.resolve(); await first;
});

test('an abort for another owner cannot stop the active owner’s call or discard their audio', async t => {
  const started = deferred(), release = deferred();
  let signal;
  const f = fixture({hooks: {turn: async (args, result) => {signal = args.signal; started.resolve(); await release.promise; return result;}}});
  t.after(() => f.runtime.stop());
  const operation = f.run(); await within(started.promise);
  f.runtime.abort(OTHER, ID);
  assert.equal(signal.aborted, false);
  release.resolve();
  const result = await operation;
  f.runtime.abort(OTHER, ID);
  assert.deepEqual((await f.run()).audio, result.audio);
});

test('watchdog aborts output after an episode version changes and records late usage', async t => {
  const started = deferred(), aborted = deferred(), release = deferred();
  const f = fixture({runtimeOptions: {watchdogMs: 5}, hooks: {turn: async (args, result) => {
    args.signal.addEventListener('abort', () => aborted.resolve(), {once: true});
    started.resolve(); await release.promise; return result;
  }}});
  t.after(() => f.runtime.stop());
  const operation = f.run();
  const rejected = assert.rejects(operation, error => error.code === 'pod_interrupted');
  await within(started.promise);
  f.episode.version++;
  await within(aborted.promise);
  release.resolve(); await rejected;
  assert.equal(f.receipts[0].usage.totalTokens, 100);
  assert.equal(f.providerCalls().length, 1);
  assert.equal(f.finishes.length, 0);
});

test('watchdog deadline and operation timeout abort the provider without committing stale output', async t => {
  for (const mode of ['deadline', 'timeout']) {
    const started = deferred(), aborted = deferred(), release = deferred();
    const f = fixture({runtimeOptions: {watchdogMs: 5, operationTimeoutMs: mode === 'timeout' ? 15 : 1000}, hooks: {turn: async (args, result) => {
      args.signal.addEventListener('abort', () => aborted.resolve(), {once: true});
      started.resolve(); await release.promise; return result;
    }}});
    t.after(() => f.runtime.stop());
    const operation = f.run();
    const rejected = assert.rejects(operation, error => error.code === (mode === 'timeout' ? 'pod_timeout' : 'pod_interrupted'));
    await within(started.promise);
    if (mode === 'deadline') f.episode.deadlineAt = new Date(f.time - 1).toISOString();
    await within(aborted.promise);
    release.resolve(); await rejected;
    assert.equal(f.receipts[0].usage.totalTokens, 100);
    assert.equal(f.finishes.length, 0);
  }
});

test('closing is requested near the deadline or on the final bounded host turn and persisted as a recap', async t => {
  for (const mode of ['deadline', 'turns']) {
    const f = fixture(); t.after(() => f.runtime.stop());
    if (mode === 'deadline') f.episode.deadlineAt = new Date(f.time + 40000).toISOString();
    else f.episode.turns = Array.from({length: 35}, () => ({speaker: 'host', text: 'A thought.'}));
    await f.run();
    const call = f.events.find(event => event.name === 'provider:turn');
    assert.equal(call.data.closing, true);
    assert.equal(f.finishes[0].summary, TURN.text);
  }
});

test('shutdown aborts active work, retains its late receipt, rejects future runs and clears replay audio', async t => {
  const started = deferred(), release = deferred();
  const f = fixture({hooks: {turn: async (_args, result) => {started.resolve(); await release.promise; return result;}}});
  t.after(() => f.runtime.stop());
  const operation = f.run();
  const rejected = assert.rejects(operation, error => error.status === 503);
  await within(started.promise);
  f.runtime.stop();
  await assert.rejects(f.run({requestId: THIRD}), error => error.status === 503);
  release.resolve(); await rejected;
  assert.equal(f.receipts[0].usage.totalTokens, 100);
  assert.equal(f.finishes.length, 0);
  assert.equal(f.runtime.activeCount, 0);
});
