## Provider hardening — password protection and headers applied

Updated October 7, 2026 after user-authorized dashboard access. Supabase leaked-password protection is saved and verified; its Security Advisor warning has cleared. All ten Render header rules below are saved and verified on live responses. The app still renders its sign-in screen. PostgreSQL remains on 17.6.1.127 pending approval of an outage window for 17.11.0.003. See `DASHBOARD_STATUS_2026-10-07.md` for evidence and the remaining upgrade hold. The connected APIs do not expose these setting changes, so they were completed through the provider dashboards.

### Supabase leaked-password protection — completed

Open the production project’s **Authentication → Sign In / Providers → Email** settings and enable **Leaked password protection / Prevent use of leaked passwords**, then save. The official documentation links directly to `https://supabase.com/dashboard/project/_/auth/providers?provider=Email` (choose the production project). This check rejects known breached passwords using Have I Been Pwned and is available on **Pro and above**. Confirm the actual organization plan; do not claim it is enabled or upgrade a paid plan without authorization. Afterwards, rerun the Security Advisor and verify the disabled-protection warning clears. Do not change customer passwords for this check. [Supabase password security](https://supabase.com/docs/guides/auth/password-security)

### Render static-site response headers — completed

For the existing **korlixdeveloper-website** service (`srv-d8ekf7t7vvec73dpar60`), open its dashboard **Headers** configuration (under service Settings in some layouts). Add each rule below twice, once for **`/app/*`** and once for **`/nova-email/*`**. Use relative paths, without a domain. Inspect existing rules first and edit matching entries instead of adding conflicting duplicates. [Render header rules](https://render.com/docs/static-site-headers)

| Header | Initial value | Reason |
|---|---|---|
| `Content-Security-Policy` | `frame-ancestors 'self'` | Prevent other origins from framing account screens while retaining same-origin embedding. |
| `X-Frame-Options` | `SAMEORIGIN` | Matching legacy frame protection. |
| `X-Content-Type-Options` | `nosniff` | Retain explicit MIME handling; already present on the observed app response. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Prevent URL paths/query details reaching other origins while preserving normal navigation behavior. |
| `Strict-Transport-Security` | `max-age=86400` | Begin with a one-day HTTPS-only policy; raise to `max-age=31536000` after confirming TLS and redirects on each served host. |

Repository review found no intentional cross-origin framing of these account screens. `'self'` is the conservative compatibility choice; use `'none'` plus `DENY` only after confirming same-origin framing is unnecessary. `frame-ancestors` restricts who embeds these pages, not their outgoing video/preview frames, and must be an HTTP header: a meta tag does not enforce it. Do not add an untested `default-src`/`script-src` CSP that could break Flutter, Wasm, OAuth, media, or external APIs. [Frame ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors)

Although header delivery is path-scoped, **HSTS persists for the entire responding hostname**, not only `/app/`. Initially omit `includeSubDomains` and `preload` to avoid affecting unverified subdomains. [HSTS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)

After saving, check actual responses for both paths, their trailing-slash entry points and `/app/main.dart.js`; confirm bare `/app` and `/nova-email` redirect to the protected paths. Verify app startup, sign-in, email launch, OAuth return, and media still work. Inspect the custom domain and Render hostname separately.

**A repository `render.yaml` alone is not an applied fix for this manually configured service.** Render requires a created/connected Blueprint and a sync that adopts the existing resource; adding an existing service requires preserving its complete current configuration. A code deploy does not automatically adopt it into a Blueprint. Direct dashboard header configuration is the smaller change. Render also documents REST `GET/POST /v1/services/{serviceId}/headers` if an authorized API capability is later available. No Blueprint adoption was performed. The ten provider header rules were applied directly in the dashboard on October 7, 2026. [Blueprint setup and existing resources](https://render.com/docs/infrastructure-as-code) · [Header API](https://api-docs.render.com/reference/add-headers)

Additional primary references: [Referrer-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referrer-Policy) · [nosniff](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Content-Type-Options). The Supabase [changelog index](https://supabase.com/changelog.md) was checked; no relevant change superseding the documented leaked-password plan requirement was found.
