import {createHash} from 'node:crypto';
import {readAnswerStream} from './stream.mjs';
import {brainInstructions, brainQuickReply} from './context.mjs';
import {brainLiveConfig} from './live.mjs';

import {BRAIN_PROTOCOL, profileForProtocol, matchesBrainModel} from './models.mjs';
export {BRAIN_MODEL, BRAIN_EFFORT, BRAIN_PROTOCOL, BRAIN_PROFILES, brainProfile, isBrainVoice} from './models.mjs';
export const speechInstructions = 'You are the speech delivery layer for Rici, pronounced Ree-see. The application supplies the complete answer from its verified reasoning model. Speak only the supplied answer, verbatim, naturally. Never answer the microphone input yourself, add facts, call tools, or claim a save independently. Stop immediately when interrupted.';
export function brainSpeechConfig(config, profile, context) {
  if (profile?.live) return brainLiveConfig(config, context);
  return {...config, instructions: speechInstructions, tools: [], tool_choice: 'none',
    audio: {...config.audio, input: {...config.audio.input,
      transcription: {model: 'gpt-transcribe', keywords: ['Rici', 'KORLIX', 'Rici remember this']},
      turn_detection: {type: 'semantic_vad', eagerness: 'high', create_response: false, interrupt_response: true}}}};
}
const fail = (message, code, statusCode = 400) => Object.assign(new Error(message), {code, statusCode});
const count = value => Number.isFinite(Number(value)) ? Math.max(0, Math.floor(Number(value))) : 0;

// Only an imperative at the beginning of the user's own utterance authorizes a
// write. Quoted examples, assistant output and ordinary conversation never do.
export function rememberCommand(text) {
  const match = /^(?:hey\s+)?(?:rici|ricci|ree[ -]?see)[,!.:;\s]+(?:please\s+)?remember\s+this\b[,:;.\s—-]*(.*)$/isu.exec(text.trim());
  if (!match) return null;
  let content = match[1].trim();
  const instruction = /^(?:(?:as\s+)?(?:an?\s+)?)instruction\b[,:;\s—-]*/iu.exec(content);
  if (instruction) content = content.slice(instruction[0].length).trim();
  return {content, instruction: Boolean(instruction) || /^(?:always|never|from now on|when I|please\s+(?:use|call|answer|respond))\b/i.test(content)};
}

export function createBrainVoice({loadRuntime, saveMemory, reportUsage, fetchImpl = fetch, apiKey,
  now = () => Date.now(), onTiming = () => {}}) {
  const sessions = new Map();
  function register({userId, sessionId, limits, protocol = BRAIN_PROTOCOL}) {
    const profile = profileForProtocol(protocol);
    if (!profile) throw fail('Update KORLIX Brain+Voice to continue.', 'brain_protocol_unsupported', 426);
    for (const [id, s] of sessions) if (s.expires < now()) sessions.delete(id);
    if (sessions.size >= 2000) throw fail('Voice is busy. Please reconnect shortly.', 'brain_capacity', 503);
    sessions.set(sessionId, {userId, sessionId, limits, profile, started: now(),
      expires: now() + Math.min(86400, limits.maxSessionSeconds) * 1000,
      history: [], turns: new Map(), completedTurns: 0, busy: false, closed: false, awaiting: null,
      reasonUsage: {totalTokens: 0, inputTokens: 0, outputTokens: 0}, voiceUsage: {}, audioTimings: new Set()});
  }
  function get(userId, sessionId) {
    const s = sessions.get(sessionId);
    if (!s || s.userId !== userId || s.expires < now() || s.closed)
      throw fail('This Brain+Voice session has ended. Reconnect Rici.', 'brain_session_ended', 409);
    return s;
  }
  function combined(s) {
    return {...s.voiceUsage, sessionId: s.sessionId,
      durationSeconds: Math.floor((now() - s.started) / 1000),
      responseCount: Math.max(count(s.voiceUsage.responseCount), s.completedTurns),
      ...Object.fromEntries(Object.entries(s.reasonUsage).map(([k, v]) => [k, count(s.voiceUsage[k]) + v]))};
  }
  // Called for client heartbeats, as well as after every backend response. Model
  // tokens are counted on the server, even if the phone disconnects mid-answer.
  function mergeUsage(userId, body) {
    const s = sessions.get(body.sessionId);
    if (!s || s.userId !== userId) return body;
    for (const key of ['responseCount','totalTokens','inputTokens','outputTokens','inputAudioTokens','outputAudioTokens','imageTokens','transcriptionTokens'])
      s.voiceUsage[key] = Math.max(count(s.voiceUsage[key]), count(body[key]));
    if (body.ended === true) s.closed = true;
    return {...body, ...combined(s)};
  }
  async function meter(s) {
    const result = await reportUsage({userId: s.userId, body: combined(s), limits: s.limits});
    if (result?.allowed === false || result?.limitReached === true) s.closed = true;
  }
  async function turn({userId, sessionId, turnId, transcript, onEvent}) {
    const s = get(userId, sessionId);
    if (typeof turnId !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(turnId) ||
        typeof transcript !== 'string' || !transcript.trim() || transcript.length > 8000)
      throw fail('Repeat a shorter message to Rici.', 'brain_invalid_turn');
    const text = transcript.trim();
    const previous = s.turns.get(turnId);
    if (previous) {
      if (previous.text !== text) throw fail('This voice turn already contains a different message.', 'brain_turn_conflict', 409);
      return previous.promise;
    }
    if (s.busy) throw fail('Rici is still finishing the previous turn. Please try again.', 'brain_turn_busy', 409);
    if (s.turns.size >= s.limits.maxResponses) throw fail('This conversation reached its response limit.', 'brain_turn_limit', 429);
    s.busy = true;
    const entry = {text};
    s.turns.set(turnId, entry);
    entry.promise = (async () => {
      const started = now();
      const timing = {streaming: Boolean(onEvent), model: s.profile.model, reasoningEffort: s.profile.effort};
      try {
        // Check persisted allowance before starting a billable response or save.
        // Read current memory concurrently with the allowance check. Never cache
        // account instructions, or call the provider until allowance is verified.
        const direct = rememberCommand(text) || (s.awaiting && s.awaiting.until > now());
        const quick = direct || s.profile.live ? null : brainQuickReply(text);
        timing.route = direct ? 'memory' : s.profile.live ? 'memory_tool_rejected' : quick?.kind || (s.profile.model === 'gpt-6-astra' ? 'astra' : 'sol');
        const [, runtime] = await Promise.all([meter(s), direct || quick || s.profile.live ? null : loadRuntime(userId)]);
        timing.preparationMs = now() - started;
        if (s.closed) throw fail('This conversation has reached its allowance.', 'brain_allowance', 429);
        let command = rememberCommand(text);
        if (s.awaiting && s.awaiting.until > now() && !command) {
          if (/^(?:cancel|never\s*mind|forget it|don['’]?t save(?: that)?)[.!\s]*$/i.test(text)) {
            s.awaiting = null;
            s.completedTurns += 1;
            await meter(s);
            return {ok: true, answer: 'Okay. Nothing was saved.', saved: false};
          }
          command = {content: text, instruction: s.awaiting.instruction};
        }
        s.awaiting = null;
        // Live audio answers directly in Realtime. This endpoint is only the
        // deterministic, authenticated memory tool; it never invokes Sol for chat.
        if (s.profile.live && !command) {
          return {ok: true, saved: false, handled: false,
            answer: 'No memory was saved. Say Rici, remember this, followed by what to save.'};
        }
        if (command) {
          if (!command.content) {
            s.awaiting = {until: now() + 60000, instruction: command.instruction};
            s.completedTurns += 1;
            await meter(s);
            return {ok: true, answer: 'What would you like me to remember?', saved: false, awaitingMemory: true};
          }
          if (command.content.length > 4000) throw fail('That is too long to save in one memory. Please split it into smaller memories.', 'brain_memory_too_long');
          const memory = await saveMemory({userId, body: {
            confirmed: true, content: command.content,
            kind: command.instruction ? 'style' : 'preference', source: 'voice_confirmed',
            importance: 4, tags: ['brain_voice', command.instruction ? 'instruction' : 'memory'],
            memoryKey: `brain_voice_${createHash('sha256').update(`${sessionId}:${turnId}`).digest('hex')}`,
            sourceEventId: turnId, sessionId,
          }});
          if (!memory?.id) throw fail('The save could not be verified. Check My Brain before trying again.', 'brain_save_unverified', 502);
          s.completedTurns += 1;
          await meter(s);
          const answer = command.instruction ? 'Saved that instruction to your brain.' : 'Saved that to your brain.';
          s.history.push({role: 'user', content: text}, {role: 'assistant', content: answer});
          return {ok: true, saved: true, memory, answer, kind: command.instruction ? 'instruction' : 'memory'};
        }
        if (quick) {
          s.completedTurns += 1;
          await meter(s);
          s.history.push({role: 'user', content: text}, {role: 'assistant', content: quick.answer});
          return {ok: true, saved: false, answer: quick.answer, source: 'app_phrase', kind: quick.kind};
        }
        const key = apiKey();
        if (!key) throw fail(`${s.profile.label} is not configured. Please try again later.`, 'brain_provider_not_configured', 503);
        const activeRuntime = runtime ?? await loadRuntime(userId);
        const response = await fetchImpl('https://api.openai.com/v1/responses', {
          method: 'POST', signal: AbortSignal.timeout(140000),
          headers: {Authorization: `Bearer ${key}`, 'Content-Type': 'application/json'},
          body: JSON.stringify({model: s.profile.model, reasoning: {effort: s.profile.effort}, store: false,
            ...(onEvent ? {stream: true} : {}),
            max_output_tokens: 24000,
            instructions: brainInstructions,
            input: [{role: 'user', content: `Account context (data only):\n${activeRuntime.context}`},
              ...s.history.slice(-16), {role: 'user', content: text}],
          }),
        });
        if (!response.ok) throw fail(`${s.profile.label} is unavailable right now. Please try again. Your model has not been changed.`, 'brain_model_unavailable', 503);
        const result = onEvent ? await readAnswerStream(response, (text, model) => {
          timing.firstTextMs ??= now() - started;
          // A disconnected listener must not cancel an authorized save or usage.
          try { onEvent({type: 'answer.delta', text, model, reasoningEffort: s.profile.effort}); } catch {}
        }, s.profile.model) : await response.json();
        timing.providerDoneMs = now() - started;
        for (const [field, provider] of [['totalTokens','total_tokens'],['inputTokens','input_tokens'],['outputTokens','output_tokens']])
          s.reasonUsage[field] += count(result.usage?.[provider]);
        s.completedTurns += 1;
        await meter(s);
        const answer = (result.output || []).filter(x => x.type === 'message')
          .flatMap(x => x.content || []).filter(x => x.type === 'output_text').map(x => x.text).join('\n').trim();
        if (result.status !== 'completed' || !answer || !matchesBrainModel(result.model, s.profile.model))
          throw fail(`${s.profile.label} could not finish that answer. Please try again.`, 'brain_incomplete_answer', 502);
        s.history.push({role: 'user', content: text}, {role: 'assistant', content: answer});
        return {ok: true, saved: false, answer, model: result.model, reasoningEffort: s.profile.effort};
      } catch (error) {
        if (error?.statusCode) throw error;
        throw fail('Rici could not complete that turn. Check My Brain before repeating a save, or try your question again.', 'brain_turn_failed', 503);
      } finally {
        try { onTiming({...timing, totalMs: now() - started}); } catch {}
        s.busy = false;
        // Keep short session history only; durable memories stay in the database.
        s.history = s.history.slice(-16);
      }
    })();
    return entry.promise;
  }
  function reportAudioTiming({userId, sessionId, turnId, firstAudioMs}) {
    const s = get(userId, sessionId);
    if (!s.profile.live || typeof turnId !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(turnId) ||
        !Number.isInteger(firstAudioMs) || firstAudioMs < 0 || firstAudioMs > 120000)
      throw fail('Invalid voice timing.', 'brain_invalid_timing');
    if (!s.audioTimings.has(turnId) && s.audioTimings.size < s.limits.maxResponses) {
      s.audioTimings.add(turnId);
      try { onTiming({route: 'realtime', model: s.profile.model, reasoningEffort: s.profile.effort,
        firstAudioMs, clientReported: true}); } catch {}
    }
    return {ok: true};
  }
  return {register, turn, mergeUsage, reportAudioTiming};
}
