import {ESHA_APPROVED_ALLOWANCES, UUID, fail} from './catalog.mjs';
import {ESHA_LIVE_MODEL, voiceUsageMilliseconds, voiceProviderEvent} from './voice.mjs';

// Storage only. This module cannot create a paid session or retry a provider call.
// A caller may send one create request only after a confirmed begin.started=true.
export function createEshaVoiceLedger({database, store} = {}) {
  const limits = {trial_limit_seconds: ESHA_APPROVED_ALLOWANCES.trial.voiceSeconds,
    monthly_limit_seconds: ESHA_APPROVED_ALLOWANCES.monthly.voiceSeconds};
  async function command(actor, action, data = {}) {
    if (typeof actor !== 'string' || !UUID.test(actor)) fail('Sign in to use Esha.', 401, 'authentication_required');
    if (store) return store(actor, action, {...limits, ...data});
    if (!database) fail('Esha voice storage is temporarily unavailable.', 503, 'storage_unavailable');
    const result = await database.rpc('korlix_esha_voice_command', {p_actor: actor, p_action: action, p: {...limits, ...data}});
    if (result.error || !result.data || typeof result.data !== 'object') {
      const known = /ESHA(\d{3}):([a-z_]+):([^\n]+)/.exec(result.error?.message || '');
      fail(known ? known[3] : 'Esha voice storage is temporarily unavailable.', known ? Number(known[1]) : 503,
        known ? known[2] : 'storage_unavailable');
    }
    return result.data;
  }
  const ledger = {
    snapshot: actor => command(actor, 'snapshot'),
    status: (actor, requestId) => command(actor, 'status', {request_id: requestId}),
    reserve: (actor, {requestId, inputHash, reserveSeconds, deepThinkingConsent = false}) => command(actor, 'reserve', {
      request_id: requestId, input_hash: inputHash, reserve_seconds: reserveSeconds,
      deep_thinking_consent: deepThinkingConsent, model: ESHA_LIVE_MODEL}),
    begin: (actor, {requestId, inputHash, requestHash}) => command(actor, 'begin', {
      request_id: requestId, input_hash: inputHash, request_hash: requestHash}),
    attach: (actor, {requestId, sessionId, expiresAt}) => command(actor, 'attach', {
      request_id: requestId, provider_session_id: sessionId, provider_expires_at: expiresAt}),
    requestClose: (actor, {requestId, reason}) => command(actor, 'request_close', {request_id: requestId, reason}),
    markUncertain: (actor, {requestId, reason}) => command(actor, 'uncertain', {request_id: requestId, reason}),
    recordUsage: (actor, {requestId, sessionId, seconds}) => command(actor, 'usage', {
      request_id: requestId, provider_session_id: sessionId, usage_ms: voiceUsageMilliseconds(seconds)}),
    settle: async (actor, {requestId, sessionId, eventId, reason, seconds}) => {
      try { return await command(actor, 'settle', {
        request_id: requestId, provider_session_id: sessionId, final_event_id: eventId, reason,
        usage_ms: voiceUsageMilliseconds(seconds)}); }
      catch (error) {
        if (error.code === 'voice_final_usage_conflict') {
          await command(actor, 'uncertain', {request_id: requestId, reason: 'finalization_unconfirmed'}).catch(() => {});
        }
        throw error;
      }
    },
    delegation: (actor, {requestId, sessionId, delegationId, inputHash, consultationRequestId}) => command(actor, 'delegation', {
      request_id: requestId, provider_session_id: sessionId, delegation_id: delegationId,
      input_hash: inputHash, consultation_request_id: consultationRequestId}),
  };
  ledger.providerEvent = async (actor, requestId, sessionId, event) => {
    const parsed = voiceProviderEvent(event, sessionId);
    if (!parsed) return null;
    return parsed.kind === 'closed' ? ledger.settle(actor, {requestId, ...parsed}) : ledger.recordUsage(actor, {requestId, ...parsed});
  };
  return ledger;
}
