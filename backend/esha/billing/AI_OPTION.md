# Esha AI model policy — prepared, inactive

The owner's current direction is **“GPT 2.5 conversational and Sol 6.1 for deep
thinking.”** This supersedes the previous inactive Luna proposal. The Sol portion
is prepared below; the exact conversational API model remains unresolved. The
previous 10-trial/120-monthly consultation proposal was not approved. No commercial
allowance or input/output/attempt budget is selected or defaulted by this change.
No production environment was changed, no deployment or migration was applied,
and no live model call was made during this preparation.

## Prepared roles

| Role | Requested model | Prepared API configuration |
| --- | --- | --- |
| `conversation` | GPT 2.5 conversational | Unresolved: `model: null`, `reasoningEffort: null`; fails closed |
| `deep_thinking` | Sol 6.1 | `gpt-6.1-sol`, explicit `reasoning.effort: high` |

[GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol) supports
the Responses API and Structured Outputs. Its documented reasoning efforts are
`low`, `medium`, `high`, `xhigh`, and `max`; `none` is unsupported. The prepared
deep-thinking role pins `high`. It does not replace Sol with Astra, choose another
conversational model, or enable a Realtime/audio integration. The current official
[model catalog](https://developers.openai.com/api/docs/models/all) did not resolve
“GPT 2.5 conversational” or `gpt-realtime-2.5`; that identity needs clarification.

`KORLIX_ESHA_AI_POLICY=conversation_and_deep_thinking_v1` selects this explicit
prepared policy. `nativeAiConfiguration(environment, {role: 'deep_thinking'})`
and `createEshaAi({environment, role: 'deep_thinking'})` prepare the Sol request
and transport. A role must be an exact string supplied by trusted server routing.
Omitting a role selects the unresolved conversation role and fails closed, even
if all activation flags and budgets happen to be present. Unknown policies/roles
and mixed legacy `KORLIX_ESHA_TEXT_MODEL` or `KORLIX_ESHA_REASONING_EFFORT`
overrides also fail closed. A client's `role`, `mode`, or `model` field cannot
select this adapter through the current consultation endpoint.

**This is not a completed, activatable two-role integration.** The shipping route
has no server role selection and remains disabled under the prepared policy. The
existing provider-attempt table constraint and debit RPC permit only Astra/max or
Luna/low, so they reject Sol/high before recording a debit. Both guards are
unchanged. A follow-up ledger migration and trusted role routing are required;
the adapter must never be used to bypass the committed debit.

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

The backend builds one complete Responses request. OpenAI's
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

1. Resolve the exact conversational API model and define when the trusted server
   chooses conversation versus deep thinking. Sol 6.1 is already the chosen
   deep-thinking model; this is not a request to approve that identity again.
2. Choose the still-unapproved commercial allowances and explicit input/output
   and provider-attempt limits. No previous proposal or test fixture supplies
   owner approval for those values.
3. Prepare and verify a narrowly scoped follow-up migration admitting Sol/high
   in the provider-attempt table and debit RPC while preserving all account,
   period, expiry, verification, idempotency, cap and irreversible-debit guards.
4. Integrate trusted role selection into the consultation route without losing
   input-token counting, reservation, debit-before-generation, replay and result
   validation. Any native mode control or Realtime feature is separate work.

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

They cover Sol/high request preparation, an unresolved conversational role,
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
