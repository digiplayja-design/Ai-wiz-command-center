import {ESHA_APPROVED_ALLOWANCES, ESHA_AI_ROLE_POLICY, UUID, digest, fail} from './catalog.mjs';

export const ESHA_LIVE_MODEL = 'gpt-live-1';
export const ESHA_LIVE_INITIALIZATION_SECONDS = 15;
const closeReasons = new Set(['close_requested', 'expired', 'content', 'remote_hangup', 'connection_lost']);
const stopReasons = new Set(['user_stop', 'paused', 'background', 'transport_error']);

export function voiceConfiguration(environment = process.env) {
  const raw = environment.KORLIX_ESHA_VOICE_MAX_SESSION_SECONDS;
  const maximum = typeof raw === 'string' && /^[1-9]\d{0,5}$/.test(raw) ? Number(raw) : null;
  return {
    model: ESHA_LIVE_MODEL, api: 'live', transport: 'webrtc', delegation: 'client',
    policySelected: environment.KORLIX_ESHA_AI_POLICY === ESHA_AI_ROLE_POLICY,
    voiceEnabled: false, configured: false, hardDurationBoundVerified: false,
    blocker: 'provider_duration_bound_unverified',
    maxSessionSeconds: maximum !== null && maximum >= ESHA_LIVE_INITIALIZATION_SECONDS &&
      maximum <= ESHA_APPROVED_ALLOWANCES.monthly.voiceSeconds ? maximum : null,
    voiceLimits: {trialSeconds: ESHA_APPROVED_ALLOWANCES.trial.voiceSeconds,
      monthlySeconds: ESHA_APPROVED_ALLOWANCES.monthly.voiceSeconds},
    deepLimits: {trial: ESHA_APPROVED_ALLOWANCES.trial.deepConsultations,
      monthly: ESHA_APPROVED_ALLOWANCES.monthly.deepConsultations},
  };
}

export function voiceRequestId(value) {
  if (typeof value !== 'string' || !UUID.test(value)) fail('Send a valid voice request ID.', 400, 'invalid_voice_request');
  return value.toLowerCase();
}

export function voiceCreateInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail('Send a voice connection offer.', 400, 'invalid_voice_request');
  const requestId = voiceRequestId(body.requestId);
  if (body.audioSharingConsent !== true) fail('Allow audio sharing before starting a voice conversation.', 400, 'voice_consent_required');
  if (body.deepThinkingConsent !== undefined && typeof body.deepThinkingConsent !== 'boolean') {
    fail('Choose whether voice can use a deep-thinking consultation.', 400, 'invalid_voice_request');
  }
  if (typeof body.sdpOffer !== 'string' || body.sdpOffer.length > 65536 ||
      !/^v=0\r?\n/.test(body.sdpOffer) || body.sdpOffer.includes('\0')) {
    fail('Send a valid voice connection offer.', 400, 'invalid_voice_request');
  }
  const data = {model: ESHA_LIVE_MODEL, sdpOffer: body.sdpOffer, audioSharingConsent: true,
    deepThinkingConsent: body.deepThinkingConsent === true};
  // SDP/audio/transcripts are not copied into the duration ledger.
  return {requestId, ...data, inputHash: digest(JSON.stringify(data))};
}

export function voiceStopReason(value) {
  if (!stopReasons.has(value)) fail('Send a valid voice stop reason.', 400, 'invalid_voice_request');
  return value;
}

export function voiceStatus(configuration, snapshot) {
  return {voiceEnabled: configuration.voiceEnabled === true, model: ESHA_LIVE_MODEL,
    voiceLimits: configuration.voiceLimits, deepLimits: configuration.deepLimits,
    membership: snapshot.membership, usage: snapshot.usage};
}

export function voiceUsageMilliseconds(seconds) {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds < 0 ||
      !Number.isSafeInteger(Math.ceil(seconds * 1000)) || seconds > 999999999) {
    fail('The voice provider returned invalid duration.', 502, 'invalid_voice_usage');
  }
  // Round conservatively to milliseconds; never round a reported billable
  // fraction down. Cumulative snapshots are replaced, not added together.
  return Math.ceil(seconds * 1000);
}

// Call only with events received on the authenticated server-owned sideband.
// This validates their shape; it is not authentication for client-supplied events.
export function voiceProviderEvent(event, sessionId) {
  if (event?.type === 'session.usage.updated') {
    return {kind: 'usage', sessionId, seconds: event.usage?.seconds,
      usageMs: voiceUsageMilliseconds(event.usage?.seconds)};
  }
  if (event?.type !== 'session.closed') return null;
  if (event.session?.id !== sessionId || event.session?.model !== ESHA_LIVE_MODEL ||
      !closeReasons.has(event.reason) || typeof event.event_id !== 'string' ||
      !/^[A-Za-z0-9_-]{1,200}$/.test(event.event_id)) {
    fail('The voice provider returned an invalid final event.', 502, 'invalid_voice_usage');
  }
  return {kind: 'closed', sessionId, eventId: event.event_id, reason: event.reason,
    seconds: event.usage?.seconds, usageMs: voiceUsageMilliseconds(event.usage?.seconds)};
}
