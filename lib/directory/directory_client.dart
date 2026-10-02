import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef DirJson = Map<String, dynamic>;
DirJson dirClone(DirJson value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
List<DirJson> dirRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
DirJson dirMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String dirId() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class DirectoryException implements Exception {
  const DirectoryException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class DirectoryClient {
  DirectoryClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.sessionChanges,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null {
    _scope = _readScope();
    sessionChanges?.addListener(_checkSession);
  }
  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final http.Client _http;
  final bool _ownsClient;
  void Function()? onSignedOut;
  final Listenable? sessionChanges;
  String? _scope;
  bool _closed = false, _changed = false;
  final Set<VoidCallback> _accessListeners = {};
  bool get sessionChanged => _closed || _changed;
  void addAccessDeniedListener(VoidCallback listener) =>
      _accessListeners.add(listener);
  void removeAccessDeniedListener(VoidCallback listener) =>
      _accessListeners.remove(listener);
  void _deny() {
    onSignedOut?.call();
    for (final listener in List<VoidCallback>.from(_accessListeners)) {
      listener();
    }
  }

  String? _readScope([Map<String, String>? headers]) {
    try {
      final value = (headers ?? headersBuilder()).entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value;
      final payload = value.split(' ').last.split('.')[1];
      final c = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
      final scope = [c['iss'], c['sub'], c['session_id']];
      if (scope.any((v) => v is! String || v.isEmpty)) return null;
      return jsonEncode(scope);
    } catch (_) {
      return null;
    }
  }

  void _checkSession() {
    if (!_closed &&
        !_changed &&
        sessionChanges != null &&
        (_scope == null || _scope != _readScope())) {
      _changed = true;
      _deny();
    }
  }

  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const DirectoryException('Reopen Directory to continue.');
    }
    _checkSession();
    if (!_changed &&
        sessionChanges != null &&
        headers != null &&
        _scope != _readScope(headers)) {
      _changed = true;
      _deny();
    }
    if (_changed) {
      throw const DirectoryException(
        'Sign in again and reopen Directory.',
        401,
      );
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    _accessListeners.clear();
    if (_ownsClient) _http.close();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    DirJson? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/directory$path',
    ).replace(queryParameters: query);
    try {
      final req = http.Request(method, uri)
        ..headers.addAll({
          ...headersBuilder(),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        });
      _guard(req.headers);
      if (body != null) req.body = jsonEncode(body);
      final res = await (() async => http.Response.fromStream(
        await _http.send(req),
      ))().timeout(const Duration(seconds: 40));
      _guard();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 401) {
          _changed = true;
          _deny();
        }
        String message =
            'Directory could not complete this request. Please try again.';
        try {
          message =
              (jsonDecode(res.body) as Map)['error']?.toString() ?? message;
        } catch (_) {}
        throw DirectoryException(message, res.statusCode);
      }
      return res;
    } on TimeoutException {
      _guard();
      throw const DirectoryException(
        'Connection timed out. Refresh to check whether your action was saved before trying again.',
      );
    } on http.ClientException {
      _guard();
      throw const DirectoryException(
        'Check your connection, then refresh your business listing.',
      );
    }
  }

  Future<DirJson> request(
    String method,
    String path, {
    DirJson? body,
    Map<String, String>? query,
  }) async {
    final res = await _send(method, path, body: body, query: query);
    try {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      throw const DirectoryException(
        'Directory returned an unreadable response. Refresh and try again.',
      );
    }
  }

  Future<Uint8List> bytes(String path, {Map<String, String>? query}) async =>
      (await _send('GET', path, query: query)).bodyBytes;
}
