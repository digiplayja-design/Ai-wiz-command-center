#!/usr/bin/env python3
"""Plan or synchronize only Esha's existing en-US draft Apple listing.

Default: read-only plan. --apply-draft writes the narrowly allowlisted fields.
Run with the pinned Codemagic CLI environment and existing integration. This
helper cannot create versions/localizations, upload, submit, publish, change
agreements/access, or answer privacy, age-rating or content-rights declarations.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from prepare_ios_profile import APP_ID, BUNDLE_ID, CLI_VERSION, CLI_SINGLE_ATTEMPT, SKU, SetupError, ToolRunner


API_ORIGIN = "https://api.appstoreconnect.apple.com"
LOCALE = "en-US"
TARGET_VERSION = "1.0.0"
PRIVACY_URL = "https://chee-chai-chee-backend.onrender.com/esha/privacy"
REPORT_FILE = "Esha-Apple-draft-listing-verification.json"
RESOURCE_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
FIELD_LIMITS = {"subtitle": 30, "description": 4000, "keywords": 100, "promotional_text": 170}
VERSION_FIELDS = {
    "description": "description", "keywords": "keywords",
    "promotional_text": "promotionalText", "support_url": "supportUrl",
}
ALLOWED_FIELDS = {
    "appInfos": {"primaryCategory", "secondaryCategory"},
    "appInfoLocalizations": {"subtitle", "privacyPolicyUrl", "privacyChoicesUrl"},
    "appStoreVersions": {"versionString"},
    "appStoreVersionLocalizations": set(VERSION_FIELDS.values()),
}
GET_PATH = re.compile(
    r"/v1/(?:apps/" + APP_ID + r"(?:/(?:appInfos|appStoreVersions|builds))?"
    r"|appCategories"
    r"|appInfos/[A-Za-z0-9_-]+(?:/appInfoLocalizations|/relationships/(?:primaryCategory|secondaryCategory))?"
    r"|appStoreVersions/[A-Za-z0-9_-]+(?:/appStoreVersionLocalizations|/relationships/build)?"
    r"|appInfoLocalizations/[A-Za-z0-9_-]+|appStoreVersionLocalizations/[A-Za-z0-9_-]+)\Z"
)


class ListingError(Exception):
    """Only fixed local messages; no credentials or response bodies."""


def require(condition, message):
    if not condition:
        raise ListingError(message)


def resource(value, kind, identifier=None):
    require(isinstance(value, dict) and value.get("type") == kind,
            "Apple returned an unexpected resource type.")
    require(isinstance(value.get("id"), str) and RESOURCE_ID.fullmatch(value["id"]),
            "Apple returned an invalid resource identifier.")
    require(identifier is None or value["id"] == identifier, "Apple returned a different resource than requested.")
    require(isinstance(value.get("attributes"), dict), "Apple returned incomplete resource attributes.")
    return value


def require_draft(value, kind):
    attributes = resource(value, kind)["attributes"]
    state_fields = ("state", "appStoreState") if kind == "appInfos" else ("appVersionState", "appStoreState")
    states = [attributes[key] for key in state_fields if attributes.get(key) is not None]
    require(states and all(state == "PREPARE_FOR_SUBMISSION" for state in states),
            "Esha's app information and version must remain Prepare for Submission.")


def is_draft(value, kind):
    try:
        require_draft(value, kind)
        return True
    except ListingError:
        return False


def validate_metadata(metadata):
    require(isinstance(metadata, dict) and metadata.get("schema_version") == 1
            and metadata.get("locale") == LOCALE, "Expected the en-US Esha metadata draft.")
    apple = metadata.get("apple")
    require(isinstance(apple, dict), "The Apple metadata draft is missing.")
    identifiers = apple.get("candidate_identifiers", {})
    require(isinstance(identifiers, dict)
            and identifiers.get("app_store_connect_numeric_app_id") == APP_ID
            and identifiers.get("bundle_id") == BUNDLE_ID
            and identifiers.get("app_store_connect_sku") == SKU,
            "The metadata app ID, bundle or SKU does not match Esha.")
    require(apple.get("version") == TARGET_VERSION
            and metadata.get("app", {}).get("source_version") == TARGET_VERSION,
            "Only Esha's prepared version 1.0.0 is supported.")
    for field, limit in FIELD_LIMITS.items():
        value = apple.get(field)
        require(isinstance(value, str) and value.strip() and len(value) <= limit
                and not any(ord(character) < 32 and character not in "\n\t" for character in value),
                f"The draft {field} is missing, invalid or exceeds Apple's field limit.")
    require(len(apple["keywords"].encode("utf-8")) <= 100, "The draft keywords exceed the conservative 100-byte limit.")
    support = apple.get("support_url")
    require(isinstance(support, str), "The draft support URL is missing.")
    url = urllib.parse.urlsplit(support)
    require(url.scheme == "https" and url.netloc == "www.korlixdeveloper.com"
            and url.path == "/support.html" and not url.query and not url.fragment,
            "The draft support URL does not match the prepared Korlix support page.")
    require(apple.get("primary_category") == "LIFESTYLE" and apple.get("secondary_category") == "SHOPPING",
            "Only the prepared Lifestyle and Shopping categories are supported.")
    require(apple.get("privacy_url") == PRIVACY_URL,
            "The draft privacy URL does not match Esha's verified public policy page.")
    return apple


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def listing_subprocess(arguments, **options):
    # The CLI's optional What's New argument reads this variable by default.
    # Exclude it so this helper cannot change a field outside the approved set.
    options["env"].pop("APP_STORE_CONNECT_WHATS_NEW", None)
    return subprocess.run(arguments, **options)


class AppleClient:
    """Strict Apple reads and two missing CLI PATCH operations; no POST/DELETE."""

    def __init__(self, auth_headers, cli, *, open_request=None, run_cli=listing_subprocess):
        self.auth_headers = auth_headers
        self.open_request = open_request or urllib.request.build_opener(NoRedirects()).open
        self.cli = ToolRunner(cli, run=run_cli)

    def document(self, method, path, *, parameters=None, body=None):
        parsed = urllib.parse.urlsplit(path)
        if parsed.scheme or parsed.netloc:
            require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                    and not parsed.fragment, "Apple pagination attempted to leave the approved API origin.")
            path = parsed.path + ("?" + parsed.query if parsed.query else "")
        parsed = urllib.parse.urlsplit(path)
        require(GET_PATH.fullmatch(parsed.path) and not parsed.fragment,
                "The request is outside Esha's draft-listing endpoint allowlist.")
        require(method in {"GET", "PATCH"}, "Only draft reads and narrowly scoped updates are permitted.")
        if method == "PATCH":
            require(not parsed.query and body is not None, "Draft updates cannot carry arbitrary query parameters.")
            validate_patch(parsed.path, body)
            require(body["data"]["type"] in {"appInfos", "appInfoLocalizations"},
                    "Supported version updates must use the pinned Codemagic CLI.")
        query = urllib.parse.urlencode(parameters) if parameters else parsed.query
        url = API_ORIGIN + parsed.path + ("?" + query if query else "")
        payload = None if body is None else json.dumps(body).encode("utf-8")
        headers = {**self.auth_headers(), "Accept": "application/json", "Content-Type": "application/json"}
        request = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with self.open_request(request, timeout=30) as response:
                require(response.getcode() == 200, "Apple returned an unexpected HTTP status; no retry was attempted.")
                content = response.read(16_000_001)
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            if code in {401, 403}:
                raise ListingError(f"The existing Apple integration rejected authentication or access (HTTP {code}). No retry was attempted.") from None
            raise ListingError(f"Apple rejected the draft operation (HTTP {code}). No retry was attempted.") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise ListingError("Apple's draft operation could not complete. No retry was attempted; re-read before any later run.") from None
        require(len(content) <= 16_000_000, "Apple returned an oversized response.")
        try:
            document = json.loads(content)
        except (ValueError, UnicodeError):
            raise ListingError("Apple returned incomplete JSON.") from None
        require(isinstance(document, dict) and "data" in document and "errors" not in document,
                "Apple returned an incomplete or error response.")
        return document

    def get(self, path, kind, identifier):
        return resource(self.document("GET", path)["data"], kind, identifier)

    def list(self, path, kind, *, parameters=None):
        values, seen_ids, seen_pages = [], set(), set()
        original_path = urllib.parse.urlsplit(path).path
        next_page, total = path, None
        while next_page:
            require(next_page not in seen_pages and len(seen_pages) < 100, "Apple returned cyclic or excessive pagination.")
            require(urllib.parse.urlsplit(next_page).path == original_path,
                    "Apple pagination changed its resource endpoint.")
            seen_pages.add(next_page)
            document = self.document("GET", next_page, parameters=parameters if len(seen_pages) == 1 else None)
            require(isinstance(document["data"], list) and isinstance(document.get("links"), dict),
                    "Apple returned an incomplete resource list.")
            for value in document["data"]:
                resource(value, kind)
                require(value["id"] not in seen_ids, "Apple returned duplicate resources across list pages.")
                seen_ids.add(value["id"])
                values.append(value)
            page_total = document.get("meta", {}).get("paging", {}).get("total")
            if page_total is not None:
                require(type(page_total) is int and page_total >= 0 and (total is None or page_total == total),
                        "Apple returned inconsistent pagination totals.")
                total = page_total
            next_page = document["links"].get("next")
            require(next_page is None or (isinstance(next_page, str) and next_page),
                    "Apple returned an invalid next-page link.")
        require(total is None or total == len(values), "Apple's resource list is incomplete.")
        return values

    def linkage(self, path, kind):
        value = self.document("GET", path)["data"]
        if value is None:
            return None
        require(isinstance(value, dict) and value.get("type") == kind
                and isinstance(value.get("id"), str) and RESOURCE_ID.fullmatch(value["id"]),
                "Apple returned an invalid relationship identifier.")
        return value["id"]

    def update(self, operation):
        body = operation.payload()
        path = f"/v1/{operation.kind}/{operation.identifier}"
        validate_patch(path, body)
        if operation.kind in {"appInfos", "appInfoLocalizations"}:
            value = self.document("PATCH", path, body=body)["data"]
        else:
            command = ("app-store-versions" if operation.kind == "appStoreVersions"
                       else "app-store-version-localizations")
            flags = {"versionString": "version-string", "description": "description", "keywords": "keywords",
                     "promotionalText": "promotional-text", "supportUrl": "support-url"}
            arguments = [self.cli.cli, command, "modify", operation.identifier]
            arguments.extend(f"--{flags[key]}={value}" for key, value in operation.after.items())
            arguments.extend(["--json", "--no-color", "--log-stream", "stderr", "--disable-jwt-cache",
                              "--api-unauthorized-retries", CLI_SINGLE_ATTEMPT,
                              "--api-server-error-retries", CLI_SINGLE_ATTEMPT])
            try:
                value = json.loads(self.cli.capture(arguments, "Apple draft listing update", apple=True))
            except SetupError as error:
                raise ListingError(str(error)) from None
            except (ValueError, UnicodeError):
                raise ListingError("Apple's draft update returned incomplete JSON; re-read before any later run.") from None
        resource(value, operation.kind, operation.identifier)


def validate_patch(path, body):
    require(isinstance(body, dict) and set(body) == {"data"} and isinstance(body["data"], dict),
            "The draft update has an unexpected payload.")
    data = body["data"]
    kind, identifier = data.get("type"), data.get("id")
    require(kind in ALLOWED_FIELDS and isinstance(identifier, str) and RESOURCE_ID.fullmatch(identifier)
            and path == f"/v1/{kind}/{identifier}", "The draft update targets an unapproved resource.")
    container = "relationships" if kind == "appInfos" else "attributes"
    require(set(data) == {"type", "id", container} and isinstance(data[container], dict)
            and data[container] and set(data[container]) <= ALLOWED_FIELDS[kind],
            "The draft update contains an unapproved field.")
    if kind == "appInfos":
        for field, relationship in data[container].items():
            expected = "LIFESTYLE" if field == "primaryCategory" else "SHOPPING"
            require(relationship == {"data": {"type": "appCategories", "id": expected}},
                    "The draft category update contains an unapproved category.")
    else:
        require(all(isinstance(value, str) for value in data[container].values()),
                "The draft update contains a non-text value.")
        if kind == "appStoreVersions":
            require(data[container] == {"versionString": TARGET_VERSION}, "The version update is not Esha 1.0.0.")
        if kind == "appInfoLocalizations":
            for field, expected in {"privacyPolicyUrl": PRIVACY_URL, "privacyChoicesUrl": PRIVACY_URL + "#deletion"}.items():
                require(field not in data[container] or data[container][field] == expected,
                        "The privacy link update does not match Esha's prepared public links.")


@dataclass(frozen=True)
class Operation:
    kind: str
    identifier: str
    before: dict
    after: dict

    def payload(self):
        if self.kind == "appInfos":
            values = {field: {"data": {"type": "appCategories", "id": value}} for field, value in self.after.items()}
            container = "relationships"
        else:
            values, container = self.after, "attributes"
        return {"data": {"type": self.kind, "id": self.identifier, container: values}}

    def summary(self):
        return {"resource_type": self.kind, "resource_id": self.identifier,
                "fields": sorted(self.after),
                "target_sha256": hashlib.sha256(json.dumps(self.after, sort_keys=True).encode()).hexdigest()}


def verify_app(client):
    app = client.get(f"/v1/apps/{APP_ID}", "apps", APP_ID)
    require(app["attributes"].get("bundleId") == BUNDLE_ID and app["attributes"].get("sku") == SKU,
            "Apple's app ID, bundle identifier or SKU does not exactly match Esha.")


def choose_locale(values, kind):
    matches = [value for value in values if resource(value, kind)["attributes"].get("locale") == LOCALE]
    require(len(matches) == 1, "Exactly one existing en-US localization is required; this helper does not create locales.")
    return matches[0]


def category_values(client, info_id):
    return {field: client.linkage(f"/v1/appInfos/{info_id}/relationships/{field}", "appCategories")
            for field in ("primaryCategory", "secondaryCategory")}


def ensure_no_builds(client, version_id):
    selected = client.linkage(f"/v1/appStoreVersions/{version_id}/relationships/build", "builds")
    builds = client.list(f"/v1/apps/{APP_ID}/builds", "builds", parameters={"limit": 200})
    require(selected is None and not builds, "Version 1.0 cannot be renamed after a build exists; review the version manually.")


def discover(client, apple):
    verify_app(client)
    infos = client.list(f"/v1/apps/{APP_ID}/appInfos", "appInfos", parameters={"limit": 200})
    drafts = [value for value in infos if is_draft(value, "appInfos")]
    require(len(drafts) == 1, "Exactly one Prepare for Submission app-info record is required.")
    info = drafts[0]
    versions = client.list(f"/v1/apps/{APP_ID}/appStoreVersions", "appStoreVersions", parameters={"limit": 200})
    drafts = [value for value in versions if value["attributes"].get("platform") == "IOS"
              and is_draft(value, "appStoreVersions")]
    require(len(drafts) == 1, "Exactly one Prepare for Submission iOS version is required.")
    version = drafts[0]
    require(version["attributes"].get("versionString") in {"1.0", TARGET_VERSION},
            "The pending iOS version is outside the prepared 1.0 to 1.0.0 transition.")
    if version["attributes"]["versionString"] == "1.0":
        ensure_no_builds(client, version["id"])
    info_locale = choose_locale(client.list(f"/v1/appInfos/{info['id']}/appInfoLocalizations",
                                             "appInfoLocalizations", parameters={"limit": 200}), "appInfoLocalizations")
    version_locale = choose_locale(client.list(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                                                "appStoreVersionLocalizations", parameters={"limit": 200}),
                                   "appStoreVersionLocalizations")
    categories = client.list("/v1/appCategories", "appCategories", parameters={"include": "parent", "limit": 200})
    for expected in (apple["primary_category"], apple["secondary_category"]):
        matches = [category for category in categories if category["id"] == expected]
        require(len(matches) == 1, "Apple did not confirm a unique requested category.")
        platforms = matches[0]["attributes"].get("platforms")
        parent = matches[0].get("relationships", {}).get("parent", {})
        require(isinstance(platforms, list) and "IOS" in platforms
                and isinstance(parent, dict) and "data" in parent and parent["data"] is None,
                "Apple did not confirm the requested top-level iOS category.")
    return {"appInfos": info, "appStoreVersions": version,
            "appInfoLocalizations": info_locale, "appStoreVersionLocalizations": version_locale,
            "category_values": category_values(client, info["id"])}


def values_for(snapshot, kind, fields):
    values = snapshot["category_values"] if kind == "appInfos" else snapshot[kind]["attributes"]
    require(all(field in values for field in fields), "Apple omitted a listing field needed for comparison.")
    return {field: values[field] for field in fields}


def plan(snapshot, apple):
    targets = [
        ("appStoreVersions", {"versionString": TARGET_VERSION}),
        ("appInfoLocalizations", {"subtitle": apple["subtitle"], "privacyPolicyUrl": apple["privacy_url"],
                                  "privacyChoicesUrl": apple["privacy_url"] + "#deletion"}),
        ("appInfos", {"primaryCategory": apple["primary_category"], "secondaryCategory": apple["secondary_category"]}),
        ("appStoreVersionLocalizations", {target: apple[source] for source, target in VERSION_FIELDS.items()}),
    ]
    operations = []
    for kind, desired in targets:
        current = values_for(snapshot, kind, desired)
        changed = {field: value for field, value in desired.items() if current[field] != value}
        if changed:
            operations.append(Operation(kind, snapshot[kind]["id"],
                                        {field: current[field] for field in changed}, changed))
    return operations


def guard_operation(client, snapshot, operation):
    verify_app(client)
    info = client.get(f"/v1/appInfos/{snapshot['appInfos']['id']}", "appInfos", snapshot["appInfos"]["id"])
    version = client.get(f"/v1/appStoreVersions/{snapshot['appStoreVersions']['id']}",
                         "appStoreVersions", snapshot["appStoreVersions"]["id"])
    require_draft(info, "appInfos")
    require_draft(version, "appStoreVersions")
    require(version["attributes"].get("platform") == "IOS"
            and version["attributes"].get("versionString") in {"1.0", TARGET_VERSION},
            "The pending iOS version changed during synchronization.")
    if operation.kind == "appStoreVersions" and version["attributes"]["versionString"] == "1.0":
        ensure_no_builds(client, version["id"])
    if operation.kind == "appInfos":
        current = category_values(client, operation.identifier)
    else:
        current_resource = client.get(f"/v1/{operation.kind}/{operation.identifier}", operation.kind, operation.identifier)
        current = current_resource["attributes"]
        if operation.kind.endswith("Localizations"):
            require(current.get("locale") == LOCALE, "The listing localization changed during synchronization.")
    require(all(field in current for field in operation.after), "Apple omitted a listing field during revalidation.")
    current = {field: current[field] for field in operation.after}
    if current == operation.after:
        return False
    require(current == operation.before, "Draft listing fields changed concurrently; re-read before making further updates.")
    return True


def save_report(path, report):
    path = Path(path)
    require(not path.parent.is_symlink() and not path.is_symlink(), "The listing report path cannot be a symlink.")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix="esha-listing-", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(report, stream, indent=2)
        stream.write("\n")
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def synchronize(client, metadata, *, apply_draft, report_path, source_commit):
    report = {"status": "checking", "mode": "apply_draft" if apply_draft else "read_only_plan",
              "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "apple_app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU, "locale": LOCALE,
              "source_commit": source_commit, "cli_version": CLI_VERSION,
              "planned_operations": [], "attempted_operations": [], "verified_operations": [],
              "uploaded": False, "submitted": False, "published": False,
              "declarations_modified": False, "access_changed": False}
    save_report(report_path, report)
    try:
        require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit),
                "A verified source commit is required.")
        apple = validate_metadata(metadata)
        report["metadata_sha256"] = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()
        snapshot = discover(client, apple)
        report["resource_ids"] = {kind: value["id"] for kind, value in snapshot.items() if kind != "category_values"}
        operations = plan(snapshot, apple)
        report["planned_operations"] = [operation.summary() for operation in operations]
        save_report(report_path, report)
        if not apply_draft:
            report["status"] = "plan_only_no_changes"
        else:
            for operation in operations:
                if guard_operation(client, snapshot, operation):
                    report["attempted_operations"].append(operation.summary())
                    save_report(report_path, report)
                    client.update(operation)
                    # Re-read each changed value; a successful HTTP response alone
                    # does not establish the final draft contents.
                    require(not guard_operation(client, snapshot, operation),
                            "Apple's draft update could not be verified; re-read before any later run.")
                report["verified_operations"].append(operation.summary())
                save_report(report_path, report)
            final = discover(client, apple)
            require(all(final[kind]["id"] == snapshot[kind]["id"] for kind in ALLOWED_FIELDS),
                    "Apple's draft resource selection changed during synchronization.")
            require(not plan(final, apple), "The final draft does not match the prepared listing fields.")
            report["status"] = "draft_listing_synchronized"
        report["completed_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save_report(report_path, report)
        return report
    except ListingError as error:
        report["status"] = "stopped_review_partial_progress"
        report["error"] = str(error)
        save_report(report_path, report)
        raise
    except Exception:
        report["status"] = "stopped_review_partial_progress"
        report["error"] = "Local draft verification failed; raw details are withheld."
        save_report(report_path, report)
        raise ListingError(report["error"]) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-draft", action="store_true", help="Apply only the allowlisted draft listing changes.")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    report_path = root / "apps/esha/artifacts/apple-listing" / REPORT_FILE
    try:
        # Remove prior success even if local credential or package checks fail.
        require(not report_path.is_symlink() and not report_path.parent.is_symlink(), "The report path cannot be a symlink.")
        report_path.unlink(missing_ok=True)
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION,
                "The draft listing helper requires codemagic-cli-tools 0.69.0.")
        require(os.environ.get("ESHA_APP_STORE_ID") == APP_ID, "ESHA_APP_STORE_ID must equal Esha's confirmed app ID.")
        cli = Path(sys.executable).parent / "app-store-connect"
        require(cli.is_file(), "Run with the pinned Codemagic CLI virtual environment's Python.")
        variables = ["APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY"]
        require(all(os.environ.get(key) for key in variables), "The existing Codemagic Apple integration credentials are unavailable.")
        metadata = json.loads((root / "apps/esha/release/store-metadata.json").read_text())
        validate_metadata(metadata)
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], stderr=subprocess.PIPE).decode().strip()
        # Use the pinned CLI's authentication implementation without its HTTP
        # logger. API credentials and the resulting JWT stay in memory. No cache.
        with tempfile.TemporaryDirectory(prefix="esha-listing-auth-") as temporary:
            previous_temp = tempfile.tempdir
            tempfile.tempdir = temporary
            try:
                from codemagic.apple.app_store_connect import AppStoreConnectApiClient
                from codemagic.tools.app_store_connect.arguments import Types
                # Resolve the same environment-backed argument types as the
                # pinned CLI, including its documented @env:/@file: forms.
                auth_values = [argument.from_environment_variable_default().value for argument in (
                    Types.KeyIdentifierArgument, Types.IssuerIdArgument, Types.PrivateKeyArgument,
                )]
                authenticator = AppStoreConnectApiClient(
                    *auth_values,
                    unauthorized_request_retries=0, server_error_retries=0, enable_jwt_cache=False,
                )
                headers = authenticator.generate_auth_headers()
                client = AppleClient(lambda: dict(headers), cli)
                report = synchronize(client, metadata, apply_draft=arguments.apply_draft,
                                     report_path=report_path, source_commit=commit)
            finally:
                tempfile.tempdir = previous_temp
    except ListingError as error:
        print(f"Esha draft listing stopped: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("Esha draft listing stopped because local setup could not complete. No success was recorded.", file=sys.stderr)
        return 1
    print("Esha draft listing synchronized and re-read." if report["status"] == "draft_listing_synchronized"
          else "Esha draft listing plan prepared; no changes made.")
    print(f"Saved {REPORT_FILE}. No upload, submission or publication was performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
