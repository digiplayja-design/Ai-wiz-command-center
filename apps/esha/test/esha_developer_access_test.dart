import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'fixtures.dart';

class DeveloperStore implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  int availabilityChecks = 0, checkouts = 0, completions = 0, restores = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [], notFoundIDs: ids.toList());

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    checkouts++;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completions++;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeveloperFixture {
  final store = DeveloperStore();
  late final KorlixApi api;
  late final EshaPurchases billing;
  DateTime now = DateTime.utc(2026, 11, 15, 12);
  String account = accountA;
  Object? appAccess = {'active': true, 'source': 'developer'};
  bool storeActive = false, storeFresh = false;
  String? storeExpiry;
  bool consultationEnabled = false, checkoutReady = false;
  int? allowanceLimit, remaining;
  int statusRequests = 0, verificationRequests = 0;
  Future<http.Response> Function()? statusResponse;
  final notifications = <({bool developer, bool loading})>[];
  bool _closed = false;

  Json get status => {
    'appAccess': appAccess,
    'purchasesEnabled': checkoutReady,
    'storeConfigurationVerified': checkoutReady,
    'allowanceConfigured': checkoutReady,
    'state': checkoutReady ? 'ready' : 'not_ready',
    'consultationLimits': {'trial': 2, 'monthly': 10},
    'consultationEnabled': consultationEnabled,
    'membership': {
      'active': storeActive,
      'verificationFresh': storeFresh,
      'trial': false,
      'expiresAt': storeExpiry,
    },
    'allowance': {'limit': allowanceLimit, 'remaining': remaining},
  };

  http.Response reply(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code);

  Future<void> start() async {
    api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: MemoryStore(),
      platform: 'ios',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/signin':
            // A session profile is not an app-access grant.
            return reply({
              ...authPayload(account),
              'profile': {'role': 'developer', 'tier': 'enterprise'},
            });
          case '/api/esha/billing/status':
            statusRequests++;
            return statusResponse == null ? reply(status) : statusResponse!();
          case '/api/esha/billing/catalog':
            return reply(status);
          case '/api/esha/billing/verify':
            verificationRequests++;
            return reply({
              'verified': true,
              'completePurchase': true,
              'status': status,
            });
          default:
            return reply({});
        }
      }),
    );
    await api.signIn('developer@example.test', 'not-a-real-password');
    billing = EshaPurchases(api, store: store, now: () => now);
    billing.addListener(() {
      notifications.add((
        developer: billing.hasDeveloperAccess,
        loading: billing.loading,
      ));
    });
    await billing.initialize();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    billing.dispose();
    api.dispose();
    await store.updates.close();
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server developer grant unlocks app without inventing a store entitlement or paid AI', () async {
    final f = DeveloperFixture();
    await f.start();
    addTearDown(f.close);

    expect(f.billing.hasDeveloperAccess, isTrue);
    expect(f.billing.hasAppAccess, isTrue);
    expect(f.billing.membership.active, isFalse);
    expect(f.billing.membership.verificationFresh, isFalse);
    expect(f.billing.membership.expiry, isNull);
    expect(f.billing.needsVerification, isFalse);
    expect(f.billing.canConsult, isFalse);
    expect(f.billing.canPurchase, isFalse);
    expect(f.billing.loading, isFalse);
    expect(f.notifications.last, (developer: true, loading: false));
    expect(f.store.availabilityChecks, 0);
    expect(f.billing.accessMessage, contains('developer access'));
    expect(f.billing.message, f.billing.accessMessage);
    expect(f.billing.message, isNot(contains('store-verified')));
  });

  test('profile roles and malformed or nondeveloper appAccess never bypass membership', () async {
    final f = DeveloperFixture();
    await f.start();
    addTearDown(f.close);
    for (final grant in [
      null,
      <String, dynamic>{},
      {'active': 'true', 'source': 'developer'},
      {'active': 1, 'source': 'developer'},
      {'active': false, 'source': 'developer'},
      {'active': true, 'source': 'store'},
      {'active': true, 'source': 'enterprise'},
    ]) {
      f.appAccess = grant;
      await f.billing.refresh();
      expect(f.billing.hasDeveloperAccess, isFalse, reason: '$grant');
      expect(f.billing.hasAppAccess, isFalse, reason: '$grant');
    }
  });

  test('ordinary store members retain expiry rules while developer access is independent', () async {
    final f = DeveloperFixture()
      ..appAccess = {'active': true, 'source': 'store'}
      ..storeActive = true
      ..storeFresh = true;
    f.storeExpiry = f.now.add(const Duration(days: 30)).toIso8601String();
    await f.start();
    addTearDown(f.close);
    expect(f.billing.hasAppAccess, isTrue);
    expect(f.billing.hasDeveloperAccess, isFalse);

    f.storeExpiry = f.now
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    await f.billing.refresh();
    expect(f.billing.hasAppAccess, isFalse);
    expect(f.billing.needsVerification, isTrue);
    f.appAccess = {'active': true, 'source': 'developer'};
    await f.billing.refresh();
    expect(f.billing.hasDeveloperAccess, isTrue);
    expect(f.billing.hasAppAccess, isTrue);
    expect(f.billing.needsVerification, isFalse);
  });

  test('developer access never bypasses checkout or consultation configuration and allowance', () async {
    final f = DeveloperFixture()..checkoutReady = true;
    await f.start();
    addTearDown(f.close);
    // Make every other checkout condition valid; the app grant still blocks it.
    f.billing.storeAvailable = true;
    f.billing.storeTermsVerified = true;
    f.billing.product = ProductDetails(
      id: 'com.korlixdeveloper.esha.monthly',
      title: 'Esha',
      description: 'Test subscription',
      price: r'$4.99',
      rawPrice: 4.99,
      currencyCode: 'USD',
    );
    expect(f.billing.catalogReady, isTrue);
    expect(f.billing.canPurchase, isFalse);
    await f.billing.purchase();
    expect(f.store.checkouts, 0);

    f.allowanceLimit = 10;
    f.remaining = 10;
    await f.billing.refresh();
    expect(f.billing.canConsult, isFalse);
    f.consultationEnabled = true;
    f.allowanceLimit = null;
    await f.billing.refresh();
    expect(f.billing.canConsult, isFalse);
    f.allowanceLimit = 10;
    f.remaining = 0;
    await f.billing.refresh();
    expect(f.billing.canConsult, isFalse);
    f.remaining = 1;
    await f.billing.refresh();
    expect(f.billing.canConsult, isTrue);
    f.billing.applyAllowance({'limit': 10, 'remaining': 0});
    expect(f.billing.hasDeveloperAccess, isTrue);
    expect(f.billing.canConsult, isFalse);
  });

  test(
    'server revocation and failed verification remove developer access',
    () async {
      final f = DeveloperFixture();
      await f.start();
      addTearDown(f.close);
      f.appAccess = {'active': false, 'source': null};
      await f.billing.refresh();
      expect(f.billing.hasAppAccess, isFalse);
      f.appAccess = {'active': true, 'source': 'developer'};
      await f.billing.refresh();
      expect(f.billing.hasDeveloperAccess, isTrue);
      f.statusResponse = () async => f.reply({'error': 'Unavailable'}, 503);
      await f.billing.refresh(requireVerification: true);
      expect(f.billing.hasDeveloperAccess, isFalse);
      expect(f.billing.hasAppAccess, isFalse);
      expect(f.billing.needsVerification, isTrue);
    },
  );

  test('account switches and sign-out invalidate grants and reject a late former-owner response', () async {
    final f = DeveloperFixture();
    await f.start();
    addTearDown(f.close);
    final delayed = Completer<http.Response>();
    final started = Completer<void>();
    final priorStatus = f.status;
    f.statusResponse = () {
      started.complete();
      return delayed.future;
    };
    final pending = f.billing.refresh();
    await started.future;

    f.account = accountB;
    await f.api.signIn('other@example.test', 'not-a-real-password');
    expect(f.billing.hasDeveloperAccess, isFalse);
    f.appAccess = {'active': false, 'source': null};
    f.statusResponse = null;
    f.billing.accountChanged();
    await flush();
    delayed.complete(f.reply(priorStatus));
    await pending;
    expect(f.billing.hasDeveloperAccess, isFalse);
    expect(f.billing.hasAppAccess, isFalse);

    f.appAccess = {'active': true, 'source': 'developer'};
    await f.billing.refresh();
    expect(f.billing.hasDeveloperAccess, isTrue);
    await f.api.signOut();
    expect(f.billing.hasDeveloperAccess, isFalse);
    f.billing.accountChanged();
    await flush();
    expect(f.billing.hasAppAccess, isFalse);
  });

  testWidgets(
    'developer lease expires while refresh is pending and cannot be revived by older work',
    (tester) async {
      final f = DeveloperFixture();
      await f.start();
      addTearDown(f.close);
      final older = Completer<http.Response>();
      final mandatory = Completer<http.Response>();
      final oldStatus = f.status;
      f.statusResponse = () =>
          f.statusRequests == 2 ? older.future : mandatory.future;
      // Start a refresh just before expiry so the real HTTP timeout has not
      // already closed it. Suppress only the earlier quiet refresh timer.
      f.billing.setForeground(false);
      f.now = f.now.add(const Duration(minutes: 14, seconds: 50));
      await tester.pump(const Duration(minutes: 14, seconds: 50));
      f.billing.setForeground(true);
      final pending = f.billing.refresh();
      await tester.pump();
      expect(f.billing.loading, isTrue);
      expect(f.billing.hasDeveloperAccess, isTrue);
      f.now = f.now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10, milliseconds: 1));
      expect(f.billing.hasDeveloperAccess, isFalse);
      expect(f.billing.needsVerification, isTrue);
      expect(f.statusRequests, 3);
      older.complete(f.reply(oldStatus));
      await tester.pump();
      await pending;
      expect(f.billing.hasDeveloperAccess, isFalse);
      f.appAccess = {'active': false, 'source': null};
      mandatory.complete(f.reply(f.status));
      await tester.pump();
      expect(f.billing.hasAppAccess, isFalse);
      await f.close();
    },
  );

  testWidgets(
    'background lease expiry requires fresh verification before developer access returns',
    (tester) async {
      final f = DeveloperFixture();
      await f.start();
      addTearDown(f.close);
      f.billing.setForeground(false);
      f.now = f.now.add(EshaPurchases.freshnessWindow);
      await tester.pump(EshaPurchases.freshnessWindow);
      expect(f.billing.hasAppAccess, isFalse);
      expect(f.statusRequests, 1);
      f.billing.setForeground(true);
      await f.billing.refresh();
      expect(f.billing.hasDeveloperAccess, isTrue);
      f.now = f.now.subtract(const Duration(seconds: 1));
      expect(f.billing.hasDeveloperAccess, isFalse);
      await f.close();
    },
  );

  test('restore and verified purchase status keep developer access distinct from membership', () async {
    final f = DeveloperFixture();
    await f.start();
    addTearDown(f.close);
    await f.billing.restore();
    expect(f.store.restores, 1);
    expect(f.billing.hasDeveloperAccess, isTrue);
    expect(f.billing.message, f.billing.accessMessage);

    final purchase = PurchaseDetails(
      purchaseID: 'test-transaction',
      productID: 'com.korlixdeveloper.esha.monthly',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'app_store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.restored,
    )..pendingCompletePurchase = true;
    f.store.updates.add([purchase]);
    await flush();
    expect(f.verificationRequests, 1);
    expect(f.store.completions, 1);
    expect(f.billing.hasDeveloperAccess, isTrue);
    expect(f.billing.membership.active, isFalse);
    expect(f.billing.message, f.billing.accessMessage);
    expect(f.billing.canConsult, isFalse);
  });
}
