const String kKorlixOpenAIPremiumModel = String.fromEnvironment(
  'KORLIX_OPENAI_PREMIUM_MODEL',
  defaultValue: 'gpt-5.5-pro',
);

const String kKorlixOpenAITextModel = String.fromEnvironment(
  'KORLIX_OPENAI_TEXT_MODEL',
  defaultValue: 'gpt-5.5-pro',
);

const String kKorlixOpenAIStreamingModel = String.fromEnvironment(
  'KORLIX_OPENAI_STREAMING_MODEL',
  defaultValue: 'gpt-5.5',
);

const String kKorlixOpenAIImageModel = String.fromEnvironment(
  'KORLIX_OPENAI_IMAGE_MODEL',
  defaultValue: 'gpt-image-2',
);

const String kKorlixOpenAIReasoningEffort = String.fromEnvironment(
  'KORLIX_OPENAI_REASONING_EFFORT',
  defaultValue: 'xhigh',
);

const String kKorlixProductionQualityDirective = '''
KORLIX AI PRODUCTION QUALITY POLICY:
Use the highest-quality available OpenAI model path for this feature.
Preferred text/reasoning model: gpt-5.5-pro.
Preferred streaming fallback model: gpt-5.5.
Preferred image model: gpt-image-2.
Reasoning effort: xhigh where supported.
Create production-ready, premium, precise, complete, polished output.
Never give shallow, placeholder, generic, unfinished, or low-quality output.
For app creation, generate complete product-grade architecture, UI, flows, copy, testing notes, deployment notes, and edge-case handling.
For writing, create professional final-quality copy.
For documents, extract details carefully and provide structured, useful analysis.
For images, preserve the user's requested identity/style constraints and produce the selected style clearly.
For code, provide robust, maintainable, tested production-quality output.
''';

Map<String, String> korlixOpenAIQualityHeaders() {
  return <String, String>{
    'X-Korlix-AI-Quality': 'highest-production',
    'X-Korlix-OpenAI-Preferred-Model': kKorlixOpenAIPremiumModel,
    'X-Korlix-OpenAI-Text-Model': kKorlixOpenAITextModel,
    'X-Korlix-OpenAI-Streaming-Model': kKorlixOpenAIStreamingModel,
    'X-Korlix-OpenAI-Image-Model': kKorlixOpenAIImageModel,
    'X-Korlix-OpenAI-Reasoning-Effort': kKorlixOpenAIReasoningEffort,
  };
}

String korlixApplyProductionQualityDirective(String prompt) {
  final trimmed = prompt.trim();

  if (trimmed.isEmpty) {
    return trimmed;
  }

  if (trimmed.contains('KORLIX AI PRODUCTION QUALITY POLICY:')) {
    return trimmed;
  }

  return '$kKorlixProductionQualityDirective\n\nUSER REQUEST:\n$trimmed';
}
