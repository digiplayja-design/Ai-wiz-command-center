'use strict';

// Main text chat and picture creation only. Nova's live voice keeps its own
// latency-sensitive reasoning configuration.
const CHAT_MODEL = 'gpt-6-astra';
const CHAT_EFFORT = 'xhigh';
const IMAGE_MODEL = 'gpt-image-2.5-sunburst';
const IMAGE_SIZES = new Set(['auto', '1024x1024', '1536x1024', '1024x1536']);
const IMAGE_STYLES = Object.freeze({
  auto: '',
  photo: 'Use convincing photographic lighting, natural textures, and realistic proportions.',
  illustration: 'Create a cohesive, deliberate illustration with clean forms and an intentional palette.',
  design: 'Create a polished graphic design with a clear visual hierarchy, balanced spacing, and legible typography.',
  cinematic: 'Use cinematic composition, purposeful lighting, rich tonal depth, and coherent detail.',
  '3d': 'Create polished three-dimensional artwork with sculpted forms, physically coherent materials, dimensional lighting, and intentional reflections.',
  watercolor: 'Create expressive watercolor artwork with translucent pigment, subtle paper texture, organic edges, and controlled washes.',
  sketch: 'Create a deliberate pencil drawing with expressive line work, layered graphite shading, and a coherent hand-drawn finish.',
  minimal: 'Create restrained minimalist artwork with deliberate negative space, simple forms, a focused palette, and a strong focal point.',
});

function invalid(message) {
  return Object.assign(new Error(message), {statusCode: 400});
}

function chatHistory(value) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 16) throw invalid('Chat history must contain at most 16 messages.');
  let length = 0;
  return value.map(message => {
    if (!message || !['user', 'assistant'].includes(message.role) ||
        typeof message.content !== 'string' || message.content.length > 12000) {
      throw invalid('Invalid chat history.');
    }
    length += message.content.length;
    if (length > 96000) throw invalid('Chat history is too long.');
    return {role: message.role, content: message.content};
  });
}

function imageSettings(body = {}, env = process.env) {
  const size = body.imageSize ?? '1024x1024';
  const style = body.imageStyle ?? 'auto';
  if (!IMAGE_SIZES.has(size)) throw invalid('Choose square, portrait, landscape, or automatic image size.');
  if (!Object.hasOwn(IMAGE_STYLES, style)) throw invalid('Choose a supported image style.');
  const model = String(env.KORLIX_CHAT_IMAGE_MODEL || IMAGE_MODEL).trim();
  // A dedicated rollback setting never inherits a legacy global image model.
  if (!/^gpt-image-(?:1(?:\.5|-mini)?|2(?:\.5-(?:sunburst|flare))?)(?:-\d{4}-\d{2}-\d{2})?$/.test(model)) {
    throw Object.assign(new Error('Picture generation model is not configured correctly.'), {statusCode: 503});
  }
  return {model, size, style, quality: model.startsWith('gpt-image-2.5-') ? 'xhigh' : 'high', output_format: 'png'};
}

function imagePrompt(prompt, style = 'auto') {
  return [
    'Create the image requested below. Follow the requested subject, composition, style, and exact written text.',
    'Make deliberate composition, lighting, color, and detail choices. Avoid accidental artifacts and added watermarks.',
    'For requested text, preserve spelling and punctuation and use readable typography. Do not invent extra copy.',
    'Respect the requested artistic style; do not impose photorealism on an illustration or graphic.',
    IMAGE_STYLES[style] || '',
    '\nUser description:\n' + prompt,
  ].filter(Boolean).join('\n');
}

async function probeModelAccess({apiKey, imageModel = IMAGE_MODEL, fetchImpl = fetch}) {
  if (!apiKey) return {chat: 'not_configured', images: 'not_configured'};
  const entries = await Promise.all([['chat', CHAT_MODEL], ['images', imageModel]].map(async ([key, model]) => {
    try {
      const response = await fetchImpl('https://api.openai.com/v1/models/' + encodeURIComponent(model), {
        headers: {Authorization: `Bearer ${apiKey}`}, signal: AbortSignal.timeout(10000),
      });
      // Model visibility is a preflight, not proof of a successful generation.
      await response.body?.cancel();
      return [key, response.ok ? 'visible' : [401, 403, 404].includes(response.status) ? 'unavailable' : 'unknown'];
    } catch (_) {return [key, 'unknown'];}
  }));
  return Object.fromEntries(entries);
}

module.exports = {CHAT_MODEL, CHAT_EFFORT, IMAGE_MODEL, chatHistory, imageSettings, imagePrompt, probeModelAccess};
