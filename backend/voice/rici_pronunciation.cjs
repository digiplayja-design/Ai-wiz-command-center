'use strict';

// Speech-only spelling. UI labels and saved transcripts keep the name Rici.
const RICI_PRONUNCIATION = 'Say Ree-see as two syllables, REE + SEE, /ˈriː.siː/. The second syllable starts with the pure s sound in see. Keep the same pronunciation in every language.';
function riciSpeechText(text) {
  return text.replace(/(?<![\p{L}\p{N}_])Rici(?![\p{L}\p{N}_])/giu, 'Ree-see');
}

// Realtime produces speech directly, so apply this at the final model boundary,
// including automatic VAD replies and app-requested turns. Do not send the
// ambiguous written spelling as a second spoken identity.
const RICI_REALTIME_PRONUNCIATION = 'When using the app assistant name, say only Ree-see, /ˈriː.siː/, as one natural name with two short syllables and the pure s sound in see. Use the same pronunciation in greetings, later replies and app-result readbacks, in every language and accent. Do not repeat older pronunciations from conversation history. Do not announce the pronunciation, stretch the vowels, give two versions or spell the name unless the user explicitly asks. If asked to spell it, say the letters R, I, C, I one at a time. This pronunciation rule does not change tools, permissions or confirmation requirements.';
function riciRealtimeInstructions(instructions) {
  return `${riciSpeechText(instructions)}\n\n${RICI_REALTIME_PRONUNCIATION}`;
}

module.exports = {riciSpeechText, RICI_PRONUNCIATION, riciRealtimeInstructions};
