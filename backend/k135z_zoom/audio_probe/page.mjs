import {AudioProbe,TonePlayer} from './probe.mjs';
const el = id => document.getElementById(id);
const probe = new AudioProbe({sdk:globalThis.zoomSdk,player:new TonePlayer(),changed:render});
function render() {
  el('message').textContent = probe.message;
  el('support').textContent = probe.ready ? `Available: ${[
    probe.supported.has('shareComputerAudio') && 'computer audio',
    probe.supported.has('shareApp') && 'app sharing (sound still needs a live test)'].filter(Boolean).join('; ')}.` : '';
  el('check').disabled = probe.busy || !!probe.mode || probe.pendingStart;
  el('check').setAttribute('aria-busy',String(probe.busy && !probe.mode));
  for (const [id,method] of [['computer','shareComputerAudio'],['app','shareApp']]) {
    el(id).disabled = !probe.ready || probe.busy || !!probe.mode || !probe.supported.has(method);
    el(id).setAttribute('aria-pressed',String(probe.mode === method && probe.ready && !probe.busy));
  }
  el('play').disabled = !probe.ready || probe.busy || !probe.mode || probe.playing;
  el('play').setAttribute('aria-busy',String(probe.playing));
  for (const id of ['yes','no']) el(id).disabled = !probe.ready || probe.busy || !probe.mode || !probe.played || probe.playing;
  el('yes').setAttribute('aria-pressed',String(probe.heard));
}
el('check').onclick = () => { probe.sdk = globalThis.zoomSdk; return probe.check(); };
el('computer').onclick = () => probe.share('shareComputerAudio');
el('app').onclick = () => probe.share('shareApp');
el('play').onclick = () => probe.play();
el('yes').onclick = () => probe.confirm(true);
el('no').onclick = () => probe.confirm(false);
el('stop').onclick = () => probe.stop();
document.addEventListener('visibilitychange',() => {
  if (document.hidden) void probe.stop();
});
window.addEventListener('pagehide',() => { void probe.stop(); });
render();
