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

The literal origin is required by the loader's `auth_referrer_policy=origin`; the pair covers the exact host according to [Google's browser restriction guidance](https://docs.cloud.google.com/api-keys/docs/add-restrictions-api-keys) and [Maps loader guidance](https://developers.google.com/maps/documentation/javascript/load-maps-js-api). Use only the actual assigned allowed acceptance hostname, never `*.onrender.com`.

In the current rollout, the owner explicitly saved both the production and allowed acceptance host pairs on the same public Maps JavaScript key; see the [release record](../../../docs/releases/brain-projection-20261111/README.md). The production pair is `https://chee-chai-chee-backend.onrender.com` and `https://chee-chai-chee-backend.onrender.com/*`. The independent wrong-origin check must use that same candidate key from a controlled host absent from its allowlist. Do not add the denial-test host to the key. Private server-side geocoding credentials remain separate. No credentials or restrictions are created or changed by this service.

## What runs

`earth.mjs`, `camera.mjs` and `earth.css` are served unchanged from `../public/`. The frame copies the released nonce CSP and denied camera/microphone/geolocation/payment policies. The test does not replace the SDK, simulate steady events, inspect Google's shadow DOM, or modify attribution.

The positive view observes the production loader and real map events. It records the requested channel/policies, actual SDK version, current steady state, animation count and sanitized provider error codes. Press **Fly to landmark**, exercise the other camera controls, and explicitly confirm visible imagery at the San Francisco Ferry Building and usable attribution/legal links. The landmark is a requested public test location, not a claim that provider coverage has already been verified. `gmp-steadychange` must identify the actual map element and supply `isSteady === true`; `isTrusted` is not required because SDK custom events need not be browser-native events. A constructor or loader HTTP 200 cannot pass the check.

Every camera command clears the visual checkboxes. A later nonsteady event invalidates the positive observation until the scene settles again. Animation-end events are diagnostic only, because reduced-motion or zero-duration camera changes may not produce one.

Camera availability is separate from a successful observation. A ready, currently steady scene with no map, loader, page or provider errors can accept camera commands even when a CSP event has been recorded. Visual checkboxes become available after **Fly to landmark** under that same interaction condition. A CSP event continues to prevent `POSITIVE_OBSERVATION_COMPLETE`; enabling camera testing never clears or waives that event. The page explains both the control state and any pending policy review.

Evidence version 4 retains the previous bounded CSP summaries and adds the wrong-origin scenario. Effective directives, dispositions, and blocked/source resource categories are fixed labels, sanitized both when recorded and when the parent receives them. No blocked/source URL, hostname, path, query, fragment, policy text, nonce, referrer or code sample is exported. The aggregate count is capped at 100; a value of 100 means at least 100 events, not 100 distinct problems. At most eight distinct CSP summaries are retained.

### Dynamic map styles

The map document's CSP includes `style-src-attr 'unsafe-inline'`. The real iPad run of Maps JavaScript 3.65.14a rendered the landmark and completed camera animations, but reported enforced `style-src-attr` violations from Google Maps. This directive permits the SDK's dynamic style attributes. Nonces authorize style elements, not attributes; adding more Google domains would not authorize inline attributes either. See [CSP style-src-attr](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/style-src-attr) and [Google's nonce-based CSP guidance](https://developers.google.com/maps/documentation/javascript/content-security-policy).

This allowance applies to **all inline style attributes in the static map document**, not just attributes created by Google. That document accepts no user-supplied HTML and consumes no application credentials. Its existing script and style-element policies, network destinations and denied device capabilities remain intact. The acceptance shell does not receive this allowance. A same-origin iframe with `allow-scripts` and `allow-same-origin` is not a complete security boundary; keep the static map-only design.

The production renderer and acceptance frame use the same policy in source, but deploying this service does not deploy the production backend. After an update, reload the page and start a **fresh** test. Old reports retain their violations. Version 4 still requires zero CSP events for a positive observation; no events are ignored or reclassified as successful. The completed version 3 allowed-origin observation remains valid within its original scope.

## No-referrer diagnostic

Open `/no-referrer`, then press **Load test map**. Version 4 sets the shell and frame HTTP headers and meta policies to `no-referrer`, and applies that policy to the iframe navigation before setting its source. A clearly isolated test observer additionally overrides the exact Google SDK loader script's explicit `referrerPolicy` immediately before `head.append`/`appendChild`; otherwise the unchanged production loader would override the document policy. The standard and wrong-origin views never change this loader property. The observer preserves native insertion behavior and does not forge an allowed referrer.

This changes referrer policies, not the page's own origin. The exact SDK version used in the iPad run also supplies the origin explicitly in its authentication and 3D-configuration request messages; see the [source review](../../../docs/releases/brain-projection-20261111/no-referrer-source-review-20261112.md). A scene rendered on an approved host under this diagnostic does **not** establish an unrestricted key. The exported policy fields describe configuration, not measured request headers. Version 3's outer shell/navigation gap is corrected, but that correction does not promise a provider denial.

Inspect the browser's actual relevant Google SDK and authorization request headers, including requests beyond the first loader. The page cannot observe cross-origin request headers itself. Check the header-observation box only if those requests omit `Referer`. The negative result remains **INCONCLUSIVE** until both that observation and `RefererNotAllowedMapError` exist. `RefererDeniedMapError` is a terms-of-service enforcement error and is not accepted as referrer-restriction evidence. Any observed steady scene causes the negative test to fail even if a later error occurs.

## Wrong-origin denial check

Deploy the same isolated acceptance server on a separately controlled HTTPS origin absent from the candidate key's current allowlist. Configure the same candidate public browser key used in the completed positive check. Leave Google's saved restrictions intact and do not add this new hostname. No private credential, account access, production activation setting, database, or provider proxy is needed.

Open `/wrong-origin` on that unapproved host and press **Load test map**. It uses the normal production SDK loader, origin-scoped authorization, and `strict-origin-when-cross-origin` policies. Confirm the origin-allowlist checkbox only after establishing that the displayed origin is absent from the key's current saved website restrictions. This is an attestation of the configuration, not a key-management action.

The wrong-origin observation requires an actual renderer error with `RefererNotAllowedMapError`, no current or previous steady scene, the expected loader/policy configuration, and that origin-allowlist attestation. A rendered scene fails the check. Generic errors, missing WebGL support, billing or quota failures, disabled APIs, and terms-of-service blocks do not establish a website restriction. Copy the sanitized report for review; this service still cannot verify all production requirements or activate production.

API allowlist denial, project quotas/billing review, and Android/iPhone WebView acceptance remain separate observations. Never use a synthetic fixture or a deployment flag as live-provider evidence.

## Evidence and production boundary

Evidence stays in the tester's browser and can be copied as sanitized JSON. The export contains no key text, raw errors, request URLs or headers. Do not substitute a full network archive containing the candidate key for this sanitized report. Closing the map removes its iframe; closing/reloading the page clears evidence. No evidence is submitted to this service.

`overallVerification` remains `NOT_ESTABLISHED` and `productionActivation` remains `false`, even after a positive local observation. This service never reads or writes `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` and does not deploy or modify the production backend. Success on this isolated acceptance origin does not prove the production origin is allowed. The actual production renderer and Android/iPhone WebViews still need their own allowed-origin, referrer, imagery, controls and lifecycle checks before an authorized owner sets the production verification flag. The owner must separately review all required observations before any production activation.

## Targeted checks

```sh
node --test backend/test/brain_projection_acceptance.test.mjs
```

These tests cover isolation, missing/invalid configuration, exact asset bytes, request allowlists, nonce/CSP parity and shell separation, deliberate negative-policy application and evidence classification/redaction. The browser fixture in `backend/tools/check_projection_renderer.mjs` additionally checks real CSP enforcement: dynamic style attributes apply, while unnonced style blocks and parser-inserted inline scripts remain blocked. The existing `strict-dynamic` script policy permits non-parser-inserted scripts created by trusted code, so a dynamically appended script would not test this denial. These checks use no real key or Google request and do not establish live-provider acceptance.
