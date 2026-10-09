const assert = require('node:assert/strict');
const {before, after, test} = require('node:test');
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright');

const root = path.resolve('build/camera_capture_browser');
let server, browser, base;

before(async () => {
  server = http.createServer(async (request, response) => {
    const pathname = decodeURIComponent(new URL(request.url, 'http://local').pathname);
    const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!file.startsWith(root + path.sep)) {
      response.writeHead(403).end();
      return;
    }
    try {
      const data = await fs.readFile(file);
      const mime = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json'};
      response.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream'}).end(data);
    } catch (_) {
      response.writeHead(404).end();
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
  browser = await chromium.launch({headless: true, executablePath: process.env.KORLIX_CHROME_PATH, args: ['--no-sandbox', '--disable-dev-shm-usage']});
});

after(async () => {
  await browser?.close();
  await new Promise(resolve => server ? server.close(resolve) : resolve());
});

async function openCamera(mode) {
  const page = await browser.newPage({viewport: {width: 390, height: 844}});
  await page.addInitScript(mode => {
    const state = window.cameraFixture = {mode, opens: 0, stops: 0, torch: false, requests: []};
    Object.defineProperty(navigator.mediaDevices, 'getUserMedia', {value: async constraints => {
      state.opens++;
      if (constraints.audio !== false) throw Error('Camera capture must not request audio');
      const canvas = document.createElement('canvas');
      canvas.width = 320;
      canvas.height = 240;
      const context = canvas.getContext('2d');
      let frame = 0;
      const paint = () => {
        context.fillStyle = state.torch ? '#eeeeee' : '#336699';
        context.fillRect(0, 0, 320, 240);
        context.fillStyle = '#222222';
        context.fillRect((frame++ * 4) % 280, 30, 40, 40);
      };
      paint();
      const stream = canvas.captureStream(20);
      const timer = setInterval(paint, 50);
      const track = stream.getVideoTracks()[0];
      const stop = track.stop.bind(track);
      const settings = track.getSettings.bind(track);
      track.getCapabilities = () => ({torch: mode !== 'unsupported'});
      track.getConstraints = () => ({facingMode: 'environment', width: {ideal: 1920}, height: {ideal: 1080}});
      track.getSettings = () => {
        if (mode === 'unreadable') throw Error('Torch state is not readable');
        const result = settings();
        if (mode !== 'missing') result.torch = mode === 'stale' ? false : state.torch;
        return result;
      };
      track.applyConstraints = async request => {
        state.requests.push(request);
        if (mode === 'rejected') throw Error('Torch command rejected');
        state.torch = request.advanced?.find(item => 'torch' in item)?.torch ?? request.torch;
        if (mode === 'paused') {
          for (const video of document.querySelectorAll('video')) {
            if (video.srcObject === stream) video.pause();
          }
        }
      };
      track.stop = () => {
        state.stops++;
        state.torch = false;
        clearInterval(timer);
        stop();
      };
      state.track = track;
      state.stream = stream;
      return stream;
    }});
  }, mode);
  await page.goto(base);
  await page.getByRole('button', {name: 'Open camera', exact: true}).click();
  await page.getByRole('button', {name: 'Capture photo', exact: true}).waitFor();
  await page.waitForFunction(() => {
    const track = window.cameraFixture.track;
    return track?.readyState === 'live' && [...document.querySelectorAll('video')].some(video => video.videoWidth > 0 && !video.paused);
  });
  return page;
}

async function expectLivePreview(page) {
  const state = await page.evaluate(() => ({
    stops: window.cameraFixture.stops,
    opens: window.cameraFixture.opens,
    readyState: window.cameraFixture.track.readyState,
    playing: [...document.querySelectorAll('video')].some(video => video.srcObject === window.cameraFixture.stream && video.videoWidth > 0 && !video.paused),
  }));
  assert.deepEqual(state, {stops: 0, opens: 1, readyState: 'live', playing: true});
  assert.equal(await page.getByRole('button', {name: 'Reopen camera', exact: true}).count(), 0);
}

for (const mode of ['stale', 'missing', 'unreadable', 'paused', 'rejected']) {
  test('Preview stays live and captures after a ' + mode + ' flashlight response', async () => {
    const page = await openCamera(mode);
    try {
      await page.getByRole('button', {name: /^(Flashlight off|Turn light on)$/}).click();
      await page.waitForFunction(() => window.cameraFixture.requests.length === 1);
      await page.waitForTimeout(300);
      await expectLivePreview(page);
      await page.getByRole('button', {name: 'Capture photo', exact: true}).click();
      await page.getByText('Captured photo', {exact: true}).waitFor();
      assert.equal(await page.evaluate(() => window.cameraFixture.stops), 1);
      assert.equal(await page.evaluate(() => window.cameraFixture.torch), false);
    } finally {
      await page.close();
    }
  });
}

test('Stale settings allow explicit on and off without reopening the camera', async () => {
  const page = await openCamera('stale');
  try {
    await page.getByRole('button', {name: /^(Flashlight off|Turn light on)$/}).click();
    await page.getByRole('button', {name: /^(Flashlight on|Turn light off)$/}).click();
    await expectLivePreview(page);
    const state = await page.evaluate(() => ({requests: window.cameraFixture.requests, torch: window.cameraFixture.torch}));
    assert.deepEqual(state.requests.map(request => request.advanced[0].torch), [true, false]);
    for (const request of state.requests) {
      assert.equal('facingMode' in request, false);
      assert.equal('width' in request, false);
      assert.equal('height' in request, false);
    }
    assert.equal(state.torch, false);
    await page.getByRole('button', {name: 'Back', exact: true}).click();
    await page.getByText('Camera closed', {exact: true}).waitFor();
    assert.equal(await page.evaluate(() => window.cameraFixture.stops), 1);
  } finally {
    await page.close();
  }
});

test('Unsupported cameras retain ordinary photo capture', async () => {
  const page = await openCamera('unsupported');
  try {
    assert.equal(await page.getByRole('button', {name: /^(Flashlight off|Turn light on)$/}).count(), 0);
    await expectLivePreview(page);
    await page.getByRole('button', {name: 'Capture photo', exact: true}).click();
    await page.getByText('Captured photo', {exact: true}).waitFor();
    assert.equal(await page.evaluate(() => window.cameraFixture.stops), 1);
  } finally {
    await page.close();
  }
});
