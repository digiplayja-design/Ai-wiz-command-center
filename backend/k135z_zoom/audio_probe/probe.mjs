// An SDK success is only an accepted request, never proof of remote audibility.
function zoomCode(error) {
  const code = error?.code;
  return (typeof code === 'number' || typeof code === 'string') && /^\d{1,6}$/.test(String(code)) ? String(code) : '';
}
function sharingFailure(error, mode, action) {
  const label = mode === 'shareApp' ? 'App sharing' : 'Computer audio sharing';
  const code = zoomCode(error);
  const reasons = {
    '10018':'Zoom could not share the app.', '10023':'Screen sharing is disabled in this meeting.',
    '10024':'Screen sharing is already active.', '10025':'Screen sharing did not start.',
    '10059':'Zoom is sharing a screen or another app.', '10129':'Computer audio sharing is disabled in this meeting.',
    '10130':'Computer audio sharing did not start.', '10131':'Zoom could not share computer audio.',
    '10132':'Computer audio sharing is already active.', '10137':'Zoom requires a choice about an existing share.'
  };
  if (error?.message === 'TIMEOUT') return `${label} ${action} timed out. Check Zoom's sharing controls.`;
  return `${label} ${action} failed${code ? ` (Zoom code ${code})` : ''}. ${reasons[code] || 'Zoom did not confirm the request.'}`;
}
function supportFailure(error, stage) {
  const code = zoomCode(error);
  const safeCode = code ? ` (Zoom code ${code})` : '';
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
    this.cleanupPending = false;
    this.shareDetail = ''; this.stopDetail = ''; this.result = '';
  }
  tell(message) { this.message = message; this.changed(); }
  async bounded(promise) {
    let timer;
    try { return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(Error('TIMEOUT')), this.timeoutMs);
    })]); } finally { clearTimeout(timer); }
  }
  async check() {
    if (this.busy || this.mode || this.pendingStart || this.cleanupPending) return;
    const e = ++this.epoch; this.ready = false; this.supported.clear(); this.busy = true;
    this.shareDetail = ''; this.stopDetail = ''; this.result = '';
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
    if (!this.ready || this.busy || this.mode || this.pendingStart || this.cleanupPending || !['shareComputerAudio','shareApp'].includes(mode) ||
        !this.supported.has(mode)) return;
    const e = ++this.epoch; this.busy = true; this.heard = false; this.played = false;
    this.shareDetail = ''; this.stopDetail = ''; this.result = '';
    this.tell('Checking the meeting before requesting sharing…');
    let requesting = false;
    try {
      const context = await this.bounded(this.sdk.getRunningContext());
      if (e !== this.epoch) return;
      if (context?.context !== 'inMeeting') { this.ready = false; throw Error('LEFT_MEETING'); }
      this.mode = mode;
      requesting = true;
      this.shareDetail = mode === 'shareApp' ? 'App sharing start requested.' : 'Computer audio sharing start requested.';
      const request = this.sdk[mode](mode === 'shareApp' ? {action:'start',withSound:true} : {action:'start',mode:'mono'});
      this.pendingStart = true;
      // If Stop/timeout wins, clean up any later acknowledgement of our request.
      Promise.resolve(request).then(() => {
        this.pendingStart = false;
        if (e !== this.epoch) this.cleanupLate(mode);
        this.changed();
      }, error => {
        this.pendingStart = false;
        if (e !== this.epoch) this.shareDetail = sharingFailure(error, mode, 'start');
        this.changed();
      });
      await this.bounded(request);
      if (e !== this.epoch) return;
      this.shareDetail = (mode === 'shareApp' ? 'App sharing' : 'Computer audio sharing') +
        ' request accepted by Zoom. Remote audibility is not confirmed.';
      this.tell('Zoom accepted the sharing request. Play the tone and ask another participant whether they hear it.');
    } catch (error) {
      if (e === this.epoch) {
        this.epoch++; this.ready = false; this.busy = false;
        this.shareDetail = requesting ? sharingFailure(error, mode, 'start') :
          'The meeting check failed before sharing was requested. Reopen this app inside the active meeting.';
        this.tell(this.shareDetail + ' Use Stop test sharing before retrying.');
      }
    } finally { if (e === this.epoch) this.busy = false; this.changed(); }
  }
  cleanupLate(mode) {
    this.mode = mode; this.ready = false;
    this.shareDetail = 'A delayed sharing request completed after cancellation. Remote audibility is not confirmed.';
    this.tell('A delayed sharing request completed. Stopping it now…');
    if (this.stopping) {
      this.cleanupPending = true;
      void this.stopping.then(() => {
        this.cleanupPending = false; this.mode = mode;
        void this.stop('late-start');
      });
    } else void this.stop('late-start');
  }
  async play() {
    if (!this.ready || this.busy || !this.mode || this.playing) return;
    const e = this.epoch; this.playing = true; this.heard = false; this.played = false; this.result = '';
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
    this.result = this.heard ? 'Test result: you confirmed another participant heard the tones.' :
      'Test result: you reported that the other participant did not hear the tones.';
    this.tell(this.heard ? 'You confirmed another participant heard the tone. Save this result for the Nova speaking integration.' :
      'The other participant did not hear the tone. The output route is not proven.');
  }
  async stop(source = 'button') {
    this.epoch++; this.player.stop(); this.playing = false; this.ready = false;
    this.heard = false; this.played = false;
    if (this.stopping) return this.stopping;
    const mode = this.mode;
    this.stopDetail = source === 'hidden' ? 'Stop requested because the test page was hidden.' :
      source === 'pagehide' ? 'Stop requested because the test page was closed or left.' :
      source === 'late-start' ? 'Stop requested after a delayed sharing response.' : 'Stop test sharing was pressed.';
    this.busy = true; this.tell('Test audio is off. Stopping test sharing…');
    this.stopping = Promise.resolve().then(async () => {
      try {
        if (mode) await this.bounded(this.sdk[mode]({action:'stop'}));
        if (this.mode === mode) this.mode = null;
        this.tell(this.pendingStart ? 'Tone stopped. Zoom has not finished responding to the sharing request. Check sharing inside Zoom.' :
          'Test stopped. Use Check Zoom audio support to run another test.');
      } catch (error) {
        // Only the documented not-started code for this exact sharing method is an inactive state.
        const inactive = mode === 'shareApp' ? zoomCode(error) === '10025' :
          mode === 'shareComputerAudio' && zoomCode(error) === '10130';
        if (inactive) {
          if (this.mode === mode) this.mode = null;
          this.stopDetail += ` Zoom reports this share was not started (Zoom code ${zoomCode(error)}).`;
          this.tell(this.pendingStart ? 'Test audio is off. An earlier start request is still pending. Check sharing inside Zoom.' :
            'Zoom reports this share is inactive. Use Check Zoom audio support to run another test.');
        } else {
          this.stopDetail += ' ' + sharingFailure(error, mode, 'stop');
          this.tell('Test audio is off, but Zoom sharing is unconfirmed. Stop sharing inside Zoom or retry Stop test sharing. See the details below.');
        }
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
