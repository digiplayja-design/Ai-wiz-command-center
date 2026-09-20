'use strict';

// Public, fixed greeting only. No request text, agent context, or meeting data.
// One cached clip per process; at most three provider attempts until restart.
const PHRASE = "Hello, I'm Nova, Korlix's AI meeting assistant. This is my voice preview. The host chooses when I speak. Thank you for helping test the meeting audio.";
const VOICES = new Set(['alloy','ash','ballad','coral','echo','sage','shimmer','verse','marin','cedar']);
const MAX_BYTES = 1024 * 1024;
const PATH = '/k135z/audio-output-test/voice/prepare';
function failure(code) { return Object.assign(Error(code), {code}); }
function createVoicePreview({env = process.env, fetchImpl = globalThis.fetch,
  now = Date.now, timeoutMs = 20000} = {}) {
  let cached, pending, attempts = 0, retryAt = 0;
  async function generate() {
    if (cached) return cached;
    if (pending) return pending;
    if (!env.OPENAI_API_KEY) throw failure('VOICE_NOT_CONFIGURED');
    if (attempts >= 3) throw failure('VOICE_LIMIT_REACHED');
    if (now() < retryAt) throw failure('VOICE_RETRY_LATER');
    attempts++; retryAt = now() + 60000;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    pending = (async () => {
      try {
        const configured = String(env.KORLIX_LIVE_CONVO_VOICE || '').trim().toLowerCase();
        const response = await fetchImpl('https://api.openai.com/v1/audio/speech', {
          method:'POST', signal:controller.signal,
          headers:{Authorization:`Bearer ${env.OPENAI_API_KEY}`, 'Content-Type':'application/json'},
          body:JSON.stringify({model:'gpt-4o-mini-tts', voice:VOICES.has(configured) ? configured : 'marin',
            input:PHRASE, response_format:'mp3',
            instructions:'Speak warmly and clearly at a natural pace. Read only the supplied greeting.'}),
        });
        if (!response.ok || !/^audio\//i.test(response.headers.get('content-type') || '')) {
          await response.body?.cancel(); throw Error('PROVIDER');
        }
        const chunks = []; let size = 0;
        for await (const chunk of response.body) {
          size += chunk.length;
          if (size > MAX_BYTES) { controller.abort(); throw Error('SIZE'); }
          chunks.push(Buffer.from(chunk));
        }
        const bytes = Buffer.concat(chunks);
        const mp3 = bytes.subarray(0,3).toString() === 'ID3' ||
          (bytes[0] === 255 && (bytes[1] & 224) === 224);
        if (controller.signal.aborted || bytes.length < 64 || !mp3) throw Error('AUDIO');
        cached = bytes; return cached;
      } catch (_) { throw failure('VOICE_PROVIDER_FAILED'); }
      finally { clearTimeout(timer); }
    })();
    try { return await pending; } finally { pending = null; }
  }
  return generate;
}
function registerVoicePreview(app, options) {
  const generate = createVoicePreview(options);
  app.post(PATH, async (req, res) => {
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
        Object.keys(req.body).length || Object.keys(req.query || {}).length) {
      return res.status(400).json({code:'FIXED_GREETING_ONLY'});
    }
    try {
      const bytes = await generate();
      res.setHeader('Content-Type','audio/mpeg');
      res.setHeader('Content-Length',String(bytes.length));
      return res.status(200).end(bytes);
    } catch (error) {
      res.setHeader('Retry-After','60');
      return res.status(503).json({code:error.code || 'VOICE_PROVIDER_FAILED'});
    }
  });
}
module.exports = {createVoicePreview, registerVoicePreview, PHRASE, PATH};
