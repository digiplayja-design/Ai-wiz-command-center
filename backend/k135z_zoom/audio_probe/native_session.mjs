// Local synthetic playback only. Zoom owns the screen broadcast and its permissions.
export class NativeBroadcastTest {
  constructor({player, changed = () => {}}) {
    Object.assign(this, {player, changed});
    this.ready = false; this.playing = false; this.finished = false;
    this.result = null; this.epoch = 0;
    this.message = 'Start a Zoom screen broadcast with device audio, then check the box below.';
  }
  tell(message) { this.message = message; this.changed(); }
  setReady(value) {
    if (value !== true) { this.stop(); return; }
    if (this.playing || this.ready) return;
    this.ready = true; this.finished = false; this.result = null;
    this.tell('Ready to play on this device. Audio reaching the other device is not confirmed.');
  }
  async play() {
    if (!this.ready || this.playing) return;
    const e = ++this.epoch;
    this.playing = true; this.finished = false; this.result = null;
    this.tell('Playing three test tones. Listen on the other device.');
    try {
      // Preserve the Play button's user activation: do not await setup first.
      await this.player.play();
      if (e === this.epoch) {
        this.finished = true;
        this.tell('Playback finished on this device. Did the other device hear the tones?');
      }
    } catch (_) {
      if (e === this.epoch) this.tell('Playback failed on this device. Tap Play to retry.');
    } finally {
      if (e === this.epoch) { this.playing = false; this.changed(); }
    }
  }
  confirm(heard) {
    if (!this.ready || this.playing || !this.finished || typeof heard !== 'boolean') return;
    this.result = heard;
    this.tell(heard ? 'You confirmed the other device heard the tones through the Zoom broadcast.' :
      'You reported the other device did not hear the tones. The output test has not passed.');
  }
  stop(reason = 'button') {
    this.epoch++; this.player.stop(); this.ready = false; this.playing = false; this.finished = false;
    this.tell(reason === 'hidden' ? 'Test audio stopped because this page was hidden. Stop Share in Zoom to end the broadcast.' :
      'Test audio stopped. Stop Share in Zoom to end the broadcast.');
  }
}
