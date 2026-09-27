import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String babyBlendRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class BabyBlendException implements Exception {
  const BabyBlendException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class BabyBlendClient {
  BabyBlendClient({
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
      throw const BabyBlendException('Reopen BabyBlend to continue.');
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
      throw const BabyBlendException(
        'Sign in again and reopen BabyBlend.',
        401,
      );
    }
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/babyblend$path',
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
        throw BabyBlendException(
          error ??
              'BabyBlend could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const BabyBlendException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const BabyBlendException(
        'Check your connection, then refresh your BabyBlend.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const BabyBlendException(
        'The BabyBlend returned an unreadable response. Refresh and try again.',
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

  Map<String, dynamic> _asset(dynamic value, {String? expected}) {
    if (value is! Map ||
        value['id'] is! String ||
        (expected != null && value['id'] != expected) ||
        !['source', 'portrait'].contains(value['kind']) ||
        !['ready', 'uploading', 'deleting'].contains(value['state'])) {
      throw const BabyBlendException(
        'The saved photo was not confirmed. Refresh before retrying.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> _job(dynamic value, String expected) {
    if (value is! Map ||
        value['id'] != expected ||
        !['running', 'completed', 'failed'].contains(value['state']) ||
        value['photoIds'] is! List ||
        (value['photoIds'] as List).length != 2) {
      throw const BabyBlendException(
        'The portrait request was not confirmed. Refresh before retrying.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> load() async {
    final r = await _request('GET', '');
    if (r['assets'] is! List || r['jobs'] is! List) {
      throw const BabyBlendException(
        'BabyBlend returned an unreadable workspace. Refresh and try again.',
      );
    }
    for (final a in r['assets']) {
      _asset(a);
    }
    return r;
  }

  Future<Map<String, dynamic>> upload(BabyBlendPhoto photo, String key) async {
    if (photo.bytes.isEmpty || photo.bytes.length > 15 * 1024 * 1024) {
      throw const BabyBlendException(
        'Choose one JPG, PNG or WEBP photo under 15 MB.',
      );
    }
    final headers = Map<String, String>.from(headersBuilder())
      ..removeWhere((k, _) => k.toLowerCase() == 'content-type');
    final r = http.MultipartRequest('POST', _uri('/photos'))
      ..headers.addAll(headers)
      ..fields.addAll({'request_key': key})
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          photo.bytes,
          filename: photo.name,
        ),
      );
    return _asset(_json(await _send(r))['asset'], expected: key);
  }

  Future<void> remove(String id) async {
    final r = await _request('DELETE', '/assets/$id', {'confirmed': true});
    if (r['deleted'] != true) {
      throw const BabyBlendException(
        'Photo removal was not confirmed. Refresh and retry.',
      );
    }
  }

  Future<Map<String, dynamic>> start({
    required String key,
    required List<String> photoIds,
    required String age,
    required String style,
  }) async {
    final r = await _request('POST', '/jobs', {
      'request_key': key,
      'photo_ids': photoIds,
      'age': age,
      'style': style,
      'consent': true,
      'adult_photo_permission': true,
    });
    final j = _job(r['job'], key);
    if (j['age'] != age ||
        j['style'] != style ||
        !listEquals(List<String>.from(j['photoIds']), photoIds)) {
      throw const BabyBlendException(
        'The portrait does not match your choices. Refresh before retrying.',
      );
    }
    return j;
  }

  Future<Map<String, dynamic>> job(String id) async {
    final r = await _request('GET', '/jobs/$id');
    _job(r['job'], id);
    if (r['asset'] != null) _asset(r['asset'], expected: id);
    return r;
  }

  Future<Uint8List> imageBytes(String id) async => (await _send(
    http.Request('GET', _uri('/assets/$id/file'))
      ..headers.addAll(headersBuilder()),
  )).bodyBytes;
  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    if (_ownsClient) _http.close();
  }
}

class BabyBlendPhoto {
  const BabyBlendPhoto(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
