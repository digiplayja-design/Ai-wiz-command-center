import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class KorlixAuthSession {
  const KorlixAuthSession({
    required this.accessToken,
    this.refreshToken,
    this.email,
  });
  final String accessToken;
  final String? refreshToken;
  final String? email;
}

Map<String, dynamic> _claims(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) {
      return {};
    }
    final value = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return value is Map<String, dynamic> ? value : {};
  } catch (_) {
    return {};
  }
}

/// Local equality/refresh scheduling only; the backend verifies authorization.
String korlixSessionIdentity(String token) {
  final claims = _claims(token);
  final values = [claims['iss'], claims['sub'], claims['session_id']];
  return values.every((value) => value is String && value.isNotEmpty)
      ? jsonEncode(values)
      : token;
}

DateTime? korlixAccessTokenExpiry(String token) {
  final expiry = _claims(token)['exp'];
  if (expiry is! num || !expiry.isFinite || expiry <= 0 || expiry > 8640000000000) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch((expiry * 1000).round(), isUtc: true);
}

class KorlixSessionRefreshUnavailable implements Exception {
  const KorlixSessionRefreshUnavailable();
  @override
  String toString() => 'We could not renew your connection. Please try again shortly.';
}

class KorlixSessionChanged implements Exception {
  const KorlixSessionChanged();
  @override
  String toString() => 'Your account changed. Please try again.';
}

/// Unknown errors are recoverable. Only explicit refresh/session revocation
/// evidence may remove credentials; rate limits and outages never do.
bool korlixRefreshWasRejected(int status, Map<String, dynamic> data) {
  if (![400, 401, 403, 422].contains(status)) {
    return false;
  }
  const terminal = {
    'refresh_token_not_found', 'refresh_token_already_used', 'session_expired',
    'session_not_found', 'user_banned', 'user_not_found', 'invalid_grant',
  };
  if (terminal.contains(data['code']) || terminal.contains(data['error_code'])) {
    return true;
  }
  final message = '${data['error'] ?? ''}';
  return RegExp(
    r'^revoked$|invalid\s+refresh\s*token|refresh\s*token.*(?:not found|already used|expired|invalid)|'
    r'session.*(?:revoked|expired|not found)|account is disabled|'
    r'device (?:is not|is no longer) authorized',
    caseSensitive: false,
  ).hasMatch(message);
}

typedef KorlixRefresh = Future<KorlixAuthSession?> Function(KorlixAuthSession session);

/// One coordinator owns refresh-token rotation in the main Flutter engine.
/// A null refresh response means confirmed revocation; exceptions are retryable.
class KorlixSessionRefreshCoordinator {
  KorlixSessionRefreshCoordinator({
    required this.current,
    required this.revision,
    required this.refresh,
    required this.persist,
    required this.publish,
    required this.clear,
    DateTime Function()? now,
    this.refreshAhead = const Duration(minutes: 2),
    this.retryDelay = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 8),
  }) : now = now ?? DateTime.now;

  final KorlixAuthSession? Function() current;
  final int Function() revision;
  final KorlixRefresh refresh;
  final Future<void> Function(KorlixAuthSession session, bool Function() stillCurrent) persist;
  final void Function(KorlixAuthSession session) publish;
  final Future<void> Function() clear;
  final DateTime Function() now;
  final Duration refreshAhead, retryDelay, timeout;
  Future<KorlixAuthSession?>? _pending;
  int? _pendingRevision, _retryRevision;
  DateTime? _retryAfter;

  bool isExpired(KorlixAuthSession session) {
    final expiry = korlixAccessTokenExpiry(session.accessToken);
    return expiry != null && !expiry.isAfter(now());
  }

  Duration? nextRefreshDelay() {
    final session = current();
    if (session == null || session.refreshToken?.isNotEmpty != true) {
      return null;
    }
    final expiry = korlixAccessTokenExpiry(session.accessToken);
    if (expiry == null) {
      return null;
    }
    final retry = _retryRevision == revision() ? _retryAfter : null;
    if (retry != null && retry.isAfter(now())) {
      return retry.difference(now());
    }
    final delay = expiry.subtract(refreshAhead).difference(now());
    return delay > const Duration(seconds: 1) ? delay : const Duration(seconds: 1);
  }

  Future<KorlixAuthSession?> ensureFresh({
    bool force = false,
    String? rejectedAccessToken,
    KorlixRefresh? refreshOverride,
  }) {
    final session = current();
    if (session == null) {
      return Future.value();
    }
    final epoch = revision();
    if (_pending != null && _pendingRevision == epoch) {
      return _waitForRefresh(_pending!, epoch);
    }
    // A delayed 401 for an already-rotated bearer is not a second revocation.
    if (rejectedAccessToken != null && rejectedAccessToken != session.accessToken) {
      force = false;
    }
    final expiry = korlixAccessTokenExpiry(session.accessToken);
    if (!force && (expiry == null || expiry.isAfter(now().add(refreshAhead)))) {
      return Future.value(session);
    }
    if (_retryRevision == epoch && _retryAfter?.isAfter(now()) == true) {
      return Future.error(const KorlixSessionRefreshUnavailable());
    }
    if (session.refreshToken?.isNotEmpty != true) {
      return isExpired(session)
          ? Future.error(const KorlixSessionRefreshUnavailable())
          : Future.value(session);
    }
    _pendingRevision = epoch;
    late final Future<KorlixAuthSession?> operation;
    operation = _run(session, epoch, refreshOverride ?? refresh).whenComplete(() {
      if (identical(_pending, operation)) {
        _pending = null;
        _pendingRevision = null;
      }
    });
    _pending = operation;
    return _waitForRefresh(operation, epoch);
  }

  Future<KorlixAuthSession?> _waitForRefresh(
    Future<KorlixAuthSession?> operation,
    int epoch,
  ) => operation.timeout(timeout, onTimeout: () {
    if (revision() != epoch) {
      throw const KorlixSessionChanged();
    }
    // Bound a UI/request wait without abandoning a provider response that may
    // already have rotated its refresh token. All later callers still join
    // the same underlying operation until its transport completes or fails.
    _retryRevision = epoch;
    _retryAfter = now().add(retryDelay);
    throw const KorlixSessionRefreshUnavailable();
  });

  Future<KorlixAuthSession?> _run(KorlixAuthSession session, int epoch, KorlixRefresh renew) async {
    bool stillCurrent() => revision() == epoch && current() != null &&
        current()!.accessToken == session.accessToken;
    try {
      final updated = await renew(session);
      if (!stillCurrent()) {
        throw const KorlixSessionChanged();
      }
      if (updated == null) {
        await clear();
        return null;
      }
      // Real JWTs must keep the same account/login. Opaque fixtures/legacy
      // credentials have no identity claims and remain server-authorized.
      if (_claims(session.accessToken).isNotEmpty &&
          korlixSessionIdentity(updated.accessToken) != korlixSessionIdentity(session.accessToken)) {
        throw const KorlixSessionRefreshUnavailable();
      }
      if (isExpired(updated)) {
        throw const KorlixSessionRefreshUnavailable();
      }
      await persist(updated, stillCurrent);
      if (!stillCurrent()) {
        throw const KorlixSessionChanged();
      }
      publish(updated);
      _retryAfter = null;
      _retryRevision = null;
      return updated;
    } on KorlixSessionChanged {
      rethrow;
    } catch (_) {
      if (!stillCurrent()) {
        throw const KorlixSessionChanged();
      }
      _retryRevision = epoch;
      _retryAfter = now().add(retryDelay);
      throw const KorlixSessionRefreshUnavailable();
    }
  }
}

/// Applies to KORLIX bearer requests only. Refresh endpoints and other origins
/// bypass this layer. Writes are never replayed automatically after a 401.
class KorlixSessionHttpClient extends http.BaseClient {
  KorlixSessionHttpClient({required this.inner, required this.sessions, required String baseUrl})
      : origin = Uri.parse(baseUrl).origin;
  final http.Client inner;
  final KorlixSessionRefreshCoordinator sessions;
  final String origin;

  String? _bearer(http.BaseRequest request) {
    final value = request.headers.entries.where((e) => e.key.toLowerCase() == 'authorization')
        .map((e) => e.value).firstOrNull;
    return value?.startsWith('Bearer ') == true ? value!.substring(7) : null;
  }

  http.StreamedResponse _unavailable(http.BaseRequest request, [String? message]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({
        'error': message ?? const KorlixSessionRefreshUnavailable().toString(),
        'code': 'session_refresh_retry',
      }))), 503, headers: {'content-type': 'application/json'}, request: request);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final provided = _bearer(request);
    if (request.url.origin != origin || provided == null ||
        request.url.path.startsWith('/api/auth/')) {
      return inner.send(request);
    }
    final before = sessions.current();
    final epoch = sessions.revision();
    bool current() => sessions.revision() == epoch && sessions.current() != null;
    if (before == null || korlixSessionIdentity(provided) != korlixSessionIdentity(before.accessToken)) {
      return _unavailable(request, const KorlixSessionChanged().toString());
    }
    KorlixAuthSession? fresh;
    try {
      fresh = await sessions.ensureFresh();
    } on KorlixSessionRefreshUnavailable {
      // A temporarily unavailable early refresh need not block a still-valid
      // access token. An expired bearer must wait for a successful renewal.
      fresh = sessions.current();
      if (fresh == null || sessions.isExpired(fresh)) {
        return _unavailable(request);
      }
    } on KorlixSessionChanged {
      return _unavailable(request, const KorlixSessionChanged().toString());
    }
    if (!current() || fresh == null) {
      return _unavailable(request, 'Please sign in again.');
    }
    for (final key in request.headers.keys.toList(growable: false)) {
      if (key.toLowerCase() == 'authorization') {
        request.headers.remove(key);
      }
    }
    request.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
    final dispatchedToken = fresh.accessToken;
    // Preserve a replayable copy only for safe read methods.
    final retry = request is http.Request && ['GET', 'HEAD', 'OPTIONS'].contains(request.method)
        ? (http.Request(request.method, request.url)..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection)
        : null;
    final response = await inner.send(request);
    if (![401, 419, 440].contains(response.statusCode)) {
      return response;
    }
    final bytes = await response.stream.toBytes();
    // Domain-specific authorization (for example a wrong Vault password) is
    // not a login-token expiry. Preserve its actionable error unchanged.
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is Map) {
        final code = data['code'] ?? data['error_code'];
        const loginCodes = {'session_expired', 'session_not_found', 'jwt_expired',
          'invalid_jwt', 'token_expired', 'not_authenticated', 'authentication_required',
          'auth_required', 'brain_vault_auth_required'};
        if ((code is String && !loginCodes.contains(code)) ||
            RegExp(r'password|passcode|\bpin\b', caseSensitive: false).hasMatch('${data['error'] ?? ''}')) {
          return http.StreamedResponse(Stream.value(bytes), response.statusCode,
            headers: response.headers, request: response.request,
            contentLength: response.contentLength,
            reasonPhrase: response.reasonPhrase,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection);
        }
      }
    } catch (_) {
      // Legacy authentication errors may not have a JSON body.
    }
    if (!current()) {
      return _unavailable(request, const KorlixSessionChanged().toString());
    }
    try {
      fresh = await sessions.ensureFresh(force: true, rejectedAccessToken: dispatchedToken);
    } catch (_) {
      return _unavailable(request);
    }
    if (!current() || fresh == null) {
      return _unavailable(request, 'Please sign in again.');
    }
    if (retry == null) {
      return _unavailable(request, 'Your connection was renewed. Please retry this action.');
    }
    retry.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
    return inner.send(retry);
  }

  @override
  void close() {
    inner.close();
    super.close();
  }
}
