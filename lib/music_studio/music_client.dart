import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String musicRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class MusicException implements Exception {
  const MusicException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class MusicClient {
  MusicClient({
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
  final Set<VoidCallback> _accessDeniedListeners = {};
  bool get sessionChanged =>
      _closed ||
      _changed ||
      (sessionChanges != null && (_scope == null || _scope != _readScope()));

  void addAccessDeniedListener(VoidCallback listener) =>
      _accessDeniedListeners.add(listener);
  void removeAccessDeniedListener(VoidCallback listener) =>
      _accessDeniedListeners.remove(listener);

  void _accessDenied() {
    if (_closed || _changed) return;
    _changed = true;
    onAccessDenied?.call();
    for (final listener in List<VoidCallback>.of(_accessDeniedListeners)) {
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
      _accessDenied();
    }
  }

  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const MusicException('Reopen Music Studio to continue.');
    }
    _checkSession();
    if (!_changed &&
        sessionChanges != null &&
        headers != null &&
        _scope != _readScope(headers)) {
      _accessDenied();
    }
    if (_changed) {
      throw const MusicException('Sign in again and reopen Music Studio.', 401);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    _accessDeniedListeners.clear();
    if (_ownsClient) _http.close();
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/music$path',
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
          _accessDenied();
        }
        String? error;
        try {
          error = (jsonDecode(response.body) as Map)['error']?.toString();
        } catch (_) {}
        throw MusicException(
          error ??
              'Music Studio could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const MusicException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const MusicException(
        'Check your connection, then refresh your Music Studio.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const MusicException(
        'The Music Studio returned an unreadable response. Refresh and try again.',
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

  Map<String, dynamic> checkedJob(dynamic value, [String? expected]) {
    if (value is! Map ||
        value['id'] is! String ||
        (expected != null && value['id'] != expected) ||
        value['tracks'] is! List ||
        value['settings'] is! Map ||
        ![
          'submitting',
          'submitted',
          'processing',
          'completed',
          'partial',
          'failed',
          'uncertain',
        ].contains(value['status'])) {
      throw const MusicException(
        'The saved creation was not confirmed. Refresh before retrying.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> checkedDraft(dynamic value) {
    if (value is! Map || value['version'] is! int || value['data'] is! Map) {
      throw const MusicException(
        'The saved draft was not confirmed. Reload before retrying.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> load() async {
    final r = await _request('GET', '/studio');
    if (r['addon'] is! Map || r['jobs'] is! List) {
      throw const MusicException(
        'Your music library could not be loaded. Refresh shortly.',
      );
    }
    for (final j in r['jobs']) {
      checkedJob(j);
    }
    checkedDraft(r['draft']);
    return r;
  }

  Future<Map<String, dynamic>> jobs({
    String query = '',
    bool favorites = false,
    String? before,
  }) async {
    final q = Uri(
      queryParameters: {
        'query': query,
        'favorites': '$favorites',
        'before': ?before,
      },
    ).query;
    final r = await _request('GET', '/jobs?$q');
    if (r['jobs'] is! List) {
      throw const MusicException('Your music library could not be loaded.');
    }
    for (final j in r['jobs']) {
      checkedJob(j);
    }
    return r;
  }

  Future<Map<String, dynamic>> draft() async =>
      checkedDraft((await _request('GET', '/draft'))['draft']);
  Future<Map<String, dynamic>> prepareVoiceDraft(
    Map<String, dynamic> body,
  ) async => _request('POST', '/voice/draft', body);
  Future<Map<String, dynamic>> saveDraft(Map<String, dynamic> body) async =>
      checkedDraft((await _request('PUT', '/draft', body))['draft']);
  Future<Map<String, dynamic>> generate(Map<String, dynamic> body) async {
    final r = await _request('POST', '/generate', body);
    checkedJob(r['job'], body['request_key']);
    return r;
  }

  Future<Map<String, dynamic>> status(String id) async =>
      checkedJob((await _request('GET', '/status/$id'))['job'], id);
  Future<Map<String, dynamic>> favorite(String id, bool value) async =>
      checkedJob(
        (await _request('PUT', '/jobs/$id/favorite', {
          'favorite': value,
        }))['job'],
        id,
      );
  Future<void> remove(String id) async {
    if ((await _request('DELETE', '/jobs/$id', {
          'confirmed': true,
        }))['removed'] !=
        true) {
      throw const MusicException(
        'Removal was not confirmed. Refresh before retrying.',
      );
    }
  }

  Future<MusicDownload> download(String id, int index) async {
    final r = await _send(
      http.Request('GET', _uri('/jobs/$id/tracks/$index/file'))
        ..headers.addAll(headersBuilder()),
    );
    final mime = r.headers['content-type']?.split(';').first;
    final extension = {
      'audio/mpeg': 'mp3',
      'audio/wav': 'wav',
      'audio/mp4': 'm4a',
    }[mime];
    if (extension == null ||
        r.bodyBytes.isEmpty ||
        r.bodyBytes.length > 64 * 1024 * 1024) {
      throw const MusicException(
        'The audio download was not confirmed. Try Open audio.',
      );
    }
    return MusicDownload(r.bodyBytes, mime!, extension);
  }
}

class MusicDownload {
  const MusicDownload(this.bytes, this.mime, this.extension);
  final Uint8List bytes;
  final String mime, extension;
}
