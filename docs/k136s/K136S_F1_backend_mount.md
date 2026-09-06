# K136S-F1 — Backend Mount

F1 is the first stage that crosses the shared gate on purpose: it mounts the K136S handler into the real backend (`backend/server.js`) with the backend's own identity resolver, service-role client, vault route, and memory helpers. Everything K136S built in B–E runs unchanged; F1 only binds the injection points and registers the routes.

## The three edits to `server.js` (additive, anchored, idempotent)

Applied by an anchor-verified script (not a rewrite). Each anchor must match **exactly once** or the edit refuses; a second run refuses because the `// K136S-F1` marker is already present.

| Edit | Anchor | Line added |
| --- | --- | --- |
| (a) import | the line closing `import { … } from "./korlix_live_convo_agents.js";` | `import k136sLearningMount from "./k136s_learning/http/mount.cjs"; // K136S-F1` |
| (b) names | inside that same import list, **only if absent** | `korlixAgentSaveMemoryV1, // K136S-F1` and `korlixAgentListMemoriesV1, // K136S-F1` |
| (c) mount | immediately before the `app.use("/api", (req, res) => {` catch-all | `k136sLearningMount.mountK136S(app, { supabaseAdmin, requireUser, korlixAgentSaveMemoryV1, korlixAgentListMemoriesV1 }); // K136S-F1` |

`server.js` is an ES module; `mount.cjs` is CommonJS and is loaded with a default import. The mount never `require`s the ESM agents module — the helpers are passed in. The mount call precedes the `/api` catch-all so the `/k136s/*` routes are not shadowed, and precedes `app.listen` so it runs at startup.

## What `mountK136S` binds

| Injection point | Bound to |
| --- | --- |
| identity | `requireUser(req)` — the same resolver the vault route uses. `accountId` = `app_metadata.account_id` (or `user_metadata.account_id`) if present, else the user id (account-owner model, as the vault reports `managerMode: "account_owner"`). |
| vault grant | D's issuer forwarding once over loopback to this backend's own `POST /api/brain-vault/password/verify` (`http://127.0.0.1:$PORT`). No vault logic is reimplemented. |
| writer | E's backend writer with `confirmationField: "confirmed"` (verified against `korlixAgentRequireConfirmationV1`). `saveMemory` calls `korlixAgentSaveMemoryV1({ client: supabaseAdmin, userId, agentId, body })` after augmenting the body for the row mapper (`label` from `summary`, `expiresAt`, `memoryKey`, and a `memory` mirror). Read-back uses `korlixAgentListMemoriesV1` filtered by key (`LoadMemoryRowByKeyV1` is not exported). |
| store | in-memory by default. `K136S_STORE=supabase` selects the mirroring store (below). |
| dev switches | **hard-off**: no dev grant, no dev identity, regardless of env. |

Health (`GET /k136s/health`) adds `mounted: true`, `stage: "F1"`, `store`. If `K136S_GRANT_KEY` is missing or any dependency is absent, the five routes are still registered but every call returns `503 K136S_NOT_CONFIGURED` with the reasons — the backend never fails to start because of K136S, and K136S never runs half-configured.

## Store modes and the migration

`supabase/migrations/202609060001_k136s_learning_build136.sql` creates `k136s_learning_sessions`, `k136s_approvals`, `k136s_audit_events` (RLS on, all grants revoked from `anon`/`authenticated`, service-role only). **F1 stages it; applying it is F3.**

`adapters/supabase_store.cjs` (selected by `K136S_STORE=supabase`) keeps the in-memory store as the authoritative, atomic source for the running process — B's approval service calls the store synchronously, and changing that is out of F1's scope — and **mirrors** asynchronously: approvals are inserted on issue (hash only) and marked `consumed_at` on consume; every audit event is inserted. Mirror failures are counted and logged, never surfaced to the request. Net effect now: a **durable audit trail** and DB visibility of approvals on a single instance. Making approvals DB-atomic (multi-instance safe) needs an async approval service — a follow-up with its own approval since it edits a B module.

## Environment (backend)

`K136S_GRANT_KEY` (required, ≥16 chars); `K136S_STORE` (`supabase` after the migration is applied; otherwise memory); `K136S_RELAY_HEADERS` (default `authorization,cookie`); `K136S_VERIFY_TIMEOUT_MS` (default 5000). `PORT` is reused for the vault loopback.

## Also in F1

`backend/test/k136s_vault_grant.test.cjs`: the "backend down" case now uses a server that accepts and immediately resets the connection instead of an unbound ephemeral port (which a parallel test process could re-bind), removing the rare flake seen in E's push.

## Verification in F1

Mount tests (stub Express app, fake `requireUser`/client/helpers): route registration; not-configured fail-closed; dev endpoints not even routed; the full grant → preview → request → confirm → VERIFIED flow through the registered routes with the real-identity binding and the `confirmed` flag; the augmented body reaching the helper with the service client; approval bound to the account from `app_metadata`; replay refused; cross-user consume refused; read-back through the list helper with REJECTED + ALERT when nothing comes back; `K136S_STORE=supabase` mirroring with the raw token never leaving the process; the host is never thrown at. Store tests cover columns, consume mirroring, and swallowed failures. A runnable ESM fixture proves the edited `server.js` imports the CJS mount and the helper names and mounts at startup.

The F1 guard: the B-stage no-conflict guard test flags any shared-file edit by design, so F1's commit block runs every suite except that guard and applies its own stricter check instead — the diff must be exactly the 8 approved paths, `server.js` must be additions-only (≤4 lines), and added lines are secret-scanned.

## Left for F3 (live, with the backend up)

Confirm the memory row's `kind` vocabulary the runtime loader expects (F1 sends `fact`), confirm `korlixAgentListMemoriesV1`'s return shape against the read-back normalizer, apply the migration, set `K136S_GRANT_KEY` (and `K136S_STORE=supabase`) on Render, deploy, and run grant → preview → approve → row-visible.
