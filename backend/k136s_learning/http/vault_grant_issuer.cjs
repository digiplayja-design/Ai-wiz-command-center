'use strict';
// K136S-D vault-backed grant issuer.
//
// Forwards the caller's vaultPassword ONCE, over loopback, to the EXISTING backend route
//   POST /api/brain-vault/password/verify
// relaying only an allow-list of the caller's auth headers (default: authorization, cookie) so the
// backend — not K136S — authenticates the user and enforces the account-manager rule. A preview grant
// is minted only when the backend answers HTTP 200 with { success: true, verified: true }.
//
// The password exists only inside the single forwarded request. It is never logged, stored, put into
// a grant, or echoed in any response. K136S keeps no failure counters: the backend's own
// RecordFailureV2 / ClearFailuresV2 / 15-minute lock remain authoritative. No DB, no state.
const http = require('node:http');
const https = require('node:https');
const { URL } = require('node:url');
const { signGrant, AUDIENCE, DEFAULT_TTL_MS } = require('./grant.cjs');

const DEFAULT_BACKEND_URL = 'http://127.0.0.1:8787';
const VERIFY_PATH = '/api/brain-vault/password/verify';
const DEFAULT_RELAY_HEADERS = Object.freeze(['authorization', 'cookie']);
const DEFAULT_TIMEOUT_MS = 5000;
const MAX_RESPONSE_BYTES = 65536;

function parseRelayHeaders(spec) {
  const raw = Array.isArray(spec) ? spec : String(spec == null ? '' : spec).split(',');
  const list = raw.map((h) => String(h).trim().toLowerCase()).filter(Boolean);
  return list.length ? Object.freeze(list) : DEFAULT_RELAY_HEADERS;
}

function lowerKeys(headers) {
  const out = {};
  if (headers && typeof headers === 'object') for (const k of Object.keys(headers)) out[String(k).toLowerCase()] = headers[k];
  return out;
}

// The real verifier: exactly one HTTP request to the backend. Resolves { status, body } (body is
// parsed JSON or null). Rejects on network error / timeout. Nothing here retains the password.
function createHttpVerifier({ backendUrl = DEFAULT_BACKEND_URL, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  const base = new URL(backendUrl);
  const isHttps = base.protocol === 'https:';
  const client = isHttps ? https : http;
  return function verify({ vaultPassword, relayHeaders }) {
    return new Promise((resolve, reject) => {
      const payload = Buffer.from(JSON.stringify({ vaultPassword }), 'utf8');
      const headers = Object.assign({}, relayHeaders || {}, {
        'content-type': 'application/json',
        'content-length': payload.length,
        accept: 'application/json',
      });
      const req = client.request({
        protocol: base.protocol, hostname: base.hostname, port: base.port || (isHttps ? 443 : 80),
        method: 'POST', path: VERIFY_PATH, headers, timeout: timeoutMs,
      }, (res) => {
        const chunks = []; let size = 0;
        res.on('data', (c) => { size += c.length; if (size <= MAX_RESPONSE_BYTES) chunks.push(c); });
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let body = null;
          try { body = text ? JSON.parse(text) : null; } catch { body = null; }
          resolve({ status: res.statusCode || 0, body });
        });
        res.on('error', reject);
      });
      req.on('timeout', () => req.destroy(new Error('verify timeout')));
      req.on('error', reject);
      req.write(payload);
      req.end();
    });
  };
}

// Decide the outcome of a grant request given a verifier. Returns { status, json }. Fail closed.
async function issueVaultGrant({ agentId, vaultPassword, headers, key, now = Date.now, ttlMs = DEFAULT_TTL_MS, verify, relayHeaderNames } = {}) {
  if (typeof verify !== 'function') return { status: 503, json: { error: 'vault grant issuer not configured', code: 'VAULT_ISSUER_NOT_CONFIGURED' } };
  if (typeof agentId !== 'string' || !agentId) return { status: 400, json: { error: 'agentId required', code: 'AGENT_ID_REQUIRED' } };
  if (typeof vaultPassword !== 'string' || !vaultPassword) return { status: 400, json: { error: 'vaultPassword required', code: 'VAULT_PASSWORD_REQUIRED' } };

  const incoming = lowerKeys(headers);
  const relay = {};
  for (const name of parseRelayHeaders(relayHeaderNames)) {
    const v = incoming[name];
    if (typeof v === 'string' && v) relay[name] = v;
  }

  let result;
  try { result = await verify({ vaultPassword, relayHeaders: relay }); }
  catch { return { status: 503, json: { error: 'vault backend unavailable', code: 'BACKEND_UNAVAILABLE' } }; }

  const status = Number(result && result.status) || 0;
  const body = result && result.body && typeof result.body === 'object' ? result.body : null;

  if (status === 200 && body && body.success === true && body.verified === true) {
    const t = typeof now === 'function' ? now() : now;
    const iat = Math.floor(t);
    const exp = iat + Math.max(1, Math.floor(ttlMs));
    const payload = {
      aud: AUDIENCE, agentId, iat, exp,
      pv: body.passwordVersion === undefined ? null : body.passwordVersion,
      mgr: body.managerMode || null,
    };
    const token = signGrant(payload, key);
    return { status: 200, json: {
      grant: token, aud: AUDIENCE, agentId, expiresAt: exp,
      managerMode: payload.mgr, passwordVersion: payload.pv,
      note: 'vault-backed grant (K136S-D)',
    } };
  }

  if (status >= 400 && status < 600) {
    const code = body && typeof body.code === 'string' ? body.code
      : status === 429 ? 'brain_vault_password_rate_limited'
      : status === 401 ? 'brain_vault_password_incorrect'
      : 'VAULT_VERIFY_REJECTED';
    const out = { error: 'vault verification failed', code };
    if (status === 429 && body && body.lockedUntil) out.lockedUntil = body.lockedUntil;
    return { status, json: out };
  }

  // 200 without success&&verified, non-JSON, or an unexpected status: refuse.
  return { status: 502, json: { error: 'unexpected vault response', code: 'BACKEND_UNEXPECTED' } };
}

module.exports = Object.freeze({
  createHttpVerifier, issueVaultGrant, parseRelayHeaders,
  DEFAULT_BACKEND_URL, VERIFY_PATH, DEFAULT_RELAY_HEADERS, DEFAULT_TIMEOUT_MS,
});
