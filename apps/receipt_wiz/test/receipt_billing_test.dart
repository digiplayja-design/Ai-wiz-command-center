import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:korlix_receipt_wiz/receipt_billing.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
final binding = 'a' * 64;

class PlayStore extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <PurchaseParam>[];
  final completed = <PurchaseDetails>[];
  Set<String> requested = {};
  bool missing = false;
  String monthlyPrice = '€8,99';
  String? trialPeriod;
  bool catalogFailure = false;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    requested = ids;
    if (catalogFailure) throw StateError('Catalog unavailable');
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
                        if (trialPeriod != null)
                          SubscriptionOfferDetailsWrapper(
                            basePlanId: 'monthly',
                            offerId: 'trial-3-days',
                            offerTags: [],
                            offerIdToken: '$id-trial',
                            pricingPhases: [
                              PricingPhaseWrapper(
                                billingCycleCount: 1,
                                billingPeriod: trialPeriod!,
                                formattedPrice: 'Free',
                                priceAmountMicros: 0,
                                priceCurrencyCode: 'EUR',
                                recurrenceMode: RecurrenceMode.finiteRecurring,
                              ),
                              PricingPhaseWrapper(
                                billingCycleCount: 0,
                                billingPeriod: 'P1M',
                                formattedPrice: '€8,99',
                                priceAmountMicros: 8990000,
                                priceCurrencyCode: 'EUR',
                                recurrenceMode:
                                    RecurrenceMode.infiniteRecurring,
                              ),
                            ],
                          ),
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
                                formattedPrice: id == receiptFullProductId
                                    ? monthlyPrice
                                    : '€124,99',
                                priceAmountMicros: 8990000,
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
  bool enabled = true, verified = true, included = false, active = false;
  Completer<http.Response>? gate;
  Map<String, String> headers() => {
    'Authorization':
        'Bearer h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': user, 'session_id': 'session-$user'})))}.s',
  };
  http.Response response(Map<String, dynamic> body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);
  late final service = ReceiptBillingService(
    backendUrl: 'https://backend.fixture',
    headers: headers,
    sessionChanges: revision,
    store: store,
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/verify')) {
        if (gate != null) return gate!.future;
        if (!verified) return response({'error': 'Not verified'}, 503);
        active = true;
        return response({
          'verified': true,
          'active': true,
          'completePurchase': true,
        });
      }
      return response({
        'plan': {
          'name': included || active ? 'full' : 'free',
          'included': included,
        },
        'entitlement': {},
        'billingEnabled': enabled,
        'canPurchase': enabled && !included && !active,
        'accountId': binding,
      });
    }),
  );
  PurchaseDetails purchase({
    String sku = receiptFullProductId,
    PurchaseStatus status = PurchaseStatus.purchased,
  }) => PurchaseDetails(
    productID: sku,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'opaque-test-token',
      source: 'google_play',
    ),
    transactionDate: '1',
    status: status,
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
  androidTest('only the monthly Receipt Full product can open Google Play', (
    tester,
  ) async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.store.trialPeriod = 'P3D';
    await f.service.start();
    expect(f.store.requested, {receiptFullProductId});
    expect(f.service.price, '€8,99');
    await f.service.buy();
    final p = f.store.bought.single as GooglePlayPurchaseParam;
    expect(p.offerToken, 'receipt_wiz_full-monthly');
    expect(p.applicationUserName, binding);
    expect(f.service.full, isFalse);
  });
  androidTest(
    'disabled billing and already included Full never start another purchase',
    (tester) async {
      final f = Fixture()..enabled = false;
      addTearDown(f.dispose);
      await f.service.start();
      await f.service.buy();
      expect(f.store.bought, isEmpty);
      f.enabled = true;
      f.included = true;
      await f.service.refresh();
      await f.service.buy();
      expect(f.service.full, isTrue);
      expect(f.store.bought, isEmpty);
    },
  );
  androidTest('pending and unrelated products cannot grant Full', (
    tester,
  ) async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.service.start();
    f.store.updates.add([
      f.purchase(sku: 'korlix_pro'),
      f.purchase(status: PurchaseStatus.pending),
    ]);
    await tester.pump();
    expect(f.service.full, isFalse);
    expect(f.service.busy, isTrue);
    expect(f.store.completed, isEmpty);
    expect(f.requests.where((r) => r.url.path.endsWith('/verify')), isEmpty);
  });
  androidTest('only server verified purchases complete and unlock Full', (
    tester,
  ) async {
    final f = Fixture()..verified = false;
    addTearDown(f.dispose);
    await f.service.start();
    f.store.updates.add([f.purchase()]);
    await tester.pump();
    expect(f.service.full, isFalse);
    expect(f.store.completed, isEmpty);
    f.verified = true;
    f.store.updates.add([f.purchase(status: PurchaseStatus.restored)]);
    await tester.pump();
    expect(f.service.full, isTrue);
    expect(f.store.completed.length, 1);
  });
  androidTest(
    'switching KORLIX accounts invalidates an in flight verification',
    (tester) async {
      final f = Fixture()..gate = Completer<http.Response>();
      addTearDown(f.dispose);
      await f.service.start();
      f.store.updates.add([f.purchase()]);
      await tester.pump();
      f.user = other;
      f.revision.value++;
      f.gate!.complete(
        f.response({
          'verified': true,
          'active': true,
          'completePurchase': true,
        }),
      );
      await tester.pump();
      expect(f.service.full, isFalse);
      expect(f.service.readyToBuy, isFalse);
      expect(f.store.completed, isEmpty);
      await f.service.buy();
      expect(f.store.bought, isEmpty);
    },
  );
  androidTest('missing monthly offer leaves purchase disabled', (tester) async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.store.missing = true;
    await f.service.start();
    expect(f.service.readyToBuy, isFalse);
    await f.service.buy();
    expect(f.store.bought, isEmpty);
  });
}
