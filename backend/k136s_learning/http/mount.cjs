'use strict';
// K136S-F1 backend mount.
//
// mountK136S(app, { supabaseAdmin, requireUser, korlixAgentSaveMemoryV1, korlixAgentListMemoriesV1 })
// wires the K136S handler (B domain + C preview + D vault grant + E write path) into the REAL backend:
//   • identity  — requireUser(req) from server.js (the same resolver the vault route uses)
//   • vault     — D's issuer forwards once over loopback to this backend's own
//                 POST /api/brain-vault/password/verify (no reimplementation of vault logic)
//   • writer    — E's backend writer bound to korlixAgentSaveMemoryV1 (confirmation field
//                 `confirmed`, body augmented with `label`/`expiresAt`/`memory` for the row mapper)
//                 and read-back via korlixAgentListMemoriesV1 filtered by key
//   • store     — in-memory by default; K136S_STORE=supabase mirrors approvals + audit to the
//                 K136S tables (after the migration is applied)
// Dev grant and dev identity are HARD-OFF here. server.js is an ES module and this file is CJS:
// it is loaded with a default import and must NOT require the ESM agents module — the helpers are
// passed in. Nothing in here throws into the host: a K136S problem logs and fails closed.
const { createPreviewHandler } = require('./preview_handler.cjs');
const { createHttpVerifier, parseRelayHeaders, DEFAULT_TIMEOUT_MS } = require('./vault_grant_issuer.cjs');
const { createApprovalRoutes } = require('./approval_routes.cjs');
const { createApprovalService } = require('../services/approval_service.cjs');
const { createMemoryStore } = require('../adapters/memory_store.cjs');
const { createSupabaseStore } = require('../adapters/supabase_store.cjs');
const { createBackendMemoryWriter } = require('../adapters/memory_writer.cjs');

const STAGE = 'F1';
const ROUTES = Object.freeze([
  ['get', '/k136s/health'], ['post', '/k136s/grant'], ['post', '/k136s/preview'],
  ['post', '/k136s/approve/request'], ['post', '/k136s/approve/confirm'],
]);
const REQ = Symbol('k136s.req');
const CONFIRMATION_FIELD = 'confirmed'; // verified at F preflight: korlixAgentRequireConfirmationV1 reads confirmed/approved

const isFn = (f) => typeof f === 'function';

// user → { userId, accountId }. Account-owner model: account = app_metadata.account_id if present, else the user id.
function identityFromUser(user) {
  const u = user && user.user && !user.id ? user.user : user;
  if (!u || typeof u.id !== 'string' || !u.id) return null;
  const am = (u.app_metadata && typeof u.app_metadata === 'object') ? u.app_metadata : {};
  const um = (u.user_metadata && typeof u.user_metadata === 'object') ? u.user_metadata : {};
  const accountId = (typeof am.account_id === 'string' && am.account_id) || (typeof um.account_id === 'string' && um.account_id) || u.id;
  return { userId: u.id, accountId };
}

// Augment E's body for the backend row mapper (reads memory.kind/content/label/source/...).
function augmentSaveBody(body) {
  const b = Object.assign({}, body);
  if (b.label === undefined && typeof b.summary === 'string') b.label = b.summary;
  if (b.expiresAt === undefined && b.expires_at !== undefined) b.expiresAt = b.expires_at;
  if (b.memoryKey === undefined && typeof b.memory_key === 'string') b.memoryKey = b.memory_key;
  // mirror under `memory` so the helper reads correctly whether it takes the body root or body.memory
  const mirror = Object.assign({}, b); delete mirror.memory;
  b.memory = mirror;
  return b;
}

function normalizeList(result) {
  if (Array.isArray(result)) return result;
  if (result && typeof result === 'object') for (const k of ['items', 'memories', 'rows', 'data']) if (Array.isArray(result[k])) return result[k];
  return [];
}
const keyOf = (r) => r && (r.memory_key || r.memoryKey || r.key || null);

function buildWriter({ supabaseAdmin, saveMemory, listMemories }) {
  return createBackendMemoryWriter({
    confirmationField: CONFIRMATION_FIELD,
    saveMemory: async ({ userId, agentId, body }) => saveMemory({ client: supabaseAdmin, userId, agentId, body: augmentSaveBody(body) }),
    loadMemoryByKey: async ({ userId, agentId, memoryKey }) => {
      const rows = normalizeList(await listMemories({ client: supabaseAdmin, userId, agentId }));
      const hit = rows.find((r) => keyOf(r) === memoryKey) || null;
      if (!hit) return null;
      // tolerate domain objects that rename metadata
      if (hit.metadata === undefined && hit.meta && typeof hit.meta === 'object') return Object.assign({}, hit, { metadata: hit.meta });
      return hit;
    },
  });
}

function mountK136S(app, deps = {}) {
  const log = deps.log || console;
  const env = deps.env || process.env;
  const now = isFn(deps.now) ? deps.now : Date.now;
  const info = (m) => { try { log.log(`[k136s] ${m}`); } catch { /* ignore */ } };
  const warn = (m) => { try { log.warn(`[k136s] ${m}`); } catch { /* ignore */ } };

  try {
    if (!app || !isFn(app.get) || !isFn(app.post)) return { ok: false, mounted: false, error: 'app missing get/post' };
    const { supabaseAdmin, requireUser, korlixAgentSaveMemoryV1: saveMemory, korlixAgentListMemoriesV1: listMemories } = deps;
    const key = typeof env.K136S_GRANT_KEY === 'string' ? env.K136S_GRANT_KEY : '';
    const configured = key.length >= 16;
    const problems = [];
    if (!configured) problems.push('K136S_GRANT_KEY missing or shorter than 16 chars');
    if (!isFn(requireUser)) problems.push('requireUser not provided');
    if (!supabaseAdmin) problems.push('supabaseAdmin not provided');
    if (!isFn(saveMemory)) problems.push('korlixAgentSaveMemoryV1 not provided');
    if (!isFn(listMemories)) problems.push('korlixAgentListMemoriesV1 not provided');

    // Not configured: register the routes so the surface is visible, but every call fails closed.
    if (problems.length) {
      warn(`NOT configured (${problems.join('; ')}) — /k136s/* routes will return 503`);
      for (const [m, p] of ROUTES) app[m](p, (req, res) => {
        res.set && res.set('cache-control', 'no-store');
        res.status(503).json({ ok: false, error: 'K136S is not configured on this backend', code: 'K136S_NOT_CONFIGURED', stage: STAGE, problems });
      });
      return { ok: false, mounted: true, configured: false, problems, routes: ROUTES.map((r) => r[1]) };
    }

    const port = Number(deps.port || env.PORT || 8787);
    const backendUrl = deps.backendUrl || `http://127.0.0.1:${port}`;
    const relayHeaderNames = parseRelayHeaders(env.K136S_RELAY_HEADERS);
    const timeoutMs = Number(env.K136S_VERIFY_TIMEOUT_MS || DEFAULT_TIMEOUT_MS);
    const vaultVerifier = isFn(deps.vaultVerifier) ? deps.vaultVerifier : createHttpVerifier({ backendUrl, timeoutMs });

    const useSupabase = String(env.K136S_STORE || '').toLowerCase() === 'supabase';
    const store = useSupabase ? createSupabaseStore({ client: supabaseAdmin, now, log }) : createMemoryStore();
    const approvals = createApprovalService({ store, now });

    // Identity: resolved from the express request attached to the headers object per call.
    const identity = async (headers) => {
      const req = headers && headers[REQ];
      if (!req) return null;
      const user = await requireUser(req); // throws → E treats as 401 UNAUTHENTICATED
      return identityFromUser(user);
    };

    const writer = buildWriter({ supabaseAdmin, saveMemory, listMemories });
    const approvalRoutes = createApprovalRoutes({ store, approvals, writer, identity, now });
    const handle = createPreviewHandler({ key, allowDevGrant: false, now, vaultVerifier, relayHeaderNames, approvalRoutes });

    const expressHandler = async (req, res) => {
      try {
        const headers = Object.assign({}, req.headers || {});
        Object.defineProperty(headers, REQ, { value: req, enumerable: false });
        const rawBody = typeof req.body === 'string' ? req.body : (req.body && typeof req.body === 'object' ? JSON.stringify(req.body) : '');
        const out = await handle.async({ method: req.method, path: req.originalUrl || req.url || req.path, headers, rawBody });
        res.set && res.set('cache-control', 'no-store');
        const json = (out && out.json) || { error: 'internal error' };
        if (out && out.status === 200 && json && typeof json === 'object' && json.service === 'k136s-preview') Object.assign(json, { mounted: true, stage: STAGE, store: store.kind || 'memory' });
        res.status((out && out.status) || 500).json(json);
      } catch (e) {
        warn(`request failed: ${e && e.message || e}`);
        try { res.status(500).json({ error: 'internal error', code: 'K136S_INTERNAL' }); } catch { /* ignore */ }
      }
    };
    for (const [m, p] of ROUTES) app[m](p, expressHandler);
    info(`mounted ${ROUTES.length} routes (stage ${STAGE}; store ${store.kind || 'memory'}; vault -> ${backendUrl}; relay ${relayHeaderNames.join(',')}; dev-grant off; dev-identity off)`);
    return { ok: true, mounted: true, configured: true, routes: ROUTES.map((r) => r[1]), store: store.kind || 'memory', backendUrl, _internals: { store, approvals, writer, handle } };
  } catch (e) {
    warn(`mount failed: ${e && e.message || e}`);
    return { ok: false, mounted: false, error: String(e && e.message || e) };
  }
}

module.exports = Object.freeze({ mountK136S, identityFromUser, augmentSaveBody, buildWriter, ROUTES, STAGE, CONFIRMATION_FIELD, REQ });
