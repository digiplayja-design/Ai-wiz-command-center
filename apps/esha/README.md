# Esha by Korlix

Esha is a standalone Flutter beauty consultant and personal collection app for
makeup, lipstick, lip gloss, lashes, body wash and lotion. The native design uses
the pink Korlix icon and the existing Esha visual direction.

## Native experience

- **Discover:** browse the manufacturer-sourced starter catalog, filter product
  categories, inspect product details and open the manufacturer page.
- **Ask Esha:** create a guided beauty edit around a budget and stated preferences,
  optionally using products already owned. Live AI consultation uses a separate,
  verified Esha membership and consultation allowance.
- **Try a Look:** explore illustrated lip colors, finishes and lash choices, then
  save a look. This is an illustration; the app does not scan a face or provide a
  camera-based virtual try-on.
- **My Vanity:** keep favorites, owned products, saved edits and looks. Guest
  collections stay on the device; signed-in collections can sync to the account
  with explicit handling of conflicting edits and pending changes.
- **Account and membership:** sign in, create a shared Korlix account, request a
  password-reset email, restore purchases, manage store subscriptions and request
  whole-account deletion. Deleting an account does not cancel store renewals.

Unknown product prices display as **Check price** and do not count as zero in a
claimed shopping budget. Known prices are dated snapshots, not live stock or
price guarantees. Physical products are purchased separately from membership.

Explicit AI-sharing consent and per-answer reporting controls are included.
The consent covers the current question, selected chat history and any
preferences the user elects to share with Korlix and OpenAI. Reporting lets the
user review the paired question, answer or disclosed
excerpt, reason and optional details before sending. Report submission uses the
existing authenticated support route and requires a returned receipt; no live
support report is sent as part of development checks.

## Account and session model

Esha uses the same Korlix identity while keeping an independent, bounded app
session identified as `esha_by_korlix`. A stored server-side binding determines
the session's scope; changing an app header cannot turn it into a hub or another
companion app session. Signing out of Esha preserves other Korlix app sessions.
An Esha subscription does not upgrade the account's Korlix Pro or Ultra tier.

The native app's account screens link to these public backend policy paths:

| Path | Purpose |
| --- | --- |
| `/esha/privacy` | Esha data use, AI sharing, retention and provider disclosures |
| `/esha/privacy#deletion` | Account/data deletion instructions inside and outside the app |
| `/esha/terms` | Esha service and membership terms |
| `/esha/terms#offer-heading` | Trial, renewal and store-pricing disclosures |

## Membership offer and activation

The approved U.S. offer is **3 days free for eligible subscribers, then $4.99 per
month**, automatically renewing through Apple or Google. The native purchase
sheet must show the actual localized price and the offer available to that store
account. A store-confirmed purchase starts an eligible trial; installation and
the device clock do not grant paid access.

**No trial or monthly consultation counts have been chosen.** The backend has no
default or unlimited allowance. Its configured counts must be disclosed before
purchase. Missing counts, output budget, explicit activation or verified store
configuration keep new purchases and native consultations unavailable. Purchase
restoration remains separate from opening new sales.

See [the native billing contract](../../backend/esha/billing/README.md) for
verification, entitlement accounting, refund handling and configuration.

## Validation and builds

The release-validation toolchain pins **Flutter 3.47.9**. Keep `pubspec.lock` and
use lockfile enforcement. From the repository root:

```sh
bash scripts/esha/validate.sh
```

This validates source configuration, resolves locked dependencies, checks Dart
formatting, runs static analysis and executes Flutter tests. Backend billing,
companion-session, signup, reporting, policy and surrounding-app checks passed
**121 tests**. The final native validation passed **36 tests**, checked formatting,
and reported no static-analysis issues. SDK telemetry is explicitly suppressed
by the Esha validation and build commands.

See [the build and signing guide](../../scripts/esha/README.md) for Android debug
and unsigned builds, iOS Simulator builds, and the separately configured signed
store-candidate workflows. Test artifacts are not store submissions.

## Release checkpoint — November 15, 2026

The following database migrations have been applied and their row-level security
and service-only command permissions checked:

| Version | Migration |
| --- | --- |
| `20261115172402` | `esha_store_billing` |
| `20261115172408` | `esha_companion_app_sessions` |

The full native source is preserved at commit
`d97cdda79f3e41be45ebeecd12718702e6b070dc` on
`feature/esha-native-20261115`. [GitHub Actions run 43741827963](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43741827963)
completed successfully for that exact commit, producing and verifying:

| Artifact | Verified use |
| --- | --- |
| Android debug APK | Android test-device installation; debug signature |
| Android release AAB | Release compilation; unsigned and not uploadable to Play |
| iOS Simulator application ZIP | Simulator execution; not an iPhone IPA |

Every artifact identifies `com.korlixdeveloper.esha`, version `1.0.0` build `1`.
Downloaded bytes were independently checked against the embedded verification
reports. Public source/build/hash details are recorded in
[build-verification.json](release/build-verification.json).

With explicit user authorization, Render deployment
`dep-dbsv84psrm7s739ov350` went **live on November 15, 2026 at 18:04:37 UTC**
for the exact backend commit `4bb80c1ce6fe1a314a31a23b60b70832c1045556` on
`release/signup-plan-intent-20261021`. Automatic deployment remains off. The
commit identity was verified from Render's live deployment metadata; the health
endpoint does not report a commit identifier.

All **nine GET-only post-deployment checks passed at 18:06:09 UTC**. Health
returned HTTP 200, and the live catalog exactly matched the local catalog's 12
products, including one unknown price. The Apple and Google billing catalogs
returned the intended 3-day / US $4.99 monthly offer while retaining
`purchasesEnabled: false`, `consultationEnabled: false`,
`storeConfigurationVerified: false` and `allowanceConfigured: false`. Both
consultation limits remain unset and the membership state remains `planned`.
An invalid billing provider returned HTTP 400, and unauthenticated billing-status
and account requests returned HTTP 401. No account, purchase or consultation was
created by these checks. Render's application error-log query since this
deployment returned no errors.

The following public policy URLs are verified live. The Privacy and Terms pages
returned HTTP 200 with the expected Esha content and restrictive CSP, `nosniff`,
`no-store` and `no-referrer` headers; the linked deletion and offer anchors were
checked in those pages.

| Public URL | Verified content |
| --- | --- |
| [Esha Privacy Policy](https://chee-chai-chee-backend.onrender.com/esha/privacy) | Esha data handling and AI-provider disclosure |
| [Esha Terms & Membership](https://chee-chai-chee-backend.onrender.com/esha/terms) | Service and intended membership offer |
| [Account/data deletion](https://chee-chai-chee-backend.onrender.com/esha/privacy#deletion) | Outside-app deletion-request instructions |
| [Subscription terms](https://chee-chai-chee-backend.onrender.com/esha/terms#offer-heading) | Trial, pricing and renewal disclosures |

The deployment identity and public HTTP results are recorded alongside the
unchanged native artifact hashes in
[build-verification.json](release/build-verification.json).

[Store metadata](release/store-metadata.json) is prepared as a draft, with source
identifiers distinguished from unverified store records. Store login/verification
and Google Play browser access remain unresolved. No app listing, subscription
product, signing identity or store submission was created by this checkpoint.

Signed Android/iPhone release builds, Esha's actual store app and subscription
records, localized prices, eligible trial configuration, consultation allowances,
and real-device purchase, restore, cancellation, refund and account-switch checks
remain pending. The backend deployment and these test artifacts do not establish
a live store release.
