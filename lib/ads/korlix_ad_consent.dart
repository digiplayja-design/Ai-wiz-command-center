import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// The native boundary is injectable so consent tests never request real ads.
abstract interface class KorlixAdConsentGateway {
  Future<void> requestConsentInfoUpdate();
  Future<void> loadAndShowConsentFormIfRequired();
  Future<bool> canRequestAds();
  Future<bool> isPrivacyOptionsRequired();
  Future<void> showPrivacyOptionsForm();
  Future<void> initializeAds();
}

/// Owns the Android advertising consent flow for one app process.
///
/// UMP owns persisted consent. No consent strings or inferred geography are
/// cached by the app. Call [prepareAds] before each ad request, and listen for
/// [adsReady] changes to discard ads when the privacy form opens.
class KorlixAdConsent extends ChangeNotifier {
  factory KorlixAdConsent({
    required KorlixAdConsentGateway gateway,
    bool? supported,
    Duration requestTimeout = const Duration(seconds: 12),
  }) => KorlixAdConsent._(
    gateway,
    supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
    requestTimeout,
  );

  KorlixAdConsent._(this._gateway, this._supported, this._requestTimeout);

  static final KorlixAdConsent instance = KorlixAdConsent(
    gateway: _GoogleAdConsentGateway(),
  );

  final KorlixAdConsentGateway _gateway;
  final bool _supported;
  final Duration _requestTimeout;
  Future<void>? _sessionPreparation;
  Future<void>? _sdkInitialization;
  Future<bool>? _privacyOperation;
  bool _authorized = false;
  bool _sdkInitialized = false;
  bool _privacyOptionsRequired = false;
  bool _privacyFormVisible = false;
  bool _disposed = false;
  int _privacyRevision = 0;

  bool get adsReady =>
      _supported &&
      !_disposed &&
      _authorized &&
      _sdkInitialized &&
      !_privacyFormVisible;

  bool get privacyOptionsRequired => _supported && _privacyOptionsRequired;

  bool get privacyOptionsShowing => _privacyFormVisible;

  /// Requests fresh information once per app session, then checks UMP before
  /// every ad request. Concurrent banners share consent forms and SDK startup.
  Future<bool> prepareAds() async {
    if (!_supported || _disposed) return false;
    await (_sessionPreparation ??= _prepareSession());
    final privacyOperation = _privacyOperation;
    if (privacyOperation != null) await privacyOperation;
    if (_disposed) return false;
    await _refreshConsentState();
    return adsReady;
  }

  Future<void> _prepareSession() async {
    try {
      await _gateway.requestConsentInfoUpdate().timeout(_requestTimeout);
      if (_disposed) return;
      // A form includes the user's decision time: never time out or dismiss it.
      await _gateway.loadAndShowConsentFormIfRequired();
    } catch (_) {
      // UMP may still permit ads using consent from a previous app session.
      // Only canRequestAds, never an app-side cached choice, decides that.
    }
    if (!_disposed) await _refreshConsentState();
  }

  Future<void> _refreshConsentState() async {
    final revision = _privacyRevision;
    bool allowed = false;
    try {
      allowed = await _gateway.canRequestAds().timeout(_requestTimeout);
    } catch (_) {
      // Unknown consent fails closed.
    }

    bool? required;
    try {
      required = await _gateway.isPrivacyOptionsRequired().timeout(
        _requestTimeout,
      );
    } catch (_) {
      // Keep an already-required entry point available after a transient error.
    }

    if (_disposed || revision != _privacyRevision) return;
    _authorized = allowed;
    if (required != null) _privacyOptionsRequired = required;

    if (allowed && !_sdkInitialized) {
      try {
        await (_sdkInitialization ??= _gateway.initializeAds().timeout(
          _requestTimeout,
        ));
        _sdkInitialized = true;
      } catch (_) {
        // Advertising failures must never block use of the app. Keep the same
        // future so a late native startup cannot cause duplicate initialization.
      }
    }
    _notify();
  }

  /// Presents UMP's privacy options. Returns false if no form could be shown.
  /// Existing banners must observe [adsReady] and dispose when it becomes false.
  Future<bool> showPrivacyOptions() async {
    if (!_supported || _disposed) return false;
    final existing = _privacyOperation;
    if (existing != null) return existing;
    final operation = _showPrivacyOptions();
    _privacyOperation = operation;
    try {
      return await operation;
    } finally {
      if (identical(_privacyOperation, operation)) _privacyOperation = null;
    }
  }

  Future<bool> _showPrivacyOptions() async {
    _privacyRevision++;
    _privacyFormVisible = true;
    _notify();
    bool shown = false;
    try {
      await (_sessionPreparation ??= _prepareSession());
      if (_disposed || !_privacyOptionsRequired) return false;
      // As above, leave the user's decision time unbounded.
      await _gateway.showPrivacyOptionsForm();
      shown = true;
    } catch (_) {
      // Callers can display a generic retry message without exposing SDK errors.
    } finally {
      if (!_disposed) await _refreshConsentState();
      _privacyFormVisible = false;
      _notify();
    }
    return shown;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _GoogleAdConsentGateway implements KorlixAdConsentGateway {
  @override
  Future<void> requestConsentInfoUpdate() async {
    final completed = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!completed.isCompleted) completed.complete();
      },
      (error) {
        if (!completed.isCompleted) completed.completeError(error);
      },
    );
    await completed.future;
  }

  @override
  Future<void> loadAndShowConsentFormIfRequired() async {
    FormError? error;
    await ConsentForm.loadAndShowConsentFormIfRequired(
      (value) => error = value,
    );
    if (error != null) throw error!;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> isPrivacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptionsForm() async {
    FormError? error;
    await ConsentForm.showPrivacyOptionsForm((value) => error = value);
    if (error != null) throw error!;
  }

  @override
  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
  }
}
