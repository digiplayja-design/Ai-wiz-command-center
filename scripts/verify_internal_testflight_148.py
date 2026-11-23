"""One existing internal TestFlight group's membership for one uploaded KORLIX build."""

import argparse
import re
import sys
import time
import traceback
from pathlib import Path
from urllib.parse import urlsplit


APP = "6783100102"
BUNDLE = "com.korlixdeveloper.korlixai"
VERSION = "12.0.7"
BUILD_NUMBER = "148"
ROOT = "https://api.appstoreconnect.apple.com/v1"
ELIGIBLE = {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}


class Stop(Exception):
    """Only constant, sanitized messages belong here."""


class Pending(Exception):
    """Eligible for read-only polling."""


def resource_id(item, kind):
    value = item["id"]
    if item["type"] != kind or not re.fullmatch(r"[A-Za-z0-9-]+", value):
        raise Stop("Apple returned an unexpected resource.")
    return value


class Apple:
    def __init__(self):
        import requests
        from codemagic.apple.app_store_connect import AppStoreConnectApiClient
        from codemagic.tools.app_store_connect.arguments import Types

        # Resolve the named integration exactly as the successful upload CLI does.
        # An environment entry can itself be an @file: or @env: reference.
        def configured(argument):
            try:
                item = argument.from_environment_variable_default()
            except (OSError, ValueError):
                raise Stop("The Codemagic integration could not resolve its " +
                           argument.environment_variable_key + " setting.") from None
            if item is None:
                raise Stop("Codemagic did not provide " + argument.environment_variable_key + ".")
            return item.value

        self.auth = AppStoreConnectApiClient(
            key_identifier=configured(Types.KeyIdentifierArgument),
            issuer_id=configured(Types.IssuerIdArgument),
            private_key=configured(Types.PrivateKeyArgument),
            log_requests=False,
            enable_jwt_cache=False,
        )
        # Validate signing before making any request. Do not log or persist the token.
        try:
            self.auth.generate_auth_headers()
        except Exception as exc:
            raise Stop(f"Local App Store Connect signing failed ({type(exc).__name__}).") from None
        self.session = requests.Session()

    def request(self, method, url, **kwargs):
        response = self.session.request(
            method, url, headers=self.auth.generate_auth_headers(),
            allow_redirects=False, timeout=25, **kwargs,
        )
        return response

    def read(self, path):
        response = self.request("GET", ROOT + path)
        if response.status_code != 200:
            raise Stop(f"Apple read returned HTTP {response.status_code}.")
        return response.json()["data"]

    def rows(self, path, **params):
        url = ROOT + path
        params["limit"] = 200
        seen = set()
        while url:
            parsed = urlsplit(url)
            if (parsed.scheme, parsed.netloc, parsed.path) != (
                "https", "api.appstoreconnect.apple.com", "/v1" + path
            ) or url in seen:
                raise Stop("Unexpected Apple pagination.")
            seen.add(url)
            response = self.request("GET", url, params=params)
            if response.status_code != 200:
                raise Stop(f"Apple list returned HTTP {response.status_code}.")
            page = response.json()
            yield from page["data"]
            url = page.get("links", {}).get("next")
            params = {}

    def add(self, group, build):
        import requests

        try:
            response = self.request(
                "POST", ROOT + f"/betaGroups/{group}/relationships/builds",
                json={"data": [{"type": "builds", "id": build}]},
            )
        except (requests.Timeout, requests.ConnectionError):
            # The outcome could be unknown. Read the relation, never repeat the write.
            return
        if response.status_code not in (204, 409) and response.status_code < 500:
            raise Stop(f"Apple group assignment returned HTTP {response.status_code}.")


def check(api, assign, wait_minutes, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + wait_minutes * 60
    attempted = None
    filters = {
        "filter[app]": APP, "filter[version]": BUILD_NUMBER,
        "filter[preReleaseVersion.version]": VERSION,
        "filter[preReleaseVersion.platform]": "IOS",
    }
    while True:
        try:
            builds = list(api.rows("/builds", **filters))
            if not builds:
                raise Pending("The exact uploaded build is not visible yet.")
            if len(builds) != 1:
                raise Stop("Apple returned multiple matching builds.")
            build = resource_id(builds[0], "builds")
            attrs = builds[0]["attributes"]
            if attrs["version"] != BUILD_NUMBER or attrs["expired"] is not False:
                raise Stop("Build number or expiry check failed.")
            if attrs["processingState"] == "PROCESSING":
                raise Pending("Apple is processing the exact uploaded build.")
            if attrs["processingState"] != "VALID":
                raise Stop("Apple has not accepted the uploaded build.")
            app = api.read(f"/builds/{build}/app")
            release = api.read(f"/builds/{build}/preReleaseVersion")
            if resource_id(app, "apps") != APP or app["attributes"]["bundleId"] != BUNDLE:
                raise Stop("The build does not belong to the expected app.")
            if (release["type"], release["attributes"]["version"], release["attributes"]["platform"]) != (
                "preReleaseVersions", VERSION, "IOS"
            ):
                raise Stop("The build does not match the expected iOS version.")
            state = api.read(f"/builds/{build}/buildBetaDetail")["attributes"]["internalBuildState"]
            if state == "PROCESSING":
                raise Pending("Apple is processing the build for internal testing.")
            if state not in ELIGIBLE:
                known = {"MISSING_EXPORT_COMPLIANCE", "IN_EXPORT_COMPLIANCE_REVIEW",
                         "PROCESSING_EXCEPTION", "EXPIRED"}
                label = state if state in known else "unavailable"
                raise Stop(f"Apple internal eligibility needs attention ({label}).")
            group_filters = {"filter[app]": APP, "filter[isInternalGroup]": "true",
                             "fields[betaGroups]": "isInternalGroup,publicLinkEnabled,hasAccessToAllBuilds"}
            groups = [g for g in api.rows("/betaGroups", **group_filters)
                      if g["attributes"]["isInternalGroup"] is True]
            if len(groups) != 1:
                raise Stop(f"Expected one existing internal group. Found {len(groups)}.")
            group = resource_id(groups[0], "betaGroups")
            if groups[0]["attributes"].get("publicLinkEnabled") is True:
                raise Stop("Apple returned an internal group with a public link.")
            target = (group, build)
            if attempted and attempted != target:
                raise Stop("The group or build changed during verification.")
            members = api.rows(f"/betaGroups/{group}/relationships/builds")
            linked = any(resource_id(member, "builds") == build for member in members)
            if linked and state == "IN_BETA_TESTING":
                return "Verified the exact build is in the existing internal group and in beta testing."
            if linked:
                raise Pending("Membership is verified. Apple has not marked the build in beta testing yet.")
            if attempted or groups[0]["attributes"].get("hasAccessToAllBuilds") is True:
                raise Pending("Awaiting Apple confirmation of this build's internal group membership.")
            if not assign:
                raise Stop("Eligible exact build; a manual internal assignment is needed.")
            attempted = target
            api.add(group, build)
            continue  # Check the actual relationship immediately, even with a zero wait.
        except Pending as pending:
            remaining = deadline - clock()
            if remaining <= 0:
                raise Stop(str(pending)) from None
            sleep(min(20, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assign", action="store_true", help="Allow one existing internal group assignment")
    parser.add_argument("--wait-minutes", type=int, choices=range(0, 31), default=20, metavar="0..30")
    args = parser.parse_args()
    try:
        print(check(Apple(), args.assign, args.wait_minutes))
    except Stop as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        # Print code locations only; provider bodies and exception text can contain secrets.
        frames = list(traceback.walk_tb(exc.__traceback__))
        verifier_frame = next((item for item in reversed(frames)
                               if item[0].f_code.co_filename == __file__), frames[0])
        for label, (frame, line) in (("Verification step", verifier_frame), ("Failure", frames[-1])):
            source = Path(frame.f_code.co_filename).name
            print(f"{label} at {source}:{line} in {frame.f_code.co_name}", file=sys.stderr)
        print(f"Verification could not finish ({type(exc).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
