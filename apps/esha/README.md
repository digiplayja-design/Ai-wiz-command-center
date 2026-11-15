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

**The app source and test builds are prepared. There is no signed iPhone IPA,
store upload or review submission yet.** The current signing attempt stopped
because the saved `Codemagic Korlix AI` Apple integration returned HTTP 401.

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
[build-verification.json](release/build-verification.json). Later commits add
release helpers, inactive backend preparation and checkpoint documentation; they
do not imply a newer compiled native artifact.

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

### Apple identity and signing blocker

The user-provided App Information screenshot confirms the created **Esha by
Korlix** record: bundle `com.korlixdeveloper.esha`, SKU `ESHA_IOS_001`, numeric
Apple ID `6835184869`, with iOS version `1.0` in **Prepare for Submission**. The
Apple Developer screenshot shows team `FJKJ9MUDZ4`. These remain screenshot
identity evidence until the Apple API can authenticate.

The `esha_release` Codemagic environment group now contains the app and team IDs.
The existing production signing certificate reference is `KORLIX_APP_STORE_CERT`;
no Esha App Store provisioning profile was found in the saved inventory.

[Signing setup build 6afa092a90e83b09c4fab31e](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa092a90e83b09c4fab31e)
passed the workflow's configuration/import stages, then stopped at its first
Apple inventory lookup with **HTTP 401**. The helper's credential-variable
mapping matches pinned Codemagic CLI 0.69.0 and the documented integration.
No Esha profile was created, no Apple identity was verified by API and no IPA was
built or uploaded. The saved Apple integration must be repaired through
[Codemagic integration settings](https://codemagic.io/teams/6a32158af7d33bf04e05cc9d)
before retrying that job.

The following manual workflows are committed, with no automatic triggers:

| Workflow | Purpose |
| --- | --- |
| `esha-ios-signing-setup` | Verify exact app/team/certificate identity and create or reuse only Esha's profile |
| `esha-apple-draft-listing` | Apply only the allowlisted draft text, categories, policy URLs and pending version alignment |
| `esha-ios-candidate` | Validate, compile and verify a signed candidate without publishing |
| `esha-ios-upload` | Validate, compile, verify and upload; both review-submission flags remain false |

The draft-listing helper passed 18 tests; combined listing/signing helper tests
passed 32 tests. The two new manual workflow structures were checked locally;
they have not been run against Apple. The [listing guide](../../scripts/esha/APPLE_LISTING.md)
and [signing/build guide](../../scripts/esha/README.md) record the guarded actions
and required artifacts. Prepared [store metadata](release/store-metadata.json)
has not yet been applied to the live listing.

### Remaining release work

The economical AI option and its durable provider-attempt ledger are preserved
at commit `e9415b73c0dc36d4474c2a2e2c6abbda7d126acd`. Its model/allowance proposal
is inactive. The migration `20261115194040_esha_provider_attempt_budget.sql` has
not been applied and the new adapter has not been deployed. Keep Esha AI disabled
until the owner chooses the model and limits, the migration is applied and every
serving worker uses the guarded code.

After Apple authentication is repaired, verify the exact app identity, create
Esha's profile, apply the pending listing fields, configure the subscription and
eligible three-day offer, and produce/upload the verified IPA. Real-device
purchase, restore, renewal, cancellation/refund, account-switch and reviewer
access checks remain necessary. Store privacy, age-rating and content-rights
forms and native screenshots remain unfinished.

Google Play account access, app record, subscription/base plan/trial offer and
release signing also remain unverified. Neither store has a verified Esha upload
or review submission. These test artifacts and the live policy pages do not
establish a released store product.
