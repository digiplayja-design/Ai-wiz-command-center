'use strict';
const C = require('../k135z_copilot_notes/contract.cjs');
const {K135zZoomError} = require('./b5b_contract.cjs');
const fail = (status, code) => { throw new K135zZoomError(status, `K135Z_RESPONSE_${code}`); };
const voices = new Set(['alloy','ash','ballad','coral','echo','sage','shimmer','verse','marin','cedar']);
const phrases = Object.freeze([
  "I'm on it. Give me a moment to think that through.",
  "I'm still working through that. Thanks for bearing with me.",
]);
function validateWaitingVoiceRequest(body) {
  C.object(body, ['context','enabled']); C.context(body.context);
  C.requireValue(body.enabled === true);
}

// Only these public, fixed phrases are cached. Never cache a question, answer,
// agent runtime or meeting audio. Playback remains a browser session choice.
function createWaitingVoice({env, provider, now}) {
  let cache, pending = false, window = now(), attempts = 0;
  const users = new Map();
  return {async run({body, principal, verify, signal}) {
    const configured = String(env.KORLIX_LIVE_CONVO_VOICE || '').trim().toLowerCase();
    const voice = voices.has(configured) ? configured : 'marin';
    if (!cache || cache.voice !== voice || cache.until <= now()) {
      if (now() - window >= 3600000) { window = now(); attempts = 0; users.clear(); }
      if (pending || attempts >= 20 || (users.get(principal.userId) || 0) >= 3) fail(429, 'LIMIT');
      pending = true; attempts++;
      users.set(principal.userId, (users.get(principal.userId) || 0) + 1);
      try {
        const clips = [];
        for (const text of phrases) {
          await verify();
          const audio = await provider('audio/speech', {model:'gpt-4o-mini-tts', voice,
            input:text, response_format:'mp3',
            instructions:'Say exactly these words, warmly and briefly. Do not add words or sound effects.'},
          signal, 120000, true);
          if (audio.length < 64 || !(audio.subarray(0,3).toString() === 'ID3' ||
              (audio[0] === 255 && (audio[1]&224) === 224))) fail(502, 'INVALID_AUDIO');
          clips.push({text, mimeType:'audio/mpeg', audio:audio.toString('base64')});
        }
        await verify();
        cache = {voice, until:now()+3600000, clips};
      } finally { pending = false; }
    }
    // Recheck permission even on a cache hit and never return the old context.
    await verify();
    return {waitingVoice:{context:body.context, clips:cache.clips}};
  }};
}
module.exports = {createWaitingVoice, validateWaitingVoiceRequest};
