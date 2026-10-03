import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local login conveniences, separate from the authenticated session.
///
/// Passwords belong to the user's OS/browser password manager. This record has
/// no password field and must never be used to hold authentication credentials.
class KorlixLoginPreferences {
  const KorlixLoginPreferences({
    this.rememberEmail = false,
    this.email = '',
    this.offerPasswordSave = true,
  });

  final bool rememberEmail;
  final String email;
  final bool offerPasswordSave;

  static const storageKey = 'korlix_login_preferences_v1';
  // Keep a future only while work is pending. Completed futures can retain the
  // event zone of a login screen/test that has already been disposed.
  static Future<void>? _writes;

  static Future<KorlixLoginPreferences> load({
    Future<SharedPreferences> Function()? loadPreferences,
  }) async {
    // A newly opened login screen must not restore an older queued choice.
    final pendingWrites = _writes;
    if (pendingWrites != null) await pendingWrites;
    try {
      final preferences =
          await (loadPreferences ?? SharedPreferences.getInstance)();
      final raw = preferences.getString(storageKey);
      if (raw == null) return const KorlixLoginPreferences();
      final data = jsonDecode(raw);
      if (data is! Map) return const KorlixLoginPreferences();
      final rememberEmail = data['rememberEmail'] == true;
      return KorlixLoginPreferences(
        rememberEmail: rememberEmail,
        email: rememberEmail && data['email'] is String
            ? (data['email'] as String).trim()
            : '',
        offerPasswordSave: data['offerPasswordSave'] is bool
            ? data['offerPasswordSave'] as bool
            : true,
      );
    } catch (_) {
      // Login remains available when device/browser storage is unavailable.
      return const KorlixLoginPreferences();
    }
  }

  /// Saves only the allowlisted convenience fields, in the order requested.
  ///
  /// Rapid checkbox changes cannot allow a slower old write to restore an
  /// email after the user has opted out. The single record also prevents a
  /// partially saved preference from retaining an opted-out email.
  Future<bool> save({Future<SharedPreferences> Function()? loadPreferences}) {
    final record = jsonEncode(<String, Object>{
      'rememberEmail': rememberEmail,
      if (rememberEmail && email.trim().isNotEmpty) 'email': email.trim(),
      'offerPasswordSave': offerPasswordSave,
    });
    final previousWrites = _writes;
    Future<bool> persist() async {
      try {
        if (previousWrites != null) await previousWrites;
        final preferences =
            await (loadPreferences ?? SharedPreferences.getInstance)();
        return await preferences.setString(storageKey, record);
      } catch (_) {
        return false;
      }
    }

    final result = persist();
    late final Future<void> tail;
    tail = result.then<void>((_) {
      // An earlier write must not clear a newer write from the queue.
      if (identical(_writes, tail)) _writes = null;
    });
    _writes = tail;
    return result;
  }
}
