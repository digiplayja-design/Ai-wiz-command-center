# Esha Apple draft listing synchronization

`sync_apple_listing.py` prepares or updates the existing **en-US** listing for
Esha by Korlix. The default invocation reads Apple and writes a local change
plan. `--apply-draft` applies only the field allowlist below. The manual Codemagic
workflow `esha-apple-draft-listing` runs that apply mode with the existing Apple
integration and `esha_release` environment group on **`mac_mini_m2`**.

**Verified checkpoint — November 15, 2026:**
[Codemagic job `6afa194090e83b09c4fab8d4`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa194090e83b09c4fab8d4)
successfully synchronized the existing draft and reread all four groups of
changes at **3:43 p.m. EST (20:43:54 UTC)**. Its exact source commit is
`80194affee0b971bcd1e67ac45ed5ee3dd528547`. The preserved
[Apple draft-listing receipt](../../apps/esha/release/apple-draft-listing-20261115.json)
records `draft_listing_synchronized`, matching planned, attempted and verified
operations, and metadata digest
`fbda1f99f03b3fd856e904a1324d66c966f48723478718ab146c3368042a4fe1`.

The verified updates were version **1.0 → 1.0.0**, subtitle and privacy links,
the **Lifestyle / Shopping** categories, and the en-US description, keywords,
promotional text and support URL. This completed a draft metadata operation;
the receipt records no upload, review submission, publication, declaration or
access change. Separate signed-upload jobs have since delivered **1.0.0 (1)**
and the branded **1.0.0 (2)** to Apple. The
[build 2 upload receipt](../../apps/esha/release/ios-upload-build-2-20261115.json)
records 49 passing native tests, verified App Store signing, independent artifact
checks and Apple's acceptance at **21:02:06 UTC**. A separate
[post-subscription inventory receipt](../../apps/esha/release/apple-inventory-after-subscription-20261115.json)
records **19 GET requests at 21:10:34 UTC** and verifies **both builds 1 and 2
as VALID and not expired**. At that historical check, version 1.0.0 was
**Prepare for Submission** with **no selected build**. The subsequent
[selection receipt](../../apps/esha/release/apple-build-selected-20261115.json)
confirms **build 2 selected and read back at 21:14:24 UTC**, with version 1.0.0
still **Prepare for Submission**. The build encryption field remains `null`,
so no export-compliance answer is established by either check.

Signing-setup build `6afa092a90e83b09c4fab31e` from commit
`be140a0c4bf713218e96f3d03e7631d97054700c` was labeled HTTP 401 by the helper,
but offline reproduction found a local CLI argument failure: CLI 0.69.0 rejects
zero retry limits, and its option name `--api-unauthorized-retries` was mistaken
for an HTTP authentication error. That result did not establish invalid Apple
credentials. CLI calls now use one attempt with no retry and distinguish local
parser failures from numeric Apple HTTP errors. The corrected signing job
`6afa106590e83b09c4fab58f` authenticated successfully, verified Esha's exact app
and signing identity, and created its App Store profile. Codemagic import as
`ESHA_APP_STORE_PROFILE` was then confirmed in the UI; see the
[signing and import evidence](../../apps/esha/release/ios-signing-20261115.json).
The successful draft job above independently confirms the existing integration
authenticated the listing reads and updates. No credential replacement was
needed. The helper does not retry authentication failures or change credentials
or permissions.

## Inputs and exact scope

The committed source of listing text is
`apps/esha/release/store-metadata.json`. The helper requires Apple app ID
**6835184869**, bundle **com.korlixdeveloper.esha**, SKU **ESHA_IOS_001**, and
`ESHA_APP_STORE_ID=6835184869` in the existing `esha_release` group.

| Resource | Fields the helper may update | Metadata source |
| --- | --- | --- |
| Existing en-US App Info localization | `subtitle`, `privacyPolicyUrl`, `privacyChoicesUrl` | `apple.subtitle`, `apple.privacy_url`, and that privacy URL plus `#deletion` |
| Pending App Info | `primaryCategory`, `secondaryCategory` | `apple.primary_category` (`LIFESTYLE`), `apple.secondary_category` (`SHOPPING`) |
| Pending iOS App Store version | `versionString` | `apple.version` and `app.source_version`, both exactly `1.0.0` |
| Existing en-US version localization | `description`, `keywords`, `promotionalText`, `supportUrl` | `apple.description`, `apple.keywords`, `apple.promotional_text`, `apple.support_url` |

The privacy fields are links to Esha's existing public policy and deletion
instructions. Those pages are verified live on Render deployment
`dep-dbt0l93l550s739n1p3g`, commit
`5e2a4086b7c4a58e8614abfa3625270b05def152`, completed on November 15 at
**2:41 p.m. EST (19:41:04 UTC)**. The
[live policy receipt](../../apps/esha/release/live-policy-check-20261115.json)
records subsequent HTTP 200 checks of `/esha/privacy` and `/esha/terms`,
whole-app membership wording, the three-day / US $4.99 offer and the deletion
anchor. The same check confirms that Apple and Google checkout and native AI
remain disabled, with store readiness and consultation allowances unset.

The helper has no operation for privacy questionnaire answers,
age ratings, content rights, export declarations, agreements, subscription
products, permissions, build uploads, review submissions, or publication. It
does not modify the app name, release type, selected build or What's New text.

## Discovery and guards

The helper reads the exact app record first, then the app's App Info and version
lists. It requires exactly one pending App Info and iOS version in
**Prepare for Submission**, plus existing en-US localizations. It reads all
pages and rejects missing data, duplicate resources, inconsistent totals,
foreign pagination URLs and redirects. It resolves the two requested category
IDs from Apple's category list and checks that they are top-level iOS categories.

Renaming version **1.0 → 1.0.0** is allowed only when the version has no selected
build and the app has no uploaded builds. Those checks run again immediately
before the rename. A version already named 1.0.0 can receive the allowed draft
text changes while it remains Prepare for Submission.

The initial draft synchronization and **1.0 → 1.0.0** transition completed
before the first IPA upload. Future runs retain these checks and can update the
allowlisted draft fields while the version remains editable. The separate
signed-build and upload workflows still verify Esha's profile and identity.

Every write rechecks identity and draft state and compares current target
fields with the values observed during planning. Another editor's changes stop
the operation. Each update is reread, and a final complete comparison must
match the prepared fields. These are separate Apple operations, not an atomic
transaction: if a later update fails, earlier verified updates may remain.

## Authentication and invocation

Use the existing **Codemagic Korlix AI** integration. No signing certificate or
profile is needed for listing metadata. Use the same pinned virtual environment
as the signing helper, or install `codemagic-cli-tools==0.69.0` into a separate
one. The helper resolves these existing integration variables using the pinned
CLI's argument types:

- `APP_STORE_CONNECT_KEY_IDENTIFIER`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Using the verified existing connection, the read-only invocation is:

```sh
"$CM_BUILD_DIR/.esha-ios-profile-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/sync_apple_listing.py"
```

To synchronize the approved draft fields:

```sh
"$CM_BUILD_DIR/.esha-ios-profile-tools/bin/python" \
  "$CM_BUILD_DIR/scripts/esha/sync_apple_listing.py" --apply-draft
```

The helper uses CLI 0.69.0's existing version and version-localization modify
commands. App Info subtitle/privacy links and category updates use the official
Apple API because that CLI version has no corresponding actions. The same
integration authenticates both paths. JWT disk caching and HTTP retries are
disabled. Raw responses, temporary CLI logs, environment values, private keys
and JWTs are not exported.

The single artifact is:

`apps/esha/artifacts/apple-listing/Esha-Apple-draft-listing-verification.json`

It records the source revision, canonical metadata digest, public resource IDs,
planned/attempted/verified field names and hashes, and a final status. A stopped
run reports partial progress; it never records synchronization success. Rerun
only after resolving the reported issue so discovery can establish Apple's
current state. A successful second run makes no redundant updates.

## Separate subscription draft workflow

Subscription preparation is implemented by **`prepare_apple_subscription.py`**
and the exact
[subscription specification](../../apps/esha/release/apple-subscription-draft.json),
published at source `d62f76a8fc97eac812668e884ba0b57d7ba84ceb`. It does not expand
the listing helper's field allowlist. The manual `esha-apple-subscription-plan`
workflow makes **GET-only** Apple requests and writes a local plan. Its
[live plan receipt](../../apps/esha/release/apple-subscription-plan-20261115.json)
records **two GET requests, no writes and nine dependent creation stages** at
**21:06:23 UTC**, with no preexisting Esha group/product.

The separate `esha-apple-subscription-draft` workflow invokes `--apply-draft`.
It can create only absent components for the exact Esha product
`com.korlixdeveloper.esha.monthly`: **USA, USD 4.99, ONE_MONTH, UPFRONT**, with
an eligible **THREE_DAYS / FREE_TRIAL** introductory offer. `UPFRONT` pays each
one-month period in full. USA-only availability may be created only when absent,
with `availableInNewTerritories: false`; existing availability is never replaced.
Exact existing components are reused, while conflicting or ambiguous state
stops the operation.

The [draft job `6afa1f0790e83b09c4fabaf9`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa1f0790e83b09c4fabaf9)
completed at **21:08:56 UTC** from the same source. Its immutable
[prepared-draft receipt](../../apps/esha/release/apple-subscription-prepared-20261115.json)
records all **nine components created and read back**, **113 total requests**
and **zero POST retries**. Apple group **22583130** and product **6835214491**
now match the exact USA monthly offer above. Agreement status and real-device
purchases remain unverified; billing and AI remain disabled.

The later inventory independently confirms the expected en-US localization,
USD 4.99 `UPFRONT` price schedule and `FREE_TRIAL` / `THREE_DAYS` / one-period
offer starting **2026-11-15**, with no end date. Apple still reports the product
as **MISSING_METADATA** and returns no subscription review screenshot. The app's
iPhone/iPad screenshot sets were also absent. Contact fields were absent in that
historical inventory; the verified contact update below supersedes that result.
Existing demo-account fields are present but untested; their values are preserved and
excluded from the receipt. Required owner declarations remain unfinished.
Price/offer readback does not verify customer purchase behavior or eligibility.

The subscription helper uses Apple API **4.6** subscription/group versions and
v2 localizations. Independent schema review found no contract mismatch. It makes
no HTTP or POST retries; an ambiguous POST is followed only by GET reconciliation
and a stop if its result cannot be established. It performs no review submission,
publication, agreement changes, backend activation or AI activation. The
[subscription guide](README.md#apple-subscription-draft) describes invocation,
all fixed settings, guarded stages and the sanitized plan/partial-progress
receipt. Review and purchase-readiness checks remain separate from creating a
draft.

## Separate draft build selection

Source `8adf46d7587ced117e725f88a404913c0d2eb61b` adds
`select_apple_build.py` and the manual `esha-apple-select-build` workflow. The
default CLI invocation produces a **GET-only plan**. Explicit `--apply-draft`
may link only validated, unexpired **build 2**
(`50de7424-a350-42fb-9a9d-78eb17021ace`) to the empty build relationship of the
existing editable iOS **1.0.0** draft. It verifies identity and the build's
pre-release version/platform, repeats the checks before apply, permits **one
PATCH maximum** and requires GET readback. A different selected build stops the
operation. It supplies no encryption answers, review contacts, review submission
or publication.

[Job `6afa207890e83b09c4fabb6a`](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa207890e83b09c4fabb6a)
completed at **21:14:24 UTC** from that source. The independently downloaded
[selection receipt](../../apps/esha/release/apple-build-selected-20261115.json)
records **`build_selected_and_read_back`**, **16 total requests**, **one PATCH**
and **zero retries**. Exact **1.0.0 (2)** is now selected, **VALID** and
unexpired; the existing version remains **Prepare for Submission** and its
build encryption field remains `null`. This supersedes the earlier inventory's
empty relationship without changing declarations, contacts, review or
publication. See the [build-selection guide](README.md#apple-draft-build-selection).

## Separate review-contact update

The manual `esha-apple-review-contact` workflow and
`prepare_apple_review_contact.py` were published at source
`2f287d515a041e66c4a9679ba2b62cde21b5cd96`.
[Job 6afa253f90e83b09c4fabd16](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6afa253f90e83b09c4fabd16?open-step=build-step-3)
completed at **21:34:42 UTC** with **10 requests, one PATCH and zero retries**.
The [contact receipt](../../apps/esha/release/apple-review-contact-updated-20261115.json)
verifies **Ricardo Bailey / support@korlixdeveloper.com / +16148942317** on the
existing version 1.0.0 review-details record, with every non-contact attribute
and the existing demo credentials preserved. Version 1.0.0 remains **Prepare for
Submission**; reviewer login is untested.

The helper defaults to a GET-only plan; explicit `--apply-draft` fills only empty
approved contact fields and stops conflicting existing values. It does not
replace credentials or notes, answer declarations, submit review or publish.
**18 focused contact tests passed**. This separate operation leaves the listing
helper's original allowlist unchanged.

## Fixture validation

```sh
python3 -m unittest discover -s scripts/esha/tests -p 'test_sync_apple_listing.py' -v
```

The fixtures do not call Apple, load credentials or execute a real CLI. They
cover identity/state/version/build guards, locale/category selection,
concurrent edits, strict pagination and URL boundaries, payload allowlists,
authentication failure without retries, partial progress and idempotent reuse.
The release automation checkpoint at `8adf46d` with pinned CLI 0.69.0 passed **91 offline
tests**, including **19 subscription**, **19 inventory** and **15 build-selection**
tests. Live draft creation is established
by the separate prepared-draft receipt; the fixtures do not verify customer checkout.

## Primary references

- [Apple App Infos](https://developer.apple.com/documentation/appstoreconnectapi/app-infos)
- [Apple: modify an App Info](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appinfos-_id_)
- [Apple: list app categories](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appcategories)
- [Apple: App Info localization update fields](https://developer.apple.com/documentation/appstoreconnectapi/appinfolocalizationupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [Apple: version localization update fields](https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionlocalizationupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [Codemagic CLI 0.69.0: version modify](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/docs/app-store-connect/app-store-versions/modify.md)
- [Codemagic CLI 0.69.0: version localization modify](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/docs/app-store-connect/app-store-version-localizations/modify.md)
- [Codemagic integration environment mapping](https://docs.codemagic.io/partials/alternative-code-signing-methods-ios/)
