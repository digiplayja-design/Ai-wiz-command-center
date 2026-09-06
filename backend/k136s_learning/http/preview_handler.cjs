'use strict';
// K136S-C preview handler. A pure function of the request that returns { status, json }.
// It imports ONLY the B domain layer plus the grant verifier. It performs NO writes, opens no
// sockets, issues no approval tokens, and touches no database. All effects (reading the socket,
// writing the response) live in preview_server.cjs. This module is exhaustively unit-testable
// without a running server.
const { normalize, contentHash, diffWords } = require('../domain/normalize_diff.cjs');
const { classify, reclassify } = require('../domain/classifier.cjs');
const { check: checkPolicy } = require('../domain/policy_check.cjs');
const { verifyGrant, mintGrant } = require('./grant.cjs');

const VERSION = 'C1';
const MAX_BODY_BYTES = 65536; // 64 KiB hard cap; the server also caps, this is defense in depth
const MAX_TEXT = 8000;        // reject absurd inputs early (policy still enforces its own 2000 limit)

function json(status, obj) { return { status, json: obj }; }
function parseBody(rawBody) {
  if (rawBody === undefined || rawBody === null || rawBody === '') return {};
  const s = typeof rawBody === 'string' ? rawBody : String(rawBody);
  if (Buffer.byteLength(s, 'utf8') > MAX_BODY_BYTES) { const e = new Error('body too large'); e.tooLarge = true; throw e; }
  return JSON.parse(s);
}

// Build the preview object for a proposed spoken change. Pure; no persistence.
function buildPreview({ agentId, proposedText, currentText, overrides }, now) {
  const normalizedText = normalize(proposedText);
  let classification = classify(normalizedText, { now });
  const applied = [];
  if (overrides && typeof overrides === 'object') {
    const r = reclassify(classification, overrides, { now });
    if (!r.ok) return { ok: false, code: r.code };
    classification = r.classification;
    for (const o of classification.overrides) applied.push(o);
  }
  const policy = checkPolicy({ classification, finalText: normalizedText });
  const diff = diffWords(typeof currentText === 'string' ? currentText : '', normalizedText);
  const hash = contentHash({
    agentId,
    text: normalizedText,
    type: classification.type,
    category: classification.category,
    sensitivity: classification.sensitivity,
    expiresAt: classification.expiresAt,
  });
  return {
    ok: true,
    preview: {
      agentId,
      normalizedText,
      classification: {
        type: classification.type,
        category: classification.category,
        sensitivity: classification.sensitivity,
        expiresAt: classification.expiresAt,
        reasons: classification.reasons,
        overrides: applied,
      },
      policy: {
        allowed: policy.allowed,
        elevated: policy.elevated,
        requiresQueue: policy.requiresQueue,
        allowedChannels: policy.allowedChannels,
        violations: policy.violations,
      },
      diff,
      contentHash: hash,
    },
  };
}

// createPreviewHandler -> handle({ method, path, headers, rawBody }) -> { status, json }
function createPreviewHandler({ key, allowDevGrant = false, now = Date.now } = {}) {
  const clock = typeof now === 'function' ? now : () => now;

  return function handle(req) {
    const method = (req && req.method ? String(req.method) : 'GET').toUpperCase();
    const rawPath = req && req.path ? String(req.path) : '/';
    const path = rawPath.split('?')[0].replace(/\/+$/, '') || '/';
    const headers = (req && req.headers) || {};

    if (method === 'GET' && path === '/k136s/health') {
      return json(200, { ok: true, service: 'k136s-preview', version: VERSION, devGrant: !!allowDevGrant });
    }

    // Dev-only grant issuer. Present ONLY when explicitly enabled; the real vault-backed issuer is K136S-D.
    if (method === 'POST' && path === '/k136s/grant/dev') {
      if (!allowDevGrant) return json(404, { error: 'not found' });
      let body;
      try { body = parseBody(req && req.rawBody); }
      catch (e) { return e.tooLarge ? json(413, { error: 'payload too large' }) : json(400, { error: 'invalid JSON body' }); }
      const agentId = body && body.agentId;
      if (typeof agentId !== 'string' || !agentId) return json(400, { error: 'agentId required' });
      try {
        const { token, payload } = mintGrant({ agentId, now: clock(), key });
        return json(200, { grant: token, aud: payload.aud, agentId: payload.agentId, expiresAt: payload.exp, note: 'dev grant — not vault-backed (K136S-C)' });
      } catch (e) {
        return json(500, { error: 'cannot mint grant', code: e && e.code });
      }
    }

    if (method === 'POST' && path === '/k136s/preview') {
      const token = headers['x-k136s-grant'] || headers['X-K136S-Grant'];
      const v = verifyGrant(token, { now: clock(), key });
      if (!v.ok) return json(401, { error: 'preview grant required', code: v.code });

      let body;
      try { body = parseBody(req && req.rawBody); }
      catch (e) { return e.tooLarge ? json(413, { error: 'payload too large' }) : json(400, { error: 'invalid JSON body' }); }

      const agentId = body && body.agentId;
      if (typeof agentId !== 'string' || !agentId) return json(400, { error: 'agentId required' });
      if (agentId !== v.payload.agentId) return json(403, { error: 'grant not valid for this agent', code: 'AGENT_MISMATCH' });

      const proposedText = body && body.proposedText;
      if (typeof proposedText !== 'string' || !proposedText.trim()) return json(400, { error: 'proposedText required' });
      if (proposedText.length > MAX_TEXT) return json(413, { error: `proposedText exceeds ${MAX_TEXT} characters` });
      if (body.currentText !== undefined && typeof body.currentText !== 'string') return json(400, { error: 'currentText must be a string' });

      const result = buildPreview({ agentId, proposedText, currentText: body.currentText, overrides: body.overrides }, clock());
      if (!result.ok) return json(422, { error: 'cannot classify with the supplied override', code: result.code });
      // NB: a preview is READ-ONLY. This returns what the secure flow WOULD show; it never commits,
      // and it never issues an approval token. policy.allowed:false is a valid, successful preview.
      return json(200, result.preview);
    }

    return json(404, { error: 'not found' });
  };
}

module.exports = Object.freeze({ createPreviewHandler, buildPreview, VERSION, MAX_BODY_BYTES, MAX_TEXT });
