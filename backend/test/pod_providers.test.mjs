import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodProviders, PodProviderError, POD_VOICES, safePodSourceUrl, validatePodWav} from '../pod/providers.mjs';

const now = () => new Date('2026-10-01T12:00:00.000Z');
const sourceUrl = 'https://www.nasa.gov/missions/';
const brief = {text: 'NASA describes its mission program. The discussion can explore priorities.', sources: [{id: 'source-1', title: 'NASA missions', url: sourceUrl}], checkedAt: now().toISOString()};
const episode = {category: 'technology', topic: 'What should space missions prioritize?', style: 'balanced', hostCount: 2, turns: []};
const usage = {input_tokens: 101, output_tokens: 38, total_tokens: 139, output_tokens_details: {reasoning_tokens: 20}};
const researchResult = () => ({status: 'completed', id: 'resp_research', _request_id: 'req_research', usage,
  output: [{type: 'web_search_call', status: 'completed', action: {type: 'search', sources: [{url: sourceUrl, title: 'NASA missions'}]}}],
  output_text: JSON.stringify({text: brief.text, currentSourcesAvailable: true, sources: [{url: sourceUrl}]})});
const turnResult = (text = 'Welcome! I’m K-Nova, here with our AI Analyst. What should these missions help us understand?', sourceIds = ['source-1']) =>
  ({status: 'completed', usage, output_text: JSON.stringify({text, sourceIds})});
const turnArgs = (overrides = {}) => ({episode, brief, remainingSeconds: 300, ...overrides});

function wav(seconds = 1) {
  const pcm = Buffer.alloc(Math.round(seconds * 48000));
  const buffer = Buffer.alloc(44 + pcm.length);
  buffer.write('RIFF'); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVE', 8);
  buffer.write('fmt ', 12); buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(24000, 24); buffer.writeUInt32LE(48000, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(pcm.length, 40); pcm.copy(buffer, 44);
  return buffer;
}
function mock({response = researchResult(), speechResponse, transcriptionResponse} = {}) {
  const calls = [];
  const client = {
    responses: {create: async (payload, options) => {calls.push({kind: 'responses', payload, options}); return typeof response === 'function' ? response(payload, options) : response;}},
    audio: {
      speech: {create: async (payload, options) => {calls.push({kind: 'speech', payload, options}); return typeof speechResponse === 'function' ? speechResponse(payload, options) : speechResponse;}},
      transcriptions: {create: async (payload, options) => {calls.push({kind: 'transcription', payload, options}); return transcriptionResponse;}},
    },
  };
  return {calls, client, providers: createPodProviders({client, now})};
}

test('research uses configured Astra xhigh, private bounded web search, actual source metadata and exact usage', async () => {
  const fixture = mock();
  assert.equal(fixture.calls.length, 0);
  const result = await fixture.providers.research(episode);
  assert.deepEqual(result.brief, brief);
  assert.equal(result.usage.totalTokens, 139);
  assert.equal(result.usage.reasoningTokens, 20);
  assert.equal(result.usage.searchCalls, 1);
  assert.equal(result.usage.providerRequestId, 'req_research');
  assert.equal(result.usage.providerResponseId, 'resp_research');
  assert.equal(result.usage.usageKnown, true);
  assert.equal(result.usage.status, 'completed');
  assert.equal(fixture.calls.length, 1);
  const {payload, options} = fixture.calls[0];
  assert.equal(payload.model, 'gpt-6-astra');
  assert.deepEqual(payload.reasoning, {effort: 'xhigh'});
  assert.equal(payload.store, false);
  assert.equal(payload.max_output_tokens, 10000);
  assert.equal(payload.max_tool_calls, 3);
  assert.deepEqual(payload.tools, [{type: 'web_search', search_context_size: 'medium'}]);
  assert.equal(payload.tool_choice, 'required');
  assert.deepEqual(payload.include, ['web_search_call.action.sources']);
  assert.equal(payload.text.format.strict, true);
  assert.match(payload.instructions, /untrusted data/);
  assert.equal(options.maxRetries, 0);
  assert.equal(options.timeout, 90000);
  assert(options.signal instanceof AbortSignal);
});

test('research rejects model-invented URLs, unsafe URLs, missing search evidence and unavailable current sources while retaining paid usage', async () => {
  const cases = [
    result => {result.output_text = JSON.stringify({text: brief.text, currentSourcesAvailable: true, sources: [{url: 'https://www.nasa.gov/invented-page'}]});},
    result => {result.output = [];},
    result => {result.output[0].status = 'in_progress';},
    result => {result.output[0].action.sources[0].url = 'http://127.0.0.1/admin'; result.output_text = JSON.stringify({text: brief.text, currentSourcesAvailable: true, sources: [{url: 'http://127.0.0.1/admin'}]});},
    result => {result.output_text = JSON.stringify({text: brief.text, currentSourcesAvailable: false, sources: [{url: sourceUrl}]});},
  ];
  for (const change of cases) {
    const response = researchResult(); change(response);
    const fixture = mock({response});
    await assert.rejects(fixture.providers.research({...episode, category: 'politics'}), error => {
      assert(error instanceof PodProviderError);
      assert.equal(error.code, 'POD_SOURCES_UNAVAILABLE');
      assert.equal(error.usage.kind, 'research');
      assert.equal(error.usage.totalTokens, 139);
      assert.equal(error.usage.status, 'failed');
      return true;
    });
    assert.equal(fixture.calls.length, 1);
  }
});

test('only public HTTPS source URLs are accepted and fragments are normalized', () => {
  for (const url of ['http://example.org', 'https://localhost/a', 'https://internal/a', 'https://127.0.0.1/a', 'https://[::1]/',
    'https://0x7f000001/', 'https://2130706433/', 'https://user:pass@example.org/', 'https://example.org:8443/',
    'https://service.internal/a', 'https://example.org./', 'https://thing.local', 'javascript:alert(1)', 'https://bad_host.org/']) {
    assert.equal(safePodSourceUrl(url), null, url);
  }
  assert.equal(safePodSourceUrl(sourceUrl + '#part'), sourceUrl);
});

test('turn alternates two or three distinct AI roles and selects host for closing', async () => {
  const fixture = mock({response: turnResult('That raises a useful tradeoff.', [])});
  assert.equal((await fixture.providers.turn(turnArgs())).speaker, 'host');
  const host = {speaker: 'host', text: 'Welcome!'};
  assert.equal((await fixture.providers.turn(turnArgs({episode: {...episode, turns: [host, {speaker: 'user', text: 'What about costs?'}]}}))).speaker, 'analyst');
  assert.equal((await fixture.providers.turn(turnArgs({episode: {...episode, hostCount: 3, turns: [host, {speaker: 'analyst', text: 'Consider scope.'}]}}))).speaker, 'challenger');
  assert.equal((await fixture.providers.turn(turnArgs({episode: {...episode, turns: [host]}, remainingSeconds: 40}))).speaker, 'host');
  const {payload, options} = fixture.calls.at(-1);
  assert.equal(payload.model, 'gpt-6-astra');
  assert.equal(payload.reasoning.effort, 'xhigh');
  assert.equal(payload.max_output_tokens, 8192);
  assert.equal(payload.tools, undefined);
  assert.equal(payload.store, false);
  assert.equal(options.maxRetries, 0);
  assert.equal(JSON.parse(payload.input).closing, true);
  assert.match(payload.instructions, /no persuasion targeted to the listener/);
  assert.match(payload.instructions, /no voting instructions/);
  assert.match(payload.instructions, /never promote it into a verified fact/);
  assert.match(payload.instructions, /10–30 seconds/);
});

test('turn rejects fabricated citations, markup and overlong or incomplete output without retries, keeping usage', async () => {
  for (const response of [turnResult('That is a claim.', ['source-99']), turnResult('x'.repeat(481)), turnResult('**A claim**'),
    turnResult('[Claim](https://example.org/)'), {...turnResult(), status: 'incomplete'}]) {
    const fixture = mock({response});
    await assert.rejects(fixture.providers.turn(turnArgs()), error => {
      assert.equal(error.usage.kind, 'turn');
      assert.equal(error.usage.totalTokens, 139);
      assert.equal(error.usage.status, 'failed');
      return true;
    });
    assert.equal(fixture.calls.length, 1);
  }
});

test('turn budgets and unverified briefs stop before any paid dispatch', async () => {
  const fixture = mock({response: turnResult()});
  for (const args of [turnArgs({remainingSeconds: 0}), turnArgs({brief: {...brief, sources: []}}),
    turnArgs({episode: {...episode, turns: Array.from({length: 36}, () => ({speaker: 'host', text: 'One thought.'}))}})]) {
    await assert.rejects(fixture.providers.turn(args), error => !error.usage);
  }
  assert.equal(fixture.calls.length, 0);
});

test('speech uses a fixed distinct voice per role, converts 24kHz PCM into valid WAV, and keeps unknown tokens null', async () => {
  const pcm = Buffer.alloc(48000, 1);
  const fixture = mock({speechResponse: () => new Response(pcm, {headers: {'content-type': 'audio/pcm', 'x-request-id': 'req_speech'}})});
  assert.equal(new Set(Object.values(POD_VOICES)).size, 3);
  for (const speaker of ['host', 'analyst', 'challenger']) {
    const result = await fixture.providers.speak({speaker, text: 'Here is one thought.'});
    assert.equal(result.mime, 'audio/wav');
    assert.equal(result.durationSeconds, 1);
    assert.equal(validatePodWav(result.wav).durationSeconds, 1);
    assert.deepEqual(validatePodWav(result.wav).pcm, pcm);
    assert.equal(result.usage.inputTokens, null);
    assert.equal(result.usage.outputTokens, null);
    assert.equal(result.usage.totalTokens, null);
    assert.equal(result.usage.usageKnown, false);
    assert.equal(result.usage.audioSeconds, 1);
    assert.equal(result.usage.inputCharacters, 20);
    assert.equal(result.usage.providerRequestId, 'req_speech');
    const {payload, options} = fixture.calls.at(-1);
    assert.equal(payload.voice, POD_VOICES[speaker]);
    assert.equal(payload.model, 'gpt-4o-mini-tts');
    assert.equal(payload.response_format, 'pcm');
    assert.equal(payload.stream_format, 'audio');
    assert.equal(options.maxRetries, 0);
  }
});

test('speech cancels an oversized stream before buffering it and never makes a retry', async () => {
  let cancelled = false;
  const stream = new ReadableStream({start(controller) {controller.enqueue(new Uint8Array(1920002));}, cancel() {cancelled = true;}});
  const fixture = mock({speechResponse: new Response(stream)});
  await assert.rejects(fixture.providers.speak({speaker: 'host', text: 'A thought.'}), error => {
    assert.equal(error.code, 'POD_AUDIO_LIMIT');
    assert.equal(error.usage.kind, 'speech');
    assert.equal(error.usage.usageKnown, false);
    return true;
  });
  assert.equal(cancelled, true);
  assert.equal(fixture.calls.length, 1);
});

test('speech rejects empty, odd-length, text and over-declared audio responses', async () => {
  for (const response of [new Response(new Uint8Array()), new Response(new Uint8Array(3)),
    new Response('upstream error', {headers: {'content-type': 'application/json'}}),
    new Response(new Uint8Array(2), {headers: {'content-length': '1920002'}})]) {
    const fixture = mock({speechResponse: response});
    await assert.rejects(fixture.providers.speak({speaker: 'host', text: 'A thought.'}), error => error.usage.kind === 'speech');
    assert.equal(fixture.calls.length, 1);
  }
});

test('speech cancels invalid content types, malformed and empty stream chunks', async () => {
  for (const variant of ['type', 'chunk', 'empty', 'status']) {
    let cancelled = false;
    const body = new ReadableStream({start(controller) {controller.enqueue(variant === 'chunk' ? 'bad chunk' : new Uint8Array(variant === 'empty' ? 0 : 2));}, cancel() {cancelled = true;}});
    const response = {body, ok: variant !== 'status', headers: new Headers({'content-type': variant === 'type' ? 'text/plain' : 'audio/pcm'})};
    const fixture = mock({speechResponse: response});
    await assert.rejects(fixture.providers.speak({speaker: 'host', text: 'A thought.'}));
    assert.equal(cancelled, true, variant);
  }
});

test('speech input bounds and invalid roles reject before dispatch', async () => {
  const fixture = mock();
  for (const args of [{speaker: 'user', text: 'Hello'}, {speaker: 'host', text: 'x'.repeat(481)}, {speaker: 'host', text: ''}]) {
    await assert.rejects(fixture.providers.speak(args), error => error.status === 400 && !error.usage);
  }
  assert.equal(fixture.calls.length, 0);
});

test('strict WAV validation rejects high-bit magic tags rather than accepting ASCII aliases', () => {
  for (const offset of [0, 8, 12, 36]) {
    const input = wav(); input[offset] |= 0x80;
    assert.throws(() => validatePodWav(input), error => error.code === 'POD_INVALID_AUDIO');
  }
});

test('transcription uploads only validated bounded WAV and reports actual tokens once without fabrication', async () => {
  const fixture = mock({transcriptionResponse: {text: 'What about the cost?', usage: {type: 'tokens', input_tokens: 50, input_token_details: {text_tokens: 10, audio_tokens: 40}, output_tokens: 6, total_tokens: 56}}});
  const audio = wav(30);
  const result = await fixture.providers.transcribe({wav: audio});
  assert.equal(result.text, 'What about the cost?');
  assert.equal(result.usage.kind, 'transcription');
  assert.equal(result.usage.totalTokens, 56);
  assert.equal(result.usage.inputAudioTokens, 40);
  assert.equal(result.usage.inputTextTokens, 10);
  assert.equal(result.usage.audioSeconds, 30);
  assert.equal(result.usage.usageKnown, true);
  const {payload, options} = fixture.calls[0];
  assert.equal(payload.model, 'gpt-4o-transcribe');
  assert.equal(payload.response_format, 'json');
  assert.equal(payload.file.name, 'listener.wav');
  assert.equal(payload.file.type, 'audio/wav');
  assert.equal(payload.file.size, 1440044);
  assert.deepEqual(Buffer.from(await payload.file.arrayBuffer()), audio);
  assert.equal(options.maxRetries, 0);
});

test('missing transcription usage stays explicitly unknown and silence is accepted', async () => {
  const fixture = mock({transcriptionResponse: {text: ''}});
  const result = await fixture.providers.transcribe({wav: wav()});
  assert.equal(result.text, '');
  assert.equal(result.usage.usageKnown, false);
  assert.equal(result.usage.totalTokens, null);
  assert.equal(result.usage.audioSeconds, 1);
});

test('invalid, stereo, wrong-rate, truncated, overlong, trailing and odd WAV input never dispatches', async () => {
  const fixture = mock();
  const stereo = wav(); stereo.writeUInt16LE(2, 22);
  const wrongRate = wav(); wrongRate.writeUInt32LE(48000, 24);
  const byteRate = wav(); byteRate.writeUInt32LE(1, 28);
  const wrongSize = wav(); wrongSize.writeUInt32LE(1, 40);
  const float = wav(); float.writeUInt16LE(3, 20);
  const odd = wav(); odd.writeUInt32LE(odd.length - 9, 4); odd.writeUInt32LE(odd.length - 45, 40);
  for (const audio of [Buffer.alloc(12), stereo, wrongRate, byteRate, float, wrongSize, wav().subarray(0, 50),
    wav(30.001), Buffer.concat([wav(), Buffer.from([0, 0])]), odd.subarray(0, -1), 'not bytes']) {
    await assert.rejects(fixture.providers.transcribe({wav: audio}), error => error.code === 'POD_INVALID_AUDIO' && !error.usage);
  }
  assert.equal(fixture.calls.length, 0);
});

test('incomplete and malformed transcription responses retain actual provider usage', async () => {
  const fixture = mock({transcriptionResponse: {text: 'x'.repeat(1001), usage}});
  await assert.rejects(fixture.providers.transcribe({wav: wav()}), error => error.usage.totalTokens === 139 && error.usage.kind === 'transcription');
  assert.equal(fixture.calls.length, 1);
});

test('pre-aborted calls do not dispatch; cancellation after dispatch aborts once and records uncertain usage', async () => {
  const stopped = new AbortController(); stopped.abort();
  const first = mock();
  await assert.rejects(first.providers.research({...episode, signal: stopped.signal}), error => error.code === 'POD_ABORTED' && !error.usage);
  assert.equal(first.calls.length, 0);

  const controller = new AbortController();
  let dispatchedSignal;
  const fixture = mock({response: (_payload, options) => {dispatchedSignal = options.signal; return new Promise(() => {});}});
  const pending = fixture.providers.research({...episode, signal: controller.signal});
  controller.abort();
  await assert.rejects(pending, error => error.code === 'POD_ABORTED' && error.usage.status === 'uncertain' && error.usage.totalTokens === null);
  assert.equal(dispatchedSignal.aborted, true);
  assert.equal(fixture.calls.length, 1);
});

test('timeouts are bounded even with a nonresponsive injected client and do not retry', async () => {
  let calls = 0, signal;
  const providers = createPodProviders({client: {responses: {create: async (_p, options) => {calls++; signal = options.signal; return new Promise(() => {});}}}, timeouts: {turn: 10}});
  await assert.rejects(providers.turn(turnArgs()), error => error.code === 'POD_PROVIDER_TIMEOUT' && error.usage.status === 'uncertain');
  assert.equal(signal.aborted, true);
  assert.equal(calls, 1);
});

test('provider failures retain reported partial usage and never expose upstream error text', async () => {
  const fixture = mock({response: () => {throw Object.assign(new Error('sensitive upstream response'), {status: 502, request_id: 'req_failed', usage});}});
  await assert.rejects(fixture.providers.research(episode), error => {
    assert.equal(error.usage.totalTokens, 139);
    assert.equal(error.usage.providerRequestId, 'req_failed');
    assert.equal(error.usage.status, 'failed');
    assert(!error.message.includes('sensitive'));
    return true;
  });
  assert.equal(fixture.calls.length, 1);
});
