const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const app = path.resolve(__dirname, '..');
const buttonIds = ['cinema-kb-pause-voice', 'cinema-kb-resume-voice', 'cinema-kb-stop-voice'];
const widths = [320, 390, 768];

// Explicit native contract fixture. This suite proves WebView behavior, not
// microphone hardware, provider connections, account billing or photo capture.
function nativeFixture() {
  localStorage.setItem('korlix-brain-welcome-v1-seen', 'true');
  window.controlsFixture = {
    calls: [], held: {}, hold: {},
    account: {training: 'Keep these existing instructions.', memories: [], canUndo: false},
  };
  const fixture = window.controlsFixture;
  fixture.emit = (phase, extra = {}) => window.KorlixBrainReceive({
    type: 'voice', phase, message: `Fixture ${phase}`, ...extra,
  });
  fixture.reply = (message, data, error) => window.KorlixBrainReceive({
    type: 'reply', id: message.id, data, error,
  });
  fixture.finish = (action, data) => {
    const message = fixture.held[action];
    if (!message) throw new Error(`No held ${action}`);
    delete fixture.held[action];
    fixture.reply(message, data);
  };
  window.Korlix = {postMessage(raw) {
    const message = JSON.parse(raw);
    fixture.calls.push(message);
    if (fixture.hold[message.action]) {
      fixture.held[message.action] = message;
      return;
    }
    setTimeout(() => {
      switch (message.action) {
        case 'load': return fixture.reply(message, fixture.account);
        case 'welcomeState': return fixture.reply(message, {native: false, automatic: false, foreground: true});
        case 'listSavedTranscripts': return fixture.reply(message, []);
        case 'startVoice':
          fixture.emit('listening', {paused: false});
          return fixture.reply(message, {active: true, paused: false});
        case 'pauseVoice':
          fixture.emit('paused', {paused: true});
          return fixture.reply(message, {active: false, paused: true});
        case 'resumeVoice':
          fixture.emit('listening', {paused: false});
          return fixture.reply(message, {active: true, paused: false});
        case 'stopVoice':
          fixture.emit('complete', {paused: false});
          return fixture.reply(message, {active: false, paused: false});
        case 'pickFile':
        case 'openDocuments': return fixture.reply(message, {imported: true});
        case 'cameraAsk': return fixture.reply(message, {opened: true});
        case 'directions': return fixture.reply(message, {opened: true});
        default: return fixture.reply(message, {});
      }
    }, 0);
  }};
}

async function state(page, active, paused) {
  await page.waitForFunction(({active, paused}) => {
    const root = document.querySelector('.kb-product');
    return root.dataset.voiceActive === String(active) && root.dataset.voicePaused === String(paused);
  }, {active, paused});
}

async function imported(page, kind) {
  await page.waitForFunction(kind => {
    const fixture = window.controlsFixture;
    const pick = fixture.calls.find(c => c.action === 'pickFile' && c.payload.kind === kind);
    return pick && fixture.calls.some(c => c.action === 'load' && Number(c.id) > Number(pick.id)) &&
      document.querySelector('#cinema-kb-account-status').textContent === 'Account connected';
  }, kind);
}

async function listening(page) {
  await state(page, true, false);
  await page.waitForFunction(() => document.querySelector('#cinema-kb-voice-phase').textContent === 'Fixture listening');
}

async function geometry(page, width) {
  const result = await page.evaluate((ids) => {
    const buttons = ids.map(id => {
      const element = document.getElementById(id);
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      const center = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2);
      return {id, x: rect.x, y: rect.y, width: rect.width, height: rect.height,
        visible: style.display !== 'none' && style.visibility === 'visible',
        reachable: Boolean(center && (center === element || element.contains(center)))};
    });
    return {buttons, width: innerWidth, height: innerHeight,
      overflow: document.documentElement.scrollWidth > innerWidth + 1};
  }, buttonIds);
  assert.equal(result.overflow, false, `No horizontal overflow at ${width}`);
  assert.equal(new Set(result.buttons.map(x => x.id)).size, 3, 'Three independent controls');
  for (const b of result.buttons) {
    assert.ok(b.visible && b.width >= 44 && b.height >= 44,
      `${b.id} must have a visible >=44px target at ${width}: ${JSON.stringify(b)}`);
    assert.ok(b.x >= -1 && b.x + b.width <= result.width + 1 &&
      b.y >= -1 && b.y + b.height <= result.height + 1,
      `${b.id} stays in viewport at ${width}: ${JSON.stringify(b)}`);
    assert.ok(b.reachable, `${b.id} center is not obscured at ${width}`);
  }
}

(async () => {
  const browser = await chromium.launch({headless: true,
    executablePath: process.env.BROWSER_EXECUTABLE_PATH || undefined,
    args: ['--no-sandbox', '--disable-dev-shm-usage']});
  const errors = [];
  try {
    for (const width of widths) {
      const page = await browser.newPage({viewport: {width, height: 900}, reducedMotion: 'reduce'});
      page.on('pageerror', error => errors.push({width, message: error.message}));
      await page.route(/^https?:\/\//, route => route.abort());
      await page.addInitScript(nativeFixture);
      await page.goto('file://' + path.join(app, 'assets/web/index.html'));
      await page.waitForFunction(() => document.querySelector('#cinema-kb-account-status')?.textContent === 'Account connected');

      for (const [id, action] of [
        ['cinema-kb-upload-pdf', 'openDocuments'],
        ['cinema-kb-camera-ask', 'cameraAsk'],
        ['cinema-kb-directions', 'directions'],
      ]) {
        const button = page.locator('#' + id);
        assert.equal(await button.count(), 1, `One ${action} entry at ${width}`);
        assert.equal(await button.isVisible(), true);
        const rect = await button.boundingBox();
        assert.ok(rect.width >= 44 && rect.height >= 44, `${action} has a usable touch target`);
        await button.click();
        await page.waitForFunction(action => window.controlsFixture.calls.some(c => c.action === action), action);
      }
      assert.equal(await page.evaluate(() => window.controlsFixture.calls.some(c => ['startVoice', 'resumeVoice'].includes(c.action))), false,
        'Opening tools does not start or resume a microphone');

      await page.locator('[data-go="memory"]').first().click();
      await page.locator('#cinema-kb-memory').fill('A typed memory remains here.');
      await page.locator('#cinema-kb-memory-file-example').click();
      await imported(page, 'memory');
      assert.equal(await page.locator('#cinema-kb-memory').inputValue(), 'A typed memory remains here.',
        'Native imported:true does not replace the draft with undefined');
      assert.equal(await page.evaluate(() => window.controlsFixture.calls.some(c => c.action === 'saveMemory' || c.action === 'saveTraining')), false,
        'Closing native PDF review never manufactures a save');

      // Training imports must follow the same no-text return contract.
      await page.locator('section[data-screen="memory"] [data-go="home"]').click();
      await page.locator('[data-go="train"]').first().click();
      await page.locator('#cinema-kb-training').fill('Draft training remains here.');
      await page.locator('#cinema-kb-training-file-example').click();
      await imported(page, 'training');
      assert.equal(await page.locator('#cinema-kb-training').inputValue(), 'Draft training remains here.');
      await page.locator('section[data-screen="train"] [data-go="home"]').click();
      await page.locator('[data-go="talk"]').first().click();
      await listening(page);
      await geometry(page, width);
      assert.equal(await page.locator('#cinema-kb-pause-voice').isEnabled(), true);
      assert.equal(await page.locator('#cinema-kb-resume-voice').isDisabled(), true);

      // Expose the intermediate state instead of acknowledging immediately.
      await page.evaluate(() => window.controlsFixture.hold.pauseVoice = true);
      await page.locator('#cinema-kb-pause-voice').click();
      assert.equal(await page.locator('#cinema-kb-pause-label').textContent(), 'Pausing…');
      assert.equal(await page.locator('#cinema-kb-pause-voice').isDisabled(), true);
      assert.equal(await page.locator('#cinema-kb-stop-voice').isEnabled(), true);
      const closeWarning = 'Paused · Microphone off. Reconnect to finish closing the voice session.';
      await page.evaluate(message => {
        window.controlsFixture.emit('paused', {paused: true, message});
        // The native event carries the pending-provider-close warning. Its
        // later bridge acknowledgement must not replace it with generic text.
        window.controlsFixture.finish('pauseVoice', {paused: true});
        window.controlsFixture.hold.pauseVoice = false;
      }, closeWarning);
      await state(page, false, true);
      assert.equal(await page.locator('#cinema-kb-voice-phase').textContent(), closeWarning,
        'Pause acknowledgement preserves the native provider-close warning');
      assert.equal(await page.locator('#cinema-kb-live-phase').textContent(), closeWarning,
        'The persistent dock retains the provider-close warning after acknowledgement');
      await geometry(page, width);
      assert.equal(await page.locator('#cinema-kb-pause-voice').isDisabled(), true);
      assert.equal(await page.locator('#cinema-kb-resume-voice').isEnabled(), true);
      assert.equal(await page.locator('#cinema-kb-stop-voice').isEnabled(), true);

      // The main navigation must not turn a user's paused microphone back on.
      const before = await page.evaluate(() => window.controlsFixture.calls.filter(c => ['startVoice', 'resumeVoice'].includes(c.action)).length);
      await page.locator('section[data-screen="talk"] [data-go="home"]').click();
      await state(page, false, true);
      await geometry(page, width);
      await page.locator('[data-go="talk"]').first().click();
      await state(page, false, true);
      assert.equal(await page.evaluate(() => window.controlsFixture.calls.filter(c => ['startVoice', 'resumeVoice'].includes(c.action)).length), before,
        'Home/Talk navigation preserves Pause');

      await page.locator('#cinema-kb-resume-voice').click();
      await listening(page);
      assert.equal(await page.evaluate(() => window.controlsFixture.calls.filter(c => c.action === 'resumeVoice').length), 1);
      await page.locator('#cinema-kb-pause-voice').click();
      await state(page, false, true);
      await page.locator('#cinema-kb-stop-voice').click();
      await state(page, false, false);
      assert.equal(await page.locator('.kb-live-banner').isVisible(), false, 'Stop ends paused conversation');

      await page.locator('#cinema-kb-replay-demo').click();
      await listening(page);
      await page.locator('#cinema-kb-pause-voice').click();
      await state(page, false, true);
      await page.evaluate(() => window.controlsFixture.hold.resumeVoice = true);
      await page.locator('#cinema-kb-resume-voice').click();
      await state(page, true, true);
      assert.equal(await page.locator('#cinema-kb-resume-voice').isDisabled(), true, 'No parallel resumes');
      assert.equal(await page.locator('#cinema-kb-stop-voice').isEnabled(), true, 'Stop can cancel a pending resume');
      await geometry(page, width);
      await page.locator('#cinema-kb-stop-voice').click();
      await state(page, false, false);
      await page.evaluate(() => window.controlsFixture.finish('resumeVoice', {active: true, paused: false}));
      await state(page, false, false);
      assert.equal(await page.locator('.kb-live-banner').isVisible(), false,
        'Late resume acknowledgement cannot undo Stop');

      // Cancellation during Stop ignores stale playback UI until terminal end.
      await page.locator('#cinema-kb-replay-demo').click();
      await listening(page);
      await page.evaluate(() => window.controlsFixture.hold.stopVoice = true);
      await page.locator('#cinema-kb-stop-voice').click();
      assert.equal(await page.locator('#cinema-kb-stop-label').textContent(), 'Stopping…');
      await page.evaluate(() => window.controlsFixture.emit('speaking'));
      assert.equal(await page.locator('#cinema-kb-stop-label').textContent(), 'Stopping…');
      assert.equal(await page.locator('#cinema-kb-stop-voice').isDisabled(), true);
      await page.evaluate(() => {
        window.controlsFixture.emit('complete', {paused: false});
        window.controlsFixture.finish('stopVoice', {active: false, paused: false});
      });
      await state(page, false, false);

      // Pause can cancel startup while native consent is still outstanding.
      // In that case no session was paused; an inactive/unpaused reply must
      // leave the interface complete and ready for an independent new start.
      await page.evaluate(() => Object.assign(window.controlsFixture.hold, {
        startVoice: true, pauseVoice: true, stopVoice: false, resumeVoice: false,
      }));
      await page.locator('#cinema-kb-replay-demo').click();
      await state(page, true, false);
      assert.equal(await page.locator('#cinema-kb-voice-phase').textContent(), 'Connecting to Rici…');
      assert.equal(await page.locator('#cinema-kb-pause-voice').isEnabled(), true);
      await page.locator('#cinema-kb-pause-voice').click();
      assert.equal(await page.locator('#cinema-kb-pause-label').textContent(), 'Pausing…');
      await page.evaluate(() => {
        window.controlsFixture.finish('pauseVoice', {active: false, paused: false});
        window.controlsFixture.finish('startVoice', {active: false, paused: false});
        window.controlsFixture.hold.startVoice = false;
        window.controlsFixture.hold.pauseVoice = false;
      });
      await state(page, false, false);
      assert.equal(await page.locator('#cinema-kb-voice-phase').textContent(), 'Microphone off',
        'Pause during consent completes instead of leaving a pausing state');
      assert.equal(await page.locator('#cinema-kb-pause-label').textContent(), 'Pause');
      assert.equal(await page.locator('#cinema-kb-pause-voice').isDisabled(), true);
      assert.equal(await page.locator('#cinema-kb-resume-voice').isDisabled(), true);
      assert.equal(await page.locator('#cinema-kb-voice-modes').isEnabled(), true);
      assert.equal(await page.locator('#cinema-kb-replay-demo').isEnabled(), true);
      assert.equal(await page.locator('.kb-live-banner').isVisible(), false);
      await page.locator('#cinema-kb-replay-demo').click();
      await listening(page);
      assert.equal(await page.locator('#cinema-kb-pause-voice').isEnabled(), true,
        'A new conversation recovers working Pause after consent cancellation');
      assert.equal(await page.locator('#cinema-kb-stop-voice').isEnabled(), true);
      await page.locator('#cinema-kb-stop-voice').click();
      await state(page, false, false);

      if (process.env.UI_SCREENSHOTS) {
        fs.mkdirSync(process.env.UI_SCREENSHOTS, {recursive: true});
        await page.evaluate(() => window.controlsFixture.emit('paused', {paused: true}));
        await page.screenshot({path: path.join(process.env.UI_SCREENSHOTS, `brain-paused-controls-${width}.png`)});
      }
      console.log(`Brain controls: ${width}px passed`);
      await page.close();
    }
    assert.deepEqual(errors, [], 'No page exceptions');
    console.log('Brain controls and feature-entry regression checks passed. Native voice/photo/device behavior is not simulated as verified.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
