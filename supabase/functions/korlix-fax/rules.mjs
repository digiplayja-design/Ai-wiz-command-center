export const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const lineNumber = /^\+1[2-9]\d{2}[2-9]\d{6}$/;
const tollFree = /^\+18(00|33|44|55|66|77|88)/;
export const uploadLimit = 8 * 1024 * 1024;
export const inboundLimit = 50 * 1024 * 1024;
export const bucket = 'korlix-fax-documents';

export function fail(status, message) {
  throw Object.assign(new Error(message), { status });
}

export function quote(entry, preference) {
  const number = entry.phone_number;
  const costs = entry.cost_information || {};
  const validAmount = (x) =>
    (typeof x === 'string' || typeof x === 'number') && /^\d+(\.\d+)?$/.test(String(x));
  if (!lineNumber.test(number) || !entry.features?.some((x) => x.name === 'fax')) return null;
  if (preference === 'toll_free' ? !tollFree.test(number) : number.slice(2, 5) !== preference)
    return null;
  if (
    costs.currency !== 'USD' ||
    !validAmount(costs.monthly_cost) ||
    !validAmount(costs.upfront_cost)
  )
    return null;
  const monthly = Number(costs.monthly_cost),
    upfront = Number(costs.upfront_cost);
  if (monthly > 2 || upfront !== 0) return null;
  return { number, monthly, upfront, currency: 'USD' };
}

export async function boundedBytes(source, limit) {
  if (Number(source.headers.get('content-length') || 0) > limit)
    fail(413, 'The document exceeds the upload limit.');
  const reader = source.body?.getReader();
  if (!reader) fail(400, 'Choose a PDF.');
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        fail(413, 'The document exceeds the upload limit.');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let start = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, start);
    start += chunk.length;
  }
  return bytes;
}
export function pdf(bytes) {
  if (new TextDecoder().decode(bytes.slice(0, 5)) !== '%PDF-')
    fail(400, 'Choose a valid PDF document.');
  return bytes;
}
export async function digest(value) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, '0')).join('');
}
export function mediaLink(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    fail(502, 'The carrier has not provided a PDF link.');
  }
  const trusted = /(^|\.)(telnyx\.com|telnyxstorage\.com|amazonaws\.com)$/.test(url.hostname);
  if (!trusted || url.protocol !== 'https:' || url.username || url.password || url.port)
    fail(502, 'Invalid carrier file location.');
  return url.href;
}
export async function verifyWebhook(key, headers, data, now = Date.now()) {
  const timestamp = headers.get('telnyx-timestamp') || '';
  if (!key) fail(503, 'Fax carrier setup is pending.');
  if (!/^\d{10}$/.test(timestamp) || Math.abs(now / 1000 - Number(timestamp)) > 300)
    fail(401, 'Invalid webhook timestamp.');
  const decode = (s) => Uint8Array.from(atob(s), (ch) => ch.charCodeAt(0));
  let valid = false;
  try {
    const pub = await crypto.subtle.importKey('raw', decode(key), { name: 'Ed25519' }, false, [
      'verify',
    ]);
    valid = await crypto.subtle.verify(
      'Ed25519',
      pub,
      decode(headers.get('telnyx-signature-ed25519') || ''),
      new TextEncoder().encode(timestamp + '|' + data)
    );
  } catch {
    /* Reject malformed or unsigned callbacks. */
  }
  if (!valid) fail(401, 'Invalid carrier signature.');
}
export const updates = {
  'fax.queued': ['queued', ['submitting', 'checking', 'queued']],
  'fax.media.processed': ['queued', ['submitting', 'checking', 'queued']],
  'fax.sending.started': ['sending', ['submitting', 'checking', 'queued', 'sending']],
  'fax.delivered': ['delivered', ['submitting', 'checking', 'queued', 'sending']],
  'fax.failed': ['failed', ['submitting', 'checking', 'queued', 'sending']],
};
