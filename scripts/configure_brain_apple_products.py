#!/usr/bin/env python3
"""Create only the approved Brain+Voice Apple product metadata and US prices.

Uses the existing Codemagic App Store Connect integration. No credentials are
exported. Does not submit review, enable billing, alter access, or create offers.
Read-only by default; --apply is required for the approved catalog writes.
"""

import argparse
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import re
from urllib.parse import urlparse

APP_ID = "6829319523"
BUNDLE_ID = "com.korlix.brain"
GROUP_NAME = "KORLIX Brain+Voice"
APPROVED = {
    "com.korlix.brain.monthly": (3499, 3600, "auto_renewable_subscription"),
    "com.korlix.brain.ai_gas.1h": (3000, 3600, "consumable"),
    "com.korlix.brain.ai_gas.2h": (5500, 7200, "consumable"),
    "com.korlix.brain.ai_gas.3h": (8000, 10800, "consumable"),
}
ROOT = Path(__file__).resolve().parents[1]


def approved_catalog():
    catalog = json.loads((ROOT / "apps/korlix_brain/store/billing-products.json").read_text())
    actual = {p["appleId"]: (p["usdCents"], p["liveSeconds"], p["type"])
              for p in catalog["products"]}
    if (catalog["bundleId"] != BUNDLE_ID or catalog["appleAppId"] != APP_ID
            or catalog["currency"] != "USD" or actual != APPROVED
            or len(catalog["products"]) != 4):
        raise ValueError("Catalog differs from the four approved Brain+Voice products")
    monthly = catalog["products"][0]
    if monthly.get("period") != "P1M" or monthly.get("rollover") is not False:
        raise ValueError("Monthly period or rollover differs from approval")
    if any(p.get("expires") is not False for p in catalog["products"][1:]):
        raise ValueError("AI GAS must not expire")
    return catalog["products"]


def unique(items, predicate, label):
    found = [item for item in items if predicate(item)]
    if len(found) > 1:
        raise ValueError(f"Ambiguous {label}; no changes made to it")
    return found[0] if found else None


def price_point(points, cents):
    target = Decimal(cents) / 100
    point = unique(points, lambda p: Decimal(p["attributes"]["customerPrice"]) == target,
                   f"exact USD {target} price point")
    if point is None:
        raise ValueError(f"Apple does not expose exact USD {target}; no substitute selected")
    return point


def relation(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def iap_price_body(identifier, point_id):
    return {
        "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
            "inAppPurchase": relation("inAppPurchases", identifier),
            "baseTerritory": relation("territories", "USA"),
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price1}"}]},
        }},
        "included": [{"type": "inAppPurchasePrices", "id": "${price1}",
            "attributes": {"startDate": None, "endDate": None},
            "relationships": {
                "inAppPurchaseV2": relation("inAppPurchases", identifier),
                "inAppPurchasePricePoint": relation("inAppPurchasePricePoints", point_id),
            }}],
    }


class Apple:
    def __init__(self, session, apply=False, auth_headers=None):
        self.session, self.apply = session, apply
        self.auth_headers = auth_headers or (lambda: {})

    @staticmethod
    def url(path):
        url = path if path.startswith("https://") else "https://api.appstoreconnect.apple.com" + path
        parsed = urlparse(url)
        if (parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com"
                or not re.match(r"^/v[12]/", parsed.path) or parsed.username or parsed.fragment):
            raise ValueError("Unexpected Apple API URL")
        return url

    def request(self, method, path, params=None, body=None, allow_missing=False):
        if method == "POST" and not self.apply:
            raise ValueError("Catalog write requires --apply")
        # Never retry POST automatically: a network timeout may mean it committed.
        response = self.session.request(method, self.url(path), params=params, json=body,
                                        headers=self.auth_headers(), timeout=60, allow_redirects=False)
        if allow_missing and response.status_code == 404:
            return None
        expected = 201 if method == "POST" else 200
        if response.status_code != expected:
            # Do not emit request headers, signed tokens, credentials or full bodies.
            codes = []
            try:
                codes = [re.sub(r"[^A-Z0-9_.-]", "", e.get("code", ""))[:100]
                         for e in response.json().get("errors", [])]
            except (ValueError, AttributeError):
                pass
            raise RuntimeError(f"Apple {method} {urlparse(self.url(path)).path}: "
                               f"HTTP {response.status_code}; codes={codes}")
        return response.json()

    def get(self, path, **params):
        return self.request("GET", path, params=params)

    def all(self, path, **params):
        output, visited = [], set()
        while path:
            if path in visited or len(visited) > 100:
                raise ValueError("Unexpected Apple pagination loop")
            visited.add(path)
            result = self.get(path, **params)
            if not isinstance(result.get("data"), list):
                raise ValueError("Apple returned a non-list resource collection")
            output.extend(result["data"])
            path = result.get("links", {}).get("next")
            params = {}
        return output

    def create(self, path, kind, attrs=None, relationships=None):
        data = {"type": kind}
        if attrs is not None:
            data["attributes"] = attrs
        if relationships is not None:
            data["relationships"] = relationships
        return self.request("POST", path, body={"data": data})["data"]


def localization(api, list_path, create_path, kind, parent_name, parent_type, parent_id, attrs):
    if len(attrs.get("name", "")) > 30 or len(attrs.get("description", "")) > 55:
        raise ValueError("Apple localization exceeds its name/description character limit")
    existing = unique(api.all(list_path), lambda r: r["attributes"]["locale"] == "en-US", kind)
    if existing:
        if any(existing["attributes"].get(k) != v for k, v in attrs.items()):
            raise ValueError(f"Existing {kind} differs; retained without overwriting")
        return existing
    return api.create(create_path, kind, {"locale": "en-US", **attrs},
                      {parent_name: relation(parent_type, parent_id)})


def ensure_us_availability(api, identifier, subscription=False):
    """Prepare the approved USD storefront without changing app release regions.

    Apple's UPFRONT means pay for the full ONE_MONTH period. MONTHLY here means
    a 12-month commitment paid in installments, which the user did not approve.
    """
    if subscription:
        options = api.all(f"/v1/subscriptions/{identifier}/planAvailabilities", limit=200)
        current = unique(options, lambda p: p["attributes"]["planType"] == "UPFRONT", "upfront plan availability")
        kind, parent, parent_type = "subscriptionPlanAvailabilities", "subscription", "subscriptions"
        attrs = {"planType": "UPFRONT", "availableInNewTerritories": False}
    else:
        result = api.request("GET", f"/v2/inAppPurchases/{identifier}/inAppPurchaseAvailability", allow_missing=True)
        current = result.get("data") if result else None
        kind, parent, parent_type = "inAppPurchaseAvailabilities", "inAppPurchase", "inAppPurchases"
        attrs = {"availableInNewTerritories": False}
    if current is None:
        current = api.create(f"/v1/{kind}", kind, attrs, {
            parent: relation(parent_type, identifier),
            "availableTerritories": {"data": [{"type": "territories", "id": "USA"}]},
        })
    territories = api.all(f"/v1/{kind}/{current['id']}/availableTerritories", limit=200)
    if "USA" not in {r["id"] for r in territories}:
        raise ValueError("Existing product availability excludes USA; retained without overwriting")
    return {"usAvailable": True, "planType": "UPFRONT" if subscription else None}


def ensure_price(api, item, cents, subscription=False):
    identifier = item["id"]
    if subscription:
        base = f"/v1/subscriptions/{identifier}"
        point_kind, relation_name = "subscriptionPricePoints", "subscriptionPricePoint"
    else:
        base = f"/v2/inAppPurchases/{identifier}"
        point_kind, relation_name = "inAppPurchasePricePoints", "inAppPurchasePricePoint"
    points = api.all(base + "/pricePoints", **{"filter[territory]": "USA", "limit": 8000})
    point = price_point(points, cents)
    if subscription:
        price_path = base + "/prices"
    else:
        schedule = api.request("GET", base + "/iapPriceSchedule", allow_missing=True)
        price_path = (f"/v1/inAppPurchasePriceSchedules/{schedule['data']['id']}/manualPrices"
                      if schedule and schedule.get("data") else None)
    filters = {"filter[territory]": "USA", "include": relation_name, "limit": 200}
    if subscription:
        filters["filter[planType]"] = "UPFRONT"
    existing = api.all(price_path, **filters) if price_path else []
    if existing:
        # Refuse to change an existing price or introduce a future price schedule.
        if len(existing) != 1 or existing[0]["relationships"][relation_name]["data"]["id"] != point["id"]:
            raise ValueError("Existing US price schedule differs; no price change made")
    elif subscription:
        api.create("/v1/subscriptionPrices", "subscriptionPrices", {"startDate": None, "planType": "UPFRONT"}, {
            "subscription": relation("subscriptions", identifier),
            "subscriptionPricePoint": relation(point_kind, point["id"]),
        })
    else:
        api.request("POST", "/v1/inAppPurchasePriceSchedules", body=iap_price_body(identifier, point["id"]))
    # Verify the exact persisted relationship, not only the create response.
    if not subscription:
        schedule = api.get(base + "/iapPriceSchedule")["data"]
        price_path = f"/v1/inAppPurchasePriceSchedules/{schedule['id']}/manualPrices"
    saved = api.all(price_path, **filters)
    if len(saved) != 1 or saved[0]["relationships"][relation_name]["data"]["id"] != point["id"]:
        raise ValueError("US price persistence verification failed")
    return {"territory": "USA", "currency": "USD", "price": str(Decimal(cents) / 100),
            "pricePointId": point["id"], "verified": True}


def run(api):
    catalog = approved_catalog()
    app = api.get(f"/v1/apps/{APP_ID}")["data"]
    if app["id"] != APP_ID or app["attributes"]["bundleId"] != BUNDLE_ID:
        raise ValueError("Wrong Apple app; no catalog writes permitted")
    groups = api.all(f"/v1/apps/{APP_ID}/subscriptionGroups", limit=200)
    subscriptions = []
    for group in groups:
        subscriptions.extend(api.all(f"/v1/subscriptionGroups/{group['id']}/subscriptions", limit=200))
    consumables = api.all(f"/v1/apps/{APP_ID}/inAppPurchasesV2", limit=200)
    report = {"appId": APP_ID, "bundleId": BUNDLE_ID, "apply": api.apply,
              "checkedAt": datetime.now(timezone.utc).isoformat(),
              "products": [], "publicSubmission": False, "billingEnabled": False,
              "remaining": ["Non-US availability and subscription prices", "IAP review screenshots",
                            "Native sandbox purchase tests", "First products with app-version review"]}
    if not api.apply:
        report["inventory"] = [{"id": r["id"], "productId": r["attributes"].get("productId"),
                                "state": r["attributes"].get("state")}
                               for r in subscriptions + consumables]
        return report
    monthly = catalog[0]
    sub = unique(subscriptions, lambda r: r["attributes"]["productId"] == monthly["appleId"], "monthly product")
    if sub is None:
        group = unique(groups, lambda r: r["attributes"]["referenceName"] == GROUP_NAME, "subscription group")
        if group is None:
            group = api.create("/v1/subscriptionGroups", "subscriptionGroups", {"referenceName": GROUP_NAME},
                               {"app": relation("apps", APP_ID)})
        localization(api, f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations",
                     "/v1/subscriptionGroupLocalizations", "subscriptionGroupLocalizations",
                     "subscriptionGroup", "subscriptionGroups", group["id"], {"name": GROUP_NAME})
        sub = api.create("/v1/subscriptions", "subscriptions", {
            "name": monthly["name"], "productId": monthly["appleId"],
            "subscriptionPeriod": "ONE_MONTH", "familySharable": False, "groupLevel": 1,
            "reviewNote": "USD 34.99 monthly. Personal Brain, Train My AI, and 60 Live minutes each billing period. "
                          "Included minutes do not roll over. AI GAS is separate; no free trial. Deep Think uses existing account limits.",
        }, {"group": relation("subscriptionGroups", group["id"])})
    if sub["attributes"].get("subscriptionPeriod") != "ONE_MONTH" or sub["attributes"].get("familySharable"):
        raise ValueError("Existing subscription period or family sharing differs")
    localization(api, f"/v1/subscriptions/{sub['id']}/subscriptionLocalizations",
                 "/v1/subscriptionLocalizations", "subscriptionLocalizations", "subscription", "subscriptions",
                 sub["id"], {"name": "Brain+Voice Monthly", "description": "Brain, training and 60 Live minutes each month."})
    report["products"].append({"productId": monthly["appleId"], "id": sub["id"],
                               "availability": ensure_us_availability(api, sub["id"], True),
                               "price": ensure_price(api, sub, monthly["usdCents"], True)})
    for product in catalog[1:]:
        item = unique(consumables, lambda r: r["attributes"]["productId"] == product["appleId"], "AI GAS product")
        minutes = product["liveSeconds"] // 60
        name = f"AI GAS - {minutes} Live Minutes"
        if item is None:
            item = api.create("/v2/inAppPurchases", "inAppPurchases", {
                "name": name, "productId": product["appleId"], "inAppPurchaseType": "CONSUMABLE",
                "familySharable": False,
                "reviewNote": f"One-time purchase of {minutes} Live Conversation minutes. "
                              "Minutes do not expire. Included monthly minutes are used first. "
                              "Server verifies the transaction and grants once. Deep Think has separate account limits.",
            }, {"app": relation("apps", APP_ID)})
        if item["attributes"]["inAppPurchaseType"] != "CONSUMABLE":
            raise ValueError("AI GAS product exists with a non-consumable type")
        localization(api, f"/v2/inAppPurchases/{item['id']}/inAppPurchaseLocalizations",
                     "/v1/inAppPurchaseLocalizations", "inAppPurchaseLocalizations", "inAppPurchaseV2",
                     "inAppPurchases", item["id"], {"name": name,
                     "description": f"Add {minutes} Live minutes with Rici. Minutes never expire."})
        report["products"].append({"productId": product["appleId"], "id": item["id"],
                                   "availability": ensure_us_availability(api, item["id"]),
                                   "price": ensure_price(api, item, product["usdCents"])})
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("artifacts/brain-apple-products.json"))
    args = parser.parse_args()
    from codemagic.apple.app_store_connect import AppStoreConnectApiClient
    from codemagic.tools.app_store_connect.arguments import Types
    import requests
    client = AppStoreConnectApiClient(
        key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
        issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
        private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
        log_requests=False, enable_jwt_cache=False)
    # A plain Session avoids the CLI's failed-request audit files and automatic
    # retries. Auth stays in memory and is refreshed by the existing integration.
    with requests.Session() as session:
        report = run(Apple(session, apply=args.apply, auth_headers=client.generate_auth_headers))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
