import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_billing.dart';

class FakeStore implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<void> completePurchase(PurchaseDetails p) async {
    completed.add(p);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApi extends BrainApi {
  FakeApi(super.auth);
  int verified = 0;
  bool fail = false;
  Completer<Map<String, dynamic>>? hold;
  @override
  Future<Map<String, dynamic>> json(
    String method,
    String path, [
    Object? body,
  ]) async {
    if (path.endsWith('/verify')) {
      verified++;
      if (fail) throw const BrainApiException('Store unavailable. Retry.');
      return hold?.future ??
          Future.value({
            'verified': true,
            'completePurchase': true,
            'active': true,
            'balance': {'gasSeconds': 3600},
          });
    }
    return {
      'enabled': false,
      'balance': {'gasSeconds': 3600},
    };
  }
}

PurchaseDetails purchase(String id, PurchaseStatus status) => PurchaseDetails(
  productID: id,
  purchaseID: '123456',
  transactionDate: '1',
  status: status,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'fixture-token',
    source: 'fixture',
  ),
)..pendingCompletePurchase = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BrainAuthController auth;
  late FakeApi api;
  late FakeStore store;
  late BrainBilling billing;
  Future<void> setup(TargetPlatform platform) async {
    auth = BrainAuthController();
    api = FakeApi(auth);
    store = FakeStore();
    billing = BrainBilling(api, store: store, platform: platform);
    await billing.initialize();
    addTearDown(() async {
      billing.dispose();
      await store.updates.close();
      api.dispose();
      auth.dispose();
    });
  }

  test('pending and canceled payments do not verify or add minutes', () async {
    await setup(TargetPlatform.iOS);
    store.updates.add([purchase(billing.gas(1), PurchaseStatus.pending)]);
    await pumpEventQueue();
    expect(billing.busy, isTrue);
    expect(api.verified, 0);
    expect(store.completed, isEmpty);
    store.updates.add([purchase(billing.gas(1), PurchaseStatus.canceled)]);
    await pumpEventQueue();
    expect(billing.busy, isFalse);
    expect(api.verified, 0);
  });
  test('Apple purchase completes only after verified durable credit; failed verification can retry', () async {
    await setup(TargetPlatform.iOS);
    api.fail = true;
    store.updates.add([purchase(billing.gas(1), PurchaseStatus.purchased)]);
    await pumpEventQueue();
    expect(store.completed, isEmpty);
    expect(billing.message, contains('Retry'));
    api.fail = false;
    await billing.restore();
    expect(api.verified, 2);
    expect(store.completed, hasLength(1));
    expect(billing.balance?['gasSeconds'], 3600);
  });
  test('Google GAS uses server consumption and never native acknowledgement of an already consumed token', () async {
    await setup(TargetPlatform.android);
    store.updates.add([purchase(billing.gas(2), PurchaseStatus.purchased)]);
    await pumpEventQueue();
    expect(api.verified, 1);
    expect(store.completed, isEmpty);
    expect(billing.balance?['gasSeconds'], 3600);
  });
  test('account change while verification is in flight cannot complete purchase for the next session', () async {
    await setup(TargetPlatform.iOS);
    api.hold = Completer();
    store.updates.add([purchase(billing.gas(1), PurchaseStatus.purchased)]);
    await pumpEventQueue();
    auth.revision++;
    api.hold!.complete({
      'verified': true,
      'completePurchase': true,
      'active': true,
      'balance': {'gasSeconds': 999},
    });
    await pumpEventQueue();
    expect(store.completed, isEmpty);
    expect(billing.balance?['gasSeconds'], 3600);
  });
}
