# K136S-E — The Write Path

E turns an approved change into a memory row — the `approve → write → verify` leg of the secure flow — over HTTP, with the same invariants K136S-B encoded in the state machine. It is built against a **pluggable writer** and a **pluggable identity resolver**: the standalone preview server stubs both (env-gated, dev-only), and F binds the backend's auth and the backend's own `korlixAgentSaveMemoryV1`. E holds no service-role key, adds no migration, and never writes to the real database.

## What the backend contract dictated

The preflight extracted the real write helper: `korlixAgentSaveMemoryV1({ client, userId, agentId, body })`. It **requires a confirmation flag in the body** (`agent_memory_confirmation_required`), validates the user and agent ownership, tags the row with the agent's latest `version_id`, derives the key with `korlixAgentMemoryKeyV1` (`body.memory_key ?? body.key`), and **upserts by key** — an existing key is `.update`d in place, a new key is `.insert`ed. E therefore:

- sets the confirmation flag **only after a single-use approval token has been consumed** — K136S's approval *is* the backend's confirmation;
- aligns with upsert-by-key instead of B's "new row + supersede pointer": a change to an existing key updates in place, and the previous content + hash are recorded in `metadata.k136s.superseded`, so **rollback is simply an approved write back to the previous content**;
- reuses the backend's validation by calling the helper itself at F rather than reimplementing memory semantics.

## Endpoints (both require the preview grant from D)

| Endpoint | Body | Result |
| --- | --- | --- |
| `POST /k136s/approve/request` | `{ sessionId, agentId, contentHash, elevated? }` | `200 { approvalToken, approvalId, expiresAt, elevated }` — a 32-byte single-use token, 120-s TTL, **SHA-256 stored only**, bound to session + user + account + agent + contentHash. |
| `POST /k136s/approve/confirm` | `{ sessionId, agentId, contentHash, approvalToken, channel, preview }` | `200 { state: "VERIFIED", memoryId, memoryKey, contentHash, verifiedAt, superseded }`, or a refusal (below). |

`confirm` runs, in order: rebuild the change from `preview` and **recompute its hash** (a forged `contentHash` is `409 HASH_MISMATCH`); re-check policy on the final text (`422 POLICY_DENIED` / `REQUIRES_QUEUE`); enforce the **elevated rule** — `channel:"typed"` (`403 ELEVATED_REQUIRES_TYPED`), a grant minted within 60 s (`403 ELEVATED_REQUIRES_FRESH_VAULT`; the grant's `iat` is the vault-verify time), and an approval that was issued as elevated (`403 ELEVATED_NOT_DECLARED`); **consume the approval atomically** (`409 ALREADY_CONSUMED`, `410 EXPIRED`, `403 BINDING_MISMATCH`, `401 NOT_FOUND`); then and only then **write**; then **read back by key** and verify content + hash + enabled/active/not-deleted → `VERIFIED`, else `409 VERIFICATION_FAILED` (`state: "REJECTED"`) with an `ALERT` audit event. A thrown write is `502 WRITE_FAILED` + `ALERT`. Without a writer the approval is still consumed and the write is refused `503 WRITER_NOT_CONFIGURED` — never a silent no-op. Every outcome is appended to the insert-only audit store.

## Injection points

| Dependency | Preview server (this stage) | Bound at F |
| --- | --- | --- |
| `identity(headers) → { userId, accountId }` | `K136S_ALLOW_DEV_IDENTITY=1` reads `x-k136s-dev-user` / `x-k136s-dev-account`; otherwise `503 IDENTITY_NOT_CONFIGURED` | backend auth (the same resolution the vault route uses) |
| `writer` (`write`, `readByKey`) | `K136S_ALLOW_FAKE_WRITER=1` → in-memory fake with upsert-by-key semantics; otherwise `503 WRITER_NOT_CONFIGURED` | `createBackendMemoryWriter({ saveMemory: (a) => korlixAgentSaveMemoryV1({ client, ...a }), loadMemoryByKey: (a) => korlixAgentLoadMemoryRowByKeyV1({ client, ...a }) })` |
| approvals + audit store | B's in-memory store (process-local) | the K136S tables (`k136s_approvals`, `k136s_audit_events`, `k136s_learning_sessions`), applied only at F |

## Modules

| File | Change |
| --- | --- |
| `adapters/memory_writer.cjs` | **new.** `toBackendSaveBody` (change → memories columns; dual names `memory_key`/`key`, `content`/`memory_text`; `source: "k136s_spoken_learning"`; `metadata.k136s` with hash, session, approval, superseded), `deriveMemoryKey` (explicit key or a deterministic `k136s:<type>:<category>:<hash16>`), `createBackendMemoryWriter`, `createFakeMemoryWriter`, `toReadBackView`. |
| `http/approval_routes.cjs` | **new.** `createApprovalRoutes({ store, approvals, writer, identity, now })` → `{ request, confirm }`. Pure w.r.t. I/O apart from the injected writer/identity. |
| `http/preview_handler.cjs` | **edited.** `handle.async` serves the two approve routes after verifying the grant; health adds `stage: "E1"` and `approvals: bool` (`version` and `build` unchanged for C/D test compatibility). |
| `http/preview_server.cjs` | **edited.** Builds the store/approval service, the env-gated dev identity and fake writer, and passes `approvalRoutes` through; logs flags by name only. |

## F-verification items (isolated on purpose)

1. **Confirmation field name.** `toBackendSaveBody` sets `body.confirm = true` by default; `createBackendMemoryWriter({ confirmationField })` overrides it. F confirms the name `korlixAgentRequireConfirmationV1` checks.
2. **Row-mapper input names.** The body uses the memories table's column names (both dual forms). F confirms against `korlixAgentMemoryDatabaseRowV1`; any adjustment is confined to `toBackendSaveBody`.

## Security posture

Write only after a consumed, bound, single-use approval; hashes recomputed server-side so the client cannot forge a change; elevated changes never on voice and never on a stale vault; read-back verification with `REJECTED + ALERT` on mismatch; insert-only audit for every outcome; no service-role key, no migration, no real DB write in this stage; identities and secrets never logged.

## Tests (`backend/test/k136s_write_path.test.cjs`, 14)

Writer mapping and key derivation; fake upsert-by-key and confirmation refusal; backend adapter calls the injected helpers in the backend's shape; request issuance/bindings/identity refusals; the full VERIFIED flow with audit trail; replay; supersede-in-place with previous content recorded; forged hash / expired / wrong binding / bad input; policy denial; all three elevated rules; write failure and read-back mismatch → REJECTED + ALERT; writer-absent 503; handler wiring and health; and a real-socket end-to-end (dev-grant → preview → request → confirm → VERIFIED → replay refused).

## Deferred to K136S-F

Binding real identity and `korlixAgentSaveMemoryV1`; the K136S tables and migration; mounting into `backend/server.js`; driving B's full state machine from the frontend-originated events (trigger, mic mute, capture); realtime context refresh; the Flutter UI.
