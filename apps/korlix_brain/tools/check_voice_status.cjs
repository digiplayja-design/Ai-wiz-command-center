const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Run the shipped bridge and voice controls without browser/network access.
// DOM stubs record the status and control state; hardware and layout remain
// covered separately by device checks and check_controls.cjs.
const source = fs.readFileSync(path.resolve(__dirname, '../assets/web/app.js'), 'utf8');
function section(start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Voice source section exists: ${start}`);
  return source.slice(first, last);
}
const bridge = section('  // The bundled view never receives an access token.', '  function applySnapshot(');
const controls = section('  function stopVoice(){', "  root.querySelectorAll('[data-go]')");

function harness() {
  const nodes = new Map(), calls = [], listeners = new Map();
  const document = {activeElement: null, body: {}, documentElement: {},
    addEventListener(type, handler) { listeners.set(type, handler); }}, selectedMode = {value: 'live'};
  const get = id => {
    if (!nodes.has(id)) nodes.set(id, {textContent: '', disabled: false, dataset: {},
      focus() { document.activeElement = this; listeners.get('focusin')?.({type: 'focusin', target: this}); }});
    return nodes.get(id);
  };
  const context = vm.createContext({
    window: {Korlix: {postMessage: raw => calls.push(JSON.parse(raw))}},
    document,
    root: {dataset: {}, querySelector: () => selectedMode},
    get, phases: ['listening', 'thinking', 'speaking', 'complete'].map(key => ({key})),
    stopWelcome() {}, setPhase() {}, refreshMusic() {}, welcomeUi() {},
    setTimeout: () => 1, clearTimeout() {},
  });
  vm.runInContext(`${bridge}\n${controls}\nthis.voice = {startVoice, pauseVoice, resumeVoice, stopVoice, syncVoiceRestart};`, context);
  const emit = (phase, message, extra = {}) => context.window.KorlixBrainReceive({type: 'voice', phase, message, ...extra});
  const pending = action => {
    const message = calls.findLast(call => call.action === action);
    assert.ok(message, `Native ${action} request exists`);
    return message;
  };
  const reply = (message, data, error) => context.window.KorlixBrainReceive({type: 'reply', id: message.id, data, error});
  const intent = (type, extra = {}) => listeners.get(type)?.({type, ...extra});
  return {...context.voice, emit, pending, reply, get, calls, root: context.root, document, selectedMode, intent};
}
const flush = () => new Promise(resolve => setImmediate(resolve));
const status = (h, expected) => {
  assert.equal(h.get('kb-voice-phase').textContent, expected);
  assert.equal(h.get('kb-live-phase').textContent, expected);
};

(async () => {
  const failure = 'Voice setup could not be confirmed. Tap Start conversation to retry.';
  for (const error of [undefined, 'Could not complete this action.']) {
    const h = harness();
    h.startVoice();
    h.emit('complete', failure);
    h.reply(h.pending('startVoice'), {active: false}, error);
    await flush();
    status(h, failure);
    assert.equal(h.root.dataset.voiceActive, 'false');
  }

  const h = harness();
  h.startVoice();
  h.reply(h.pending('startVoice'), null, failure);
  await flush();
  status(h, failure);
  assert.equal(h.root.dataset.voiceActive, 'false');
  h.startVoice();
  h.emit('listening', 'Rici is listening');
  h.reply(h.pending('startVoice'), {active: true});
  await flush();
  status(h, 'Rici is listening');
  assert.equal(h.calls.filter(call => call.action === 'startVoice').length, 2);

  h.pauseVoice();
  h.emit('paused', 'Paused', {paused: true});
  h.reply(h.pending('pauseVoice'), {active: false, paused: true});
  await flush();
  const resumeFailure = 'The conversation could not be restored. Tap Resume to try again.';
  h.resumeVoice();
  h.emit('paused', resumeFailure, {paused: true});
  h.reply(h.pending('resumeVoice'), null, 'Could not complete this action.');
  await flush();
  status(h, resumeFailure);
  assert.equal(h.get('kb-resume-voice').disabled, false);
  h.resumeVoice();
  h.reply(h.pending('resumeVoice'), null, resumeFailure);
  await flush();
  status(h, resumeFailure);

  h.resumeVoice();
  const canceledResume = h.pending('resumeVoice');
  h.stopVoice();
  h.emit('complete', 'Microphone off');
  h.reply(h.pending('stopVoice'), null);
  h.reply(canceledResume, null, resumeFailure);
  await flush();
  status(h, 'Microphone off');
  assert.equal(h.root.dataset.voicePaused, 'false');

  h.startVoice();
  const canceledStart = h.pending('startVoice');
  h.pauseVoice();
  h.reply(h.pending('pauseVoice'), {active: false, paused: false});
  h.reply(canceledStart, null, failure);
  await flush();
  status(h, 'Microphone off');
  assert.equal(h.root.dataset.voiceActive, 'false');

  // A delayed bridge failure cannot erase a listening state already delivered
  // by the native session, or imply that a still-open microphone has stopped.
  h.startVoice();
  h.emit('listening', 'Rici is listening');
  h.reply(h.pending('startVoice'), null, 'Bridge reply interrupted.');
  await flush();
  status(h, 'Rici is listening');
  assert.equal(h.root.dataset.voiceActive, 'true');

  // Stop used to remove the complete fixed dock. Keep a reachable start state
  // even when the inline link is offscreen, with no implicit microphone start.
  const startsBeforeStop = h.calls.filter(call => call.action === 'startVoice').length;
  h.document.activeElement = h.get('kb-stop-voice');
  h.stopVoice();
  h.document.activeElement = h.document.body; // Browser blur after Stop disables.
  h.emit('complete', 'Microphone off');
  h.reply(h.pending('stopVoice'), null);
  await flush();
  assert.equal(h.root.dataset.voiceControls, 'true');
  assert.equal(h.root.dataset.voiceIdle, 'true');
  assert.equal(h.get('kb-start-voice').hidden, false);
  assert.equal(h.get('kb-start-voice').disabled, false);
  assert.equal(h.get('kb-active-voice-controls').hidden, true);
  assert.equal(h.get('kb-start-label').textContent, 'Start Live Conversation');
  assert.equal(h.document.activeElement, h.get('kb-start-voice'));
  assert.equal(h.calls.filter(call => call.action === 'startVoice').length, startsBeforeStop);
  h.selectedMode.value = 'deep';
  h.syncVoiceRestart();
  assert.equal(h.get('kb-start-label').textContent, 'Start Deep Think');
  h.startVoice();
  h.startVoice();
  assert.equal(h.calls.filter(call => call.action === 'startVoice').length, startsBeforeStop + 1);
  assert.equal(h.pending('startVoice').payload.mode, 'deep');
  h.emit('listening', 'Rici is listening');
  h.reply(h.pending('startVoice'), {active: true});
  await flush();
  assert.equal(h.get('kb-start-voice').hidden, true);
  assert.equal(h.get('kb-active-voice-controls').hidden, false);

  for (const navigation of ['focusin', 'pointerdown', 'keydown']) {
    const f = harness();
    f.startVoice(); f.emit('listening', 'Rici is listening');
    f.reply(f.pending('startVoice'), {active: true});
    await flush();
    f.document.activeElement = f.get('kb-stop-voice');
    f.stopVoice();
    f.document.activeElement = f.document.body;
    if (navigation === 'focusin') f.get('kb-return-voice').focus();
    else f.intent(navigation, navigation === 'keydown' ? {key: 'Tab'} : {target: f.document.body});
    const chosenFocus = f.document.activeElement;
    f.emit('complete', 'Microphone off');
    f.reply(f.pending('stopVoice'), null);
    await flush();
    assert.equal(f.document.activeElement, chosenFocus,
      `Completing Stop must respect the user's intervening ${navigation}`);
    assert.equal(f.get('kb-start-voice').disabled, false);
  }
  console.log('Brain voice status regressions passed (shipped JS; no hardware simulation).');
})().catch(error => {console.error(error); process.exitCode = 1;});
