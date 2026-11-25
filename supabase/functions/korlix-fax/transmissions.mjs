import {
  boundedBytes,
  fail,
  inboundLimit,
  lineNumber,
  mediaLink,
  pdf,
  updates,
  uploadLimit,
  uuid,
  verifyWebhook,
} from './rules.mjs';

const table = 'korlix_fax_documents';
const now = () => new Date().toISOString();
const match = (id) => ({ id: 'eq.' + id });
const patch = (svc, where, values) =>
  svc.db(table, where, 'PATCH', { ...values, updated_at: now() });
export async function send(req, user, svc) {
  const line = await svc.lineFor({ user_id: 'eq.' + user.user_id, state: 'eq.active' });
  if (!line || !svc.ready) fail(409, 'An active fax line is required to send.');
  const to = req.headers.get('x-fax-to') || '',
    request = req.headers.get('x-request-id') || '';
  if (!lineNumber.test(to) || !uuid.test(request))
    fail(400, 'Enter a valid +1 fax number and confirm the document.');
  const prior = async () =>
    (
      await svc.db(table, {
        user_id: 'eq.' + user.user_id,
        request_id: 'eq.' + request,
        limit: '1',
      })
    )[0];
  const existing = await prior();
  if (existing) return { id: existing.id, status: existing.status };
  let name;
  try {
    name = decodeURIComponent(req.headers.get('x-filename') || 'Document.pdf')
      .replace(/[\x00-\x1f\/\\]/g, ' ')
      .trim()
      .slice(0, 120);
  } catch {
    fail(400, 'Invalid file name.');
  }
  const bytes = pdf(await boundedBytes(req, uploadLimit));
  const id = crypto.randomUUID(),
    objectPath = user.user_id + '/outbound/' + id + '.pdf';
  const [job] = await svc.db(
    table,
    { on_conflict: 'user_id,request_id' },
    'POST',
    {
      id,
      user_id: user.user_id,
      request_id: request,
      direction: 'outbound',
      name: name || 'Document.pdf',
      sender: line.phone,
      recipient: to,
      status: 'preparing',
    },
    'resolution=ignore-duplicates,return=representation'
  );
  if (!job) {
    const duplicate = await prior();
    return { id: duplicate.id, status: duplicate.status };
  }
  let submitted = false;
  try {
    await svc.put(objectPath, bytes);
    const media = await svc.signed(objectPath, 1800);
    await patch(svc, match(id), { status: 'submitting', object_path: objectPath });
    submitted = true;
    const result = await svc.carrier('faxes', 'POST', {
      connection_id: svc.connection,
      from: line.phone,
      to,
      media_url: media,
      client_state: btoa(id),
      webhook_url: svc.hook,
    });
    if (!uuid.test(result?.id)) fail(502, 'Waiting for carrier confirmation.');
    await patch(
      svc,
      { ...match(id), status: 'in.(submitting,checking)' },
      { status: 'queued', carrier_id: result.id }
    );
  } catch (error) {
    const rejected = [400, 401, 402, 403, 404, 413, 422, 429].includes(error.remoteStatus);
    const uncertain = submitted && !rejected;
    await patch(
      svc,
      { ...match(id), status: 'in.(preparing,submitting,checking)' },
      {
        status: uncertain ? 'checking' : 'failed',
        detail: uncertain ? 'Awaiting carrier confirmation.' : 'The fax could not be submitted.',
      }
    );
  }
  const current = await prior();
  return { id, status: current.status };
}

async function incoming(event, p, svc) {
  const line = await svc.lineFor({ phone: 'eq.' + p.to, state: 'eq.active' });
  if (!line?.user_id) return;
  const where = {
    direction: 'eq.inbound',
    carrier_id: 'eq.' + p.fax_id,
    user_id: 'eq.' + line.user_id,
  };
  const existing = (await svc.db(table, where))[0];
  if (existing?.status === 'received' || (existing && event === 'fax.failed')) return;
  const complete = event === 'fax.received' && !p.partial_content;
  let objectPath = null;
  if (complete || (p.partial_content && p.media_url)) {
    const response = await svc.http(mediaLink(p.media_url || p.stored_media_url), {
      redirect: 'error',
      signal: AbortSignal.timeout(25000),
    });
    if (!response.ok) fail(503, 'The carrier document is temporarily unavailable.');
    const bytes = pdf(await boundedBytes(response, inboundLimit));
    objectPath = line.user_id + '/inbound/' + p.fax_id + '.pdf';
    await svc.put(objectPath, bytes);
  }
  const record = {
    user_id: line.user_id,
    direction: 'inbound',
    carrier_id: p.fax_id,
    sender: String(p.from || 'Unknown').slice(0, 60),
    recipient: line.phone,
    name: 'Incoming fax.pdf',
    status: complete ? 'received' : 'failed',
    object_path: objectPath,
    detail: complete
      ? null
      : p.partial_content
        ? 'The carrier received only part of this fax.'
        : String(p.failure_reason || 'Transmission failed.').slice(0, 160),
    pages: Number.isInteger(p.page_count) ? p.page_count : null,
    updated_at: now(),
  };
  await svc.db(
    table,
    { on_conflict: 'direction,carrier_id' },
    'POST',
    record,
    'resolution=ignore-duplicates,return=minimal'
  );
  if (complete) await patch(svc, { ...where, status: 'eq.failed' }, record);
}
export async function callback(req, svc) {
  const raw = new TextDecoder().decode(await boundedBytes(req, 128 * 1024));
  await verifyWebhook(svc.publicKey, req.headers, raw);
  let data;
  try {
    data = JSON.parse(raw).data;
  } catch {
    fail(400, 'Invalid callback.');
  }
  const p = data?.payload,
    event = data?.event_type;
  if (!p || !uuid.test(p.fax_id) || String(p.connection_id) !== svc.connection) return;
  if (p.direction === 'inbound') {
    if (event === 'fax.received' || event === 'fax.failed') await incoming(event, p, svc);
    return;
  }
  if (p.direction !== 'outbound' || !Object.hasOwn(updates, event)) return;
  let localId;
  try {
    localId = atob(p.client_state || '');
  } catch {
    localId = '';
  }
  const [status, allowed] = updates[event];
  const where = {
    direction: 'eq.outbound',
    sender: 'eq.' + p.from,
    recipient: 'eq.' + p.to,
    status: 'in.(' + allowed.join(',') + ')',
  };
  if (uuid.test(localId)) {
    where.id = 'eq.' + localId;
    where.or = '(carrier_id.is.null,carrier_id.eq.' + p.fax_id + ')';
  } else where.carrier_id = 'eq.' + p.fax_id;
  const changes = {
    status,
    carrier_id: p.fax_id,
    detail:
      status === 'failed' ? String(p.failure_reason || 'Transmission failed.').slice(0, 160) : null,
  };
  if (Number.isInteger(p.page_count)) changes.pages = p.page_count;
  await patch(svc, where, changes);
}
