import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/billing/korlix_apple_billing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';

class Store extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  final bought = <PurchaseParam>[];
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> ids,
  ) async => ProductDetailsResponse(
    productDetails: ids
        .map(
          (id) => ProductDetails(
            id: id,
            title: id,
            description: 'Monthly membership',
            price: id == kKorlixAppleProMonthlyProductId ? '€34,99' : '€124,99',
            rawPrice: id == kKorlixAppleProMonthlyProductId ? 34.99 : 124.99,
            currencyCode: 'EUR',
          ),
        )
        .toList(),
    notFoundIDs: const [],
  );
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam);
    return true;
  }
}

PurchaseDetails purchase({
  String id = 'one',
  String productId = kKorlixAppleProMonthlyProductId,
}) => PurchaseDetails(
  purchaseID: id,
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'signed-data',
    source: 'app_store',
  ),
  transactionDate: '1',
  status: PurchaseStatus.restored,
)..pendingCompletePurchase = true;

class Fixture {
  final store = Store();
  final revision = ValueNotifier(0);
  final callbacks = <String>[];
  final requests = <http.Request>[];
  String user = owner;
  String tier = 'basic';
  Completer<http.Response>? gate;
  bool verificationSucceeds = true;
  Map<String, String> headers() => {
    'Authorization':
        'Bearer h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': user, 'session_id': 'session-$user'})))}.s',
  };
  http.Response response(Map<String, dynamic> value, [int code = 200]) =>
      http.Response(jsonEncode(value), code);
  late final service = KorlixAppleBillingService.forTesting(
    store,
    MockClient((request) async {
      requests.add(request);
      if (gate != null) return gate!.future;
      if (request.method == 'POST') {
        return response(
          verificationSucceeds
              ? {
                  'verified': true,
                  'tier': 'pro',
                  'active': true,
                  'status': 'active',
                }
              : {'error': 'Verification unavailable.'},
          verificationSucceeds ? 200 : 503,
        );
      }
      return response({
        'tier': tier,
        'entitlement': null,
        'webSubscriptionActive': false,
      });
    }),
  );
  Future<void> configure() => service.configure(
    backendBaseUrl: 'https://backend.fixture',
    headersBuilder: headers,
    currentTier: 'basic',
    onTierChanged: callbacks.add,
    sessionChanges: revision,
  );
  void dispose() {
    service.dispose();
    unawaited(store.updates.close());
    revision.dispose();
  }
}

void nativeTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

void main() {
  nativeTestWidgets(
    'restore with no purchases ends and offers a clear result',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      await f.service.restorePurchases();
      expect(f.service.busy, isTrue);
      f.store.updates.add([]);
      await tester.pump();
      expect(f.service.busy, isFalse);
      expect(f.service.message, contains('No restorable'));
    },
  );

  nativeTestWidgets('restore cannot leave the paywall disabled indefinitely', (
    tester,
  ) async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.configure();
    await f.service.restorePurchases();
    await tester.pump(const Duration(seconds: 61));
    expect(f.service.busy, isFalse);
    expect(f.service.error, contains('taking longer'));
  });

  nativeTestWidgets(
    'account switch rejects late private status and tier callback',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      f.callbacks.clear();
      f.gate = Completer<http.Response>();
      final pending = f.service.refreshStatus();
      f.user = other;
      f.revision.value++;
      f.gate!.complete(
        f.response({
          'tier': 'ultra',
          'entitlement': {'transaction_id': 'private-owner-transaction'},
        }),
      );
      await pending;
      expect(f.service.currentTier, 'basic');
      expect(f.service.entitlement, isNull);
      expect(f.callbacks, isEmpty);
      expect(f.service.checkingStatus, isFalse);
    },
  );

  nativeTestWidgets(
    'account switch during verification never completes or applies old purchase',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      f.callbacks.clear();
      f.gate = Completer<http.Response>();
      f.store.updates.add([purchase()]);
      await tester.pump();
      expect(f.requests.last.method, 'POST');
      f.user = other;
      f.revision.value++;
      f.gate!.complete(
        f.response({'verified': true, 'tier': 'pro', 'active': true}),
      );
      await tester.pump();
      expect(f.store.completed, isEmpty);
      expect(f.service.currentTier, 'basic');
      expect(f.callbacks, isEmpty);
    },
  );

  nativeTestWidgets(
    'purchase batches verify serially and finish only after server verification',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      f.gate = Completer<http.Response>();
      f.store.updates.add([purchase(id: 'one')]);
      f.store.updates.add([purchase(id: 'two')]);
      await tester.pump();
      expect(f.requests.where((r) => r.method == 'POST').length, 1);
      expect(f.store.completed, isEmpty);
      final gate = f.gate!;
      f.gate = null;
      gate.complete(
        f.response({'verified': true, 'tier': 'pro', 'active': true}),
      );
      await tester.pump();
      expect(f.store.completed.map((p) => p.purchaseID), ['one', 'two']);
      expect(f.service.currentTier, 'pro');
      expect(f.service.busy, isFalse);
    },
  );

  nativeTestWidgets(
    'failed verification leaves purchase recoverable by restore',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      f.verificationSucceeds = false;
      f.store.updates.add([purchase()]);
      await tester.pump();
      expect(f.store.completed, isEmpty);
      expect(f.service.currentTier, 'basic');
      expect(f.service.error, contains('Restore Purchases'));
      f.verificationSucceeds = true;
      await f.service.restorePurchases();
      f.store.updates.add([purchase()]);
      await tester.pump();
      expect(f.store.completed, hasLength(1));
      expect(f.service.currentTier, 'pro');
    },
  );

  nativeTestWidgets(
    'purchases bind the account UUID and a stream failure recovers the controls',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.configure();
      await f.service.purchase(kKorlixAppleProMonthlyProductId);
      expect(f.store.bought.single.applicationUserName, owner);
      expect(f.service.busy, isTrue);
      f.store.updates.addError(StateError('transport failure'));
      await tester.pump();
      expect(f.service.busy, isFalse);
      expect(f.service.error, contains('Restore Purchases'));
    },
  );

  nativeTestWidgets(
    'an organization membership prevents an unnecessary personal purchase',
    (tester) async {
      final f = Fixture()..tier = 'enterprise';
      addTearDown(f.dispose);
      await f.configure();
      await f.service.purchase(kKorlixAppleProMonthlyProductId);
      expect(f.store.bought, isEmpty);
      expect(f.service.currentTier, 'enterprise');
      expect(f.service.error, contains('No additional subscription'));
    },
  );

  nativeTestWidgets(
    'native paywall shows localized monthly prices, restore and legal links at large text',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.gate = Completer<http.Response>();
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  unawaited(
                    showKorlixAppleSubscriptionSheet(
                      context: context,
                      backendBaseUrl: 'https://backend.fixture',
                      headersBuilder: f.headers,
                      currentTier: 'basic',
                      sessionChanges: f.revision,
                      billingService: f.service,
                    ),
                  );
                },
                child: const Text('Plans'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plans'));
      await tester.pump();
      expect(find.text('Korlix Plans'), findsOneWidget);
      expect(f.service.checkingStatus, isTrue);
      f.gate!.complete(
        f.response({'tier': 'basic', 'webSubscriptionActive': false}),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('€34,99 / month'), 400);
      expect(find.text('€34,99 / month'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Restore Purchases'), 400);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Privacy Policy'), 400);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
