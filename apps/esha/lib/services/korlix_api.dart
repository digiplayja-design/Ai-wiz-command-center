import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

abstract interface class StringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SecureSessionStore implements StringStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

class PreferenceStore implements StringStore {
  PreferenceStore(this.preferences);
  final SharedPreferences preferences;
  @override
  Future<String?> read(String key) async => preferences.getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await preferences.setString(key, value)) {
      throw const EshaException(
        'LOCAL_STORAGE',
        'Your local collection could not be saved.',
      );
    }
  }

  @override
  Future<void> remove(String key) async {
    await preferences.remove(key);
  }
}

class ServiceConfig {
  ServiceConfig.fromJson(Json json)
    : apiOrigin = json['apiOrigin'] as String? ?? '',
      supabaseUrl = json['supabaseUrl'] as String? ?? '',
      supabasePublishableKey = json['supabasePublishableKey'] as String? ?? '' {
    if (apiOrigin != 'https://chee-chai-chee-backend.onrender.com' ||
        supabaseUrl != 'https://uxtjzjbwtppjvnsoiijv.supabase.co' ||
        !supabasePublishableKey.startsWith('sb_publishable_')) {
      throw const EshaException(
        'CONFIGURATION',
        'Esha could not load its service settings.',
      );
    }
  }
  final String apiOrigin, supabaseUrl, supabasePublishableKey;
}

class AuthSession {
  AuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.profile = const {},
  });
  factory AuthSession.fromJson(Json json) {
    final tokens = object(json['session']);
    final user = object(json['user']);
    if (user['id'] is! String ||
        !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(user['id'] as String) ||
        tokens['access_token'] is! String ||
        tokens['refresh_token'] is! String ||
        tokens['expires_at'] is! num) {
      throw const EshaException(
        'AUTH_REQUIRED',
        'Korlix did not return a complete session. Please sign in again.',
      );
    }
    return AuthSession(
      userId: user['id'] as String,
      email: user['email'] as String? ?? '',
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
      expiresAt: (tokens['expires_at'] as num).toInt(),
      profile: object(json['profile']),
    );
  }
  final String userId, email, accessToken, refreshToken;
  final int expiresAt;
  final Json profile;
  Json toJson() => {
    'user': {'id': userId, 'email': email},
    'session': {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_at': expiresAt,
    },
    'profile': profile,
  };
}

class OwnerSnapshot {
  const OwnerSnapshot(this.epoch, this.userId);
  final int epoch;
  final String userId;
}

class VanityRecord {
  const VanityRecord(this.state, this.version);
  final Vanity? state;
  final int version;
}

abstract interface class VanityGateway {
  Future<VanityRecord> loadVanity();
  Future<VanityRecord> saveVanity(Vanity state, int expectedVersion);
}

class KorlixApi implements VanityGateway {
  KorlixApi({
    required this.config,
    required this.secureStorage,
    required this.localStorage,
    required this.platform,
    http.Client? client,
  }) : _client = client ?? http.Client();
  static const sessionKey = 'esha.native.session.v1';
  static const deviceKey = 'esha.native.device.v1';
  final ServiceConfig config;
  final StringStore secureStorage, localStorage;
  final String platform;
  final http.Client _client;
  AuthSession? _session;
  int _epoch = 0;
  String? _device;
  Future<void>? _refreshing, _closing;
  Future<void> _sessionWrites = Future.value();
  int? _refreshEpoch;
  void Function()? onSessionInvalidated;
  AuthSession? get session => _session;
  int get epoch => _epoch;
  String get provider => platform == 'ios' ? 'apple' : 'google';
  String get deviceLabel =>
      platform == 'ios' ? 'Esha by Korlix iOS' : 'Esha by Korlix Android';

  OwnerSnapshot owner() {
    if (_session == null) {
      throw const EshaException(
        'AUTH_REQUIRED',
        'Sign in to your Korlix account to continue.',
      );
    }
    return OwnerSnapshot(_epoch, _session!.userId);
  }

  bool isOwner(OwnerSnapshot expected) =>
      expected.epoch == _epoch && expected.userId == _session?.userId;
  void verifyOwner(OwnerSnapshot expected) {
    if (!isOwner(expected)) {
      throw const EshaException(
        'SESSION_CHANGED',
        'The active account changed. This result was not applied.',
      );
    }
  }

  Future<void> initializeDevice() async {
    _device ??= await localStorage.read(deviceKey);
    if (_device == null ||
        !RegExp(r'^esha-native-[a-f0-9-]{36}$').hasMatch(_device!)) {
      _device = 'esha-native-${const Uuid().v4()}';
      await localStorage.write(deviceKey, _device!);
    }
  }

  Map<String, String> get _deviceHeaders => {
    'X-Korlix-App': 'esha_by_korlix',
    'X-Korlix-Device-Id': _device!,
    'X-Korlix-Device-Label': deviceLabel,
    'X-Korlix-Platform': platform,
  };
  Json get _deviceBody => {
    'client_app': 'esha_by_korlix',
    'device_id': _device,
    'device_label': deviceLabel,
    'platform': platform,
  };

  Future<AuthSession?> restoreSession() async {
    await initializeDevice();
    final epoch = _epoch;
    final stored = await secureStorage.read(sessionKey);
    if (stored == null) return null;
    try {
      final candidate = AuthSession.fromJson(object(jsonDecode(stored)));
      if (epoch != _epoch) return null;
      _session = candidate;
      final snapshot = owner();
      await authenticated('GET', '/api/me', retryUnauthorized: true);
      verifyOwner(snapshot);
      return _session;
    } on EshaException catch (error) {
      if (epoch == _epoch) _session = null;
      if ([
        'AUTH_REQUIRED',
        'DEVICE_LIMIT',
        'ACCOUNT_UNAVAILABLE',
      ].contains(error.code)) {
        await _writeSession(epoch, null);
        return null;
      }
      rethrow;
    } catch (_) {
      if (epoch == _epoch) {
        _session = null;
        await _writeSession(epoch, null);
      }
      return null;
    }
  }

  Future<AuthSession> signIn(String email, String password) async {
    if (_closing != null) {
      try {
        await _closing;
      } catch (_) {}
    }
    await initializeDevice();
    final epoch = ++_epoch;
    _session = null;
    await _writeSession(epoch, null);
    if (email.trim().isEmpty || password.isEmpty) {
      throw const EshaException(
        'INVALID_INPUT',
        'Enter your Korlix email and password.',
      );
    }
    final result = await _request(
      'POST',
      '${config.apiOrigin}/api/auth/signin',
      headers: _deviceHeaders,
      body: {'email': email.trim(), 'password': password, ..._deviceBody},
    );
    _ensureSuccess(result, signIn: true);
    return _acceptSession(object(result.body), epoch);
  }

  /// A null session means the registration request was accepted but email
  /// confirmation is still required. It never grants membership or signs in.
  Future<AuthSession?> signUp(
    String email,
    String password, {
    required String ageBand,
    required bool termsAccepted,
    required bool privacyAcknowledged,
    required bool parentPermission,
  }) async {
    _validateEmail(email);
    if (password.trim().length < 6) {
      throw const EshaException(
        'INVALID_INPUT',
        'Choose a password with at least 6 characters.',
      );
    }
    if (password != password.trim()) {
      throw const EshaException(
        'INVALID_INPUT',
        'Your password cannot start or end with a space.',
      );
    }
    if (!['16_17', '18_plus'].contains(ageBand)) {
      throw const EshaException(
        'SIGNUP_AGE_REQUIRED',
        'Choose your age range. You must be at least 16 to create an account.',
      );
    }
    if (!termsAccepted || !privacyAcknowledged) {
      throw const EshaException(
        'SIGNUP_POLICIES_REQUIRED',
        'Agree to the Terms of Use and acknowledge the Privacy Policy.',
      );
    }
    if (ageBand == '16_17' && !parentPermission) {
      throw const EshaException(
        'SIGNUP_PARENT_PERMISSION_REQUIRED',
        'You need permission from a parent or guardian to create an account.',
      );
    }
    if (_closing != null) {
      try {
        await _closing;
      } catch (_) {}
    }
    if (_session != null) {
      throw const EshaException(
        'ACCOUNT_ALREADY_ACTIVE',
        'Sign out before creating another Korlix account.',
      );
    }
    await initializeDevice();
    final epoch = ++_epoch;
    await _writeSession(epoch, null);
    final result = await _request(
      'POST',
      '${config.apiOrigin}/api/auth/signup',
      headers: _deviceHeaders,
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'signup_plan': 'basic',
        'signup_eligibility': {
          'age_band': ageBand,
          'terms_accepted': termsAccepted,
          'privacy_acknowledged': privacyAcknowledged,
          'parent_permission': ageBand == '16_17' && parentPermission,
          'policy_version': '2026-10-06',
        },
        ..._deviceBody,
      },
    );
    if (epoch != _epoch) {
      throw const EshaException(
        'SESSION_CHANGED',
        'The active account changed. Please sign in to continue.',
      );
    }
    _ensureSuccess(result, signIn: true);
    final body = object(result.body);
    if (body['success'] != true || !body.containsKey('session')) {
      throw const EshaException(
        'SIGNUP_UNCONFIRMED',
        'The account request could not be confirmed. Check your email before trying again, or try signing in.',
      );
    }
    if (body['session'] == null) return null;
    return _acceptSession(body, epoch);
  }

  Future<void> requestPasswordReset(String email) async {
    _validateEmail(email);
    final result = await _request(
      'POST',
      '${config.apiOrigin}/api/auth/password-reset',
      body: {'email': email.trim().toLowerCase()},
    );
    _ensureSuccess(result);
    if (object(result.body)['success'] != true) {
      throw const EshaException(
        'RESET_UNCONFIRMED',
        'The reset request could not be confirmed. Check your email before requesting another link.',
      );
    }
  }

  void _validateEmail(String email) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const EshaException(
        'INVALID_INPUT',
        'Enter a valid email address.',
      );
    }
  }

  Future<AuthSession> _acceptSession(
    Json body,
    int epoch, [
    String? expectedUser,
  ]) async {
    if (epoch != _epoch) {
      throw const EshaException(
        'SESSION_CHANGED',
        'The active account changed.',
      );
    }
    final candidate = AuthSession.fromJson(body);
    if (expectedUser != null && expectedUser != candidate.userId) {
      throw const EshaException(
        'SESSION_CHANGED',
        'The account changed during session renewal.',
      );
    }
    // Persist before exposing a usable authenticated session. A keychain failure
    // must never degrade to storing refresh tokens in preferences.
    await _writeSession(epoch, candidate);
    if (epoch != _epoch) {
      throw const EshaException(
        'SESSION_CHANGED',
        'The active account changed.',
      );
    }
    _session = candidate;
    return candidate;
  }

  Future<void> _writeSession(int epoch, AuthSession? candidate) {
    final operation = _sessionWrites.catchError((Object _) {}).then((_) async {
      if (epoch != _epoch) return;
      if (candidate == null) {
        await secureStorage.remove(sessionKey);
      } else {
        await secureStorage.write(sessionKey, jsonEncode(candidate.toJson()));
      }
    });
    _sessionWrites = operation;
    return operation;
  }

  Future<void> signOut() async {
    final previous = _session;
    final epoch = ++_epoch;
    _session = null;
    final closing = () async {
      try {
        await _writeSession(epoch, null);
        if (previous == null) return;
        final response = await _request(
          'POST',
          '${config.apiOrigin}/api/auth/signout',
          headers: {
            'Authorization': 'Bearer ${previous.accessToken}',
            ..._deviceHeaders,
          },
          body: {},
        );
        if (response.status != 401) _ensureSuccess(response);
      } catch (_) {
        throw const EshaException(
          'SIGNOUT_UNCONFIRMED',
          'Signed out on this device. Remote session closure was not confirmed; review active devices in your Korlix account.',
        );
      }
    }();
    _closing = closing;
    try {
      await closing;
    } finally {
      if (identical(_closing, closing)) _closing = null;
    }
  }

  Future<void> _refresh() async {
    if (_refreshEpoch == _epoch && _refreshing != null) return _refreshing;
    final snapshot = owner(), previous = _session!;
    final operation = () async {
      final result = await _request(
        'POST',
        '${config.apiOrigin}/api/auth/refresh',
        headers: _deviceHeaders,
        body: {'refresh_token': previous.refreshToken, ..._deviceBody},
      );
      verifyOwner(snapshot);
      if (result.status == 401) {
        final invalidEpoch = ++_epoch;
        _session = null;
        onSessionInvalidated?.call();
        await _writeSession(invalidEpoch, null);
      }
      _ensureSuccess(result);
      await _acceptSession(
        object(result.body),
        snapshot.epoch,
        snapshot.userId,
      );
    }();
    _refreshEpoch = snapshot.epoch;
    _refreshing = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshing, operation)) {
        _refreshing = null;
        _refreshEpoch = null;
      }
    }
  }

  Future<String> _authorizedToken(OwnerSnapshot snapshot) async {
    verifyOwner(snapshot);
    if (_session!.expiresAt * 1000 <
        DateTime.now().millisecondsSinceEpoch + 60000) {
      await _refresh();
    }
    verifyOwner(snapshot);
    return _session!.accessToken;
  }

  Future<Json> authenticated(
    String method,
    String path, {
    Json? body,
    bool retryUnauthorized = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final snapshot = owner();
    var token = await _authorizedToken(snapshot);
    var response = await _request(
      method,
      '${config.apiOrigin}$path',
      headers: {'Authorization': 'Bearer $token', ..._deviceHeaders},
      body: body,
      timeout: timeout,
    );
    verifyOwner(snapshot);
    if (response.status == 401 && retryUnauthorized) {
      await _refresh();
      token = await _authorizedToken(snapshot);
      response = await _request(
        method,
        '${config.apiOrigin}$path',
        headers: {'Authorization': 'Bearer $token', ..._deviceHeaders},
        body: body,
        timeout: timeout,
      );
      verifyOwner(snapshot);
    }
    _ensureSuccess(response);
    if (response.body is! Map) {
      throw const EshaException(
        'INVALID_RESPONSE',
        'The service did not return a complete response.',
      );
    }
    return object(response.body);
  }

  Future<Json> billingCatalog() async {
    final response = await _request(
      'GET',
      '${config.apiOrigin}/api/esha/billing/catalog?provider=$provider',
    );
    _ensureSuccess(response);
    return object(response.body);
  }

  Future<Json> billingStatus() => authenticated(
    'GET',
    '/api/esha/billing/status?provider=$provider&refresh=1',
    retryUnauthorized: true,
  );
  Future<Json> preparePurchase(String productId) => authenticated(
    'POST',
    '/api/esha/billing/prepare',
    body: {'provider': provider, 'productId': productId},
  );
  Future<Json> verifyPurchase(Json purchase) => authenticated(
    'POST',
    '/api/esha/billing/verify',
    body: {'provider': provider, ...purchase},
    timeout: const Duration(seconds: 60),
  );
  Future<Json> consult(Json request) => authenticated(
    'POST',
    '/api/esha/consult',
    body: request,
    timeout: const Duration(seconds: 120),
  );
  Future<Json> requestAccountDeletion(String reason) => authenticated(
    'POST',
    '/api/account/delete-request',
    body: {'reason': reason},
  );
  Future<Json> reportOutput(Json report) => authenticated(
    'POST',
    '/api/report-output',
    body: report,
    timeout: const Duration(seconds: 60),
  );

  Future<_Reply> _data(
    String method,
    String path,
    OwnerSnapshot snapshot, {
    Json? body,
  }) async {
    var token = await _authorizedToken(snapshot);
    Future<_Reply> send(String value) => _request(
      method,
      '${config.supabaseUrl}/rest/v1/$path',
      headers: {
        'Authorization': 'Bearer $value',
        'apikey': config.supabasePublishableKey,
        if (method != 'GET') 'Prefer': 'return=representation',
      },
      body: body,
    );
    var response = await send(token);
    verifyOwner(snapshot);
    if (response.status == 401) {
      await _refresh();
      token = await _authorizedToken(snapshot);
      response = await send(token);
      verifyOwner(snapshot);
    }
    return response;
  }

  @override
  Future<VanityRecord> loadVanity() async {
    final snapshot = owner();
    final response = await _data(
      'GET',
      'korlix_esha_vanity?user_id=eq.${Uri.encodeComponent(snapshot.userId)}&select=state,version&limit=1',
      snapshot,
    );
    _ensureSuccess(response);
    final list = response.body;
    if (list is! List || list.length > 1) {
      throw const EshaException(
        'LOAD_UNCONFIRMED',
        'Your account collection could not be read completely. Please retry.',
      );
    }
    if (list.isEmpty) return const VanityRecord(null, 0);
    return _record(list.single, 0, 'LOAD_UNCONFIRMED');
  }

  @override
  Future<VanityRecord> saveVanity(Vanity state, int expectedVersion) async {
    final snapshot = owner();
    final value = Vanity.fromJson(state.toJson()).toJson();
    if (expectedVersion < 0) {
      throw const EshaException(
        'INVALID_STATE',
        'Reload your account collection before saving.',
      );
    }
    final path = expectedVersion == 0
        ? 'korlix_esha_vanity'
        : 'korlix_esha_vanity?user_id=eq.${Uri.encodeComponent(snapshot.userId)}&version=eq.$expectedVersion';
    _Reply response;
    try {
      response = await _data(
        expectedVersion == 0 ? 'POST' : 'PATCH',
        path,
        snapshot,
        body: expectedVersion == 0
            ? {'user_id': snapshot.userId, 'state': value}
            : {'state': value},
      );
    } on EshaException catch (e) {
      if (e.code == 'NETWORK_ERROR') {
        throw const EshaException(
          'SYNC_UNCERTAIN',
          'The save could not be confirmed. Your local draft is retained. Retry to reconcile safely.',
        );
      }
      rethrow;
    }
    if (response.status == 409 ||
        (response.status >= 200 &&
            response.status < 300 &&
            response.body is List &&
            (response.body as List).isEmpty)) {
      throw const EshaException(
        'CONFLICT',
        'Your collection changed on another device. Your local draft has been retained.',
      );
    }
    _ensureSuccess(response);
    if (response.body is! List || (response.body as List).length != 1) {
      throw const EshaException(
        'SYNC_UNCERTAIN',
        'The service did not confirm this save. Your local draft is retained.',
      );
    }
    return _record(
      (response.body as List).single,
      expectedVersion,
      'SYNC_UNCERTAIN',
    );
  }

  VanityRecord _record(Object? value, int minimumVersion, String code) {
    final row = object(value);
    if (row['version'] is! int ||
        (row['version'] as int) <= minimumVersion ||
        (row['version'] as int) > 9007199254740991) {
      throw EshaException(
        code,
        'The collection version could not be confirmed.',
      );
    }
    return VanityRecord(
      Vanity.fromJson(object(row['state'])),
      row['version'] as int,
    );
  }

  Future<_Reply> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Json? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final request = http.Request(method, Uri.parse(url));
      request.headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...?headers,
      });
      if (body != null) request.body = jsonEncode(body);
      // Response.fromStream is inside the timeout, so a stalled response body
      // cannot hold an operation open after headers arrive.
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      return _Reply(response.statusCode, decoded);
    } on TimeoutException {
      throw const EshaException(
        'NETWORK_ERROR',
        'The connection timed out. Please check your connection.',
      );
    } on http.ClientException {
      throw const EshaException(
        'NETWORK_ERROR',
        'The connection was interrupted. Please try again.',
      );
    }
  }

  void _ensureSuccess(_Reply response, {bool signIn = false}) {
    if (response.status >= 200 && response.status < 300) return;
    final data = object(response.body);
    final code = data['code'] as String? ?? '';
    final detail = '${data['error']} $code'.toLowerCase();
    final accountMessage = switch (code) {
      'KORLIX_ACCOUNT_EXISTS' => 'You already have a Korlix account. Sign in with that email, or use Forgot password.',
      'SIGNUP_AGE_RESTRICTED' =>
        'You must be at least 16 to create a Korlix account.',
      'SIGNUP_AGE_REQUIRED' => 'Choose your age range to continue.',
      'SIGNUP_ELIGIBILITY_REQUIRED' || 'SIGNUP_POLICY_CHANGED' =>
        'Please update Esha to review the current signup policies.',
      'SIGNUP_POLICIES_REQUIRED' =>
        'Agree to the Terms of Use and acknowledge the Privacy Policy.',
      'SIGNUP_PARENT_PERMISSION_REQUIRED' =>
        'Users aged 16–17 need permission from a parent or guardian.',
      _ => null,
    };
    if (accountMessage != null) {
      throw EshaException(code, accountMessage, response.status);
    }
    if (signIn &&
        (detail.contains('invalid login credentials') ||
            detail.contains('invalid_credentials'))) {
      throw EshaException(
        'AUTH_REQUIRED',
        'Please check your Korlix email and password, or use Forgot password.',
        response.status,
      );
    }
    if (signIn &&
        (detail.contains('weak_password') ||
            detail.contains('password should be') ||
            detail.contains('password must be') ||
            detail.contains('pwned'))) {
      throw EshaException(
        'PASSWORD_REJECTED',
        'This password could not be accepted. Choose a longer password with letters, numbers and symbols.',
        response.status,
      );
    }
    if (detail.contains('device')) {
      throw EshaException(
        'DEVICE_LIMIT',
        'Korlix could not authorize this device. Review active devices in your Korlix account.',
        response.status,
      );
    }
    if (response.status == 401) {
      throw EshaException(
        'AUTH_REQUIRED',
        signIn
            ? 'Please check your Korlix email and password.'
            : 'Your session has ended. Please sign in again.',
        401,
      );
    }
    if (detail.contains('confirm') || detail.contains('email_not_verified')) {
      throw const EshaException(
        'EMAIL_VERIFICATION_REQUIRED',
        'Complete your Korlix email verification, then sign in.',
      );
    }
    if (response.status == 429) {
      throw EshaException(
        'RATE_LIMIT',
        'Please wait a moment before trying again.',
        429,
      );
    }
    final message = switch (response.status) {
      402 =>
        detail.contains('allowance') || detail.contains('quota')
            ? 'Your Esha consultation allowance has been used. Check your membership for its renewal date.'
            : 'An active Esha membership is required for live consultations.',
      403 => 'Your Korlix account could not authorize this request.',
      409 =>
        detail.contains('owner') || detail.contains('account')
            ? 'This store purchase belongs to a different Korlix account. Sign in to that account to restore it.'
            : 'This request is pending or your membership is already active. Refresh its status before trying again.',
      503 => 'This Esha service is still being configured or is temporarily unavailable. Please try again later.',
      _ => 'The service could not complete this request. Please try again.',
    };
    throw EshaException(
      code.isEmpty ? 'SERVICE_UNAVAILABLE' : code,
      message,
      response.status,
    );
  }

  void dispose() {
    _client.close();
  }
}

class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final Object? body;
}
