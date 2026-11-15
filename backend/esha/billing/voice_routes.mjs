import {UUID, EshaBillingError, digest, fail, productFor} from './catalog.mjs';
import {consultationInput} from './consultation.mjs';
import {voiceConfiguration, voiceCreateInput, voiceRequestId, voiceStopReason, voiceStatus,
  ESHA_LIVE_MODEL, ESHA_LIVE_INITIALIZATION_SECONDS} from './voice.mjs';
import {createEshaVoiceLedger} from './voice_ledger.mjs';
import {createEshaLiveTransport, liveSessionRequest} from './voice_transport.mjs';

function requireVerifiedUser(user) {
  if (!UUID.test(user?.id || '')) fail('Sign in to your Korlix account.', 401, 'authentication_required');
  if (!user.email_confirmed_at) fail('Verify your Korlix email before using voice.', 403, 'email_confirmation_required');
}
function publicSession(result) {
  return {...result, state: result.state === 'reserved' ? 'starting' : result.state};
}
function consultationId(actor, requestId, delegationId) {
  const hex = digest(`esha:voice:deep:${actor}:${requestId}:${delegationId}`);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

export function createEshaVoice({database, store, requireUser, billing, environment = process.env,
  ledger = createEshaVoiceLedger({database, store, environment}), transport = createEshaLiveTransport({environment}),
  configuration = () => voiceConfiguration(environment), now = Date.now, watchdogMs = 5000} = {}) {
  const sessions = new Map();
  const rates = new Map();
  let durationContradicted = false;
  const sessionKey = (actor, requestId) => `${actor}:${requestId}`;
  const ready = () => {
    const config = configuration();
    return !durationContradicted && config.configured === true && config.voiceEnabled === true && config.policySelected === true &&
      config.hardDurationBoundVerified === true && Number.isInteger(config.maxSessionSeconds) &&
      config.maxSessionSeconds >= ESHA_LIVE_INITIALIZATION_SECONDS && config.maxSessionSeconds <= 1800 &&
      config.startAttemptsConfigured === true && Number.isInteger(config.trialStartAttempts) && config.trialStartAttempts > 0 &&
      Number.isInteger(config.monthlyStartAttempts) && config.monthlyStartAttempts > 0 &&
      environment.KORLIX_ESHA_VOICE_ENABLED === 'true' && transport.available() && billing?.ready?.() === true;
  };
  const uncertain = (record, reason) => ledger.markUncertain(record.user.id,
    {requestId: record.requestId, reason}).catch(() => {});
  const forget = record => {
    clearInterval(record.watchdog); clearTimeout(record.deadline);
    record.connection?.dispose(); record.connection = null;
    record.transcript.length = 0; record.seen.clear();
    sessions.delete(sessionKey(record.user.id, record.requestId));
  };
  function sendClose(record) {
    if (!record.connection || record.closeSent) return;
    record.connection.closeSession(`esha_close_${record.requestId}`);
    record.closeSent = true;
  }
  async function requestClose(record, reason = 'transport_error') {
    record.closing = true;
    let result;
    try { result = await ledger.requestClose(record.user.id, {requestId: record.requestId, reason}); }
    finally {
      // Ask the provider to stop even if storage is currently unavailable.
      // Neither this send nor a closed socket is a final-usage receipt.
      try { sendClose(record); }
      catch { await uncertain(record, 'transport_lost'); }
    }
    if (result?.finalizationConfirmed) {record.finalized = true; forget(record);}
    return result;
  }
  const commentary = (record, delegationId, content) => {
    if (record.closing || record.finalized) return;
    try { record.connection?.commentary(delegationId, content, `esha_deep_${digest(delegationId).slice(0, 32)}`); }
    catch { void requestClose(record).catch(() => {}); }
  };
  async function delegate(record, event) {
    const id = event.delegation?.id;
    if (event.delegation?.target !== 'client' || !/^[A-Za-z0-9_-]{1,200}$/.test(id || '') ||
        record.delegations.has(id) || record.closing || record.finalized) return;
    record.delegations.add(id);
    if (!record.deepThinkingConsent) {
      commentary(record, id, 'Deep thinking was not enabled for this call. You can end this call and enable it before starting another.');
      return;
    }
    // A greeting or replay without a spoken user question never spends a Sol
    // consultation. This transcript is temporary and never enters the voice ledger.
    const lastUser = record.transcript.findLastIndex(turn => turn.role === 'user' && turn.content.trim());
    if (lastUser < 0) {commentary(record, id, 'Ask the caller what beauty question they would like help with.'); return;}
    try {
      const body = {requestId: consultationId(record.user.id, record.requestId, id),
        question: record.transcript[lastUser].content.slice(-3000),
        history: record.transcript.slice(0, lastUser).slice(-10), preferences: {}};
      const input = consultationInput(body);
      const bound = await ledger.delegation(record.user.id, {requestId: record.requestId, sessionId: record.sessionId,
        delegationId: id, inputHash: input.inputHash, consultationRequestId: input.requestId});
      // Only the durable first mapping can initiate a new consultation. Replayed
      // events after reconnect do not reconstruct or re-run a paid request.
      if (bound.created !== true || record.closing || record.finalized) return;
      const result = await billing.consult(record.user, {...body, requestId: bound.consultationRequestId});
      commentary(record, id, result.answer);
    } catch (error) {
      commentary(record, id, ['allowance_exhausted', 'provider_attempts_exhausted'].includes(error?.code)
        ? 'No deep-thinking consultations are available in this billing period. Continue with general cosmetic conversation.'
        : 'Deep thinking is unavailable for this request. Do not invent a completed analysis or a product recommendation.');
    }
  }
  async function eventReceived(record, event) {
    if (record.finalized) return;
    if (event.event_id) {
      if (typeof event.event_id !== 'string' || event.event_id.length > 512 || record.seen.has(event.event_id)) return;
      if (record.seen.size >= 16000) {await requestClose(record); return;}
      record.seen.add(event.event_id);
    }
    if (['session.started', 'session.updated'].includes(event.type)) {
      if (event.session?.id !== record.sessionId || event.session?.model !== ESHA_LIVE_MODEL ||
          !Number.isSafeInteger(event.session.expires_at) || event.session.expires_at <= 0 ||
          event.session.expires_at > 253402300799) throw new Error('invalid_voice_session');
      const result = await ledger.attach(record.user.id, {requestId: record.requestId, sessionId: record.sessionId,
        expiresAt: new Date(event.session.expires_at * 1000).toISOString()});
      // An observed expiry beyond the authorized hold contradicts the proposed
      // bound. Stop immediately; keep the hold until final usage is confirmed.
      if (Date.parse(result.authorizedUntil) < event.session.expires_at * 1000 || result.closeRequired) {
        if (Date.parse(result.authorizedUntil) < event.session.expires_at * 1000) durationContradicted = true;
        await requestClose(record);
      }
    } else if (event.type === 'session.closed' || event.type === 'session.usage.updated') {
      if (event.type === 'session.closed') record.pendingTerminal = event;
      const result = await ledger.providerEvent(record.user.id, record.requestId, record.sessionId, event);
      if (event.type === 'session.closed' && result?.finalizationConfirmed) {
        record.pendingTerminal = null;
        record.finalized = true; forget(record);
      } else if (result?.closeRequired) await requestClose(record);
    } else if (event.type === 'error') {
      if (record.closing) await uncertain(record, 'finalization_unconfirmed');
      else await requestClose(record);
    } else if (['session.input_transcript.delta', 'session.output_transcript.delta'].includes(event.type)) {
      if (typeof event.delta !== 'string' || !event.delta) return;
      const role = event.type === 'session.input_transcript.delta' ? 'user' : 'assistant';
      const last = record.transcript.at(-1);
      if (last?.role === role) last.content = (last.content + event.delta).slice(-3000);
      else record.transcript.push({role, content: event.delta.slice(-3000)});
      if (record.transcript.length > 10) record.transcript.shift();
    } else if (event.type === 'session.delegation.created') {
      // Token counting/generation must never block usage, close or revoke events.
      void delegate(record, event);
    }
  }
  async function observe(record) {
    if (record.connection || record.attaching) return record.attaching;
    const observation = {lost: false};
    record.observation = observation;
    record.attaching = transport.attach(record.sessionId, {
      onEvent(event) {
        record.queue = record.queue.then(() => eventReceived(record, event)).catch(async () => {
          if (event.event_id) record.seen.delete(event.event_id);
          await uncertain(record, 'storage_unconfirmed');
          await requestClose(record).catch(() => {});
        });
        return record.queue;
      },
      onDisconnect: async () => {
        observation.lost = true;
        if (record.finalized || record.observation !== observation) return;
        record.connection = null;
        record.closing = true;
        await uncertain(record, 'transport_lost');
      },
    }).then(connection => {
      if (record.finalized) connection.dispose();
      else if (observation.lost || record.observation !== observation) {
        connection.dispose();
        fail('The voice connection could not be monitored.', 503, 'voice_sideband_unavailable');
      } else {
        record.connection = connection;
        record.closeSent = false;
        try {if (record.closing) sendClose(record);}
        catch (error) {record.connection = null; connection.dispose(); throw error;}
      }
    }).finally(() => {record.attaching = null;});
    return record.attaching;
  }
  function makeRecord(user, result, identityPersisted = false) {
    const record = {user, requestId: result.requestId, sessionId: result.sessionId,
      deepThinkingConsent: result.deepThinkingConsent === true, closing: result.closeRequested === true,
      finalized: false, transcript: [], seen: new Set(), delegations: new Set(), queue: Promise.resolve(),
      connection: null, attaching: null, watchdog: null, deadline: null, pendingTerminal: null, recoveryAttempts: 0,
      identityPersisted, closeSent: false};
    sessions.set(sessionKey(user.id, result.requestId), record);
    watch(record, result);
    return record;
  }
  function watch(record, authorization) {
    if (record.watchdog) return;
    // These timers are defense in depth only. They are never accepted as proof
    // of a provider-enforced duration bound by ready()/voiceConfiguration().
    const deadline = Date.parse(authorization.authorizedUntil);
    record.deadline = setTimeout(() => {void requestClose(record).catch(() => {});},
      Math.max(0, deadline - now() - 1000));
    record.deadline.unref?.();
    let pending = false;
    record.watchdog = setInterval(async () => {
      if (pending || record.finalized) return;
      pending = true;
      try {
        if (!record.identityPersisted) {
          await ledger.attach(record.user.id, {requestId: record.requestId, sessionId: record.sessionId, expiresAt: null});
          record.identityPersisted = true;
        }
        if (record.pendingTerminal) {
          const terminal = record.pendingTerminal;
          try {await eventReceived(record, terminal);}
          catch (error) {record.seen.delete(terminal.event_id); throw error;}
        }
        if (record.finalized) return;
        if (!record.connection && record.closing && record.recoveryAttempts < 1) {
          record.recoveryAttempts++;
          await observe(record);
          await requestClose(record);
        }
        const result = await ledger.status(record.user.id, record.requestId);
        if (result.finalizationConfirmed) {record.finalized = true; forget(record);}
        else if (result.closeRequired || !ready()) await requestClose(record);
      } catch {await requestClose(record).catch(() => {});}
      finally {pending = false;}
    }, watchdogMs);
    record.watchdog.unref?.();
  }
  async function status(user, providerName, refresh = false) {
    requireVerifiedUser(user); productFor(providerName);
    if (refresh) await billing?.refresh(user.id);
    const snapshot = await ledger.snapshot(user.id);
    const startBudget = snapshot.usage?.voiceStarts;
    const startsConfigured = startBudget?.configured === true;
    const startsExhausted = startBudget?.configured === true && startBudget.remaining === 0;
    const reason = !ready() ? 'voice_not_configured' : !startsConfigured ? 'voice_start_budget_conflict'
      : startsExhausted ? 'voice_start_attempts_exhausted' : null;
    return {...voiceStatus({...configuration(), voiceEnabled: ready() && startsConfigured && !startsExhausted}, snapshot),
      unavailabilityReason: reason};
  }
  async function start(user, body) {
    requireVerifiedUser(user);
    if (!ready()) fail('Voice is being configured. No voice session has been started.', 503, 'voice_not_configured');
    const input = voiceCreateInput(body);
    let balance = await ledger.snapshot(user.id);
    if (!balance.membership?.verificationFresh) {await billing.refresh(user.id); balance = await ledger.snapshot(user.id);}
    const reserveSeconds = configuration().maxSessionSeconds;
    // Reserve the complete verified worst-case duration, not a guessed shorter
    // call duration. Users cannot create a session with a partial hold.
    let reserved;
    try {reserved = await ledger.reserve(user.id, {...input, reserveSeconds});}
    catch (error) {
      if (error instanceof EshaBillingError && ['voice_start_attempts_exhausted', 'voice_start_attempts_not_configured',
        'voice_start_budget_conflict'].includes(error.code)) {
        // SQL replays existing UUIDs before these checks. Only an absent UUID
        // can receive this rejection: no reservation or provider begin exists.
        // Never reuse this zero-work code for begin/transport/storage failures.
        fail(error.message, error.status, 'voice_start_not_created');
      }
      throw error;
    }
    if (reserved.created !== true) fail('This voice request already exists. Check its status before starting another call.', 409, 'voice_request_pending');
    const request = liveSessionRequest({actor: user.id, ...input});
    let record, began = false, beginReturned = false;
    try {
      const authorization = await ledger.begin(user.id, {requestId: input.requestId, inputHash: input.inputHash,
        requestHash: digest(JSON.stringify(request))});
      beginReturned = true;
      if (authorization.exhausted === true) {
        await ledger.requestClose(user.id, {requestId: input.requestId, reason: 'transport_error'});
        fail('The voice connection limit has been reached for this billing period.', 429, 'voice_start_attempts_exhausted');
      }
      if (authorization.started !== true) fail('This voice request has already been sent.', 409, 'voice_request_pending');
      began = true;
      const created = await transport.create(request);
      record = makeRecord(user, {...authorization, ...created, requestId: input.requestId,
        deepThinkingConsent: input.deepThinkingConsent});
      const attached = await ledger.attach(user.id, {requestId: input.requestId, sessionId: created.sessionId, expiresAt: null});
      record.identityPersisted = true;
      await observe(record);
      if (record.closing || record.finalized || attached.closeRequired) fail('The voice session is already ending. Check its status.', 409, 'voice_request_pending');
      return {...publicSession(attached), sdpAnswer: created.sdpAnswer};
    } catch (error) {
      if (began) {
        if (record) {
          await uncertain(record, 'create_unconfirmed');
          await observe(record).catch(() => {});
          await requestClose(record).catch(() => {});
        } else await ledger.markUncertain(user.id, {requestId: input.requestId, reason: 'create_unconfirmed'}).catch(() => {});
      } else if (!beginReturned) {
        // An uncertain begin response is resolved by database state: a never-
        // started reservation may cancel; a committed begin retains its hold.
        await ledger.requestClose(user.id, {requestId: input.requestId, reason: 'transport_error'}).catch(() => {});
      }
      throw error;
    }
  }
  async function session(user, id) {
    requireVerifiedUser(user); const requestId = voiceRequestId(id);
    const result = await ledger.status(user.id, requestId);
    if (!result.finalizationConfirmed && result.sessionId && !sessions.has(sessionKey(user.id, requestId))) {
      // A process restart cannot resume unmonitored media. Reattach only to end
      // the already-existing session and reconcile its final usage.
      return stopSession(user, requestId, 'transport_error');
    }
    return publicSession(result);
  }
  async function stopSession(user, id, reason) {
    requireVerifiedUser(user); const requestId = voiceRequestId(id); voiceStopReason(reason);
    let result = await ledger.requestClose(user.id, {requestId, reason});
    if (result.finalizationConfirmed || !result.sessionId) return publicSession(result);
    let record = sessions.get(sessionKey(user.id, requestId));
    if (!record) record = makeRecord(user, result, true);
    record.closing = true;
    await observe(record).catch(async () => {await uncertain(record, 'transport_lost');});
    await requestClose(record, reason).catch(() => {});
    result = await ledger.status(user.id, requestId);
    return publicSession(result);
  }
  const protectedRoute = handler => async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = typeof requireUser === 'function' ? await requireUser(req) : null;
      requireVerifiedUser(user);
      const previous = rates.get(user.id);
      if (previous && previous.until > now()) {if (++previous.count > 60) fail('Wait a minute before retrying.', 429, 'rate_limited');}
      else rates.set(user.id, {count: 1, until: now() + 60000});
      if (rates.size > 10000) for (const [key, value] of rates) if (value.until <= now()) rates.delete(key);
      res.json(await handler(req, user));
    } catch (error) {
      const code = error instanceof EshaBillingError ? error.status : 503;
      res.status(code).json({error: error instanceof EshaBillingError ? error.message : 'Voice is temporarily unavailable. Check your session status before retrying.',
        code: error instanceof EshaBillingError ? error.code : 'voice_unavailable'});
    }
  };
  function register(app) {
    app.get('/api/esha/voice/status', protectedRoute((req, user) => status(user, req.query.provider, req.query.refresh === '1')));
    app.post('/api/esha/voice/sessions', protectedRoute((req, user) => start(user, req.body)));
    app.get('/api/esha/voice/sessions/:requestId', protectedRoute((req, user) => session(user, req.params.requestId)));
    app.post('/api/esha/voice/sessions/:requestId/stop', protectedRoute((req, user) => stopSession(user, req.params.requestId, req.body?.reason)));
  }
  async function dispose() {
    await Promise.all([...sessions.values()].map(async record => {
      await requestClose(record).catch(() => {});
      // Shutdown cannot manufacture terminal proof. Preserve the durable hold.
      if (!record.finalized) await uncertain(record, 'finalization_unconfirmed');
      forget(record);
    }));
  }
  return {register, ready, status, start, session, stopSession, dispose};
}
