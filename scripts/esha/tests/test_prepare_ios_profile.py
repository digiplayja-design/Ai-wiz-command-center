"""Fixture-only safety checks; no Apple requests or macOS keychain access."""

import base64
import copy
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_ios_profile as setup


TEAM = "FIXTURE123"
PREFIX = "LEGACY1234"
NOW = dt.datetime(2026, 11, 15, 18, 0, tzinfo=setup.UTC)
COMMIT = "a" * 40


def make_certificate(team=TEAM, *, days=180, serial=1234):
    # Ephemeral fixture key: never serialized or used with a real account.
    key = ec.generate_private_key(ec.SECP256R1())
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "Apple Distribution: Fixture Company"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team),
    ])
    certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                   .public_key(key.public_key()).serial_number(serial)
                   .not_valid_before(NOW - dt.timedelta(days=30))
                   .not_valid_after(NOW + dt.timedelta(days=days))
                   .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]), critical=False)
                   .sign(key, hashes.SHA256()))
    der = certificate.public_bytes(serialization.Encoding.DER)
    return certificate, der, certificate.public_bytes(serialization.Encoding.PEM)


def api_resource(kind, identifier, attributes):
    return {"type": kind, "id": identifier, "attributes": attributes}


def certificate_resource(certificate, der, identifier="CERTFIXTURE"):
    return api_resource("certificates", identifier, {
        "certificateContent": base64.b64encode(der).decode(),
        "certificateType": "DISTRIBUTION",
        "serialNumber": format(certificate.serial_number, "X"),
        "expirationDate": setup.cert_date(certificate, "not_valid_after").isoformat(),
    })


def profile_resource(der):
    expires = NOW + dt.timedelta(days=90)
    profile = {
        "UUID": "ACD2014C-1281-4AA7-9089-AB980E5A2388",
        "TeamIdentifier": [TEAM],
        "ApplicationIdentifierPrefix": [PREFIX],
        "DeveloperCertificates": [der],
        "CreationDate": (NOW - dt.timedelta(hours=1)).replace(tzinfo=None),
        "ExpirationDate": expires.replace(tzinfo=None),
        "Entitlements": {
            "application-identifier": PREFIX + "." + setup.BUNDLE_ID,
            "com.apple.developer.team-identifier": TEAM,
            "get-task-allow": False,
        },
    }
    return api_resource("profiles", "PROFILEFIXTURE", {
        "profileState": "ACTIVE", "profileType": "IOS_APP_STORE", "platform": "IOS",
        "uuid": profile["UUID"], "expirationDate": expires.isoformat(),
        "profileContent": base64.b64encode(plistlib.dumps(profile)).decode(),
    })


def mutate_profile(value, change):
    value = copy.deepcopy(value)
    profile = plistlib.loads(base64.b64decode(value["attributes"]["profileContent"]))
    change(profile)
    value["attributes"]["profileContent"] = base64.b64encode(plistlib.dumps(profile)).decode()
    return value


class FixtureRunner:
    def __init__(self, certificate, der, pem):
        self.apps = [api_resource("apps", setup.APP_ID, {"bundleId": setup.BUNDLE_ID, "sku": setup.SKU})]
        self.bundles = [api_resource("bundleIds", "BUNDLEFIXTURE", {
            "identifier": setup.BUNDLE_ID, "platform": "IOS", "seedId": PREFIX,
        })]
        self.certificates = [certificate_resource(certificate, der)]
        self.created_profile = profile_resource(der)
        self.profiles = [copy.deepcopy(self.created_profile)]
        self.pem = pem
        self.identities = ('  1) ' + hashlib.sha1(der).hexdigest().upper()
                           + ' "Apple Distribution: Fixture Company"\n     1 valid identities found\n').encode()
        self.calls = []
        self.failures = {}

    def api(self, *arguments):
        self.calls.append(arguments)
        action = arguments[:2]
        if action in self.failures:
            raise self.failures[action]
        inventories = {
            ("apps", "list"): self.apps,
            ("bundle-ids", "list"): self.bundles,
            ("certificates", "list"): self.certificates,
            ("bundle-ids", "profiles"): self.profiles,
        }
        if action == ("profiles", "create"):
            self.profiles = [copy.deepcopy(self.created_profile)]
            return copy.deepcopy(self.created_profile)
        return copy.deepcopy(inventories[action])

    def public_certificates(self):
        return self.pem

    def signing_identities(self):
        return self.identities

    def decode_profile(self, content):
        return plistlib.loads(content)

    def create_calls(self):
        return [call for call in self.calls if call[:2] == ("profiles", "create")]


class ProfileSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.certificate, cls.der, cls.pem = make_certificate()

    def setUp(self):
        self.runner = FixtureRunner(self.certificate, self.der, self.pem)

    def assert_no_create(self):
        self.assertEqual(self.runner.create_calls(), [])

    def test_reuses_exact_profile_with_legacy_prefix_and_duplicate_public_certificates(self):
        self.runner.pem += self.pem
        content, report = setup.prepare_profile(self.runner, TEAM, NOW)
        self.assertEqual(content, base64.b64decode(self.runner.profiles[0]["attributes"]["profileContent"]))
        self.assertTrue(report["profile"]["reused"])
        self.assertEqual(report["profile"]["app_identifier_prefix"], PREFIX)
        self.assertEqual(report["create_attempts"], 0)
        self.assert_no_create()

    def test_app_identity_mismatches_abort_before_signing_inventory_or_create(self):
        for location, key in [("resource", "id"), ("attributes", "bundleId"), ("attributes", "sku")]:
            with self.subTest(field=key):
                self.runner = FixtureRunner(self.certificate, self.der, self.pem)
                target = self.runner.apps[0] if location == "resource" else self.runner.apps[0]["attributes"]
                target[key] = "OTHERAPP"
                with self.assertRaises(setup.SetupError):
                    setup.prepare_profile(self.runner, TEAM, NOW)
                self.assertEqual(len(self.runner.calls), 1)
                self.assert_no_create()

    def test_public_certificate_without_valid_private_key_identity_is_rejected(self):
        self.runner.identities = b"     0 valid identities found\n"
        with self.assertRaisesRegex(setup.SetupError, "private key"):
            setup.prepare_profile(self.runner, TEAM, NOW)
        self.assert_no_create()

    def test_wrong_team_or_expired_installed_identity_cannot_create(self):
        for certificate in [make_certificate("OTHER12345"), make_certificate(days=-1)]:
            with self.subTest(case=certificate[0].serial_number):
                self.runner = FixtureRunner(*certificate)
                with self.assertRaises(setup.SetupError):
                    setup.prepare_profile(self.runner, TEAM, NOW)
                self.assert_no_create()

    def test_distinct_usable_identities_are_ambiguous(self):
        other_certificate, other_der, other_pem = make_certificate(serial=5678)
        self.runner.pem += other_pem
        self.runner.identities += ('  2) ' + hashlib.sha1(other_der).hexdigest().upper()
                                   + ' "Apple Distribution: Another Fixture"\n').encode()
        self.runner.certificates.append(certificate_resource(other_certificate, other_der, "OTHERCERT"))
        with self.assertRaisesRegex(setup.SetupError, "exactly one"):
            setup.prepare_profile(self.runner, TEAM, NOW)
        self.assert_no_create()

    def test_api_certificate_must_match_exact_der_type_serial_and_expiry(self):
        changes = {
            "certificateContent": base64.b64encode(b"different certificate").decode(),
            "certificateType": "DEVELOPMENT",
            "serialNumber": "FFFF",
            "expirationDate": (NOW + dt.timedelta(days=3)).isoformat(),
        }
        for key, value in changes.items():
            with self.subTest(field=key):
                self.runner = FixtureRunner(self.certificate, self.der, self.pem)
                self.runner.certificates[0]["attributes"][key] = value
                with self.assertRaises(setup.SetupError):
                    setup.prepare_profile(self.runner, TEAM, NOW)
                self.assert_no_create()

    def test_malformed_or_failed_inventory_is_never_an_empty_inventory(self):
        for inventory in [None, {}, {"errors": []}, [None], [{"id": "missing-type"}],
                          [self.runner.profiles[0], self.runner.profiles[0]]]:
            with self.subTest(inventory=type(inventory).__name__):
                self.runner.profiles = inventory
                with self.assertRaises(setup.SetupError):
                    setup.prepare_profile(self.runner, TEAM, NOW)
                self.assert_no_create()
        self.runner.failures[("bundle-ids", "profiles")] = setup.SetupError("Inventory lookup failed.")
        with self.assertRaises(setup.SetupError):
            setup.prepare_profile(self.runner, TEAM, NOW)
        self.assert_no_create()

    def test_invalid_existing_profile_never_triggers_creation(self):
        changes = {
            "wrong team": lambda p: p.update(TeamIdentifier=["OTHER12345"]),
            "wrong certificate": lambda p: p.update(DeveloperCertificates=[b"different"]),
            "wrong bundle": lambda p: p["Entitlements"].update({"application-identifier": PREFIX + ".other"}),
            "wrong prefix": lambda p: p.update(ApplicationIdentifierPrefix=["OTHER12345"]),
            "debugging enabled": lambda p: p["Entitlements"].update({"get-task-allow": True}),
            "debugging missing": lambda p: p["Entitlements"].pop("get-task-allow"),
            "debugging integer": lambda p: p["Entitlements"].update({"get-task-allow": 0}),
            "device list empty": lambda p: p.update(ProvisionedDevices=[]),
            "enterprise": lambda p: p.update(ProvisionsAllDevices=True),
            "enterprise field false": lambda p: p.update(ProvisionsAllDevices=False),
            "expired": lambda p: p.update(ExpirationDate=(NOW - dt.timedelta(days=1)).replace(tzinfo=None)),
            "not yet valid": lambda p: p.update(CreationDate=(NOW + dt.timedelta(days=1)).replace(tzinfo=None)),
            "UUID mismatch": lambda p: p.update(UUID="FA6A8C66-5307-4999-AF2A-7377C41AD6A2"),
        }
        original = self.runner.profiles[0]
        for reason, change in changes.items():
            with self.subTest(reason=reason):
                self.runner.profiles = [mutate_profile(original, change)]
                with self.assertRaises(setup.SetupError):
                    setup.prepare_profile(self.runner, TEAM, NOW)
                self.assert_no_create()

    def test_single_creation_uses_observed_ids_then_second_run_reuses_it(self):
        self.runner.profiles = []
        with tempfile.TemporaryDirectory() as directory:
            first = setup.run_setup(self.runner, TEAM, setup.APP_ID, directory, COMMIT, NOW)
            second = setup.run_setup(self.runner, TEAM, setup.APP_ID, directory, COMMIT, NOW)
            self.assertTrue(first["profile"]["created"])
            self.assertTrue(second["profile"]["reused"])
            self.assertEqual(self.runner.create_calls(), [(
                "profiles", "create", "BUNDLEFIXTURE", "--certificate-ids", "CERTFIXTURE",
                "--type", "IOS_APP_STORE", "--name", "Esha App Store",
            )])
            self.assertEqual({p.name for p in Path(directory).iterdir()}, {setup.PROFILE_FILE, setup.REPORT_FILE})
            report = (Path(directory) / setup.REPORT_FILE).read_text()
            self.assertEqual(json.loads(report)["source_commit"], COMMIT)
            self.assertNotIn("BEGIN", report)
            self.assertNotIn(base64.b64encode(self.der).decode(), report)
            for flag in ["certificate_created", "permissions_changed", "private_key_exported", "app_uploaded"]:
                self.assertFalse(second[flag])

    def test_created_profile_is_revalidated_before_any_artifact_is_saved(self):
        self.runner.profiles = []
        self.runner.created_profile = mutate_profile(self.runner.created_profile,
                                                     lambda p: p.update(TeamIdentifier=["OTHER12345"]))
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(setup.SetupError):
                setup.run_setup(self.runner, TEAM, setup.APP_ID, directory, COMMIT, NOW)
            self.assertEqual(list(Path(directory).iterdir()), [])
        self.assertEqual(len(self.runner.create_calls()), 1)

    def test_creation_failure_is_not_retried(self):
        self.runner.profiles = []
        self.runner.failures[("profiles", "create")] = setup.SetupError("Profile creation timed out.")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(setup.SetupError):
                setup.run_setup(self.runner, TEAM, setup.APP_ID, directory, COMMIT, NOW)
            self.assertEqual(list(Path(directory).iterdir()), [])
        self.assertEqual(len(self.runner.create_calls()), 1)

    def test_failed_environment_preflight_removes_only_stale_allowlisted_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in [setup.PROFILE_FILE, setup.REPORT_FILE, "unrelated.txt"]:
                (Path(directory) / name).write_text("stale")
            with self.assertRaises(setup.SetupError):
                setup.run_setup(self.runner, TEAM, "WRONG", directory, COMMIT, NOW)
            self.assertEqual([p.name for p in Path(directory).iterdir()], ["unrelated.txt"])
        self.assertEqual(self.runner.calls, [])


class ToolRunnerTests(unittest.TestCase):
    def test_api_failures_timeout_and_bad_json_are_sanitized_and_not_retried(self):
        for failure in [401, 403, 500, "timeout", "partial", "concatenated"]:
            with self.subTest(failure=failure):
                calls = []
                def command(arguments, **kwargs):
                    calls.append((arguments, kwargs))
                    if failure == "timeout":
                        raise subprocess.TimeoutExpired(arguments, 120, output=b"PRIVATE-CONTENT")
                    if isinstance(failure, int):
                        return subprocess.CompletedProcess(arguments, 1, b"PRIVATE-CONTENT", str(failure).encode())
                    output = b'[{"partial":' if failure == "partial" else b"[] []"
                    return subprocess.CompletedProcess(arguments, 0, output, b"PRIVATE-CONTENT")
                runner = setup.ToolRunner("/fixture/app-store-connect", run=command)
                with self.assertRaises(setup.SetupError) as raised:
                    runner.api("profiles", "create", "BUNDLEFIXTURE", "--certificate-ids", "CERTFIXTURE")
                self.assertNotIn("PRIVATE-CONTENT", str(raised.exception))
                self.assertEqual(len(calls), 1)
                arguments, options = calls[0]
                for flag in ["--api-unauthorized-retries", "--api-server-error-retries"]:
                    self.assertEqual(arguments[arguments.index(flag) + 1], "0")
                self.assertIn("--disable-jwt-cache", arguments)
                self.assertFalse(Path(options["env"]["TMPDIR"]).exists())

    def test_private_temp_logs_are_removed_and_unrelated_key_is_not_passed(self):
        def command(arguments, **kwargs):
            temporary = Path(kwargs["env"]["TMPDIR"])
            (temporary / "raw-response.log").write_text("SENSITIVE-RESPONSE")
            self.assertNotIn("CERTIFICATE_PRIVATE_KEY", kwargs["env"])
            self.assertNotIn("CERTIFICATE_PRIVATE_KEY_PASSWORD", kwargs["env"])
            self.assertEqual(kwargs["env"]["APP_STORE_CONNECT_PRIVATE_KEY"], "FIXTURE-AUTH")
            self.temporary = temporary
            return subprocess.CompletedProcess(arguments, 0, b"[]", b"")
        runner = setup.ToolRunner("/fixture/app-store-connect", run=command)
        with mock.patch.dict(os.environ, {
            "CERTIFICATE_PRIVATE_KEY": "UNRELATED-KEY", "CERTIFICATE_PRIVATE_KEY_PASSWORD": "UNRELATED-PASSWORD",
            "APP_STORE_CONNECT_PRIVATE_KEY": "FIXTURE-AUTH",
        }):
            self.assertEqual(runner.api("certificates", "list"), [])
        self.assertFalse(self.temporary.exists())


if __name__ == "__main__":
    unittest.main()
