import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createFieldProofEmailProvider, FieldProofEmailProviderError } from '../fieldproof/email_provider.mjs';

const id = 'af495a12-5bd0-44e9-a44d-550c7c6a25f9';
const providerId = '194e31bd-cab3-44c9-b665-041b55d7fb14';
const environment = { RESEND_API_KEY: 'test-key-no-network', KORLIX_AGENT_EMAIL_FROM: 'KORLIX FieldProof <reports@example.test>' };
const input = () => ({ id, to: 'customer@example.test', subject: 'Job completed', text: 'The approved work was completed.', replyTo: 'owner@example.test' });
const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } });
const pdf = Buffer.from('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n').toString('base64');
const checkError = expected => error => {
  assert(error instanceof FieldProofEmailProviderError);
  for (const [key, value] of Object.entries(expected)) assert.equal(error[key], value, key);
  return true;
};

test('provider status exposes capabilities without keys, addresses or NOVA ownership', () => {
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => json({ id: providerId }) });
  assert.deepEqual(provider.status(), { provider: 'resend', ready: true, reason: null, senderFingerprint: createHash('sha256').update(environment.KORLIX_AGENT_EMAIL_FROM).digest('hex'), requiredEnvironment: ['RESEND_API_KEY', 'KORLIX_AGENT_EMAIL_FROM'] });
  assert(!JSON.stringify(provider.status()).includes('example.test'));
  assert(!JSON.stringify(provider.status()).includes(environment.RESEND_API_KEY));
  assert.equal(createFieldProofEmailProvider({ environment: {} }).status().reason, 'provider_key_unavailable');
  assert.equal(createFieldProofEmailProvider({ environment: { ...environment, KORLIX_AGENT_EMAIL_FROM: 'x\r\nBcc: other@example.test' } }).status().reason, 'sender_unavailable');
  assert.equal(createFieldProofEmailProvider({ environment, fetchImpl: null }).status().reason, 'transport_unavailable');
});

test('unconfigured transport fails before a provider call', async () => {
  let calls = 0;
  const provider = createFieldProofEmailProvider({ environment: {}, fetchImpl: async () => { calls++; } });
  await assert.rejects(provider.send(input()), checkError({ code: 'fieldproof_email_provider_unavailable', outcome: 'not_sent', retryable: false }));
  assert.equal(calls, 0);
});

test('sender fingerprint changes with the server sender so stored retries can reject a changed From', () => {
  const mutable = { ...environment };
  const provider = createFieldProofEmailProvider({ environment: mutable });
  const before = provider.status().senderFingerprint;
  mutable.KORLIX_AGENT_EMAIL_FROM = 'Different business <reports@example.test>';
  assert.notEqual(provider.status().senderFingerprint, before);
  mutable.KORLIX_AGENT_EMAIL_FROM = 'invalid sender';
  assert.equal(provider.status().senderFingerprint, null);
  assert.equal(provider.status().ready, false);
});

test('sends one transactional recipient with fixed From, verified caller reply-to and stable UUID key', async () => {
  const calls = [];
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async (url, options) => {
    calls.push({ url, options });
    return json({ id: providerId });
  } });
  const mail = { ...input(), html: '<p>Completed work.</p>', attachments: [{ filename: 'FieldProof-report.pdf', content: pdf }] };
  const first = await provider.send(mail), second = await provider.send({ ...mail, id: id.toUpperCase() });
  assert.deepEqual(first, { accepted: true, provider: 'resend', providerId, idempotencyKey: `fp-email:${id}` });
  assert.deepEqual(second, first);
  for (const { url, options } of calls) {
    assert.equal(url, 'https://api.resend.com/emails');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers['Idempotency-Key'], `fp-email:${id}`);
    assert(options.signal instanceof AbortSignal);
    assert.deepEqual(JSON.parse(options.body), {
      from: environment.KORLIX_AGENT_EMAIL_FROM, to: [mail.to], subject: mail.subject, text: mail.text,
      reply_to: mail.replyTo, html: mail.html,
      tags: [{ name: 'fieldproof_delivery', value: id }],
      attachments: [{ filename: 'FieldProof-report.pdf', content: pdf }],
    });
  }
  assert.equal(calls[0].options.body, calls[1].options.body);
});

test('rejects recipient/header injection, arbitrary From or headers, invalid identity and empty bodies before fetch', async () => {
  let calls = 0;
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => { calls++; return json({ id: providerId }); } });
  const mutations = [
    { to: ['one@example.test', 'two@example.test'] }, { to: 'Name <one@example.test>' },
    { to: 'one@example.test,two@example.test' }, { to: 'one@example.test\r\nBcc: other@example.test' },
    { to: 'one..two@example.test' }, { to: 'a@-bad.example.test' }, { to: 'a@one..test' },
    { replyTo: 'one@example.test\nother@example.test' }, { replyTo: null },
    { subject: 'Report\r\nBcc: other@example.test' }, { subject: 'a'.repeat(201) },
    { id: 'a/../../other' }, { id: 7 }, { text: '' }, { text: 'a\0b' }, { text: 'a'.repeat(128 * 1024 + 1) },
    { html: { unexpected: 'body' } }, { from: 'someone@example.test' }, { headers: { Bcc: 'someone@example.test' } },
    { tags: [{ name: 'fieldproof_delivery', value: 'different-delivery' }] },
  ];
  for (const mutation of mutations) await assert.rejects(provider.send({ ...input(), ...mutation }), checkError({ code: 'fieldproof_email_payload_invalid', outcome: 'not_sent' }));
  assert.equal(calls, 0);
});

test('attachment validation allows only one bounded inline PDF and no remote paths', async () => {
  let calls = 0;
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => { calls++; return json({ id: providerId }); } });
  const oversized = Buffer.alloc(8 * 1024 * 1024 + 1).toString('base64');
  const attachments = [
    [{ filename: '../report.pdf', content: pdf }], [{ filename: 'report.exe', content: pdf }],
    [{ filename: 'report.pdf', path: 'https://private.example.test/attachment' }],
    [{ filename: 'report.pdf', content: Buffer.from('<html/>').toString('base64') }],
    [{ filename: 'report.pdf', content: pdf + '\n' }], [{ filename: 'report.pdf', content: '====' }],
    [{ filename: 'report.pdf', content: Buffer.from('%PDF-1.7\ntruncated').toString('base64') }],
    [{ filename: 'report.pdf', content: oversized }],
    [{ filename: 'first.pdf', content: pdf }, { filename: 'second.pdf', content: pdf }],
  ];
  for (const files of attachments) await assert.rejects(provider.send({ ...input(), attachments: files }), checkError({ code: 'fieldproof_email_payload_invalid' }));
  assert.equal(calls, 0);
});

test('ordinary provider 4xx rejection is definite and does not echo provider content', async () => {
  for (const status of [400, 401, 403, 404, 413, 422]) {
    const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => json({ message: 'PRIVATE secret-recipient@example.test', name: 'validation_error' }, status) });
    await assert.rejects(provider.send(input()), error => {
      checkError({ code: 'fieldproof_email_provider_rejected', outcome: 'not_sent', retryable: false, statusCode: 422 })(error);
      assert(!error.message.includes('PRIVATE'));
      assert(!error.message.includes('example.test'));
      return true;
    });
  }
});

test('rate limits are definite, retryable and have bounded retry hints', async () => {
  for (const [header, delay] of [['90', 90], ['999999', 3600], ['0', 1], ['not-numeric', null]]) {
    const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => json({ name: 'rate_limit_exceeded' }, 429, { 'Retry-After': header }) });
    await assert.rejects(provider.send(input()), checkError({ code: 'fieldproof_email_rate_limited', outcome: 'not_sent', retryable: true, retryAfterSeconds: delay }));
  }
});

test('idempotency conflicts are never turned into a fresh send', async () => {
  for (const [name, code, retryable] of [
    ['concurrent_idempotent_requests', 'fieldproof_email_dispatch_in_progress', true],
    ['invalid_idempotent_request', 'fieldproof_email_idempotency_conflict', false],
  ]) {
    let calls = 0;
    const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => { calls++; return json({ name }, 409); } });
    await assert.rejects(provider.send(input()), checkError({ code, outcome: 'uncertain', retryable }));
    assert.equal(calls, 1);
  }
});

test('transport errors are uncertain, preserve the original delivery identity and never automatically resend', async () => {
  let calls = 0;
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async (_url, options) => {
    calls++;
    assert.equal(options.headers['Idempotency-Key'], `fp-email:${id}`);
    throw new Error('Secret token or recipient from underlying transport');
  } });
  await assert.rejects(provider.send(input()), checkError({ code: 'fieldproof_email_transport_uncertain', outcome: 'uncertain', retryable: true }));
  assert.equal(calls, 1);
});

test('timeouts abort after thirty seconds and retain an uncertain outcome', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal;
  const provider = createFieldProofEmailProvider({ environment, fetchImpl: async (_url, options) => {
    signal = options.signal;
    return new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  } });
  const pending = provider.send(input());
  const rejected = assert.rejects(pending, checkError({ code: 'fieldproof_email_transport_uncertain', outcome: 'uncertain' }));
  t.mock.timers.tick(29999);
  assert.equal(signal.aborted, false);
  t.mock.timers.tick(1);
  assert.equal(signal.aborted, true);
  await rejected;
});

test('server errors, malformed receipts and ambiguous success remain uncertain', async () => {
  const responses = [
    () => json({ message: 'server failed' }, 500), () => json({}, 503), () => json({}, 408),
    () => json({}), () => json({ id: 'unusable-receipt' }), () => json({ id: providerId, error: 'failed' }),
    () => new Response('not-json'), () => new Response('x'.repeat(32 * 1024 + 1)),
  ];
  for (const response of responses) {
    const provider = createFieldProofEmailProvider({ environment, fetchImpl: async () => response() });
    await assert.rejects(provider.send(input()), checkError({ code: 'fieldproof_email_receipt_uncertain', outcome: 'uncertain', retryable: true }));
  }
});

test('unreadable definite rejection keeps its HTTP outcome', async () => {
  const rejected = createFieldProofEmailProvider({ environment, fetchImpl: async () => new Response('x'.repeat(32 * 1024 + 1), { status: 403 }) });
  await assert.rejects(rejected.send(input()), checkError({ outcome: 'not_sent', retryable: false }));
  const throttled = createFieldProofEmailProvider({ environment, fetchImpl: async () => new Response('not-json', { status: 429 }) });
  await assert.rejects(throttled.send(input()), checkError({ outcome: 'not_sent', retryable: true, statusCode: 429 }));
});
