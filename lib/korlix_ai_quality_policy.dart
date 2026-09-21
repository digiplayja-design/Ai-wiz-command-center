const String kKorlixOpenAIPremiumModel = String.fromEnvironment(
  'KORLIX_OPENAI_PREMIUM_MODEL',
  defaultValue: 'gpt-6-astra',
);

const String kKorlixOpenAITextModel = String.fromEnvironment(
  'KORLIX_OPENAI_TEXT_MODEL',
  defaultValue: 'gpt-6-astra',
);

const String kKorlixOpenAIStreamingModel = String.fromEnvironment(
  'KORLIX_OPENAI_STREAMING_MODEL',
  defaultValue: 'gpt-6-astra',
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
Preferred text/reasoning model: $kKorlixOpenAIPremiumModel.
Preferred streaming fallback model: $kKorlixOpenAIStreamingModel.
Preferred image model: $kKorlixOpenAIImageModel.
Reasoning effort: $kKorlixOpenAIReasoningEffort where supported.
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

// KORLIX_POLICY_LEAK_STRIPPER_BEGIN
String korlixStripProductionQualityDirective(String input) {
  var clean = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

  if (clean.isEmpty) {
    return clean;
  }

  clean = clean.replaceAll(
    RegExp(
      r'KORLIX AI PRODUCTION QUALITY POLICY:[\s\S]*?\bUSER REQUEST:\s*',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(
    RegExp(
      r'''^\s*(KORLIX AI PRODUCTION QUALITY POLICY:?.*|Use the highest-quality.*|Preferred text/reasoning model:.*|Preferred streaming fallback model:.*|Preferred streaming fallback:.*|Preferred image model:.*|Reasoning effort:.*|Create production-ready.*|Never give shallow.*|For app creation,.*|For writing,.*|For documents,.*|For images,.*|For code,.*|USER REQUEST:\s*)\s*$''',
      caseSensitive: false,
      multiLine: true,
    ),
    '',
  );

  return clean
      .replaceAll(RegExp(r'\n[ \t]+\n'), '\n\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

// KORLIX_POLICY_LEAK_STRIPPER_END
