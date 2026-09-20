// An SDK success is only an accepted request, never proof of remote audibility.
function supportFailure(error, stage) {
  const code = error?.code;
  const safeCode = (typeof code === 'number' || typeof code === 'string') && /^\d{1,6}$/.test(String(code))
    ? ` (Zoom code ${code})` : '';
  const setup = 'In Marketplace > Development > Features > Surface > Zoom Apps SDK, check these APIs: ' +
    'getSupportedJsApis, getRunningContext, shareApp, shareComputerAudio. Save, reopen the app in Zoom, then retry.';
  if (error?.message === 'SDK_UNAVAILABLE') return 'Zoom SDK did not load. Check the app domain allow list includes appssdk.zoom.us, then reopen this app in Zoom.';
  if (error?.message === 'The Zoom Apps SDK is not supported by this browser') return 'The Zoom SDK cannot reach the Zoom client. ' + setup;
  if (error?.message === 'NOT_IN_MEETING') return 'Zoom reports this app is outside a meeting. Reopen Korlix Meeting Copilot from Apps inside the active meeting, then retry.';
  if (error?.message === 'BAD_RESPONSE') return `${stage} returned an unexpected response. Reopen the app and retry; report this message if it continues.`;
  if (error?.message === 'TIMEOUT') return `${stage} timed out. Close and reopen this app before retrying. ` + setup;
  return `${stage} failed${safeCode}. ` + setup;
}

export class AudioProbe {
  constructor({sdk, player, changed = () => {}, timeoutMs = 10000}) {
    Object.assign(this, {sdk, player, changed, timeoutMs});
    this.supported = new Set(); this.busy = false; this.mode = null;
    this.ready = false; this.playing = false; this.heard = false; this.played = false;
    this.message = 'Open this test inside Zoom, then check audio support.';
    this.epoch = 0;
    this.pendingStart = false;
  }
  tell(message) { this.message = message; this.changed(); }
  async bounded(promise) {
    let timer;
    try { return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(Error('TIMEOUT')), this.timeoutMs);
    })]); } finally { clearTimeout(timer); }
  }
  async check() {
    if (this.busy || this.mode || this.pendingStart) return;
    const e = ++this.epoch; this.ready = false; this.supported.clear(); this.busy = true;
    this.heard = false; this.played = false; this.tell('Checking Zoom audio support…');
    let stage = 'Zoom SDK loading';
    try {
      if (typeof this.sdk?.config !== 'function') throw Error('SDK_UNAVAILABLE');
      stage = 'Zoom app authorization';
      this.tell('Checking Zoom app authorization…');
      const c = await this.bounded(this.sdk.config({version:'0.16', capabilities:
        ['getSupportedJsApis','getRunningContext','shareComputerAudio','shareApp']}));
      if (e !== this.epoch) return;
      if (!c || typeof c.runningContext !== 'string') throw Error('BAD_RESPONSE');
      stage = 'Meeting context check';
      if (c.runningContext !== 'inMeeting') throw Error('NOT_IN_MEETING');
      stage = 'Zoom API availability check';
      this.tell('Checking which sharing controls Zoom allows…');
      const apis = await this.bounded(this.sdk.getSupportedJsApis());
      if (e !== this.epoch) return;
      if (!Array.isArray(apis?.supportedApis)) throw Error('BAD_RESPONSE');
      const excluded = new Set(c.unsupportedApis || []);
      this.supported = new Set(apis.supportedApis.filter(x => !excluded.has(x)));
      this.ready = this.supported.has('getRunningContext') &&
        (this.supported.has('shareComputerAudio') || this.supported.has('shareApp'));
      this.tell(this.ready ? 'Choose an available sharing option. Nothing is shared yet.' :
        'This Zoom client does not expose the required sharing controls. Try Zoom on Windows or Mac.');
    } catch (error) {
      if (e === this.epoch) {
        this.ready = false; this.supported.clear();
        this.tell(supportFailure(error, stage));
      }
    } finally { if (e === this.epoch) { this.busy = false; this.changed(); } }
  }
  async share(mode) {
    if (!this.ready || this.busy || this.mode || this.pendingStart || !['shareComputerAudio','shareApp'].includes(mode) ||
        !this.supported.has(mode)) return;
    const e = ++this.epoch; this.busy = true; this.heard = false; this.played = false;
    this.tell('Checking the meeting before requesting sharing…');
    try {
      const context = await this.bounded(this.sdk.getRunningContext());
      if (e !== this.epoch) return;
      if (context.context !== 'inMeeting') { this.ready = false; throw Error('LEFT_MEETING'); }
      this.mode = mode;
      const request = this.sdk[mode](mode === 'shareApp' ? {action:'start',withSound:true} : {action:'start',mode:'mono'});
      this.pendingStart = true;
      // If Stop/timeout wins, clean up any later acknowledgement of our request.
      Promise.resolve(request).then(() => {
        this.pendingStart = false;
        if (e !== this.epoch) this.cleanupLate(mode);
        this.changed();
      }, () => { this.pendingStart = false; this.changed(); });
      await this.bounded(request);
      if (e !== this.epoch) return;
      this.tell('Zoom accepted the sharing request. Play the tone and ask another participant whether they hear it.');
    } catch (_) {
      if (e === this.epoch) {
        this.epoch++; this.ready = false; this.busy = false;
        this.tell('Sharing was not confirmed. Use Stop test sharing; check Zoom’s sharing controls before retrying.');
      }
    } finally { if (e === this.epoch) this.busy = false; this.changed(); }
  }
  cleanupLate(mode) {
    this.mode = mode; this.ready = false;
    this.tell('A delayed sharing request completed. Stopping it now…');
    void this.stop();
  }
  async play() {
    if (!this.ready || this.busy || !this.mode || this.playing) return;
    const e = this.epoch; this.playing = true; this.heard = false; this.played = false;
    this.tell('Playing the test tone on this device. Remote audibility is not confirmed.');
    try {
      await this.player.play();
      if (e === this.epoch) {
        this.played = true;
        this.tell('Tone finished. Ask a second participant on another device whether they heard it.');
      }
    } catch (_) {
      if (e === this.epoch) this.tell('Tone playback failed. Stop sharing, check device audio, then retry.');
    } finally { this.playing = false; this.changed(); }
  }
  confirm(heard) {
    if (!this.ready || this.busy || !this.mode || !this.played || this.playing) return;
    this.heard = heard === true;
    this.tell(this.heard ? 'You confirmed another participant heard the tone. Save this result for the Nova speaking integration.' :
      'The other participant did not hear the tone. The output route is not proven.');
  }
  async stop() {
    this.epoch++; this.player.stop(); this.playing = false; this.ready = false;
    this.heard = false; this.played = false;
    if (this.stopping) return this.stopping;
    const mode = this.mode;
    this.busy = true; this.tell('Tone stopped. Stopping test sharing…');
    this.stopping = Promise.resolve().then(async () => {
      try {
        if (mode) await this.bounded(this.sdk[mode]({action:'stop'}));
        if (this.mode === mode) this.mode = null;
        this.tell(this.pendingStart ? 'Tone stopped. Zoom has not finished responding to the sharing request. Check sharing inside Zoom.' :
          'Test stopped. Use Check Zoom audio support to run another test.');
      } catch (_) {
        this.tell('Tone stopped, but Zoom sharing is unconfirmed. Stop sharing inside Zoom or retry Stop test sharing.');
      } finally { this.busy = false; this.stopping = null; this.changed(); }
    });
    return this.stopping;
  }
}

export class TonePlayer {
  constructor(createContext = () => new (globalThis.AudioContext || globalThis.webkitAudioContext)()) {
    this.createContext = createContext; this.context = null; this.epoch = 0;
  }
  async play() {
    this.stop(); const e = this.epoch; const c = this.createContext(); this.context = c;
    await c.resume();
    if (e !== this.epoch) throw Error('STOPPED');
    const oscillator = c.createOscillator(), gain = c.createGain();
    oscillator.frequency.value = 523.25; gain.gain.value = 0;
    oscillator.connect(gain); gain.connect(c.destination);
    const t = c.currentTime;
    for (let i = 0; i < 3; i++) {
      gain.gain.setValueAtTime(0, t + i * .65);
      gain.gain.linearRampToValueAtTime(.08, t + i * .65 + .03);
      gain.gain.setValueAtTime(.08, t + i * .65 + .30);
      gain.gain.linearRampToValueAtTime(0, t + i * .65 + .35);
    }
    await new Promise(resolve => {
      this.finish = resolve; oscillator.onended = resolve;
      oscillator.start(t); oscillator.stop(t + 1.8);
    });
    if (e !== this.epoch) throw Error('STOPPED');
    this.stop();
  }
  stop() {
    this.epoch++; this.finish?.(); this.finish = null;
    const c = this.context; this.context = null;
    if (c && c.state !== 'closed') void c.close().catch(() => {});
  }
}
