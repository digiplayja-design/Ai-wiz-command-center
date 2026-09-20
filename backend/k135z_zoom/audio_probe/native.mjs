import {MediaTonePlayer} from './media_player.mjs';
import {NativeBroadcastTest} from './native_session.mjs';
const el = id => document.getElementById(id);
const test = new NativeBroadcastTest({player:new MediaTonePlayer(), changed:render});
function render() {
  el('broadcast').checked = test.ready;
  el('message').textContent = test.message;
  el('play').disabled = !test.ready || test.playing;
  el('play').setAttribute('aria-busy', String(test.playing));
  el('play').textContent = test.playing ? 'Playing test tones…' : 'Play three test tones';
  for (const [id, result] of [['yes',true],['no',false]]) {
    el(id).disabled = !test.ready || test.playing || !test.finished;
    el(id).setAttribute('aria-pressed', String(test.result === result));
  }
  el('result').textContent = test.result === null ? 'No participant result reported.' :
    test.result ? 'Last result: you reported tones heard on the other device.' : 'Last result: you reported no tones on the other device.';
}
el('broadcast').onchange = event => test.setReady(event.target.checked);
el('play').onclick = () => test.play();
el('stop').onclick = () => test.stop();
el('yes').onclick = () => test.confirm(true);
el('no').onclick = () => test.confirm(false);
document.addEventListener('visibilitychange', () => { if (document.hidden) test.stop('hidden'); });
window.addEventListener('pagehide', () => test.stop('hidden'));
render();
