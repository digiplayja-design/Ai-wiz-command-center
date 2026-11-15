# Esha AI model policy — prepared, inactive

The owner clarified the conversational requirement as **“the highest live
conversation model OpenAI has”**, while retaining **Sol 6.1 for deep thinking**.
Current official documentation resolves that voice role to **`gpt-live-1`**. This
supersedes the earlier ambiguous “GPT 2.5 conversational” wording and inactive Luna
proposal. Both model identities are resolved; the Live integration is unimplemented.
The previous 10-trial/120-monthly consultation proposal was not approved. No
commercial voice/consultation allowance or input/output/attempt budget is selected
or defaulted by this change.
No production environment was changed, no deployment or migration was applied,
and no live model call was made during this preparation.

## Prepared roles

| Role | Resolved model | API and transport selection |
| --- | --- | --- |
| `conversation` | `gpt-live-1` | `api: live`, `transport: webrtc`; resolved but unimplemented and disabled |
| `deep_thinking` | `gpt-6.1-sol` | `api: responses`, `transport: https`, explicit `reasoning.effort: high` |

[GPT-Live-1](https://developers.openai.com/api/docs/models/gpt-live-1) is OpenAI's
premier full-duplex conversational voice model. Its API is `/v1/live/sessions`;
it does not support the Responses or Realtime endpoints. It does not provide
Structured Outputs. This selection adds no voice session creation or audio code.

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
because this code has no Live transport or duration ledger. Existing token and
attempt settings cannot activate Live, even if all flags are present. Unknown policies/roles
and mixed legacy `KORLIX_ESHA_TEXT_MODEL` or `KORLIX_ESHA_REASONING_EFFORT`
overrides also fail closed. A client's `role`, `mode`, or `model` field cannot
select this adapter through the current consultation endpoint.

**This is not a completed, activatable two-role integration.** The shipping route
has no server role selection and remains disabled under the prepared policy. The
existing provider-attempt table constraint and debit RPC permit only Astra/max or
Luna/low, so they reject Sol/high before recording a debit. Both guards are
unchanged. A follow-up ledger migration and trusted role routing are required;
the adapter must never be used to bypass the committed debit.

## Live session contract and spending blocker

The proposed native path is WebRTC media plus an Esha-controlled server sideband.
The trusted server creates `/v1/live/sessions` with the native SDP offer, `store:
false`, and `delegation: {type: 'client'}`; it keeps the API key off the device.
The native peer uses the `oai-events` data channel, applies the returned SDP answer,
and waits for `session.started`. Audio travels on WebRTC tracks. The sideband uses
`wss://api.openai.com/v1/live/sessions/{session_id}/attach`. Frontend command
permissions must be restricted explicitly because omission allows all commands.
These are proposed integration requirements, not implemented behavior.

Client delegation lets Esha apply its own token counting, reservation, durable
attempt debit and result validation to every Sol call. The server accumulates
transcript deltas, deduplicates `session.delegation.created` by session/delegation
ID, then returns validated context with `session.commentary.append` carrying the
matching delegation ID. Its 500-token content cap needs an explicit bounded spoken
summary. Live may paraphrase that context; structured product cards remain based
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
but the inspected documentation does not state a numeric lifetime usable as an
Esha budget guarantee. An in-process sideband timer cannot enforce a hard cap if
Esha crashes while native WebRTC remains connected. Before activation, establish
a verified provider-side bound or another proven bounded primary-connection
design, with durable reservations, independent closure and conservative recovery.
Do not infer Live's lifetime from Realtime documentation. See [session lifecycle](https://developers.openai.com/api/docs/guides/live-conversations).

The inspected backend SDK is OpenAI 6.39.0; offline inspection finds no `client.live`
resource. The Flutter app has no WebRTC dependency, microphone permissions or audio
controller. A future Esha-specific transport must address these gaps without
silently upgrading shared app behavior. No voice-minute defaults are added here.

## Explicit limits and legacy compatibility

All of these settings remain required; no values are chosen here:

| Setting | Environment variable |
| --- | --- |
| Total counted request input | `KORLIX_ESHA_MAX_INPUT_TOKENS` |
| Total generated output, including reasoning | `KORLIX_ESHA_MAX_OUTPUT_TOKENS` |
| Successful consultations during a verified trial | `KORLIX_ESHA_TRIAL_CONSULTATIONS` |
| Successful consultations per verified monthly period | `KORLIX_ESHA_MONTHLY_CONSULTATIONS` |
| Provider generation attempts during a verified trial | `KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS` |
| Provider generation attempts per verified monthly period | `KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS` |

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

## Required integration before activation

1. Implement the selected Live/WebRTC transport and authenticated Esha-only
   voice route, with client delegation to the selected Sol/high backend. Both
   model identities are settled; no model substitution is required.
2. Choose the still-unapproved voice-minute and consultation allowances, plus
   explicit input/output, provider-attempt and session limits. Establish the
   independently enforceable duration bound described above. No previous proposal
   or test fixture supplies owner approval for those values.
3. Prepare and verify a narrowly scoped follow-up migration admitting Sol/high
   in the provider-attempt table and debit RPC while preserving all account,
   period, expiry, verification, idempotency, cap and irreversible-debit guards.
4. Integrate trusted role selection into the consultation route without losing
   input-token counting, reservation, debit-before-generation, replay and result
   validation. Add a separate durable voice-duration ledger and native microphone,
   playback, interruption and session-closure handling; existing consultation
   counts cannot account for voice time. Validate the genuine flow on devices.

Keep Esha generation disabled until the complete selected policy, limits,
compatible serving code and database guards are ready. An older worker has no
provider-attempt guard. This file does not authorize deployment, activation or
database changes. Store price, three-day trial and whole-app membership are
unchanged.

Offline tests use the real SQL in PGlite and mocked provider calls:

```sh
cd backend
node --test test/esha_sol_preparation.test.mjs test/esha_ai_budget.test.mjs test/esha_native_billing.test.mjs
```

They cover Sol/high request preparation, resolved but inactive Live selection,
rejection of Live by the Responses adapter even with forged ready flags,
exact trusted role selection, unchanged legacy behavior, strict output format,
count/generation context parity, real SDK retry suppression, and the shipping
route's refusal to run a client-selected role. The real SQL also verifies that
Sol remains blocked by the current ledger model guard without consuming a debit.
Existing ledger tests cover disabled configuration, retry suppression,
per-period limits, concurrent debit requests, replay, ambiguous failures, timeouts,
invalid output, refund races, cross-account access, RLS/RPC permissions and legacy
migration behavior. PGlite serializes its local connection; the real PostgreSQL
RPC's account row lock is the cross-worker serialization boundary.

All numeric fixture values are test data, not production settings or approved
allowances. Official references: [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol),
[GPT-6 compatibility](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6.1-sol),
and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
