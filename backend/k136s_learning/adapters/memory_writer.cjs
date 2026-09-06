'use strict';
// K136S-E memory writer.
//
// The ONLY component that turns an approved change into a memory row — and it is pluggable:
//   • createBackendMemoryWriter({ saveMemory, loadMemoryByKey, confirmationField })
//       maps a K136S write onto the backend's existing helpers, in the backend's own shape:
//         saveMemory       ≈ (args) => korlixAgentSaveMemoryV1({ client, ...args })      // client injected at F
//         loadMemoryByKey  ≈ (args) => korlixAgentLoadMemoryRowByKeyV1({ client, ...args })
//       The backend upserts by key (existing key → update in place, new key → insert), tags the
//       version row, validates ownership, and requires a confirmation flag in the body. K136S sets
//       that flag ONLY after a single-use approval token has been consumed.
//   • createFakeMemoryWriter() — in-memory, process-local, mirrors upsert-by-key. Used by tests and
//       by the preview server ONLY when K136S_ALLOW_FAKE_WRITER=1. Never persistent.
//
// Nothing in this module touches a database or holds a credential. K136S adds no migration.
const { contentHash } = require('../domain/normalize_diff.cjs');

const DEFAULT_CONFIRMATION_FIELD = 'confirm'; // F-verification item: match korlixAgentRequireConfirmationV1
const K136S_SOURCE = 'k136s_spoken_learning';

// Derive the stable memory key for a K136S change. Explicit key wins; otherwise a deterministic key
// from agent + type + category + the normalized text's hash prefix, so the same change maps to the
// same row and a re-approval updates in place (matching the backend's upsert-by-key).
function deriveMemoryKey({ agentId, type, category, normalizedText, memoryKey }) {
  if (typeof memoryKey === 'string' && memoryKey.trim()) return memoryKey.trim().toLowerCase().slice(0, 120);
  const h = contentHash({ agentId, text: normalizedText, type, category, sensitivity: 'low', expiresAt: null }).slice(0, 16);
  return `k136s:${String(type || 'memory').toLowerCase()}:${String(category || 'general').toLowerCase()}:${h}`;
}

// Build the body the backend's save helper expects. Field names follow the memories table columns
// (which the backend's row mapper reads; dual names like key/memory_key are both provided).
// F-verification items are isolated here: the confirmation field name and the mapper's input names.
function toBackendSaveBody({ change, memoryKey, previous, sessionId, approvalId, confirmationField = DEFAULT_CONFIRMATION_FIELD }) {
  const metadata = {
    k136s: {
      version: 'E1',
      contentHash: change.contentHash,
      type: change.type,
      category: change.category,
      sensitivity: change.sensitivity,
      sessionId: sessionId || null,
      approvalId: approvalId || null,
      superseded: previous ? {
        previousContentHash: previous.contentHash || null,
        previousContent: typeof previous.content === 'string' ? previous.content : null,
        at: previous.at || null,
      } : null,
    },
  };
  const body = {
    memory_key: memoryKey, key: memoryKey,
    kind: 'fact',
    memory_type: String(change.type || 'MEMORY').toLowerCase(),
    category: change.category || null,
    scope: 'agent',
    content: change.normalizedText, memory_text: change.normalizedText,
    summary: change.normalizedText.length > 140 ? change.normalizedText.slice(0, 137) + '...' : change.normalizedText,
    source: K136S_SOURCE,
    session_id: sessionId || null,
    expires_at: change.expiresAt || null,
    metadata,
  };
  body[confirmationField] = true; // set ONLY after a consumed approval — the caller guarantees this
  return body;
}

// Normalize whatever the backend (or the fake) returns into the small shape K136S verifies against.
function toReadBackView(row) {
  if (!row || typeof row !== 'object') return null;
  const md = (row.metadata && typeof row.metadata === 'object') ? row.metadata : {};
  const k = (md.k136s && typeof md.k136s === 'object') ? md.k136s : {};
  return {
    id: row.id || row.memoryId || null,
    memoryKey: row.memory_key || row.memoryKey || row.key || null,
    content: typeof row.content === 'string' ? row.content : (typeof row.memory_text === 'string' ? row.memory_text : (typeof row.text === 'string' ? row.text : null)),
    contentHash: k.contentHash || row.content_hash || null,
    enabled: row.enabled !== false, active: row.active !== false,
    deletedAt: row.deleted_at || row.deletedAt || null, forgottenAt: row.forgotten_at || row.forgottenAt || null,
    updatedAt: row.updated_at || row.updatedAt || null,
  };
}

// The adapter used at F. `saveMemory` and `loadMemoryByKey` are injected (with the backend's client
// already bound). Both are awaited; failures propagate as thrown errors the route turns into REJECTED.
function createBackendMemoryWriter({ saveMemory, loadMemoryByKey, confirmationField = DEFAULT_CONFIRMATION_FIELD } = {}) {
  if (typeof saveMemory !== 'function' || typeof loadMemoryByKey !== 'function') throw new TypeError('backend memory writer requires saveMemory and loadMemoryByKey functions');
  return Object.freeze({
    kind: 'backend',
    async readByKey({ userId, agentId, memoryKey }) {
      const row = await loadMemoryByKey({ userId, agentId, memoryKey, key: memoryKey });
      return toReadBackView(row);
    },
    async write({ userId, agentId, change, memoryKey, previous, sessionId, approvalId }) {
      const body = toBackendSaveBody({ change, memoryKey, previous, sessionId, approvalId, confirmationField });
      const row = await saveMemory({ userId, agentId, body });
      return toReadBackView(row);
    },
  });
}

// In-memory fake with the backend's upsert-by-key behaviour. Keyed by agentId + memoryKey.
function createFakeMemoryWriter({ now = Date.now, failOn = null } = {}) {
  const rows = new Map();
  const keyOf = (agentId, memoryKey) => `${agentId}\u0000${memoryKey}`;
  let seq = 0;
  const fake = {
    kind: 'fake',
    async readByKey({ agentId, memoryKey }) { return toReadBackView(rows.get(keyOf(agentId, memoryKey)) || null); },
    async write({ userId, agentId, change, memoryKey, previous, sessionId, approvalId }) {
      if (typeof failOn === 'function' && failOn({ agentId, memoryKey, change })) throw new Error('fake writer failure');
      const body = toBackendSaveBody({ change, memoryKey, previous, sessionId, approvalId });
      if (body.confirm !== true) throw new Error('agent_memory_confirmation_required');
      const k = keyOf(agentId, memoryKey);
      const existing = rows.get(k);
      const t = new Date(now()).toISOString();
      const row = Object.assign({}, existing || { id: `fake-${++seq}`, created_at: t, created_by: userId }, {
        agent_id: agentId, memory_key: memoryKey, key: memoryKey, kind: body.kind, memory_type: body.memory_type,
        category: body.category, scope: body.scope, content: body.content, memory_text: body.memory_text, summary: body.summary,
        source: body.source, session_id: body.session_id, expires_at: body.expires_at, metadata: body.metadata,
        enabled: true, active: true, updated_at: t,
      });
      rows.set(k, row);
      return toReadBackView(row);
    },
    _rows() { return Array.from(rows.values()).map((r) => Object.assign({}, r)); },
    _reset() { rows.clear(); seq = 0; },
  };
  return Object.freeze(fake);
}

module.exports = Object.freeze({
  createBackendMemoryWriter, createFakeMemoryWriter, toBackendSaveBody, toReadBackView, deriveMemoryKey,
  DEFAULT_CONFIRMATION_FIELD, K136S_SOURCE,
});
