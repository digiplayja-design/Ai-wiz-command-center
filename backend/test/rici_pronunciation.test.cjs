const test = require('node:test');
const assert = require('node:assert/strict');
const {riciSpeechText, riciRealtimeInstructions} = require('../voice/rici_pronunciation.cjs');

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
    const instructions=riciRealtimeInstructions(prompt);
    assert.match(instructions, /pure s sound in see/);
    assert(!instructions.includes('Rici'));
    assert(!instructions.includes('written Ree-see'));
  }
});

test('the exact production realtime config covers normal voice and every isolated workspace', async () => {
 const {readFile}=require('node:fs/promises');
 const source=await readFile(new URL('../server.js','file://'+__filename),'utf8');
 const start=source.indexOf('function korlixLiveConvoSessionConfigV1(req) {');
 const end=source.indexOf('// KORLIX_LIVE_CONVO_BUILD129_LIMITS_BEGIN',start);
 const make=new Function('riciRealtimeInstructions','workforceVoiceInstructions','crmVoiceInstructions','fieldProofVoiceInstructions','bookkeepingVoiceInstructions','musicVoiceInstructions','korlixLiveConvoAgentInstructionsV1','korlixLiveConvoEnvStringV1','korlixLiveConvoModelV1','korlixLiveConvoAccentInstructionV1','korlixLiveConvoReasoningEffortV1','korlixLiveConvoVoiceV1',source.slice(start,end)+'; return korlixLiveConvoSessionConfigV1;');
 const prompt=()=> 'Agent Rici. Preserve the selected workspace and ask before saving.';
 const config=make(riciRealtimeInstructions,prompt,prompt,prompt,prompt,prompt,prompt,(_k,f)=>f,()=> 'test-model',()=> 'Selected accent',()=> 'low',()=> 'marin');
 for(const mode of ['normal','korlixWorkforceVoice','korlixCrmVoice','korlixFieldProofVoice','korlixBookkeepingVoice','korlixMusicVoice','inventory','scheduling']) {
  const req={headers:{},query:{},[mode]:true};
  if(mode==='inventory'||mode==='scheduling')req.query[mode]='1';
  const session=config(req);
  assert(!session.instructions.includes('Rici'), mode+' must not send the ambiguous spelling to speech');
  assert.match(session.instructions,/say only Ree-see/);
  assert.match(session.instructions,/Do not announce the pronunciation/);
  assert.equal(session.audio.input.turn_detection.create_response,true);
  assert.equal(session.audio.input.turn_detection.interrupt_response,true);
 }
});
