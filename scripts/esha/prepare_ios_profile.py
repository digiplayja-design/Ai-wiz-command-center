#!/usr/bin/env python3
"""Prepare only Esha's App Store profile using an existing signing identity.

Run inside the manual Codemagic signing-setup workflow. The integration supplies
API authentication and Codemagic imports KORLIX_APP_STORE_CERT into its keychain.
Only public certificates are read. This script never creates a key/certificate,
changes capabilities or permissions, uploads an app, or exports a private key.
"""

from __future__ import annotations

import base64
import datetime as dt
import hashlib
import importlib.metadata
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


CLI_VERSION = "0.69.0"
APP_ID = "6835184869"
BUNDLE_ID = "com.korlixdeveloper.esha"
SKU = "ESHA_IOS_001"
PROFILE_NAME = "Esha App Store"
PROFILE_FILE = "Esha-App-Store.mobileprovision"
REPORT_FILE = "Esha-iOS-signing-setup-verification.json"
# CLI 0.69.0 rejects zero. Its retry counter starts at one, so a limit of one
# makes exactly one HTTP attempt; a 401/5xx response is never retried.
CLI_SINGLE_ATTEMPT = "1"
UTC = dt.timezone.utc
RESOURCE_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
PEM_CERTIFICATE = re.compile(
    rb"-----BEGIN CERTIFICATE-----\s+.+?\s+-----END CERTIFICATE-----", re.S
)


class SetupError(Exception):
    """Messages are fixed local text, never subprocess/API response content."""


def require(condition, message):
    if not condition:
        raise SetupError(message)


def utc_date(value, label):
    if isinstance(value, str):
        try:
            value = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise SetupError(f"{label} has an invalid date.") from None
    require(isinstance(value, dt.datetime), f"{label} has no valid date.")
    # Dates in decoded Apple property lists are naive UTC datetimes.
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def cert_date(certificate, name):
    value = getattr(certificate, name + "_utc", None)
    return utc_date(value if value is not None else getattr(certificate, name), "Certificate")


def resource(value, kind):
    require(isinstance(value, dict), "Apple returned a malformed resource.")
    require(value.get("type") == kind, "Apple returned an unexpected resource type.")
    require(isinstance(value.get("id"), str) and RESOURCE_ID.fullmatch(value["id"]),
            "Apple returned an invalid resource identifier.")
    require(isinstance(value.get("attributes"), dict), "Apple resource attributes are missing.")
    return value["attributes"]


def resource_list(value, kind):
    require(isinstance(value, list), "Apple did not return a complete resource list.")
    for item in value:
        resource(item, kind)
    require(len({item["id"] for item in value}) == len(value),
            "Apple returned duplicate resource identifiers.")
    return value


def decoded_bytes(value, label):
    require(isinstance(value, str) and 0 < len(value) <= 4_000_000,
            f"{label} content is missing or too large.")
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise SetupError(f"{label} content is not valid base64.") from None


class ToolRunner:
    def __init__(self, cli, run=subprocess.run):
        self.cli = str(cli)
        self.run = run

    def capture(self, arguments, stage, *, apple=False):
        # CLI 0.69.0 writes response logs/audits under its temporary directory.
        # Isolate and remove those files; only our two allowlisted artifacts exit
        # the job. JWT disk caching is disabled separately below.
        with tempfile.TemporaryDirectory(prefix="esha-signing-command-") as temporary:
            environment = os.environ.copy()
            environment["TMPDIR"] = temporary
            environment["TMP"] = temporary
            environment["TEMP"] = temporary
            if apple:
                # Certificate listing must not inspect another workflow's key.
                environment.pop("CERTIFICATE_PRIVATE_KEY", None)
                environment.pop("CERTIFICATE_PRIVATE_KEY_PASSWORD", None)
            try:
                result = self.run(
                    arguments, check=False, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, timeout=120, env=environment,
                )
            except subprocess.TimeoutExpired:
                raise SetupError(f"{stage} timed out. No retry was attempted; run the inventory checks again.") from None
            except OSError:
                raise SetupError(f"{stage} could not run its required tool.") from None
            if result.returncode:
                output = result.stdout + result.stderr
                # argparse diagnostics include the option name "unauthorized".
                # That word alone is not evidence of an Apple HTTP response.
                if result.returncode == 2 and re.search(rb"(?:^|\n)usage:|error: (?:argument|unrecognized)", output, re.I):
                    raise SetupError(f"{stage} failed local command validation before an Apple request. No authentication result was obtained.")
                # Match the pinned CLI's AppStoreConnectApiError rendering,
                # including the Apple origin, request method and numeric status.
                status = re.search(
                    rb"\b(?:GET|POST|PATCH|DELETE) https://api\.appstoreconnect\.apple\.com/\S+ returned (401|403):",
                    output,
                )
                if status and status[1] == b"403":
                    raise SetupError(f"{stage} was denied by the existing API permissions (403).")
                if status and status[1] == b"401":
                    raise SetupError(f"{stage} could not authenticate with the configured integration (401).")
                raise SetupError(f"{stage} failed. Raw tool output is withheld; no retry was attempted.")
            require(len(result.stdout) <= 16_000_000, f"{stage} returned an oversized response.")
            return result.stdout

    def api(self, *arguments):
        creating = arguments[:2] == ("profiles", "create")
        stage = "Profile creation" if creating else "Apple signing inventory lookup"
        output = self.capture([
            self.cli, *arguments, "--json", "--no-color", "--log-stream", "stderr",
            "--disable-jwt-cache", "--api-unauthorized-retries", CLI_SINGLE_ATTEMPT,
            "--api-server-error-retries", CLI_SINGLE_ATTEMPT,
        ], stage, apple=True)
        # The pinned CLI paginates list requests before printing one JSON value.
        # Empty output, concatenated/partial JSON, and errors cannot mean [] here.
        try:
            return json.loads(output)
        except (ValueError, UnicodeError):
            raise SetupError(f"{stage} did not return complete JSON. No retry was attempted.") from None

    def public_certificates(self):
        return self.capture(["security", "find-certificate", "-a", "-p"], "Public certificate inspection")

    def signing_identities(self):
        return self.capture(["security", "find-identity", "-v", "-p", "codesigning"], "Signing identity inspection")

    def decode_profile(self, content):
        with tempfile.TemporaryDirectory(prefix="esha-profile-inspection-") as temporary:
            profile = Path(temporary) / "profile.mobileprovision"
            profile.write_bytes(content)
            decoded = self.capture(["security", "cms", "-D", "-i", str(profile)], "Provisioning profile decoding")
        try:
            result = plistlib.loads(decoded)
        except (ValueError, TypeError, plistlib.InvalidFileException):
            raise SetupError("Apple's provisioning profile could not be decoded.") from None
        require(isinstance(result, dict), "Apple's provisioning profile is not a property-list dictionary.")
        return result


@dataclass(frozen=True)
class SigningIdentity:
    der: bytes
    api_id: str
    sha1: str
    sha256: str
    expires: dt.datetime


def select_signing_identity(pem_data, identity_data, api_certificates, team_id, now):
    valid_identities = set(re.findall(
        rb'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"[^"\r\n]+"\s*$',
        identity_data, re.M,
    ))
    valid_identities = {fingerprint.decode().upper() for fingerprint in valid_identities}
    require(valid_identities, "No valid installed code-signing identity with a private key was found.")
    installed = {}
    blocks = PEM_CERTIFICATE.findall(pem_data)
    require(blocks, "The keychain returned no public certificates.")
    for block in blocks:
        try:
            certificate = x509.load_pem_x509_certificate(block)
        except ValueError:
            raise SetupError("The keychain returned an invalid public certificate.") from None
        der = certificate.public_bytes(serialization.Encoding.DER)
        sha1 = hashlib.sha1(der).hexdigest().upper()
        if sha1 not in valid_identities:
            continue
        names = certificate.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
        teams = certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
        if len(names) != 1 or not re.match(r"^(Apple Distribution|iPhone Distribution): .+", names[0].value):
            continue
        if len(teams) != 1 or teams[0].value != team_id:
            continue
        if not cert_date(certificate, "not_valid_before") <= now < cert_date(certificate, "not_valid_after"):
            continue
        try:
            purposes = certificate.extensions.get_extension_for_class(x509.ExtendedKeyUsage).value
        except x509.ExtensionNotFound:
            continue
        if ExtendedKeyUsageOID.CODE_SIGNING not in purposes:
            continue
        # Identical copies in the keychain are one identity, not an ambiguity.
        installed[der] = certificate
    require(len(installed) == 1,
            "Expected exactly one valid installed distribution identity for the configured Apple team.")
    der, certificate = next(iter(installed.items()))
    matches = []
    for candidate in resource_list(api_certificates, "certificates"):
        attributes = candidate["attributes"]
        remote_der = decoded_bytes(attributes.get("certificateContent"), "Apple certificate")
        if remote_der != der:
            continue
        require(attributes.get("certificateType") in {"DISTRIBUTION", "IOS_DISTRIBUTION"},
                "The matching Apple certificate is not a distribution certificate.")
        expires = utc_date(attributes.get("expirationDate"), "Apple certificate")
        require(expires > now and abs((expires - cert_date(certificate, "not_valid_after")).total_seconds()) <= 1,
                "Apple and the keychain disagree about certificate validity.")
        serial = attributes.get("serialNumber")
        require(isinstance(serial, str) and re.fullmatch(r"[A-Fa-f0-9]+", serial),
                "Apple returned an invalid certificate serial number.")
        require(int(serial, 16) == certificate.serial_number, "Apple certificate serial numbers do not match.")
        matches.append(candidate)
    require(len(matches) == 1, "The installed distribution certificate has no unique exact match in this Apple account.")
    return SigningIdentity(
        der, matches[0]["id"], hashlib.sha1(der).hexdigest().upper(),
        hashlib.sha256(der).hexdigest().upper(), cert_date(certificate, "not_valid_after"),
    )


@dataclass(frozen=True)
class VerifiedProfile:
    content: bytes
    api_id: str
    uuid: str
    prefix: str
    expires: dt.datetime


def verify_profile_resource(value, runner, identity, team_id, seed_id, now):
    attributes = resource(value, "profiles")
    require(attributes.get("profileState") == "ACTIVE" and attributes.get("profileType") == "IOS_APP_STORE",
            "Apple returned a profile outside the active iOS App Store selection.")
    require(attributes.get("platform") == "IOS", "Apple returned a profile for another platform.")
    content = decoded_bytes(attributes.get("profileContent"), "Provisioning profile")
    profile = runner.decode_profile(content)
    require(profile.get("TeamIdentifier") == [team_id], "The profile belongs to a different Apple team.")
    require("ProvisionedDevices" not in profile and "ProvisionsAllDevices" not in profile,
            "The profile permits device-restricted or enterprise distribution.")
    entitlements = profile.get("Entitlements")
    require(isinstance(entitlements, dict), "The profile has no entitlements dictionary.")
    require(entitlements.get("get-task-allow") is False, "The profile does not explicitly disable debugging.")
    require(entitlements.get("com.apple.developer.team-identifier") == team_id,
            "The profile's team entitlement does not match the configured team.")
    prefixes = profile.get("ApplicationIdentifierPrefix")
    require(isinstance(prefixes, list) and len(prefixes) == 1 and isinstance(prefixes[0], str)
            and re.fullmatch(r"[A-Z0-9]{10}", prefixes[0]), "The profile has an ambiguous App ID prefix.")
    prefix = prefixes[0]
    # Legacy App ID prefixes need not equal the Developer Team ID.
    require(seed_id is None or prefix == seed_id, "The profile prefix does not match the registered Bundle ID.")
    require(entitlements.get("application-identifier") == prefix + "." + BUNDLE_ID,
            "The profile does not match Esha's exact bundle identifier.")
    require(profile.get("DeveloperCertificates") == [identity.der],
            "The profile does not contain exactly the verified existing signing certificate.")
    expires = utc_date(profile.get("ExpirationDate"), "Provisioning profile")
    created = utc_date(profile.get("CreationDate"), "Provisioning profile")
    require(created <= now + dt.timedelta(minutes=5) and created < expires and now < expires,
            "The profile is expired, not yet valid, or has inconsistent dates.")
    remote_expiry = utc_date(attributes.get("expirationDate"), "Apple profile metadata")
    require(abs((remote_expiry - expires).total_seconds()) <= 1, "Apple profile expiry metadata does not match its content.")
    profile_uuid = profile.get("UUID")
    try:
        require(isinstance(profile_uuid, str) and str(uuid.UUID(profile_uuid)).upper() == profile_uuid.upper(),
                "The profile has an invalid UUID.")
    except ValueError:
        raise SetupError("The profile has an invalid UUID.") from None
    require(isinstance(attributes.get("uuid"), str) and attributes["uuid"].upper() == profile_uuid.upper(),
            "Apple profile UUID metadata does not match its content.")
    return VerifiedProfile(content, value["id"], profile_uuid.upper(), prefix, expires)


def prepare_profile(runner, team_id, now):
    require(isinstance(team_id, str) and re.fullmatch(r"[A-Z0-9]{10}", team_id),
            "ESHA_APPLE_TEAM_ID must contain the actual ten-character Apple Developer Team ID.")
    apps = resource_list(runner.api("apps", "list", "--bundle-id-identifier", BUNDLE_ID,
                                    "--strict-match-identifier"), "apps")
    require(len(apps) == 1 and apps[0]["id"] == APP_ID
            and apps[0]["attributes"].get("bundleId") == BUNDLE_ID
            and apps[0]["attributes"].get("sku") == SKU,
            "The Apple app ID, bundle identifier or SKU does not exactly match Esha.")
    bundles = resource_list(runner.api("bundle-ids", "list", "--bundle-id-identifier", BUNDLE_ID,
                                       "--strict-match-identifier"), "bundleIds")
    require(len(bundles) == 1 and bundles[0]["attributes"].get("identifier") == BUNDLE_ID
            and bundles[0]["attributes"].get("platform") in {"IOS", "UNIVERSAL"},
            "No unique registered Esha Bundle ID was returned.")
    bundle_id = bundles[0]["id"]
    seed_id = bundles[0]["attributes"].get("seedId")
    require(seed_id is None or (isinstance(seed_id, str) and re.fullmatch(r"[A-Z0-9]{10}", seed_id)),
            "Apple returned an invalid App ID prefix.")
    public_certificates = runner.public_certificates()
    signing_identities = runner.signing_identities()
    certificates = runner.api("certificates", "list", "--profile-type", "IOS_APP_STORE")
    identity = select_signing_identity(public_certificates, signing_identities, certificates, team_id, now)
    profiles = resource_list(runner.api("bundle-ids", "profiles", "--bundle-ids", bundle_id,
                                        "--type", "IOS_APP_STORE", "--state", "ACTIVE"), "profiles")
    # A malformed/mismatched active profile is a blocker, never an empty list.
    verified = [verify_profile_resource(item, runner, identity, team_id, seed_id, now) for item in profiles]
    created = not verified
    if created:
        result = runner.api("profiles", "create", bundle_id, "--certificate-ids", identity.api_id,
                            "--type", "IOS_APP_STORE", "--name", PROFILE_NAME)
        selected = verify_profile_resource(result, runner, identity, team_id, seed_id, now)
    else:
        selected = max(verified, key=lambda value: (value.expires, value.uuid))
    report = {
        "verified_at_utc": now.isoformat(),
        "cli_version": CLI_VERSION,
        "apple_app_id": APP_ID,
        "bundle_id": BUNDLE_ID,
        "sku": SKU,
        "apple_team_id": team_id,
        "bundle_resource_id": bundle_id,
        "certificate": {
            "codemagic_reference": "KORLIX_APP_STORE_CERT",
            "apple_resource_id": identity.api_id,
            "sha1": identity.sha1,
            "sha256": identity.sha256,
            "expires_at_utc": identity.expires.isoformat(),
            "installed_private_key_identity_verified": True,
            "exact_api_certificate_match": True,
        },
        "profile": {
            "file": PROFILE_FILE,
            "codemagic_reference_to_import": "ESHA_APP_STORE_PROFILE",
            "apple_resource_id": selected.api_id,
            "uuid": selected.uuid,
            "type": "IOS_APP_STORE",
            "state": "ACTIVE",
            "app_identifier_prefix": selected.prefix,
            "expires_at_utc": selected.expires.isoformat(),
            "sha256": hashlib.sha256(selected.content).hexdigest(),
            "created": created,
            "reused": not created,
        },
        "create_attempts": int(created),
        "certificate_created": False,
        "permissions_changed": False,
        "private_key_exported": False,
        "app_uploaded": False,
    }
    return selected.content, report


def clear_artifacts(output_directory):
    output_directory = Path(output_directory)
    require(not output_directory.is_symlink(), "The signing artifact directory cannot be a symlink.")
    outputs = [output_directory / PROFILE_FILE, output_directory / REPORT_FILE]
    # A failed run must not leave a previous success artifact available to CI.
    try:
        output_directory.mkdir(parents=True, exist_ok=True)
        for output in outputs:
            output.unlink(missing_ok=True)
    except OSError:
        raise SetupError("The signing artifact directory could not be prepared safely.") from None
    return outputs


def run_setup(runner, team_id, app_id, output_directory, source_commit, now):
    output_directory = Path(output_directory)
    outputs = clear_artifacts(output_directory)
    require(app_id == APP_ID, "ESHA_APP_STORE_ID must equal Esha's confirmed Apple app ID.")
    require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit),
            "A verified source commit is required.")
    content, report = prepare_profile(runner, team_id, now)
    report["source_commit"] = source_commit
    try:
        with tempfile.TemporaryDirectory(prefix="esha-signing-artifacts-", dir=output_directory.parent) as temporary:
            temporary = Path(temporary)
            (temporary / PROFILE_FILE).write_bytes(content)
            (temporary / REPORT_FILE).write_text(json.dumps(report, indent=2) + "\n")
            for output in outputs:
                os.replace(temporary / output.name, output)
    except OSError:
        for output in outputs:
            output.unlink(missing_ok=True)
        raise SetupError("The verified signing artifacts could not be saved.") from None
    return report


def main():
    try:
        root = Path(__file__).resolve().parents[2]
        output_directory = root / "apps/esha/artifacts/ios-signing"
        # Clear prior outputs before even the local CLI/environment preflight.
        clear_artifacts(output_directory)
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION,
                "Esha signing setup requires codemagic-cli-tools 0.69.0.")
        cli = Path(sys.executable).parent / "app-store-connect"
        require(cli.is_file(), "Run this script with the pinned Codemagic CLI virtual environment's Python.")
        runner = ToolRunner(cli)
        commit = runner.capture(["git", "-C", str(root), "rev-parse", "HEAD"], "Source revision lookup").decode().strip()
        report = run_setup(
            runner, os.environ.get("ESHA_APPLE_TEAM_ID", ""), os.environ.get("ESHA_APP_STORE_ID", ""),
            output_directory, commit, dt.datetime.now(UTC),
        )
    except SetupError as error:
        print(f"Esha signing setup stopped: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("Esha signing setup stopped because local verification could not complete. No success was recorded.", file=sys.stderr)
        return 1
    action = "Created" if report["profile"]["created"] else "Reused"
    print(f"{action} and verified Esha's App Store profile using the existing distribution identity.")
    print(f"Saved {PROFILE_FILE} and {REPORT_FILE}. Import the profile as ESHA_APP_STORE_PROFILE.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
