# Esha AI model policy — prepared, inactive

The owner clarified the conversational requirement as **“the highest live
conversation model OpenAI has”**, while retaining **Sol 6.1 for deep thinking**.
Current official documentation resolves that voice role to **`gpt-live-1`**. This
supersedes the earlier ambiguous “GPT 2.5 conversational” wording and inactive Luna
proposal. Both model identities are resolved. The owner has now approved **five
Live minutes plus two deep-thinking consultations during the trial**, and **30
Live minutes plus ten deep-thinking consultations per month**: exactly 300/1800
voice seconds and 2/10 successful consultations. The previous 10/120 consultation
proposal was not approved and is superseded. Engineering input/output, provider
generation attempts, voice-start attempts and per-session bounds remain explicit
settings without approved defaults.
No production environment was changed, no deployment or migration was applied,
and no live model call was made during this preparation.

## Prepared roles

| Role | Resolved model | API and transport selection |
| --- | --- | --- |
| `conversation` | `gpt-live-1` | `api: live`, `transport: webrtc`; prepared and disabled |
| `deep_thinking` | `gpt-6.1-sol` | `api: responses`, `transport: https`, explicit `reasoning.effort: high` |

[GPT-Live-1](https://developers.openai.com/api/docs/models/gpt-live-1) is OpenAI's
premier full-duplex conversational voice model. Its API is `/v1/live/sessions`;
it does not support the Responses or Realtime endpoints. It does not provide
Structured Outputs. Voice accounting preparation does not authorize paid sessions.

[GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol) supports
the Responses API and Structured Outputs. Its documented reasoning efforts are
`low`, `medium`, `high`, `xhigh`, and `max`; `none` is unsupported. The prepared
deep-thinking role pins `high` and preserves strict structured result validation.
The Responses adapter explicitly rejects Live before token counting or generation,
even if a caller supplies a configuration marked ready. Model identity alone does
not make an incompatible API or missing budget ready.

`KORLIX_ESHA_AI_POLICY=conversation_and_deep_thinking_v1` selects this explicit
prepared policy. `nativeAiConfiguration(environment, {role: 'deep_thinking'})`
and `createEshaAi({environment, role: 'deep_thinking'})` prepare the Sol request
and transport. A role must be an exact string supplied by trusted server routing.
Omitting a role selects the resolved Live conversation role and fails closed
because the Responses adapter cannot serve Live. Existing token and attempt
settings cannot activate Live, even if all flags are present. Unknown policies/roles
and mixed legacy `KORLIX_ESHA_TEXT_MODEL` or `KORLIX_ESHA_REASONING_EFFORT`
overrides also fail closed. A client's `role`, `mode`, or `model` field cannot
select this adapter through the current consultation endpoint.

**The native and backend integration is implemented in prepared source and remains
inactive.** Trusted server routing selects Sol/high for Esha's consultation
adapter; the authenticated voice routes connect the Live transport to the
durable voice ledger. The original provider-attempt migration admits only
Astra/max and Luna/low. The additive
`20261115220600_esha_sol_deep_attempts.sql` prepares Sol/high compatibility while
retaining those legacy paths and all existing debit guards. Sol requires the
approved 2/10 successful-consultation grants; voice-linked requests also recheck
their consented, active session, original period and input hash at debit time.
The migrations are applied only to offline PGlite test databases in this work;
production activation remains blocked. No adapter may bypass the committed debit.

## Live session contract and spending blocker

The implemented native path uses WebRTC media plus an Esha-controlled server sideband.
The trusted server creates `/v1/live/sessions` with the native SDP offer, `store:
false`, and `delegation: {type: 'client'}`; it keeps the API key off the device.
The native peer uses the `oai-events` data channel, applies the returned SDP answer,
and waits for `session.started`. Audio travels on WebRTC tracks. The sideband uses
`wss://api.openai.com/v1/live/sessions/{session_id}/attach`. The prepared request
explicitly permits only `session.close` from the frontend data channel; the
device cannot change models, instructions or delegation. Authenticated routes
require a verified Korlix account and retain account/session ownership checks.
Native audio sharing requires fresh consent before each call, with separate
optional deep-thinking consent. Stop, pause, backgrounding and account changes
stop local audio and clear those choices; resume does not reuse consent.

Client delegation lets Esha apply its own token counting, reservation, durable
attempt debit and result validation to every Sol call. The server accumulates
transcript deltas, deduplicates `session.delegation.created` by session/delegation
ID, then returns validated context with `session.commentary.append` carrying the
matching delegation ID. The spoken handoff is bounded to 384 UTF-8 bytes, below
the provider's 500-token ceiling. Live may paraphrase that context; structured product cards remain based
on the separately validated Sol result. See [delegation](https://developers.openai.com/api/docs/guides/live-delegation)
and [WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc?api=live).

As checked on 2026-11-15, Live costs **$0.05/minute, billed per second**, plus Sol
usage. Silence and waiting for the backend remain billable. WebRTC creation
charges 15 seconds, credited against a started session's duration. Usage updates
are cumulative snapshots, not increments; final usage is confirmed by
`session.closed`. Unconfirmed finalization must retain a conservative reservation.
See [voice costs](https://developers.openai.com/api/docs/guides/voice-latency-cost?api=live).

**A crash-safe duration cap is still an activation blocker.** The published
[create schema](https://developers.openai.com/api/reference/resources/live/methods/create)
does not expose a caller-selected maximum duration or expiry. Session resources
return a server-assigned `expires_at`, and `expired` is a documented close reason,
but the inspected documentation does not establish a numeric lifetime usable as
an Esha budget guarantee for the selected WebRTC path. The create reference's SIP
ringing/connected-call limits are not treated as a verified WebRTC budget bound.
An in-process sideband timer cannot enforce a hard cap if
Esha crashes while native WebRTC remains connected. Before activation, establish
a verified provider-side bound or another proven bounded primary-connection
design, with durable reservations, independent closure and conservative recovery.
Do not infer Live's lifetime from Realtime documentation. See [session lifecycle](https://developers.openai.com/api/docs/guides/live-conversations).

The inspected backend SDK is OpenAI 6.39.0; offline inspection finds no `client.live`
resource. Esha therefore uses a fixed-host HTTP create request and a direct
WebSocket transport with `ws` pinned to **8.23.0**, without upgrading the shared
OpenAI SDK. Creation has no automatic retry. The real `voiceConfiguration()`
returns `configured: false`, `voiceEnabled: false` and
`hardDurationBoundVerified: false`; environment flags cannot override that
provider-bound blocker. Enabled fixtures are injected only in offline tests.
The approved commercial voice-minute defaults are not evidence that the provider
lifetime is bounded.

The retry watcher starts as soon as a provider session is known, including
recovered stop requests. It can persist known identity and retry the exact final
usage event after a transient storage failure without creating another session.
An observer that disconnects before attachment finishes is rejected; close
commands are bounded per observer to avoid an error/close feedback loop. A status
read after a worker restart can reattach only to close the existing session and
reconcile its usage. It cannot resume unmonitored media or authorize paid creation.

## Durable voice reservation and settlement

`20261115220519_esha_live_voice_ledger.sql` adds Esha-only duration and provider-start
period budgets, session records and immutable session/delegation-to-consultation mappings. Its RPC takes
the same account row lock as membership refunds and consultation spending.
`voice_ledger.mjs` wraps this RPC and cannot create a provider session.

Reserve an explicit engineering duration bound before creation. A confirmed
`begin.started: true` authorizes one creation attempt; a duplicate or lost debit
reply cannot authorize another. At most one unfinished session per account is
permitted, including uncertain requests across billing-period changes. The ledger
stores request hashes and accounting metadata, without SDP, audio or transcripts.

Each confirmed first `begin` also consumes one irreversible provider-start attempt,
before any paid creation request. Both trial and monthly start caps require explicit
canonical positive integer settings; they have no production defaults. The first
committed begin pins the selected cap for that verified billing period. Duplicate
begins never spend again, and a lost commit reply cannot authorize another provider
request. Failed or uncertain creation, a stop after begin, and a final duration of
zero never refund a start attempt. Cancellation before begin spends none.

`usage.voiceStarts` reports this technical budget separately from customer seconds.
Repeated zero-duration sessions therefore exhaust a finite creation allowance even
though they consume no confirmed customer minutes. Restore cannot refill it;
changing the configured cap fails closed for new work in that period. Renewals
receive a separate budget with no rollover. Missing or changed settings never
prevent status, stop, provider identity attachment, trusted usage or final settlement
for an existing request. Existing reserve/begin replays are resolved before these
configuration checks, preserving the original immutable outcome.

Only a known reserve-stage cap rejection for an absent request UUID is translated
to `voice_start_not_created`. That code guarantees no reservation, provider begin
or paid create exists for the request, so the native app can clear its pending ID.
Failures after reservation keep their original errors and reconcile or cancel
the durable row; they never use this no-work code. Status reports a separate
`unavailabilityReason` when the start budget is exhausted or incompatible with
the configured cap. It disables new-call availability without subtracting
customer minutes or changing recovery access for existing calls.

Immediately persist a returned provider session ID, even if expiry is not yet
known. Identity-only attachment stays `starting`; verified startup expiry can
later fill the null field once. Known expiry cannot be changed or erased, and no
expiry is invented from local timing. Provider-finalization validation uses the
terminal event and exact session identity, not a session object's status label.

Cumulative usage is monotonic and stored in milliseconds, rounding reported
fractions upward. Reserve at least 15 seconds for startup exposure, but settle
customer voice minutes only from trusted terminal cumulative duration: 5.8 seconds
settles as 5.8, and consistent zero usage remains zero. A final duration below an
earlier observed total is inconsistent; it retains the hold for reconciliation.
Final settlement records the reported amount once and returns unused customer
allowance reservation. This does not assert a provider refund or a minimum billed
duration for short sessions. Provider startup costs remain distinct from consumed
customer minutes. An actual overshoot is recorded honestly, flags
closure and prevents further overspending; it is never truncated to an allowance.

Only cancellation before `begin` can confirm zero provider usage without a final
provider event. After `begin`, a timer, mute, disconnected socket, missing response,
pause, or stop acknowledgement cannot release the hold. Native pause/background
requests closure; resume requires reconciliation and a fresh request ID. Missing
finalization remains uncertain until trusted evidence resolves it. This retention
is deliberately conservative and is not a substitute for the hard duration bound.

Voice-triggered Sol requires `deepThinkingConsent: true` captured before that
session starts; the default is false. The server binds each delegation to the
validated consultation input hash and one durable consultation UUID. Retries reuse
the mapping, and the Sol debit checks that its session is still active and
consented. Missing consent or exhausted deep allowance cannot trigger generation.
If an already authorized Sol response finishes after voice closes, its committed
validated answer remains recoverable through that voice session's status. The
`deepResults` list returns only the owning session's matching delegation/request
hashes, newest first with a stable UUID tie-breaker, and at most ten results. It
contains request IDs, answers and product IDs; it adds no transcript exposure.

All new tables have RLS enabled with no public client policies. The RPC is
security-invoker with an empty search path and service-role-only execution. Account
deletion cascades to voice/delegation accounting records.

## Explicit limits and legacy compatibility

Engineering settings remain required without defaults. Under the exact new role
policy, commercial counts default to the approved values; explicit conflicting
commercial environment settings fail closed. Legacy no-policy behavior is unchanged.

| Setting | Environment variable |
| --- | --- |
| Total counted request input | `KORLIX_ESHA_MAX_INPUT_TOKENS` |
| Total generated output, including reasoning | `KORLIX_ESHA_MAX_OUTPUT_TOKENS` |
| Successful consultations during a verified trial: approved 2 | `KORLIX_ESHA_TRIAL_CONSULTATIONS` (optional exact override under new policy) |
| Successful consultations per verified monthly period: approved 10 | `KORLIX_ESHA_MONTHLY_CONSULTATIONS` (optional exact override under new policy) |
| Provider generation attempts during a verified trial | `KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS` |
| Provider generation attempts per verified monthly period | `KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS` |
| Voice provider starts during a verified trial | `KORLIX_ESHA_TRIAL_VOICE_START_ATTEMPTS` |
| Voice provider starts per verified monthly period | `KORLIX_ESHA_MONTHLY_VOICE_START_ATTEMPTS` |
| Authorized duration for one voice session | `KORLIX_ESHA_VOICE_MAX_SESSION_SECONDS` |

Sol input is capped at no more than its documented 922,000 maximum input tokens;
output cannot exceed 128,000 tokens. The inherited minimum valid non-Astra output
cap is 256 tokens, not a recommendation for a usable high-reasoning answer.
Selected production limits must be explicit and evaluated with the actual task.
`KORLIX_ESHA_NATIVE_AI_ENABLED`, allowance, billing, provider and store-product
readiness gates continue to apply. This preparation sets none of them.

With no role policy selected and no server role supplied, the prior single-model
contract remains compatible: Astra/max is the default; legacy Luna/low still
requires `KORLIX_ESHA_ECONOMICAL_AI_APPROVED=true`. Legacy Luna support is not
the current owner choice. Setting Sol in the old single-model variable fails
closed rather than relabeling every conversation as deep thinking. Astra retains
its existing 32,768 minimum output budget and shared max-reasoning policy.
`backend/korlix_astra.cjs` and other apps are unchanged. Unconfigured AI keeps
new Esha checkout unavailable; existing purchases remain restorable/verifiable.

## Enforcement

For deep thinking, the backend builds one complete Responses request. OpenAI's
[input-token endpoint](https://developers.openai.com/api/docs/guides/token-counting)
counts the actual model input, including the system instructions, full server
catalog, selected conversation, optional shared preferences, reasoning settings,
and JSON output schema. The generation request uses the identical context fields.
Creation-only `max_output_tokens` and `store` fields are omitted from counting.
The input is never silently truncated to fit a cap. Counting failure or an
oversized request blocks generation and returns the successful-consultation hold.
The documented output cap covers the total generated output, including reasoning;
it is not only a visible-answer length limit.

The existing prepared Esha-only migration adds a provider budget per verified store billing
period and an append-only provider-attempt ledger. Its RPC uses the same account
row lock as the existing successful-consultation ledger and receipt/refund logic.
It rechecks the reserved UUID, account ownership, active current period, expiry,
and recent verification, then commits one irreversible debit **before** the paid
provider request. A duplicate UUID cannot authorize another generation. A lost
database response fails closed even if the debit committed.

Provider timeouts, invalid or incomplete output, process crashes, and failed result
commits retain the provider debit. SDK retries are disabled on both clients and
individual requests. There is no repair request or fallback generation. A completed
consultation replay returns its stored answer without counting tokens, generating,
or debiting either allowance again.

Successful consultation allowance and provider-attempt allowance are independent.
A failed answer releases the successful-consultation hold, but does not restore a
provider attempt. Exhausting provider attempts does not revoke app membership.
Attempt caps are fixed at first use for the verified billing period; restore or
later environment changes cannot refill or raise that period's cap. New verified
periods start separate budgets without rollover or duplicate-store stacking.

If the migration encounters historical consultation requests, it conservatively
records one legacy debit per pre-existing request, including failed or unfinished
requests whose provider outcome was previously unknown. This can overcount old
failed requests, but avoids resetting historical spending. It does not claim to
reconstruct exact historical provider usage. The migration sets no commercial cap.

The new tables have RLS enabled with no client policies. Table access and RPC
execution are restricted to `service_role`; the RPC is security-invoker with an
empty search path. The ledger stores hashes, model/budget metadata and counts,
without copying questions or answers. Account deletion cascades to these records.

## Remaining verification and activation gates

1. Establish the independently enforceable duration bound described above. The
   wired transport, local timers and approved commercial allowances do not prove
   that bound; paid voice creation remains disabled in production configuration.
2. Select and validate explicit input/output, provider-generation-attempt,
   voice-start-attempt and per-session
   engineering limits. The approved commercial inclusions do not choose these
   technical limits, and fixture values are not production settings. Disclose
   any selected connection/start limit in the actual offer before enabling
   checkout; no production start-cap values have been selected.
3. Review and apply the prepared additive voice and Sol migrations through the
   authorized deployment process while preserving account, period, expiry,
   verification, idempotency, cap and irreversible-debit guards.
4. Verify the locally tested native source in its own Android/iOS CI builds, then test
   genuine devices, microphone permission, interruption, pause/background,
   consent resets, account changes and final usage recovery. Perform separately
   authorized paid-provider and store sandbox validation only after the guards
   and technical limits are ready. Offline mocks do not validate live audio,
   provider billing, store purchases or a provider-enforced duration bound.
5. Produce fresh signed native artifacts, verify the amended policy deployment
   and update the applicable store disclosures and genuine screenshots. The
   previously uploaded iOS build 2 does not contain this later voice work.

Keep Esha generation disabled until the complete selected policy, limits,
compatible serving code and database guards are ready. An older worker has no
provider-attempt guard. This file does not authorize deployment, activation or
database changes. Store price, three-day trial and whole-app membership are
unchanged.

Offline backend tests use the real SQL in PGlite and mocked provider calls:

```sh
cd backend
node --test test/esha*.test.mjs
```

At the corrected November 15 local checkpoint, the clean 363-package environment
was retained with a byte-identical lockfile, and current Esha source, tests and
prepared SQL were refreshed. Node **22.23.5** passed `node --check server.js`
and **116 tests across nine Esha files** (111 top-level and five nested, zero
failures or skips). This is the authoritative aggregate and already
includes the policy, ledger, Sol, transport and route suites. Flutter **3.47.9** /
Dart **3.13.7** separately passed analysis with no issues and **79 native tests**
(49 existing plus 30 voice). Coverage includes the reserve-only no-work error,
separate connection-limit availability, and historical answer retrieval that
cannot replace renewed current-period allowance.

The first voice checkpoint at `1440c0f46a105e7b4467ff0d603814e2ad801b18`
passed all three jobs in [GitHub run 43769036015](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43769036015).
Its earlier local counts were 109 backend and 76 native tests. That successful
workflow precedes this start-budget correction; the corrected commit/run remains
pending. Fresh signed artifacts, physical audio and real paid provider behavior
remain unverified. These results do not activate service.

They cover Sol/high request preparation, resolved but inactive Live selection,
rejection of Live by the Responses adapter even with forged ready flags,
exact trusted role selection, unchanged legacy behavior, strict output format,
count/generation context parity, real SDK retry suppression, and the shipping
route's refusal to run a client-selected role. The baseline-only SQL test verifies
that Sol is blocked before its migration; the additive-migration tests verify
Sol/high admission, irreversible attempts and rejection after voice closure.
Voice tests exercise actual SQL reservation, replay, lost-commit replies,
cumulative fractional settlement, irreversible start caps independent of zero or
fractional customer duration, frozen per-period limits, configuration-free recovery,
startup exposure, overshoot, refunds, ownership,
renewal, consent, delegation identity, post-closure answer recovery, permissions
and account deletion.
Existing ledger tests cover disabled configuration, retry suppression,
per-period limits, concurrent debit requests, replay, ambiguous failures, timeouts,
invalid output, refund races, cross-account access, RLS/RPC permissions and legacy
migration behavior. PGlite serializes its local connection; the real PostgreSQL
RPC's account row lock is the cross-worker serialization boundary.

Commercial fixture quantities reflect the approved 300/1800 seconds and 2/10
consultations. Engineering fixture values remain test data, not production
settings or approved limits. Official references: [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol),
[GPT-6 compatibility](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6.1-sol),
and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
