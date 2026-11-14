import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

MODULE = Path(__file__).resolve().parents[1] / "complete_copybox_apple_age_rating.py"
sys.path.insert(0, str(MODULE.parent))
spec = importlib.util.spec_from_file_location("copybox_age_completion", MODULE)
age = importlib.util.module_from_spec(spec)
spec.loader.exec_module(age)


def entity(kind, ident, attrs=None, relationships=None):
    return {"type": kind, "id": ident, "attributes": attrs or {},
            "relationships": relationships or {}}


class Response:
    def __init__(self, payload, status=200):
        self.payload, self.status_code = payload, status
        self.content = json.dumps(payload).encode()

    def json(self):
        return self.payload


class Session:
    """Stateful fake Apple transport; no network is reachable through it."""

    def __init__(self, complete=False, override="NONE", initial_ratings=None,
                 calculated_ratings=None, overridden_ratings=None):
        self.calls, self.patch_bodies = [], []
        self.attrs = {key: value if complete else None for key, value in age.REVIEWED_ATTRIBUTES.items()}
        self.attrs.update(kidsAgeBand=None, ageRatingOverride="NONE",
                          ageRatingOverrideV2=override, koreaAgeRatingOverride="NONE",
                          developerAgeRatingInfoUrl="https://PRIVATE_URL_SECRET.invalid",
                          gracRatingClassificationNumber="PRIVATE_RCN_SECRET")
        self.app = entity("apps", age.APP_ID, {"bundleId": age.BUNDLE_ID, "name": "PRIVATE_APP_NAME_SECRET"})
        self.version = entity("appStoreVersions", age.VERSION_ID,
                              {"versionString": age.TARGET_VERSION, "platform": "IOS",
                               "appStoreState": "PREPARE_FOR_SUBMISSION",
                               "appVersionState": "PREPARE_FOR_SUBMISSION",
                               "releaseType": "AFTER_APPROVAL",
                               "demoAccountPassword": "PRIVATE_REVIEW_SECRET"})
        self.info = entity("appInfos", age.APP_INFO_ID,
                           {"state": "PREPARE_FOR_SUBMISSION"},
                           {"ageRatingDeclaration": {"data": {"type": "ageRatingDeclarations",
                                                             "id": age.DECLARATION_ID}}})
        self.declaration_id = age.DECLARATION_ID
        self.initial_ratings = initial_ratings if initial_ratings is not None else {"USA": None, "BRA": None, "KOR": None}
        self.calculated_ratings = calculated_ratings or {"USA": "THIRTEEN_PLUS", "BRA": "SIXTEEN_PLUS", "KOR": "TWELVE_PLUS"}
        self.overridden_ratings = overridden_ratings or {"USA": "SIXTEEN_PLUS", "BRA": "SIXTEEN_PLUS", "KOR": "FIFTEEN_PLUS"}
        if complete and initial_ratings is None:
            self.initial_ratings = dict(self.overridden_ratings if override == "SIXTEEN_PLUS" else self.calculated_ratings)
        self.descriptor_patched = self.override_patched = False
        self.ratings_reads = 0
        self.ratings_sequences = []
        self.next_url = None
        self.paginate = False
        self.list_next = None
        self.reject_patch = False
        self.patch_failure = None
        self.ignore_descriptor = False
        self.get_failure = None

    def declaration(self):
        return {"data": entity("ageRatingDeclarations", self.declaration_id, copy.deepcopy(self.attrs))}

    def rating_response(self, values, cursor=False):
        rows = [entity("territoryAgeRatings", "opaque:" + territory,
                       {"appStoreAgeRating": rating},
                       {"territory": {"data": {"type": "territories", "id": territory}}})
                for territory, rating in values.items()]
        next_url = self.next_url
        if self.paginate:
            rows = [row for row in rows if (row["relationships"]["territory"]["data"]["id"] != "USA") == cursor]
            next_url = None if cursor else age.ORIGIN + age.TERRITORY_PATH + "?limit=200&include=territory&cursor=page-two"
        return {"data": rows, "links": {"next": next_url}}

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if self.get_failure and method == "GET":
            raise self.get_failure
        base = age.ORIGIN + "/v1/apps/" + age.APP_ID
        if method == "GET":
            if url == base:
                return Response({"data": copy.deepcopy(self.app)})
            if url == base + "/appStoreVersions":
                return Response({"data": [copy.deepcopy(self.version)], "links": {"next": self.list_next}})
            if url == base + "/appInfos":
                return Response({"data": [copy.deepcopy(self.info)], "links": {"next": None}})
            if url == age.ORIGIN + age.DECLARATION_READ:
                return Response(self.declaration())
            if url.startswith(age.ORIGIN + age.TERRITORY_PATH + "?"):
                self.ratings_reads += 1
                if self.ratings_sequences:
                    values = self.ratings_sequences.pop(0)
                else:
                    values = self.overridden_ratings if self.override_patched else (
                        self.calculated_ratings if self.descriptor_patched else self.initial_ratings)
                return Response(self.rating_response(values, cursor="cursor=" in url))
        if method == "PATCH" and url == age.ORIGIN + age.DECLARATION_WRITE:
            self.patch_bodies.append(copy.deepcopy(kwargs["json"]))
            if self.patch_failure:
                raise self.patch_failure
            if self.reject_patch:
                return Response({"errors": [{"detail": "PRIVATE_ERROR_SECRET"}]}, status=403)
            attrs = kwargs["json"]["data"]["attributes"]
            self.attrs.update(attrs)
            if "ageRatingOverrideV2" in attrs:
                self.override_patched = True
            else:
                self.descriptor_patched = True
                if self.ignore_descriptor:
                    self.attrs["advertising"] = None
            return Response(self.declaration())
        raise AssertionError("Unexpected transport method/path")


def execute(session):
    return age.run(session, lambda: {"Authorization": "Bearer AUTH_SECRET"}, pause=lambda _: None)


class CompletionTests(unittest.TestCase):
    def test_reviewed_completion_writes_only_24_fields_then_the_conditional_override(self):
        session = Session()
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(session.patch_bodies), 2)
        first, second = [body["data"] for body in session.patch_bodies]
        self.assertEqual(first, {"type": "ageRatingDeclarations", "id": age.DECLARATION_ID,
                                 "attributes": age.REVIEWED_ATTRIBUTES})
        self.assertEqual(len(first["attributes"]), 24)
        self.assertEqual(second["attributes"], {"ageRatingOverrideV2": "SIXTEEN_PLUS"})
        self.assertEqual(report["finalTerritoryRatings"]["USA"], "SIXTEEN_PLUS")
        # Regional mappings need not literally be sixteen (Korea is fifteen).
        self.assertEqual(report["finalTerritoryRatings"]["KOR"], "FIFTEEN_PLUS")
        self.assertFalse(report["mutationOutcomeUnknown"])
        self.assertFalse(report["submissionAttempted"])
        first_patch = next(i for i, call in enumerate(session.calls) if call[0] == "PATCH")
        self.assertTrue(any(call[1].endswith(age.DECLARATION_READ) for call in session.calls[:first_patch]))
        for method, url, options in session.calls:
            self.assertIn(method, {"GET", "PATCH"})
            if method == "PATCH":
                self.assertEqual(url, age.ORIGIN + age.DECLARATION_WRITE)
            self.assertIs(options["allow_redirects"], False)
            self.assertEqual(options["timeout"], 30)

    def test_idempotent_rerun_of_completed_sixteen_declaration_writes_nothing(self):
        session = Session(complete=True, override="SIXTEEN_PLUS")
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(session.patch_bodies, [])
        self.assertEqual(report["overrideDecision"], "preserved_existing_override")

    def test_higher_computed_rating_is_preserved_without_override_write(self):
        ratings = {"USA": "EIGHTEEN_PLUS", "BRA": "EIGHTEEN_PLUS", "KOR": "NINETEEN_PLUS"}
        session = Session(calculated_ratings=ratings)
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(session.patch_bodies), 1)
        self.assertEqual(report["finalTerritoryRatings"], ratings)
        self.assertEqual(report["finalDeclaration"]["options"]["ageRatingOverrideV2"], "NONE")

    def test_existing_higher_override_is_not_lowered(self):
        ratings = {"USA": "EIGHTEEN_PLUS", "KOR": "NINETEEN_PLUS"}
        session = Session(override="EIGHTEEN_PLUS", initial_ratings=ratings, calculated_ratings=ratings)
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(session.patch_bodies), 1)
        self.assertEqual(session.attrs["ageRatingOverrideV2"], "EIGHTEEN_PLUS")

    def test_identity_and_relationship_mismatches_prevent_every_write(self):
        changes = [
            lambda s: s.app.update(id="other-app"),
            lambda s: s.app["attributes"].update(bundleId="other.bundle"),
            lambda s: s.version.update(id="other-version"),
            lambda s: s.version["attributes"].update(versionString="2.0.0"),
            lambda s: s.version["attributes"].update(platform="MAC_OS"),
            lambda s: s.version["attributes"].update(appVersionState="WAITING_FOR_REVIEW"),
            lambda s: s.info.update(id="other-app-info"),
            lambda s: s.info["attributes"].update(state="WAITING_FOR_REVIEW"),
            lambda s: s.info["relationships"]["ageRatingDeclaration"]["data"].update(id="other-declaration"),
            lambda s: setattr(s, "declaration_id", "other-declaration"),
            lambda s: s.version["relationships"].update(app={"data": {"type": "apps", "id": "other-app"}}),
        ]
        for change in changes:
            with self.subTest(change=change):
                session = Session()
                change(session)
                report = execute(session)
                self.assertFalse(report["success"])
                self.assertEqual(session.patch_bodies, [])

    def test_unknown_declaration_enum_or_boolean_prevents_every_write(self):
        for field, value in [("violenceRealistic", "PRIVATE_UNKNOWN_ENUM_SECRET"),
                             ("ageRatingOverrideV2", "PRIVATE_UNKNOWN_OVERRIDE_SECRET"),
                             ("gambling", 1), ("healthOrWellnessTopics", "false")]:
            with self.subTest(field=field):
                session = Session()
                session.attrs[field] = value
                report = execute(session)
                self.assertFalse(report["success"])
                self.assertEqual(session.patch_bodies, [])
                self.assertNotIn("SECRET", json.dumps(report))

    def test_unknown_initial_rating_prevents_every_write_without_exporting_its_value(self):
        session = Session(initial_ratings={"USA": "PRIVATE_UNKNOWN_RATING_SECRET"})
        report = execute(session)
        self.assertFalse(report["success"])
        self.assertEqual(report["failureCode"], "rating_enum_unknown")
        self.assertEqual(session.patch_bodies, [])
        self.assertNotIn("SECRET", json.dumps(report))

    def test_unknown_post_patch_rating_stops_before_override(self):
        session = Session(calculated_ratings={"USA": "NEW_RATING_SECRET"})
        report = execute(session)
        self.assertFalse(report["success"])
        self.assertTrue(report["descriptorsVerified"])
        self.assertEqual(len(session.patch_bodies), 1)
        self.assertEqual(report["failureCode"], "rating_enum_unknown")
        self.assertNotIn("SECRET", json.dumps(report))

    def test_unrated_is_preserved_and_never_changed_to_sixteen(self):
        for session in [Session(override="UNRATED"), Session(initial_ratings={"USA": "UNRATED"})]:
            report = execute(session)
            self.assertFalse(report["success"])
            self.assertEqual(session.patch_bodies, [])
            self.assertEqual(report["failureCode"], "unrated_preserved_no_mutation")

    def test_unset_post_patch_ratings_get_bounded_read_only_rechecks(self):
        session = Session(calculated_ratings={"USA": None})
        pauses = []
        report = age.run(session, lambda: {}, pause=pauses.append)
        self.assertFalse(report["success"])
        self.assertEqual(len(session.patch_bodies), 1)
        self.assertEqual(pauses, [1, 1])
        self.assertEqual(report["failureCode"], "rating_readback_unconfirmed")

    def test_higher_rating_appearing_before_override_is_preserved(self):
        session = Session()
        session.ratings_sequences = [
            {"USA": None},
            {"USA": "THIRTEEN_PLUS"},
            {"USA": "EIGHTEEN_PLUS"},
        ]
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(session.patch_bodies), 1)
        self.assertEqual(report["finalTerritoryRatings"]["USA"], "EIGHTEEN_PLUS")

    def test_override_cannot_silently_reduce_a_higher_regional_rating(self):
        session = Session(
            calculated_ratings={"USA": "THIRTEEN_PLUS", "KOR": "NINETEEN_PLUS"},
            overridden_ratings={"USA": "SIXTEEN_PLUS", "KOR": "FIFTEEN_PLUS"})
        report = execute(session)
        self.assertFalse(report["success"])
        self.assertEqual(len(session.patch_bodies), 2)
        self.assertEqual(report["failureCode"], "rating_readback_unconfirmed")
        self.assertNotIn("finalTerritoryRatings", report)

    def test_narrow_mutator_refuses_unverified_unreviewed_or_unjustified_writes(self):
        session, report = Session(), age.new_report()
        api = age.AppleAgeCompletion(session, lambda: {}, report)
        with self.assertRaises(age.CompletionStop):
            api.patch("descriptors", dict(age.REVIEWED_ATTRIBUTES))
        api.verify_scope()
        api.declaration()
        for kind, attrs in [
            ("release", {"releaseType": "MANUAL"}),
            ("descriptors", {**age.REVIEWED_ATTRIBUTES, "kidsAgeBand": None}),
            ("descriptors", {**age.REVIEWED_ATTRIBUTES, "gambling": 0}),
            ("override", {"ageRatingOverrideV2": "SIXTEEN_PLUS"}),
        ]:
            with self.subTest(kind=kind):
                with self.assertRaises(age.CompletionStop):
                    api.patch(kind, attrs)
        self.assertEqual(session.patch_bodies, [])

    def test_each_patch_kind_is_attempted_at_most_once_even_on_transport_failure(self):
        session, report = Session(), age.new_report()
        api = age.AppleAgeCompletion(session, lambda: {}, report)
        api.verify_scope()
        api.declaration()
        session.patch_failure = RuntimeError("PRIVATE_TRANSPORT_SECRET")
        for _ in range(2):
            with self.assertRaises(age.CompletionStop):
                api.patch("descriptors", dict(age.REVIEWED_ATTRIBUTES))
        self.assertEqual(len(session.patch_bodies), 1)

    def test_incomplete_app_list_and_unsafe_pagination_prevent_writes(self):
        sessions = [Session() for _ in range(4)]
        sessions[0].list_next = "https://untrusted.invalid/PRIVATE_URL_SECRET"
        sessions[1].next_url = "https://untrusted.invalid/PRIVATE_URL_SECRET"
        sessions[2].next_url = age.ORIGIN + "/v1/apps/other/territoryAgeRatings?limit=200&cursor=x"
        sessions[3].next_url = age.ORIGIN + age.TERRITORY_PATH + "?limit=200&include=app&cursor=x"
        for session in sessions:
            report = execute(session)
            self.assertFalse(report["success"])
            self.assertEqual(session.patch_bodies, [])
            self.assertFalse(any("untrusted" in call[1] for call in session.calls))
            self.assertNotIn("PRIVATE_URL_SECRET", json.dumps(report))

    def test_valid_territory_pagination_stays_on_the_exact_scoped_endpoint(self):
        session = Session()
        session.paginate = True
        report = execute(session)
        self.assertTrue(report["success"], report)
        self.assertEqual(set(report["finalTerritoryRatings"]), {"USA", "BRA", "KOR"})
        cursor_calls = [call for call in session.calls if "cursor=" in call[1]]
        self.assertTrue(cursor_calls)
        for call in cursor_calls:
            self.assertTrue(call[1].startswith(age.ORIGIN + age.TERRITORY_PATH + "?limit=200&include=territory&cursor="))

    def test_failed_or_mismatched_patch_never_leads_to_an_override(self):
        sessions = [Session(), Session(), Session()]
        sessions[0].reject_patch = True
        sessions[1].ignore_descriptor = True
        sessions[2].patch_failure = RuntimeError("PRIVATE_TRANSPORT_SECRET")
        for session in sessions:
            report = execute(session)
            self.assertFalse(report["success"])
            self.assertEqual(len(session.patch_bodies), 1)
            self.assertTrue(report["mutationOutcomeUnknown"])
            self.assertNotIn("SECRET", json.dumps(report))

    def test_artifacts_never_contain_auth_review_contact_urls_or_raw_errors(self):
        report = execute(Session())
        self.assertNotIn("SECRET", json.dumps(report))
        session = Session()
        session.get_failure = RuntimeError("PRIVATE_GET_SECRET")
        report = execute(session)
        self.assertFalse(report["success"])
        self.assertNotIn("SECRET", json.dumps(report))


if __name__ == "__main__":
    unittest.main()
