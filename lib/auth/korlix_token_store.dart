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
  static const _key = 'korlix_auth_tokens_v1';
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
  }) : _useSecureStorage = useSecureStorage ?? !kIsWeb,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _secureStorage = secureStorage ?? _NativeTokenBackend();

  static final instance = KorlixTokenStore();
  static const accessTokenKey = 'korlix_access_token';
  static const refreshTokenKey = 'korlix_refresh_token';
  static const _signedOutKey = 'korlix_tokens_signed_out_v1';

  final bool _useSecureStorage;
  final Future<SharedPreferences> Function() _preferences;
  final KorlixSecureTokenBackend _secureStorage;
  Future<void> _pending = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed operation must not poison later sign-in or sign-out attempts.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<KorlixStoredTokens?> read() => _serial(() async {
    final prefs = await _preferences();
    // Persisted before secure deletion: a device-storage failure during logout
    // must not resurrect the session the next time the application opens.
    if (prefs.getBool(_signedOutKey) == true) return null;

    if (_useSecureStorage) {
      // Keychain entries can survive an iOS uninstall. A fresh installation
      // without our local marker or a legacy session must start signed out.
      if (!prefs.containsKey(_signedOutKey) &&
          _nonEmpty(prefs.getString(accessTokenKey)) == null) {
        return null;
      }
      final String? value;
      try {
        value = await _secureStorage.read();
      } catch (_) {
        // Never fall back to plaintext when the keychain/keystore is locked.
        throw const KorlixTokenStorageException();
      }
      if (value != null) {
        final tokens = _decode(value);
        _require(await prefs.setBool(_signedOutKey, false));
        await _removeLegacy(prefs);
        return tokens;
      }
    }

    final accessToken = prefs.getString(accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) return null;
    final refreshToken = prefs.getString(refreshTokenKey);
    final tokens = KorlixStoredTokens(
      accessToken: accessToken,
      refreshToken: _nonEmpty(refreshToken),
    );
    if (_useSecureStorage) {
      // Verify the new secure entry before removing either legacy credential.
      await _saveSecure(tokens);
      _require(await prefs.setBool(_signedOutKey, false));
      await _removeLegacy(prefs);
    }
    return tokens;
  });

  Future<void> write({required String accessToken, String? refreshToken}) =>
      _serial(() async {
        if (accessToken.isEmpty) throw const KorlixTokenStorageException();
        final prefs = await _preferences();
        final tokens = KorlixStoredTokens(
          accessToken: accessToken,
          refreshToken: _nonEmpty(refreshToken),
        );
        if (_useSecureStorage) {
          await _saveSecure(tokens);
          _require(await prefs.setBool(_signedOutKey, false));
          await _removeLegacy(prefs);
        } else {
          _require(await prefs.setString(accessTokenKey, accessToken));
          if (tokens.refreshToken == null) {
            _require(await prefs.remove(refreshTokenKey));
          } else {
            _require(
              await prefs.setString(refreshTokenKey, tokens.refreshToken!),
            );
          }
        }
        if (!_useSecureStorage) {
          _require(await prefs.setBool(_signedOutKey, false));
        }
      });

  Future<void> clear() => _serial(() async {
    final prefs = await _preferences();
    _require(await prefs.setBool(_signedOutKey, true));
    await _removeLegacy(prefs);
    if (_useSecureStorage) {
      try {
        await _secureStorage.delete();
      } catch (_) {
        throw const KorlixTokenStorageException();
      }
    }
  });

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
    _require(await prefs.remove(accessTokenKey));
    _require(await prefs.remove(refreshTokenKey));
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
