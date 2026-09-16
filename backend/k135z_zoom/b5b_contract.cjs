'use strict';
// K135Z-B5B v1. Pure validation; no environment, database, or network access.
const crypto = require('node:crypto');
class K135zZoomError extends Error {
  constructor(status, code, message = code) {
    super(message); this.name = 'K135zZoomError'; this.status = status; this.code = code;
  }
}
function need(ok, code, status = 400) { if (!ok) throw new K135zZoomError(status, code); }
function object(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
function keys(v, required, optional = []) {
  need(object(v), 'ZOOM_RECORD_INVALID');
  need(required.every(k => Object.hasOwn(v, k)) &&
    Object.keys(v).every(k => required.includes(k) || optional.includes(k)), 'ZOOM_RECORD_FIELDS_INVALID');
}
function text(v, max = 256) {
  need(typeof v === 'string' && v.length > 0 && v.length <= max &&
    v === v.trim() && !/[\x00-\x1f\x7f]/.test(v), 'ZOOM_TEXT_INVALID'); return v;
}
function time(v) { need(Number.isSafeInteger(v) && v >= 0 && v <= 8640000000000000, 'ZOOM_TIME_INVALID'); return v; }
function identity(v) {
  need(object(v), 'ZOOM_IDENTITY_REQUIRED', 401);
  const tenantId = v.tenantId, userId = v.userId ?? v.id, agentId = v.agentId;
  need(typeof userId === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(userId) &&
    userId !== '00000000-0000-0000-0000-000000000000', 'ZOOM_USER_UUID_REQUIRED', 401);
  for (const val of [tenantId, agentId]) need(typeof val === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(val), 'ZOOM_TENANT_AGENT_REQUIRED', 401);
  need(v.id === undefined || v.userId === undefined || v.id === v.userId, 'ZOOM_IDENTITY_CONFLICT', 401);
  return {tenantId, userId, agentId};
}
function identityKey(v) { const i = identity(v); return JSON.stringify([i.tenantId, i.userId, i.agentId]); }
function identityFromKey(key) {
  let parts; try { parts = JSON.parse(key); } catch { need(false, 'ZOOM_IDENTITY_KEY_INVALID'); }
  need(Array.isArray(parts) && parts.length === 3, 'ZOOM_IDENTITY_KEY_INVALID');
  const i = identity({tenantId: parts[0], userId: parts[1], agentId: parts[2]});
  need(identityKey(i) === key, 'ZOOM_IDENTITY_KEY_INVALID'); return i;
}
function normalizeReturnTo(value, allowedOrigins = []) {
  if (value === null || value === undefined || value === '') return null;
  text(value, 2048);
  need(!/[\\\x00-\x20\x7f]/.test(value) && !/%(?:0[0-9a-f]|1[0-9a-f]|7f|5c)/i.test(value), 'ZOOM_RETURN_URL_INVALID');
  let url; try { url = new URL(value); } catch { need(false, 'ZOOM_RETURN_URL_INVALID'); }
  need(url.protocol === 'https:' && !url.username && !url.password, 'ZOOM_RETURN_URL_SCHEME_REJECTED');
  need(Array.isArray(allowedOrigins) && allowedOrigins.length > 0, 'ZOOM_RETURN_URL_NOT_ALLOWED');
  const allowed = allowedOrigins.map(v => {
    text(v, 2048); let u; try { u = new URL(v); } catch { need(false, 'ZOOM_RETURN_ALLOWLIST_INVALID', 503); }
    need(u.protocol === 'https:' && !u.username && !u.password && u.pathname === '/' &&
      !u.search && !u.hash && (v === u.origin || v === u.origin + '/'), 'ZOOM_RETURN_ALLOWLIST_INVALID', 503);
    return u.origin;
  });
  need(allowed.includes(url.origin), 'ZOOM_RETURN_URL_NOT_ALLOWED'); return url.toString();
}
function hash(v) { return crypto.createHash('sha256').update(v).digest('hex'); }
function hash64(v) { need(typeof v === 'string' && /^[a-f0-9]{64}$/.test(v), 'ZOOM_HASH_INVALID'); return v; }
function stateRecord(v) {
  keys(v, ['tenantId','userId','agentId','returnTo','createdAtMs','expiresAtMs']); identity(v);
  time(v.createdAtMs); time(v.expiresAtMs);
  need(v.expiresAtMs > v.createdAtMs && v.expiresAtMs - v.createdAtMs <= 600000, 'ZOOM_STATE_TTL_INVALID');
  if (v.returnTo !== null) { text(v.returnTo, 2048); const u = new URL(v.returnTo); normalizeReturnTo(v.returnTo, [u.origin]); }
  return structuredClone(v);
}
function envelope(v) {
  keys(v, ['version','algorithm','iv','tag','ciphertext']);
  need(v.version === 2 && v.algorithm === 'aes-256-gcm', 'ZOOM_TOKEN_ENVELOPE_INVALID');
  for (const [k, size] of [['iv',12],['tag',16],['ciphertext',null]]) {
    need(typeof v[k] === 'string' && /^[A-Za-z0-9_-]+$/.test(v[k]), 'ZOOM_TOKEN_ENVELOPE_INVALID');
    const b = Buffer.from(v[k], 'base64url');
    need(b.toString('base64url') === v[k] && (size ? b.length === size : b.length > 0 && b.length <= 32768), 'ZOOM_TOKEN_ENVELOPE_INVALID');
  }
  return v;
}
function connectionRecord(key, v) {
  keys(v, ['key','tenantId','userId','agentId','zoomAccountId','zoomUserId','scope','expiresAtMs','connectedAtMs','updatedAtMs','encryptedTokens']);
  identityFromKey(key); need(v.key === key && identityKey(v) === key, 'ZOOM_CONNECTION_BINDING_INVALID');
  text(v.zoomAccountId); text(v.zoomUserId); need(typeof v.scope === 'string' && v.scope.length <= 4096 && !/[\x00-\x1f]/.test(v.scope), 'ZOOM_SCOPE_INVALID');
  for (const k of ['expiresAtMs','connectedAtMs','updatedAtMs']) time(v[k]);
  envelope(v.encryptedTokens); return structuredClone(v);
}
function canonical(v, depth = 0) {
  need(depth < 20, 'ZOOM_EVENT_TOO_DEEP');
  if (v === null || typeof v === 'string' || typeof v === 'boolean') return JSON.stringify(v);
  if (typeof v === 'number') { need(Number.isFinite(v), 'ZOOM_EVENT_INVALID'); return JSON.stringify(v); }
  if (Array.isArray(v)) return '[' + v.map(x => canonical(x, depth + 1)).join(',') + ']';
  need(object(v), 'ZOOM_EVENT_INVALID');
  return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k], depth + 1)).join(',') + '}';
}
function eventPlan(verified) {
  const body = verified?.body; need(object(body), 'ZOOM_EVENT_INVALID');
  const event = text(body.event, 128), eventTs = time(body.event_ts);
  const payloadHash = hash(canonical(body));
  const p = body.payload, o = p?.object;
  let mutation = {kind: 'none'};
  if (event === 'app_deauthorized') {
    mutation = {kind: 'deauthorize', zoomAccountId: text(p?.account_id), zoomUserId: text(p?.user_id)};
  } else if (['meeting.rtms_started','meeting.rtms_stopped','meeting.rtms_interrupted'].includes(event)) {
    const account = text(p?.account_id), uuid = text(o?.uuid, 512), stream = text(o?.rtms_stream_id, 512);
    const key = hash(JSON.stringify([account, uuid, stream]));
    mutation = {kind: 'session', key, record: {sessionKey: key, zoomAccountId: account,
      meetingUuid: uuid, streamId: stream, eventTs,
      status: event.slice('meeting.rtms_'.length), mediaConnected: false, transcriptCollected: false, audioInjected: false}};
  }
  const providerId = body.event_id === undefined ? null : text(body.event_id, 512);
  const eventId = hash(canonical(providerId ? [event, p?.account_id ?? '', providerId] : [event, payloadHash]));
  return validatePlan({eventId, payloadHash, event, eventTs, mutation});
}
function sessionRecord(key, v) {
  keys(v, ['sessionKey','zoomAccountId','meetingUuid','streamId','eventTs','status','mediaConnected','transcriptCollected','audioInjected']);
  hash64(key); text(v.zoomAccountId); text(v.meetingUuid,512); text(v.streamId,512); time(v.eventTs);
  need(v.sessionKey === key && key === hash(JSON.stringify([v.zoomAccountId,v.meetingUuid,v.streamId])), 'ZOOM_SESSION_BINDING_INVALID');
  need(['started','stopped','interrupted'].includes(v.status) &&
    v.mediaConnected === false && v.transcriptCollected === false && v.audioInjected === false, 'ZOOM_MEDIA_DISABLED');
  return structuredClone(v);
}
function validatePlan(v) {
  keys(v, ['eventId','payloadHash','event','eventTs','mutation']); hash64(v.eventId); hash64(v.payloadHash); text(v.event,128); time(v.eventTs);
  const m = v.mutation; need(object(m), 'ZOOM_EVENT_MUTATION_INVALID');
  if (m.kind === 'none') keys(m,['kind']);
  else if (m.kind === 'deauthorize') { keys(m,['kind','zoomAccountId','zoomUserId']); text(m.zoomAccountId); text(m.zoomUserId); need(v.event === 'app_deauthorized','ZOOM_EVENT_MUTATION_INVALID'); }
  else if (m.kind === 'session') { keys(m,['kind','key','record']); sessionRecord(m.key,m.record); need(v.event === 'meeting.rtms_' + m.record.status && v.eventTs === m.record.eventTs,'ZOOM_EVENT_MUTATION_INVALID'); }
  else need(false, 'ZOOM_EVENT_MUTATION_INVALID');
  return structuredClone(v);
}
module.exports = {K135zZoomError, need, keys, text, time, identity, identityKey, identityFromKey,
  normalizeReturnTo, hash, hash64, stateRecord, envelope, connectionRecord, eventPlan, validatePlan, sessionRecord};
