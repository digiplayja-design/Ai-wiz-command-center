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

Before every API call, the transport requires OAuth `whoami --format json` to name the expected context in test mode and list test authorization for it. It then pins the request itself: platform calls use the exact `Stripe-Context`, connected-account calls use the exact `context/merchant` `Stripe-Account`, and all calls set `Stripe-Livemode: false`. CLI 1.53 applies these explicit custom headers after its credential-derived headers, so an active-context change between commands cannot reroute the API call. Arbitrary headers, endpoints, live mode and API-key overrides are disallowed. Child processes receive only a small environment allowlist; inherited API keys, alternate sockets, proxies and other Stripe overrides are removed. A plain opaque string supplies the local adapter's fingerprint; it is never a key and never reaches network authentication.

The transport checks actual verbose request headers, final HTTP status and request ID. A CLI exit code of zero is not payment success. Errors preserve only a validated machine-readable Stripe error code and generic text; raw CLI diagnostics and credentials are not printed. Calls have a 15-second timeout, bounded output and cancellation. This path remains manual acceptance tooling and is not imported into production.

Start the listener with the installed CLI (adjust its path if necessary):

```bash
/workspace/scratch/3f6fe4659caf/bin/stripe listen \
  --config /workspace/scratch/3f6fe4659caf/stripe-acceptance-auth/config.toml \
  --events checkout.session.completed,checkout.session.expired,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,charge.refunded \
  --forward-connect-to http://127.0.0.1:8787/api/scheduling/payments/webhook
```

The listener's startup output contains a signing secret. Capture that output privately and set the acceptance webhook variable without displaying it in chat. No Dashboard endpoint or public tunnel is needed. Do not use `--live`. Verify the selected sandbox before starting the listener and do not switch its active context during the run. The API transport's per-request pinning does not configure the separate listener. Keep the listener running for the payment and refund checks.

From the repository root, with the dedicated environment variables loaded:

```bash
node backend/test/manual/stripe_sandbox_acceptance.mjs --serve
```

Startup prints only the local API address, private run-directory path, and control-token file path. Save the run-directory path. Ledger and encrypted grant material persist there; do not delete it while test payments or refunds are unresolved. Every restart begins paused. Recover the same ledger, using the same sandbox credentials, with:

```bash
node backend/test/manual/stripe_sandbox_acceptance.mjs --serve --resume /absolute/run-directory
```

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
    with urllib.request.urlopen(request, timeout=60) as response:
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
3. `acceptance enable '{"confirmed":true}'` — enables only the local harness and seeds its synthetic event.
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

The transport tests also verify explicit CLI authentication mode, rejection of API keys/native-fetch fallback, exact post-selection header pins, removal of ambient credential/socket overrides, preservation of GET query and POST form values/idempotency keys, wrong-context/abort rejection before API execution, HTTP errors with a zero process exit, and rejection of malformed or missing status evidence. No test starts a real CLI session or contacts Stripe.
