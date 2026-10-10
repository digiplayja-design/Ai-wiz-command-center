import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {registerFieldProof} from '../fieldproof/routes.mjs';
import {createFieldProofEmails} from '../fieldproof/emails.mjs';
import {fieldProofVoiceSessionGuard} from '../fieldproof/voice.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
const id = '22222222-2222-4222-8222-222222222222';
async function fixture(t) {
  const f = {profile: {id: owner, tier: 'enterprise', is_disabled: false}, queries: 0, calls: [], allowance: 0};
  const database = {
    from(table) {
      assert.equal(table, 'user_profiles');
      return {select(columns) {
        assert.equal(columns, 'id,tier,is_disabled');
        return {eq(column, value) {
          assert.equal(column, 'id'); assert.equal(value, owner);
          return {async maybeSingle() {f.queries++; return {data: f.profile, error: f.error};}};
        }};
      }};
    },
    async rpc(name, args) {
      f.calls.push({name, args});
      assert.equal(name, 'korlix_fieldproof_v1'); assert.equal(args.p_action, 'list');
      return {data: []};
    },
  };
  const requireUser = async req => req.headers.authorization === 'signed-in'
    ? {id: owner, user_metadata: {tier: 'enterprise', is_admin: true}} : null;
  const app = express(); app.use(express.json());
  registerFieldProof(app, {database, storageDatabase: {}, requireUser});
  const email = createFieldProofEmails({database, requireUser, autoStart: false});
  email.register(app);
  app.use('/api/live-convo/session', fieldProofVoiceSessionGuard({database, requireUser}));
  app.post('/api/live-convo/session', (req, res) => {
    f.allowance++; res.json(req.korlixFieldProofVoice || {regularVoice: true});
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(async () => {email.stop(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve));});
  const base = `http://127.0.0.1:${server.address().port}`;
  f.request = (path, method = 'GET', auth = 'signed-in') => fetch(base + path, {
    method, headers: {Authorization: auth, 'Content-Type': 'application/json', 'X-Tier': 'enterprise'},
    ...(method === 'GET' ? {} : {body: JSON.stringify({tier: 'enterprise', confirmed: true})}),
  });
  return f;
}

const gatedRoutes = [
  ['/api/fieldproof'], ['/api/fieldproof/jobs', 'POST'],
  [`/api/fieldproof/jobs/${id}`], [`/api/fieldproof/jobs/${id}`, 'PUT'],
  [`/api/fieldproof/jobs/${id}`, 'DELETE'],
  ...['approval', 'complete', 'reopen', 'photos', 'reviews'].map(action => [`/api/fieldproof/jobs/${id}/${action}`, 'POST']),
  [`/api/fieldproof/photos/${id}`, 'DELETE'], [`/api/fieldproof/photos/${id}/file`],
  [`/api/fieldproof/reviews/${id}`], ['/api/fieldproof/voice/draft', 'POST'],
  ['/api/fieldproof/email'], ['/api/fieldproof/email/settings', 'PUT'],
  [`/api/fieldproof/email/jobs/${id}`], [`/api/fieldproof/email/jobs/${id}`, 'PUT'],
  [`/api/fieldproof/email/jobs/${id}/prepare`, 'POST'],
  [`/api/fieldproof/email/deliveries/${id}`], [`/api/fieldproof/email/deliveries/${id}/report`],
  ...['approve', 'cancel', 'retry'].map(action => [`/api/fieldproof/email/deliveries/${id}/${action}`, 'POST']),
  ['/api/live-convo/session?fieldproof=1', 'POST'],
];

for (const tier of ['basic', 'pro', 'ultra', '', null, 'enterprise_trial']) {
  test(`${tier || 'missing tier'} cannot access FieldProof or spoof Enterprise`, async t => {
    const f = await fixture(t); f.profile.tier = tier;
    for (const [path, method] of gatedRoutes) {
      const response = await f.request(path, method);
      const data = await response.json();
      assert.equal(response.status, 402, `${path}: ${JSON.stringify(data)}`);
      assert.equal(data.code, 'fieldproof_enterprise_required');
      assert.equal(data.requiredTier, 'enterprise'); assert.equal(data.upgradeRequired, true);
      assert.equal(response.headers.get('cache-control'), 'no-store');
    }
    assert.equal(f.calls.length, 0, 'No private data, upload, export or AI handler ran');
    assert.equal(f.allowance, 0, 'No live-voice allowance was reserved');
  });
}
test('Enterprise access follows the current plan on every request', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/api/fieldproof')).status, 200);
  f.profile.tier = 'ultra';
  assert.equal((await f.request('/api/fieldproof')).status, 402);
  f.profile.tier = ' Enterprise ';
  assert.equal((await f.request('/api/fieldproof')).status, 200);
  const voice = await f.request('/api/live-convo/session?fieldproof=1', 'POST');
  assert.equal(voice.status, 200); assert.deepEqual(await voice.json(), {enabled: true});
  assert.equal(f.queries, 4); assert.equal(f.calls.length, 2); assert.equal(f.allowance, 1);
});
test('signed-out, inactive and unavailable accounts fail before feature work', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/api/fieldproof', 'GET', '')).status, 401);
  assert.equal(f.queries, 0);
  for (const profile of [null, {id: owner, tier: 'enterprise', is_disabled: true}, {id, tier: 'enterprise'}]) {
    f.profile = profile;
    assert.equal((await f.request('/api/fieldproof')).status, 403);
    assert.equal((await f.request('/api/live-convo/session?fieldproof=1', 'POST')).status, 403);
  }
  f.error = Error('private database credentials');
  const response = await f.request('/api/fieldproof/email');
  assert.equal(response.status, 503); assert.doesNotMatch(await response.text(), /credentials/);
  assert.equal(f.calls.length, 0); assert.equal(f.allowance, 0);
});
test('the FieldProof gate leaves general Live Convo and unsubscribe available', async t => {
  const f = await fixture(t); f.profile.tier = 'basic';
  const voice = await f.request('/api/live-convo/session', 'POST');
  assert.equal(voice.status, 200); assert.deepEqual(await voice.json(), {regularVoice: true});
  const unsub = await f.request('/api/fieldproof/email/unsubscribe', 'GET', '');
  assert.equal(unsub.status, 200); assert.match(await unsub.text(), /email preferences/);
  assert.equal(f.queries, 0); assert.equal(f.calls.length, 0);
});
