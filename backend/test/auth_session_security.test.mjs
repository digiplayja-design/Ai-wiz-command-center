import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Execute the real server authorization functions with an in-memory provider.
// No server import, provider credentials, real users, or network access.
const source = readFileSync(process.env.KORLIX_AUTH_SESSION_TEST_SOURCE || new URL('../server.js', import.meta.url), 'utf8');
const between = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const functions = between('function makeHttpError(', 'async function getOrCreateProfile(');
const refreshRoute = between('app.post("/api/auth/refresh"', 'app.post("/api/characters/select"');
const signoutRoute = between('app.post("/api/auth/signout"', 'app.get("/api/video-credits"');

function fixture({ status = 'active', disabled = false, explicit = true, lookupError = false, race = false, logoutError = false } = {}) {
  const calls = [], handlers = new Map();
  let device = status ? { id: 'device-row', user_id: 'alice', device_id: 'alice-phone', status } : null;
  const user = { id: 'alice', email: 'alice@example.test', user_metadata: { is_disabled: false } };
  const account = { id: 'alice', is_disabled: disabled, tier: 'basic' };
  const deviceInfo = { deviceId: 'alice-phone', explicitDeviceId: explicit, platform: 'fixture' };
  const database = {
    auth: {
      getUser: async token => { calls.push(['getUser', token]); return { data: { user } }; },
      admin: { signOut: async (token, scope) => { calls.push(['signOut', token, scope]); return { error: logoutError ? { message: 'offline provider failure' } : null }; } },
    },
    from(table) {
      const filters = []; let operation = 'read', value;
      const result = () => {
        calls.push([table, operation, filters, value]);
        if (lookupError && operation === 'read') return { data: null, error: new Error('offline storage failure') };
        if (table === 'user_profiles') return { data: account };
        if (operation === 'upsert') { device = { id: 'device-row', ...value }; return { data: device }; }
        if (operation === 'update') {
          if (race && filters.some(([k, v]) => k === 'status' && v === 'active')) return { data: null };
          if (device) device = { ...device, ...value };
        }
        return { data: device };
      };
      const chain = {
        select() { return chain; }, eq(k, v) { filters.push([k, v]); return chain; },
        update(v) { operation = 'update'; value = v; return chain; },
        upsert(v) { operation = 'upsert'; value = v; return chain; },
        maybeSingle: async () => result(), single: async () => result(),
        then(resolve, reject) { return Promise.resolve(result()).then(resolve, reject); },
      };
      return chain;
    },
  };
  const context = vm.createContext({
    supabaseAdmin: database,
    supabaseAuth: { auth: { refreshSession: async () => ({ data: { user, session: { access_token: 'rotated-token', refresh_token: 'rotated-refresh' } } }) } },
    getOrCreateProfile: async () => account,
    getRequestDeviceInfo: () => deviceInfo,
    getTierDeviceLimit: () => 2,
    getKorlixUserFacingError: error => error.message,
    sanitize: value => value,
    console: { warn() {} },
    app: { post: (path, handler) => handlers.set(path, handler) },
  });
  vm.runInContext(functions + '\n' + refreshRoute + '\n' + signoutRoute, context);
  const req = { headers: { authorization: 'Bearer original-token' }, body: { refresh_token: 'original-refresh' } };
  const response = () => ({ statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } });
  return { context, calls, handlers, req, response, deviceInfo, account, device: () => device };
}

test('an explicitly revoked device is rejected instead of swallowed', async () => {
  const f = fixture({ status: 'revoked' });
  await assert.rejects(f.context.getAuthenticatedUser(f.req), error => error.statusCode === 403);
  assert.equal(f.calls.some(c => c[1] === 'upsert'), false);
});

test('a verified legacy session with an unregistered stable device remains usable without creating a new device', async () => {
  const f = fixture({ status: null });
  assert.equal((await f.context.getAuthenticatedUser(f.req)).id, 'alice');
  assert.equal(f.calls.some(c => c[1] === 'upsert'), false);
  assert.equal(f.device(), null);
});

test('legacy clients without device headers remain compatible when account is enabled', async () => {
  const f = fixture({ status: 'revoked', explicit: false });
  assert.equal((await f.context.getAuthenticatedUser(f.req)).id, 'alice');
  assert.equal(f.calls.some(c => c[0] === 'device_sessions'), false);
});

test('disabled server-side account is denied with or without device headers despite editable metadata', async () => {
  for (const explicit of [true, false]) {
    const f = fixture({ disabled: true, explicit });
    await assert.rejects(f.context.getAuthenticatedUser(f.req), error => error.statusCode === 403);
    assert.equal(f.calls.some(c => c[0] === 'device_sessions'), false);
  }
});

test('account access lookup failure fails closed', async () => {
  const f = fixture({ lookupError: true });
  await assert.rejects(f.context.getAuthenticatedUser(f.req), error => error.statusCode === 503);
});

test('active explicit device works and a concurrent revocation cannot be overwritten by a touch', async () => {
  const active = fixture();
  assert.equal((await active.context.getAuthenticatedUser(active.req)).id, 'alice');
  const f = fixture({ race: true });
  await assert.rejects(f.context.getAuthenticatedUser(f.req), error => error.statusCode === 403);
  assert(f.calls.some(c => c[1] === 'update' && c[2].some(([k, v]) => k === 'status' && v === 'active')));
});

test('refresh may register a missing legacy row but never reactivate an existing revoked one', async () => {
  const f = fixture({ status: 'revoked' });
  await assert.rejects(f.context.touchActiveDeviceSession({ userId: 'alice', profile: f.account, deviceInfo: f.deviceInfo, allowRegister: true }), e => e.statusCode === 403);
  assert.equal(f.calls.some(c => c[1] === 'upsert'), false);
  const legacy = fixture({ status: null });
  const row = await legacy.context.touchActiveDeviceSession({ userId: 'alice', profile: legacy.account, deviceInfo: legacy.deviceInfo, allowRegister: true });
  assert.equal(row.status, 'active');
});

test('fresh password sign-in can reactivate a device but cannot enable a disabled account', async () => {
  const f = fixture({ status: 'revoked' });
  const row = await f.context.registerDeviceSession({ userId: 'alice', profile: f.account, deviceInfo: f.deviceInfo });
  assert.equal(row.status, 'active');
  const disabled = fixture({ disabled: true });
  await assert.rejects(disabled.context.registerDeviceSession({ userId: 'alice', profile: disabled.account, deviceInfo: disabled.deviceInfo }), e => e.statusCode === 403);
  assert.equal(disabled.calls.length, 0);
});

test('rejected refresh revokes the newly rotated provider session and never returns its tokens', async () => {
  for (const options of [{ status: 'revoked' }, { disabled: true }]) {
    const f = fixture(options), res = f.response();
    await f.handlers.get('/api/auth/refresh')(f.req, res);
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.session, undefined);
    assert.deepEqual(f.calls.filter(c => c[0] === 'signOut'), [['signOut', 'rotated-token', 'local']]);
  }
});

test('refresh tolerates a missing historical device row without consuming a device slot or revoking the provider session', async () => {
  for (const explicit of [true, false]) {
    const f = fixture({ status: null, explicit }), res = f.response();
    await f.handlers.get('/api/auth/refresh')(f.req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.session.access_token, 'rotated-token');
    assert.equal(res.body.deviceSession, null);
    assert.equal(f.calls.some(c => c[1] === 'upsert'), false);
    assert.equal(f.calls.some(c => c[0] === 'signOut'), false);
    assert.equal(f.device(), null);
  }
});

test('missing device compatibility never bypasses disabled accounts', async () => {
  const f = fixture({ status: null, disabled: true });
  await assert.rejects(f.context.getAuthenticatedUser(f.req), error => error.statusCode === 403);
  const res = f.response();
  await f.handlers.get('/api/auth/refresh')(f.req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.session, undefined);
});

test('successful refresh retains the active session', async () => {
  const f = fixture(), res = f.response();
  await f.handlers.get('/api/auth/refresh')(f.req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.session.access_token, 'rotated-token');
  assert.equal(f.calls.some(c => c[0] === 'signOut'), false);
});

test('signout revokes this provider session and the device, preserving other sessions', async () => {
  const f = fixture(), res = f.response();
  await f.handlers.get('/api/auth/signout')(f.req, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(f.calls.filter(c => c[0] === 'signOut'), [['signOut', 'original-token', 'local']]);
  assert.equal(f.device().status, 'revoked');
});

test('failed provider signout is not reported as success or hidden by a local-only revoke', async () => {
  const f = fixture({ logoutError: true }), res = f.response();
  await f.handlers.get('/api/auth/signout')(f.req, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.success, undefined);
  assert.equal(f.device().status, 'active');
});
