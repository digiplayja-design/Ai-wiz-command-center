# K136S-C — Read-Only Preview Service

The first wiring stage. C exposes the pure B domain layer over HTTP as a **read-only preview service**: a client posts a proposed spoken change and gets back exactly what the secure flow would show at `PREVIEW_READY` — classification, policy decision, normalized text, a word-level diff, and a content hash — **without any database write and without persisting anything**. C builds on the K136S-B branch and inherits its domain modules unchanged.

## Why a standalone server

Mounting into `backend/server.js` would edit a shared gate file that stays frozen until the K136S-F integration gate. So C ships its own server built on **`node:http`** — no Express, no new dependencies — and binds **one** K136S port (7461, from the reserved 7460–7469 range). It mounts nothing into the live backend and starts only when run directly.

## Modules (`backend/k136s_learning/http/`)

| Module | Responsibility |
| --- | --- |
| `grant.cjs` | Mint and verify a short-lived HMAC **preview grant** (`node:crypto`). A grant asserts only "a preview may be computed for this agent until `exp`". It carries no secret and no vault material. `verifyGrant` fails closed on bad format, signature, audience, or expiry. |
| `preview_handler.cjs` | A **pure** `handle(request) → { status, json }`. Imports only the B domain modules and the grant verifier. Routes the three endpoints, runs normalize → classify → policy → diff → contentHash, and returns the preview. Performs no I/O, no writes, and issues no approval token. |
| `preview_server.cjs` | The `node:http` server that does the I/O the handler avoids: read the body (with a hard size cap), hand a plain request object to the handler, write the JSON response. Exposes `createServer(opts)` (no listen — used by tests on an ephemeral port) and `start()` (reads env, listens). Refuses to start without a grant key. |

## Endpoints

| Method + path | Auth | Behaviour |
| --- | --- | --- |
| `GET /k136s/health` | none | `200 { ok, service, version: "C1", devGrant }` liveness. |
| `POST /k136s/grant/dev` | none | **Dev issuer, present only when `K136S_ALLOW_DEV_GRANT=1`.** Body `{ agentId }` → mints a 60-second grant. Absent (404) otherwise. The real vault-backed issuer is K136S-D. |
| `POST /k136s/preview` | preview grant (`x-k136s-grant`) | Body `{ agentId, proposedText, currentText?, overrides? }`. The grant must be valid and bound to `agentId`. Returns `200` with `{ normalizedText, classification, policy, diff, contentHash }`. **Read-only** — it never commits and never issues an approval token; `policy.allowed:false` is a valid, successful preview that reveals a rejection. |

Bodies are capped at 64 KiB (server and handler), `proposedText` at 8000 characters (policy still enforces its own 2000-character limit inside the preview). Unknown routes are `404`; trailing slashes and query strings are tolerated.

## Environment

`K136S_GRANT_KEY` (required, ≥ 16 chars — the server refuses to start without it); `K136S_PORT` (default 7461); `K136S_HOST` (default `127.0.0.1`, loopback only — forwarding is opt-in via the Codespaces Ports panel); `K136S_ALLOW_DEV_GRANT` (`1` to expose the dev issuer). Run locally with:

```
K136S_GRANT_KEY=<local dev key> K136S_ALLOW_DEV_GRANT=1 node backend/k136s_learning/http/preview_server.cjs
```

## Security posture

1. **Read-only.** No endpoint writes; the preview path imports only the domain layer and never reaches a store, an approval issuer, or the database.
2. **Gated.** `POST /k136s/preview` requires a valid, unexpired, agent-bound HMAC grant; a mismatched agent is rejected `403`, a missing/expired/tampered grant `401`.
3. **Credential-free.** No real password is handled anywhere in C. The dev grant is env-gated and clearly labelled non-vault-backed.
4. **Fail-closed startup.** The server exits rather than run without a grant key.
5. **Pure preview.** Identical inputs yield an identical content hash; the computation has no side effects.

## Deferred to K136S-D (explicitly out of C)

The real vault-backed grant issuer (calls the existing `POST /api/brain-vault/password/verify` and mints a grant only on success); any write to `korlix_live_convo_agent_memories`; HTTP approval issuance/consumption; session persistence; mic/realtime coupling; mounting into `backend/server.js`; and applying the three K136S tables.

## Tests (`backend/test/k136s_preview_handler.test.cjs`)

Grant crypto (round-trip, expiry, tampering, wrong key, wrong audience, not-yet-valid); handler routing and gating (health, grant-required, expired grant, agent mismatch, happy path, purity, prohibited-content preview, accepted override, refused prohibited override, bad JSON, missing fields, dev-grant on/off, trailing-slash/unknown-route); and a real `node:http` round-trip over an ephemeral loopback port including the 64 KiB body cap. Built-ins only; no new dependencies.
