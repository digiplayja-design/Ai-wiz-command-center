# KORLIX Messenger native notification integration

The owner reported the Android test app worked and requested continued work on October 25, 2026. This is owner-reported testing; two-account messaging, background delivery and signed-store installation have not been independently observed.

## Runtime behavior

`GET /api/social/native_push_state`, `POST /api/social/native_push_subscribe` and `POST /api/social/native_push_unsubscribe` use the existing verified Social authentication. The app scope comes from the server's persisted companion session, never caller headers or body fields. Hub and Messenger registrations have independent device limits, state and unsubscribe operations. Messenger registration requires its active provider login and the `com.korlixdeveloper.messenger` package. Receipt Wiz cannot enroll.

The service-only, RLS-protected queue checks blocks, membership, reads, deletions, dumps, preferences and expiry again before delivery. Messenger also rechecks its active login; revoked logins cancel delivery. Token rotation/account handoff invalidates queued work. Sending uses leases, bounded retries, provider Retry-After, and no replay after an uncertain send. Private message text, sender names and group names are excluded from provider payloads. Android uses data-only HTTP v1 FCM so the existing native owner/binding check runs before displaying an alert. Apple support is included but remains unconfigured.

The integration adapts the earlier staged Social native-push implementation from `feat/social-native-push-20261018` to the deployed Messenger backend. Existing web-push functions are unchanged. All native functions are security invoker with an empty search path; only `service_role` can access the tables or execute the RPCs. Existing Social test fixtures now include their new companion-session schema dependency.

## Provider configuration

Messenger Android FCM is now configured and enabled on the live backend. The owner saved its dedicated service-account JSON directly in Render Secret Files. Runtime validation confirmed the expected service-account type, project and account, the official OAuth token endpoint, and a valid RSA private key without printing the credential. OAuth succeeded and Firebase HTTP v1 accepted a `validate_only: true` request with HTTP 200. This proves provider authorization and request validation; it does not prove delivery to an Android device. The Firebase connector remains unavailable, so Firebase setup used the owner-approved browser workflow.

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

Android test build 0.1.0, version code 2, includes the actual Firebase client registration for `com.korlixdeveloper.messenger` in project `korlix-ai`. Its package, resource values and APK signature were verified, and its debug signer matches the earlier test build. Version code 1 lacks the Firebase client configuration and must be updated for background notification testing. A service-account JSON must never enter an APK, AAB, repository or client artifact.

The Render service uses `korlix-messenger-fcm.json` mounted at `/etc/secrets/korlix-messenger-fcm.json`, with both `MESSENGER_NATIVE_PUSH_ENABLED` and `MESSENGER_NATIVE_FCM_ENABLED` set to `true`, project `korlix-ai`, and Android package `com.korlixdeveloper.messenger`. Configuration was merged into existing service settings. Hub and Apple notification settings were not enabled.

## Release checks

Run the native provider/HTTP and SQL tests plus Social, Messenger inbox/auth and companion-session regressions. Exercise notification permission denial, background receipt, taps/replies, logout, account switching, revoked sessions, reinstall and two-device calls with explicit test accounts before a production store rollout. These remaining checks require configured providers and actual devices.

Official protocol references: [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api) and [Android delivery options](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidConfig). The newer AndroidConfigV2 client is currently documented as an EAP; this integration retains the stable data-only path used by the implemented Android receiver.

Validation: all 251 Social/Messenger/companion regression tests passed, including 54 native provider/HTTP/SQL cases. Migration `20261025020547_korlix_social_native_push.sql` is applied; its SQL MD5 `675071708d4a2c483e005dc71f1c1aa6` matches local source exactly. Live checks confirmed RLS, no anonymous/authenticated table or RPC access, invoker rights, empty search paths, service-role execution and zero enrolled native subscriptions. Security advisors reported no warnings or errors. Provider readiness is verified at server startup after deployment.

The initial native-push deployment at `f31c922ce3003f8e05e99746c5a7ae77c06b00c1` (Render `dep-dbem8npsrm7s73cjr2lg`, live `2026-10-25T02:08:09.849148Z`) passed 11 HTTP checks with both native providers disabled. That historical evidence remains in `docs/evidence/korlix-messenger-native-push-20261025.json`.

FCM activation used the same runtime commit. Render deployment `dep-dben7l5g1s2s7384p7ug` became live at `2026-10-25T03:13:58.531564Z`. Startup reported `korlix_ai: false` and `korlix_messenger: true`. All 11 live HTTP checks passed again, including rejection of unauthenticated requests to all three native notification endpoints. Evidence: `docs/evidence/korlix-messenger-fcm-activation-20261025.json`.

Next device check: install Android build 2, sign in, open the top-right menu, choose **Notification settings**, tap **Enable device notifications**, and allow Android permission. Put Messenger in the background and send a message from a separate authorized KORLIX account. Verify the alert, sound, tap destination, and logout/account-switch isolation. These device checks, signed Play AAB generation and Play publication remain pending.
