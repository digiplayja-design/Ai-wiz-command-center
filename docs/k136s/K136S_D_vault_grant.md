# K136S-D — Vault-Backed Grant Issuer

D binds the preview grant to the **real** Brain Vault. C proved the HTTP layer and the grant gate with an env-gated dev issuer; D adds `POST /k136s/grant`, which forwards the caller's vault password **once**, over loopback, to the existing backend route and mints a grant only when the vault says yes. K136S still writes nothing.

## Flow

```
client ──POST /k136s/grant {agentId, vaultPassword} + auth headers──▶ k136s-preview (7461)
                                                                        │ relay allow-listed headers
                                                                        │ forward ONCE over loopback
                                                                        ▼
                                          POST http://127.0.0.1:8787/api/brain-vault/password/verify {vaultPassword}
                                                                        │ backend authenticates the user,
                                                                        │ enforces account-manager rule,
                                                                        │ checks scrypt hash, manages lockout
                                                                        ▼
                 200 {success:true, verified:true, managerMode, passwordVersion} ──▶ mint 60-s grant ──▶ 200 {grant, expiresAt, managerMode, passwordVersion}
                 4xx {code}                                                     ──▶ relay status + code, NO grant
                 unreachable / timeout / malformed                              ──▶ 503 / 502, NO grant
```

The grant is the same HMAC token C enforces on `POST /k136s/preview`, now also carrying `pv` (vault `passwordVersion`) and `mgr` (`managerMode`) so a later password change can invalidate outstanding grants.

## Contract mapping (from the preflight extraction)

| Backend behaviour | D outcome |
| --- | --- |
| body field `vaultPassword` (normalized, policy-checked) | D sends `{ vaultPassword }` verbatim, nothing else |
| credential loaded by `user.id`; `RequireAccountManagerV2(user, credential)` | D relays the caller's auth headers and lets the backend decide identity and role |
| `200 { success:true, verified:true, managerMode, passwordVersion, unlockExpiresAt }` | **grant minted** |
| `401 brain_vault_password_incorrect` | 401, same code, no grant |
| `429 brain_vault_password_rate_limited` (lock active) | 429, same code, `lockedUntil` relayed if present, no grant |
| `409 brain_vault_password_not_configured` | 409, same code, no grant |
| 403 (not the account manager) / 400 (policy) | relayed, no grant |
| `RecordFailureV2` / `ClearFailuresV2` / 15-minute lock | **backend's own bookkeeping; D keeps no counters** |
| `200` that is not `success && verified`, or non-JSON | 502 `BACKEND_UNEXPECTED`, no grant |
| connection refused / timeout | 503 `BACKEND_UNAVAILABLE`, no grant |

## Modules

| File | Change |
| --- | --- |
| `http/vault_grant_issuer.cjs` | **new.** `createHttpVerifier({ backendUrl, timeoutMs })` performs the single forwarded request (`node:http`/`node:https`, response capped at 64 KiB). `issueVaultGrant({...})` decides the outcome from the verifier's `{ status, body }` and mints via `signGrant`. `parseRelayHeaders` builds the allow-list. |
| `http/preview_handler.cjs` | **edited.** Adds `handle.async(req)`, which serves `POST /k136s/grant` (must await the backend) and otherwise delegates to the unchanged synchronous `handle`. Health now also reports `build: "D1"` and `vaultGrant: true/false`; `version` stays `"C1"` for API compatibility. |
| `http/preview_server.cjs` | **edited.** `createServer` accepts `vaultVerifier` / `relayHeaderNames` / `grantTtlMs` and awaits `handle.async`. `start()` builds the real verifier from env and logs the backend URL and relay header *names* only. |

`grant.cjs` is untouched: `verifyGrant` already ignores extra claims, so D-minted grants validate with C's verifier.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `K136S_GRANT_KEY` | *(required)* | HMAC key; server refuses to start without it |
| `K136S_BACKEND_URL` | `http://127.0.0.1:8787` | where the verify route lives (loopback) |
| `K136S_RELAY_HEADERS` | `authorization,cookie` | caller headers relayed to the backend; change here if the backend keys off a custom header |
| `K136S_VERIFY_TIMEOUT_MS` | `5000` | forward timeout; on expiry the grant request fails closed (503) |
| `K136S_PORT` / `K136S_HOST` | `7461` / `127.0.0.1` | as in C |
| `K136S_ALLOW_DEV_GRANT` | `0` | C's dev issuer; unchanged, still off by default |

## Security posture

1. **One forward, loopback only.** The password is placed into exactly one outbound request to the configured backend URL and is not retained after the request ends.
2. **Never logged, stored, minted, or echoed.** Tests sweep every outcome's response and all console output for the fixture password and assert its absence; they also decode the grant payload and assert it is not inside.
3. **Backend is the authority.** D relays credentials rather than re-implementing auth; identity, the account-manager rule, hash verification, failure counting, and the lockout all stay in the backend.
4. **Allow-listed relay.** Only the configured header names cross to the backend; everything else (including `x-k136s-grant`, `host`, `x-forwarded-*`) is dropped. Tested.
5. **Fail closed everywhere.** Missing verifier, missing fields, unexpected 200s, non-JSON, refused connections, and timeouts all end without a grant.
6. **No new counters, no DB, no state.** Read-only on K136S's side.

## Tests (`backend/test/k136s_vault_grant.test.cjs`)

Issuer outcomes for every backend status; a `200` that is not `success && verified`; unreachable and missing verifier; 400 on missing fields with the backend never called; the header allow-list and its configurability; the password-leak sweep (responses, console, grant payload); handler wiring (`handle.async`, health flags, grant → preview end-to-end, issuer-off 503, dev-grant still absent); and two real-socket tests against an in-process fake backend proving the forward happens exactly once to `/api/brain-vault/password/verify` with the relayed `authorization` header (and without non-allow-listed headers), plus down/hanging backends yielding 503. Built-ins only.

## Deferred to K136S-E

The write path: HTTP approval issuance/consumption, committing an approved change to `korlix_live_convo_agent_memories`, session persistence in the K136S tables, supersede/rollback. Frontend and mic/realtime coupling and mounting into `backend/server.js` remain K136S-F.
