# KORLIX Messenger 1.0.1 (build 4) release record

The authorized release deployed the production backend and database changes and uploaded the signed Android bundle to a Google Play production draft. **The Android release is not submitted or published.** Play blocks submission until the foreground-service declaration includes a video demonstrating Android screen sharing.

## Source and backend

- App PR #26 merged at `5a080008eb890b9784242d49c1c910a41e33ee52`. The signed build used `5a4ec3615630c608387b8c7d7664622c97a9e424`; both have the identical tree `ff0a6bb308dfa90f0dae0d777abff26d6cf4eaa6`.
- Backend PR #28 merged at `80e311721cbfc18372ed46350570d917890a25f9`, integrating the Messenger changes on the then-live `ae503f5b70cf528e54f11da3dacceeba2c1f6527` base. The tested tree is `ab1c975dbc6f3bf952c5051cd8fbd54027f1697a`. This preserves the newer Auto-Email work; PR #27 was closed as superseded.
- Production migration `20261028160934_korlix_social_message_interactions.sql` was applied before the backend deployment. Formatting columns, reaction storage/RPC, RLS and service-role-only access were verified. Anonymous and authenticated database roles have no direct reaction-table or RPC access.
- Render deployment `dep-dbh21ml9el5s73dpndug` is live on the merged backend commit. `/api/health` returned 200 with Supabase and Auth configured, and an unauthenticated `/api/social/react` request returned 401. No private user messages were read or created for these checks.

## Signed Android artifact

| Field | Verified value |
| --- | --- |
| Package | `com.korlixdeveloper.messenger` |
| Version | `1.0.1` / version code `4` |
| Filename | `KORLIX-Messenger-1.0.1-build4.aab` |
| Bytes | `92979192` |
| SHA-256 | `90aa1ee77dfa5e1a85cef6adb3d438c3b86388c975edb8f83d98a064511441ef` |
| Upload certificate SHA-256 | `35ef7904721695155160430e265765dc7bda73ff3d9018e94f9aaadc2f66b4c3` |
| Android SDK | minimum 24, target 36 |

The bundle was built in an isolated Codespace checkout using Flutter 3.47.7 and the existing Messenger upload identity. Archive CRC and JAR signature verification passed. The Firebase app ID and API key match the previously released Messenger bundle. All ten ARM64/x86-64 native libraries have load-segment alignment of at least 16 KB; Play also reports 16 KB compatibility. Temporary signing inputs were removed after the build, and the source checkout remained unchanged.

Validation passed: 27 standalone Messenger tests and standalone analysis in the release build environment; 181 backend tests on the integrated production tree. Earlier mobile validation run [40716915868](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40716915868) passed the Android debug build, iOS simulator build, 27 standalone tests and 197 shared app tests. The prior focused interaction suite passed 86 tests. Automated validation does not establish physical two-device behavior.

Machine-readable artifact checks are in [the build verification record](evidence/korlix-messenger-play-build4-20261028.json).

## Play draft and remaining work

Play accepted bundle 4 (1.0.1) in production release 2 and saved these release notes:

> React to messages, format selected text, and explore 48 sticker and GIF designs. Share private video clips, enjoy improved call controls and notifications, and share your screen during Android calls. Includes profile, inbox, accessibility, and reliability improvements.

The review page reports one blocking foreground-service declaration error and one download-size warning. Estimated new download size is 31.2 MB, 7.47 MB larger than the previous version; estimated update size is 10.1 MB. Supported devices remain 19,486. Build 3 (1.0.0) remains the published version.

The existing call/background-audio demo does not show screen sharing. The media-projection task is selected in the open declaration form, but its video field is blank and that declaration has not been saved. Supply a genuine accessible video showing a connected Android call, Share screen, Android capture consent, the screen reaching the other caller, and Stop sharing. Do not reuse the older video for a feature it does not demonstrate.

The Play bundle explorer exposes a signed universal APK for device testing. Physical two-device call/sharing, long-press selection, keyboard/IME, reaction synchronization and GIF playback checks remain unverified. After those checks and the new video, complete the declaration, re-open release review, and submit the prepared production release.
