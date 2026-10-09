const assert = require('node:assert/strict');
const {before, after, test} = require('node:test');
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright');
const root = path.resolve('build/logo_studio_browser');
const artifacts = path.resolve(process.env.LOGO_BROWSER_ARTIFACTS || 'build/logo_browser_checks');
let server, browser, base;

before(async () => {
  await fs.mkdir(artifacts, {recursive: true});
  server = http.createServer(async (request, response) => {
    const pathname = decodeURIComponent(new URL(request.url, 'http://local').pathname);
    const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
    try {
      const data = await fs.readFile(file);
      const mime = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json'};
      response.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream'}).end(data);
    } catch (_) { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
  browser = await chromium.launch({headless: true, executablePath: process.env.KORLIX_CHROME_PATH,
    args: ['--no-sandbox', '--disable-dev-shm-usage']});
});
after(async () => {
  await browser?.close();
  await new Promise(resolve => server ? server.close(resolve) : resolve());
});

async function reveal(page, locator, direction = 1) {
  for (let i = 0; i < 24; i++) {
    if (await locator.count()) {
      try { await locator.first().scrollIntoViewIfNeeded(); return locator.first(); }
      catch (error) { if (!error.message.includes('not attached')) throw error; }
    }
    const size = page.viewportSize();
    await page.mouse.move(size.width * .8, size.height * .76);
    await page.mouse.wheel(0, (i < 12 ? direction : -direction) * 400);
    await page.waitForTimeout(120);
  }
  throw Error('Control not found: ' + locator);
}
// Browser semantics checks use keyboard activation; widget tests exercise touch.
async function click(page, name, {exact = true, direction = 1} = {}) {
  const control = await reveal(page, page.getByRole('button', {name, exact}), direction);
  await control.press('Enter');
  await page.mouse.move(2, 2);
  await page.waitForTimeout(150);
}
async function enterText(page, locator, value) {
  await locator.focus();
  // Let Flutter finish configuring its focused semantic input before typing.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText(value);
  await page.keyboard.press('Tab');
}
async function nav(page, name) {
  const tab = page.getByRole('tab', {name, exact: true});
  if (await tab.count()) await tab.press('Enter');
  else await page.getByRole('button', {name: new RegExp(name + ' Tab [1-5] of 5$')}).press('Enter');
  await page.mouse.click(2, 2);
  await page.waitForTimeout(150);
}
async function download(page, name, suffix) {
  const control = await reveal(page, page.getByRole('button', {name: new RegExp(name)}));
  const event = page.waitForEvent('download', {timeout: 45000});
  await control.press('Enter');
  const file = await event;
  assert.ok(file.suggestedFilename().endsWith(suffix), file.suggestedFilename());
  assert.equal(await file.failure(), null);
  return fs.readFile(await file.path());
}

for (const setup of [
  {id: 'phone', width: 390, height: 844, theme: 'korlix_blue'},
  {id: 'desktop', width: 1440, height: 1000, theme: 'pure_white'},
]) {
  test(setup.id + ': create, refine, save, reopen, and download real brand assets', {timeout: 120000}, async () => {
    const page = await browser.newPage({viewport: {width: setup.width, height: setup.height}, acceptDownloads: true});
    page.setDefaultTimeout(10000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(base + '/?theme=' + setup.theme);
      await page.getByRole('heading', {name: 'Logo Studio'}).waitFor();
      await page.screenshot({path: path.join(artifacts, setup.id + '-start.png')});
      const name = await reveal(page, page.getByRole('textbox', {name: 'Business or brand name', exact: true}));
      await enterText(page, name, 'Poppy & Pine');
      await click(page, 'Café & food');
      await click(page, /Create my logos/, {exact: false});
      await page.getByRole('button', {name: 'Customize', exact: true}).first().waitFor();
      await page.screenshot({path: path.join(artifacts, setup.id + '-ideas.png')});
      await page.getByRole('button', {name: 'Customize', exact: true}).first().press('Enter');
      await click(page, 'Edit logo shape Shape');
      // Exercise keyboard activation of the scrolled symbol picker as well.
      const symbol = await reveal(page, page.getByRole('button', {name: /Petal$/}));
      await symbol.press('Enter');
      await page.screenshot({path: path.join(artifacts, setup.id + '-shape.png')});
      await click(page, 'Edit typography Type');
      await click(page, 'Wide');
      await click(page, 'Edit colors Color');
      await click(page, 'Ocean & pearl');
      await page.screenshot({path: path.join(artifacts, setup.id + '-color.png')});
      await click(page, 'Edit brand text Brand');
      const edit = await reveal(page, page.getByRole('textbox', {name: 'Brand name', exact: true}));
      await enterText(page, edit, 'Poppy & Pine Studio');
      await page.getByRole('button', {name: 'Save logo project', exact: true}).press('Enter');
      await nav(page, 'Saved');
      await click(page, /Open project/);
      await page.getByRole('textbox', {name: 'Brand name', exact: true}).waitFor();
      if (setup.id === 'phone') {
        await page.setViewportSize({width: 390, height: 440});
        await page.waitForTimeout(250);
        await reveal(page, page.getByRole('textbox', {name: 'Brand name', exact: true}));
        // Flutter populates the HTML editing value when the semantic field is focused.
        await page.getByRole('textbox', {name: 'Brand name', exact: true}).focus();
        await page.waitForFunction(() => document.activeElement?.value === 'Poppy & Pine Studio');
        await page.setViewportSize({width: 390, height: 844});
        await page.waitForTimeout(250);
      }
      await page.screenshot({path: path.join(artifacts, setup.id + '-editor.png')});
      await nav(page, 'Kit');
      await page.screenshot({path: path.join(artifacts, setup.id + '-kit.png')});
      const project = JSON.parse((await download(page, 'Project backup', '.korlix-logo.json')).toString());
      assert.equal(project.name, 'Poppy & Pine Studio');
      assert.equal(project.mark, 'Petal');
      assert.equal(project.typeface, 'Wide');
      assert.equal(project.primary, '135C73');
      const svg = (await download(page, 'Download SVG', '.svg')).toString();
      assert.ok(svg.includes('Poppy &amp; Pine Studio'));
      assert.ok(svg.includes('#135C73'));
      assert.ok(svg.includes('<path'));
      const png = await download(page, 'Download PNG', '.png');
      assert.equal(png.readUInt32BE(16), 2400);
      assert.equal(png.readUInt32BE(20), 1600);
      const kit = await download(page, 'Download brand kit', '.zip');
      assert.equal(kit.subarray(0, 2).toString(), 'PK');
      assert.ok(kit.length > 10000);
      assert.deepEqual(errors, []);
    } catch (error) {
      await page.screenshot({path: path.join(artifacts, setup.id + '-failure.png')});
      console.error(error.message);
      console.error(await page.locator('body').ariaSnapshot());
      throw error;
    } finally { await page.close(); }
  });
}
