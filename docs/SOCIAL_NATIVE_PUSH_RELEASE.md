# KORLIX Social native notifications

This adds Android FCM and iPhone/iPad APNs notifications alongside the existing
browser Web Push service. It does not turn an iOS conversation into an overlay
over another app. Android chat bubbles are handled by the native app.

## Release state

The implementation is staged for review. No migration, production deployment,
credential change, live notification send, or phone installation is performed by
this change. Enabling a provider requires the matching native app build and the
server configuration below. A compiled build does not verify provider delivery.

## Server configuration

All native providers default to disabled. Browser Web Push variables and endpoints
remain unchanged. Credentials are read only from server files; never put them in
Flutter defines, the repository, release notes, or a public download directory.

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | Existing authenticated project URL; fixes the trusted JWT issuer |
| `SOCIAL_NATIVE_PUSH_ENABLED` | `true` only after the migration and native client are ready |
| `SOCIAL_NATIVE_FCM_ENABLED` | `true` to enable Android |
| `SOCIAL_NATIVE_FCM_PROJECT_ID` | Firebase project with FCM HTTP v1 enabled |
| `SOCIAL_NATIVE_FCM_APP_ID` | Exact Android application/package ID, not the Firebase application ID |
| `SOCIAL_NATIVE_FCM_SERVICE_ACCOUNT_FILE` | Private server path to a Firebase service-account JSON file with send permission |
| `SOCIAL_NATIVE_APNS_ENABLED` | `true` to enable iPhone/iPad |
| `SOCIAL_NATIVE_APNS_APP_ID` | Exact signed iOS bundle ID / APNs topic |
| `SOCIAL_NATIVE_APNS_TEAM_ID` | Apple Developer team ID |
| `SOCIAL_NATIVE_APNS_KEY_ID` | Apple APNs key ID |
| `SOCIAL_NATIVE_APNS_PRIVATE_KEY_FILE` | Private server path to the matching `.p8` key |
| `SOCIAL_NATIVE_APNS_ALLOW_SANDBOX` | Optional `true` only for development builds; production remains separate |

Readiness responses report configuration status, not a successful round trip to
Apple/Google. Missing or invalid credentials still require an operator to correct
the configuration and a signed-device test. Android's build needs its matching
Firebase client configuration; iOS signing needs Push Notifications entitlement
and the correct APNs environment. User notification permission remains required.

## API contract

All endpoints use the existing authenticated, email-confirmed Social account.
An active Social profile and database authorization are required to enroll.

* `GET /api/social/native_push_state`: `{enabled,native:true,reason,providers,subscriptions}`.
  `providers` has `fcm` and `apns` objects with `enabled` and `reason`.
  Subscription state includes device, binding, provider, environment and preferences,
  never a provider token or secret.
* `POST /api/social/native_push_subscribe`: `{device,binding,subscription,messages,calls,online}`.
  Device and binding are UUIDs; preferences are booleans. Subscription is
  `{provider:'fcm'|'apns',token,app_id,environment:'production'|'sandbox'}`.
* `POST /api/social/native_push_unsubscribe`: `{device,binding}`. Both are required,
  including when the native service is disabled. A delayed unsubscribe cannot
  remove a replacement binding.

The backend verifies the bearer token through the existing authentication path,
then checks its issuer and subject against its own project URL and verified user.
The notification owner is the exact compact JSON string `[issuer,authUserId]`.
Clients cannot choose an owner. Each device must discard its old binding, pending
opens/replies and visible notifications on logout/account switch. Rebinding a
native token atomically removes its former registration and pending queue rows.

The delivered fields are `owner`, `binding`, `kind` (`peer` or `group`), `id`
(peer profile ID or group ID), `event_id`, `type` (`message`, `call` or `online`),
`expires_at`, `silent`, `title`, and `body`. FCM data values are strings, including
`silent` (`true`/`false`). APNs custom values retain their JSON types.
Notification text is generic: no message body, contact name, media URL, or bearer
token is sent. FCM is data-only so native code can validate the current owner and
binding before displaying. APNs displays only a generic OS alert; opening or
replying must validate the current account. APNs message category is
`KORLIX_SOCIAL_MESSAGE`; calls and online alerts use `KORLIX_SOCIAL_OPEN`.
There is no background automatic call answering or unauthenticated reply route.

## Delivery and privacy

Native subscriptions and queue rows use separate RLS-enabled tables with no anon
or authenticated client grants. The service-only RPC enforces current profile,
connection, block, group membership, read receipt, dump/expiry, call and online
watch state before authorizing every send. Provider token replacement invalidates
older leases; disabled-device revocation remains available. Expired tokens are
removed only for explicit provider invalid-token responses. Credentials/project
errors do not delete valid subscriptions. Network outcomes that might already
have delivered are recorded as uncertain and never automatically replayed.

Provider acceptance is not proof of display. Device settings, Doze, focus modes,
force-stop, user permission and provider throttling can delay or prevent alerts.
The app must continue using authenticated Social history as the source of truth.

## Verification and rollout

1. Run the focused native API/provider/database tests and existing Social
   communication tests on the candidate revision.
2. Apply the additive native migration to the target database through the normal
   reviewed migration process. Keep native provider flags disabled initially.
3. Configure server credentials and package/bundle IDs, and produce matching signed
   Android/iOS builds. Enable one provider at a time for testing.
4. On two real accounts, test background and locked-screen delivery, bubble open,
   reply, group chat, muted/blocked/removed connections, logout/account switch,
   token rotation, and denied notification permission. Confirm a ringing-call
   alert only opens the authenticated app; it never answers automatically.
5. Confirm iOS production/TestFlight and development tokens use their own APNs
   environment. Inspect generic log status only; do not log provider tokens.
6. Publish only after signed-device checks. Disable the native master/provider
   flag to stop delivery without changing the existing browser push service.

## Provider references

* [FCM HTTP v1 send and OAuth](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
* [Apple APNs requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
* [Apple APNs token authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)
