import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KorlixStoredTokens {
  const KorlixStoredTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}

/// Only this adapter touches the native keychain/keystore. The interface allows
/// migration and failure behavior to be tested without real account credentials.
abstract interface class KorlixSecureTokenBackend {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class _NativeTokenBackend implements KorlixSecureTokenBackend {
  _NativeTokenBackend([this._key = 'korlix_auth_tokens_v1']);
  final String _key;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class KorlixTokenStorageException implements Exception {
  const KorlixTokenStorageException();

  @override
  String toString() =>
      'Your session could not be saved securely. Unlock your device and try again.';
}

/// Native credentials use one atomic secure-storage entry, so an access token
/// cannot be paired with a previous account's refresh token. Web keeps its
/// existing storage contract; browser storage is not a native secure store.
class KorlixTokenStore {
  KorlixTokenStore({
    bool? useSecureStorage,
    Future<SharedPreferences> Function()? preferences,
    KorlixSecureTokenBackend? secureStorage,
    String namespace = '',
  }) : _useSecureStorage = useSecureStorage ?? !kIsWeb,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _namespace = namespace,
       _secureStorage =
           secureStorage ??
           _NativeTokenBackend(
             namespace.isEmpty
                 ? 'korlix_auth_tokens_v1'
                 : '${namespace}_auth_tokens_v1',
           );

  static final instance = KorlixTokenStore();
  static const accessTokenKey = 'korlix_access_token';
  static const refreshTokenKey = 'korlix_refresh_token';
  static const _signedOutKey = 'korlix_tokens_signed_out_v1';

  final String _namespace;
  String get _accessKey =>
      _namespace.isEmpty ? accessTokenKey : '${_namespace}_access_token';
  String get _refreshKey =>
      _namespace.isEmpty ? refreshTokenKey : '${_namespace}_refresh_token';
  String get _logoutKey =>
      _namespace.isEmpty ? _signedOutKey : '${_namespace}_tokens_signed_out_v1';

  final bool _useSecureStorage;
  final Future<SharedPreferences> Function() _preferences;
  final KorlixSecureTokenBackend _secureStorage;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed operation must not poison later sign-in or sign-out attempts.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<KorlixStoredTokens?> read() {
    final generation = _generation;
    return _serial(() async {
      final prefs = await _preferences();
      if (generation != _generation) return null;
      // Persisted before secure deletion: a device-storage failure during logout
      // must not resurrect the session the next time the application opens.
      if (prefs.getBool(_logoutKey) == true) return null;

      if (_useSecureStorage) {
        // Keychain entries can survive an iOS uninstall. A fresh installation
        // without our local marker or a legacy session must start signed out.
        if (!prefs.containsKey(_logoutKey) &&
            _nonEmpty(prefs.getString(_accessKey)) == null) {
          return null;
        }
        final String? value;
        try {
          value = await _secureStorage.read();
        } catch (_) {
          // Never fall back to plaintext when the keychain/keystore is locked.
          throw const KorlixTokenStorageException();
        }
        if (generation != _generation) return null;
        if (value != null) {
          final tokens = _decode(value);
          _require(await prefs.setBool(_logoutKey, false));
          await _removeLegacy(prefs);
          return generation == _generation ? tokens : null;
        }
      }

      final accessToken = prefs.getString(_accessKey);
      if (accessToken == null || accessToken.isEmpty) return null;
      final refreshToken = prefs.getString(_refreshKey);
      final tokens = KorlixStoredTokens(
        accessToken: accessToken,
        refreshToken: _nonEmpty(refreshToken),
      );
      if (_useSecureStorage) {
        // Verify the new secure entry before removing either legacy credential.
        await _saveSecure(tokens);
        if (generation != _generation) return null;
        _require(await prefs.setBool(_logoutKey, false));
        await _removeLegacy(prefs);
      }
      return generation == _generation ? tokens : null;
    });
  }

  /// A secondary engine must not migrate credentials or rewrite the logout
  /// marker. Reload it on both sides of the secure read so a concurrent logout
  /// cannot be undone by a floating chat opening in another Flutter engine.
  Future<KorlixStoredTokens?> readOnly() => _serial(() async {
    final prefs = await _preferences();
    await prefs.reload();
    if (prefs.getBool(_logoutKey) != false) return null;
    if (!_useSecureStorage) {
      final access = _nonEmpty(prefs.getString(_accessKey));
      return access == null
          ? null
          : KorlixStoredTokens(
              accessToken: access,
              refreshToken: _nonEmpty(prefs.getString(_refreshKey)),
            );
    }
    final String? value;
    try {
      value = await _secureStorage.read();
    } catch (_) {
      throw const KorlixTokenStorageException();
    }
    await prefs.reload();
    if (prefs.getBool(_logoutKey) != false || value == null) return null;
    return _decode(value);
  });

  Future<void> write({
    required String accessToken,
    String? refreshToken,
    bool Function()? isCurrent,
  }) {
    final generation = _generation;
    bool current() => generation == _generation && isCurrent?.call() != false;
    return _serial(() async {
      if (!current()) return;
      if (accessToken.isEmpty) throw const KorlixTokenStorageException();
      final prefs = await _preferences();
      if (!current()) return;
      final tokens = KorlixStoredTokens(
        accessToken: accessToken,
        refreshToken: _nonEmpty(refreshToken),
      );
      if (_useSecureStorage) {
        await _saveSecure(tokens);
        if (!current()) return;
        _require(await prefs.setBool(_logoutKey, false));
        await _removeLegacy(prefs);
      } else {
        _require(await prefs.setString(_accessKey, accessToken));
        if (!current()) return;
        if (tokens.refreshToken == null) {
          _require(await prefs.remove(_refreshKey));
        } else {
          _require(await prefs.setString(_refreshKey, tokens.refreshToken!));
        }
        if (!current()) return;
        _require(await prefs.setBool(_logoutKey, false));
      }
    });
  }

  /// This small durable marker must not wait behind a stalled keychain write.
  /// A read/migration or write started before logout cannot reset it afterward.
  Future<void> markSignedOut() async {
    _generation++;
    final prefs = await _preferences();
    _require(await prefs.setBool(_logoutKey, true));
  }

  Future<void> clear() {
    // Capture an early preference failure while deletion waits for storage.
    final marked = markSignedOut().then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    return _serial(() async {
      final markerError = await marked;
      if (markerError != null) throw markerError;
      final prefs = await _preferences();
      await _removeLegacy(prefs);
      if (_useSecureStorage) {
        try {
          await _secureStorage.delete();
        } catch (_) {
          throw const KorlixTokenStorageException();
        }
      }
    });
  }

  Future<void> _saveSecure(KorlixStoredTokens tokens) async {
    final encoded = jsonEncode({
      'access_token': tokens.accessToken,
      'refresh_token': tokens.refreshToken,
    });
    try {
      await _secureStorage.write(encoded);
      if (await _secureStorage.read() != encoded) {
        throw const KorlixTokenStorageException();
      }
    } catch (_) {
      throw const KorlixTokenStorageException();
    }
  }

  Future<void> _removeLegacy(SharedPreferences prefs) async {
    _require(await prefs.remove(_accessKey));
    _require(await prefs.remove(_refreshKey));
  }

  static KorlixStoredTokens _decode(String value) {
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic> ||
          data['access_token'] is! String ||
          (data['access_token'] as String).isEmpty ||
          (data['refresh_token'] != null && data['refresh_token'] is! String)) {
        throw const KorlixTokenStorageException();
      }
      return KorlixStoredTokens(
        accessToken: data['access_token'] as String,
        refreshToken: _nonEmpty(data['refresh_token'] as String?),
      );
    } catch (_) {
      // FormatException can include its input; never expose token JSON in logs.
      throw const KorlixTokenStorageException();
    }
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  static void _require(bool success) {
    if (!success) throw const KorlixTokenStorageException();
  }
}
