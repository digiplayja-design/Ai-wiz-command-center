# Esha Apple draft listing synchronization

`sync_apple_listing.py` prepares or updates the existing **en-US** listing for
Esha by Korlix. The default invocation reads Apple and writes a local change
plan. `--apply-draft` applies only the field allowlist below. No Codemagic
workflow has been added for this helper yet.

The existing Apple integration returned HTTP 401 in signing-setup build
`6afa092a90e83b09c4fab31e` from commit
`be140a0c4bf713218e96f3d03e7631d97054700c`. This helper is prepared for use after
that authentication issue is resolved. It has not been run against Apple.
It does not retry authentication failures or change credentials or permissions.

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
instructions. The helper has no operation for privacy questionnaire answers,
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

After the connection is working, the read-only invocation is:

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

## Fixture validation

```sh
python3 -m unittest discover -s scripts/esha/tests -p 'test_sync_apple_listing.py' -v
```

The fixtures do not call Apple, load credentials or execute a real CLI. They
cover identity/state/version/build guards, locale/category selection,
concurrent edits, strict pagination and URL boundaries, payload allowlists,
authentication failure without retries, partial progress and idempotent reuse.

## Primary references

- [Apple App Infos](https://developer.apple.com/documentation/appstoreconnectapi/app-infos)
- [Apple: modify an App Info](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appinfos-_id_)
- [Apple: list app categories](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appcategories)
- [Apple: App Info localization update fields](https://developer.apple.com/documentation/appstoreconnectapi/appinfolocalizationupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [Apple: version localization update fields](https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionlocalizationupdaterequest/data-data.dictionary/attributes-data.dictionary)
- [Codemagic CLI 0.69.0: version modify](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/docs/app-store-connect/app-store-versions/modify.md)
- [Codemagic CLI 0.69.0: version localization modify](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/docs/app-store-connect/app-store-version-localizations/modify.md)
- [Codemagic integration environment mapping](https://docs.codemagic.io/partials/alternative-code-signing-methods-ios/)
