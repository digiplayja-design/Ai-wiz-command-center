const test = require('node:test');
const assert = require('node:assert/strict');
const {riciSpeechText} = require('../voice/rici_pronunciation.cjs');

test('speech uses a soft s phonetic name without rewriting other words or saved copy', () => {
  const display = 'Rici, meet RICI. Rici’s voice. Ricin, Patricia, Ricié and user_Rici stay intact.';
  assert.equal(riciSpeechText(display), 'Ree-see, meet Ree-see. Ree-see’s voice. Ricin, Patricia, Ricié and user_Rici stay intact.');
  assert(display.startsWith('Rici,'));
  assert.equal(riciSpeechText('Read the exact approved amount: $15.00.'), 'Read the exact approved amount: $15.00.');
});

test('each feature voice identifies the spoken name with the s sound in see', async () => {
  const bookkeeping = await import('../bookkeeping/voice.mjs');
  const crm = await import('../contacts_crm/voice.mjs');
  const fieldproof = await import('../fieldproof/voice.mjs');
  const music = await import('../music/voice.mjs');
  const workforce = await import('../workforce/voice.mjs');
  const prompts = [
    bookkeeping.bookkeepingVoiceInstructions({business: {}, month: '2026-10'}),
    crm.crmVoiceInstructions(), fieldproof.fieldProofVoiceInstructions(),
    music.musicVoiceInstructions(), workforce.workforceVoiceInstructions(),
  ];
  for (const prompt of prompts) {
    assert.match(prompt, /REE \+ SEE, with the s sound in see/);
    assert.match(prompt, /written Rici/);
  }
});
