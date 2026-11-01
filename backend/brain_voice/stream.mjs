import {BRAIN_MODEL, matchesBrainModel} from './models.mjs';

// Decode the provider's SSE incrementally; never expose reasoning events.
export async function readAnswerStream(response, onDelta, expectedModel = BRAIN_MODEL) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '', model = '', result;
  try {
    while (true) {
      const {value, done} = await reader.read();
      buffer += decoder.decode(value, {stream: !done});
      if (buffer.length > 2000000) throw Error('Provider event too large');
      let boundary;
      while ((boundary = /\r?\n\r?\n/.exec(buffer))) {
        const block = buffer.slice(0, boundary.index);
        buffer = buffer.slice(boundary.index + boundary[0].length);
        const data = block.split(/\r?\n/).filter(x => x.startsWith('data:'))
          .map(x => x.slice(5).trimStart()).join('\n');
        if (!data || data === '[DONE]') continue;
        const event = JSON.parse(data);
        if (event.response?.model) model = event.response.model;
        if (event.type === 'response.output_text.delta') {
          if (!matchesBrainModel(model, expectedModel)) throw Error('Unverified model');
          if (typeof event.delta === 'string') onDelta(event.delta, model);
        } else if (['response.completed', 'response.incomplete', 'response.failed'].includes(event.type)) {
          result = event.response;
        } else if (event.type === 'error') {
          throw Error('Provider stream error');
        }
      }
      if (done) break;
    }
    if (!result) throw Error('Provider stream ended without completion');
    return result;
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

// Authentication is performed by the existing route wrapper, before headers.
export async function streamBrainTurn({res, run}) {
  res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, no-transform');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();
  const send = event => {
    if (!res.destroyed && !res.writableEnded) res.write(`${JSON.stringify(event)}\n`);
  };
  const heartbeat = setInterval(() => send({type: 'turn.waiting'}), 10000);
  try {
    const result = await run(send);
    send({type: 'turn.completed', ...result});
  } catch (error) {
    send({type: 'turn.error', code: error.code || 'brain_turn_failed',
      error: error.statusCode ? error.message : 'Rici could not finish that turn. Please try again.'});
  } finally {
    clearInterval(heartbeat);
    if (!res.destroyed && !res.writableEnded) res.end();
  }
}
