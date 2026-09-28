import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String defenderRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class DefenderException implements Exception {
  const DefenderException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class DefenderClient {
  DefenderClient({
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
  final Listenable? sessionChanges;
  String? _scope;
  bool _closed = false, _changed = false;
  VoidCallback? onAccessDenied;
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
      onAccessDenied?.call();
    }
  }

  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const DefenderException(
        'Reopen Cybersecurity Defender to continue.',
      );
    }
    _checkSession();
    if (!_changed &&
        sessionChanges != null &&
        headers != null &&
        _scope != _readScope(headers)) {
      _changed = true;
      onAccessDenied?.call();
    }
    if (_changed) {
      throw const DefenderException(
        'Sign in again and reopen Cybersecurity Defender.',
        401,
      );
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    if (_ownsClient) _http.close();
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/cyber-defender$path',
  );
  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      _guard(request.headers);
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 70));
      _guard();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          _changed = true;
          onAccessDenied?.call();
        }
        String? error;
        try {
          error = (jsonDecode(response.body) as Map)['error']?.toString();
        } catch (_) {}
        throw DefenderException(
          error ??
              'Cybersecurity Defender could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const DefenderException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const DefenderException(
        'Check your connection, then refresh your Cybersecurity Defender.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const DefenderException(
        'The Cybersecurity Defender returned an unreadable response. Refresh and try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final r = http.Request(method, _uri(path))
      ..headers.addAll({
        ...headersBuilder(),
        'Content-Type': 'application/json',
      });
    if (body != null) r.body = jsonEncode(body);
    return _json(await _send(r));
  }

  Map<String, dynamic> _report(dynamic value, String expected) {
    final s = defenderMap(value),
        result = defenderMap(defenderMap(value)['result']);
    if (s['id'] != expected ||
        !['preparing', 'ready', 'failed'].contains(s['state']) ||
        s['revision'] is! int ||
        s['details'] is! Map ||
        s['progress'] is! Map ||
        s['review'] is! Map ||
        result['title'] is! String ||
        result['summary'] is! String ||
        ![
          'high',
          'review',
          'unknown',
          'incident',
        ].contains(result['concern']) ||
        result['findings'] is! List ||
        result['domains'] is! List ||
        result['actions'] is! List ||
        defenderItems(result['actions']).isEmpty) {
      throw const DefenderException(
        'This report was not confirmed. Refresh Saved reports.',
      );
    }
    return s;
  }

  Future<Map<String, dynamic>> list() async {
    final r = await _request('GET', '');
    if (r['reports'] is! List ||
        r['habits'] is! List ||
        r['incidents'] is! List ||
        r['sources'] is! List ||
        r['profile'] is! Map ||
        defenderMap(r['profile'])['revision'] is! int) {
      throw const DefenderException(
        'Your Defender workspace could not be loaded.',
      );
    }
    return r;
  }

  Future<Map<String, dynamic>> checklist(Map<String, dynamic> body) async {
    final r = await _request('PUT', '/checklist', body);
    final p = defenderMap(r['profile']);
    if (p['revision'] is! int ||
        p['habits'] is! Map ||
        !['personal', 'business'].contains(p['mode'])) {
      throw const DefenderException(
        'Your checklist change was not confirmed. Refresh before retrying.',
      );
    }
    return p;
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      _report(
        (await _request('POST', '/reports', body))['report'],
        body['request_key'],
      );
  Future<Map<String, dynamic>> open(String id) async =>
      _report((await _request('GET', '/reports/$id'))['report'], id);
  Future<Map<String, dynamic>> progress(
    String id,
    Map<String, dynamic> body,
  ) async => _report(
    (await _request('PUT', '/reports/$id/progress', body))['report'],
    id,
  );
  Future<void> remove(String id) async {
    final r = await _request('DELETE', '/reports/$id', {'confirmed': true});
    if (r['removed'] != true) {
      throw const DefenderException(
        'Removal was not confirmed. Refresh Saved reports.',
      );
    }
  }

  Future<List<int>> export(String id) async {
    final req = http.Request('GET', _uri('/reports/$id/export'))
      ..headers.addAll(headersBuilder());
    final r = await _send(req);
    if (!r.headers['content-type'].toString().contains('text/plain') ||
        r.bodyBytes.isEmpty ||
        r.bodyBytes.length > 500000) {
      throw const DefenderException(
        'The Defender report download was incomplete. Try again.',
      );
    }
    _guard();
    return r.bodyBytes;
  }
}

Map<String, dynamic> defenderMap(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : {};
List<Map<String, dynamic>> defenderItems(dynamic x) =>
    x is List ? x.map(defenderMap).toList() : [];
