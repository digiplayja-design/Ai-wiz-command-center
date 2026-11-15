# Esha AI option — prepared, inactive

The existing default remains **GPT-6 Astra with max reasoning**. The economical
option is implemented for review but has not been approved or activated. No
production environment was changed, no commercial allowance was chosen, no
migration was applied to a service, and no live model call was made during this
preparation.

The candidate owner decision is:

| Setting | Inactive proposal | Environment variable |
| --- | --- | --- |
| Model | `gpt-6-luna` | `KORLIX_ESHA_TEXT_MODEL` |
| Reasoning | `low` | `KORLIX_ESHA_REASONING_EFFORT` |
| Total request input | 8,192 actual tokens | `KORLIX_ESHA_MAX_INPUT_TOKENS` |
| Total generated output, including reasoning | 4,096 tokens | `KORLIX_ESHA_MAX_OUTPUT_TOKENS` |
| Successful consultations during a verified trial | 10 | `KORLIX_ESHA_TRIAL_CONSULTATIONS` |
| Successful consultations per verified monthly period | 120 | `KORLIX_ESHA_MONTHLY_CONSULTATIONS` |
| Provider generation attempts during a verified trial | 20 | `KORLIX_ESHA_TRIAL_PROVIDER_ATTEMPTS` |
| Provider generation attempts per verified monthly period | 240 | `KORLIX_ESHA_MONTHLY_PROVIDER_ATTEMPTS` |

These numbers are **not defaults**. The Luna branch additionally requires
`KORLIX_ESHA_ECONOMICAL_AI_APPROVED` to be explicitly set to `true`. Existing
`KORLIX_ESHA_NATIVE_AI_ENABLED` and the store billing/product readiness gates
still apply. Selecting an unknown model, another effort, missing limits, or
unapproved Luna configuration fails closed. There is no automatic model fallback.

The Astra default also requires explicit input/output/attempt limits before new
Esha generation can be enabled. It retains the shared Astra/max policy and its
32,768 minimum output budget. `backend/korlix_astra.cjs` and all other apps are
unchanged. Unconfigured AI keeps new Esha checkout unavailable; existing purchases
can still be restored and verified.

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

The new Esha-only migration adds a provider budget per verified store billing
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

## Before activation

An owner must choose and approve the model/allowances, review the proposed cost
and quality tradeoff, apply the new migration, and explicitly configure the
limits. Keep Esha generation disabled until every serving worker uses the new
code and the new migration is present; an older worker has no provider-attempt
guard. This file does not authorize those actions. Store prices, the three-day
trial and the whole-app membership boundary are unchanged.

Offline tests use the real SQL in PGlite and mocked provider calls:

```sh
cd backend
node --test test/esha_ai_budget.test.mjs test/esha_native_billing.test.mjs
```

They cover request counting parity, disabled configuration, retry suppression,
per-period limits, concurrent debit requests, replay, ambiguous failures, timeouts,
invalid output, refund races, cross-account access, RLS/RPC permissions and legacy
migration behavior. PGlite serializes its local connection; the real PostgreSQL
RPC's account row lock is the cross-worker serialization boundary.

Official model reference: [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna).
