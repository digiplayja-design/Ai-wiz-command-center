import {createHash} from 'node:crypto';
import {readAnswerStream} from './stream.mjs';

export const BRAIN_MODEL = 'gpt-6-astra';
export const BRAIN_EFFORT = 'max';
export const BRAIN_PROTOCOL = 'astra-max-v1';
export const speechInstructions = 'You are the speech delivery layer for Rici, pronounced Ree-see. The application supplies the complete answer from GPT-6 Astra Max. Speak only the supplied answer, verbatim, naturally. Never answer the microphone input yourself, add facts, call tools, or claim a save independently. Stop immediately when interrupted.';
export const isBrainVoice = req => req.headers?.['x-korlix-brain-voice'] === BRAIN_PROTOCOL;
export function brainSpeechConfig(config) {
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
  function register({userId, sessionId, limits}) {
    for (const [id, s] of sessions) if (s.expires < now()) sessions.delete(id);
    if (sessions.size >= 2000) throw fail('Voice is busy. Please reconnect shortly.', 'brain_capacity', 503);
    sessions.set(sessionId, {userId, sessionId, limits, started: now(),
      expires: now() + Math.min(86400, limits.maxSessionSeconds) * 1000,
      history: [], turns: new Map(), completedTurns: 0, busy: false, closed: false, awaiting: null,
      reasonUsage: {totalTokens: 0, inputTokens: 0, outputTokens: 0}, voiceUsage: {}});
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
      const timing = {streaming: Boolean(onEvent)};
      try {
        // Check persisted allowance before starting a billable response or save.
        // Read current memory concurrently with the allowance check. Never cache
        // account instructions, or call the provider until allowance is verified.
        const direct = rememberCommand(text) || (s.awaiting && s.awaiting.until > now());
        const [, runtime] = await Promise.all([meter(s), direct ? null : loadRuntime(userId)]);
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
        const key = apiKey();
        if (!key) throw fail('Astra Max is not configured. Please try again later.', 'brain_provider_not_configured', 503);
        const activeRuntime = runtime ?? await loadRuntime(userId);
        const response = await fetchImpl('https://api.openai.com/v1/responses', {
          method: 'POST', signal: AbortSignal.timeout(140000),
          headers: {Authorization: `Bearer ${key}`, 'Content-Type': 'application/json'},
          body: JSON.stringify({model: BRAIN_MODEL, reasoning: {effort: BRAIN_EFFORT}, store: false,
            ...(onEvent ? {stream: true} : {}),
            max_output_tokens: 24000,
            instructions: `${activeRuntime.instructions}\n\nYou are Rici (Ree-see), the user's KORLIX Brain+Voice assistant. Give the complete useful answer in natural spoken language, usually a few sentences; be thorough when the user asks. Apply relevant saved preferences and instructions. The explicit voice command 'Rici remember this' is handled by the application and authorizes a direct save without a second password or approval. You cannot write records yourself. Do not claim any new save happened. If the user wants a save but has not used the command, tell them how to say it. Do not claim access to unavailable tools or live sources.`,
            input: [...s.history.slice(-16), {role: 'user', content: text}],
          }),
        });
        if (!response.ok) throw fail('GPT-6 Astra Max is unavailable right now. Please try again. Your model has not been changed.', 'brain_astra_unavailable', 503);
        const result = onEvent ? await readAnswerStream(response, (text, model) => {
          timing.firstTextMs ??= now() - started;
          // A disconnected listener must not cancel an authorized save or usage.
          try { onEvent({type: 'answer.delta', text, model, reasoningEffort: BRAIN_EFFORT}); } catch {}
        }) : await response.json();
        timing.providerDoneMs = now() - started;
        for (const [field, provider] of [['totalTokens','total_tokens'],['inputTokens','input_tokens'],['outputTokens','output_tokens']])
          s.reasonUsage[field] += count(result.usage?.[provider]);
        s.completedTurns += 1;
        await meter(s);
        const answer = (result.output || []).filter(x => x.type === 'message')
          .flatMap(x => x.content || []).filter(x => x.type === 'output_text').map(x => x.text).join('\n').trim();
        if (result.status !== 'completed' || !answer || !/^gpt-6-astra(?:-|$)/.test(result.model || ''))
          throw fail('Astra Max could not finish that answer. Please try again.', 'brain_incomplete_answer', 502);
        s.history.push({role: 'user', content: text}, {role: 'assistant', content: answer});
        return {ok: true, saved: false, answer, model: result.model, reasoningEffort: BRAIN_EFFORT};
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
  return {register, turn, mergeUsage};
}
