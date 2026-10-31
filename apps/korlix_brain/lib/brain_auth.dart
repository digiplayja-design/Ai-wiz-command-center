import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';

const brainBackendUrl = String.fromEnvironment(
  'KORLIX_BACKEND_URL',
  defaultValue: 'https://chee-chai-chee-backend.onrender.com',
);
const existingKorlixAccountMessage =
    'You already have a KORLIX account.\n\n'
    'Sign in using the same email address and password you use for KORLIX AI. '
    'Your account also works with KORLIX Brain.';

class BrainAuthException implements Exception {
  const BrainAuthException(this.message, {this.code, this.status = 0});
  final String message;
  final String? code;
  final int status;
  bool get existingAccount =>
      code == 'KORLIX_ACCOUNT_EXISTS' ||
      code == 'user_already_exists' ||
      RegExp(
        r'user already registered|email.*already (registered|exists)',
        caseSensitive: false,
      ).hasMatch(message);
  bool get emailUnconfirmed =>
      code == 'email_not_confirmed' ||
      message.toLowerCase().contains('email not confirmed');
  @override
  String toString() => message;
}

class BrainAuthController extends ChangeNotifier {
  BrainAuthController({
    http.Client? client,
    KorlixTokenStore? tokenStore,
    this.backendUrl = brainBackendUrl,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _tokens = tokenStore ?? KorlixTokenStore(namespace: 'korlix_brain') {
    final uri = Uri.parse(backendUrl);
    if (uri.scheme != 'https' && !(kDebugMode && uri.host == 'localhost')) {
      throw ArgumentError('KORLIX sign-in requires HTTPS.');
    }
    sessions = KorlixSessionRefreshCoordinator(
      current: () => session,
      revision: () => revision,
      refresh: _refresh,
      persist: (value, current) async {
        if (current()) {
          await _tokens.write(
            accessToken: value.accessToken,
            refreshToken: value.refreshToken,
            isCurrent: current,
          );
        }
      },
      publish: (value) {
        session = value;
        _scheduleRefresh();
        notifyListeners();
      },
      clear: _clear,
    );
  }

  final String backendUrl;
  final http.Client _client;
  final bool _ownsClient;
  final KorlixTokenStore _tokens;
  late final KorlixSessionRefreshCoordinator sessions;
  KorlixAuthSession? session;
  int revision = 0;
  bool ready = false, _disposed = false;
  String? restoreError;
  String _deviceId = '';
  bool _deviceReady = false;
  String get platform => kIsWeb ? 'web' : defaultTargetPlatform.name;
  Timer? _refreshTimer;
  Future<void>? _initializing;

  Map<String, String> get deviceHeaders => {
    'X-Korlix-Device-Id': _deviceId,
    'X-Korlix-Device-Label': 'Brain ($platform)',
    'X-Korlix-Platform': platform,
    'X-Korlix-App': 'korlix_brain',
  };
  Map<String, Object> get _deviceBody => {
    'device_id': _deviceId,
    'device_label': 'Brain ($platform)',
    'platform': platform,
    'client_app': 'korlix_brain',
  };
  Map<String, String> headers() => {
    ...deviceHeaders,
    if (session != null) 'Authorization': 'Bearer ${session!.accessToken}',
  };

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('korlix_brain_device_id') ?? '';
      if (_deviceId.isEmpty) {
        final random = Random.secure();
        _deviceId =
            'korlix_brain_${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        if (!await prefs.setString('korlix_brain_device_id', _deviceId)) {
          throw const BrainAuthException(
            'Device settings could not be saved. Please try again.',
          );
        }
      }
      _deviceReady = true;
      final value = await _tokens.read();
      if (value != null) {
        session = KorlixAuthSession(
          accessToken: value.accessToken,
          refreshToken: value.refreshToken,
          email: prefs.getString('korlix_brain_email'),
        );
        _setConsentScope();
        await sessions.ensureFresh(force: true);
      }
    } catch (error) {
      restoreError = error.toString();
    } finally {
      ready = true;
      _scheduleRefresh();
      if (!_disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$backendUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              ...deviceHeaders,
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const BrainAuthException(
        'The connection timed out. Please try again.',
      );
    } on http.ClientException {
      throw const BrainAuthException(
        'Could not connect to KORLIX. Check your connection and try again.',
      );
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const BrainAuthException(
        'KORLIX returned an unreadable response. Please try again.',
      );
    }
    if (response.statusCode >= 400) {
      throw BrainAuthException(
        data['error']?.toString() ?? 'Please try again.',
        code: data['code']?.toString(),
        status: response.statusCode,
      );
    }
    return data;
  }

  Future<bool> authenticate({
    required String email,
    required String password,
    bool signup = false,
    String? ageBand,
    bool acceptedPolicies = false,
    bool parentPermission = false,
  }) async {
    await initialize();
    if (!_deviceReady) {
      _initializing = null;
      await initialize();
      if (!_deviceReady) {
        throw const BrainAuthException(
          'Device settings could not be saved. Please restart Brain and try again.',
        );
      }
    }
    final operation = ++revision;
    final cleanEmail = email.trim().toLowerCase();
    final data = await _post(signup ? '/api/auth/signup' : '/api/auth/signin', {
      'email': cleanEmail,
      'password': password,
      ..._deviceBody,
      if (signup) 'signup_plan': 'basic',
      if (signup)
        'signup_eligibility': {
          'age_band': ageBand,
          'terms_accepted': acceptedPolicies,
          'privacy_acknowledged': acceptedPolicies,
          'parent_permission': parentPermission,
          'policy_version': '2026-10-06',
        },
    });
    if (operation != revision || _disposed) throw const KorlixSessionChanged();
    final raw = data['session'];
    if (raw is! Map ||
        raw['access_token'] is! String ||
        (raw['access_token'] as String).isEmpty) {
      if (signup) return false;
      throw const BrainAuthException(
        'Sign-in did not return a session. Please try again.',
      );
    }
    final next = KorlixAuthSession(
      accessToken: raw['access_token'] as String,
      refreshToken: raw['refresh_token']?.toString(),
      email: cleanEmail,
    );
    await _tokens.write(
      accessToken: next.accessToken,
      refreshToken: next.refreshToken,
      isCurrent: () => operation == revision && !_disposed,
    );
    if (operation != revision || _disposed) throw const KorlixSessionChanged();
    final prefs = await SharedPreferences.getInstance();
    if (operation != revision || _disposed) throw const KorlixSessionChanged();
    await prefs.setString('korlix_brain_email', cleanEmail);
    if (operation != revision || _disposed) throw const KorlixSessionChanged();
    session = next;
    restoreError = null;
    _setConsentScope();
    _scheduleRefresh();
    notifyListeners();
    return true;
  }

  Future<void> requestPasswordReset(String email) async {
    await initialize();
    await _post('/api/auth/password-reset', {
      'email': email.trim().toLowerCase(),
    });
  }

  Future<KorlixAuthSession?> _refresh(KorlixAuthSession old) async {
    if (old.refreshToken?.isNotEmpty != true) return null;
    try {
      final data = await _post('/api/auth/refresh', {
        'refresh_token': old.refreshToken,
        ..._deviceBody,
      }, timeout: const Duration(seconds: 60));
      final raw = data['session'];
      if (raw is! Map ||
          raw['access_token'] is! String ||
          (raw['access_token'] as String).isEmpty) {
        throw const KorlixSessionRefreshUnavailable();
      }
      return KorlixAuthSession(
        accessToken: raw['access_token'] as String,
        refreshToken: raw['refresh_token']?.toString() ?? old.refreshToken,
        email: old.email,
      );
    } on BrainAuthException catch (error) {
      if (korlixRefreshWasRejected(error.status, {
        'error': error.message,
        'code': error.code,
      })) {
        return null;
      }
      rethrow;
    }
  }

  void _setConsentScope() {
    String? scope;
    if (session != null) {
      try {
        final parts = session!.accessToken.split('.');
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ) as Map;
        if (claims['iss'] is String && claims['sub'] is String) {
          scope = jsonEncode([claims['iss'], claims['sub']]);
        }
      } catch (_) {
        /* UI scoping only; the backend validates every request. */
      }
    }
    KorlixThirdPartyAiConsent.setAccountScope(scope);
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final delay = sessions.nextRefreshDelay();
    if (!_disposed && delay != null) {
      _refreshTimer = Timer(delay, () => unawaited(resume()));
    }
  }

  Future<void> resume() async {
    if (session == null || _disposed) return;
    try {
      await sessions.ensureFresh();
    } catch (_) {
      /* Keep recoverable sessions; requests show an actionable error. */
    }
    _scheduleRefresh();
  }

  Future<void> _clear() async {
    revision++;
    session = null;
    _refreshTimer?.cancel();
    _setConsentScope();
    if (!_disposed) notifyListeners();
    await _tokens.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('korlix_brain_email');
  }

  Future<void> signOut() async {
    final old = session;
    await _clear();
    if (old != null) {
      try {
        await _post(
          '/api/auth/signout',
          _deviceBody,
          accessToken: old.accessToken,
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        /* Local secure credentials have already been removed. */
      }
    }
  }

  Future<void> requestAccountDeletion() async {
    final before = revision;
    final current = await sessions.ensureFresh();
    if (current == null || before != revision) {
      throw const KorlixSessionChanged();
    }
    await _post('/api/account/delete-request', {
      'reason': 'Requested from standalone KORLIX Brain.',
    }, accessToken: current.accessToken);
  }

  @override
  void dispose() {
    _disposed = true;
    revision++;
    _refreshTimer?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
