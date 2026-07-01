'use strict';

const KORLIX_OPENAI_QUALITY = Object.freeze({
  premiumTextModel:
    process.env.KORLIX_OPENAI_PREMIUM_MODEL ||
    process.env.KORLIX_OPENAI_TEXT_MODEL ||
    process.env.OPENAI_MODEL ||
    'gpt-5.5-pro',

  textModel:
    process.env.KORLIX_OPENAI_TEXT_MODEL ||
    process.env.KORLIX_OPENAI_PREMIUM_MODEL ||
    process.env.OPENAI_MODEL ||
    'gpt-5.5-pro',

  streamingModel:
    process.env.KORLIX_OPENAI_STREAMING_MODEL ||
    process.env.KORLIX_OPENAI_TEXT_MODEL ||
    'gpt-5.5',

  imageModel:
    process.env.KORLIX_OPENAI_IMAGE_MODEL ||
    'gpt-image-2',

  audioModel:
    process.env.KORLIX_OPENAI_AUDIO_MODEL ||
    'gpt-audio-1.5',

  transcriptionModel:
    process.env.KORLIX_OPENAI_TRANSCRIPTION_MODEL ||
    'gpt-realtime-whisper',

  embeddingModel:
    process.env.KORLIX_OPENAI_EMBEDDING_MODEL ||
    'text-embedding-3-large',

  moderationModel:
    process.env.KORLIX_OPENAI_MODERATION_MODEL ||
    'omni-moderation',

  reasoningEffort:
    process.env.KORLIX_OPENAI_REASONING_EFFORT ||
    'xhigh',
});

const KORLIX_QUALITY_INSTRUCTION = `
KORLIX AI PRODUCTION QUALITY POLICY:
Use the highest-quality available OpenAI model path for this feature.
Preferred text/reasoning model: ${KORLIX_OPENAI_QUALITY.premiumTextModel}.
Preferred streaming fallback model: ${KORLIX_OPENAI_QUALITY.streamingModel}.
Preferred image model: ${KORLIX_OPENAI_QUALITY.imageModel}.
Reasoning effort: ${KORLIX_OPENAI_QUALITY.reasoningEffort} where supported.
Create production-ready, premium, precise, complete, polished output.
Never give shallow, placeholder, generic, unfinished, or low-quality output.
For app creation, generate complete product-grade architecture, UI, flows, copy, testing notes, deployment notes, and edge-case handling.
For writing, create professional final-quality copy.
For documents, extract details carefully and provide structured, useful analysis.
For images, preserve requested identity/style constraints and visibly apply the selected style.
For code, provide robust, maintainable, tested production-quality output.
`.trim();

function korlixResolveOpenAIModel(options = {}) {
  const task = String(options.task || options.feature || 'text').toLowerCase();
  const requested = options.requested || options.model;

  if (
    process.env.KORLIX_ALLOW_MODEL_DOWNGRADE === 'true' &&
    typeof requested === 'string' &&
    requested.trim()
  ) {
    return requested.trim();
  }

  if (task.includes('image')) return KORLIX_OPENAI_QUALITY.imageModel;
  if (task.includes('audio') || task.includes('speech')) return KORLIX_OPENAI_QUALITY.audioModel;
  if (task.includes('transcrib') || task.includes('whisper')) return KORLIX_OPENAI_QUALITY.transcriptionModel;
  if (task.includes('embed')) return KORLIX_OPENAI_QUALITY.embeddingModel;
  if (task.includes('moderation') || task.includes('safety')) return KORLIX_OPENAI_QUALITY.moderationModel;
  if (task.includes('stream')) return KORLIX_OPENAI_QUALITY.streamingModel;

  return KORLIX_OPENAI_QUALITY.premiumTextModel;
}

function korlixApplyQualityInstruction(input) {
  if (!input) return input;

  if (Array.isArray(input)) {
    return [
      { role: 'system', content: KORLIX_QUALITY_INSTRUCTION },
      ...input,
    ];
  }

  if (typeof input === 'string') {
    if (input.includes('KORLIX AI PRODUCTION QUALITY POLICY:')) {
      return input;
    }

    return `${KORLIX_QUALITY_INSTRUCTION}\n\nUSER REQUEST:\n${input}`;
  }

  return input;
}

function korlixEnhanceOpenAIPayload(payload = {}, options = {}) {
  const task = options.task || options.feature || payload.task || 'text';
  const enhanced = { ...payload };

  enhanced.model = korlixResolveOpenAIModel({
    task,
    requested: payload.model,
  });

  if (enhanced.input) {
    enhanced.input = korlixApplyQualityInstruction(enhanced.input);
  } else if (enhanced.messages) {
    enhanced.messages = korlixApplyQualityInstruction(enhanced.messages);
  } else if (enhanced.prompt) {
    enhanced.prompt = korlixApplyQualityInstruction(enhanced.prompt);
  }

  if (
    enhanced.model === KORLIX_OPENAI_QUALITY.premiumTextModel ||
    enhanced.model === KORLIX_OPENAI_QUALITY.textModel
  ) {
    enhanced.reasoning = {
      ...(enhanced.reasoning || {}),
      effort:
        enhanced.reasoning?.effort ||
        process.env.KORLIX_OPENAI_REASONING_EFFORT ||
        KORLIX_OPENAI_QUALITY.reasoningEffort,
    };
  }

  return enhanced;
}

function korlixQualityHeaders() {
  return {
    'X-Korlix-AI-Quality': 'highest-production',
    'X-Korlix-OpenAI-Preferred-Model': KORLIX_OPENAI_QUALITY.premiumTextModel,
    'X-Korlix-OpenAI-Text-Model': KORLIX_OPENAI_QUALITY.textModel,
    'X-Korlix-OpenAI-Streaming-Model': KORLIX_OPENAI_QUALITY.streamingModel,
    'X-Korlix-OpenAI-Image-Model': KORLIX_OPENAI_QUALITY.imageModel,
    'X-Korlix-OpenAI-Reasoning-Effort': KORLIX_OPENAI_QUALITY.reasoningEffort,
  };
}

module.exports = {
  KORLIX_OPENAI_QUALITY,
  KORLIX_QUALITY_INSTRUCTION,
  korlixResolveOpenAIModel,
  korlixApplyQualityInstruction,
  korlixEnhanceOpenAIPayload,
  korlixQualityHeaders,
};
