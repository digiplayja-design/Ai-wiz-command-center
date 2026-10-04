/// Written branding and speech instructions are separate. Keep user messages,
/// tool arguments and saved business records unchanged.
String riciSpeechText(String text) => text.replaceAll(
  RegExp(
    r'(?<![\p{L}\p{N}_])Rici(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
  'Ree-see',
);

const riciRealtimePronunciation =
    'When using the app assistant name, say only Ree-see, /ˈriː.siː/, as one '
    'natural name with two short syllables and the pure s sound in see. '
    'Use the same pronunciation in greetings, later replies and app-result '
    'readbacks, in every language and accent. Do not repeat older pronunciations '
    'from conversation history. Do not announce the pronunciation, stretch the '
    'vowels, give two versions or spell the name unless the user explicitly asks. '
    'If asked to spell it, say the letters R, I, C, I one at a time. This '
    'pronunciation rule does not change tools, permissions or confirmation requirements.';

String riciRealtimeInstructions(String instructions) =>
    '${riciSpeechText(instructions)}\n\n$riciRealtimePronunciation';

/// Only assistant captions use the display spelling; user transcripts stay exact.
String riciDisplayText(String text) => text.replaceAll(
  RegExp(r'\b(?:ree[- ]see|risi)\b', caseSensitive: false),
  'Rici',
);
