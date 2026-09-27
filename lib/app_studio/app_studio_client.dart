import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String appRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class AppStudioException implements Exception {
  const AppStudioException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class AppStudioClient {
  AppStudioClient({
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
      throw const AppStudioException('Reopen App Studio to continue.');
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
      throw const AppStudioException(
        'Sign in again and reopen App Studio.',
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
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/app-studio$path',
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
        throw AppStudioException(
          error ??
              'App Studio could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const AppStudioException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const AppStudioException(
        'Check your connection, then refresh your App Studio.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const AppStudioException(
        'The App Studio returned an unreadable response. Refresh and try again.',
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

  Map<String, dynamic> project(dynamic v) {
    if (v is! Map ||
        v['id'] is! String ||
        v['version'] is! int ||
        v['brief'] is! Map ||
        v['spec'] is! Map) {
      throw const AppStudioException(
        'The saved project was not confirmed. Refresh before retrying.',
      );
    }
    return Map<String, dynamic>.from(v);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final r = await _request('GET', '');
    if (r['projects'] is! List) {
      throw const AppStudioException('Your projects could not be loaded.');
    }
    return (r['projects'] as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      project((await _request('POST', '/projects', body))['project']);
  Future<Map<String, dynamic>> open(String id) async {
    final r = await _request('GET', '/projects/$id');
    project(r['project']);
    if (r['project']['id'] != id ||
        r['versions'] is! List ||
        (r['previewHtml'] != null && r['previewHtml'] is! String)) {
      throw const AppStudioException('Project response was incomplete.');
    }
    return r;
  }

  Future<Map<String, dynamic>> build(
    String id,
    Map<String, dynamic> body,
  ) async {
    final r = await _request('POST', '/projects/$id/build', body);
    if (r['run'] is! Map ||
        r['run']['id'] != body['request_key'] ||
        r['run']['projectId'] != id) {
      throw const AppStudioException(
        'Build acknowledgement was not confirmed. Refresh your project.',
      );
    }
    return Map<String, dynamic>.from(r['run']);
  }

  Future<Map<String, dynamic>> style(
    String id,
    Map<String, dynamic> body,
  ) async =>
      project((await _request('PUT', '/projects/$id/style', body))['project']);
  Future<Map<String, dynamic>> restore(
    String id,
    Map<String, dynamic> body,
  ) async => project(
    (await _request('POST', '/projects/$id/restore', body))['project'],
  );
  Future<void> remove(String id) async {
    final r = await _request('DELETE', '/projects/$id', {'confirmed': true});
    if (r['removed'] != true) {
      throw const AppStudioException(
        'Removal was not confirmed. Refresh your projects.',
      );
    }
  }

  Future<List<int>> export(String id) async {
    final r = http.Request('GET', _uri('/projects/$id/export'))
      ..headers.addAll(headersBuilder());
    final response = await _send(r), b = response.bodyBytes;
    if (!response.headers['content-type'].toString().contains(
          'application/zip',
        ) ||
        b.length < 22 ||
        b.length > 2000000 ||
        b[0] != 80 ||
        b[1] != 75) {
      throw const AppStudioException(
        'The app download was incomplete. Please try again.',
      );
    }
    return b;
  }
}
