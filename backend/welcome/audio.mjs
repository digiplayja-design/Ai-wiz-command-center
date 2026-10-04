// One public, fixed welcome clip. No user text, identity, microphone or AI GAS.
export const WELCOME_TEXT = "Welcome to KORLIX! I'm K-Nova, your AI voice companion. You'll find me in CRM, Workforce, Inventory, Bookkeeping, Music Studio, and more. Look for K-Nova or the voice button, tap to start, and tell me what you need. I can guide you, help you find things, and make everyday tasks easier. Let's explore!";
const RATE = 24000, MAX_PCM = RATE * 2 * 40;

function wav(pcm) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVEfmt ', 8); header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(RATE, 24); header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

export function createWelcomeAudio({speak, now = Date.now, timeoutMs = 45000} = {}) {
  let cached = null, pending = null, retryAt = 0;
  async function generate() {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), timeoutMs); timer.unref?.();
    let reader;
    try {
      const response = await speak({
        model: 'gpt-4o-mini-tts', voice: 'marin', input: WELCOME_TEXT,
        response_format: 'pcm', speed: 1.06,
        instructions: 'Speak as K-Nova, a warm, confident and welcoming female AI companion. Be bright and conversational, with natural pauses. Pronounce KORLIX as KOR-liks and K-Nova as Kay Nova. Read only the supplied welcome, with no extra words or sound effects.',
      }, {signal: abort.signal, timeout: timeoutMs, maxRetries: 0});
      if (response?.ok === false || !response?.body?.getReader || /json|text|html/i.test(response.headers?.get('content-type') || '')) throw new Error('Invalid welcome audio');
      reader = response.body.getReader();
      const parts = []; let length = 0;
      while (true) {
        const {done, value} = await reader.read(); if (done) break;
        if (!(value instanceof Uint8Array) || (length += value.length) > MAX_PCM) throw new Error('Welcome audio too large');
        parts.push(Buffer.from(value));
      }
      if (length < RATE * 2 || length % 2) throw new Error('Invalid welcome duration');
      cached = wav(Buffer.concat(parts));
      return cached;
    } catch {
      retryAt = now() + 300000;
      throw new Error('Welcome audio is temporarily unavailable');
    } finally {
      clearTimeout(timer); abort.abort();
      try { await reader?.cancel(); } catch {}
    }
  }
  return {
    get() {
      if (cached) return Promise.resolve(cached);
      if (pending) return pending;
      if (now() < retryAt) return Promise.reject(new Error('Welcome audio is temporarily unavailable'));
      pending = generate().finally(() => { pending = null; });
      return pending;
    },
    status() { return {version: 1, ready: !!cached, voice: 'marin', metered: false}; },
  };
}

export function registerWelcomeAudio(app, options) {
  const audio = createWelcomeAudio(options);
  app.get('/api/welcome/knova-v1.wav', async (_req, res) => {
    try {
      const bytes = await audio.get();
      res.set({'Content-Type': 'audio/wav', 'Cache-Control': 'public, max-age=86400', 'X-Content-Type-Options': 'nosniff'}).send(bytes);
    } catch {
      res.set({'Cache-Control': 'no-store', 'Retry-After': '300'}).status(503).json({error: 'Welcome audio is temporarily unavailable. You can keep using KORLIX.'});
    }
  });
  // Warm before sign-in so the first greeting does not wait for generation.
  void audio.get().catch(() => console.warn('[K-Nova welcome] Audio warming is temporarily unavailable.'));
  return audio;
}
