# K136S-B — Domain Model and State Machine

Pure, dependency-free domain layer for Nova's secure spoken-learning flow. Everything here is deterministic and side-effect-free: the state machine is a reducer that returns the next (frozen) session plus a list of **effects** for an outer adapter to perform later. No network, no database, no clock of its own — the caller passes `now`. Phase B is **tests + local commit only**; nothing in here is wired into a server.

## Module map (`backend/k136s_learning/`)

| Module | Responsibility |
| --- | --- |
| `domain/state_machine.cjs` | The reducer. `createSession(input, now)` → frozen `IDLE` session; `transition(session, event, ctx)` → `{ ok, session, effects, code, message }`. Fail-closed; never throws on bad events. Emits a `WRITE` effect only on a validated `APPROVE`. |
| `domain/classifier.cjs` | `classify(text, {now})` sorts an utterance into `PROHIBITED > TOOL_PERMISSION > PROFILE > TRAINING > MEMORY`, assigns a category and a low/medium/high sensitivity, and parses expiry phrases deterministically. `reclassify` applies a bounded manager override. |
| `domain/policy_check.cjs` | `check({classification, finalText})` → `{ allowed, elevated, requiresQueue, allowedChannels, violations }`. Blocks prohibited/secret-like/platform-control/cross-tenant content; elevates profile and high-sensitivity changes; routes destructive tool-permission changes to a queue. |
| `domain/normalize_diff.cjs` | `normalize` cleans a spoken utterance (wake word, fillers, lead-ins, punctuation). `contentHash` is a stable SHA-256 over the canonical field set. `diffWords` produces a word-level equal/insert/delete diff for the preview. |
| `domain/similarity.cjs` | `findDuplicates` (identical hash, or char-trigram Jaccard ≥ 0.85 within the same agent + type) and `findContradictions` (same agent + category + subject, below the duplicate threshold, negation flip or different value). |
| `services/approval_service.cjs` | `issue`/`consume` single-use approval tokens. Stores only a SHA-256 of the token, 120-second TTL, bound to session + user + account + agent + content hash. `consume` is atomic and single-use. |
| `adapters/memory_store.cjs` | In-memory store used by the tests and the service: approvals (with an atomic `consumeIfValid`), sessions, and an insert-only audit log. Mirrors the shape of the future Supabase-backed store; nothing here is networked. |
| `index.cjs` | Barrel exports. `K136S_VERSION = 'B1'`. Not mounted anywhere. |

## States

| State | Meaning |
| --- | --- |
| `IDLE` | Fresh session; nothing requested. |
| `TRIGGERED` | An authorized account-manager trigger phrase matched inside live conversation. |
| `AUTH_REQUIRED` | Mic muted; the Brain Vault password field is shown. |
| `AUTHENTICATED` | Vault verification succeeded and is fresh; capture may begin. |
| `CAPTURING` | Accumulating the spoken change text (bounded). |
| `CLASSIFYING` | Capture ended; classifier + policy run. |
| `PREVIEW_READY` | A normalized preview + diff is shown for review. |
| `CONFIRMATION_REQUIRED` | An approval token has been issued and is awaited. |
| `COMMITTING` | Approval consumed; a single `WRITE` effect has been emitted. |
| `VERIFIED` | The adapter confirmed the write matches the approved content. Terminal (success). |
| `CANCELLED` / `EXPIRED` / `REJECTED` | Terminal (stop). |

Terminal states are immutable: any event other than a read returns the same session unchanged.

## Events → guards → next state (happy path and the important refusals)

| From | Event | Guard (must hold) | To | Effects |
| --- | --- | --- | --- | --- |
| `IDLE` | `TRIGGER` | actor is the account manager **and** `actor.userId === session.userId`, `source === 'live_convo'`, `triggerMatched === true` | `TRIGGERED` | `MUTE_MIC`, `AUDIT` |
| `TRIGGERED` | `MIC_MUTED` | `micMuted === true` | `AUTH_REQUIRED` | `SHOW_VAULT_FIELD` |
| `AUTH_REQUIRED` | `VAULT_VERIFIED` | verification is bound to this user + account and its timestamp is fresh | `AUTHENTICATED` | `UNMUTE_MIC`, `AUDIT` |
| `AUTH_REQUIRED` | `VAULT_FAILED` | — (5th failure → `REJECTED` / `VAULT_LOCKED`) | `AUTH_REQUIRED` | `AUDIT` |
| `AUTHENTICATED` | `CAPTURE_TEXT` | within character limit | `CAPTURING` | — |
| `CAPTURING` | `CAPTURE_TEXT` | cumulative length ≤ 4000 | `CAPTURING` | — |
| `CAPTURING` | `END_CAPTURE` | — | `CLASSIFYING` | `CLASSIFY` |
| `CLASSIFYING` | `CLASSIFIED` | not prohibited; policy allows (or a queue path exists) | `PREVIEW_READY` | `SHOW_PREVIEW` |
| `CLASSIFYING` | `CLASSIFIED` | prohibited, or policy-denied with no queue | `REJECTED` | `AUDIT` |
| `PREVIEW_READY` | `EDIT` | — | `PREVIEW_READY` | `SHOW_PREVIEW` |
| `PREVIEW_READY` | `REQUEST_CONFIRMATION` | — | `CONFIRMATION_REQUIRED` | `AUDIT` |
| `CONFIRMATION_REQUIRED` | `APPROVE` | a **consumed** approval matching `approvalId` + `contentHash` + user/account/agent; elevated changes additionally require `channel === 'typed'` and a vault re-verification within 60 s | `COMMITTING` | `WRITE`, `AUDIT` |
| `CONFIRMATION_REQUIRED` | `TOKEN_EXPIRED` | — | `PREVIEW_READY` | `AUDIT` |
| `COMMITTING` | `COMMITTED` | the reported write matches the approved content hash | `VERIFIED` | `REFRESH_CONTEXT`, `AUDIT` |
| `COMMITTING` | `COMMITTED` | mismatch | `REJECTED` | `ALERT`, `AUDIT` |
| `COMMITTING` | `COMMIT_FAILED` | — | `REJECTED` | `ALERT`, `AUDIT` |
| any non-terminal | `CANCEL` | — | `CANCELLED` | `UNMUTE_MIC`, `AUDIT` |
| any non-terminal | `TICK` / any event past a deadline | a TTL has elapsed | `EXPIRED` | `UNMUTE_MIC`, `AUDIT` |

The happy path appends exactly nine history entries from `TRIGGER` through `COMMITTED`.

## Timeouts (`TTL_MS`)

Session 10 min; `AUTH_REQUIRED` 2 min; `CAPTURING` 3 min; `PREVIEW_READY` 10 min; `CONFIRMATION_REQUIRED` 120 s; vault verification validity 15 min; elevated-change freshness 60 s. Expiry is checked before every event against `session.expiresAt` and the current `stateExpiresAt`.

## Limits

`MAX_VAULT_FAILURES = 5` (then `REJECTED` / `VAULT_LOCKED`); `MAX_CAPTURE_CHARS = 4000`.

## Security invariants (enforced in code, covered by tests)

1. **No silent learning.** Every write path runs `TRIGGER → mute → vault → capture → classify → policy → preview → confirmation → approve → verify`. There is no shortcut into `COMMITTING`.
2. **A `WRITE` effect is emitted only by a validated `APPROVE`.** No other transition can produce a write.
3. **Approvals are single-use and bound.** A token is 32 random bytes; only its SHA-256 is stored; it expires in 120 s; it must match session + user + account + agent + content hash; consuming is atomic and cannot be replayed.
4. **Authentication is mandatory and fresh.** Vault verification must be bound to the acting user + account and be within its validity window; elevated changes require a 60-second-fresh re-verification over a typed channel (never voice).
5. **Prohibited content never reaches a write.** Credential-like utterances are classified `PROHIBITED` and rejected at classification; policy independently blocks secret-like, platform-control, and cross-tenant content.
6. **Credentials never enter session context.** `transition` recursively scans the supplied `ctx` (to a bounded depth) and fail-closes with `CREDENTIAL_IN_CONTEXT` if any key looks like a password/secret/token, so a vault password can never be persisted in session state or audit.
7. **Commit is verified.** A reported write is accepted only if its content hash matches the approved preview; a mismatch or failure goes to `REJECTED` and raises an `ALERT`.
8. **Sessions are immutable.** Each transition returns a deep-frozen clone; terminal sessions ignore further events.

## Test coverage (phase B)

`node --test` over six suites — state machine (13), classifier (6), policy (few), normalize/diff (3), similarity (6), approval (7) — plus a read-only no-conflict guard suite that fails if the branch diff touches any K135Z-owned or shared gate path, or if any added line matches a secret pattern. All domain suites pass (40 domain assertions green) with built-ins only; no dependencies are added.
