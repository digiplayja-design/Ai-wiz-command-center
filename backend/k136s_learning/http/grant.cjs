'use strict';
// K136S-C preview grant. A short-lived, single-audience HMAC token that gates POST /k136s/preview.
// Pure crypto over node:crypto. No I/O, no storage. The grant carries NO secret and NO vault material:
// it only asserts "a preview may be computed for this agent until exp". In C the token is minted by a
// dev issuer (env-gated in the server); the real vault-backed issuer is deferred to K136S-D.
const crypto = require('node:crypto');

const AUDIENCE = 'k136s-preview';
const DEFAULT_TTL_MS = 60000; // 60s
const CLOCK_SKEW_MS = 2000;   // tolerate small forward/backward clock drift

function b64u(buf) { return Buffer.from(buf).toString('base64url'); }
function fromB64u(str) { return Buffer.from(String(str), 'base64url'); }

function requireKey(key) {
  if (typeof key !== 'string' || key.length < 16) {
    const e = new Error('K136S grant key missing or too short (need >= 16 chars)');
    e.code = 'GRANT_KEY_INVALID';
    throw e;
  }
  return key;
}

// sign an arbitrary payload object -> "<b64u(json)>.<b64u(hmac)>"
function signGrant(payload, key) {
  requireKey(key);
  const body = b64u(Buffer.from(JSON.stringify(payload), 'utf8'));
  const mac = crypto.createHmac('sha256', key).update(body).digest();
  return `${body}.${b64u(mac)}`;
}

// mint a well-formed preview grant bound to an agent
function mintGrant({ agentId, now = Date.now(), ttlMs = DEFAULT_TTL_MS, key } = {}) {
  requireKey(key);
  if (typeof agentId !== 'string' || !agentId) { const e = new Error('agentId required'); e.code = 'AGENT_ID_REQUIRED'; throw e; }
  const iat = Math.floor(now);
  const payload = { aud: AUDIENCE, agentId, iat, exp: iat + Math.max(1, Math.floor(ttlMs)) };
  return { token: signGrant(payload, key), payload };
}

// verify a preview grant. Fail closed: bad format/signature/audience/expiry all return ok:false.
function verifyGrant(token, { now = Date.now(), key } = {}) {
  try {
    requireKey(key);
    if (typeof token !== 'string' || token.indexOf('.') < 0) return { ok: false, code: 'MALFORMED' };
    const [body, sig] = token.split('.');
    if (!body || !sig) return { ok: false, code: 'MALFORMED' };
    const expected = crypto.createHmac('sha256', key).update(body).digest();
    const got = fromB64u(sig);
    if (got.length !== expected.length || !crypto.timingSafeEqual(got, expected)) return { ok: false, code: 'BAD_SIGNATURE' };
    let payload;
    try { payload = JSON.parse(fromB64u(body).toString('utf8')); } catch { return { ok: false, code: 'MALFORMED' }; }
    if (!payload || payload.aud !== AUDIENCE) return { ok: false, code: 'WRONG_AUDIENCE' };
    if (!payload.agentId || typeof payload.agentId !== 'string') return { ok: false, code: 'MALFORMED' };
    if (!Number.isFinite(payload.iat) || !Number.isFinite(payload.exp)) return { ok: false, code: 'MALFORMED' };
    if (payload.iat - CLOCK_SKEW_MS > now) return { ok: false, code: 'NOT_YET_VALID' };
    if (payload.exp + CLOCK_SKEW_MS <= now) return { ok: false, code: 'EXPIRED' };
    return { ok: true, payload: Object.freeze(payload) };
  } catch (err) {
    return { ok: false, code: err && err.code === 'GRANT_KEY_INVALID' ? 'GRANT_KEY_INVALID' : 'ERROR' };
  }
}

module.exports = Object.freeze({ AUDIENCE, DEFAULT_TTL_MS, signGrant, mintGrant, verifyGrant });
