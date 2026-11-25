# FAX Number by Korlix

The mobile web app in `website/fax-number` uses existing confirmed Korlix accounts. Each account can request a U.S. local or toll-free line. The operator's Line requests screen manages activation. Only a verified company account holds that role. The migration seeds the first toll-free request using the existing Korlix support account.

## Carrier setup

Create a dedicated Telnyx Fax Application with inbound PDF delivery, an outbound voice profile covering the intended destinations, and this primary webhook:

```text
https://uxtjzjbwtppjvnsoiijv.supabase.co/functions/v1/korlix-fax/carrier
```

Set the Edge Function secrets `TELNYX_API_KEY`, `TELNYX_FAX_CONNECTION_ID`, and `TELNYX_PUBLIC_KEY` (the base64 Ed25519 webhook verification key) in Supabase. The browser receives only a fax-scoped session. If the app's origin changes, set `FAX_WEB_ORIGIN` to its exact HTTPS origin.

In **Line requests**, select the company request, review current inventory and confirm a quote. The app accepts fax-capable numbers with a verified USD price of up to $2/month and zero upfront cost. Transmission, usage and taxes are additional. An existing, routed number can be linked through **Link an owned number**. **Check order** reconciles uncertain orders. Verify the assigned number with a one-page outbound and inbound fax using a destination under your control before sharing it.

## Verification

Run `node --test backend/test/fax_number.test.mjs`. The tests exercise ownership, webhook verification, routing, replayed and out-of-order events, delivery states and duplicate purchases using fixtures.
