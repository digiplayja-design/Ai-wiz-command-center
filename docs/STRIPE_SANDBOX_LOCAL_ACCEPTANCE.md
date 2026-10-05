# Isolated manual Stripe acceptance

This harness exercises the actual scheduling routes and payment adapter against a local PGlite ledger. It does not load the production server, Supabase, email, calendars, or any production environment variables. The live Stripe account and sandbox currently attached to the production backend are explicitly rejected. Use a separate Stripe sandbox with no webhook pointing to the production backend.

The script is `backend/test/manual/stripe_sandbox_acceptance.mjs`. Importing it or running it without `--serve` makes no network requests. Starting it creates a private local ledger and loopback server, with checkout paused and no provider requests. Only explicit local commands contact Stripe. A fresh run uses synthetic people and USD 1.00 appointments. No messages or calendar invitations are sent. This is payment-provider acceptance, not a new OAuth test: the independently verified merchant grant is seeded into this isolated ledger.

## Preparation

Use Node 22+ and the backend development dependencies (`npm ci --ignore-scripts` in `backend`, including PGlite). A separate sandbox platform must already have Connect and a full-dashboard merchant whose Accounts v2 card-payments and payouts capabilities are active, with Stripe collecting fees and losses. The harness does not create accounts or change capabilities. Its independent endpoint-list check rejects **any enabled persisted webhook endpoint**, malformed endpoint data, or a paginated list: sandbox setup may have copied existing settings. CLI listeners need no persisted endpoint and pass this check. Do not disable production endpoints to make a sandbox pass. The acceptance key needs webhook-endpoint read access as well as the account and payment permissions used by the adapter.

Set only these **acceptance-specific** variables in the process that launches the harness. Enter keys through a private environment file or secret store; never paste them into chat, commit them, print them, or reuse the production environment file.

| Variable | Value |
| --- | --- |
| `KORLIX_ACCEPTANCE_RUN` | `isolated-stripe-sandbox` |
| `KORLIX_ACCEPTANCE_AUTH_MODE` | `api_key` (default) or `cli_session` |
| `KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY` | Test API key belonging to the separate sandbox; **omit in CLI mode** |
| `KORLIX_ACCEPTANCE_WEBHOOK_SECRET` | Signing secret from that sandbox's CLI listener |
| `KORLIX_ACCEPTANCE_PLATFORM_ID` | Exact expected separate sandbox `acct_…` |
| `KORLIX_ACCEPTANCE_MERCHANT_ID` | Exact expected independent connected merchant `acct_…` |
| `KORLIX_ACCEPTANCE_PORT` | `8787` (optional; loopback binding is fixed) |
| `KORLIX_ACCEPTANCE_CLI_CONTEXT` | CLI mode only: exact sandbox context ID from authorized OAuth `whoami` |
| `KORLIX_ACCEPTANCE_CLI_CONFIG` | CLI mode only: dedicated absolute CLI config path |

The same sandbox must be selected in the Stripe CLI. Browser login is a separate authorization step. In `cli_session` mode the harness uses the browser-authorized CLI session without extracting its token or requesting an API key. The module `backend/test/manual/stripe_cli_session_transport.mjs` executes the installed CLI directly with argument arrays and no shell. Never extract a CLI browser session token and pretend it is an API key.

In CLI mode, omit all Stripe API-key variables, including `STRIPE_API_KEY` and `KORLIX_ACCEPTANCE_STRIPE_SECRET_KEY`; supplying one rejects startup. Set the CLI context separately from the expected `/v1/account` platform ID: they must be independently verified rather than assumed identical. For this workspace, the prepared config path is `/workspace/scratch/3f6fe4659caf/stripe-acceptance-auth/config.toml`. Its parent directory is private. A dedicated config file does **not** guarantee separate OAuth credentials or active-context state: CLI 1.53 also uses a global keyring.

Before every API call, the transport requires OAuth `whoami --format json` to name the expected context in test mode and list test authorization for it. It then pins the request itself: platform calls use the exact `Stripe-Context`, connected-account calls use the exact `context/merchant` `Stripe-Account`, and all calls set `Stripe-Livemode: false`. CLI 1.53 applies these explicit custom headers after its credential-derived headers, so an active-context change between commands cannot reroute the API call. Arbitrary headers, endpoints, live mode and API-key overrides are disallowed. Child processes receive only a small environment allowlist; inherited API keys, alternate sockets and other Stripe overrides are removed. Standard proxy and Go certificate variables from the trusted execution runtime are retained because managed workspaces may require them for network access. A plain opaque string supplies the local adapter's fingerprint; it is never a key and never reaches network authentication.

The transport checks actual verbose request headers, final HTTP status and request ID. A CLI exit code of zero is not payment success. Errors preserve only a validated machine-readable Stripe error code and generic text; raw CLI diagnostics and credentials are not printed. Each CLI child has a 30-second timeout with bounded output and cancellation. The manual CLI harness injects a 45-second overall Stripe request budget to accommodate both the identity preflight and API process; this shared abort signal still limits their combined duration. Its API-key mode and all production defaults retain the original 15 seconds; there is no production environment override. The reusable request helper accepts only explicit integer budgets from 1 through 60,000 milliseconds. This CLI path remains manual acceptance tooling and is not imported into production.

The child environment explicitly sets `STRIPE_NO_AUTO_UPDATE=1` and `DO_NOT_TRACK=1`, ignoring inherited values for both. These documented CLI controls prevent deferred update checks and telemetry from consuming the provider timeout after an API response. They are fixed execution settings; no authentication, endpoint, socket or mode override is inherited.

Start the listener with the installed CLI (adjust its path if necessary):

```bash
/workspace/scratch/3f6fe4659caf/bin/stripe listen \
  --config /workspace/scratch/3f6fe4659caf/stripe-acceptance-auth/config.toml \
  --timeout 120 \
  --events checkout.session.completed,checkout.session.expired,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,charge.refunded \
  --forward-connect-to http://127.0.0.1:8787/api/scheduling/payments/webhook
```

The listener's startup output contains a signing secret. Capture that output privately and set the acceptance webhook variable without displaying it in chat. No Dashboard endpoint or public tunnel is needed. Do not use `--live`. Verify the selected sandbox before starting the listener and do not switch its active context during the run. The API transport's per-request pinning does not configure the separate listener. `--timeout 120` gives the forwarded local handler enough time for its independent Stripe reads under the manual CLI request budget; it does not extend the application's 45-second per-request budget. Keep the listener running for the payment and refund checks.

Run the listener, harness and local command client in the **same persistent shell/runtime and network namespace**. In this execution environment, separate shell tool jobs can have separate loopback networks even when they share files. A listener in one job cannot reach a harness in another job through `127.0.0.1`. Use one persistent orchestration process to launch both children and issue local HTTP commands; do not assume separate tool calls share localhost.

The execution session must also survive the entire wait for the user to complete hosted Checkout, including conversation turns. In this workspace, sessions have become unavailable across user turns even when the private checkpoint still said `waiting_for_signed_payment` and had no shutdown timestamp. Do not rely on these work sessions for uninterrupted listening across turns. A persisted ledger or a saved `ready: true` field does not prove that a listener is alive. Check process liveness before handing off the Checkout URL and again when the user returns. If the session is unavailable, resume the same ledger with checkout paused and use the original-event recovery procedure below; do not request another payment merely to recover its event. Before reopening a ledger, ensure its previous process has stopped so there is only one PGlite writer.

From the repository root, with the dedicated environment variables loaded:

```bash
node backend/test/manual/stripe_sandbox_acceptance.mjs --serve
```

Startup prints only the local API address, private run-directory path, and control-token file path. Save the run-directory path. Ledger and encrypted grant material persist there; do not delete it while test payments or refunds are unresolved. Every restart begins paused. Recover the same ledger, using the same sandbox credentials, with:

```bash
node backend/test/manual/stripe_sandbox_acceptance.mjs --serve --resume /absolute/run-directory
```

## Recover an existing payment event after listener interruption

Stripe documents [`events resend`](https://docs.stripe.com/cli/events/resend) as resending an existing event to the CLI's local webhook endpoint when no `--webhook-endpoint` is supplied. CLI 1.53.0's [implementation](https://github.com/stripe/stripe-cli/blob/v1.53.0/pkg/cmd/resource/events_resend.go) adds `for_stripecli=true` to `POST /v1/events/{event}/retry` in that case. This requests a new delivery of the original event; it does not create another payment or require a persisted/public webhook endpoint.

1. Preserve the unavailable session's checkpoint and the ledger's existing receipt IDs before restarting. Restart the listener, harness and local command client together in one current execution/network namespace, with the original ledger resumed and checkout paused. Capture the current listener secret privately into the harness environment. Verify actual process liveness and the local `status` response rather than trusting old readiness files.
2. Run `whoami --format json` with the dedicated CLI config in the sanitized environment described above. Require the exact isolated platform context `acct_1UN1QuLwavBaepoe`, `mode: test`, and test authorization for that context. The independently verified merchant for this run is `acct_1UN1WiLwavcz7g46`. Stop on a mismatch; do not switch to the production account or its attached sandbox. Confirm endpoint isolation remains satisfied. Do not export OAuth credentials or print tokens/secrets.
3. Use read-only Stripe requests with the same identity preflight and account/mode/header checks to retrieve the existing Checkout session and its exact `checkout.session.completed` event. Do not select an event solely by recency. Match the event's connected account to the expected merchant, its `data.object.id` to the resumed ledger's `checkoutId`, and both `client_reference_id` and `metadata.korlix_booking` to that ledger's booking ID. Require sandbox mode, `payment_status: paid`, USD currency and an amount of 100 cents; verify the session's PaymentIntent belongs to that payment. Preserve the baseline ledger state and receipt IDs. Do not invoke `reconcile` or `tick` first when assessing whether the webhook itself performs confirmation.
4. With the current listener active, resend only that verified event using the same dedicated CLI session. Run the following in the sanitized environment, replacing `evt_VERIFIED_PAYMENT_EVENT` with the retrieved ID. Capture the response privately and inspect only safe event, request and status fields:

   ```bash
   /workspace/scratch/3f6fe4659caf/bin/stripe \
     --config /workspace/scratch/3f6fe4659caf/stripe-acceptance-auth/config.toml \
     events resend evt_VERIFIED_PAYMENT_EVENT \
     --account acct_1UN1WiLwavcz7g46 \
     --request-header 'Stripe-Context: acct_1UN1QuLwavBaepoe' \
     --request-header 'Stripe-Livemode: false' \
     --stripe-version 2026-09-30.endive \
     --confirm
   ```

   For this Connect resend command, `--account` is a request-body parameter naming the originating merchant; Stripe explicitly says to use it instead of `--stripe-account`. Omit `--webhook-endpoint` so delivery targets the CLI listener, and never add `--live`. Keep the same authenticated config and platform context for listener and resend. The reviewed documentation does not specify every server-side user/device routing detail, so verify receipt rather than assuming delivery from an API response.
5. A successful resend response alone does not pass the webhook check. Require the original event ID to arrive at the actual handler with a fresh valid Stripe signature, pass its normal connected-account and independent Checkout lookup, create one matching receipt, and change the existing booking from unpaid to `paymentState: paid` and `bookingState: confirmed` without manual reconciliation. If the booking hold has expired, retain the actual resulting state and resolve the payment through the normal refund path; do not force confirmation or reset timestamps to make the check pass.
6. After verified delivery, run `duplicate` within the signature window, then `fee-proof` and the normal full-refund procedure while checkout remains paused. Require the actual original payment event for the duplicate check, and verify both the refund outcome and any separately received signed refund event. Stop the processes only after the payment/refund outcome is resolved.

Record this evidence as **a signed replay of the original payment event after listener recovery**, not proof of uninterrupted first delivery. If no payment receipt existed before replay, retain that fact. A later signed refund event alone proves only the refund-event path. If supported replay cannot be received, independent `reconcile` can still safely resolve the existing payment and permit its refund, but the signed payment-delivery check remains unverified. Do not manufacture a webhook signature or create another checkout to disguise missing evidence. These instructions describe the supported recovery procedure; they do not assert that a particular replay has passed.

## Local commands

The API binds only to `127.0.0.1`. Commands require the private bearer token from the printed `controlTokenFile`; the signed webhook is the sole unauthenticated route. Browser origins and non-loopback Host headers are rejected. Use a local command client that reads the token from disk; do not print the token or put it into a shared URL.

For example, set `KORLIX_ACCEPTANCE_DIRECTORY` to the printed directory and invoke this helper from the shell. It prints results, never credentials:

```bash
acceptance() {
  python3 - "$@" <<'PY'
import json, os, pathlib, sys, urllib.request, urllib.error
directory = pathlib.Path(os.environ['KORLIX_ACCEPTANCE_DIRECTORY'])
command = sys.argv[1]
body = json.loads(sys.argv[2]) if len(sys.argv) > 2 else None
token = (directory / 'control-token').read_text()
url = 'http://127.0.0.1:8787/acceptance/' + command
request = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
    headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(request, timeout=240) as response:
        print(response.read().decode())
except urllib.error.HTTPError as error:
    print(error.read().decode())
    raise SystemExit(1)
PY
}
```

Run the sequence below, substituting the returned `bookingId` where shown:

1. `acceptance status` — verify local checkout is off and there are no bookings.
2. `acceptance verify '{}'` — verifies the API key's platform ID and the merchant's v2 identity, sandbox mode, fee/loss responsibility, and active capabilities. A failure must be resolved before a payment test.
3. `acceptance enable '{"confirmed":true}'` — performs fresh platform, endpoint-isolation and merchant verification, then enables only the local harness and seeds its synthetic event. CLI identity preflights add latency; the local helper allows up to four minutes for a command without extending any individual provider or subprocess timeout.
4. `acceptance book '{"confirmed":true}'` — creates one local USD 1.00 payment hold, returning its booking ID.
5. `acceptance pause '{}'`, then `acceptance checkout '{"bookingId":"BOOKING_ID","confirmed":true}'` — expect checkout rejection and no Stripe payment creation.
6. Enable locally again, then repeat `checkout` for that booking within nine minutes of its creation. Open the returned hosted sandbox Checkout URL on the iPad and complete it using Stripe test payment details. Never enter a real card.
7. Pause locally again. Wait for the CLI delivery, then use `acceptance status`. Before manually invoking `reconcile` or `tick`, verify the signed event receipt and the local booking's paid state. This proves the webhook path performed independent payment verification.
8. Within five minutes of delivery, `acceptance duplicate '{}'` replays the exact signed bytes and verifies that booking state and receipt count do not change. It does not manufacture a new signature. Use another real delivery after the five-minute signature window expires.
9. `acceptance fee-proof '{"bookingId":"BOOKING_ID"}'` independently reads the connected-account payment and verifies a USD 1.00 sandbox charge with no application fee.
10. `acceptance refund '{"bookingId":"BOOKING_ID","confirmed":true}'` uses the authenticated scheduling refund route and runs its worker while checkout remains paused. Confirm `paymentState: refunded` and `refundState: succeeded`; allow the real `charge.refunded` event to arrive too.
11. If an operation is pending, inspect `status` first. `reconcile` with the booking ID independently reads its payment, and `tick '{}'` retries the local worker. The production adapter retains its normal idempotency keys. Do not discard the ledger and blindly repeat a payment.

The local script does not poll providers automatically. Stop both processes only after refunds are confirmed; retain the private ledger for any unresolved outcome. These test transactions use no real funds and do not enable any KORLIX production checkout switch.

## Limits and evidence

The harness uses `https://korlix-acceptance.invalid` as the public origin. The actual application generates its ordinary return URLs under that reserved domain. After test payment, the iPad return page will not load; close the tab and inspect the local signed webhook result. No synthetic booking is sent to a production URL. This deliberately leaves the mobile/browser return-page experience untested.

The CLI signs and forwards real sandbox Connect events to the local handler. This verifies handler signatures, event routing, independent payment reads and ledger transitions; it does not verify delivery to the production Render webhook URL. A complete launch gate must separately test that deployed endpoint and the actual customer return flow. Declines and delayed payment success/failure also need separate sandbox runs; the basic sequence above covers paid checkout, replay, pause and full refund.

Offline harness validation (fixtures only):

```bash
node --test backend/test/manual/stripe_sandbox_acceptance.offline.test.mjs
node --test backend/test/manual/stripe_cli_session_transport.offline.test.mjs
```

This verifies forbidden configuration, zero provider calls on startup, mismatched-platform/active-webhook/pending-capability rejection before writes, control authentication/browser rejection, paused checkout, signed fixture confirmation, duplicate-delivery handling, fee inspection, full refund while paused, and recovery of the persistent local ledger. It is not evidence of real Stripe acceptance.

The transport tests also verify explicit CLI authentication mode, rejection of API keys/native-fetch fallback, exact post-selection header pins, removal of ambient credential/socket overrides while retaining managed runtime proxy/CA settings, preservation of GET query and POST form values/idempotency keys, wrong-context/abort rejection before API execution, HTTP errors with a zero process exit, and rejection of malformed or missing status evidence. No test starts a real CLI session or contacts Stripe.
