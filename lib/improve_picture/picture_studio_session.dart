import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Owns private photo state for one login session, including token refreshes.
/// This local lifetime check does not replace server authentication.
class PictureStudioSession extends ChangeNotifier {
  PictureStudioSession({
    required this.headersBuilder,
    required this.sessionChanges,
  }) {
    _scope = _readScope();
    _invalidated = _scope == null;
    if (!_invalidated) sessionChanges.addListener(_onSessionChanged);
  }

  final Map<String, String> Function() headersBuilder;
  final Listenable sessionChanges;
  late final String? _scope;
  bool _invalidated = false;
  bool _disposed = false;

  bool get isCurrent {
    // Also check at asynchronous boundaries when no auth event was delivered.
    _checkSession(deferNotification: true);
    return !_disposed && !_invalidated;
  }

  String? _readScope() {
    try {
      final values = headersBuilder().entries.where(
        (entry) => entry.key.toLowerCase() == 'authorization',
      );
      if (values.length != 1) return null;
      final bearer = RegExp(
        r'^Bearer\s+(\S+)$',
        caseSensitive: false,
      ).firstMatch(values.single.value.trim());
      final parts = bearer?.group(1)?.split('.');
      if (parts == null || parts.length != 3 || parts.any((p) => p.isEmpty)) {
        return null;
      }
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map) return null;
      final identity = [claims['iss'], claims['sub'], claims['session_id']];
      if (identity.any((value) => value is! String || value.trim().isEmpty)) {
        return null;
      }
      return jsonEncode(identity);
    } catch (_) {
      return null;
    }
  }

  void _onSessionChanged() => _checkSession();

  void _checkSession({bool deferNotification = false}) {
    if (_disposed || _invalidated || _scope == _readScope()) return;
    _invalidated = true;
    sessionChanges.removeListener(_onSessionChanged);
    if (deferNotification) {
      // A getter can be evaluated while a route is building. Publish its
      // invalidation after that build rather than notifying during build.
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }
}
