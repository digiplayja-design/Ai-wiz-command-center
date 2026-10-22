# Accessible signup and three-day trials — 21 October 2026

Frontend branch: `release/accessible-trials-20261021`.
Source base: `002725add41fbd4b79d4059c218d08a17da63b95` on `release/report-images-20261019`, preserving the newer Android billing, email-confirmation and report-image changes.
Backend companion branch: `release/signup-plan-intent-20261021`, based on `92cad91d290d4ac93d273960c1144798f3afd14f`.

## Registration

Registration, the entry welcome and confirmation use a white surface, static cyan circuit details, the official logo and readable dark text. Signup requires an explicit Ultra, Pro or Basic selection, in that order. Ultra is recommended; Basic says “Most features are extremely limited” and remains free. There is no paid plan selected by default.

The plan choice survives email confirmation using an account-specific local preference and non-authoritative signup metadata. A verified account opens subscription review; selecting a plan or creating the account never starts a purchase or grants paid access. The existing age, policy, parent-permission and email-verification checks remain in force. Web users can create accounts and activate native trials after signing in to the Android or iOS app; the existing web payment flow is not changed into a trial flow.

Rendered screenshots from the actual Flutter widgets:

- [Plan selection](accessible-signup-20261021/signup-plans.png)
- [Account registration](accessible-signup-20261021/signup-account.png)

These screenshots were rendered without a store session. The app shows localized prices when the store returns them rather than inventing prices for an unavailable catalog.

## Trial and billing behavior

Google Play selects an eligible monthly offer with exactly one free `P3D` phase followed by a paid, infinitely recurring `P1M` phase. The renewal price comes from the paid phase, never the trial’s zero price. The regular monthly base plan remains available when a trial is ineligible; annual and seven-day offers are not selected as a three-day trial.

Apple uses the monthly auto-renewable StoreKit 2 product, its introductory free-trial duration and StoreKit eligibility. An Apple free introductory offer with a different duration is not presented as this offer. Unknown eligibility is not advertised as a confirmed free trial.

A trial tap rechecks the offer, eligibility and displayed renewal price. If they change or the catalog cannot be refreshed, the app stops before purchase and asks the user to review the offer again. The standard store sheet confirms the subscription. Existing account binding, cross-provider checks, restore handling, server verification and entitlement updates are preserved. Paid access is never granted optimistically by the client.

## Accessibility and version information

Accessibility is available before signup and under Legal & Privacy for every tier. Device preferences include system-preserving enlarged text, high contrast, larger inherited controls, reduced motion, quiet interface sounds and persistent message alerts. Text scaling does not cap a larger system setting. Reduced motion prevents automatic smoke and suppresses orbit wind and existing alert shaking; an explicitly requested smoke preview remains still. High contrast also removes decorative workspace frames. The existing Live Convo transcript and typed input are retained. Controls have semantic labels and keyboard access; device VoiceOver/TalkBack and switch access are described without presenting fake in-app screen-reader switches.

Legal & Privacy displays the runtime package version and build number with a copy control. This correctly reflects Android/iOS build-number overrides instead of hardcoding the pubspec build. The two newly direct dependencies were already in the lockfile; package versions did not change.

## Validation

Flutter 3.47.7 / Dart 3.13.5:

- 114 frontend tests passed; one optional screenshot-only test skipped. Coverage includes signup and confirmation, preference persistence/account isolation, 320px and enlarged-text layouts, privacy controls, runtime build information, reduced motion, orbit and alert behavior, and Apple/Google billing including changed/expired trial offers.
- 20 backend signup tests passed, including invalid plan rejection and proof that the plan metadata never grants an entitlement.
- Accessibility preferences, billing and app-information static analysis passed without issues. Targeted analysis including the existing large main file had no errors; existing main-file warnings and informational lints remain. A full-library analyzer run also encountered two pre-existing `dart:web_audio` imports in unrelated web player files.
- Actual Flutter registration screenshots were rendered and visually reviewed. `git diff --check` passed.

No store build, production deployment or store-console change is included in this source update. Test purchases use fake store catalogs; real device screen-reader/switch navigation and sandbox trial-to-renewal/cancellation/restore checks remain release checks.

## Store setup before release

In App Store Connect, configure a three-day free introductory offer for the existing monthly Pro and Ultra subscriptions in the intended subscription group. In Google Play Console, activate a three-day free introductory offer on each existing `monthly` base plan with new-subscriber eligibility and the existing monthly renewal price. Avoid developer-determined eligibility unless independently validated. Preserve the current product identifiers:

| Store | Pro | Ultra |
| --- | --- | --- |
| Apple | `com.korlixdeveloper.korlixai.pro.monthly` | `com.korlixdeveloper.korlixai.ultra.monthly` |
| Google Play | `korlix_pro` | `korlix_ultra` |

Verify regional availability, eligibility and the final store price before distributing a new build. Without a valid three-day offer, the app will not claim a confirmed free trial. Deploy the small backend companion before distribution for cross-device continuation; there is no database migration.

## Publishing status

Publishing these release branches was approved on 21 October 2026. This is a source update; store builds, production deployments, and store-console configuration remain separate release steps.

## Build 141 device feedback: visible trial message

Google Play confirmed version 12.0.2 (141) available to internal testers on 21 October 2026. The subsequent registration photo showed store prices on Ultra and Pro but only the generic "Trial eligibility checked by the store" fallback. The three-day duration was below Basic, making the trial offer too easy to miss. This screen does not establish why the store did not return a confirmed trial for that account.

The follow-up adds a prominent "3-day free trial" callout before the plan cards, immediately qualified for eligible new Ultra and Pro subscribers and accompanied by monthly automatic-renewal and cancellation terms. Both paid cards now name the three-day free trial even when store eligibility is unconfirmed, with explicit conditional wording. Prices still come from the store; eligibility checks and purchase confirmation are unchanged. Web registration identifies Android/iOS as the trial activation location. The screenshots above document the initial layout before this follow-up.

Validation: all 25 existing signup/accessibility, Google Play billing and Apple billing tests passed, including 320px width and 200 percent text. Static analysis of the modified signup widget passed without issues, and `git diff --check` passed. This correction requires a new mobile build; the installed build 141 retains the earlier wording.
