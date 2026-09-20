// Preparation is silent. Each playback requires a fresh, explicit Play click.
export class VoicePreview {
  constructor({player, load, changed = () => {}}) {
    Object.assign(this, {player, load, changed});
    this.ready = false; this.loading = false; this.playing = false;
    this.bytes = null; this.finished = false; this.result = null; this.epoch = 0;
    this.message = 'Prepare the greeting first. Nothing plays until you tap Play Nova greeting.';
  }
  tell(message) { this.message = message; this.changed(); }
  async prepare() {
    if (this.loading || this.playing || this.bytes) return;
    const e = ++this.epoch;
    const controller = new AbortController(); this.controller = controller;
    this.loading = true; this.finished = false; this.result = null;
    this.tell('Preparing Nova’s greeting… Audio is not playing.');
    try {
      const bytes = await this.load(controller.signal);
      if (e !== this.epoch) return;
      this.bytes = bytes;
      this.tell('Greeting prepared. Confirm your Zoom broadcast, then tap Play Nova greeting.');
    } catch (error) {
      if (e === this.epoch) this.tell(error?.code === 'VOICE_NOT_CONFIGURED' ?
        'Voice service is not configured. Share this message with KORLIX support.' :
        error?.code === 'VOICE_LIMIT_REACHED' ?
        'Voice preparation needs a service reset. Share this message with KORLIX support.' :
        'Could not prepare the voice preview. Wait one minute, then tap Prepare greeting again.');
    } finally {
      if (e === this.epoch) { this.loading = false; this.controller = null; this.changed(); }
    }
  }
  setReady(value) {
    if (value !== true) { this.stop(); return; }
    if (this.playing) return;
    this.ready = true; this.changed();
  }
  async play() {
    if (!this.ready || !this.bytes || this.loading || this.playing) return;
    const e = ++this.epoch;
    this.playing = true; this.finished = false; this.result = null;
    this.tell('Playing Nova’s greeting. Listen on the participant’s device.');
    try {
      await this.player.play(this.bytes, 'audio/mpeg');
      if (e === this.epoch) {
        this.finished = true;
        this.tell('Greeting finished on this device. Was it heard on the participant’s device?');
      }
    } catch (_) {
      if (e === this.epoch) this.tell('Playback failed. Keep Chrome visible and tap Play Nova greeting again.');
    } finally {
      if (e === this.epoch) { this.playing = false; this.changed(); }
    }
  }
  confirm(heard) {
    if (!this.ready || !this.finished || this.playing || typeof heard !== 'boolean') return;
    this.result = heard;
    this.tell(heard ? 'You confirmed Nova’s greeting was heard on the participant’s device.' :
      'You reported that the participant’s device did not hear the greeting.');
  }
  stop() {
    this.epoch++; this.controller?.abort(); this.controller = null; this.player.stop();
    this.ready = false; this.loading = false; this.playing = false; this.finished = false;
    this.tell('Voice stopped. Confirm the broadcast again before replaying. Stop Share in Zoom to end the broadcast.');
  }
}
