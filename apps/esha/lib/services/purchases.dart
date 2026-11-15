import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import 'korlix_api.dart';

class MembershipStatus {
  const MembershipStatus({
    this.catalog = const {},
    this.active = false,
    this.trial = false,
    this.verificationFresh = false,
    this.expiresAt,
    this.allowanceLimit,
    this.remaining,
    this.used = 0,
    this.reserved = 0,
    this.periodEndsAt,
    this.warning,
  });
  factory MembershipStatus.fromJson(Json json) {
    final membership = object(json['membership']),
        allowance = object(json['allowance']);
    return MembershipStatus(
      catalog: json,
      active: membership['active'] == true,
      trial: membership['trial'] == true,
      verificationFresh: membership['verificationFresh'] == true,
      expiresAt: membership['expiresAt'] is String
          ? membership['expiresAt'] as String
          : null,
      allowanceLimit: allowance['limit'] is int
          ? allowance['limit'] as int
          : null,
      remaining: allowance['remaining'] is int
          ? allowance['remaining'] as int
          : null,
      used: allowance['used'] is int ? allowance['used'] as int : 0,
      reserved: allowance['reserved'] is int ? allowance['reserved'] as int : 0,
      periodEndsAt: allowance['periodEndsAt'] as String?,
      warning: json['warning'] as String?,
    );
  }
  final Json catalog;
  final bool active, trial, verificationFresh;
  final int? allowanceLimit, remaining;
  final int used, reserved;
  final String? expiresAt, periodEndsAt, warning;
  DateTime? get expiry =>
      expiresAt == null ? null : DateTime.tryParse(expiresAt!)?.toUtc();
  bool isCurrentAt(DateTime now) =>
      active && verificationFresh && expiry != null && expiry!.isAfter(now);
  bool get canConsult =>
      isCurrentAt(DateTime.now().toUtc()) &&
      catalog['consultationEnabled'] == true &&
      allowanceLimit != null &&
      remaining != null &&
      remaining! > 0;
}

/// A client purchase callback never grants access by itself. This predicate is
/// also used by tests to keep the completion decision independent of UI state.
bool mayCompleteVerifiedPurchase(Json response, {required bool sameAccount}) =>
    sameAccount &&
    response['verified'] == true &&
    response['completePurchase'] == true;

class EshaPurchases extends ChangeNotifier {
  EshaPurchases(this.api, {InAppPurchase? store, DateTime Function()? now})
    : _store = store ?? InAppPurchase.instance,
      _now = now ?? DateTime.now;
  final KorlixApi api;
  final InAppPurchase _store;
  final DateTime Function() _now;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Timer? _accessTimer, _refreshTimer;
  OwnerSnapshot? _membershipOwner;
  DateTime? _checkedAt;
  static const freshnessWindow = Duration(minutes: 15);
  static const refreshInterval = Duration(minutes: 10);
  bool _needsVerification = true;
  bool _foreground = true;
  final Map<String, PurchaseDetails> _pendingVerification = {};
  final Set<String> _verifying = {};
  bool _disposed = false;
  int _refreshEpoch = 0;
  int _membershipRevision = 0;
  int _verificationRevision = 0;
  Json catalog = {};
  MembershipStatus _membership = const MembershipStatus();
  MembershipStatus get membership => _membership;
  bool get hasCurrentStatus =>
      _membershipOwner != null &&
      api.isOwner(_membershipOwner!) &&
      !_needsVerification &&
      _checkedAt != null &&
      !_now().toUtc().isBefore(_checkedAt!) &&
      _now().toUtc().difference(_checkedAt!) < freshnessWindow;
  bool get hasDeveloperAccess =>
      hasCurrentStatus &&
      object(membership.catalog['appAccess'])['active'] == true &&
      object(membership.catalog['appAccess'])['source'] == 'developer';
  bool get hasAppAccess =>
      hasDeveloperAccess ||
      (hasCurrentStatus && membership.isCurrentAt(_now().toUtc()));
  bool get canConsult =>
      hasAppAccess &&
      membership.catalog['consultationEnabled'] == true &&
      membership.allowanceLimit != null &&
      (membership.remaining ?? 0) > 0;
  bool get needsVerification =>
      api.session != null &&
      (!hasCurrentStatus ||
          (!hasDeveloperAccess &&
              membership.active &&
              !membership.isCurrentAt(_now().toUtc())));
  String get accessMessage {
    if (api.session == null) {
      return 'Sign in to start or restore your Esha membership. An eligible 3-day trial begins only after store confirmation.';
    }
    if (loading && !hasAppAccess) return 'Checking your Esha membership…';
    if (needsVerification) {
      return 'Connect to verify your Esha membership. Your saved collection is kept while access is paused.';
    }
    if (!hasAppAccess) {
      return 'An active Esha trial or subscription is required to explore products, build edits and use your vanity and look studio.';
    }
    if (hasDeveloperAccess) {
      return 'Your developer access is active. Store subscriptions and paid AI are managed separately.';
    }
    return membership.trial
        ? 'Your store-verified Esha trial is active.'
        : 'Your store-verified Esha membership is active.';
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) _refreshTimer?.cancel();
  }

  void _clearAccess() {
    _accessTimer?.cancel();
    _refreshTimer?.cancel();
    _accessTimer = null;
    _membershipOwner = null;
    _checkedAt = null;
    _needsVerification = true;
    _membership = const MembershipStatus();
  }

  void _acceptStatus(Json status, OwnerSnapshot owner) {
    if (!api.isOwner(owner)) return;
    ++_verificationRevision;
    _accessTimer?.cancel();
    _refreshTimer?.cancel();
    _membership = MembershipStatus.fromJson(status);
    _membershipOwner = owner;
    _checkedAt = _now().toUtc();
    _needsVerification =
        object(status['membership'])['active'] is! bool ||
        (status['warning'] is String &&
            (status['warning'] as String).trim().isNotEmpty);
    if (!hasCurrentStatus) return;
    final untilExpiry = !hasDeveloperAccess && hasAppAccess
        ? membership.expiry!.difference(_checkedAt!)
        : freshnessWindow;
    // Quietly refresh before the in-memory verification lease ends. Neither
    // interval starts or extends a trial, which comes only from the store.
    // A developer grant has no store expiry and must renew this same lease.
    _accessTimer = Timer(
      untilExpiry < freshnessWindow ? untilExpiry : freshnessWindow,
      () {
        if (_disposed || !api.isOwner(owner)) return;
        _needsVerification = true;
        _notify();
        if (_foreground) unawaited(refresh(requireVerification: true));
      },
    );
    if (_foreground && hasAppAccess && untilExpiry > refreshInterval) {
      _refreshTimer = Timer(refreshInterval, () {
        if (!_disposed && _foreground && api.isOwner(owner)) {
          unawaited(refresh());
        }
      });
    }
  }

  ProductDetails? product;
  String? offerToken, localizedMonthlyPrice, error, message;
  bool? trialEligible;
  bool busy = false,
      loading = false,
      awaitingApproval = false,
      storeAvailable = false,
      storeTermsVerified = false;
  int? _offerLimit(String period) {
    final value = object(catalog['consultationLimits'])[period];
    return value is int && value > 0 ? value : null;
  }

  int? get trialConsultationLimit => _offerLimit('trial');
  int? get monthlyConsultationLimit => _offerLimit('monthly');
  bool get supported =>
      !kIsWeb && (api.platform == 'ios' || api.platform == 'android');
  bool get catalogReady =>
      catalog['purchasesEnabled'] == true &&
      catalog['storeConfigurationVerified'] == true &&
      catalog['allowanceConfigured'] == true &&
      trialConsultationLimit != null &&
      monthlyConsultationLimit != null &&
      catalog['state'] == 'ready';
  bool get canPurchase =>
      supported &&
      api.session != null &&
      hasCurrentStatus &&
      catalogReady &&
      storeAvailable &&
      storeTermsVerified &&
      product != null &&
      !busy &&
      !loading &&
      !awaitingApproval &&
      !hasUnverifiedPurchase &&
      !hasAppAccess;
  String get productId =>
      object(catalog['product'])['productId'] as String? ??
      (api.provider == 'apple'
          ? 'com.korlixdeveloper.esha.monthly'
          : 'esha_monthly');
  bool get hasUnverifiedPurchase => _pendingVerification.isNotEmpty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearStoreTerms() {
    product = null;
    trialEligible = null;
    storeTermsVerified = false;
    localizedMonthlyPrice = null;
    offerToken = null;
  }

  void applyAllowance(Json allowance) {
    ++_membershipRevision;
    _membership = MembershipStatus.fromJson({
      ...membership.catalog,
      'allowance': allowance,
    });
    _notify();
  }

  Future<void> initialize() async {
    if (supported) {
      _subscription = _store.purchaseStream.listen(
        (updates) {
          for (final purchase in updates) {
            unawaited(_handle(purchase));
          }
        },
        onError: (Object _) {
          busy = false;
          error = 'The store purchase update could not be read. Use Restore purchases to check again.';
          _notify();
        },
      );
    }
    await refresh();
  }

  void accountChanged() {
    ++_refreshEpoch;
    ++_membershipRevision;
    _clearAccess();
    busy = false;
    loading = false;
    error = null;
    message = null;
    _clearStoreTerms();
    _notify();
    unawaited(refresh());
  }

  Future<void> refresh({bool requireVerification = false}) async {
    final epoch = ++_refreshEpoch,
        authEpoch = api.epoch,
        user = api.session?.userId,
        membershipRevision = _membershipRevision,
        verificationRevision = _verificationRevision;
    bool current() =>
        !_disposed &&
        epoch == _refreshEpoch &&
        authEpoch == api.epoch &&
        user == api.session?.userId;
    if (requireVerification) {
      _accessTimer?.cancel();
      _refreshTimer?.cancel();
      _needsVerification = true;
    }
    loading = true;
    error = null;
    _notify();
    try {
      final remote = user == null
          ? await api.billingCatalog()
          : await api.billingStatus();
      if (!current()) return;
      catalog = remote;
      if (membershipRevision == _membershipRevision) {
        if (user == null) {
          _clearAccess();
        } else {
          _acceptStatus(remote, OwnerSnapshot(authEpoch, user));
        }
      } else if (verificationRevision == _verificationRevision &&
          user != null) {
        // An in-flight consultation can update its allowance while a mandatory
        // check runs. Keep that usage update without losing the new entitlement.
        _acceptStatus({
          ...remote,
          'allowance': membership.catalog['allowance'],
        }, OwnerSnapshot(authEpoch, user));
      }
      _clearStoreTerms();
      if (supported && !hasDeveloperAccess) {
        try {
          final available = await _store.isAvailable();
          if (!current()) return;
          storeAvailable = available;
          if (available && remote['storeConfigurationVerified'] == true) {
            final details = await _store.queryProductDetails({productId});
            if (!current()) return;
            if (details.error != null) {
              throw const EshaException(
                'STORE_UNAVAILABLE',
                'The store could not load the current subscription terms.',
              );
            }
            await _selectProduct(details.productDetails, current);
          }
        } catch (e) {
          if (!current()) return;
          // Storefront prices are needed for a new checkout, not for an
          // existing entitlement freshly verified by the membership server.
          _clearStoreTerms();
          error = e is EshaException ? e.message : 'The store could not load subscription options. Please try again.';
        }
      }
      if (!current()) return;
      if (awaitingApproval) {
        message = 'This purchase is awaiting store approval. You can restore purchases to check again.';
      } else if (hasDeveloperAccess) {
        message = accessMessage;
      } else if (!catalogReady && !hasAppAccess) {
        message = 'Membership is being prepared for launch. No trial or payment starts in this preview.';
      }
      if (user != null) unawaited(retryVerification());
    } catch (e) {
      if (!current()) return;
      error = e is EshaException
          ? e.message
          : 'Membership could not be checked. Please try again.';
      // An old local status can never authorize a new live consultation.
      if (verificationRevision == _verificationRevision) {
        _clearAccess();
        catalog = {};
      }
      _clearStoreTerms();
    } finally {
      if (current()) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> _selectProduct(
    List<ProductDetails> products,
    bool Function() current,
  ) async {
    _clearStoreTerms();
    final spec = object(catalog['product']);
    if (api.provider == 'apple') {
      for (final item in products.whereType<AppStoreProduct2Details>()) {
        if (item.id != productId) continue;
        final subscription = item.sk2Product.subscription;
        if (subscription == null ||
            subscription.subscriptionPeriod.value != 1 ||
            subscription.subscriptionPeriod.unit !=
                SK2SubscriptionPeriodUnit.month) {
          continue;
        }
        if (item.currencyCode == 'USD' &&
            (item.rawPrice - 4.99).abs() > 0.001) {
          continue;
        }
        final eligible = await SK2Product.isIntroductoryOfferEligible(item.id);
        if (!current()) return;
        final correctTrial = subscription.promotionalOffers.any(
          (offer) =>
              offer.type == SK2SubscriptionOfferType.introductory &&
              offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial &&
              offer.price == 0 &&
              offer.period.value == 3 &&
              offer.period.unit == SK2SubscriptionPeriodUnit.day &&
              offer.periodCount == 1,
        );
        if (eligible && !correctTrial) {
          error = 'The store trial configuration does not match the advertised 3 days. Please try again after it is updated.';
          continue;
        }
        product = item;
        localizedMonthlyPrice = item.price;
        trialEligible = eligible;
        storeTermsVerified = true;
        break;
      }
    } else {
      GooglePlayProductDetails? regular;
      SubscriptionOfferDetailsWrapper? regularOffer;
      var advertisedTrialReturned = false;
      for (final item in products.whereType<GooglePlayProductDetails>()) {
        if (item.id != productId || item.subscriptionIndex == null) continue;
        final offers = item.productDetails.subscriptionOfferDetails;
        if (offers == null ||
            item.subscriptionIndex! < 0 ||
            item.subscriptionIndex! >= offers.length) {
          continue;
        }
        final offer = offers[item.subscriptionIndex!];
        if (offer.basePlanId != spec['basePlanId']) continue;
        // A returned offer has already passed Google Play's eligibility filter.
        // A malformed eligible trial is a configuration problem, not a reason
        // to silently substitute an immediately paid monthly plan.
        if (offer.offerId == spec['offerId']) advertisedTrialReturned = true;
        if (offer.offerIdToken.isEmpty ||
            offer.installmentPlanDetails != null) {
          continue;
        }
        final phases = offer.pricingPhases;
        if (phases.isEmpty) continue;
        final monthly = phases.last;
        if (monthly.billingPeriod != 'P1M' ||
            monthly.recurrenceMode != RecurrenceMode.infiniteRecurring ||
            monthly.priceAmountMicros <= 0) {
          continue;
        }
        if (monthly.priceCurrencyCode == 'USD' &&
            monthly.priceAmountMicros != 4990000) {
          continue;
        }
        if (offer.offerId == spec['offerId'] &&
            phases.length == 2 &&
            phases.first.billingPeriod == 'P3D' &&
            phases.first.priceAmountMicros == 0 &&
            phases.first.billingCycleCount == 1 &&
            phases.first.recurrenceMode == RecurrenceMode.finiteRecurring) {
          product = item;
          offerToken = offer.offerIdToken;
          localizedMonthlyPrice = monthly.formattedPrice;
          trialEligible = true;
          storeTermsVerified = true;
          break;
        }
        if (offer.offerId == null && phases.length == 1) {
          regular = item;
          regularOffer = offer;
        }
      }
      if (product == null && regular != null && !advertisedTrialReturned) {
        product = regular;
        offerToken = regularOffer!.offerIdToken;
        localizedMonthlyPrice = regularOffer.pricingPhases.last.formattedPrice;
        trialEligible = false;
        storeTermsVerified = true;
      }
      if (product == null && advertisedTrialReturned) {
        error = 'The store trial configuration does not match the advertised 3 days. Please try again after it is updated.';
      }
    }
    if (product == null && catalogReady) error ??= 'The store has not returned the configured Esha monthly plan. Please try again later.';
  }

  Future<void> purchase() async {
    if (!canPurchase) return;
    final snapshot = api.owner(), selected = product!;
    final selectedOfferToken = offerToken;
    final selectedSpec = object(catalog['product']);
    busy = true;
    error = null;
    message = 'Preparing your store purchase…';
    _notify();
    try {
      final prepared = await api.preparePurchase(selected.id);
      api.verifyOwner(snapshot);
      final accountId = prepared['accountId'];
      if (prepared['canPurchase'] != true ||
          prepared['productId'] != selected.id ||
          prepared['bundleId'] != 'com.korlixdeveloper.esha' ||
          accountId is! String ||
          accountId.isEmpty) {
        throw const EshaException(
          'STORE_NOT_READY',
          'Your store purchase could not be prepared safely. Refresh membership and try again.',
        );
      }
      if (api.provider == 'apple' && accountId != snapshot.userId) {
        throw const EshaException(
          'OWNER_MISMATCH',
          'The store account binding did not match your Korlix account.',
        );
      }
      final PurchaseParam param;
      if (api.provider == 'apple') {
        param = Sk2PurchaseParam(
          productDetails: selected,
          applicationUserName: accountId,
        );
      } else {
        if (prepared['basePlanId'] != selectedSpec['basePlanId'] ||
            prepared['offerId'] != selectedSpec['offerId'] ||
            selectedOfferToken == null ||
            selectedOfferToken.isEmpty) {
          throw const EshaException(
            'STORE_NOT_READY',
            'Refresh the current Google Play subscription offer.',
          );
        }
        param = GooglePlayPurchaseParam(
          productDetails: selected,
          applicationUserName: accountId,
          offerToken: selectedOfferToken,
        );
      }
      api.verifyOwner(snapshot);
      final opened = await _store.buyNonConsumable(purchaseParam: param);
      if (!api.isOwner(snapshot)) return;
      if (!opened) {
        throw const EshaException(
          'STORE_UNAVAILABLE',
          'The store purchase sheet did not open. Please try again.',
        );
      }
      if (busy && !awaitingApproval && !hasUnverifiedPurchase) {
        message = 'Confirm the price and renewal terms in the store sheet.';
      }
    } catch (e) {
      if (api.isOwner(snapshot)) {
        busy = false;
        error = e is EshaException
            ? e.message
            : 'The store could not start this purchase.';
      }
    }
    _notify();
  }

  String _purchaseKey(PurchaseDetails purchase) =>
      '${purchase.productID}:${purchase.purchaseID ?? purchase.verificationData.serverVerificationData}';
  Future<void> _handle(PurchaseDetails purchase) async {
    if (_disposed) return;
    final expected = api.provider == 'apple'
        ? 'com.korlixdeveloper.esha.monthly'
        : 'esha_monthly';
    if (purchase.productID != expected) return;
    // The Android plugin labels every restored item "restored", including
    // purchases whose original BillingClient state is still pending.
    final pending =
        purchase.status == PurchaseStatus.pending ||
        (purchase is GooglePlayPurchaseDetails &&
            purchase.billingClientPurchase.purchaseState ==
                PurchaseStateWrapper.pending);
    if (pending) {
      awaitingApproval = true;
      busy = false;
      error = null;
      message = 'This purchase is awaiting store approval. Access starts after verification. You can restore purchases to check again.';
      _notify();
      return;
    }
    awaitingApproval = false;
    if (purchase.status == PurchaseStatus.canceled) {
      busy = false;
      message = 'Purchase canceled. No Esha membership was activated.';
      _notify();
      return;
    }
    if (purchase.status == PurchaseStatus.error) {
      busy = false;
      error = 'The store could not complete this purchase. Restore purchases if you were charged.';
      _notify();
      return;
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    final key = _purchaseKey(purchase);
    _pendingVerification[key] = purchase;
    if (api.session == null) {
      busy = false;
      message =
          'Sign in to the Korlix account that owns this purchase to verify it.';
      _notify();
      return;
    }
    if (!_verifying.add(key)) return;
    final snapshot = api.owner();
    try {
      final Json payload = {'productId': purchase.productID};
      if (api.provider == 'apple') {
        if (purchase.purchaseID == null || purchase.purchaseID!.isEmpty) {
          throw const EshaException(
            'VERIFICATION_PENDING',
            'The App Store transaction identifier is not available yet. Restore purchases to retry.',
          );
        }
        payload['purchaseId'] = purchase.purchaseID;
      } else {
        final token = purchase.verificationData.serverVerificationData;
        if (token.isEmpty) {
          throw const EshaException(
            'VERIFICATION_PENDING',
            'The Google Play purchase token is not available yet. Restore purchases to retry.',
          );
        }
        payload['purchaseToken'] = token;
      }
      final response = await api.verifyPurchase(payload);
      if (!mayCompleteVerifiedPurchase(
        response,
        sameAccount: api.isOwner(snapshot),
      )) {
        throw const EshaException(
          'VERIFICATION_PENDING',
          'Store verification is pending. Access will appear after it is confirmed.',
        );
      }
      ++_membershipRevision;
      catalog = object(response['status']);
      _acceptStatus(catalog, snapshot);
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
      if (!api.isOwner(snapshot)) return;
      _pendingVerification.remove(key);
      error = null;
      message = hasDeveloperAccess
          ? accessMessage
          : hasAppAccess
          ? 'Your Esha membership is verified.'
          : needsVerification
          ? accessMessage
          : 'Purchase checked. This membership is not currently active.';
    } catch (e) {
      if (api.isOwner(snapshot)) error = e is EshaException ? e.message : 'Your purchase could not be verified yet. Use Retry verification or Restore purchases. No local purchase status grants access.';
    } finally {
      _verifying.remove(key);
      if (api.isOwner(snapshot)) busy = false;
      _notify();
    }
  }

  Future<void> retryVerification() async {
    if (api.session == null) return;
    for (final purchase in _pendingVerification.values.toList()) {
      await _handle(purchase);
    }
  }

  Future<void> restore() async {
    if (_disposed || busy || loading) return;
    if (api.session == null) {
      error = 'Sign in to the Korlix account that owns your membership, then restore purchases.';
      _notify();
      return;
    }
    final snapshot = api.owner();
    final wasAwaitingApproval = awaitingApproval;
    busy = true;
    error = null;
    message = 'Checking the store for existing purchases…';
    _notify();
    try {
      if (!await _store.isAvailable()) {
        throw const EshaException(
          'STORE_UNAVAILABLE',
          'The store is unavailable on this device.',
        );
      }
      api.verifyOwner(snapshot);
      // A successful restore returning no pending purchase clears an old
      // approval state; a failed restore leaves that state recoverable.
      awaitingApproval = false;
      await _store.restorePurchases();
      if (!api.isOwner(snapshot)) return;
      await refresh();
      if (!api.isOwner(snapshot)) return;
      message = awaitingApproval
          ? 'This purchase is still awaiting store approval. No membership has been activated.'
          : hasDeveloperAccess
          ? accessMessage
          : hasAppAccess
          ? 'Your Esha membership is verified.'
          : 'Restore requested. Store results will be verified as they arrive.';
    } catch (e) {
      if (api.isOwner(snapshot)) {
        awaitingApproval = awaitingApproval || wasAwaitingApproval;
        error = e is EshaException
            ? e.message
            : 'The store could not restore purchases. Please try again.';
      }
    } finally {
      if (api.isOwner(snapshot)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> manage() async {
    final uri = Uri.parse(
      api.provider == 'apple' ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions?sku=esha_monthly&package=com.korlixdeveloper.esha',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      error = 'Open your App Store or Google Play account to manage the Esha subscription.';
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_refreshEpoch;
    _accessTimer?.cancel();
    _refreshTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
