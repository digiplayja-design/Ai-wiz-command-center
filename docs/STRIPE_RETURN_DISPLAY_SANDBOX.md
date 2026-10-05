# Saved sandbox return display

This separate app lets an iPad open the shipped 2MEETU return page over HTTPS using the saved public projection of an already-refunded synthetic booking. It requires no new payment. It is not a Stripe redirect test, a fresh Stripe status read, or deployed paid-booking confirmation.

The entry point is `backend/test/manual/stripe_return_preview.mjs`. It uses only Node's standard library and the existing scheduling HTML, browser script, and styles. It is never imported by the production server or the local acceptance control harness. A banner identifies the saved result and its capture time. Unsupported calendar and booking-action buttons are hidden; reloading the saved result and copying its new private display link remain available. The shipped `booking.js` is served unchanged.

## Data and access

Export only a known synthetic booking that is canceled, refunded, refund succeeded, USD 100 cents, and `livemode=false`. Use the public `/api/scheduling/manage` projection from a temporary copy of the finalized isolated ledger, with provider calls rejected and checkout paused. Normalize timestamps to ISO without changing their instants. Preserve the original ledger.

The preview config selects only display fields. Checkout URLs, meeting links, event slugs, provider IDs/errors, answers, notification history, and calendar history are omitted. No original management token, control token, encryption key, sealed grant, Stripe credential, or database configuration belongs in the service. The guest and host must match the known synthetic acceptance identities.

Generate a new 32-byte random token, put only its SHA-256 hash in the service environment, and give the user a link shaped as `/book/manage#BOOKING_ID.NEW_TOKEN`. The token stays in the URL fragment and is sent only in the same-origin JSON request body. Do not put the link, token, or environment payload in Git or request logs.

Required environment variables:

| Variable | Value |
| --- | --- |
| `KORLIX_RETURN_PREVIEW` | `refunded-sandbox-display-v1` |
| `KORLIX_RETURN_PREVIEW_DATA` | JSON containing `capturedAt` and the sanitized `booking` |
| `KORLIX_RETURN_PREVIEW_TOKEN_HASH` | SHA-256 of the new 64-character hexadecimal token |
| `KORLIX_RETURN_PREVIEW_EXPIRES_AT` | ISO timestamp, at most seven days after capture |
| `KORLIX_RETURN_PREVIEW_ORIGIN` | Optional explicit HTTPS origin; otherwise Render's `RENDER_EXTERNAL_URL` |

The service checks the fixed booking ID, token hash, origin and expiry. Only the saved manage response is available. Checkout, cancellation, refund, webhook, owner, and acceptance-control routes are absent. It sends no emails, calendar requests, or provider requests. All responses use `no-store`, `no-referrer`, and a restrictive CSP. Health discloses no booking data. Access expires even after a service restart.

## Dedicated Render service

Use a new **Free** Node web service, auto-deploy off, with no environment group, datastore, disk, worker, or provider credentials. Do not repurpose either historical test backend or production services.

- Repository: `digiplayja-design/Ai-wiz-command-center`
- Branch: `release/k135z-backend-render-20260919`
- Build: `node --check backend/test/manual/stripe_return_preview.mjs`
- Start: `node backend/test/manual/stripe_return_preview.mjs`
- Additional env: `NODE_VERSION=24`, `SKIP_INSTALL_DEPS=true`
- Port: Render's `PORT`; binds `0.0.0.0`
- Health: `/health`

Render supplies the HTTPS URL and the runtime environment, so this display survives work-session loss and service restarts without a local database. The Free instance may take about a minute to wake after inactivity and shares the workspace's free-instance allowance. See [Render's free-instance documentation](https://render.com/docs/free) and [default environment variables](https://render.com/docs/environment-variables). Do not upgrade its compute plan automatically.

Run the focused disclosure and mutation-boundary tests before deployment:

```bash
node --test backend/test/manual/stripe_return_preview.test.mjs
```

After deployment, verify health, page/assets, valid display access, rejection of a wrong token, and absence of payment/action routes. Then ask the user to open the new private HTTPS link on their iPad and confirm **Appointment canceled**, **refunded**, **Full refund: succeeded**, and no payment button. That screenshot can establish actual iPad rendering of this saved result. The original `.invalid` Checkout URLs and end-to-end paid return still remain separate limitations.

## Deployment checkpoint — 2026-10-05

The Free service is live at [korlix-2meetu-return-sandbox.onrender.com](https://korlix-2meetu-return-sandbox.onrender.com), with auto-deploy off:

- Service: `srv-db1sgdtg1s2s73bjmuvg`
- Deploy: `dep-db1sge5g1s2s73bjn1hg`, live at 15:55 UTC
- Code: `bf10b93c65e00c829362462f412d1734ace9e422`
- Saved result captured: `2026-10-05T15:50:11.427Z`
- Private access expires: `2026-10-08T15:50:11.427Z`

All nine focused tests and the live HTTPS route/access checks passed. The served browser script matched the committed source exactly, and authenticated data reported canceled / refunded / refund succeeded. Production scheduling, web billing, and directory checkout remain disabled. The private link is supplied separately to the user; actual iPad rendering is pending. This saved display does not complete the separate paid-booking or original Stripe redirect acceptance checks.
