# Isolated Projection map acceptance

This small Node service provides a real HTTPS test surface for the released Google Maps JavaScript `maps3d` adapter. It does not activate production. It has no package dependencies, database, account authentication, geocoder, AI requests, proxy or arbitrary file route.

## Start and deployment settings

Run with Node 22 or later from the repository root:

```sh
node backend/brain_projection/acceptance/server.mjs
```

The server binds `0.0.0.0:$PORT`; the default port is `10000`. For an explicitly authorized Render **Free** web service, use the repository root, `NODE_VERSION=22`, build command `node --check backend/brain_projection/acceptance/server.mjs`, start command above, and health check `/health`. No dependency installation is needed. Creating or changing a service is separate from this code; no infrastructure is provisioned by it. Use the actual HTTPS hostname returned by Render, never an assumed hostname.

Only these environment variables are read:

- `PORT`: the listening port.
- `BRAIN_PROJECTION_ACCEPTANCE_BROWSER_KEY`: the candidate public, website-restricted Maps JavaScript API key.

The acceptance key has no fallback to any production key or setting. Initially deploy without a key: the public page identifies its exact origin and shows setup required, and `/health` stays healthy. After an authorized owner configures the key for that origin and securely supplies it to this acceptance service, an explicit **Load test map** button starts the SDK. Root pages never include the key, and no Google SDK loads merely by opening a page, including direct frame URLs. The candidate browser key is necessarily present in the map frame when configured; it is not a private server credential.

### Candidate key restrictions

Project API enablement and a key's API allowlist are separate controls. The owner must enable **Maps JavaScript API** in the chosen project, then restrict this candidate key's API allowlist to **Maps JavaScript API only**. Enabling another API in that project does not authorize this key to use it. This acceptance service has no geocoding feature and needs no geocoding key.

For the candidate key's website restrictions, copy the exact HTTPS origin displayed by the deployed acceptance page as two entries:

1. The literal origin, with no trailing slash or path.
2. The same literal origin with `/*` appended.

The literal origin is required by the loader's `auth_referrer_policy=origin`; the pair covers the exact host according to [Google's browser restriction guidance](https://docs.cloud.google.com/api-keys/docs/add-restrictions-api-keys) and [Maps loader guidance](https://developers.google.com/maps/documentation/javascript/load-maps-js-api). Use only the actual assigned acceptance hostname, never `*.onrender.com`. Keep the candidate and production browser keys separate.

For comparison, the separate production browser key's exact-host entries are `https://chee-chai-chee-backend.onrender.com` and `https://chee-chai-chee-backend.onrender.com/*`. These are not the candidate key's acceptance-host entries. No credentials or restrictions are created or changed by this service.

## What runs

`earth.mjs`, `camera.mjs` and `earth.css` are served unchanged from `../public/`. The frame copies the released nonce CSP and denied camera/microphone/geolocation/payment policies. The test does not replace the SDK, simulate steady events, inspect Google's shadow DOM, or modify attribution.

The positive view observes the production loader and real map events. It records the requested channel/policies, actual SDK version, current steady state, animation count and sanitized provider error codes. Press **Fly to landmark**, exercise the other camera controls, and explicitly confirm visible imagery at the San Francisco Ferry Building and usable attribution/legal links. The landmark is a requested public test location, not a claim that provider coverage has already been verified. `gmp-steadychange` must identify the actual map element and supply `isSteady === true`; `isTrusted` is not required because SDK custom events need not be browser-native events. A constructor or loader HTTP 200 cannot pass the check.

Every camera command clears the visual checkboxes. A later nonsteady event invalidates the positive observation until the scene settles again. Animation-end events are diagnostic only, because reduced-motion or zero-duration camera changes may not produce one.

## Deliberate no-referrer check

Open `/no-referrer`, then press **Load test map**. Both the negative frame's HTTP header and meta policy are `no-referrer`. A clearly isolated test observer additionally overrides the exact Google SDK loader script's explicit `referrerPolicy` immediately before `head.append`/`appendChild`; otherwise the unchanged production loader would override the document policy. The positive view never changes this property. The observer preserves native insertion behavior and does not forge an allowed referrer.

Inspect the browser's actual relevant Google SDK and authorization request headers, including requests beyond the first loader. The page cannot observe cross-origin request headers itself. Check the header-observation box only if those requests omit `Referer`. The negative result remains **INCONCLUSIVE** until both that observation and `RefererNotAllowedMapError` exist. `RefererDeniedMapError` is a terms-of-service enforcement error and is not accepted as referrer-restriction evidence. Any observed steady scene causes the negative test to fail even if a later error occurs.

Wrong-origin testing requires a controlled HTTPS origin that is absent from the candidate key's current allowlist. This same acceptance host can supply that observation before its exact-host pair is authorized: the owner can initially allow only the production-origin pair on the separate candidate key, record `RefererNotAllowedMapError` from this unapproved test host together with the then-current restrictions, then add the acceptance-host pair and rerun positive and no-referrer checks. This requires no second service and no forged headers; the page does not automatically classify or claim a wrong-origin result. API allowlist denial, project quotas/billing review, and Android/iPhone WebView acceptance remain separate observations. Never use a synthetic fixture or a deployment flag as evidence.

## Evidence and production boundary

Evidence stays in the tester's browser and can be copied as sanitized JSON. The export contains no key text, raw errors, request URLs or headers. Do not substitute a full network archive containing the candidate key for this sanitized report. Closing the map removes its iframe; closing/reloading the page clears evidence. No evidence is submitted to this service.

`overallVerification` remains `NOT_ESTABLISHED` and `productionActivation` remains `false`, even after a positive local observation. This service never reads or writes `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` and does not deploy or modify the production backend. Success on this isolated acceptance origin does not prove the production origin is allowed. The actual production renderer and Android/iPhone WebViews still need their own allowed-origin, referrer, imagery, controls and lifecycle checks before an authorized owner sets the production verification flag. The owner must separately review all required observations before any production activation.

## Targeted checks

```sh
node --test backend/test/brain_projection_acceptance.test.mjs
```

These tests cover isolation, missing/invalid configuration, exact asset bytes, request allowlists, nonce/CSP parity, deliberate negative-policy application and evidence classification/redaction. They use no real key or Google request and do not establish live-provider acceptance.
