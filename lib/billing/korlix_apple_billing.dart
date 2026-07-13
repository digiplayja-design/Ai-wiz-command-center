import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

typedef KorlixBillingHeadersBuilder = Map<String, String> Function();
typedef KorlixBillingTierChanged = FutureOr<void> Function(String tier);

const String kKorlixAppleProMonthlyProductId =
    'com.korlixdeveloper.korlixai.pro.monthly';
const String kKorlixAppleUltraMonthlyProductId =
    'com.korlixdeveloper.korlixai.ultra.monthly';

const Set<String> kKorlixAppleSubscriptionProductIds = <String>{
  kKorlixAppleProMonthlyProductId,
  kKorlixAppleUltraMonthlyProductId,
};

// KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_CLIENT_BEGIN
class KorlixAppleBillingService extends ChangeNotifier {
  KorlixAppleBillingService._();

  static final KorlixAppleBillingService instance =
      KorlixAppleBillingService._();

  final InAppPurchase _store = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = <String, ProductDetails>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  String _backendBaseUrl = '';
  KorlixBillingHeadersBuilder? _headersBuilder;
  KorlixBillingTierChanged? _onTierChanged;
  bool _started = false;
  bool _loadingProducts = false;
  bool _checkingStatus = false;
  bool _restoring = false;
  bool _storeAvailable = false;
  String _currentTier = 'basic';
  String? _busyProductId;
  String? _message;
  String? _error;
  Map<String, dynamic>? _entitlement;

  bool get isApplePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get loadingProducts => _loadingProducts;
  bool get checkingStatus => _checkingStatus;
  bool get restoring => _restoring;
  bool get storeAvailable => _storeAvailable;
  bool get busy => _busyProductId != null || _restoring;
  String get currentTier => _currentTier;
  String? get busyProductId => _busyProductId;
  String? get message => _message;
  String? get error => _error;
  Map<String, dynamic>? get entitlement => _entitlement;

  ProductDetails? productFor(String productId) => _products[productId];

  Future<void> configure({
    required String backendBaseUrl,
    required KorlixBillingHeadersBuilder headersBuilder,
    required String currentTier,
    KorlixBillingTierChanged? onTierChanged,
  }) async {
    _backendBaseUrl = backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    _headersBuilder = headersBuilder;
    _onTierChanged = onTierChanged;
    _currentTier = _normalizeTier(currentTier);

    if (!_started) {
      _started = true;
      _purchaseSubscription = _store.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error) {
          _setError('App Store purchase update failed: $error');
        },
      );
    }

    if (!isApplePlatform) {
      _storeAvailable = false;
      _message =
          'Apple subscriptions are available in the iPhone and iPad app.';
      notifyListeners();
      return;
    }

    await refreshAll();
  }

  Future<void> refreshAll() async {
    await refreshProducts();
    await refreshStatus();
  }

  Future<void> refreshProducts() async {
    if (!isApplePlatform || _loadingProducts) {
      return;
    }

    _loadingProducts = true;
    _error = null;
    notifyListeners();

    try {
      _storeAvailable = await _store.isAvailable();

      if (!_storeAvailable) {
        _products.clear();
        _message = 'The App Store is temporarily unavailable.';
        return;
      }

      final ProductDetailsResponse response = await _store.queryProductDetails(
        kKorlixAppleSubscriptionProductIds,
      );

      if (response.error != null) {
        throw StateError(
          response.error?.message ?? 'Could not load App Store products.',
        );
      }

      _products
        ..clear()
        ..addEntries(
          response.productDetails.map(
            (ProductDetails product) =>
                MapEntry<String, ProductDetails>(product.id, product),
          ),
        );

      _message = response.notFoundIDs.isEmpty
          ? null
          : 'App Store products are still syncing: '
                '${response.notFoundIDs.join(', ')}';
    } catch (error) {
      _setError(_friendlyError(error));
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  Future<void> refreshStatus() async {
    if (_checkingStatus || _backendBaseUrl.isEmpty) {
      return;
    }

    final KorlixBillingHeadersBuilder? builder = _headersBuilder;
    if (builder == null) {
      return;
    }

    final Map<String, String> headers = Map<String, String>.from(builder());
    if (!_hasBearer(headers)) {
      _entitlement = null;
      _message = 'Sign in to view or restore your Korlix subscription.';
      notifyListeners();
      return;
    }

    _checkingStatus = true;
    _error = null;
    notifyListeners();

    try {
      final http.Response response = await http
          .get(
            Uri.parse('$_backendBaseUrl/api/billing/apple/status?refresh=1'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 45));

      final Map<String, dynamic> data = _decodeJson(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          data['error']?.toString() ??
              'Could not refresh your subscription status.',
        );
      }

      _currentTier = _normalizeTier(data['tier']?.toString());
      _entitlement = (data['entitlement'] as Map?)?.cast<String, dynamic>();
      await _notifyTierChanged(_currentTier);
    } catch (error) {
      _setError(_friendlyError(error));
    } finally {
      _checkingStatus = false;
      notifyListeners();
    }
  }

  Future<void> purchase(String productId) async {
    if (!isApplePlatform) {
      _setError('Apple subscriptions require the iPhone or iPad app.');
      return;
    }

    final KorlixBillingHeadersBuilder? builder = _headersBuilder;
    if (builder == null || !_hasBearer(builder())) {
      _setError('Please sign in before subscribing.');
      return;
    }

    ProductDetails? product = _products[productId];

    if (product == null) {
      await refreshProducts();
      product = _products[productId];
    }

    if (product == null) {
      _setError('This subscription is not available from the App Store yet.');
      return;
    }

    _busyProductId = productId;
    _error = null;
    _message = 'Opening the App Store purchase sheet…';
    notifyListeners();

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: _currentUserIdFromHeaders(builder()),
      );

      final bool started = await _store.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!started) {
        throw StateError('The App Store did not start the purchase.');
      }
    } catch (error) {
      _busyProductId = null;
      _setError(_friendlyError(error));
    } finally {
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (!isApplePlatform || _restoring) {
      return;
    }

    final KorlixBillingHeadersBuilder? builder = _headersBuilder;
    if (builder == null || !_hasBearer(builder())) {
      _setError('Please sign in before restoring purchases.');
      return;
    }

    _restoring = true;
    _error = null;
    _message = 'Checking your App Store purchase history…';
    notifyListeners();

    try {
      await _store.restorePurchases();
    } catch (error) {
      _restoring = false;
      _setError(_friendlyError(error));
    }
  }

  Future<void> openManageSubscriptions() async {
    final Uri uri = Uri.parse('https://apps.apple.com/account/subscriptions');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _setError('Could not open Apple subscription management.');
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    if (purchases.isEmpty && _restoring) {
      _restoring = false;
      _message = 'No restorable Korlix subscription was found.';
      notifyListeners();
      return;
    }

    for (final PurchaseDetails purchase in purchases) {
      if (!kKorlixAppleSubscriptionProductIds.contains(purchase.productID)) {
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _busyProductId = purchase.productID;
          _message = 'Your App Store purchase is pending…';
          _error = null;
          notifyListeners();
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndFinish(purchase);
          break;
        case PurchaseStatus.error:
          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }
          _busyProductId = null;
          _restoring = false;
          _setError(
            purchase.error?.message ??
                'The App Store could not complete this purchase.',
          );
          break;
        case PurchaseStatus.canceled:
          _busyProductId = null;
          _restoring = false;
          _message = 'Purchase canceled.';
          _error = null;
          notifyListeners();
          break;
      }
    }
  }

  Future<void> _verifyAndFinish(PurchaseDetails purchase) async {
    _busyProductId = purchase.productID;
    _message = 'Verifying your subscription securely…';
    _error = null;
    notifyListeners();

    try {
      final KorlixBillingHeadersBuilder? builder = _headersBuilder;
      if (builder == null) {
        throw StateError('Korlix sign-in information is unavailable.');
      }

      final Map<String, String> headers = Map<String, String>.from(builder())
        ..['Content-Type'] = 'application/json';

      if (!_hasBearer(headers)) {
        throw StateError('Please sign in to verify your subscription.');
      }

      final http.Response response = await http
          .post(
            Uri.parse('$_backendBaseUrl/api/billing/apple/verify'),
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'productId': purchase.productID,
              'purchaseId': purchase.purchaseID,
              'verificationData':
                  purchase.verificationData.serverVerificationData,
              'source': purchase.verificationData.source,
              'transactionDate': purchase.transactionDate,
              'restored': purchase.status == PurchaseStatus.restored,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final Map<String, dynamic> data = _decodeJson(response.body);

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['verified'] != true) {
        throw StateError(
          data['error']?.toString() ??
              'Apple could not verify this subscription.',
        );
      }

      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }

      _currentTier = _normalizeTier(data['tier']?.toString());
      _entitlement = <String, dynamic>{
        'product_id': data['productId'],
        'status': data['status'],
        'expires_at': data['expiresAt'],
        'environment': data['environment'],
        'transaction_id': data['transactionId'],
        'original_transaction_id': data['originalTransactionId'],
      };

      _busyProductId = null;
      _restoring = false;
      _message = data['active'] == true
          ? '${_tierLabel(_currentTier)} is active.'
          : 'Your Apple subscription is not currently active.';
      _error = null;

      await _notifyTierChanged(_currentTier);
      notifyListeners();
    } catch (error) {
      _busyProductId = null;
      _restoring = false;
      _setError(
        '${_friendlyError(error)} The purchase was not marked complete, '
        'so it can be verified again.',
      );
    }
  }

  Future<void> _notifyTierChanged(String tier) async {
    final KorlixBillingTierChanged? callback = _onTierChanged;
    if (callback != null) {
      await callback(tier);
    }
  }

  bool _hasBearer(Map<String, String> headers) {
    final String authorization = headers['Authorization']?.trim() ?? '';
    return authorization.toLowerCase().startsWith('bearer ');
  }

  String? _currentUserIdFromHeaders(Map<String, String> headers) {
    final String authorization = headers['Authorization']?.trim() ?? '';
    if (!authorization.toLowerCase().startsWith('bearer ')) {
      return null;
    }

    final String token = authorization.substring(7).trim();
    final List<String> parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final Object? decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );

      if (decoded is Map) {
        final String subject = decoded['sub']?.toString().trim() ?? '';
        return subject.isEmpty ? null : subject;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // Fall through.
    }

    return <String, dynamic>{};
  }

  String _normalizeTier(String? tier) {
    switch ((tier ?? '').trim().toLowerCase()) {
      case 'enterprise':
        return 'enterprise';
      case 'ultra':
      case 'ultra_premium':
      case 'ultra premium':
        return 'ultra';
      case 'pro':
        return 'pro';
      default:
        return 'basic';
    }
  }

  String _tierLabel(String tier) {
    switch (_normalizeTier(tier)) {
      case 'enterprise':
        return 'Enterprise';
      case 'ultra':
        return 'Ultra Premium';
      case 'pro':
        return 'Pro';
      default:
        return 'Basic';
    }
  }

  String _friendlyError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }

  void _setError(String message) {
    _error = message.trim();
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }
}

Future<void> showKorlixAppleSubscriptionSheet({
  required BuildContext context,
  required String backendBaseUrl,
  required KorlixBillingHeadersBuilder headersBuilder,
  required String currentTier,
  KorlixBillingTierChanged? onTierChanged,
}) async {
  final KorlixAppleBillingService service = KorlixAppleBillingService.instance;

  await service.configure(
    backendBaseUrl: backendBaseUrl,
    headersBuilder: headersBuilder,
    currentTier: currentTier,
    onTierChanged: onTierChanged,
  );

  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF031019),
    barrierColor: Colors.black.withValues(alpha: 0.78),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext sheetContext) {
      return _KorlixAppleSubscriptionSheet(service: service);
    },
  );
}

class _KorlixAppleSubscriptionSheet extends StatelessWidget {
  const _KorlixAppleSubscriptionSheet({required this.service});

  final KorlixAppleBillingService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (BuildContext context, Widget? child) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.60,
          maxChildSize: 0.98,
          builder: (BuildContext context, ScrollController scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF78909B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Korlix Plans',
                            style: TextStyle(
                              color: Color(0xFFF2F6F8),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Secure subscriptions through Apple',
                            style: TextStyle(
                              color: Color(0xFFA9C6CF),
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close plans',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFFE4EBEE),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _statusBanner(),
                const SizedBox(height: 14),
                _basicPlan(),
                const SizedBox(height: 14),
                _storePlan(
                  productId: kKorlixAppleProMonthlyProductId,
                  title: 'Pro',
                  subtitle: 'For regular creators and daily productivity.',
                  accent: const Color(0xFFB794F4),
                  icon: Icons.auto_awesome_rounded,
                  features: const <String>[
                    'Higher text generation limits',
                    'Access to up to 3 characters',
                    'PDF and export access',
                    'Saved settings access',
                    'Reduced or no ads',
                    'Voice input and document upload',
                  ],
                ),
                const SizedBox(height: 14),
                _storePlan(
                  productId: kKorlixAppleUltraMonthlyProductId,
                  title: 'Ultra Premium',
                  subtitle:
                      'For power users who want the full Korlix experience.',
                  accent: const Color(0xFFFFD166),
                  icon: Icons.workspace_premium_rounded,
                  features: const <String>[
                    'Access to all Korlix characters',
                    'Highest personal generation limits',
                    'LIVE CONVO fair-use allowance',
                    'OCR, handwriting, and scanned-image reading',
                    'Limited video generation',
                    'No ads',
                  ],
                ),
                const SizedBox(height: 14),
                _enterprisePlan(),
                const SizedBox(height: 16),
                if (service.isApplePlatform) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: service.busy
                              ? null
                              : service.restorePurchases,
                          icon: service.restoring
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.restore_rounded),
                          label: Text(
                            service.restoring
                                ? 'Restoring…'
                                : 'Restore Purchases',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF69D9E8),
                            minimumSize: const Size.fromHeight(52),
                            side: const BorderSide(color: Color(0xFF31566A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: service.openManageSubscriptions,
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('Manage'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFA9C6CF),
                            minimumSize: const Size.fromHeight(52),
                            side: const BorderSide(color: Color(0xFF31566A)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Subscriptions renew automatically unless canceled at '
                    'least 24 hours before the end of the current period. '
                    'Payment is charged to your Apple Account. You can manage '
                    'or cancel from Apple subscription settings.',
                    style: TextStyle(
                      color: Color(0xFF78909B),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ] else
                  const Text(
                    'Apple subscription purchases are available in the '
                    'iPhone and iPad version of Korlix.',
                    style: TextStyle(color: Color(0xFFA9C6CF), height: 1.4),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statusBanner() {
    final String? error = service.error;
    final String? message = service.message;

    if (error == null && message == null) {
      return const SizedBox.shrink();
    }

    final bool isError = error != null;
    final Color accent = isError
        ? const Color(0xFFFF5E73)
        : const Color(0xFF69D9E8);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.52)),
      ),
      child: Text(
        error ?? message ?? '',
        style: TextStyle(
          color: accent,
          height: 1.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _basicPlan() {
    return _planShell(
      title: 'Basic',
      subtitle: 'Free entry plan for light use.',
      price: 'Free',
      accent: const Color(0xFF69D9E8),
      current: service.currentTier == 'basic',
      icon: Icons.bolt_rounded,
      features: const <String>[
        '3 generations per day',
        'Access to 1 character',
        'Ads included',
        'Limited saved settings',
      ],
      action: null,
    );
  }

  Widget _enterprisePlan() {
    return _planShell(
      title: 'Enterprise',
      subtitle: 'For teams, businesses, schools, and agencies.',
      price: 'Contact support@korlixdeveloper.com',
      accent: const Color(0xFFE4EBEE),
      current: service.currentTier == 'enterprise',
      icon: Icons.business_center_rounded,
      features: const <String>[
        'All available characters',
        'Team seats and admin controls',
        'Custom text, video, and usage limits',
        'Priority support and onboarding',
      ],
      action: null,
    );
  }

  Widget _storePlan({
    required String productId,
    required String title,
    required String subtitle,
    required Color accent,
    required IconData icon,
    required List<String> features,
  }) {
    final ProductDetails? product = service.productFor(productId);
    final String expectedTier = productId == kKorlixAppleUltraMonthlyProductId
        ? 'ultra'
        : 'pro';
    final bool current = service.currentTier == expectedTier;
    final bool working = service.busyProductId == productId;
    final String price =
        product?.price ??
        (service.loadingProducts ? 'Loading App Store price…' : 'Unavailable');

    return _planShell(
      title: title,
      subtitle: subtitle,
      price: price,
      accent: accent,
      current: current,
      icon: icon,
      features: features,
      action: current
          ? null
          : FilledButton.icon(
              onPressed: product == null || service.busy
                  ? null
                  : () => service.purchase(productId),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF041018),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: working
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_rounded),
              label: Text(
                working ? 'Processing…' : 'Subscribe to $title',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
    );
  }

  Widget _planShell({
    required String title,
    required String subtitle,
    required String price,
    required Color accent,
    required bool current,
    required IconData icon,
    required List<String> features,
    required Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: current ? 0.95 : 0.43),
          width: current ? 2 : 1.2,
        ),
        boxShadow: current
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.16),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: accent, size: 27),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.65)),
                  ),
                  child: Text(
                    'Current',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            price,
            style: const TextStyle(
              color: Color(0xFFF2F6F8),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final String feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: accent,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFFE4EBEE),
                        height: 1.32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (action != null) ...<Widget>[const SizedBox(height: 8), action],
        ],
      ),
    );
  }
}
// KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_CLIENT_END
