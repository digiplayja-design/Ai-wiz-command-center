import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String seoRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class SeoException implements Exception {
  const SeoException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SeoClient {
  SeoClient({
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
        (sessionChanges != null || _scope != null) &&
        (_scope == null || _scope != _readScope())) {
      _changed = true;
      onAccessDenied?.call();
    }
  }

  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const SeoException('Reopen SEO Agent to continue.');
    }
    _checkSession();
    if (!_changed &&
        (sessionChanges != null || _scope != null) &&
        headers != null &&
        _scope != _readScope(headers)) {
      _changed = true;
      onAccessDenied?.call();
    }
    if (_changed) {
      throw const SeoException('Sign in again and reopen SEO Agent.', 401);
    }
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/seo-agent$path',
  );
  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      _guard(request.headers);
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 130));
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
        throw SeoException(
          error ??
              'SEO Agent could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const SeoException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const SeoException(
        'Check your connection, then refresh SEO Agent.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const SeoException(
        'SEO Agent returned an unreadable response. Refresh and try again.',
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

  void checkAccess() => _guard();

  Future<Map<String, dynamic>> load() => _request('GET', '');
  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> data) async {
    final profile = (await _request('PUT', '/profile', data))['profile'];
    if (profile is! Map || profile['data'] is! Map) {
      throw const SeoException(
        'The save could not be confirmed. Your entries are still here; try saving again.',
      );
    }
    return Map<String, dynamic>.from(profile);
  }

  Future<Map<String, dynamic>> setMonitoring(bool enabled) async {
    final value = await _request('PUT', '/monitoring', {
      'enabled': enabled,
      if (enabled) 'consent': true,
    });
    final profile = value['profile'];
    if (profile is! Map || profile['data'] is! Map) {
      throw const SeoException(
        'The monitoring change could not be confirmed. Refresh to check its status.',
      );
    }
    return Map<String, dynamic>.from(profile);
  }

  Map<String, dynamic> _run(dynamic value) {
    if (value is! Map || value['id'] is! String || value['state'] is! String) {
      throw const SeoException(
        'This audit could not be loaded. Refresh to check its status.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> start(String requestKey) async => _run(
    (await _request('POST', '/runs', {
      'request_key': requestKey,
      'consent': true,
    }))['run'],
  );
  Future<Map<String, dynamic>> run(String id) async =>
      _run((await _request('GET', '/runs/${Uri.encodeComponent(id)}'))['run']);
  Future<Map<String, dynamic>> progress(
    String id,
    Map<String, dynamic> data,
  ) async => _run(
    (await _request('PATCH', '/runs/${Uri.encodeComponent(id)}', data))['run'],
  );
  Future<void> remove(String id) async {
    await _request('DELETE', '/runs/${Uri.encodeComponent(id)}', {
      'confirmed': true,
    });
  }

  Future<void> clear() async {
    await _request('DELETE', '', {'confirmed': true});
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    if (_ownsClient) _http.close();
  }
}
