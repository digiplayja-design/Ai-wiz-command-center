import test from 'node:test';
import assert from 'node:assert/strict';
import {brainSpeechConfig, rememberCommand} from '../brain_voice/core.mjs';

test('both Brain speech modes use the shared soft-s pronunciation without changing tool authorization',()=>{
  for(const live of [true,false]) {
    const base={audio:{input:{},output:{voice:'marin'}}};
    const session=brainSpeechConfig(base,{live},JSON.stringify({training:'Rici is useful'}));
    assert.match(session.instructions,/say only Ree-see/);
    assert.match(session.instructions,/pure s sound in see/);
    assert(!session.instructions.includes('Rici'));
    assert.equal(session.audio.output.voice,'marin');
    assert.equal(session.audio.input.turn_detection.create_response,live);
    assert.equal(session.tools.length,live?1:0);
    if(live)assert.equal(session.tools[0].name,'remember_in_brain');
    assert.deepEqual(base,{audio:{input:{},output:{voice:'marin'}}});
  }
});

test('Risi transcription authorizes only the same explicit memory command',()=>{
  assert.deepEqual(rememberCommand('Risi, remember this: Purple is my favorite.'),
    {content:'Purple is my favorite.',instruction:false});
  for(const text of ['What does Risi remember this mean?', '“Risi remember this: x”', 'Risi, do not remember this: x'])
    assert.equal(rememberCommand(text),null);
});
