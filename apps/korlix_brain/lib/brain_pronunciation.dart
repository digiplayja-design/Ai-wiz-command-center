/// The written brand stays Rici; speech gets an unambiguous soft-s name.
const brainPronunciation =
    'Say only Ree-see, /ˈriː.siː/, as one natural name with two short syllables '
    'and the pure s sound in see. Keep this pronunciation in every language. '
    'Do not announce the pronunciation or spell the name unless asked.';

String brainSpeechText(String text) => text.replaceAll(
  RegExp(
    r'(?<![\p{L}\p{N}_])Rici(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
  'Ree-see',
);

String brainDisplaySpeech(String text) => text.replaceAll(
  RegExp(
    r'(?<![\p{L}\p{N}_])Ree[ -]see(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
  'Rici',
);
