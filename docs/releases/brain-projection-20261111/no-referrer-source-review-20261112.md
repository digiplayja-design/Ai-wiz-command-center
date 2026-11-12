# No-referrer result: source review

## Observation

The owner's iPad [version 3 report](ipad-no-referrer-v3-20261112.json) recorded a ready, steady scene on the approved acceptance host while the document and initial loader were configured with `no-referrer`. The separate attestation of actual Google request headers was false. The test did not establish a provider denial or an unrestricted key.

## Independent sources of origin information

A document's outgoing HTTP `Referer` policy, its incoming `document.referrer`, and its own `location.origin` are different values. A `no-referrer` policy does not turn an approved HTTPS page into a different origin. Browser standards also allow individual requests to set their own referrer policy; an initial script attribute does not measure every later authorization request. See the [HTML script referrer-policy definition](https://html.spec.whatwg.org/multipage/scripting.html#attr-script-referrerpolicy) and [Referrer Policy specification](https://www.w3.org/TR/referrer-policy/).

[Google's loader documentation](https://developers.google.com/maps/documentation/javascript/load-maps-js-api#optional_parameters_direct) describes `auth_referrer_policy=origin` as limiting the page information used for authorization to its origin and requiring a matching domain-level restriction. It does not promise that suppressing only an HTTP header on an approved page will produce a denial.

## Versioned SDK source inspected

The publicly served, keyless loader selected Maps JavaScript **3.65.14a**, matching the owner's report. Read-only inspection used the provider's versioned [common.js](https://maps.googleapis.com/maps-api-v3/api/js/65/14a/common.js), [maps3d.js](https://maps.googleapis.com/maps-api-v3/api/js/65/14a/maps3d.js), and [main.js](https://maps.googleapis.com/maps-api-v3/api/js/65/14a/main.js). No provider source was changed or substituted into the app.

- In `common.js`, the helper named `_.Nv()` returns the page's `window.location.origin` when the loader's configuration field 45 is `origin`.
- The authentication request builder obtains that value and assigns it to the URL field of its request message before serializing the message for `AuthenticationService.Authenticate`.
- In `maps3d.js`, the `MSa` request builder places the same value in field 1 of the message sent to `MapsJsInternalService/GetMap3DConfig`, separately from the HTTP-header object.
- Inspection of the setters in `main.js` confirms that the message is the same object being passed to that request builder.

These are implementation observations about this SDK version, not a supported interface for application use. They establish an explicit origin-data path independent of the HTTP `Referer` header. They do not establish which bytes the iPad sent or how Google's servers selected their authorization decision. The observed successful render is consistent with this path and an approved page origin; the exact live authorization path remains unmeasured.

## Harness correction and next meaningful check

The live version 3 outer `/no-referrer` shell had the standard policy, and the child frame navigation had no explicit referrer-policy attribute. Version 4 corrects those navigation policies and explains their limits. It retains the original failed classification and the production verification boundary.

A separate wrong-origin check uses a controlled HTTPS origin absent from the key's saved website allowlist, while preserving the ordinary production loader and its origin-scoped authorization. Success requires an actual provider referrer-denial code and no rendered steady scene. No allowed referrer is forged, no SDK authorization field is altered, and no Google restriction is removed to manufacture a result.

An attempted fresh-profile local Chromium diagnostic could not launch because the runtime denied its process-singleton socket. It yielded no browser request-header evidence. Loopback HTTP and classifier tests remain synthetic checks of the harness, not live-provider or native-device verification.

The existing positive iPad observation remains valid within its original scope. The production activation flag remains false. Google credentials, saved restrictions, and the production application were not changed by this source review.
