import test from 'node:test';
import assert from 'node:assert/strict';
import {ESHA_AI_ROLE_POLICY, ESHA_APPROVED_ALLOWANCES, allowanceConfiguration, nativeAiConfigured} from '../esha/billing/catalog.mjs';
import {voiceConfiguration, voiceCreateInput, voiceProviderEvent, voiceUsageMilliseconds} from '../esha/billing/voice.mjs';

const requestId = '11111111-1111-4111-8111-111111111111';
const offer = {requestId, sdpOffer: 'v=0\r\no=fixture\r\n', audioSharingConsent: true};

test('approved role policy supplies exactly 300/1800 voice seconds and 2/10 deep counts; legacy configuration is unchanged', () => {
  assert.deepEqual(ESHA_APPROVED_ALLOWANCES, {trial: {voiceSeconds: 300, deepConsultations: 2},
    monthly: {voiceSeconds: 1800, deepConsultations: 10}});
  const policy = {KORLIX_ESHA_AI_POLICY: ESHA_AI_ROLE_POLICY};
  assert.deepEqual(allowanceConfiguration(policy), {configured: true, trial: 2, monthly: 10});
  assert.equal(nativeAiConfigured(policy, {role: 'deep_thinking'}), false);
  for (const change of [{KORLIX_ESHA_TRIAL_CONSULTATIONS: '3'}, {KORLIX_ESHA_MONTHLY_CONSULTATIONS: '4'},
    {KORLIX_ESHA_MONTHLY_CONSULTATIONS: ''}, {KORLIX_ESHA_TRIAL_CONSULTATIONS: 2}]) {
    assert.deepEqual(allowanceConfiguration({...policy, ...change}), {configured: false, trial: null, monthly: null});
  }
  assert.deepEqual(allowanceConfiguration({}), {configured: false, trial: null, monthly: null});
  assert.deepEqual(allowanceConfiguration({KORLIX_ESHA_TRIAL_CONSULTATIONS: '2', KORLIX_ESHA_MONTHLY_CONSULTATIONS: '4'}),
    {configured: true, trial: 2, monthly: 4});
});

test('engineering flags and an asserted provider bound cannot activate the unverified Live implementation', () => {
  for (const environment of [{}, {KORLIX_ESHA_AI_POLICY: ESHA_AI_ROLE_POLICY,
    KORLIX_ESHA_NATIVE_VOICE_ENABLED: 'true', KORLIX_ESHA_VOICE_PROVIDER_BOUND_VERIFIED: 'true',
    KORLIX_ESHA_VOICE_MAX_SESSION_SECONDS: '60', KORLIX_ESHA_NATIVE_AI_ENABLED: 'true'}]) {
    const config = voiceConfiguration(environment);
    assert.equal(config.model, 'gpt-live-1'); assert.equal(config.transport, 'webrtc');
    assert.equal(config.configured, false); assert.equal(config.voiceEnabled, false);
    assert.equal(config.hardDurationBoundVerified, false);
    assert.deepEqual(config.voiceLimits, {trialSeconds: 300, monthlySeconds: 1800});
    assert.deepEqual(config.deepLimits, {trial: 2, monthly: 10});
  }
  assert.equal(voiceConfiguration({}).maxSessionSeconds, null);
  for (const value of ['0', '14', '1801', '1e2', '', 'Infinity']) {
    assert.equal(voiceConfiguration({KORLIX_ESHA_VOICE_MAX_SESSION_SECONDS: value}).maxSessionSeconds, null);
  }
});

test('voice input requires audio consent, defaults deep consent off, and binds SDP and consent into identity', () => {
  const plain = voiceCreateInput(offer);
  assert.equal(plain.deepThinkingConsent, false); assert.equal(plain.model, 'gpt-live-1');
  assert.notEqual(voiceCreateInput({...offer, deepThinkingConsent: true}).inputHash, plain.inputHash);
  assert.notEqual(voiceCreateInput({...offer, sdpOffer: offer.sdpOffer+'a=sendrecv\r\n'}).inputHash, plain.inputHash);
  assert.equal(voiceCreateInput({...offer, model: 'cheaper-model', role: 'system'}).inputHash, plain.inputHash);
  for (const body of [{...offer, audioSharingConsent: false}, {...offer, audioSharingConsent: 'true'},
    {...offer, deepThinkingConsent: 'true'}, {...offer, sdpOffer: 'invalid'}, {...offer, sdpOffer: 'v=0\n'+'x'.repeat(65536)},
    {...offer, requestId: '../another-user'}]) assert.throws(() => voiceCreateInput(body));
});

test('provider finalization requires exact session identity and a terminal event; decimal cumulative usage is preserved', () => {
  const event = {type: 'session.closed', event_id: 'evt_closed_1', reason: 'close_requested',
    session: {id: 'live_fixture', model: 'gpt-live-1', status: 'active'}, usage: {seconds: 45.8}};
  assert.deepEqual(voiceProviderEvent(event, 'live_fixture'), {kind: 'closed', sessionId: 'live_fixture',
    eventId: 'evt_closed_1', reason: 'close_requested', seconds: 45.8, usageMs: 45800});
  assert.equal(voiceProviderEvent({type: 'socket.closed'}, 'live_fixture'), null);
  assert.equal(voiceProviderEvent({type: 'session.updated'}, 'live_fixture'), null);
  assert.throws(() => voiceProviderEvent(event, 'live_other'), {code: 'invalid_voice_usage'});
  for (const seconds of [-1, NaN, Infinity, '20', 1e15]) assert.throws(() => voiceUsageMilliseconds(seconds));
  assert.equal(voiceUsageMilliseconds(0.0001), 1);
});
