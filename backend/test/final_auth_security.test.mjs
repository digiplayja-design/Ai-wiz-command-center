import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import crypto from 'node:crypto';
import vm from 'node:vm';
import express from 'express';
import {publicApiErrorHandler} from '../security/http_errors.mjs';
import {createAccountRequestLimiter} from '../security/account_request_limiter.mjs';

const source = readFileSync(new URL('../server.js', import.meta.url), 'utf8');
function section(start, end) {
  const offset = source.indexOf(start);
  assert(offset >= 0 && source.indexOf(end, offset) > offset);
  return source.slice(offset, source.indexOf(end, offset));
}
const auth = section('function makeHttpError(', 'async function getOrCreateProfile(');
const customAuth = section('async function korlixCustomAccessResolveUserV1(', 'function korlixCustomAccessSupportEmailV1(')
  + section('async function korlixCustomAccessRequireUserV1(', 'app.get("/api/custom-access/me"');
const deletionRoute = section('app.post("/api/account/delete-request"', 'async function createKorlixImprovedImage(');
const reset = section('function getPasswordResetRedirectUrl(', 'function secretMatches(');
const res = () => ({statusCode: 200, status(code) {this.statusCode = code; return this;}, json(body) {this.body = body; return this;}});

function fixture({disabled = false, device = 'active', storageError = false} = {}) {
  const calls = [], routes = new Map();
  const database = {
    auth: {getUser: async token => ({data: {user: token === 'valid' ? {id: 'alice', email: 'alice@example.test'} : null}})},
    from(table) {
      const chain = {
        select() {return chain;}, eq() {return chain;}, update() {return chain;},
        async maybeSingle() {
          return {data: table === 'user_profiles' ? {is_disabled: disabled} : device ? {id: 'device-row', status: device} : null,
            error: storageError ? new Error('private database diagnostics') : null};
        },
      };
      return chain;
    },
    async rpc(name, payload) {calls.push({name, payload}); return {data: {id: 'deletion-request', status: 'requested'}};},
  };
  const context = vm.createContext({
    supabaseAdmin: database, getRequestDeviceInfo: () => ({deviceId: 'alice-phone', explicitDeviceId: true}),
    getKorlixUserFacingError: error => error.message,
    app: {post: (path, handler) => routes.set(path, handler)},
  });
  vm.runInContext(auth + customAuth + deletionRoute, context);
  return {context, calls, routes, req: {headers: {authorization: 'Bearer valid'}, body: {}}};
}

test('Custom Access denies disabled and revoked devices through the real shared auth guard', async () => {
  for (const options of [{disabled: true}, {device: 'revoked'}]) {
    const f = fixture(options), response = res();
    assert.equal(await f.context.korlixCustomAccessRequireUserV1(f.req, response), null);
    assert.equal(response.statusCode, 403);
  }
});

test('Custom Access preserves legacy missing-device compatibility and fails closed on access storage outages', async () => {
  const legacy = fixture({device: null});
  assert.equal((await legacy.context.korlixCustomAccessRequireUserV1(legacy.req, res())).id, 'alice');
  const offline = fixture({storageError: true}), response = res();
  assert.equal(await offline.context.korlixCustomAccessRequireUserV1(offline.req, response), null);
  assert.equal(response.statusCode, 503);
  assert(!JSON.stringify(response.body).includes('private database'));
});

test('all legacy feature auth helpers use the same verified account and device principal', async () => {
  for (const [start, end] of [
    ['async function korlixLiveConvoResolveUserV1(', 'async function korlixLiveConvoSafetyIdentifierV1('],
    ['async function korlixI2vResolveUserV1(', 'async function korlixI2vResolveTierV1('],
  ]) {
    const f = fixture({disabled: true});
    vm.runInContext(section(start, end), f.context);
    const name = start.match(/function (\w+)/)[1];
    await assert.rejects(f.context[name](f.req), error => error.statusCode === 403);
  }
});

test('deletion requests cannot be forged anonymously or by disabled/revoked sessions', async () => {
  for (const options of [{}, {disabled: true}, {device: 'revoked'}]) {
    const f = fixture(options), response = res();
    if (!options.disabled && !options.device) f.req.headers = {};
    f.req.body.email = 'victim@example.test';
    await f.routes.get('/api/account/delete-request')(f.req, response);
    assert.equal(response.statusCode, Object.keys(options).length ? 403 : 401);
    assert.equal(f.calls.length, 0);
  }
});

test('deletion request RPC uses only the verified user identity and bounded reason', async () => {
  const f = fixture(), response = res();
  f.req.body = {user_id: 'victim', email: 'victim@example.test', reason: ' Please delete my account. '};
  await f.routes.get('/api/account/delete-request')(f.req, response);
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(JSON.stringify(f.calls)), [{name: 'korlix_request_account_deletion', payload: {
    p_user_id: 'alice', p_email: 'alice@example.test', p_reason: 'Please delete my account.',
  }}]);
  f.req.body.reason = 'x'.repeat(2001);
  const oversized = res();
  await f.routes.get('/api/account/delete-request')(f.req, oversized);
  assert.equal(oversized.statusCode, 400);
  assert.equal(f.calls.length, 1);
});

test('password reset ignores attacker-controlled origin headers but honors explicit configuration', () => {
  const context = vm.createContext({process: {env: {}}, crypto, passwordResetAttempts: new Map()});
  vm.runInContext(reset, context);
  const poisoned = {protocol: 'http', get: () => 'attacker.example'};
  assert.equal(context.getPasswordResetRedirectUrl(poisoned), 'https://chee-chai-chee-backend.onrender.com/reset-password');
  context.process.env.KORLIX_PASSWORD_RESET_REDIRECT_URL = 'https://trusted.example/reset-password';
  assert.equal(context.getPasswordResetRedirectUrl(poisoned), 'https://trusted.example/reset-password');
});

test('reset budgets survive IP rotation, expire, and cannot grow memory without bounds', () => {
  let now = 0;
  const attempts = new Map();
  const context = vm.createContext({process: {env: {}}, crypto, Date: {now: () => now}, passwordResetAttempts: attempts});
  vm.runInContext(reset, context);
  for (let i = 0; i < 5; i++) assert.equal(context.checkPasswordResetRateLimit({ip: `192.0.2.${i}`}, 'Alice@example.test'), true);
  assert.equal(context.checkPasswordResetRateLimit({ip: '192.0.2.99'}, 'alice@example.test'), false);
  assert(!JSON.stringify([...attempts.keys()]).includes('example.test'));
  for (let i = 0; i < 5000; i++) context.checkPasswordResetRateLimit({}, `person${i}@example.test`);
  assert.equal(attempts.size, 5000);
  assert.equal(context.checkPasswordResetRateLimit({}, 'overflow@example.test'), false);
  now = 15 * 60 * 1000;
  assert.equal(context.checkPasswordResetRateLimit({}, 'alice@example.test'), true);
  assert.equal(attempts.size, 1);
});

test('authenticated side-effect budgets expire and do not evict active accounts at capacity', () => {
  let now = 0;
  const consume = createAccountRequestLimiter({windowMs: 1000, maxAttempts: 2, maxAccounts: 2, now: () => now});
  consume('alice'); consume('alice');
  assert.throws(() => consume('alice'), error => error.statusCode === 429 && error.retryAfter === 1);
  consume('bob');
  assert.throws(() => consume('charlie'), error => error.statusCode === 503);
  assert.throws(() => consume('alice'), error => error.statusCode === 429);
  now = 1000;
  assert.doesNotThrow(() => consume('alice'));
});

test('custom access mail requests stop before persistence and email when their verified actor budget is exhausted', async () => {
  const handlers = new Map(), writes = [], emails = [];
  const context = vm.createContext({
    app: {post: (path, handler) => handlers.set(path, handler)},
    korlixCustomAccessRequireUserV1: async () => ({id: 'alice', email: 'alice@example.test'}),
    consumeCustomAccessRequest: createAccountRequestLimiter({windowMs: 3600000, maxAttempts: 3}),
    korlixCustomAccessSupabaseClientV1: () => ({from() {
      const chain = {insert(value) {writes.push(value); return chain;}, select() {return chain;}, single: async () => ({data: {id: 'request'}})};
      return chain;
    }}),
    korlixCustomAccessEmailNormV1: value => String(value || '').trim().toLowerCase(),
    korlixCustomAccessStringV1: value => String(value || '').trim(),
    korlixCustomAccessSendSupportEmailV1: async value => {emails.push(value); return {ok: true};},
    korlixCustomAccessSupportEmailV1: () => 'support@example.test',
  });
  vm.runInContext(section('app.post("/api/custom-access/request-code"', 'app.post("/api/custom-access/redeem-code"'), context);
  for (let i = 0; i < 4; i++) {
    const response = {...res(), set() {return this;}};
    await handlers.get('/api/custom-access/request-code')({body: {email: 'victim@example.test', notes: 'x'.repeat(4000)}}, response);
    assert.equal(response.statusCode, i < 3 ? 200 : 429);
  }
  assert.equal(writes.length, 3);
  assert.equal(emails.length, 3);
  assert(writes.every(row => row.user_id === 'alice' && row.email === 'alice@example.test' && row.notes.length === 2000));
});

test('real HTTP parser errors return safe JSON without request bodies or stack traces', async () => {
  const app = express();
  app.use(express.json({limit: '64b'}));
  app.post('/api/private', (_req, response) => response.json({ok: true}));
  app.get('/api/failure', () => {throw new Error('private-secret provider diagnostic');});
  app.use(publicApiErrorHandler);
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    for (const [path, options, expected] of [
      ['/api/private', {method: 'POST', headers: {'content-type': 'application/json'}, body: '{"private-secret":'}, 400],
      ['/api/private', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({data: 'x'.repeat(100)})}, 413],
      ['/api/failure', {}, 500],
    ]) {
      const response = await fetch(base + path, options);
      assert.equal(response.status, expected);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      const body = await response.json();
      assert.equal(body.ok, false);
      assert(!JSON.stringify(body).includes('private-secret'));
      assert.equal(body.stack, undefined);
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
