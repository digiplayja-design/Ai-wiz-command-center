import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "configure_brain_apple_products.py"
spec = importlib.util.spec_from_file_location("brain_apple_products", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppleProductTests(unittest.TestCase):
    def test_catalog_is_exactly_the_four_approved_products(self):
        catalog = module.approved_catalog()
        self.assertEqual([p["usdCents"] for p in catalog], [3499, 3000, 5500, 8000])
        self.assertEqual([p["liveSeconds"] for p in catalog], [3600, 3600, 7200, 10800])

    def test_nearby_price_is_never_substituted(self):
        with self.assertRaisesRegex(ValueError, "no substitute"):
            module.price_point([{"id": "near", "attributes": {"customerPrice": "29.99"}}], 3000)
        point = {"id": "exact", "attributes": {"customerPrice": "30.00"}}
        self.assertIs(module.price_point([point], 3000), point)

    def test_duplicate_price_points_stop(self):
        point = {"id": "exact", "attributes": {"customerPrice": "30.00"}}
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            module.price_point([point, point], 3000)

    def test_credentials_cannot_follow_external_pagination_or_redirects(self):
        for url in ["https://example.com/v1/apps", "http://api.appstoreconnect.apple.com/v1/apps",
                    "https://api.appstoreconnect.apple.com.evil.example/v1/apps",
                    "https://user@api.appstoreconnect.apple.com/v1/apps"]:
            with self.assertRaises(ValueError):
                module.Apple.url(url)

    def test_read_only_mode_blocks_writes_before_network(self):
        with self.assertRaisesRegex(ValueError, "requires --apply"):
            module.Apple(None).create("/v1/subscriptions", "subscriptions")

    def test_wrong_app_stops_before_catalog_writes(self):
        class WrongApp:
            def get(self, path):
                return {"data": {"id": module.APP_ID, "attributes": {"bundleId": "com.other.app"}}}
        with self.assertRaisesRegex(ValueError, "Wrong Apple app"):
            module.run(WrongApp())

    def test_oversize_localization_is_rejected_before_network(self):
        with self.assertRaisesRegex(ValueError, "character limit"):
            module.localization(None, "", "", "", "", "", "", {"description": "x" * 56})

    def test_missing_schedule_is_readable_without_hiding_auth_failure(self):
        class Response:
            status_code = 404
            def json(self):
                return {"errors": [{"code": "NOT_FOUND"}]}
        class Session:
            def request(self, *args, **kwargs):
                self.kwargs = kwargs
                return Response()
        session = Session()
        api = module.Apple(session)
        self.assertIsNone(api.request("GET", "/v2/inAppPurchases/1/iapPriceSchedule", allow_missing=True))
        self.assertIs(session.kwargs["allow_redirects"], False)
        Response.status_code = 401
        with self.assertRaisesRegex(RuntimeError, "HTTP 401"):
            api.request("GET", "/v2/inAppPurchases/1/iapPriceSchedule", allow_missing=True)

    def test_price_schedule_uses_one_USA_manual_price(self):
        body = module.iap_price_body("iap-id", "point-id")
        self.assertEqual(body["data"]["relationships"]["baseTerritory"]["data"]["id"], "USA")
        self.assertEqual(len(body["included"]), 1)
        self.assertEqual(body["included"][0]["attributes"], {"startDate": None, "endDate": None})
        self.assertEqual(body["included"][0]["relationships"]["inAppPurchasePricePoint"]["data"]["id"], "point-id")

    def test_regular_monthly_plan_does_not_create_twelve_month_commitment(self):
        class Api:
            def all(self, path, **params):
                return [{"id": "USA"}] if path.endswith("/availableTerritories") else []
            def create(self, path, kind, attrs, relationships):
                self.attrs, self.relationships = attrs, relationships
                return {"id": "availability"}
        api = Api()
        module.ensure_us_availability(api, "subscription", True)
        self.assertEqual(api.attrs["planType"], "UPFRONT")
        self.assertEqual(api.relationships["availableTerritories"]["data"], [{"type": "territories", "id": "USA"}])


if __name__ == "__main__":
    unittest.main()
