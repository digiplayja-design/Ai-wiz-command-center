import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/billing/korlix_apple_billing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
final binding = 'a' * 64;

class PlayStore extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <PurchaseParam>[];
  final completed = <PurchaseDetails>[];
  Set<String> requested = {};
  bool missing = false;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    requested = ids;
    return ProductDetailsResponse(
      productDetails: missing
          ? []
          : ids
                .expand(
                  (id) => GooglePlayProductDetails.fromProductDetails(
                    ProductDetailsWrapper(
                      productId: id,
                      productType: ProductType.subs,
                      title: id,
                      name: id,
                      description: 'Membership',
                      subscriptionOfferDetails: [
                        for (final base in ['annual', 'monthly'])
                          SubscriptionOfferDetailsWrapper(
                            basePlanId: base,
                            offerTags: [],
                            offerIdToken: '$id-$base',
                            pricingPhases: [
                              PricingPhaseWrapper(
                                billingCycleCount: 0,
                                billingPeriod: base == 'monthly'
                                    ? 'P1M'
                                    : 'P1Y',
                                formattedPrice:
                                    id == kKorlixGoogleProMonthlyProductId
                                    ? '€34,99'
                                    : '€124,99',
                                priceAmountMicros: 34990000,
                                priceCurrencyCode: 'EUR',
                                recurrenceMode:
                                    RecurrenceMode.infiniteRecurring,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                )
                .toList(),
      notFoundIDs: missing ? ids.toList() : [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    updates.add([]);
  }
}

class Fixture {
  final store = PlayStore();
  final revision = ValueNotifier(0);
  final requests = <http.Request>[];
  String user = owner;
  bool enabled = true;
  bool verified = true;
  Completer<http.Response>? verificationGate;
  Map<String, String> headers() => {
    'Authorization':
        'Bearer h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': user, 'session_id': 'session-$user'})))}.s',
  };
  http.Response response(Map<String, dynamic> body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);
  late final service = KorlixAppleBillingService.forTesting(
    store,
    MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/verify')) {
        if (verificationGate != null) return verificationGate!.future;
        return response(
          verified
              ? {
                  'verified': true,
                  'tier': 'pro',
                  'active': true,
                  'completePurchase': true,
                }
              : {'error': 'Not verified'},
          verified ? 200 : 503,
        );
      }
      return response({
        'tier': 'basic',
        'billingEnabled': enabled,
        'canPurchase': enabled,
        'accountId': binding,
        'webSubscriptionActive': false,
        'otherStoreSubscriptionActive': false,
      });
    }),
  );
  Future<void> configure() => service.configure(
    backendBaseUrl: 'https://backend.fixture',
    headersBuilder: headers,
    currentTier: 'basic',
    sessionChanges: revision,
  );
  PurchaseDetails purchase() => PurchaseDetails(
    productID: kKorlixGoogleProMonthlyProductId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'opaque-purchase-token',
      source: 'google_play',
    ),
    transactionDate: '1',
    status: PurchaseStatus.purchased,
  )..pendingCompletePurchase = true;
  void dispose() {
    service.dispose();
    revision.dispose();
    unawaited(store.updates.close());
  }
}

void androidTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: TargetPlatformVariant.only(TargetPlatform.android),
);

void main() {
  androidTest(
    'Android loads the Play catalog and monthly base plan, with store prices',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      expect(f.store.requested, kKorlixGoogleSubscriptionProductIds);
      expect(
        f.requests.every((r) => r.url.path.startsWith('/api/billing/google/')),
        isTrue,
      );
      final product =
          f.service.productFor(kKorlixGoogleProMonthlyProductId)
              as GooglePlayProductDetails;
      expect(product.offerToken, 'korlix_pro-monthly');
      expect(product.price, '€34,99');
      expect(f.service.canPurchase, isTrue);
    },
  );
  androidTest(
    'Basic upgrade prepares a bound account and launches Google Play with the selected offer',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      await f.service.purchase(kKorlixGoogleProMonthlyProductId);
      final param = f.store.bought.single as GooglePlayPurchaseParam;
      expect(param.applicationUserName, binding);
      expect(param.offerToken, 'korlix_pro-monthly');
      expect(param.changeSubscriptionParam, isNull);
      expect(jsonDecode(f.requests.last.body), {'productId': 'korlix_pro'});
    },
  );
  androidTest(
    'unconfigured billing or missing store products never launches a charge',
    (tester) async {
      final f = Fixture()..enabled = false;
      addTearDown(f.dispose);
      await f.configure();
      expect(f.service.message, contains('being set up'));
      await f.service.purchase(kKorlixGoogleProMonthlyProductId);
      expect(f.store.bought, isEmpty);
      f.enabled = true;
      f.store.missing = true;
      await f.service.refreshAll();
      await f.service.purchase(kKorlixGoogleProMonthlyProductId);
      expect(f.store.bought, isEmpty);
    },
  );
  androidTest(
    'Google tokens go to Google verification and only verified payments complete',
    (tester) async {
      final f = Fixture()..verified = false;
      addTearDown(f.dispose);
      await f.configure();
      f.store.updates.add([f.purchase()]);
      await tester.pump();
      expect(f.store.completed, isEmpty);
      expect(f.requests.last.url.path, '/api/billing/google/verify');
      final payload = jsonDecode(f.requests.last.body);
      expect(payload['source'], 'google_play');
      expect(payload['verificationData'], 'opaque-purchase-token');
      f.verified = true;
      f.store.updates.add([f.purchase()]);
      await tester.pump();
      expect(f.store.completed, hasLength(1));
      expect(f.service.currentTier, 'pro');
    },
  );
  androidTest(
    'switching Basic profiles while verification runs cannot apply or finish another account purchase',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      f.verificationGate = Completer<http.Response>();
      f.store.updates.add([f.purchase()]);
      await tester.pump();
      f.user = other;
      f.revision.value++;
      f.verificationGate!.complete(
        f.response({'verified': true, 'tier': 'pro', 'active': true}),
      );
      await tester.pump();
      expect(f.store.completed, isEmpty);
      expect(f.service.currentTier, 'basic');
      expect(f.service.canPurchase, isFalse);
    },
  );
  androidTest(
    'Android paywall displays Google Play and has no Apple-only unavailable message',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showKorlixAppleSubscriptionSheet(
                  context: context,
                  backendBaseUrl: 'https://backend.fixture',
                  headersBuilder: f.headers,
                  currentTier: 'basic',
                  billingService: f.service,
                  sessionChanges: f.revision,
                ),
                child: const Text('Plans'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      expect(
        find.text('Secure subscriptions through Google Play'),
        findsOneWidget,
      );
      expect(find.textContaining('Apple subscription purchases'), findsNothing);
      expect(find.text('€34,99 / month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
