import test from 'node:test';
import assert from 'node:assert/strict';
import {brainSpeechConfig, createBrainVoice, brainProfile} from '../brain_voice/core.mjs';
import {brainRuntimeContext} from '../brain_voice/context.mjs';

const limits = {maxSessionSeconds:600,maxResponses:10};
function setup(extra={}) {
  const saves=[], timings=[], requests=[];
  const v=createBrainVoice({apiKey:()=>{throw Error('No text provider in Live');},
    loadRuntime:async()=>{throw Error('Normal Live replies must not load context per turn');},
    saveMemory:async x=>{saves.push(x);return {id:'m1',...x.body};},
    reportUsage:async()=>({allowed:true}),onTiming:x=>timings.push(x),
    fetchImpl:async()=>{requests.push(1);throw Error('No Sol call');},...extra});
  v.register({userId:'owner',sessionId:'live',protocol:'rici-live-v1',limits});
  return {v,saves,timings,requests,turn:(text,id='one')=>v.turn({userId:'owner',sessionId:'live',turnId:id,transcript:text})};
}

test('Live enables native audio replies with low effort and a single constrained memory tool',()=>{
  const data=brainRuntimeContext({profile:{active:true,memoryEnabled:true,trainingInstructions:'Your name is Kim. Use metric units.'},memories:[]}).context;
  const c=brainSpeechConfig({audio:{input:{},output:{voice:'marin'}}},brainProfile({headers:{'x-korlix-brain-voice':'rici-live-v1'}}),data);
  assert.equal(c.model,'gpt-realtime-2.1'); assert.deepEqual(c.reasoning,{effort:'low'});
  assert.equal(c.audio.input.turn_detection.create_response,true);
  assert.equal(c.audio.input.turn_detection.interrupt_response,true);assert.equal(c.audio.output.voice,'marin');
  assert.equal(c.tools.length,1);assert.equal(c.tools[0].name,'remember_in_brain');
  assert.deepEqual(c.tools[0].parameters.properties,{});assert.equal(c.tools[0].parameters.additionalProperties,false);
  assert.match(c.instructions,/spoken name is always Ree-see/);assert.match(c.instructions,/Account data JSON:/);
  assert.match(c.instructions,/Do not claim a save until the tool confirms saved:true/);
});

test('Live tool cannot turn normal, quoted or negated conversation into a save or Sol call',async()=>{
  const c=setup();
  for (const [i,text] of ['Hello there','“Rici remember this: x”','Do not remember this','What does Rici remember this mean?'].entries()) {
    const r=await c.turn(text,'t'+i);assert.equal(r.saved,false);assert.equal(r.handled,false);
  }
  assert.equal(c.requests.length,0);assert.equal(c.saves.length,0);
});

test('Live memory uses original authorized words, idempotency, next-turn capture and cancellation',async()=>{
  const c=setup();
  const one=await c.turn('Rici, remember this instruction: Always use metric.');
  assert.equal(one.saved,true);assert.equal(c.saves[0].body.content,'Always use metric.');
  await c.turn('Rici, remember this instruction: Always use metric.');assert.equal(c.saves.length,1);
  assert.equal((await c.turn('Rici remember this','two')).awaitingMemory,true);
  await c.turn('My dog is Joy.','three');assert.equal(c.saves[1].body.content,'My dog is Joy.');
  await c.turn('Rici remember this','four');await c.turn('Never mind','five');assert.equal(c.saves.length,2);
  assert.equal(c.requests.length,0);
});

test('Live preserves ownership, allowance and durable acknowledgement before save success',async()=>{
  const c=setup();await assert.rejects(c.v.turn({userId:'other',sessionId:'live',turnId:'one',transcript:'Rici remember this: x'}),{code:'brain_session_ended'});
  const limited=setup({reportUsage:async()=>({allowed:false})});await assert.rejects(limited.turn('Rici remember this: x'),{code:'brain_allowance'});
  assert.equal(limited.saves.length,0);
  const broken=setup({saveMemory:async()=>({})});await assert.rejects(broken.turn('Rici remember this: x'),{code:'brain_save_unverified'});
});

test('Audio timing is account bound, bounded, deduplicated and excludes user content',()=>{
  const c=setup();const t={userId:'owner',sessionId:'live',turnId:'one',firstAudioMs:420,transcript:'must not log'};
  c.v.reportAudioTiming(t);c.v.reportAudioTiming(t);
  assert.equal(c.timings.length,1);assert.deepEqual(c.timings[0],{route:'realtime',model:'gpt-realtime-2.1',reasoningEffort:'low',firstAudioMs:420,clientReported:true});
  assert.throws(()=>c.v.reportAudioTiming({...t,userId:'other'}),{code:'brain_session_ended'});
  assert.throws(()=>c.v.reportAudioTiming({...t,firstAudioMs:-2}),{code:'brain_invalid_timing'});
});
