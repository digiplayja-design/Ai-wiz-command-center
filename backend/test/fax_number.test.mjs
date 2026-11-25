import test from 'node:test';
import assert from 'node:assert/strict';
import {
  boundedBytes,
  mediaLink,
  pdf,
  quote,
  updates,
  verifyWebhook,
} from '../../supabase/functions/korlix-fax/rules.mjs';
import { createHandler } from '../../supabase/functions/korlix-fax/handler.mjs';
import { send, callback } from '../../supabase/functions/korlix-fax/transmissions.mjs';

const company = '+18335550123',
  contact = '+16145550124',
  user = { user_id: crypto.randomUUID(), email: 'fixture@example.test', operator: false };
const carrierId = crypto.randomUUID(),
  docId = crypto.randomUUID();
const inventory = (monthly, upfront = '0') => ({
  phone_number: company,
  features: [{ name: 'fax' }],
  cost_information: { monthly_cost: monthly, upfront_cost: upfront, currency: 'USD' },
});
test('orders require a matching fax capability, prefix and explicit zero-upfront USD quote within the authorized cap', () => {
  assert.deepEqual(quote(inventory('1.00'), 'toll_free'), {
    number: company,
    monthly: 1,
    upfront: 0,
    currency: 'USD',
  });
  for (const entry of [
    inventory('2.01'),
    inventory('1', '0.1'),
    inventory(null),
    inventory('1', null),
    { ...inventory('1'), features: [] },
    { ...inventory('1'), phone_number: contact },
  ])
    assert.equal(quote(entry, 'toll_free'), null);
  assert.equal(quote(inventory('1'), '614'), null);
});
test('private PDF intake bounds the streamed body and requires a PDF header', async () => {
  assert.throws(() => pdf(new TextEncoder().encode('hello')));
  await assert.rejects(boundedBytes(new Response('a'.repeat(200)), 100), { status: 413 });
  assert.equal(pdf(await boundedBytes(new Response('%PDF-1.7'), 100)).length, 8);
  assert.throws(() => mediaLink('http://127.0.0.1/private'));
});
const key = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
const base64 = (buf) => Buffer.from(buf).toString('base64');
const pub = base64(await crypto.subtle.exportKey('raw', key.publicKey));
async function signed(data) {
  const message = JSON.stringify({ data }),
    time = String(Math.floor(Date.now() / 1000));
  const sign = await crypto.subtle.sign(
    'Ed25519',
    key.privateKey,
    new TextEncoder().encode(time + '|' + message)
  );
  return new Request('https://fax.test/carrier', {
    method: 'POST',
    body: message,
    headers: { 'telnyx-timestamp': time, 'telnyx-signature-ed25519': base64(sign) },
  });
}
test('webhooks require the Ed25519 signature and a fresh timestamp', async () => {
  const r = await signed({});
  const raw = await r.text();
  await verifyWebhook(pub, r.headers, raw);
  await assert.rejects(verifyWebhook(pub, r.headers, raw + '!'), { status: 401 });
  await assert.rejects(verifyWebhook(pub, r.headers, raw, Date.now() + 600000), { status: 401 });
});
test('an inbound PDF is saved once, routed to the destination owner and a later failure cannot replace it', async () => {
  let archive = [],
    docs = [];
  const svc = {
    publicKey: pub,
    connection: '55',
    lineFor: async (f) =>
      f.phone === 'eq.' + company ? { user_id: user.user_id, phone: company } : undefined,
    http: async () => new Response('%PDF-1.5'),
    put: async (path, bytes) => archive.push([path, bytes.length]),
    db: async (t, f, m, body) => {
      if (!m) return docs;
      if (m === 'POST' && !docs.length) docs.push(body);
      return [];
    },
  };
  const payload = {
    direction: 'inbound',
    connection_id: '55',
    fax_id: carrierId,
    from: contact,
    to: company,
    media_url: 'https://media.telnyx.com/fax',
    page_count: 2,
  };
  for (const event_type of ['fax.received', 'fax.received', 'fax.failed'])
    await callback(await signed({ event_type, payload }), svc);
  await callback(
    await signed({ event_type: 'fax.received', payload: { ...payload, to: contact } }),
    svc
  );
  assert.equal(archive.length, 1);
  assert.equal(docs[0].user_id, user.user_id);
  assert.equal(docs[0].status, 'received');
  assert.equal(docs[0].pages, 2);
});
test('outbound submission retries reuse the same fax and ambiguous carrier acceptance never creates a second send', async () => {
  let rows = [],
    calls = 0;
  const svc = {
    ready: true,
    connection: '55',
    hook: 'https://fax.test/hook',
    lineFor: async () => ({ phone: company }),
    put: async () => {},
    signed: async () => 'https://signed.test/doc',
    carrier: async () => {
      calls++;
      throw Error('disconnected');
    },
    db: async (t, f, m, body) => {
      if (!m) return rows;
      if (m === 'POST') {
        rows = [body];
        return rows;
      }
      if (m === 'PATCH') {
        Object.assign(rows[0], body);
        return rows;
      }
      return [];
    },
  };
  const request = () =>
    new Request('https://fax.test/send', {
      method: 'POST',
      headers: { 'x-fax-to': contact, 'x-request-id': docId },
      body: '%PDF-1.7 fixture',
    });
  const first = await send(request(), user, svc),
    second = await send(request(), user, svc);
  assert.equal(calls, 1);
  assert.equal(first.status, 'checking');
  assert.deepEqual(second, first);
});
test('late queued or sending events cannot regress a delivered fax', () => {
  for (const [, allowed] of Object.values(updates)) assert.ok(!allowed.includes('delivered'));
});
test('user history and file links are restricted to the signed-in owner, and operators have a separate gate', async () => {
  const seen = [];
  const svc = {
    identity: async () => user,
    db: async (t, filters) => {
      seen.push(filters);
      return [];
    },
    signed: () => assert.fail('wrong owner'),
  };
  const app = createHandler(svc);
  const request = (route) => new Request('https://fax.test/korlix-fax' + route);
  assert.equal((await app(request('/file/' + docId))).status, 404);
  assert.equal((await app(request('/history?direction=inbound'))).status, 200);
  assert.ok(seen.every((f) => f.user_id === 'eq.' + user.user_id));
  assert.equal((await app(request('/operator/requests'))).status, 403);
});
test('ordering is locked before calling the carrier and routes are checked before activating', async () => {
  const { services } = await import('../../supabase/functions/korlix-fax/services.mjs');
  const settings = {
    SUPABASE_URL: 'https://project.test',
    SUPABASE_SERVICE_ROLE_KEY: 'fixture',
    TELNYX_API_KEY: 'fixture',
    TELNYX_FAX_CONNECTION_ID: '55',
    TELNYX_PUBLIC_KEY: 'fixture',
  };
  const line = {
    id: crypto.randomUUID(),
    state: 'requested',
    is_company: true,
    preference: 'toll_free',
  };
  let count = 0;
  const mock = async (url, opts) => {
    url = new URL(url);
    const body = opts.body ? JSON.parse(opts.body) : {};
    if (url.pathname.endsWith('korlix_fax_lines')) {
      if (opts.method === 'PATCH') {
        if (url.searchParams.get('state') !== 'eq.' + line.state) return Response.json([]);
        Object.assign(line, body);
      }
      return Response.json([{ ...line }]);
    }
    if (url.pathname.endsWith('available_phone_numbers'))
      return Response.json({ data: [inventory('1')] });
    if (url.pathname.endsWith('/number_orders') && opts.method === 'POST') {
      count++;
      return Response.json({ data: { id: 'order-1' } });
    }
    if (url.pathname.endsWith('/number_orders/order-1'))
      return Response.json({
        data: {
          id: 'order-1',
          customer_reference: line.id,
          status: 'success',
          phone_numbers: [{ status: 'success', phone_number: company }],
        },
      });
    if (url.pathname.endsWith('/phone_numbers'))
      return Response.json({
        data: [{ status: 'active', phone_number: company, connection_id: '55' }],
      });
    if (url.pathname.endsWith('/fax_applications/55'))
      return Response.json({
        data: {
          active: true,
          webhook_event_url: 'https://project.test/functions/v1/korlix-fax/carrier',
          outbound: { outbound_voice_profile_id: '7' },
        },
      });
    throw Error('Unexpected ' + url.pathname);
  };
  const svc = services((name) => settings[name], mock);
  await svc.order({ ...line }, quote(inventory('1'), 'toll_free'));
  await svc.order({ ...line }, quote(inventory('1'), 'toll_free'));
  assert.equal(count, 1);
  assert.equal(line.state, 'active');
});
