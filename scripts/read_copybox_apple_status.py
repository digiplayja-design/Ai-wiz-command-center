#!/usr/bin/env python3
"""Read a narrowly scoped, sanitized COPY Box Apple release snapshot.

Uses the existing Codemagic-managed App Store Connect API integration. No POST,
PATCH, DELETE, upload, tester invitation, auth change, or review submission exists
in this program. The API's private review values stay in memory and become only
presence booleans. Never write raw responses, tokens, private keys, contacts,
reviewer credentials, notes, or tester identities to stdout or artifacts.

Known source baseline: PR #42 head 59fb45c3dd7a85f9e2576930b9f2bdb5360019be.
API docs: https://developer.apple.com/documentation/appstoreconnectapi
This is an incomplete readiness audit, not Apple's submission validator.
"""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys

APP_ID = "6830765098"
BUNDLE_ID = "com.korlixdeveloper.copybox"
TARGET_VERSION = "1.0.0"
ORIGIN = "https://api.appstoreconnect.apple.com"
APP_PATH = f"/v1/apps/{APP_ID}"
OUTPUT = Path("artifacts/copybox-apple-status.json")
MAX_RESPONSE_BYTES = 2_000_000
MAX_CHILD_DETAILS = 10

ROOT_RELATIONS = {
    "appStoreVersions", "appInfos", "builds", "betaGroups", "reviewSubmissions",
}
CHILD_RELATIONS = {
    "appStoreVersions": {"appStoreReviewDetail", "relationships/build"},
    "appInfos": {"ageRatingDeclaration"},
    "builds": {"buildBetaDetail", "preReleaseVersion"},
    "betaGroups": {"relationships/betaTesters", "relationships/builds"},
}
AGE_DESCRIPTORS = (
    "advertising", "alcoholTobaccoOrDrugUseOrReferences", "contests",
    "gambling", "gamblingSimulated", "gunsOrOtherWeapons", "healthOrWellnessTopics",
    "lootBox", "medicalOrTreatmentInformation", "messagingAndChat",
    "parentalControls", "profanityOrCrudeHumor", "ageAssurance",
    "sexualContentGraphicAndNudity", "sexualContentOrNudity", "socialMedia",
    "socialMediaAgeRestricted", "horrorOrFearThemes", "matureOrSuggestiveThemes",
    "unrestrictedWebAccess", "userGeneratedContent", "violenceCartoonOrFantasy",
    "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
)
AGE_OPTIONS = (
    "kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
)


class AuditError(RuntimeError):
    """Only fixed, non-sensitive diagnostic strings may be included."""


def require(condition, message):
    if not condition:
        raise AuditError(message)


def ident(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9-]{1,128}", value),
            "Invalid Apple resource identifier")
    return value


def enum(value):
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, str) and re.fullmatch(r"[A-Z][A-Z0-9_]{0,79}", value):
        return value
    raise AuditError("Unexpected Apple status or declaration value")


def version(value):
    require(value is None or (isinstance(value, str)
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,4}", value)),
            "Unexpected Apple version value")
    return value


def timestamp(value):
    if value is None:
        return None
    require(isinstance(value, str) and len(value) <= 40, "Unexpected Apple timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        raise AuditError("Unexpected Apple timestamp") from None
    require(parsed.tzinfo is not None, "Apple timestamp lacks a timezone")
    return parsed.isoformat()


def present(value):
    return isinstance(value, str) and bool(value.strip())


def resource(item, expected_type):
    require(isinstance(item, dict) and item.get("type") == expected_type,
            "Unexpected Apple resource type")
    ident(item.get("id"))
    attrs = item.get("attributes", {})
    require(isinstance(attrs, dict), "Invalid Apple resource attributes")
    return attrs


def related_id(item, relation, expected_type):
    data = item.get("relationships", {}).get(relation, {}).get("data")
    if data is None:
        return None
    require(isinstance(data, dict) and data.get("type") == expected_type,
            "Unexpected Apple relationship type")
    return ident(data.get("id"))


class AppleReadOnly:
    def __init__(self, session, auth_headers):
        self.session = session
        self.auth_headers = auth_headers
        self.allowed = {APP_PATH}
        self.verified_app = False
        self.registered = {kind: set() for kind in CHILD_RELATIONS}
        self.request_count = 0

    def verify_app(self):
        result = self.get(APP_PATH)
        app = result["data"]
        attrs = resource(app, "apps")
        require(app["id"] == APP_ID and attrs.get("bundleId") == BUNDLE_ID,
                "COPY Box Apple app identity did not match")
        self.verified_app = True
        self.allowed.update(f"{APP_PATH}/{relation}" for relation in ROOT_RELATIONS)
        return {"id": APP_ID, "bundleId": BUNDLE_ID,
                "contentRightsDeclaration": enum(attrs.get("contentRightsDeclaration")),
                "primaryLocale": attrs.get("primaryLocale") if attrs.get("primaryLocale") == "en-US" else "other_or_unset"}

    def register_from_app_list(self, kind, item):
        require(self.verified_app and kind in CHILD_RELATIONS,
                "App scope must be verified before related access")
        resource(item, kind)
        app_id = related_id(item, "app", "apps")
        require(app_id in (None, APP_ID), "Related resource belongs to another app")
        item_id = ident(item["id"])
        self.registered[kind].add(item_id)
        self.allowed.update(f"/v1/{kind}/{item_id}/{suffix}"
                            for suffix in CHILD_RELATIONS[kind])

    def get(self, path, optional=False):
        # Exact registered relative routes only; no caller URL, arbitrary query,
        # redirect, or server-provided pagination URL is ever followed.
        require(isinstance(path, str) and path in self.allowed,
                "Apple endpoint is outside this read-only app audit")
        try:
            response = self.session.request(
                "GET", ORIGIN + path, headers=self.auth_headers(),
                timeout=30, allow_redirects=False,
            )
        except Exception:
            raise AuditError("Apple GET transport failed") from None
        self.request_count += 1
        if optional and response.status_code == 404:
            return None
        require(response.status_code == 200,
                f"Apple GET failed: HTTP {int(response.status_code)}")
        require(len(response.content) <= MAX_RESPONSE_BYTES, "Apple response exceeded size limit")
        try:
            payload = response.json()
        except Exception:
            raise AuditError("Apple returned invalid JSON") from None
        require(isinstance(payload, dict) and "data" in payload,
                "Apple returned incomplete data")
        return payload

    def app_list(self, relation):
        require(relation in ROOT_RELATIONS, "Unexpected app relationship")
        payload = self.get(f"{APP_PATH}/{relation}")
        require(isinstance(payload["data"], list) and len(payload["data"]) <= 200,
                "Invalid or oversized Apple resource list")
        for row in payload["data"]:
            resource(row, relation)
            if relation in CHILD_RELATIONS:
                self.register_from_app_list(relation, row)
        return payload["data"], bool(payload.get("links", {}).get("next"))


def review_presence(payload):
    if payload is None or payload.get("data") is None:
        return {"exists": False}
    attrs = resource(payload["data"], "appStoreReviewDetails")
    result = {"exists": True, "id": ident(payload["data"]["id"]),
              "demoAccountRequired": enum(attrs.get("demoAccountRequired"))}
    for key in ("demoAccountName", "demoAccountPassword", "contactFirstName",
                "contactLastName", "contactPhone", "contactEmail", "notes"):
        # Keep only presence. Never emit values, prefixes, hashes or lengths.
        result[key + "Present"] = present(attrs.get(key))
    return result


def linkage_summary(payload, expected_type):
    if payload is None:
        return {"available": False}
    require(isinstance(payload["data"], list) and len(payload["data"]) <= 200,
            "Invalid Apple linkage list")
    for row in payload["data"]:
        resource(row, expected_type)
    # Tester IDs are neither persisted nor returned.
    return {"available": True, "countOnFirstPage": len(payload["data"]),
            "hasMore": bool(payload.get("links", {}).get("next"))}


def run(session, auth_headers):
    api = AppleReadOnly(session, auth_headers)
    app = api.verify_app()
    findings = []
    completeness = {}

    rows, completeness["appStoreVersionsHasMore"] = api.app_list("appStoreVersions")
    versions = []
    targets = []
    for row in rows:
        attrs = resource(row, "appStoreVersions")
        summary = {"id": row["id"], "platform": enum(attrs.get("platform")),
                   "versionString": version(attrs.get("versionString")),
                   "appStoreState": enum(attrs.get("appStoreState")),
                   "appVersionState": enum(attrs.get("appVersionState")),
                   "releaseType": enum(attrs.get("releaseType")),
                   "copyrightPresent": present(attrs.get("copyright"))}
        versions.append(summary)
        if attrs.get("platform") == "IOS" and attrs.get("versionString") == TARGET_VERSION:
            targets.append((row, summary))
    require(len(targets) <= 1, "Multiple target iOS versions need manual inspection")
    if not targets:
        findings.append("target_ios_version_not_observed_on_first_page")
    for row, summary in targets:
        detail = api.get(f"/v1/appStoreVersions/{row['id']}/appStoreReviewDetail", optional=True)
        summary["reviewDetails"] = review_presence(detail)
        link = api.get(f"/v1/appStoreVersions/{row['id']}/relationships/build", optional=True)
        selected_build = None
        if link is not None and link["data"] is not None:
            resource(link["data"], "builds")
            selected_build = ident(link["data"]["id"])
        summary["selectedBuildId"] = selected_build
        if selected_build is None:
            findings.append("target_version_has_no_selected_build")
        if not summary["copyrightPresent"]:
            findings.append("target_version_copyright_missing")
        review = summary["reviewDetails"]
        if not review["exists"]:
            findings.append("target_version_review_details_missing")
        else:
            for field in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
                if not review[field + "Present"]:
                    findings.append("target_review_" + field + "_missing")
            if review["demoAccountRequired"] is True:
                for field in ("demoAccountName", "demoAccountPassword"):
                    if not review[field + "Present"]:
                        findings.append("target_review_" + field + "_missing")

    rows, completeness["appInfosHasMore"] = api.app_list("appInfos")
    app_infos = []
    require(len(rows) <= MAX_CHILD_DETAILS, "Too many app infos for this bounded audit")
    for row in rows:
        attrs = resource(row, "appInfos")
        summary = {"id": row["id"], **{key: enum(attrs.get(key)) for key in
                   ("appStoreState", "state", "appStoreAgeRating", "australiaAgeRating",
                    "brazilAgeRating", "brazilAgeRatingV2", "franceAgeRating", "koreaAgeRating")}}
        payload = api.get(f"/v1/appInfos/{row['id']}/ageRatingDeclaration", optional=True)
        if payload is None or payload["data"] is None:
            summary["ageDeclaration"] = {"exists": False}
        else:
            age = resource(payload["data"], "ageRatingDeclarations")
            summary["ageDeclaration"] = {
                "exists": True, "id": ident(payload["data"]["id"]),
                "observedAttributes": {key: enum(age[key]) for key in AGE_DESCRIPTORS + AGE_OPTIONS if key in age},
                "unansweredReturnedDescriptors": [key for key in AGE_DESCRIPTORS if key in age and age[key] is None],
                "notReturnedDescriptors": [key for key in AGE_DESCRIPTORS if key not in age],
                "developerAgeRatingInfoUrlPresent": present(age.get("developerAgeRatingInfoUrl")),
            }
        app_infos.append(summary)

    rows, completeness["buildsHasMore"] = api.app_list("builds")
    builds = []
    completeness["buildDetailsLimited"] = len(rows) > MAX_CHILD_DETAILS
    for index, row in enumerate(rows):
        attrs = resource(row, "builds")
        summary = {"id": row["id"], "buildNumber": version(attrs.get("version")),
                   "processingState": enum(attrs.get("processingState")),
                   "expired": enum(attrs.get("expired")),
                   "usesNonExemptEncryption": enum(attrs.get("usesNonExemptEncryption")),
                   "uploadedDate": timestamp(attrs.get("uploadedDate")),
                   "expirationDate": timestamp(attrs.get("expirationDate")),
                   "minOsVersion": version(attrs.get("minOsVersion"))}
        if index < MAX_CHILD_DETAILS:
            pre = api.get(f"/v1/builds/{row['id']}/preReleaseVersion", optional=True)
            if pre is not None and pre["data"] is not None:
                pa = resource(pre["data"], "preReleaseVersions")
                summary["preReleaseVersion"] = version(pa.get("version"))
                summary["platform"] = enum(pa.get("platform"))
            beta = api.get(f"/v1/builds/{row['id']}/buildBetaDetail", optional=True)
            if beta is not None and beta["data"] is not None:
                ba = resource(beta["data"], "buildBetaDetails")
                summary["beta"] = {key: enum(ba.get(key)) for key in
                                   ("internalBuildState", "externalBuildState", "autoNotifyEnabled")}
        builds.append(summary)

    rows, completeness["betaGroupsHasMore"] = api.app_list("betaGroups")
    groups = []
    completeness["betaGroupDetailsLimited"] = len(rows) > MAX_CHILD_DETAILS
    for index, row in enumerate(rows):
        attrs = resource(row, "betaGroups")
        summary = {"id": row["id"], **{key: enum(attrs.get(key)) for key in
                   ("isInternalGroup", "hasAccessToAllBuilds", "publicLinkEnabled")}}
        if index < MAX_CHILD_DETAILS:
            summary["testers"] = linkage_summary(api.get(
                f"/v1/betaGroups/{row['id']}/relationships/betaTesters", optional=True), "betaTesters")
            summary["builds"] = linkage_summary(api.get(
                f"/v1/betaGroups/{row['id']}/relationships/builds", optional=True), "builds")
        groups.append(summary)

    rows, completeness["reviewSubmissionsHasMore"] = api.app_list("reviewSubmissions")
    submissions = []
    for row in rows:
        attrs = resource(row, "reviewSubmissions")
        submissions.append({"id": row["id"], "platform": enum(attrs.get("platform")),
                            "state": enum(attrs.get("state")),
                            "submittedDate": timestamp(attrs.get("submittedDate"))})
    return {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "readOnly": True, "app": app, "targetVersion": TARGET_VERSION,
        "appStoreVersions": versions, "appInfos": app_infos, "builds": builds,
        "betaGroups": groups, "reviewSubmissions": submissions,
        "detectedMissingFields": sorted(set(findings)), "completeness": completeness,
        "requestCount": api.request_count,
        "notAssessed": [
            "review_credentials_validity_or_live_login", "physical_device_acceptance",
            "public_privacy_urls_and_actual_data_practices", "privacy_nutrition_labels",
            "screenshots_and_localized_listing_completeness", "pricing_and_territory_availability",
            "agreements_tax_and_banking", "all_apple_submission_validation_rules",
            "testers_outside_copybox_groups_or_their_identities",
        ],
        "overallSubmissionReadiness": "NOT_ESTABLISHED_BY_READ_ONLY_AUDIT",
    }


def main():
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
            report = run(session, client.generate_auth_headers)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "appId": APP_ID, "readOnly": True, "requestCount": report["requestCount"],
            "versionsObserved": len(report["appStoreVersions"]),
            "buildsObserved": len(report["builds"]), "betaGroupsObserved": len(report["betaGroups"]),
            "report": str(OUTPUT), "submissionReadiness": report["overallSubmissionReadiness"],
        }))
        return 0
    except AuditError as error:
        print(f"COPY Box read-only audit stopped: {error}", file=sys.stderr)
    except Exception:
        # No traceback or exception object: libraries may embed credentials or bodies.
        print("COPY Box read-only audit stopped: managed Apple access or response unavailable", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
