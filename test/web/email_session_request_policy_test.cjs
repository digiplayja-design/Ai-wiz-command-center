const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const policy = require('../../website/nova-email/session-request-policy.js');

const now = Date.now();
const token = (user, session, remaining = 3600) => [
  Buffer.from('{"alg":"HS256"}').toString('base64url'),
  Buffer.from(JSON.stringify({iss: 'https://test.supabase.co/auth/v1', sub: user,
    session_id: session, exp: Math.floor(now / 1000) + remaining})).toString('base64url'),
  'test-signature',
].join('.');

test('access and refresh credentials are blocked before any untrusted request', async () => {
  const urls = [
    'https://attacker.example/api/auth/refresh',
    'http://chee-chai-chee-backend.onrender.com/api/auth/refresh',
    'https://chee-chai-chee-backend.onrender.com.attacker.example/api/me',
    'https://chee-chai-chee-backend.onrender.com@attacker.example/api/me',
    'https://attacker@chee-chai-chee-backend.onrender.com/api/me',
    'https://chee-chai-chee-backend.onrender.com:8443/api/me',
    'https://chee-chai-chee-backend.onrender.com/portals/unsafe',
    'https://chee-chai-chee-backend.onrender.com/api/../portals/unsafe',
    'https://chee-chai-chee-backend.onrender.com/api/me#token',
    '//attacker.example/api/me',
    'javascript:alert(1)',
  ];
  let requests = 0;
  for (const url of urls) {
    await assert.rejects(policy.request(url, {
      method: 'POST',
      headers: {Authorization: 'Bearer private-access-token'},
      body: JSON.stringify({refresh_token: 'private-refresh-token'}),
    }, () => { requests++; }), /secure KORLIX API/);
  }
  assert.equal(requests, 0);
});

test('the trusted API retains auth and refresh bodies but cannot follow redirects', async () => {
  const options = {
    method: 'POST', headers: {Authorization: 'Bearer private-access-token'},
    body: JSON.stringify({refresh_token: 'private-refresh-token'}),
    redirect: 'follow', credentials: 'include', referrerPolicy: 'unsafe-url',
  };
  const result = await policy.request(`${policy.apiOrigin}/api/auth/refresh`, options,
    async (url, sent) => {
      assert.equal(url, `${policy.apiOrigin}/api/auth/refresh`);
      assert.equal(sent.headers.Authorization, options.headers.Authorization);
      assert.equal(sent.body, options.body);
      assert.equal(sent.redirect, 'error');
      assert.equal(sent.credentials, 'omit');
      assert.equal(sent.referrerPolicy, 'no-referrer');
      return {ok: true};
    });
  assert.equal(result.ok, true);
});

test('Email Center loads the boundary first and routes every fetch through it', () => {
  const root = path.join(__dirname, '../../website/nova-email');
  const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  assert.ok(html.indexOf('/nova-email/session-request-policy.js') < html.indexOf('/nova-email/app.js'));
  assert.doesNotMatch(app, /\bfetch\s*\(/);
  assert.doesNotMatch(app, /getItem\(["']korlixNovaEmailApiBase/);
  assert.equal((app.match(/KorlixEmailRequestPolicy\.request\(/g) || []).length, 3);
});

test('a longer-lived cached token cannot select another account or signed-out session', () => {
  const accountA = token('person-a', 'login-a', 7200);
  const accountB = token('person-b', 'login-b');
  assert.equal(policy.chooseSessionToken(accountB, [accountA], now), accountB);
  assert.equal(policy.chooseSessionToken('', [accountA], now), '');
  assert.equal(policy.chooseSessionToken('invalid', [accountA], now), '');
  const newLoginA = token('person-a', 'new-login-a');
  assert.equal(policy.chooseSessionToken(newLoginA, [accountA], now), newLoginA);
});

test('rotation within the current login remains available after the main token expires', () => {
  const expired = token('person-a', 'login-a', -20);
  const rotated = token('person-a', 'login-a', 7200);
  assert.equal(policy.chooseSessionToken(expired, [rotated], now), rotated);
  assert.equal(policy.chooseSessionToken(expired, [token('person-b', 'login-b')], now), '');
});

test('only the main Flutter login keys can authorize a standalone Email Center session', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../website/nova-email/app.js'), 'utf8');
  const stored = new Map([
    ['access_token', JSON.stringify(token('old-person', 'old-session'))],
    ['other.korlix_access_token', JSON.stringify(token('old-person', 'old-session'))],
    ['korlixNovaEmailAccessTokenV2', token('old-person', 'old-session')],
  ]);
  const context = {localStorage: {getItem: key => stored.get(key) ?? null},
    korlixParseStoredValueV2: value => value === null ? null : JSON.parse(value)};
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('function korlixMainStoredStringV3('),
    source.indexOf('function korlixChooseAccessTokenV3(')), context);
  const read = () => context.korlixMainStoredStringV3(['korlix_access_token', 'access_token', 'accessToken']);
  assert.equal(read(), '');
  const current = token('current-person', 'current-session');
  stored.set('flutter.korlix_access_token', JSON.stringify(current));
  assert.equal(read(), current);
  stored.delete('flutter.korlix_access_token');
  assert.equal(read(), '');
});

function sessionHarness() {
  const source = fs.readFileSync(path.join(__dirname, '../../website/nova-email/app.js'), 'utf8');
  let mainToken = token('person-a', 'login-a'), sent = 0, reset = 0, finish;
  const context = {
    APP: {token: mainToken}, AbortController, setTimeout, clearTimeout,
    KorlixEmailRequestPolicy: {...policy, request: async () => {
      sent++;
      return new Promise(resolve => { finish = resolve; });
    }},
    korlixMainStoredStringV3: () => mainToken,
    korlixResetEmailSessionV3: () => { context.APP.token = null; reset++; },
    document: {querySelectorAll: () => []},
    renderDashboard() {}, setMessage() {}, els: {},
  };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('function korlixMainSessionScopeV5('),
    source.indexOf('function korlixStaleRefreshErrorV3(')), context);
  vm.runInContext(source.slice(source.indexOf('async function korlixFetchWithTimeoutV2('),
    source.indexOf('function korlixResponseErrorV2(')), context);
  return {context, change: value => {mainToken = value;}, sent: () => sent,
    reset: () => reset, finish: () => finish({ok: true})};
}

test('actual Email Center transport refuses an account switch before dispatch', async () => {
  const h = sessionHarness();
  h.change(token('person-b', 'login-b'));
  await assert.rejects(h.context.korlixFetchWithTimeoutV2(`${policy.apiOrigin}/api/me`), /login changed/);
  assert.equal(h.sent(), 0);
  assert.equal(h.reset(), 1);
  assert.equal(h.context.APP.token, null);
});

test('actual Email Center transport rejects an in-flight response after logout', async () => {
  const h = sessionHarness();
  const request = h.context.korlixFetchWithTimeoutV2(`${policy.apiOrigin}/api/me`);
  assert.equal(h.sent(), 1);
  h.change(''); h.finish();
  await assert.rejects(request, /login changed/);
  assert.equal(h.reset(), 1);
});


test('Email Center uses the main app device when a stale Email-only device exists', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../website/nova-email/app.js'), 'utf8');
  const main = {korlix_device_id: 'main-device', korlix_device_label: 'Main browser'};
  const context = {
    APP: {token: 'current-token'},
    firstDefined: (...values) => values.find(value => value !== undefined && value !== null && value !== ''),
    korlixMainStoredStringV3: names => main[names[0]] || '',
    korlixOwnSessionValueV2: () => 'stale-email-device',
    korlixStoredStringV2: () => 'other-legacy-device',
  };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('function korlixEnsureDeviceV2('),
    source.indexOf('async function korlixFetchWithTimeoutV2(')), context);
  let headers = context.korlixAuthHeadersV2();
  assert.equal(headers['X-Korlix-Device-Id'], 'main-device');
  assert.equal(headers['X-Korlix-Device-Label'], 'Main browser');
  assert.equal(headers.Authorization, 'Bearer current-token');
  main.korlix_device_id = 'replacement-main-device';
  headers = context.korlixAuthHeadersV2();
  assert.equal(headers['X-Korlix-Device-Id'], 'replacement-main-device');
});
