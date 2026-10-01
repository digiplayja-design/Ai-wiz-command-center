import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setImmediate as nextTurn} from 'node:timers/promises';
import {createLiveRuntime} from '../live_studio/runtime.mjs';
import {createYouTube} from '../live_studio/youtube.mjs';

const showFixture = () => ({
  id: randomUUID(), owner_id: randomUUID(), run_id: randomUUID(), worker_token: randomUUID(),
  state: 'preparing', mode: 'youtube', channel_id: 'UCexpected',
  config: {title: 'Source binding rehearsal', topic: 'Community technology', category: 'technology', durationSeconds: 80, hostCount: 2},
  command: {action: 'play', seq: 0},
});

test('speculative question research cannot change the sources of the segment currently on air', async () => {
  const show = showFixture();
  const briefA = {checkedAt: '2026-10-01T12:00:00Z', sources: [{id: 'A', title: 'Initial verified source', url: 'https://example.com/a'}]};
  const briefB = {checkedAt: '2026-10-01T12:01:00Z', sources: [{id: 'B', title: 'Audience question source', url: 'https://example.com/b'}]};
  const progress = [], renderings = [], generationOrder = [];
  let clock = Date.parse('2026-10-01T12:00:00Z'), chatPolls = 0, questionResearch = 0, finished;
  const store = {async call(owner, action, id, data = {}) {
    assert.equal(owner, show.owner_id); assert.equal(id, show.id);
    if (action === 'heartbeat') return {...show};
    if (action === 'events') return {events: []};
    if (action === 'progress') {progress.push(data.progress); return {...show};}
    if (action === 'finish') {finished = data; return {...show, state: data.error ? 'failed' : 'completed'};}
    assert.equal(action, 'event'); return {recorded: true};
  }};
  const providers = {
    async research(input) {
      if (input.contributions) {questionResearch++; generationOrder.push('question-research'); return {brief: briefB};}
      return {brief: briefA, initialTurn: {speaker: 'analyst', text: 'Opening evidence', sourceIds: ['A']}};
    },
    async moderate() {return true;},
    async turn({brief}) {
      const source = brief.sources[0].id;
      generationOrder.push('generate-' + source);
      return {speaker: 'host', text: 'Discussion using source ' + source, sourceIds: [source]};
    },
    async speak() {return {wav: Buffer.alloc(0), durationSeconds: 8};},
  };
  const youtube = {
    async setup() {return {id: 'broadcast', streamId: 'stream', ingest: 'test-only', watchUrl: 'https://www.youtube.com/watch?v=broadcast'};},
    async start() {return true;},
    async finish() {},
    async chat() {
      chatPolls++;
      return {items: chatPolls === 2 ? [{id: 'question', text: 'What new evidence changes this assessment?'}] : [], nextPageToken: String(chatPolls), pollingIntervalMillis: 5000};
    },
  };
  const runtime = createLiveRuntime({store, providers, youtube, mode: 'youtube', now: () => clock, logger: {warn() {}},
    sinkFactory: () => ({async write() {}, async close() {}, stop() {}}),
    async render({turn, sources, seconds}) {
      const entry = {text: turn.text, sources: structuredClone(sources), researchedBefore: questionResearch};
      renderings.push(entry);
      // Allow the prefetched next turn, including audience research, to finish
      // while the current segment is still being encoded and sent.
      await nextTurn();
      entry.researchedAfter = questionResearch;
      clock += seconds * 1000;
      return {file: 'mock-segment.ts', duration: seconds};
    },
  });
  await runtime.run(show);
  assert.equal(finished.error, null);
  assert.equal(questionResearch, 1);
  assert(generationOrder.includes('generate-B'));
  const overlap = renderings.find(r => r.text === 'Discussion using source A' && r.researchedAfter > r.researchedBefore);
  assert(overlap, 'The fixture must exercise research changing during an earlier spoken segment.');
  for (const item of [...renderings, ...progress.map(p => ({text: p.caption, sources: p.sources}))]) {
    const source = /Discussion using source ([AB])/.exec(item.text)?.[1];
    if (source) assert.equal(item.sources[0].id, source, 'Displayed evidence must match the spoken segment.');
  }
});

test('YouTube refuses a grant for another channel before creating any broadcast or stream', async () => {
  const requests = [];
  const youtube = createYouTube({channelId: 'UCexpected', accessToken: async () => 'fixture-token'}, {
    async fetcher(url, options) {
      requests.push({url, method: options.method});
      return new Response(JSON.stringify({items: [{id: 'UCdifferent'}]}), {status: 200, headers: {'content-type': 'application/json'}});
    },
  });
  await assert.rejects(youtube.setup(showFixture()), error => error.status === 409 && /channel changed/.test(error.message));
  assert.equal(requests.length, 1);
  assert.equal(requests[0].method, 'GET');
  assert.equal(new URL(requests[0].url).pathname, '/youtube/v3/channels');
});
