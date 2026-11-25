import assert from 'node:assert/strict';
import test from 'node:test';
import { createHandler } from '../../supabase/functions/korlix-fax/handler.mjs';
import { activityCsv } from '../../website/fax-number/fax-activity.js';

const url = 'https://fax.example.test/korlix-fax/activity?';
const owner = crypto.randomUUID();
const time = '2024-02-29T23:59:59.999871+00:00';
const records = Array.from({ length: 51 }, (_, index) => ({
  id: crypto.randomUUID(), updated_at: time, direction: 'outbound', sender: '+12125550123',
  recipient: '+13105550134', name: 'Job ' + index + '.pdf', status: 'delivered', pages: 1,
})).sort((left, right) => right.id.localeCompare(left.id));

test('company activity uses the same UTC month and owner for totals and keyset-paginated receipts', async () => {
  let rpcCalls = 0;
  const lastVisible = records[49];
  const handler = createHandler({
    identity: async () => ({ user_id: owner, operator: true }),
    db: async (table, filters) => {
      assert.equal(table, 'korlix_fax_documents');
      assert.equal(filters.user_id, 'eq.' + owner);
      assert.equal(filters.status, 'in.(delivered,received)');
      assert.equal(filters.and, '(updated_at.gte.2024-02-01T00:00:00.000Z,updated_at.lt.2024-03-01T00:00:00.000Z)');
      assert.equal(filters.order, 'updated_at.desc,id.desc');
      assert.equal(filters.limit, '51');
      assert.doesNotMatch(filters.select, /object_path|user_id|carrier_id/);
      if (!filters.or) return records;
      assert.equal(filters.or, '(updated_at.lt.' + time + ',and(updated_at.eq.' + time + ',id.lt.' + lastVisible.id + '))');
      return records.slice(50);
    },
    rpc: async (name, values) => {
      rpcCalls++;
      assert.equal(name, 'monthly_usage');
      assert.deepEqual(values, { p_user: owner, p_start: '2024-02-01T00:00:00.000Z', p_end: '2024-03-01T00:00:00.000Z' });
      return { pages: 51, outboundPages: 51, inboundPages: 0, pendingReports: 0 };
    },
  });
  const params = new URLSearchParams({ month: '2024-02', user_id: crypto.randomUUID() });
  const first = await (await handler(new Request(url + params))).json();
  assert.equal(first.items.length, 50);
  assert.equal(first.summary.pages, 51);
  assert.equal(first.next, time + '|' + lastVisible.id);
  params.set('cursor', first.next);
  const second = await (await handler(new Request(url + params))).json();
  assert.deepEqual(second, { items: records.slice(50), next: null });
  assert.equal(rpcCalls, 1);
});

test('private activity enforces the launch hold and rejects invalid month and cursor values before data access', async () => {
  let operator = false;
  const handler = createHandler({
    identity: async () => ({ user_id: owner, operator }),
    db: async () => assert.fail('unexpected query'),
    rpc: async () => assert.fail('unexpected summary'),
  });
  assert.equal((await handler(new Request(url + 'month=2024-02'))).status, 403);
  operator = true;
  const invalid = [
    {month: ''}, {month: '2024-13'}, {month: '2100-01'},
    {month: '2024-02', cursor: '2024-03-01T00:00:00Z|' + owner},
    {month: '2024-02', cursor: time + '|broken'},
    {month: '2024-02', cursor: time + '|' + owner + '|extra'},
  ];
  for (const params of invalid)
    assert.equal((await handler(new Request(url + new URLSearchParams(params)))).status, 400);
});

test('CSV exports every page, distinguishes pending counts and protects spreadsheet cell contents', async () => {
  const seen = [];
  const custom = { ...records[0], name: '=Notes, "revised".pdf', pages: null };
  const marker = time + '|' + records[49].id;
  const blob = await activityCsv('2024-02', (month, cursor) => {
    assert.equal(month, '2024-02');
    seen.push(cursor);
    return cursor ? { items: [custom], next: null } : { items: records.slice(0,50), next: marker };
  });
  assert.deepEqual(seen, [null, marker]);
  const csv = await blob.text();
  assert.equal(csv.trimEnd().split('\r\n').length, 52);
  assert.match(csv, /"'=Notes, ""revised""\.pdf","Delivered","","Pending"/);
  assert.match(csv, /"\(212\) 555-0123","\(310\) 555-0134"/);
  await assert.rejects(activityCsv('2024-02', async (month, cursor) => {
    if (cursor) throw Error('Connection lost');
    return { items: records.slice(0,50), next: marker };
  }), /Connection lost/);
});
