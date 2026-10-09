import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {registerLogoJobs} from '../logo_jobs.mjs';

const brief = {name: 'Poppy & Pine', primary: '135C73', secondary: 'F5B575', paper: 'F4F8F9'};
const payload = {clientRequestId: 'request_12345678', prompt: 'A botanical logo', logoBrief: brief};
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => {let resolve, reject; const promise = new Promise((a, b) => {resolve = a; reject = b;}); return {promise, resolve, reject};};

async function fixture(t) {
  const app = express(), scheduled = [], calls = [], diagnostics = [], completion = deferred();
  let clock = Date.now();
  app.use(express.json());
  registerLogoJobs(app, {
    requireUser: async req => {
      if (!req.headers.authorization) throw Object.assign(Error('Sign in'), {statusCode: 401});
      return {id: req.headers.authorization};
    },
    execute: async request => {calls.push(request); return completion.promise;},
    schedule: fn => scheduled.push(fn), now: () => clock, log: value => diagnostics.push(value),
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => {server.close(resolve); server.closeAllConnections();}));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function request(method, path, body, owner = 'alice') {
    const response = await fetch(base + path, {method,
      headers: {'Content-Type': 'application/json', ...(owner ? {Authorization: owner} : {})},
      ...(body ? {body: JSON.stringify(body)} : {})});
    return {status: response.status, headers: response.headers, body: await response.json()};
  }
  return {calls, scheduled, completion, diagnostics,
    post: (body = payload, owner) => request('POST', '/api/logo/jobs', body, owner),
    get: (id, owner) => request('GET', `/api/logo/jobs/${id}`, null, owner),
    advance: ms => {clock += ms;},
  };
}

test('HTTP jobs return before generation, report real stages and return the result', async t => {
  const f = await fixture(t), started = await f.post();
  assert.equal(started.status, 202);
  assert.equal(started.headers.get('cache-control'), 'no-store');
  assert.equal(started.body.status, 'queued');
  assert.equal(f.calls.length, 0);
  f.scheduled.shift()();
  assert.equal(f.calls.length, 1);
  f.calls[0].onStage('rendering');
  const current = await f.get(started.body.jobId);
  assert.equal(current.body.stage, 'rendering');
  assert.equal(current.body.ownerId, undefined);
  assert.equal(current.body.result, undefined);
  f.calls[0].onStage('finishing');
  assert.equal((await f.get(started.body.jobId)).body.stage, 'finishing');
  f.completion.resolve({generationId: 'result1', imageDataUrl: 'fixture', creditsUsed: 1});
  await tick();
  const done = await f.get(started.body.jobId);
  assert.equal(done.body.status, 'completed');
  assert.equal(done.body.result.generationId, 'result1');
  assert.equal(done.body.result.creditsUsed, 1);
  assert.equal(f.calls[0].body.logoBrief.name, brief.name);
  assert.equal(f.calls[0].body.clientRequestId, undefined);
});

test('lost start replies and repeated polling never start or charge a second generation', async t => {
  const f = await fixture(t), first = await f.post();
  assert.equal((await f.post()).body.jobId, first.body.jobId);
  assert.equal((await f.post({...payload, clientRequestId: 'reopened_123456'})).body.jobId, first.body.jobId);
  assert.equal(f.scheduled.length, 1);
  f.scheduled.shift()();
  let credits = 0;
  f.completion.promise.then(() => credits++);
  f.completion.resolve({generationId: 'result1'});
  await tick();
  assert.equal((await f.post()).status, 200);
  await f.get(first.body.jobId);
  await f.get(first.body.jobId);
  assert.equal(credits, 1);
  assert.equal(f.calls.length, 1);
  assert.equal(f.scheduled.length, 0);
});

test('owners are isolated and changed briefs cannot reuse an in-flight request', async t => {
  const f = await fixture(t), first = await f.post();
  assert.equal((await f.get(first.body.jobId, 'bob')).status, 404);
  assert.equal((await f.get(first.body.jobId, '')).status, 401);
  assert.equal((await f.post(payload, '')).status, 401);
  assert.equal((await f.post({...payload, prompt: 'different'})).status, 409);
  assert.equal((await f.post({...payload, clientRequestId: 'another_request', prompt: 'different'})).status, 409);
  const other = await f.post(payload, 'bob');
  assert.equal(other.status, 202);
  assert.notEqual(other.body.jobId, first.body.jobId);
});

test('input validation and bounded concurrency reject work before provider spend', async t => {
  const f = await fixture(t);
  for (const body of [{}, {...payload, clientRequestId: '../bad'}, {...payload, logoBrief: {}},
    {...payload, prompt: 'x'.repeat(12001)}, {...payload, language: []}]) {
    assert.equal((await f.post(body)).status, 400);
  }
  assert.equal(f.scheduled.length, 0);
  for (let i = 0; i < 8; i++) assert.equal((await f.post(payload, `user${i}`)).status, 202);
  assert.equal((await f.post(payload, 'user9')).status, 503);
  assert.equal(f.scheduled.length, 8);
  assert.equal(f.calls.length, 0);
});

test('terminal failure reports safe text and is not resubmitted by the same request', async t => {
  const f = await fixture(t), first = await f.post();
  f.scheduled.shift()();
  f.completion.reject(Object.assign(Error('secret provider detail'), {statusCode: 500}));
  await tick();
  const failed = await f.get(first.body.jobId);
  assert.equal(failed.body.status, 'failed');
  assert.doesNotMatch(JSON.stringify(failed.body), /secret/);
  assert.doesNotMatch(JSON.stringify(f.diagnostics), /secret/);
  assert.equal((await f.post()).body.status, 'failed');
  assert.equal(f.calls.length, 1);
  assert.equal(f.scheduled.length, 0);
});

test('finished results expire while running jobs remain available', async t => {
  const f = await fixture(t), first = await f.post();
  f.scheduled.shift()();
  f.advance(31 * 60 * 1000);
  assert.equal((await f.get(first.body.jobId)).status, 200);
  f.completion.resolve({generationId: 'result1'});
  await tick();
  f.advance(31 * 60 * 1000);
  assert.equal((await f.get(first.body.jobId)).status, 404);
});
