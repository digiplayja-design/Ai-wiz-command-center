// Standard media playback for comparison with the v3 Web Audio oscillator.
// Successful local playback never proves that Zoom delivered audio remotely.
export function makeToneWav() {
  const rate = 24000, samples = Math.round(rate * 1.8);
  const bytes = new Uint8Array(44 + samples * 2), view = new DataView(bytes.buffer);
  const word = (offset, value) => [...value].forEach((c, i) => { bytes[offset + i] = c.charCodeAt(0); });
  word(0, 'RIFF'); view.setUint32(4, bytes.length - 8, true); word(8, 'WAVE');
  word(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  word(36, 'data'); view.setUint32(40, samples * 2, true);
  for (let i = 0; i < samples; i++) {
    const t = i / rate, pulse = Math.floor(t / .65), within = t - pulse * .65;
    const envelope = pulse < 3 && within < .35 ? Math.min(1, within / .03, (.35 - within) / .05) : 0;
    view.setInt16(44 + i * 2, Math.round(Math.sin(2 * Math.PI * 523.25 * t) * .08 * envelope * 32767), true);
  }
  return bytes;
}

export class MediaTonePlayer {
  constructor({createAudio = () => {
    const audio = document.createElement('audio');
    document.body.append(audio);
    return audio;
  }, createUrl = bytes => URL.createObjectURL(new Blob([bytes], {type:'audio/wav'})),
  revokeUrl = url => URL.revokeObjectURL(url), timeoutMs = 15000} = {}) {
    Object.assign(this, {createAudio, createUrl, revokeUrl, timeoutMs});
    this.current = null;
  }
  play() {
    this.stop();
    return new Promise((resolve, reject) => {
      let audio, url, timer, settled = false, session;
      const finish = error => {
        if (settled) return;
        settled = true; clearTimeout(timer);
        if (this.current === session) this.current = null;
        if (audio) {
          audio.removeEventListener('ended', ended);
          audio.removeEventListener('error', failed);
          // Cancel pending play promises and detach the source as well as pausing.
          try { audio.pause(); audio.removeAttribute('src'); audio.load(); } catch (_) {}
          audio.remove();
        }
        if (url) this.revokeUrl(url);
        error ? reject(error) : resolve();
      };
      const ended = () => { if (audio.ended) finish(); };
      const failed = () => finish(Error('MEDIA_PLAYBACK_FAILED'));
      session = {cancel:() => finish(Error('STOPPED'))};
      this.current = session;
      try {
        audio = this.createAudio(); url = this.createUrl(makeToneWav());
        audio.autoplay = false; audio.loop = false; audio.muted = false; audio.volume = 1;
        audio.preload = 'auto'; audio.setAttribute('playsinline', '');
        audio.addEventListener('ended', ended); audio.addEventListener('error', failed);
        audio.src = url;
        timer = setTimeout(() => finish(Error('MEDIA_PLAYBACK_TIMEOUT')), this.timeoutMs);
        // Called synchronously from the user's Play button to retain activation.
        Promise.resolve(audio.play()).then(() => {
          if (settled) audio.pause();
        }, failed);
      } catch (_) { failed(); }
    });
  }
  stop() { this.current?.cancel(); }
}
