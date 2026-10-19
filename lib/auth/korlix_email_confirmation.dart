import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const korlixConfirmationScheme = 'com.korlixdeveloper.korlixai';

bool get korlixSupportsEmailAppLink =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class KorlixConfirmationException implements Exception {
  const KorlixConfirmationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class KorlixConfirmedSession {
  const KorlixConfirmedSession({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
  });
  final String accessToken, refreshToken, email;
}

/// Only a callback for a signup started on this installation can sign it in.
/// Never persist or log the incoming URL: its fragment contains credentials.
class KorlixEmailConfirmation {
  static const pendingKey = 'korlix_pending_email_confirmation_v1';
  bool _busy = false;

  static Future<String> begin(String email) async {
    final random = Random.secure();
    final state = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      pendingKey,
      jsonEncode({
        'state': state,
        'email': email.trim().toLowerCase(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (!saved) {
      throw const KorlixConfirmationException(
        'We could not prepare email confirmation. Please try again.',
      );
    }
    return state;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingKey);
  }

  static bool matches(Uri uri) =>
      uri.scheme == korlixConfirmationScheme &&
      uri.host == 'auth' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'confirm' &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(uri.pathSegments.last) &&
      !uri.hasQuery;

  Future<void> complete(
    Uri uri, {
    required Future<KorlixConfirmedSession?> Function(String) exchange,
    required Future<void> Function(KorlixConfirmedSession) accept,
    required bool Function() canAccept,
  }) async {
    if (!matches(uri) || _busy || !canAccept()) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingKey);
      if (raw == null) return; // Duplicate or another installation's link.
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      if (pending['state'] != uri.pathSegments.last) return;
      final created = DateTime.tryParse('${pending['created_at']}');
      if (created == null ||
          DateTime.now().toUtc().difference(created) >
              const Duration(days: 1)) {
        throw const KorlixConfirmationException(
          'Your email link is no longer current. Please sign in or request a new confirmation.',
        );
      }
      final values = Uri.splitQueryString(uri.fragment);
      if (values.containsKey('error') || values.containsKey('error_code')) {
        throw const KorlixConfirmationException(
          'This confirmation link has expired or was already used. Please try signing in.',
        );
      }
      // A password-recovery link must never become a normal signup session.
      if (values['type'] != 'signup') return;
      final refreshToken = values['refresh_token'] ?? '';
      if (refreshToken.isEmpty ||
          refreshToken.length > 4096 ||
          (values['access_token'] ?? '').isEmpty) {
        throw const KorlixConfirmationException(
          'We could not finish confirmation. Please try signing in.',
        );
      }
      if (!canAccept()) return;
      // The server validates the token and applies normal device/account rules.
      final session = await exchange(refreshToken);
      if (!canAccept()) return;
      if (session == null ||
          session.accessToken.isEmpty ||
          session.refreshToken.isEmpty ||
          session.email.trim().toLowerCase() != pending['email']) {
        throw const KorlixConfirmationException(
          'Your email is confirmed. Please sign in to finish opening KORLIX.',
        );
      }
      await accept(session);
      // Do not clear a newer signup that started while this request was running.
      if (prefs.getString(pendingKey) == raw) await prefs.remove(pendingKey);
    } on KorlixConfirmationException {
      rethrow;
    } catch (_) {
      // Provider errors and URLs can contain tokens; show only a fixed message.
      throw const KorlixConfirmationException(
        'We could not finish opening KORLIX. Check your connection and try signing in.',
      );
    } finally {
      _busy = false;
    }
  }
}
