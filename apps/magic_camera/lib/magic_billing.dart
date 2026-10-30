import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:korlix_receipt_core/auth/korlix_http.dart' as korlix_http;
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';

const magicProductIds = {'magic_camera_starter', 'magic_camera_plus'};
const magicPlayPackage = 'com.korlixdeveloper.magiccamera';

class MagicBillingService extends ChangeNotifier {
  MagicBillingService({
    required this.backendUrl,
    required this.headers,
    required this.sessionChanges,
    InAppPurchase? store,
    http.Client? client,
  }) : _store = store ?? InAppPurchase.instance,
       _http = client ?? korlix_http.createClient(),
       _ownsClient = client == null {
    _scope = _identity();
    sessionChanges.addListener(_sessionChanged);
  }
  final String backendUrl;
  final Map<String, String> Function() headers;
  final Listenable sessionChanges;
  final InAppPurchase _store;
  final http.Client _http;
  final bool _ownsClient;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  Timer? _restoreTimer;
  String? _scope;
  bool _disposed = false, _invalid = false, _started = false;
  bool busy = false,
      loading = false,
      billingEnabled = false,
      canPurchase = false;
  String? error, message;
  Map<String, dynamic> plan = {}, entitlement = {};
  final Map<String, ProductDetails> products = {};
  String selectedId = 'magic_camera_starter';
  ProductDetails? get product => products[selectedId];
  void select(String id) {
    if (magicProductIds.contains(id)) {
      selectedId = id;
      _notify();
    }
  }

  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  bool get apple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get full =>
      plan['name'] != null && !['free', 'locked'].contains(plan['name']);
  String? get price => product?.price;
  bool get readyToBuy =>
      supported &&
      billingEnabled &&
      canPurchase &&
      product != null &&
      !busy &&
      !loading &&
      _alive;
  bool get _alive =>
      !_disposed && !_invalid && _scope != null && _identity() == _scope;

  String? _identity() {
    final authorization =
        headers()['Authorization'] ?? headers()['authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    return korlixSessionIdentity(authorization.substring(7));
  }

  void _sessionChanged() {
    if (_disposed || _invalid || _identity() == _scope) return;
    _invalid = true;
    products.clear();
    plan = {};
    entitlement = {};
    canPurchase = billingEnabled = busy = loading = false;
    error = 'Your account changed. Reopen your plan after signing in.';
    _restoreTimer?.cancel();
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!_alive) throw StateError('Sign in again to manage Magic Camera.');
    final request = http.Request(
      body == null ? 'GET' : 'POST',
      Uri.parse(
        '${backendUrl.replaceFirst(RegExp(r'/+$'), '')}/api/magic-camera/billing/${apple ? 'apple' : 'google'}/$path',
      ),
    )..headers.addAll({...headers(), 'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    final response = await _http
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    if (!_alive) throw StateError('Your account changed. Reopen your plan.');
    final value = jsonDecode(response.body);
    if (value is! Map) {
      throw StateError('Could not read your subscription. Please retry.');
    }
    final data = Map<String, dynamic>.from(value);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['error']?.toString() ??
            'Could not verify your subscription. Please retry.',
      );
    }
    return data;
  }

  Future<void> start() async {
    if (_started || !_alive) return;
    _started = true;
    if (supported) {
      _subscription = _store.purchaseStream.listen(
        (purchases) {
          _queue = _queue.then((_) => _purchases(purchases)).catchError((
            Object _,
          ) {
            if (_alive) {
              busy = false;
              error = 'Purchase verification was interrupted. Try Restore purchases.';
              _notify();
            }
          });
        },
        onError: (Object _) {
          if (_alive) {
            busy = false;
            error = 'the app store could not respond. Please retry.';
            _notify();
          }
        },
      );
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!_alive || loading) return;
    loading = true;
    error = null;
    _notify();
    try {
      final data = await _request('status?refresh=1');
      if (!_alive) return;
      plan = Map<String, dynamic>.from(data['plan'] as Map? ?? {});
      entitlement = Map<String, dynamic>.from(
        data['entitlement'] as Map? ?? {},
      );
      billingEnabled = data['billingEnabled'] == true;
      canPurchase = data['canPurchase'] == true;
      if (data['refreshWarning'] != null) {
        error = data['refreshWarning'].toString();
      }
      products.clear();
      if (supported && await _store.isAvailable()) {
        if (!_alive) return;
        final response = await _store.queryProductDetails(magicProductIds);
        if (!_alive) return;
        for (final item in response.productDetails) {
          if (apple) {
            if (magicProductIds.contains(item.id)) products[item.id] = item;
            continue;
          }
          if (item is! GooglePlayProductDetails ||
              !magicProductIds.contains(item.id) ||
              item.productDetails.productType != ProductType.subs) {
            continue;
          }
          final offers = item.productDetails.subscriptionOfferDetails;
          final index = item.subscriptionIndex;
          if (offers == null ||
              index == null ||
              index < 0 ||
              index >= offers.length) {
            continue;
          }
          final offer = offers[index];
          if (offer.basePlanId != 'monthly' ||
              offer.offerId != null ||
              offer.pricingPhases.length != 1) {
            continue;
          }
          final phase = offer.pricingPhases.single;
          if (phase.billingPeriod == 'P1M' &&
              phase.priceAmountMicros > 0 &&
              phase.recurrenceMode == RecurrenceMode.infiniteRecurring) {
            products[item.id] = item;
          }
        }
      }
    } catch (e) {
      if (_alive) {
        canPurchase = false;
        error = _friendly(e);
      }
    } finally {
      if (_alive) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> buy() async {
    if (!readyToBuy) return;
    final selected = product!;
    busy = true;
    error = null;
    message = 'Opening the app store…';
    _notify();
    try {
      final data = await _request('prepare', body: {'productId': selected.id});
      if (!_alive) return;
      final accountId = data['accountId']?.toString() ?? '';
      if (data['canPurchase'] != true ||
          !(apple ? RegExp(r'^[0-9a-f-]{36}$') : RegExp(r'^[0-9a-f]{64}$'))
              .hasMatch(accountId)) {
        throw StateError(
          'Magic Camera may already be included. Refresh your plan before purchasing.',
        );
      }
      if (!await _store.buyNonConsumable(
        purchaseParam: apple
            ? PurchaseParam(
                productDetails: selected,
                applicationUserName: accountId,
              )
            : GooglePlayPurchaseParam(
                productDetails: selected,
                applicationUserName: accountId,
                offerToken: (selected as GooglePlayProductDetails).offerToken,
              ),
      )) {
        throw StateError(
          'the app store did not open the purchase. Please retry.',
        );
      }
    } catch (e) {
      if (_alive) {
        busy = false;
        message = null;
        error = _friendly(e);
        _notify();
      }
    }
  }

  Future<void> restore() async {
    if (!_alive || !supported || busy) return;
    busy = true;
    error = null;
    message = 'Checking your the app store purchases…';
    _notify();
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 20), () {
      if (_alive && busy) {
        busy = false;
        message = 'No confirmed purchase was returned yet. Check your the app store account, then try again.';
        _notify();
      }
    });
    try {
      await _store.restorePurchases();
    } catch (e) {
      if (_alive) {
        _restoreTimer?.cancel();
        busy = false;
        error = _friendly(e);
        _notify();
      }
    }
  }

  Future<void> _purchases(List<PurchaseDetails> purchases) async {
    if (!_alive) return;
    for (final purchase in purchases) {
      if (!_alive) return;
      if (!magicProductIds.contains(purchase.productID)) continue;
      if (purchase.status == PurchaseStatus.pending) {
        busy = true;
        message = 'Payment is pending in the app store. Your plan activates after confirmation.';
        _notify();
        continue;
      }
      _restoreTimer?.cancel();
      if (purchase.status == PurchaseStatus.canceled ||
          purchase.status == PurchaseStatus.error) {
        busy = false;
        message = purchase.status == PurchaseStatus.canceled
            ? 'Purchase canceled.'
            : null;
        error = purchase.status == PurchaseStatus.error
            ? 'the app store could not complete the purchase. Please retry.'
            : null;
        _notify();
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      busy = true;
      message = 'Verifying your Magic Camera subscription…';
      error = null;
      _notify();
      try {
        final data = await _request(
          'verify',
          body: {
            'productId': purchase.productID,
            'purchaseId': purchase.purchaseID,
            'source': purchase.verificationData.source,
            'verificationData':
                purchase.verificationData.serverVerificationData,
          },
        );
        if (!_alive) return;
        if (data['verified'] != true) {
          throw StateError(
            'Purchase verification is incomplete. Try Restore purchases.',
          );
        }
        if (purchase.pendingCompletePurchase &&
            data['completePurchase'] == true) {
          await _store.completePurchase(purchase);
        }
        if (!_alive) return;
        message = data['active'] == true
            ? 'Magic Camera is active.'
            : 'This subscription is not currently active.';
        await refresh();
      } catch (e) {
        if (_alive) {
          error = _friendly(e);
          message = null;
        }
      } finally {
        if (_alive) {
          busy = false;
          _notify();
        }
      }
    }
  }

  String _friendly(Object e) => e is StateError
      ? e.message.toString()
      : 'Could not connect to subscription services. Please retry or use Restore purchases.';
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restoreTimer?.cancel();
    unawaited(_subscription?.cancel());
    sessionChanges.removeListener(_sessionChanged);
    if (_ownsClient) _http.close();
    super.dispose();
  }
}
