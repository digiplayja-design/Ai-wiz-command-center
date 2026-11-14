#!/usr/bin/env python3
"""Sync reviewed COPY Box description and App Review notes only.

Uses the existing managed Apple integration. Review reads use sparse fieldsets.
PATCH response bodies are never read because they may contain private fields.
No contact, demo-account, build, pricing, release-mode or submission mutation.
"""

from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

from read_copybox_apple_status import (
    APP_ID, BUNDLE_ID, TARGET_VERSION, ORIGIN, AppleReadOnly, AuditError,
    ident, related_id, resource,
)

VERSION_ID = "3ae65f97-f9c5-498d-80b6-8f6d208615d6"
REVIEW_ID = "46939d38-8276-4684-b64d-0b32b319bbf0"
SOURCE_COMMIT = "e25b4b57f34cf1fc82d92fea2e6e9ab98d3f730c"
SOURCE_PREFIX = "docs/releases/copybox-20261103/store-submission/"
INPUT_PREFIX = "docs/releases/copybox/2026-11-14/metadata-inputs/"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path("artifacts/copybox-apple-metadata-sync.json")
INPUTS = {
    "description": {
        "file": "description.txt",
        "sha256": "c5af1d7e94273f8e68f5e60a58c9c4984808b1d0792428512c21eecf856bdbae",
        "gitBlobSha": "d91aa14999af2b613cced9f4afdf49dabe9fa35b",
    },
    "notes": {
        "file": "apple-review-notes.txt",
        "sha256": "83d8a2acebdefb1709ed412740042d6132adbe75cffeb42cdcef4019a169a779",
        "gitBlobSha": "26c0d24207e6eaeb1f7cf896bf214370dcea5c19",
    },
}
LOCALIZATIONS_GET = (
    f"/v1/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations"
    "?filter[locale]=en-US&fields[appStoreVersionLocalizations]=locale,description,appStoreVersion"
)
REVIEW_GET = (
    f"/v1/appStoreVersions/{VERSION_ID}/appStoreReviewDetail"
    "?fields[appStoreReviewDetails]=notes,appStoreVersion"
)


class MetadataStop(Exception):
    def __init__(self, code):
        self.code = code


def require(condition, code):
    if not condition:
        raise MetadataStop(code)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def load_inputs(root=ROOT):
    result = {}
    for field, expected in INPUTS.items():
        data = (root / INPUT_PREFIX / expected["file"]).read_bytes()
        require(sha256(data) == expected["sha256"], "reviewed_input_hash_mismatch")
        require(hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                == expected["gitBlobSha"], "reviewed_input_blob_mismatch")
        text = data.decode("utf-8").rstrip("\n")
        require(0 < len(text.encode("utf-8")) <= 4000, "reviewed_input_size_invalid")
        result[field] = text
    return result


def source_summary(inputs):
    return {field: {
        "sourcePath": SOURCE_PREFIX + values["file"],
        "sourceFileSha256": values["sha256"],
        "sourceGitBlobSha": values["gitBlobSha"],
        "submittedSha256": sha256(inputs[field].encode("utf-8")),
        "submittedBytes": len(inputs[field].encode("utf-8")),
    } for field, values in INPUTS.items()}


def new_report():
    return {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "appId": APP_ID, "versionId": VERSION_ID, "reviewDetailId": REVIEW_ID,
        "version": TARGET_VERSION, "locale": "en-US", "sourceCommit": SOURCE_COMMIT,
        "success": False, "phase": "initial", "scopeVerified": False,
        "fields": {}, "patchAttempts": [], "mutationOutcomeUnknown": False,
        "versionAttributesUnchanged": False, "requestCount": 0,
        "submissionAttempted": False, "failureCode": None,
    }


class AppleMetadataSync:
    def __init__(self, session, auth_headers, report, inputs):
        self.session, self.auth_headers, self.report = session, auth_headers, report
        self.inputs = inputs
        self.read = AppleReadOnly(session, auth_headers)
        self.localization_id = None
        self.ready_field = None
        self.used_fields = set()

    def scope(self):
        rows, more = self.read.app_list("appStoreVersions")
        require(not more, "version_scope_incomplete")
        matches = [row for row in rows if row["id"] == VERSION_ID]
        require(len(matches) == 1, "version_identity_mismatch")
        attrs = resource(matches[0], "appStoreVersions")
        require(attrs.get("platform") == "IOS"
                and attrs.get("versionString") == "1.0.0", "version_identity_mismatch")
        states = [attrs[key] for key in ("appStoreState", "appVersionState") if key in attrs]
        require(states and all(value == "PREPARE_FOR_SUBMISSION" for value in states),
                "version_not_in_preparation")
        require(attrs.get("releaseType") == "AFTER_APPROVAL", "release_type_changed")
        self.read.allowed.update((LOCALIZATIONS_GET, REVIEW_GET))
        return deepcopy(attrs)

    def fields(self):
        payload = self.read.get(LOCALIZATIONS_GET)
        require(isinstance(payload["data"], list)
                and len(payload["data"]) <= 200
                and not payload.get("links", {}).get("next"), "localization_scope_incomplete")
        matches = []
        for row in payload["data"]:
            attrs = resource(row, "appStoreVersionLocalizations")
            require(set(attrs) <= {"locale", "description"}, "sparse_fieldset_not_respected")
            if attrs.get("locale") == "en-US":
                require(related_id(row, "appStoreVersion", "appStoreVersions") in (None, VERSION_ID),
                        "localization_version_mismatch")
                matches.append(row)
        require(len(matches) == 1, "english_localization_not_unique")
        row = matches[0]
        localization_id = ident(row["id"])
        require(self.localization_id in (None, localization_id), "localization_identity_changed")
        self.localization_id = localization_id
        description = row["attributes"].get("description")
        require(description is None or type(description) is str, "description_type_invalid")

        review = self.read.get(REVIEW_GET)["data"]
        attrs = resource(review, "appStoreReviewDetails")
        require(review["id"] == REVIEW_ID, "review_detail_identity_mismatch")
        # Do not retrieve, compare, log, hash or otherwise inspect private values.
        require(set(attrs) <= {"notes"}, "sparse_fieldset_not_respected")
        require(related_id(review, "appStoreVersion", "appStoreVersions") in (None, VERSION_ID),
                "review_detail_version_mismatch")
        notes = attrs.get("notes")
        require(notes is None or type(notes) is str, "notes_type_invalid")
        return {"localizationId": localization_id, "description": description, "notes": notes}

    def patch_once(self, field):
        require(field in INPUTS and field not in self.used_fields
                and self.ready_field == field and self.read.verified_app
                and self.localization_id is not None, "mutation_scope_violation")
        kind = "appStoreVersionLocalizations" if field == "description" else "appStoreReviewDetails"
        item_id = self.localization_id if field == "description" else REVIEW_ID
        self.used_fields.add(field)  # Never retry an ambiguous write.
        self.ready_field = None
        attempt = {"field": field, "httpStatus": None, "readbackVerified": False}
        self.report["patchAttempts"].append(attempt)
        self.report["mutationOutcomeUnknown"] = True
        response = None
        try:
            response = self.session.request(
                "PATCH", ORIGIN + f"/v1/{kind}/{item_id}",
                json={"data": {"type": kind, "id": item_id,
                               "attributes": {field: self.inputs[field]}}},
                headers=self.auth_headers(), timeout=30, allow_redirects=False,
                stream=True,
            )
            status = response.status_code
        except Exception:
            raise MetadataStop("apple_patch_transport_unconfirmed") from None
        finally:
            if response is not None:
                response.close()  # PATCH bodies may contain credentials; never read them.
        require(type(status) is int and 100 <= status <= 599, "apple_patch_status_invalid")
        attempt["httpStatus"] = status
        require(status == 200, "apple_patch_not_confirmed")
        return attempt


def run(session, auth_headers, root=ROOT):
    report = new_report()
    api = None
    try:
        report["phase"] = "verify_reviewed_inputs"
        inputs = load_inputs(root)
        report["sources"] = source_summary(inputs)
        api = AppleMetadataSync(session, auth_headers, report, inputs)
        report["phase"] = "verify_identity"
        app = api.read.verify_app()
        require(app["id"] == "6830765098" and app["bundleId"] == "com.korlixdeveloper.copybox",
                "app_identity_mismatch")
        original_attrs = api.scope()
        current = api.fields()
        report["scopeVerified"] = True
        report["localizationId"] = current["localizationId"]

        for field in ("description", "notes"):
            if current[field] == inputs[field]:
                report["fields"][field] = "unchanged_verified"
                continue
            report["phase"] = "recheck_" + field
            require(api.scope() == original_attrs, "version_changed_during_run")
            require(api.fields() == current, "metadata_changed_during_run")
            api.ready_field = field
            report["phase"] = "update_" + field
            attempt = api.patch_once(field)
            report["phase"] = "verify_" + field
            require(api.scope() == original_attrs, "version_changed_during_run")
            observed = api.fields()
            expected = dict(current) | {field: inputs[field]}
            require(observed == expected, "metadata_readback_mismatch")
            attempt["readbackVerified"] = True
            report["mutationOutcomeUnknown"] = False
            report["fields"][field] = "updated_verified"
            current = observed

        report["phase"] = "verify_final_state"
        require(api.scope() == original_attrs, "version_changed_during_run")
        final = api.fields()
        require(all(final[field] == inputs[field] for field in INPUTS), "final_readback_mismatch")
        report["versionAttributesUnchanged"] = True
        report["releaseType"] = "AFTER_APPROVAL"
        report["state"] = "PREPARE_FOR_SUBMISSION"
        report["phase"] = "complete"
        report["success"] = True
    except MetadataStop as error:
        report["failureCode"] = error.code
    except AuditError:
        report["failureCode"] = "apple_scoped_get_or_identity_check_failed"
    except Exception:
        report["failureCode"] = "metadata_sync_unconfirmed"
    if api is not None:
        report["requestCount"] = api.read.request_count + len(api.used_fields)
    return report


def main():
    if sys.argv[1:] != ["--apply-reviewed-metadata"]:
        print("Use --apply-reviewed-metadata for the reviewed COPY Box text-only action.",
              file=sys.stderr)
        return 2
    report = new_report()
    try:
        load_inputs()  # Fail before managed authentication if pinned text changed.
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
    except MetadataStop as error:
        report["failureCode"] = error.code
    except Exception:
        report["failureCode"] = "managed_apple_access_or_inputs_unavailable"
    try:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception:
        print("COPY Box metadata sync stopped: evidence could not be saved.", file=sys.stderr)
        return 1
    print(json.dumps({key: report[key] for key in (
        "appId", "success", "phase", "fields", "failureCode", "requestCount",
    )} | {"report": str(OUTPUT)}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
