# Esha by Korlix

Esha is a standalone Flutter beauty consultant and personal collection app for
makeup, lipstick, lip gloss, lashes, body wash and lotion. The native design uses
the pink Korlix icon and the existing Esha visual direction.

## Native experience

Discover, the routine planner, My Vanity, Try a Look and live consultations all
require a signed-in account with a freshly server-verified active Esha trial or
paid membership. A local purchase result or stored collection does not unlock
the app. Core features remain usable when an active member's AI allowance is
exhausted; live consultations also require available service, remaining
allowance and explicit AI-sharing permission.

- **Discover:** browse the manufacturer-sourced starter catalog, filter product
  categories, inspect product details and open the manufacturer page.
- **Ask Esha:** create a guided beauty edit around a budget and stated preferences,
  optionally using products already owned. Live AI consultations use the same
  Esha membership and its disclosed consultation allowance.
- **Try a Look:** explore illustrated lip colors, finishes and lash choices, then
  save a look. This is an illustration; the app does not scan a face or provide a
  camera-based virtual try-on.
- **My Vanity:** keep favorites, owned products, saved edits and looks. Signed-in
  collections can sync to the account with explicit handling of conflicting
  edits and pending changes. Existing device-only guest data remains separate
  and does not provide continued app access without membership.
- **Account and membership:** sign in, create a shared Korlix account, request a
  password-reset email, restore purchases, manage store subscriptions and request
  whole-account deletion. These account, recovery, restore, subscription,
  legal, support and deletion controls remain available without an active
  subscription, with account verification where needed. Deleting an account
  does not cancel store renewals.

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
account. A store-confirmed purchase starts an eligible trial; installation,
account creation and the device clock do not grant app access. A fresh server
check must verify the active store entitlement for the same signed-in Korlix
account. Stale or unavailable verification pauses feature access while keeping
saved collections; account and membership controls remain reachable.

**No trial or monthly consultation counts, Esha-specific AI model choice or
token/attempt budgets have been approved.** The backend has no default or unlimited
allowance. Its configured counts must be disclosed before purchase. Missing
counts, token/attempt limits, explicit activation or verified store configuration keep
new purchases and native consultations unavailable. Purchase restoration remains
available separately from opening new sales; restored feature access still
requires fresh verification of an active same-account entitlement.

See [the native billing contract](../../backend/esha/billing/README.md) for
verification, entitlement accounting, refund handling and configuration.
The [inactive AI option](../../backend/esha/billing/AI_OPTION.md) documents the
prepared Esha-only model adapter and provider-attempt budget. It has not changed
the shared Astra/max default or activated a production model.

## Validation and builds

The release-validation toolchain pins **Flutter 3.47.9**. Keep `pubspec.lock` and
use lockfile enforcement. From the repository root:

```sh
bash scripts/esha/validate.sh
```

This validates source configuration, resolves locked dependencies, checks Dart
formatting, runs static analysis and executes Flutter tests. The current native
source passed **49 tests**, formatting and static analysis locally and in the
successful cloud build at commit `bf4ff498e3aa71eea07d4052d8789cd37ddba7c0`.
The inactive AI preparation passed **55 scoped backend tests**, with its six
adapter tests passing again after the final activation guard. An earlier broader
backend checkpoint passed 121 tests; that earlier count is not presented as a
rerun of the later AI preparation.
SDK telemetry is explicitly suppressed by the Esha validation and build commands.

See [the build and signing guide](../../scripts/esha/README.md) for Android debug
and unsigned builds, iOS Simulator builds, and the separately configured signed
store-candidate workflows. Test artifacts are not store submissions.

## Release checkpoint — November 15, 2026

**Esha's signed iPhone build 2, with the branded launch screen, has been verified,
uploaded to Apple and selected for version 1.0.0.**
The existing `Codemagic Korlix AI` integration authenticated successfully, Esha's
dedicated provisioning profile is imported, and the Apple draft listing is
synchronized. Apple reports **both builds 1 and 2 as VALID and not expired**.
Version 1.0.0 remains **Prepare for Submission**. Review submission and customer
availability are not established by these checkpoints. The exact USA $4.99
monthly subscription draft and eligible three-day trial have also been created
and read back in Apple; the product is still **MISSING_METADATA**, and customer
purchases and AI remain disabled.

### Native builds

[GitHub Actions run 43754059868](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43754059868)
completed successfully at source commit
`bf4ff498e3aa71eea07d4052d8789cd37ddba7c0` on
`feature/esha-native-20261115`. Both the Android and iOS Simulator jobs succeeded.
The Android validation passed all 49 native tests, formatting and analysis.

| Artifact | Verified use |
| --- | --- |
| Android debug APK | Android test-device installation; debug signature |
| Android release AAB | Release compilation; unsigned and not uploadable to Play |
| iOS Simulator application ZIP | Simulator execution; not an iPhone IPA |

Downloaded bytes for all three artifacts were independently rehashed against the
CI reports. Binary inspection confirms `com.korlixdeveloper.esha`, version
`1.0.0`, build `1`, and the platform/signing classifications above. Exact hashes,
artifact provenance, verification methods and the older checkpoint are recorded in
[build-verification.json](release/build-verification.json). These hashes describe
the Android and Simulator artifacts at `bf4ff49`; the separate signed-device and
upload receipts below record the later iPhone builds. Inactive backend preparation
and documentation commits do not themselves establish a compiled or deployed
artifact.

### Live backend and policies

The following database migrations have been applied, with row-level security
and service-only command permissions checked:

| Version | Migration |
| --- | --- |
| `20261115172402` | `esha_store_billing` |
| `20261115172408` | `esha_companion_app_sessions` |

Render deployment `dep-dbt0l93l550s739n1p3g` went **live on November 15, 2026 at
19:41:04 UTC**, using backend commit
`5e2a4086b7c4a58e8614abfa3625270b05def152` on
`release/signup-plan-intent-20261021`. This revision changes only the Esha policy
wording to match whole-app membership. Automatic deployment remains off. The
commit identity comes from Render deployment metadata; the public health
endpoint does not expose a commit identifier.

At 19:41:54 UTC, health, both policy pages and both provider billing catalogs
returned HTTP 200. The deployed Privacy and Terms HTML exactly matched the
frozen source, including the deletion and offer anchors. Restrictive CSP,
`nosniff`, `no-store` and `no-referrer` headers were verified. No application
errors were returned by the Render log query since deployment.

| Public URL | Verified content |
| --- | --- |
| [Esha Privacy Policy](https://chee-chai-chee-backend.onrender.com/esha/privacy) | Esha data handling and AI-provider disclosure |
| [Esha Terms & Membership](https://chee-chai-chee-backend.onrender.com/esha/terms) | Whole-app membership, service and renewal terms |
| [Account/data deletion](https://chee-chai-chee-backend.onrender.com/esha/privacy#deletion) | Outside-app deletion-request instructions |
| [Subscription terms](https://chee-chai-chee-backend.onrender.com/esha/terms#offer-heading) | Three-day trial, pricing and renewal disclosures |

Both provider catalogs still report `planned` membership, the intended three-day
trial / US $4.99 monthly offer, and disabled new purchases and consultations.
Store verification and consultation allowances remain unset. The policy-only
deployment did not enable billing, change a model or apply the new AI-budget
migration.

### Apple identity, signing and verified uploads

The successful Apple API checks verified the exact **Esha by Korlix** record:
bundle `com.korlixdeveloper.esha`, SKU `ESHA_IOS_001`, numeric Apple ID
`6835184869` and team `FJKJ9MUDZ4`. These checks supplement the original
user-provided App Information and Apple Developer screenshots.

The earlier signing setup build `6afa092a90e83b09c4fab31e` was incorrectly
labeled HTTP 401. Pinned Codemagic CLI 0.69.0 rejected retry limits of zero
locally before an Apple request; the helper matched `unauthorized` in an option
name and reported an authentication failure. Corrected CLI calls use one attempt
with no retry and distinguish parser errors from actual Apple HTTP responses.
The saved integration worked without credential replacement.

[Signing setup build 6afa106590e83b09c4fab58f](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa106590e83b09c4fab58f),
source `d1e592b901efe020a9df7c3f6fc33a31600671f4`, verified the existing
`KORLIX_APP_STORE_CERT` identity and created Esha's App Store profile at
**20:05:54 UTC**. Codemagic subsequently confirmed the import under
**`ESHA_APP_STORE_PROFILE`**, with the exact Esha bundle and matching existing
certificate. The `esha_release` environment group supplies the verified app and
team IDs. The [signing receipt](release/ios-signing-20261115.json) distinguishes
the API verification from the UI-confirmed profile import.

[Draft-listing build 6afa194090e83b09c4fab8d4](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa194090e83b09c4fab8d4),
source `80194affee0b971bcd1e67ac45ed5ee3dd528547`, synchronized and reread
the allowlisted Apple draft fields at **20:43:54 UTC**. It aligned the existing
editable iOS version from **1.0 to 1.0.0** and saved the subtitle, privacy links,
categories, description, keywords, promotional text and support URL. The job ran
on `mac_mini_m2`; the [draft-listing receipt](release/apple-draft-listing-20261115.json)
records the verified operations separately from upload or submission.

[Signed upload build 6afa19ff90e83b09c4fab91c](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa19ff90e83b09c4fab91c),
source `494b070ecf423dd0440bb8b798c4c5ed826f080d`, passed all 49 native tests
and verified the App Store distribution signature for **version 1.0.0, build 1**.
Apple accepted the 25,194,089-byte IPA at **20:52:05 UTC** with delivery UUID
`26b909f8-e0ab-4d4e-81c0-beab571214d0`. Its downloaded bytes were independently
rehashed and its app plist checked against the build receipt. See the
[first signed upload evidence](release/ios-upload-build-1-20261115.json).
The subsequent [read-only Apple inventory](release/apple-inventory-before-subscription-20261115.json)
at **20:56:56 UTC** reported build 1 as **VALID** and not expired. At that check,
version 1.0.0 remained **Prepare for Submission** with no selected build, native
screenshot sets or subscription groups. Existing reviewer demo-account fields
were present, but the review contact fields were absent; field presence does not
verify that the credentials work. The inventory preserves those credentials and reports only
their presence.

[Branded upload build 6afa1c8190e83b09c4faba0a](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1c8190e83b09c4faba0a),
source `fbfde79df731dea5a2e7fc65ee9d4308aebe80dd`, passed all **49 native
tests** and verified App Store distribution signing for **version 1.0.0, build
2**. It replaces the default launch image with Esha's existing pink Korlix logo.
Apple accepted the **28,206,010-byte IPA at 21:02:06 UTC**, with delivery UUID
`50de7424-a350-42fb-9a9d-78eb17021ace`. The downloaded IPA's size and SHA-256
matched the Mac verification receipt; local inspection also confirmed the exact
bundle, version/build and compiled launch storyboard. The launch-screen pixels
were not rendered locally. See the immutable
[build 2 upload evidence](release/ios-upload-build-2-20261115.json).
The separate
[post-subscription inventory](release/apple-inventory-after-subscription-20261115.json),
[job 6afa1f8d90e83b09c4fabb26](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1f8d90e83b09c4fabb26)
from source `d62f76a8fc97eac812668e884ba0b57d7ba84ceb`, completed **19 GET
requests at 21:10:34 UTC**. It verified build 2
(`50de7424-a350-42fb-9a9d-78eb17021ace`) as **VALID** and not expired, and
reconfirmed that state for build 1. The build's non-exempt encryption field is
`null`, so that declaration remains unresolved. At this **21:10:34 UTC** check,
version **1.0.0** was **Prepare for Submission** with **no selected build**.
That historical selection observation is superseded by the successful selection
below. The immutable upload
receipt retains its original upload-only observations; this later inventory
establishes processing. None of these actions submitted Esha for review.

[Build-selection job 6afa207890e83b09c4fabb6a](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa207890e83b09c4fabb6a),
source `8adf46d7587ced117e725f88a404913c0d2eb61b`, completed at **21:14:24 UTC**.
The independently downloaded
[selection receipt](release/apple-build-selected-20261115.json) records
**`build_selected_and_read_back`**, **16 total requests**, **one PATCH** and
**zero retries**. Existing version `ab8553e4-56d5-40a9-aa7a-8cfb447fca72`
remains **Prepare for Submission**, now selecting exact build
`50de7424-a350-42fb-9a9d-78eb17021ace`, **1.0.0 (2)**, **VALID** and not
expired. The encryption field remains `null`; no declaration, review contact,
review submission or publication was changed by selection.

### Subscription draft preparation

Source `d62f76a8fc97eac812668e884ba0b57d7ba84ceb` publishes
`prepare_apple_subscription.py`, the exact
[subscription draft specification](release/apple-subscription-draft.json), and
separate manual plan/apply workflows. The default invocation makes **GET-only
Apple requests** and writes a local plan. `--apply-draft` can create only absent
components of Esha's **USA / USD 4.99 / ONE_MONTH / UPFRONT** subscription and
eligible **three-day free trial**, including USA-only availability when absent.
`UPFRONT` means payment in full for each one-month subscription period. Exact
existing components are reused; conflicts or ambiguous state stop the operation.
It performs no retries, review submission, publication, agreement changes or
backend/AI activation.

The implementation uses Apple's API 4.6 subscription/group versions and v2
localizations, with v1 product, price and offer resources. Independent schema
review found no contract mismatch. The
[live plan receipt](release/apple-subscription-plan-20261115.json) records
**two GET requests and no writes at 21:06:23 UTC**: the group/product were absent,
and the plan identified nine dependent creation stages.

[Subscription draft job 6afa1f0790e83b09c4fabaf9](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1f0790e83b09c4fabaf9)
completed at **21:08:56 UTC** from the same source. Its immutable
[prepared-draft receipt](release/apple-subscription-prepared-20261115.json)
records all **nine components created and read back**, **113 total requests**
and **zero POST retries**. Apple group **22583130** and product **6835214491**
(`com.korlixdeveloper.esha.monthly`) have the exact USA-only `UPFRONT`
availability, USD 4.99 price point and `THREE_DAYS` / `FREE_TRIAL` offer. New
territories are disabled. Agreement status and real-device purchases remain
unverified; this draft operation did not activate billing or AI, change
agreements, submit review or publish Esha. The
[subscription workflow guide](../../scripts/esha/README.md#apple-subscription-draft)
describes the exact scope and evidence requirements.

The **21:10:34 UTC** inventory independently reread the product's en-US
localization, **USD 4.99 / UPFRONT** price schedule and **FREE_TRIAL /
THREE_DAYS / one period** offer, starting **2026-11-15** with no end date.
Apple reports the product as **MISSING_METADATA**. Its subscription review
screenshot is absent, and the app has no iPhone/iPad screenshot sets. Review
contact fields are also absent. Existing reviewer credentials are preserved and
reported only as present; their validity has not been tested. Price-schedule
and offer readback do not verify StoreKit purchase behavior or trial eligibility.

The following manual workflows are committed, with no automatic triggers:

| Workflow | Purpose |
| --- | --- |
| `esha-ios-signing-setup` | Verify exact app/team/certificate identity and create or reuse only Esha's profile |
| `esha-apple-draft-listing` | Apply only the allowlisted draft text, categories, policy URLs and pending version alignment |
| `esha-ios-candidate` | Validate, compile and verify a signed candidate without publishing |
| `esha-ios-upload` | Validate, compile, verify and upload; both review-submission flags remain false |
| `esha-apple-release-inventory` | Read exact Esha release state; preserve reviewer credentials and report only their presence |
| `esha-apple-select-build` | Associate only validated build 2 with the editable version; verify readback without answering declarations or submitting review |
| `esha-apple-subscription-plan` | Read exact Esha subscription state and write a local change plan; no Apple writes |
| `esha-apple-subscription-draft` | Create only absent components of the exact USA monthly subscription draft and trial |

The initial draft-listing helper checkpoint passed 18 tests, and its combined
listing/signing helper checkpoint passed 32 tests. The latest release automation
suite with pinned CLI 0.69.0 passes **91 tests**, including **19 subscription**,
**19 inventory** and **15 build-selection** tests. Live subscription draft
creation is established by the separate prepared
receipt; the offline suite does not verify customer checkout. The
[listing guide](../../scripts/esha/APPLE_LISTING.md) and
[signing/build guide](../../scripts/esha/README.md) describe the guarded actions
and required artifacts. The allowlisted fields in
[store metadata](release/store-metadata.json) have been applied to the existing
Apple draft; this does not complete store declarations or publish the listing.

### Remaining release work

The economical AI option and its durable provider-attempt ledger are preserved
at commit `e9415b73c0dc36d4474c2a2e2c6abbda7d126acd`. Its model/allowance proposal
is inactive. The migration `20261115194040_esha_provider_attempt_budget.sql` has
not been applied and the new adapter has not been deployed. Keep Esha AI disabled
until the owner chooses the model and limits, the migration is applied and every
serving worker uses the guarded code.

Apple identity, profile setup, draft-listing synchronization, both signed IPA
uploads and both builds' **VALID** processing states are verified. **Build 2 is
selected and read back** for version 1.0.0, which remains **Prepare for
Submission**. Complete the subscription's missing
metadata and review screenshot, iPhone/iPad screenshots and review contact
fields. Verify agreements and store sandbox purchases against the prepared
subscription and eligible three-day offer. Real-device purchase, restore,
renewal, cancellation/refund, account-switch and reviewer access checks remain
necessary. Store privacy, age-rating, content-rights and export-compliance
declarations remain unfinished; the inventory does not infer questionnaire
completion from optional or nullable fields.

At **21:07:44 UTC**, the Codemagic Android keystore inventory confirmed that
**`ESHA_ANDROID_UPLOAD_KEY` is absent**; only two other product keystores were
visible. No Esha key was created/imported, its fingerprint value was not
inspected, and no signed Android build was started. The manual candidate
workflow now uses `mac_mini_m2`; the missing Esha key remains its prerequisite.
See the
[Android prerequisite receipt](release/android-signing-prerequisites-20261115.json).
Google Play access could not be verified because automatic approval review
rejected the redirect from `play.google.com` to `google.play/business/` as a
mismatched or untrusted origin. The Play app record, upload-key registration,
subscription/base plan/trial offer and signed release remain unverified.

Apple has accepted Esha's first two IPA uploads. Neither store has a verified
review submission or released Esha product. The
upload, test artifacts and live policy pages do not activate customer checkout
or native AI.
