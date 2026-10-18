# iOS Social notification setup

The existing iOS signing configuration is unchanged. Builds using
`Runner/Runner.entitlements` do not advertise Social push support. No notification
permission is requested until the user explicitly enables Social notifications.

To enable APNs in a signed build:

1. Enable **Push Notifications** on the existing Apple Developer app identifier
   `com.korlixdeveloper.korlixai`; refresh its provisioning profiles in the build
   service. Preserve the existing keychain groups and other capabilities.
2. For the **Runner target**, select
   `CODE_SIGN_ENTITLEMENTS = Runner/RunnerPush.entitlements` and set
   `KORLIX_APNS_ENVIRONMENT = production` for App Store, TestFlight and production
   profiles. Development profiles require `development`. Set both values in the
   same build configuration; do not determine the APNs environment from DEBUG.
   Existing builds may keep the original entitlements and the environment unset.
3. Confirm the signed app's entitlements contain the matching `aps-environment`
   with `codesign -d --entitlements :- /path/to/Runner.app`. Confirm its built
   Info.plist `KorlixAPNsEnvironment` matches. Verify the exported IPA, because
   an export can change signing profiles. Rebuild if these values differ.
4. Configure the backend APNs provider with its Apple team ID, key ID, APNs
   signing key and allowed bundle ID using the backend's documented secret
   configuration. Never put a provider signing key in the app, source control,
   `--dart-define`, or notification payload.
5. Install the signed build on a physical iPhone/iPad, sign in, enable Social
   notifications, and allow the iOS permission prompt. A token is returned only
   after APNs registration succeeds. Test permission denial, background message,
   cold-launch open, foreground/unlocked quick reply, logout and account switch.

The `korlix/social_native` channel exposes `capabilities`, `activate`, `current`,
`subscribe`, `unsubscribe` and `takeEvent`. Identity is the same canonical JSON
`[issuer, subject]` string used by the authenticated Dart adapter. Each installation
has a random device ID; each account binding is random and changes on logout,
account switch, or unsubscribe. APNs tokens are obtained on launch, not persisted.
Provider registration returns `environment: sandbox` for development, otherwise
`production`. Capability means this build is configured; successful registration
is the final OS check of its actual signing entitlement.

APNs custom payload keys are `owner`, `binding`, `kind` (`peer` or `group`), `id`,
`event_id`, `expires_at` (ISO-8601), `silent` (`true` or `false` string), and
`type` (`message`, `call`, or `online`). Expired actions are rejected, including
queued actions that expire while authentication is being restored. Use
`aps.category = KORLIX_SOCIAL_MESSAGE` for message alerts and
`KORLIX_SOCIAL_OPEN` for other activity. Alert title/body must be generic and
must not contain names or message text. Payloads with a wrong owner/binding are
never opened/replied to. Logout unregisters APNs and removes delivered/pending
Social alerts. iOS may still display an already in-flight generic remote alert;
the main process cannot intercept system delivery while suspended.

Reply uses `UNTextInputNotificationAction` with foreground and authentication
required. Its text remains in a bounded in-memory event queue until Dart restores
the correct authenticated owner and drains `takeEvent`. Native code never sends
a reply, fetches messages, stores bearer tokens, answers a call, or starts a mic.
The stream's `event` callback signals queued events; a token callback instead
signals Dart to reread `current`. Call alerts only open the existing call screen.

No silent-push/background-fetch or VoIP entitlement is added. Existing Rici/Social
WebRTC background audio, remote Stop controls and short sound effects are unchanged.

## Video Picture in Picture

This change does not claim chat overlays or video PiP on iOS. The pinned
`flutter_webrtc` package exposes native tracks, but does not provide a complete
iOS video-call PiP surface through the current app's Dart call view. A separate
implementation must attach the remote WebRTC video renderer to an
`AVPictureInPictureVideoCallViewController`, handle call teardown/restore, and
check multitasking-camera availability and entitlement requirements before
keeping local video active. It requires an Xcode build and real-device call
testing; ordinary notifications do not provide this capability.

Primary references:
- https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment
- https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction
- https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls
