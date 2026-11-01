import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'brain_api.dart';

class BrainBilling extends ChangeNotifier {
  BrainBilling(this.api, {InAppPurchase? store, TargetPlatform? platform})
    : store = store ?? InAppPurchase.instance,
      platform = platform ?? defaultTargetPlatform;
  final BrainApi api;
  final InAppPurchase store;
  final TargetPlatform platform;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  final _retry = <String, PurchaseDetails>{};
  final products = <String, ProductDetails>{};
  Map<String, dynamic>? balance;
  String? message;
  bool enabled = false, busy = false, loading = false, _disposed = false;
  bool get supported =>
      !kIsWeb &&
      (platform == TargetPlatform.iOS || platform == TargetPlatform.android);
  bool get apple => platform == TargetPlatform.iOS;
  String get provider => apple ? 'apple' : 'google';
  String get monthly =>
      apple ? 'com.korlix.brain.monthly' : 'korlix_brain_monthly';
  String gas(int hours) => apple
      ? 'com.korlix.brain.ai_gas.${hours}h'
      : 'korlix_brain_ai_gas_${hours}h';
  Set<String> get ids => {monthly, gas(1), gas(2), gas(3)};
  bool get subscriptionActive => balance?['subscriptionActive'] == true;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (!supported || _subscription != null) return;
    _subscription = store.purchaseStream.listen(
      (updates) {
        _queue = _queue.then((_) => _handle(updates)).catchError((Object _) {
          message =
              'Purchase verification could not finish. Tap Restore / retry.';
          busy = false;
          _notify();
        });
      },
      onError: (Object _) {
        message = 'The store connection was interrupted. Tap Restore / retry.';
        busy = false;
        _notify();
      },
    );
    await refresh();
  }

  bool _validProduct(ProductDetails product) {
    if (!ids.contains(product.id)) return false;
    if (product.id != monthly) return true;
    if (product is GooglePlayProductDetails) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) {
        return false;
      }
      final offer = offers[index];
      return offer.basePlanId == 'monthly' &&
          offer.offerId == null &&
          offer.pricingPhases.length == 1 &&
          offer.pricingPhases.single.billingPeriod == 'P1M';
    }
    if (product is AppStoreProduct2Details) {
      final subscription = product.sk2Product.subscription;
      return subscription?.subscriptionPeriod.unit ==
              SK2SubscriptionPeriodUnit.month &&
          subscription?.subscriptionPeriod.value == 1;
    }
    return false;
  }

  Future<void> refresh() async {
    if (_disposed || loading || !supported) return;
    final revision = api.auth.revision;
    loading = true;
    message = null;
    _notify();
    try {
      final status = await api.json(
        'GET',
        '/api/brain/billing/status?provider=$provider&refresh=1',
      );
      if (_disposed || revision != api.auth.revision) return;
      balance = (status['balance'] as Map?)?.cast<String, dynamic>();
      enabled = status['enabled'] == true;
      message = status['warning'] as String?;
      if (enabled && await store.isAvailable()) {
        final result = await store.queryProductDetails(ids);
        if (_disposed || revision != api.auth.revision) return;
        products.clear();
        for (final item in result.productDetails.where(_validProduct)) {
          products[item.id] = item;
        }
        if (result.error != null || products.length != ids.length) {
          enabled = false;
          message = 'The store has not made every plan and AI GAS package available yet. Please retry later.';
        }
      } else {
        enabled = false;
        message ??= 'Store purchases are being set up. Please try again later.';
      }
    } catch (error) {
      enabled = false;
      message = error is BrainApiException
          ? error.message
          : 'Could not reach the store. Please retry.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> buy(String id) async {
    if (_disposed || busy || !enabled || !products.containsKey(id)) return;
    final revision = api.auth.revision;
    busy = true;
    message = 'Opening ${apple ? 'App Store' : 'Google Play'}…';
    _notify();
    try {
      final prepared = await api.json('POST', '/api/brain/billing/prepare', {
        'provider': provider,
        'productId': id,
      });
      if (_disposed || revision != api.auth.revision) return;
      final account = prepared['accountId'] as String?;
      if (prepared['canPurchase'] != true || account == null) {
        throw const BrainApiException('Refresh your plan before purchasing.');
      }
      final product = products[id]!;
      final param = product is GooglePlayProductDetails
          ? GooglePlayPurchaseParam(
              productDetails: product,
              applicationUserName: account,
              offerToken: product.offerToken,
            )
          : PurchaseParam(
              productDetails: product,
              applicationUserName: account,
            );
      final started = id == monthly
          ? await store.buyNonConsumable(purchaseParam: param)
          : await store.buyConsumable(purchaseParam: param, autoConsume: apple);
      if (!started) {
        throw const BrainApiException(
          'The store did not start the purchase. Please retry.',
        );
      }
    } catch (error) {
      busy = false;
      message = error is BrainApiException
          ? error.message
          : 'The purchase did not complete. Please retry.';
      _notify();
    }
  }

  Future<void> _handle(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      if (_disposed || !ids.contains(purchase.productID)) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          busy = true;
          message = 'Waiting for the store to approve your purchase. Minutes are added after approval.';
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(purchase);
        case PurchaseStatus.canceled:
          busy = false;
          message = 'Purchase canceled.';
        case PurchaseStatus.error:
          busy = false;
          message = 'The store could not complete this purchase. Please retry.';
      }
      _notify();
    }
  }

  Future<void> _verify(PurchaseDetails purchase) async {
    final revision = api.auth.revision;
    final key = '${purchase.productID}:${purchase.purchaseID}';
    _retry[key] = purchase;
    try {
      final result = await api.json('POST', '/api/brain/billing/verify', {
        'provider': provider,
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID,
        if (!apple)
          'purchaseToken': purchase.verificationData.serverVerificationData,
      });
      if (_disposed || revision != api.auth.revision) return;
      if (result['verified'] != true || result['completePurchase'] != true) {
        throw const BrainApiException(
          'The store has not confirmed this purchase. Tap Restore / retry.',
        );
      }
      balance = (result['balance'] as Map?)?.cast<String, dynamic>();
      // Google consumables are consumed by the server only after the durable
      // credit succeeds. Completing them here would acknowledge a consumed token.
      if (purchase.pendingCompletePurchase &&
          (apple || purchase.productID == monthly)) {
        await store.completePurchase(purchase);
      }
      _retry.remove(key);
      message = result['active'] == true
          ? 'Purchase verified. Your Live minutes are ready.'
          : 'Purchase checked. This purchase has no active allowance.';
    } catch (error) {
      message = error is BrainApiException ? error.message : 'Verification is incomplete. Tap Restore / retry; do not buy again.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> restore() async {
    if (_disposed || busy || !supported) return;
    busy = true;
    message = 'Checking your store purchases and saved minute balance…';
    _notify();
    try {
      for (final purchase in List<PurchaseDetails>.of(_retry.values)) {
        await _verify(purchase);
      }
      await store.restorePurchases();
      await refresh();
    } catch (_) {
      message = 'Restore could not finish. Please retry when connected.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
