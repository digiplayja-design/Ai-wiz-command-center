# KORLIX Messenger native notification integration

The owner reported the Android test app worked and requested continued work on October 25, 2026. This is owner-reported testing; two-account messaging, background delivery and signed-store installation have not been independently observed.

## Runtime behavior

`GET /api/social/native_push_state`, `POST /api/social/native_push_subscribe` and `POST /api/social/native_push_unsubscribe` use the existing verified Social authentication. The app scope comes from the server's persisted companion session, never caller headers or body fields. Hub and Messenger registrations have independent device limits, state and unsubscribe operations. Messenger registration requires its active provider login and the `com.korlixdeveloper.messenger` package. Receipt Wiz cannot enroll.

The service-only, RLS-protected queue checks blocks, membership, reads, deletions, dumps, preferences and expiry again before delivery. Messenger also rechecks its active login; revoked logins cancel delivery. Token rotation/account handoff invalidates queued work. Sending uses leases, bounded retries, provider Retry-After, and no replay after an uncertain send. Private message text, sender names and group names are excluded from provider payloads. Android uses data-only HTTP v1 FCM so the existing native owner/binding check runs before displaying an alert. Apple support is included but remains unconfigured.

The integration adapts the earlier staged Social native-push implementation from `feat/social-native-push-20261018` to the deployed Messenger backend. Existing web-push functions are unchanged. All native functions are security invoker with an empty search path; only `service_role` can access the tables or execute the RPCs. Existing Social test fixtures now include their new companion-session schema dependency.

## Provider configuration

Firebase is not yet installed/connected in this ChatGPT session. Provider delivery remains disabled until its actual client registration and server credentials are configured and tested. Do not enable it merely because database and HTTP tests pass.

Messenger uses its own environment variables:

| Variable | Purpose |
| --- | --- |
| `MESSENGER_NATIVE_PUSH_ENABLED` | Explicit master switch; absent/false disables delivery |
| `MESSENGER_NATIVE_FCM_ENABLED` | Explicit Android provider switch |
| `MESSENGER_NATIVE_FCM_PROJECT_ID` | Firebase project containing the Messenger Android app |
| `MESSENGER_NATIVE_FCM_APP_ID` | Android package; defaults to `com.korlixdeveloper.messenger`; a different value disables FCM |
| `MESSENGER_NATIVE_FCM_SERVICE_ACCOUNT_FILE` | Private server-mounted credential file with FCM sending permission |
| `MESSENGER_NATIVE_APNS_ENABLED` | Separate Apple provider switch |
| `MESSENGER_NATIVE_APNS_APP_ID` | Messenger bundle ID |
| `MESSENGER_NATIVE_APNS_TEAM_ID` / `KEY_ID` | Apple issuer and key identifiers; each uses the full `MESSENGER_NATIVE_APNS_` prefix |
| `MESSENGER_NATIVE_APNS_PRIVATE_KEY_FILE` | Private server-mounted Apple `.p8` file |
| `MESSENGER_NATIVE_APNS_ALLOW_SANDBOX` | Explicit allowance for signed development-device testing |

`SUPABASE_URL` remains the trusted authentication issuer. Hub notifications use `SOCIAL_NATIVE_*` with package `com.korlixdeveloper.korlixai`. Messenger never falls back to hub flags, credentials or app IDs. Provider status responses expose readiness only, not credential paths, token values or project secrets.

The Android app needs the public Firebase `google-services.json` for its package and a rebuild before FCM is available. A service-account JSON must never enter an APK, AAB, repository or client artifact. The existing test APK has no Firebase client configuration and cannot demonstrate remote background delivery.

## Release checks

Run the native provider/HTTP and SQL tests plus Social, Messenger inbox/auth and companion-session regressions. Exercise notification permission denial, background receipt, taps/replies, logout, account switching, revoked sessions, reinstall and two-device calls with explicit test accounts before a production store rollout. These remaining checks require configured providers and actual devices.

Official protocol references: [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api) and [Android delivery options](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidConfig). The newer AndroidConfigV2 client is currently documented as an EAP; this integration retains the stable data-only path used by the implemented Android receiver.

Validation: all 251 Social/Messenger/companion regression tests passed, including 54 native provider/HTTP/SQL cases. Migration `20261025020547_korlix_social_native_push.sql` is applied; its SQL MD5 `675071708d4a2c483e005dc71f1c1aa6` matches local source exactly. Live checks confirmed RLS, no anonymous/authenticated table or RPC access, invoker rights, empty search paths, service-role execution and zero enrolled native subscriptions. Security advisors reported no warnings or errors. Provider readiness is verified at server startup after deployment.
