import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {createEshaLiveTransport, liveSessionRequest, voiceCommentary} from '../esha/billing/voice_transport.mjs';

const actor = '11111111-1111-4111-8111-111111111111';
const environment = {OPENAI_API_KEY: 'offline-fixture-not-a-key'};
const offer = 'v=0\r\na=sendrecv\r\n';
const request = () => liveSessionRequest({actor, sdpOffer: offer, deepThinkingConsent: false});

test('Live request fixes model, retention, delegation and untrusted frontend capabilities', () => {
  const value = request();
  assert.equal(value.session.model, 'gpt-live-1');
  assert.equal(value.session.store, false);
  assert.deepEqual(value.session.delegation, {type: 'client'});
  assert.deepEqual(value.transport, {type: 'webrtc', sdp: offer});
  assert.deepEqual(value.session.client.data_channel.allowed_client_events, ['session.close']);
  assert(!JSON.stringify(value).includes(environment.OPENAI_API_KEY));
  assert(!JSON.stringify(value).includes(actor));
  assert(!value.session.client.data_channel.allowed_server_events.some(item => item.type === 'session.delegation.created'));
  assert.match(value.session.instructions, /has not allowed deep-thinking/);
  assert.match(liveSessionRequest({actor, sdpOffer: offer, deepThinkingConsent: true}).session.instructions, /allowed deep thinking/);
});

test('WebRTC creation makes exactly one authenticated fixed-host request and returns no credential', async () => {
  const calls = [];
  const transport = createEshaLiveTransport({environment, fetchImpl: async (url, init) => {
    calls.push({url, init});
    return new Response(JSON.stringify({session: {id: 'live_fixture_1'}, transport: {type: 'webrtc', sdp: offer}}), {status: 201});
  }});
  assert.deepEqual(await transport.create(request()), {sessionId: 'live_fixture_1', sdpAnswer: offer});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.openai.com/v1/live/sessions');
  assert.equal(calls[0].init.redirect, 'error');
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${environment.OPENAI_API_KEY}`);
  assert.deepEqual(JSON.parse(calls[0].init.body), request());
});

test('ambiguous HTTP failures and malformed responses never retry or expose the provider body', async () => {
  for (const response of [new Response('sensitive-request-body', {status: 401}),
    new Response('{"session":{"id":"https://wrong-host"}}', {status: 201}),
    new Response('not-json', {status: 201}), null]) {
    let attempts = 0;
    const transport = createEshaLiveTransport({environment, fetchImpl: async () => {
      attempts++; if (!response) throw new Error('network timeout containing a secret'); return response;
    }});
    await assert.rejects(transport.create(request()), error => {
      assert.equal(error.code, 'voice_create_unconfirmed');
      assert(!/sensitive|secret|401/.test(error.message)); return true;
    });
    assert.equal(attempts, 1);
  }
});

class Socket extends EventEmitter {
  readyState = 0;
  sent = [];
  close() {this.readyState = 3; this.emit('close');}
  terminate() {this.close();}
  send(value) {this.sent.push(JSON.parse(value));}
}
test('sideband authenticates only on the server and waits for final provider evidence', async () => {
  let socket, captured, lost = 0;
  const events = [];
  const transport = createEshaLiveTransport({environment, socketFactory: async (url, options) => {
    captured = {url, options}; socket = new Socket();
    setImmediate(() => {socket.readyState = 1; socket.emit('open');}); return socket;
  }});
  const channel = await transport.attach('live_fixture_1', {onEvent: event => events.push(event), onDisconnect: () => lost++});
  assert.equal(captured.url, 'wss://api.openai.com/v1/live/sessions/live_fixture_1/attach');
  assert.equal(captured.options.headers.Authorization, `Bearer ${environment.OPENAI_API_KEY}`);
  assert.equal(captured.options.followRedirects, false);
  assert.equal(socket.sent.length, 0, 'An attachment must never send session.start.');
  channel.closeSession('stop_1');
  assert.deepEqual(socket.sent, [{type: 'session.close', event_id: 'stop_1'}]);
  assert.equal(socket.readyState, 1, 'Keep receiving after requesting closure.');
  socket.emit('message', Buffer.from('{"type":"session.output_audio.delta","delta":"private-audio"}'), false);
  socket.emit('message', Buffer.from('{"type":"session.usage.updated","usage":{"seconds":5.8}}'), false);
  assert.equal(events.length, 1);
  assert.equal(events[0].usage.seconds, 5.8);
  channel.commentary('delegation_1', 'A checked recommendation.', 'commentary_1');
  assert.equal(socket.sent[1].type, 'session.commentary.append');
  assert.equal(socket.sent[1].delegation_id, 'delegation_1');
  channel.dispose();
  assert.equal(lost, 0, 'Intentional disposal after finalization is not a new disconnect.');
});

test('sideband connection failure cannot create another paid session', async () => {
  let attempts = 0, creates = 0;
  const transport = createEshaLiveTransport({environment, fetchImpl: async () => {creates++;}, socketFactory: async () => {
    attempts++; const socket = new Socket(); setImmediate(() => socket.emit('error', new Error('fixture'))); return socket;
  }});
  await assert.rejects(transport.attach('live_fixture_1'), {code: 'voice_sideband_unavailable'});
  assert.equal(attempts, 1); assert.equal(creates, 0);
  await assert.rejects(transport.attach('live_1/../../other'), {code: 'voice_sideband_unavailable'});
  assert.equal(attempts, 1);
});

test('an observer that opens then immediately closes is rejected before returning a dead connection', async () => {
  let disconnected = 0;
  const transport = createEshaLiveTransport({environment, socketFactory: async () => {
    const socket = new Socket();
    setImmediate(() => {socket.readyState = 1; socket.emit('open'); socket.close();});
    return socket;
  }});
  await assert.rejects(transport.attach('live_fixture_1', {onDisconnect: () => disconnected++}), {code: 'voice_sideband_unavailable'});
  assert.equal(disconnected, 1);
});

test('spoken commentary is bounded without splitting Unicode characters', () => {
  const value = voiceCommentary('🌹保湿 '.repeat(500));
  assert(Buffer.byteLength(value) <= 384);
  assert(!value.includes('\ufffd'));
  assert.equal(voiceCommentary('  short\n answer  '), 'short answer');
});
