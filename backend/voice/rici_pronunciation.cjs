'use strict';

// Speech-only spelling. UI labels and saved transcripts keep the name Rici.
const RICI_PRONUNCIATION = 'Say Ree-see as two syllables, REE + SEE, /ˈriː.siː/. The second syllable starts with the pure s sound in see. Keep the same pronunciation in every language.';
function riciSpeechText(text) {
  return text.replace(/(?<![\p{L}\p{N}_])Rici(?![\p{L}\p{N}_])/giu, 'Ree-see');
}

module.exports = {riciSpeechText, RICI_PRONUNCIATION};
