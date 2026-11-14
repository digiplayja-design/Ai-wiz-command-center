#!/usr/bin/env python3
"""Complete only the reviewed COPY Box Apple age declaration.

Manual CI action using the existing Codemagic-managed Apple integration. The
CopyBox output boundary was verified live at backend commit
a8a416fa77eac0a25236e72cc3828f1a5ccf96cf before this candidate was prepared.
No app submission, release type, build, price, privacy or credential mutation
exists here. Never log raw responses, auth material or external error messages.

Current ratings come from territoryAgeRatings (Apple OpenAPI 4.6), not the
deprecated AppInfo age-rating fields. They are displayed ratings; the API does
not separately expose an unoverridden base calculation.
"""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import parse_qs, urlencode, urlsplit

from read_copybox_apple_status import AppleReadOnly, AuditError, resource, related_id

APP_ID = "6830765098"
BUNDLE_ID = "com.korlixdeveloper.copybox"
VERSION_ID = "3ae65f97-f9c5-498d-80b6-8f6d208615d6"
TARGET_VERSION = "1.0.0"
APP_INFO_ID = "02fecba7-6986-4f9b-b400-749d9e36f499"
DECLARATION_ID = "02fecba7-6986-4f9b-b400-749d9e36f499"
ORIGIN = "https://api.appstoreconnect.apple.com"
DECLARATION_READ = f"/v1/appInfos/{APP_INFO_ID}/ageRatingDeclaration"
DECLARATION_WRITE = f"/v1/ageRatingDeclarations/{DECLARATION_ID}"
TERRITORY_PATH = f"/v1/appInfos/{APP_INFO_ID}/territoryAgeRatings"
OUTPUT = Path("artifacts/copybox-apple-age-completion.json")
MAX_RESPONSE_BYTES = 2_000_000
MAX_RATING_PAGES = 3
RATING_READ_ATTEMPTS = 3

# These are the reviewed 24 answers, not configurable CI inputs.
REVIEWED_ATTRIBUTES = {
    "advertising": False,
    "alcoholTobaccoOrDrugUseOrReferences": "INFREQUENT",
    "contests": "NONE",
    "gambling": False,
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "INFREQUENT",
    "healthOrWellnessTopics": True,
    "lootBox": False,
    "medicalOrTreatmentInformation": "INFREQUENT",
    "messagingAndChat": False,
    "parentalControls": False,
    "profanityOrCrudeHumor": "INFREQUENT",
    "ageAssurance": True,
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "INFREQUENT",
    "socialMedia": False,
    "socialMediaAgeRestricted": False,
    "horrorOrFearThemes": "INFREQUENT",
    "matureOrSuggestiveThemes": "INFREQUENT",
    "unrestrictedWebAccess": False,
    "userGeneratedContent": False,
    "violenceCartoonOrFantasy": "INFREQUENT",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "violenceRealistic": "INFREQUENT",
}
FREQUENCIES = {"NONE", "INFREQUENT", "FREQUENT", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE"}
OPTION_ENUMS = {
    "kidsAgeBand": {"FIVE_AND_UNDER", "SIX_TO_EIGHT", "NINE_TO_ELEVEN"},
    "ageRatingOverride": {"NONE", "NINE_PLUS", "THIRTEEN_PLUS", "SIXTEEN_PLUS", "SEVENTEEN_PLUS", "UNRATED"},
    "ageRatingOverrideV2": {"NONE", "NINE_PLUS", "THIRTEEN_PLUS", "SIXTEEN_PLUS", "EIGHTEEN_PLUS", "UNRATED"},
    "koreaAgeRatingOverride": {"NONE", "ALL", "TWELVE_PLUS", "FIFTEEN_PLUS", "NINETEEN_PLUS"},
}
NUMBER_WORDS = (
    "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE",
    "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN",
    "SEVENTEEN", "EIGHTEEN", "NINETEEN", "TWENTY", "TWENTY_ONE",
)
RATING_AGES = {"L": 0, "ALL": 0, "ZERO_ZERO": 0,
               **{word + "_PLUS": i for i, word in enumerate(NUMBER_WORDS, 1)}}
PRESERVED_OPTIONS = ("kidsAgeBand", "koreaAgeRatingOverride",
                     "gracRatingClassificationNumber", "developerAgeRatingInfoUrl")


class CompletionStop(Exception):
    """Fixed diagnostic codes and trusted field names only."""

    def __init__(self, code, field=None):
        super().__init__(code)
        self.code = code
        self.field = field


def require(condition, code, field=None):
    if not condition:
        raise CompletionStop(code, field)


def new_report():
    return {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "appId": APP_ID, "bundleId": BUNDLE_ID, "versionId": VERSION_ID,
        "targetVersion": TARGET_VERSION, "appInfoId": APP_INFO_ID,
        "declarationId": DECLARATION_ID, "success": False,
        "scopeVerified": False, "phase": "starting", "failureCode": None,
        "failureField": None, "requestCount": 0, "patchAttempts": [],
        "mutationOutcomeUnknown": False, "overrideDecision": None,
        "globalComparisonTerritory": "USA",
        "ratingSemantics": "Displayed territory ratings; separate base calculation not exposed",
        "rootVerifiedBackendBoundaryCommit": "a8a416fa77eac0a25236e72cc3828f1a5ccf96cf",
        "submissionAttempted": False,
    }


def declaration_attributes(payload):
    row = payload.get("data")
    attrs = resource(row, "ageRatingDeclarations")
    require(row["id"] == DECLARATION_ID, "declaration_identity_mismatch")
    for key, expected in REVIEWED_ATTRIBUTES.items():
        require(key in attrs, "declaration_field_missing", key)
        value = attrs[key]
        if value is None:
            continue
        if isinstance(expected, bool):
            require(type(value) is bool, "declaration_boolean_invalid", key)
        else:
            require(type(value) is str and value in FREQUENCIES,
                    "declaration_enum_unknown", key)
    require("ageRatingOverrideV2" in attrs, "override_field_missing", "ageRatingOverrideV2")
    for key, choices in OPTION_ENUMS.items():
        value = attrs.get(key)
        require(value is None or (type(value) is str and value in choices),
                "declaration_enum_unknown", key)
    require(attrs.get("kidsAgeBand") is None, "unexpected_kids_category")
    return attrs


def declaration_snapshot(attrs):
    return {
        "attributes": {key: attrs[key] for key in REVIEWED_ATTRIBUTES},
        "options": {key: attrs.get(key) for key in OPTION_ENUMS},
        "gracRatingClassificationNumberPresent": bool(attrs.get("gracRatingClassificationNumber")),
        "developerAgeRatingInfoUrlPresent": bool(attrs.get("developerAgeRatingInfoUrl")),
    }


def attributes_match(attrs, expected):
    return all(key in attrs and type(attrs[key]) is type(value) and attrs[key] == value
               for key, value in expected.items())


def preserve_options(before, after, include_override=True):
    keys = PRESERVED_OPTIONS + (("ageRatingOverrideV2", "ageRatingOverride") if include_override else ())
    for key in keys:
        require(before.get(key) == after.get(key), "unrequested_option_changed", key)


class AppleAgeCompletion:
    def __init__(self, session, auth_headers, report):
        self.session, self.auth_headers, self.report = session, auth_headers, report
        self.read = AppleReadOnly(session, auth_headers)
        self.scope_verified = False
        self.declaration_read = False
        self.override_allowed = False
        self.used_patches = set()
        self.patch_count = 0

    def verify_scope(self):
        self.scope_verified = False
        app = self.read.verify_app()
        require(app["id"] == APP_ID and app["bundleId"] == BUNDLE_ID, "app_identity_mismatch")
        versions, more = self.read.app_list("appStoreVersions")
        require(not more, "version_scope_incomplete")
        targets = [row for row in versions if row.get("id") == VERSION_ID]
        require(len(targets) == 1, "version_identity_mismatch")
        attrs = resource(targets[0], "appStoreVersions")
        require(attrs.get("platform") == "IOS" and attrs.get("versionString") == TARGET_VERSION,
                "version_identity_mismatch")
        require(attrs.get("appVersionState", attrs.get("appStoreState")) == "PREPARE_FOR_SUBMISSION",
                "version_not_in_preparation")
        infos, more = self.read.app_list("appInfos")
        require(not more, "app_info_scope_incomplete")
        targets = [row for row in infos if row.get("id") == APP_INFO_ID]
        require(len(targets) == 1, "app_info_identity_mismatch")
        attrs = resource(targets[0], "appInfos")
        require(attrs.get("state", attrs.get("appStoreState")) == "PREPARE_FOR_SUBMISSION",
                "app_info_not_in_preparation")
        linked = related_id(targets[0], "ageRatingDeclaration", "ageRatingDeclarations")
        require(linked in (None, DECLARATION_ID), "declaration_relationship_mismatch")
        self.scope_verified = True
        self.report["scopeVerified"] = True

    def declaration(self):
        require(self.scope_verified, "scope_not_verified")
        attrs = declaration_attributes(self.read.get(DECLARATION_READ))
        self.declaration_read = True
        return attrs

    def ratings(self):
        require(self.scope_verified, "scope_not_verified")
        path = TERRITORY_PATH + "?limit=200&include=territory"
        seen, ratings = set(), {}
        for _ in range(MAX_RATING_PAGES):
            require(path not in seen, "rating_pagination_cycle")
            seen.add(path)
            # Only locally constructed routes for this verified appInfo are added.
            self.read.allowed.add(path)
            payload = self.read.get(path)
            require(isinstance(payload["data"], list) and len(payload["data"]) <= 200,
                    "rating_list_invalid")
            for row in payload["data"]:
                require(isinstance(row, dict) and row.get("type") == "territoryAgeRatings",
                        "rating_resource_invalid")
                attrs = row.get("attributes")
                require(isinstance(attrs, dict) and "appStoreAgeRating" in attrs,
                        "rating_field_missing", "appStoreAgeRating")
                link = row.get("relationships", {}).get("territory", {}).get("data")
                require(isinstance(link, dict) and link.get("type") == "territories",
                        "rating_territory_missing")
                territory = link.get("id")
                require(type(territory) is str and re.fullmatch(r"[A-Z]{3}", territory),
                        "rating_territory_invalid")
                require(territory not in ratings, "rating_territory_duplicate")
                value = attrs["appStoreAgeRating"]
                require(value is None or (type(value) is str and
                        (value in RATING_AGES or value == "UNRATED")),
                        "rating_enum_unknown", "appStoreAgeRating")
                ratings[territory] = value
            next_url = payload.get("links", {}).get("next")
            if not next_url:
                return dict(sorted(ratings.items()))
            require(type(next_url) is str and len(next_url) <= 4096,
                    "rating_pagination_outside_scope")
            parsed = urlsplit(next_url)
            require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                    and parsed.path == TERRITORY_PATH and not parsed.fragment,
                    "rating_pagination_outside_scope")
            try:
                query = parse_qs(parsed.query, strict_parsing=True, max_num_fields=3)
            except ValueError:
                raise CompletionStop("rating_pagination_outside_scope") from None
            require(set(query) == {"limit", "include", "cursor"}
                    and query["limit"] == ["200"] and query["include"] == ["territory"]
                    and len(query["cursor"]) == 1, "rating_pagination_outside_scope")
            cursor = query["cursor"][0]
            require(0 < len(cursor) <= 2048 and re.fullmatch(r"[A-Za-z0-9_+/=.-]+", cursor),
                    "rating_pagination_outside_scope")
            path = TERRITORY_PATH + "?" + urlencode({"limit": "200", "include": "territory", "cursor": cursor})
        raise CompletionStop("rating_pagination_limit")

    def patch(self, kind, attrs):
        require(self.scope_verified and self.declaration_read, "mutation_before_scope_check")
        require(kind in {"descriptors", "override"} and kind not in self.used_patches,
                "mutation_scope_violation")
        expected = REVIEWED_ATTRIBUTES if kind == "descriptors" else {"ageRatingOverrideV2": "SIXTEEN_PLUS"}
        require(type(attrs) is dict and set(attrs) == set(expected)
                and attributes_match(attrs, expected), "mutation_attributes_not_reviewed")
        require(kind != "override" or self.override_allowed, "override_not_justified")
        self.used_patches.add(kind)  # No retry after an ambiguous write.
        self.patch_count += 1
        attempt = {"kind": kind, "httpStatus": None, "responseConfirmed": False}
        self.report["patchAttempts"].append(attempt)
        self.report["mutationOutcomeUnknown"] = True
        body = {"data": {"type": "ageRatingDeclarations", "id": DECLARATION_ID,
                         "attributes": dict(attrs)}}
        try:
            response = self.session.request(
                "PATCH", ORIGIN + DECLARATION_WRITE, json=body,
                headers=self.auth_headers(), timeout=30, allow_redirects=False,
            )
        except Exception:
            raise CompletionStop("apple_patch_transport_unconfirmed") from None
        status = response.status_code
        require(type(status) is int and 100 <= status <= 599, "apple_patch_status_invalid")
        attempt["httpStatus"] = status
        require(status == 200, "apple_patch_rejected")
        require(len(response.content) <= MAX_RESPONSE_BYTES, "apple_patch_response_oversized")
        try:
            payload = response.json()
        except Exception:
            raise CompletionStop("apple_patch_response_invalid") from None
        require(isinstance(payload, dict), "apple_patch_response_invalid")
        returned = declaration_attributes(payload)
        require(attributes_match(returned, attrs), "apple_patch_response_mismatch")
        attempt["responseConfirmed"] = True
        self.report["mutationOutcomeUnknown"] = False


def complete_ratings(api, pause, minimum=None, previous=None):
    for attempt in range(RATING_READ_ATTEMPTS):
        ratings = api.ratings()
        require("UNRATED" not in ratings.values(), "unrated_not_store_eligible")
        complete = bool(ratings) and "USA" in ratings and all(value is not None for value in ratings.values())
        if complete:
            sufficient = minimum is None or RATING_AGES[ratings["USA"]] >= minimum
            if previous is not None:
                sufficient = sufficient and set(ratings) == set(previous) and all(
                    RATING_AGES[ratings[key]] >= RATING_AGES[value]
                    for key, value in previous.items() if key in ratings)
            if sufficient:
                return ratings
        if attempt + 1 < RATING_READ_ATTEMPTS:
            pause(1)
    raise CompletionStop("rating_readback_unconfirmed", "appStoreAgeRating")


def run(session, auth_headers, pause=time.sleep):
    report = new_report()
    api = AppleAgeCompletion(session, auth_headers, report)
    try:
        report["phase"] = "verify_identity"
        api.verify_scope()
        before = api.declaration()
        report["beforeDeclaration"] = declaration_snapshot(before)
        report["beforeTerritoryRatings"] = api.ratings()
        require("UNRATED" not in report["beforeTerritoryRatings"].values()
                and before.get("ageRatingOverrideV2") != "UNRATED", "unrated_preserved_no_mutation")

        report["phase"] = "apply_reviewed_descriptors"
        if not attributes_match(before, REVIEWED_ATTRIBUTES):
            api.patch("descriptors", dict(REVIEWED_ATTRIBUTES))
        after = api.declaration()
        require(attributes_match(after, REVIEWED_ATTRIBUTES), "descriptor_readback_mismatch")
        preserve_options(before, after)
        report["descriptorsVerified"] = True
        report["afterDescriptors"] = declaration_snapshot(after)

        report["phase"] = "read_computed_territory_ratings"
        ratings = complete_ratings(api, pause)
        report["afterDescriptorTerritoryRatings"] = ratings
        current_override = after.get("ageRatingOverrideV2")
        global_age = RATING_AGES[ratings["USA"]]
        override_age = 0 if current_override in (None, "NONE") else RATING_AGES[current_override]

        if override_age >= 16:
            require(global_age >= override_age, "existing_override_not_reflected")
            report["overrideDecision"] = "preserved_existing_override"
        elif global_age >= 16:
            report["overrideDecision"] = "preserved_computed_rating_at_or_above_sixteen"
        else:
            report["phase"] = "apply_minimum_age_override"
            # Recheck the app/version scope and current declaration immediately
            # before the second narrowly scoped write.
            api.verify_scope()
            latest = api.declaration()
            require(attributes_match(latest, REVIEWED_ATTRIBUTES), "declaration_changed_during_run")
            preserve_options(after, latest)
            ratings = complete_ratings(api, pause)
            if RATING_AGES[ratings["USA"]] >= 16:
                after = latest
                report["overrideDecision"] = "preserved_computed_rating_at_or_above_sixteen"
            else:
                api.override_allowed = True
                api.patch("override", {"ageRatingOverrideV2": "SIXTEEN_PLUS"})
                after = api.declaration()
                require(attributes_match(after, REVIEWED_ATTRIBUTES)
                        and after.get("ageRatingOverrideV2") == "SIXTEEN_PLUS",
                        "override_readback_mismatch")
                preserve_options(latest, after, include_override=False)
                ratings = complete_ratings(api, pause, minimum=16, previous=ratings)
                report["overrideDecision"] = "raised_lower_displayed_global_rating_to_sixteen"

        report["finalDeclaration"] = declaration_snapshot(after)
        report["finalTerritoryRatings"] = ratings
        report["phase"] = "complete"
        report["success"] = True
    except CompletionStop as error:
        report["failureCode"], report["failureField"] = error.code, error.field
    except AuditError:
        report["failureCode"] = "apple_scoped_get_or_identity_check_failed"
    except Exception:
        report["failureCode"] = "completion_unconfirmed"
    report["requestCount"] = api.read.request_count + api.patch_count
    return report


def main():
    if sys.argv[1:] != ["--apply-reviewed"]:
        print("Use --apply-reviewed for the reviewed COPY Box age-only CI action.", file=sys.stderr)
        return 2
    report = new_report()
    try:
        from codemagic.apple.app_store_connect import AppStoreConnectApiClient
        from codemagic.tools.app_store_connect.arguments import Types
        import requests
        client = AppStoreConnectApiClient(
            key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
            issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
            private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
            log_requests=False, enable_jwt_cache=False,
        )
        with requests.Session() as session:
            session.trust_env = False
            report = run(session, client.generate_auth_headers)
    except Exception:
        report["failureCode"] = "managed_apple_access_unavailable"
    try:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception:
        print("COPY Box age completion stopped: evidence could not be saved.", file=sys.stderr)
        return 1
    print(json.dumps({key: report[key] for key in
                      ("appId", "success", "phase", "failureCode", "requestCount", "overrideDecision")}
                     | {"report": str(OUTPUT)}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
