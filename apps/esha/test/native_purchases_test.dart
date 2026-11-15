import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'fixtures.dart';

const monthlyPhase = PricingPhaseWrapper(
  billingCycleCount: 0,
  billingPeriod: 'P1M',
  formattedPrice: r'$4.99',
  priceAmountMicros: 4990000,
  priceCurrencyCode: 'USD',
  recurrenceMode: RecurrenceMode.infiniteRecurring,
);
const trialPhase = PricingPhaseWrapper(
  billingCycleCount: 1,
  billingPeriod: 'P3D',
  formattedPrice: r'$0.00',
  priceAmountMicros: 0,
  priceCurrencyCode: 'USD',
  recurrenceMode: RecurrenceMode.finiteRecurring,
);

SubscriptionOfferDetailsWrapper offer({
  bool trial = false,
  String? token,
  PricingPhaseWrapper firstPhase = trialPhase,
  InstallmentPlanDetailsWrapper? installment,
}) => SubscriptionOfferDetailsWrapper(
  basePlanId: 'monthly',
  offerId: trial ? 'trial-3-days' : null,
  offerTags: const [],
  offerIdToken:
      token ?? (trial ? 'eligible-trial-token' : 'regular-plan-token'),
  pricingPhases: [if (trial) firstPhase, monthlyPhase],
  installmentPlanDetails: installment,
);

List<GooglePlayProductDetails> products(
  List<SubscriptionOfferDetailsWrapper> offers,
) => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: 'Esha membership',
    name: 'Esha monthly',
    productId: 'esha_monthly',
    productType: ProductType.subs,
    subscriptionOfferDetails: offers,
    title: 'Esha monthly',
  ),
);

GooglePlayPurchaseDetails transaction({
  PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
  PurchaseStatus status = PurchaseStatus.purchased,
}) => GooglePlayPurchaseDetails.fromPurchase(
  PurchaseWrapper(
    orderId: state == PurchaseStateWrapper.pending ? '' : 'GPA.test-order',
    packageName: 'com.korlixdeveloper.esha',
    purchaseTime: 1,
    purchaseToken: 'test-token',
    signature: 'test-signature',
    products: const ['esha_monthly'],
    isAutoRenewing: true,
    originalJson: '{}',
    isAcknowledged: false,
    purchaseState: state,
  ),
).single..status = status;

class FakeStore implements InAppPurchase {
  final changes = StreamController<List<PurchaseDetails>>.broadcast();
  List<ProductDetails> details = products([offer(), offer(trial: true)]);
  bool available = true, failProductQuery = false;
  int completed = 0, restores = 0;
  PurchaseParam? checkout;
  Future<void> Function()? onRestore;
  Future<bool> Function()? onBuy;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => changes.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    if (failProductQuery) throw StateError('Storefront unavailable');
    return ProductDetailsResponse(productDetails: details, notFoundIDs: []);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    checkout = purchaseParam;
    return onBuy == null ? true : await onBuy!();
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    if (onRestore != null) await onRestore!();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BillingFixture {
  final store = FakeStore();
  late final KorlixApi api;
  late final EshaPurchases billing;
  bool active = false, rejectVerification = false;
  int verificationRequests = 0;
  Json limits = {'trial': 3, 'monthly': 20};
  Future<http.Response> Function()? prepareResponse;
  Future<http.Response> Function()? statusResponse;

  Json get status => {
    'purchasesEnabled': true,
    'storeConfigurationVerified': true,
    'allowanceConfigured': true,
    'consultationEnabled': true,
    'state': 'ready',
    'consultationLimits': limits,
    'product': {
      'productId': 'esha_monthly',
      'basePlanId': 'monthly',
      'offerId': 'trial-3-days',
    },
    'membership': {'active': active, 'verificationFresh': active},
    'allowance': {
      'configured': active,
      'limit': active ? 20 : null,
      'remaining': active ? 19 : null,
    },
  };
  Json get prepared => {
    'canPurchase': true,
    'accountId': 'esha-scoped-test-account',
    'bundleId': 'com.korlixdeveloper.esha',
    'productId': 'esha_monthly',
    'basePlanId': 'monthly',
    'offerId': 'trial-3-days',
  };
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);

  Future<void> start() async {
    api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: MemoryStore(),
      platform: 'android',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return reply(authPayload(accountA));
        }
        if (request.url.path == '/api/esha/billing/prepare') {
          return prepareResponse == null
              ? reply(prepared)
              : await prepareResponse!();
        }
        if (request.url.path == '/api/esha/billing/status' &&
            statusResponse != null) {
          return await statusResponse!();
        }
        if (request.url.path == '/api/esha/billing/verify') {
          verificationRequests++;
          if (rejectVerification) {
            return reply({
              'error': 'Store unavailable',
              'code': 'store_unavailable',
            }, 503);
          }
          active = true;
          return reply({
            'verified': true,
            'completePurchase': true,
            'active': true,
            'status': status,
          });
        }
        return reply(status);
      }),
    );
    await api.signIn('person@example.test', 'not-a-real-password');
    billing = EshaPurchases(api, store: store);
    await billing.initialize();
  }

  Future<void> close() async {
    billing.dispose();
    await store.changes.close();
    api.dispose();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public allowances are shown before membership and must be valid before checkout', () async {
    final f = BillingFixture();
    await f.start();
    addTearDown(f.close);
    expect(f.billing.membership.active, isFalse);
    expect(f.billing.membership.allowanceLimit, isNull);
    expect(f.billing.trialConsultationLimit, 3);
    expect(f.billing.monthlyConsultationLimit, 20);
    expect(f.billing.canPurchase, isTrue);
    f.limits = {'trial': 0, 'monthly': '20'};
    await f.billing.refresh();
    expect(f.billing.trialConsultationLimit, isNull);
    expect(f.billing.monthlyConsultationLimit, isNull);
    expect(f.billing.canPurchase, isFalse);
  });

  test(
    'Android chooses the eligible trial token and shows its paid monthly price',
    () async {
      final f = BillingFixture();
      await f.start();
      addTearDown(f.close);
      expect(f.billing.trialEligible, isTrue);
      expect(f.billing.localizedMonthlyPrice, r'$4.99');
      await f.billing.purchase();
      final checkout = f.store.checkout as GooglePlayPurchaseParam;
      expect(checkout.offerToken, 'eligible-trial-token');
      expect(checkout.applicationUserName, 'esha-scoped-test-account');
      expect(checkout.productDetails.rawPrice, 0);
    },
  );

  test('checkout keeps the selected token if a refresh changes eligibility during preparation', () async {
    final f = BillingFixture();
    await f.start();
    addTearDown(f.close);
    final prepared = Completer<http.Response>();
    f.prepareResponse = () => prepared.future;
    final purchase = f.billing.purchase();
    await settle();
    f.store.details = products([offer(token: 'new-regular-token')]);
    await f.billing.refresh();
    expect(f.billing.trialEligible, isFalse);
    prepared.complete(f.reply(f.prepared));
    await purchase;
    expect(
      (f.store.checkout as GooglePlayPurchaseParam).offerToken,
      'eligible-trial-token',
    );
  });

  test('malformed eligible trials and installment commitments never fall back to paid checkout', () async {
    final f = BillingFixture();
    f.store.details = products([
      offer(),
      offer(
        trial: true,
        firstPhase: const PricingPhaseWrapper(
          billingCycleCount: 1,
          billingPeriod: 'P3D',
          formattedPrice: r'$0.00',
          priceAmountMicros: 0,
          priceCurrencyCode: 'USD',
          recurrenceMode: RecurrenceMode.infiniteRecurring,
        ),
      ),
    ]);
    await f.start();
    addTearDown(f.close);
    expect(f.billing.product, isNull);
    expect(f.billing.canPurchase, isFalse);
    f.store.details = products([
      offer(
        installment: const InstallmentPlanDetailsWrapper(
          commitmentPaymentsCount: 12,
          subsequentCommitmentPaymentsCount: 0,
        ),
      ),
    ]);
    await f.billing.refresh();
    expect(f.billing.canPurchase, isFalse);
    f.store.details = products([offer()]);
    await f.billing.refresh();
    expect(f.billing.trialEligible, isFalse);
    expect(f.billing.canPurchase, isTrue);
  });

  test('storefront failure preserves a fresh verified membership but clears checkout options', () async {
    final f = BillingFixture();
    f.active = true;
    await f.start();
    addTearDown(f.close);
    expect(f.billing.membership.canConsult, isTrue);
    f.store.failProductQuery = true;
    await f.billing.refresh();
    expect(f.billing.membership.active, isTrue);
    expect(f.billing.membership.canConsult, isTrue);
    expect(f.billing.localizedMonthlyPrice, isNull);
    expect(f.billing.product, isNull);
    expect(f.billing.canPurchase, isFalse);
  });

  test('restored Android pending payments do not verify, complete, or lock recovery controls', () async {
    final f = BillingFixture();
    await f.start();
    addTearDown(f.close);
    f.store.onRestore = () async {
      f.store.changes.add([
        transaction(
          state: PurchaseStateWrapper.pending,
          status: PurchaseStatus.restored,
        ),
      ]);
    };
    await f.billing.restore();
    await settle();
    expect(f.billing.awaitingApproval, isTrue);
    expect(f.billing.busy, isFalse);
    expect(f.billing.canPurchase, isFalse);
    expect(f.billing.membership.active, isFalse);
    expect(f.verificationRequests, 0);
    expect(f.store.completed, 0);
    f.store.onRestore = () async => f.store.changes.add([]);
    await f.billing.restore();
    await settle();
    expect(f.store.restores, 2);
    expect(f.billing.awaitingApproval, isFalse);
    expect(f.billing.canPurchase, isTrue);
  });

  test('an unverified purchase blocks duplicate checkout and can be verified on retry', () async {
    final f = BillingFixture();
    f.rejectVerification = true;
    await f.start();
    addTearDown(f.close);
    f.store.changes.add([transaction()]);
    await settle();
    expect(f.billing.hasUnverifiedPurchase, isTrue);
    expect(f.billing.canPurchase, isFalse);
    expect(f.store.completed, 0);
    f.rejectVerification = false;
    await f.billing.retryVerification();
    expect(f.billing.hasUnverifiedPurchase, isFalse);
    expect(f.billing.membership.active, isTrue);
    expect(f.store.completed, 1);
  });

  test(
    'a stale refresh cannot replace a newer successful purchase verification',
    () async {
      final f = BillingFixture();
      await f.start();
      addTearDown(f.close);
      final oldStatus = f.status;
      final delayed = Completer<http.Response>();
      f.statusResponse = () => delayed.future;
      final refresh = f.billing.refresh();
      await settle();
      f.store.changes.add([transaction()]);
      await settle();
      expect(f.billing.membership.active, isTrue);
      delayed.complete(f.reply(oldStatus));
      await refresh;
      expect(f.billing.membership.active, isTrue);
      expect(f.billing.membership.canConsult, isTrue);
    },
  );
}
