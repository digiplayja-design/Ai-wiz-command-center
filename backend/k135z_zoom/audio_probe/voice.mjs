import {MediaTonePlayer} from './media_player.mjs';
import {VoicePreview} from './voice_session.mjs';
const el = id => document.getElementById(id);
async function load(signal) {
  const timeout = new AbortController();
  const abort = () => timeout.abort(); signal.addEventListener('abort', abort, {once:true});
  if (signal.aborted) timeout.abort();
  const timer = setTimeout(abort, 25000);
  try {
    const response = await fetch('/k135z/audio-output-test/voice/prepare', {
      method:'POST', headers:{'Content-Type':'application/json'}, body:'{}', signal:timeout.signal,
      credentials:'omit', cache:'no-store',
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw Object.assign(Error('PREPARATION_FAILED'), {code:body.code});
    }
    if (!(response.headers.get('content-type') || '').startsWith('audio/mpeg')) throw Error('AUDIO');
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length < 64 || bytes.length > 1024 * 1024) throw Error('SIZE');
    return bytes;
  } finally { clearTimeout(timer); signal.removeEventListener('abort', abort); }
}
const preview = new VoicePreview({player:new MediaTonePlayer({timeoutMs:30000}), load, changed:render});
function render() {
  el('broadcast').checked = preview.ready;
  el('prepare').disabled = preview.loading || preview.playing || !!preview.bytes;
  el('prepare').textContent = preview.loading ? 'Preparing greeting…' : preview.bytes ? 'Greeting prepared' : 'Prepare greeting';
  el('prepare').setAttribute('aria-busy', String(preview.loading));
  el('prepare').setAttribute('aria-pressed', String(!!preview.bytes));
  el('play').disabled = !preview.ready || !preview.bytes || preview.loading || preview.playing;
  el('play').textContent = preview.playing ? 'Nova is speaking…' : 'Play Nova greeting';
  el('play').setAttribute('aria-busy', String(preview.playing));
  el('message').textContent = preview.message;
  for (const [id, heard] of [['yes',true],['no',false]]) {
    el(id).disabled = !preview.ready || !preview.finished || preview.playing;
    el(id).setAttribute('aria-pressed', String(preview.result === heard));
  }
  el('result').textContent = preview.result === null ? 'No participant result reported.' :
    preview.result ? 'Last report: greeting heard on the other device.' : 'Last report: greeting not heard on the other device.';
}
el('prepare').onclick = () => preview.prepare();
el('broadcast').onchange = event => preview.setReady(event.target.checked);
el('play').onclick = () => preview.play();
el('stop').onclick = () => preview.stop();
el('yes').onclick = () => preview.confirm(true);
el('no').onclick = () => preview.confirm(false);
document.addEventListener('visibilitychange', () => { if (document.hidden) preview.stop(); });
window.addEventListener('pagehide', () => preview.stop());
render();
