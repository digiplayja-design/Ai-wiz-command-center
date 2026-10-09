import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import express from 'express';
import { registerEnterpriseBusinessAccess } from '../enterprise_business_access.mjs';
import { registerInventory } from '../inventory/routes.mjs';
import { registerBookkeeping } from '../bookkeeping/routes.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
const business = '22222222-2222-4222-8222-222222222222';
let profile, storageError, queries, calls, server, base;
const database = {
  from(table) {
    assert.equal(table, 'user_profiles');
    return { select(columns) {
      assert.equal(columns, 'id,tier,is_disabled');
      return { eq(column, value) {
        assert.equal(column, 'id'); assert.equal(value, owner);
        return { async maybeSingle() {
          queries++; return { data: profile, error: storageError };
        } };
      } };
    } };
  },
  async rpc(name, args) {
    calls.push({ name, args });
    if (name === 'korlix_tax_prep_v1' && args.p_action === 'create') {
      return { data: { workspace: {
        id: args.p_id, tax_year: args.p_data.year, country: 'US', version: 1,
        business_ids: [], books: [], data: args.p_data.data,
      } } };
    }
    return { data: { businesses: [], workspaces: [], items: [] } };
  },
};
test.before(async () => {
  const app = express(); app.use(express.json());
  const requireUser = async req => req.headers.authorization === 'signed-in'
    ? { id: owner, user_metadata: { tier: 'enterprise' } } : null;
  registerEnterpriseBusinessAccess(app, { database, requireUser });
  registerInventory(app, { database, requireUser });
  registerBookkeeping(app, { database, requireUser });
  for (const path of ['/api/scheduling', '/api/receipt-wiz']) {
    app.get(path, (_req, res) => res.json({ available: true }));
  }
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
test.beforeEach(() => {
  profile = { id: owner, tier: 'enterprise', is_disabled: false };
  storageError = null; queries = 0; calls = [];
});
test.after(async () => {
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
});
const request = (path, method = 'GET', body, auth = 'signed-in') => fetch(base + path, {
  method, headers: { Authorization: auth, 'Content-Type': 'application/json' },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});

for (const tier of ['basic', 'pro', 'ultra', '', null]) {
  test(`${tier || 'missing'} cannot use business tools or forge Enterprise access`, async () => {
    profile.tier = tier;
    const routes = [
      ['/api/inventory'], ['/api/inventory/search'], ['/api/inventory/export'],
      ['/api/inventory/changes', 'POST'], ['/api/inventory/vision', 'POST'],
      [`/api/inventory/items/${business}/photo`, 'POST'],
      ['/api/bookkeeping/businesses'], ['/api/bookkeeping/businesses', 'POST'],
      [`/api/bookkeeping/businesses/${business}/overview`],
      [`/api/bookkeeping/businesses/${business}/entries`, 'POST'],
      [`/api/bookkeeping/businesses/${business}/receipts`, 'POST'],
      [`/api/bookkeeping/businesses/${business}/reports`],
      [`/api/bookkeeping/businesses/${business}/export`],
      [`/api/bookkeeping/businesses/${business}/voice/context`],
      [`/api/bookkeeping/businesses/${business}/statements/preview`, 'POST'],
    ];
    for (const [path, method = 'GET'] of routes) {
      const res = await request(path, method, method === 'GET' ? undefined : { tier: 'enterprise' });
      const data = await res.json();
      assert.equal(res.status, 402, `${path}: ${JSON.stringify(data)}`);
      assert.equal(data.requiredTier, 'enterprise'); assert.equal(data.upgradeRequired, true);
      assert.equal(res.headers.get('cache-control'), 'no-store');
    }
    assert.equal(calls.length, 0, 'No data, upload or AI handler ran');
  });
}
test('Enterprise reaches the existing Inventory and Bookkeeping routes', async () => {
  for (const path of ['/api/inventory', '/api/bookkeeping/businesses']) {
    assert.equal((await request(path)).status, 200);
  }
  assert.deepEqual(calls.map(c => c.name), [
    'korlix_inventory_v1', 'korlix_inventory_v1', 'korlix_bookkeeping_v1',
  ]);
});
test('an upgrade or downgrade takes effect on the next request', async () => {
  assert.equal((await request('/api/inventory')).status, 200);
  profile.tier = 'ultra';
  assert.equal((await request('/api/inventory')).status, 402);
  profile.tier = ' Enterprise ';
  assert.equal((await request('/api/inventory')).status, 200);
  assert.equal(queries, 3);
});
test('disabled, missing and mismatched profiles fail closed', async () => {
  for (const value of [null, { ...profile, is_disabled: true }, { ...profile, id: business }]) {
    profile = value;
    assert.equal((await request('/api/bookkeeping/businesses')).status, 403);
  }
  assert.equal(calls.length, 0);
});
test('signed-out users and failed profile storage cannot run tool handlers', async () => {
  assert.equal((await request('/api/inventory', 'GET', undefined, 'invalid')).status, 401);
  assert.equal(queries, 0);
  storageError = new Error('private database detail');
  const res = await request('/api/bookkeeping/businesses');
  assert.equal(res.status, 503); assert(!JSON.stringify(await res.json()).includes('private database'));
  assert.equal(calls.length, 0);
});
test('free scheduling, Receipt Wiz and personal Tax Prep stay available', async () => {
  profile.tier = 'basic';
  for (const path of ['/api/scheduling', '/api/receipt-wiz', '/api/bookkeeping/tax-prep']) {
    assert.equal((await request(path)).status, 200);
  }
  assert.equal(queries, 0);
});
test('linking business books requires Enterprise; personal organizers do not', async () => {
  profile.tier = 'ultra';
  for (const path of ['/api/bookkeeping/tax-prep', `/api/bookkeeping/tax-prep/${business}/books`]) {
    assert.equal((await request(path, 'POST', { business_ids: [business] })).status, 402);
  }
  assert.equal(calls.length, 0);
  assert.equal((await request('/api/bookkeeping/tax-prep', 'POST', {
    business_ids: [], year: 2026, request_key: business,
  })).status, 201);
});
test('production installs the access gate before either feature route', async () => {
  const source = await readFile(new URL('../server.js', import.meta.url), 'utf8');
  const gate = source.indexOf('registerEnterpriseBusinessAccess(app,');
  assert(gate > 0);
  assert(gate < source.indexOf('registerInventory(app,'));
  assert(gate < source.indexOf('registerBookkeeping(app,'));
});
