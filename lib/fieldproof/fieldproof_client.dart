import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String fieldProofRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class FieldProofException implements Exception {
  const FieldProofException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class FieldProofClient {
  FieldProofClient({
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
  final Set<VoidCallback> _accessListeners = {};
  bool get sessionChanged => _closed || _changed;
  void addAccessDeniedListener(VoidCallback listener) =>
      _accessListeners.add(listener);
  void removeAccessDeniedListener(VoidCallback listener) =>
      _accessListeners.remove(listener);
  void _deny() {
    onAccessDenied?.call();
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
      throw const FieldProofException('Reopen FieldProof to continue.');
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
      throw const FieldProofException(
        'Sign in again and reopen FieldProof.',
        401,
      );
    }
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/fieldproof$path',
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
          _deny();
        }
        String? error;
        try {
          error = (jsonDecode(response.body) as Map)['error']?.toString();
        } catch (_) {}
        throw FieldProofException(
          error ??
              'FieldProof could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const FieldProofException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const FieldProofException(
        'Check your connection, then refresh FieldProof.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const FieldProofException(
        'FieldProof returned an unreadable response. Refresh and try again.',
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
    final result = _json(await _send(r));
    if (path == '/jobs' ||
        (path.startsWith('/jobs/') &&
            !path.endsWith('/reviews') &&
            method != 'DELETE') ||
        (path.startsWith('/photos/') && method == 'DELETE')) {
      final expected = path == '/jobs'
          ? (body?['request_key'])
          : path.startsWith('/jobs/')
          ? path.split('/')[2]
          : null;
      return _snapshot(result, expected);
    }
    if (method == 'DELETE' && result['deleted'] != true) {
      throw const FieldProofException(
        'Deletion was not confirmed. Refresh and retry.',
      );
    }
    return result;
  }

  Map<String, dynamic> _snapshot(
    Map<String, dynamic> result,
    Object? expected,
  ) {
    final job = result['job'];
    if (job is! Map ||
        job['id'] is! String ||
        (expected != null && job['id'] != expected) ||
        job['version'] is! int ||
        job['version'] < 1 ||
        job['data'] is! Map ||
        result['evidence'] is! List ||
        result['readiness'] is! Map) {
      throw const FieldProofException(
        'The saved job was not confirmed. Your entries remain here; refresh before retrying.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> prepareVoiceDraft(
    String? id,
    int? revision,
    Map<String, dynamic> draft,
  ) => _request('POST', '/voice/draft', {
    'jobId': id,
    'version': revision,
    'draft': draft,
  });

  Future<Map<String, dynamic>> load() => _request('GET', '');
  Future<Map<String, dynamic>> job(String id) => _request('GET', '/jobs/$id');
  Future<Map<String, dynamic>> create(String key, Map<String, dynamic> data) =>
      _request('POST', '/jobs', {'request_key': key, 'data': data});
  Future<Map<String, dynamic>> save(
    String id,
    int version,
    Map<String, dynamic> data,
  ) => _request('PUT', '/jobs/$id', {'version': version, 'data': data});
  Future<Map<String, dynamic>> approve(
    String id,
    int version,
    String name,
    String note,
  ) => _request('POST', '/jobs/$id/approval', {
    'version': version,
    'confirmed': true,
    'name': name,
    'note': note,
  });
  Future<Map<String, dynamic>> complete(String id, int version) => _request(
    'POST',
    '/jobs/$id/complete',
    {'version': version, 'confirmed': true},
  );
  Future<Map<String, dynamic>> reopen(String id, int version) => _request(
    'POST',
    '/jobs/$id/reopen',
    {'version': version, 'confirmed': true},
  );
  Future<void> remove(String id, int version) async {
    await _request('DELETE', '/jobs/$id', {
      'version': version,
      'confirmed': true,
    });
  }

  Future<Map<String, dynamic>> removePhoto(String id) =>
      _request('DELETE', '/photos/$id', {'confirmed': true});
  Future<Map<String, dynamic>> startReview(
    String id,
    int version,
    String key,
  ) async => Map<String, dynamic>.from(
    (await _request('POST', '/jobs/$id/reviews', {
      'version': version,
      'request_key': key,
      'consent': true,
    }))['review'],
  );
  Future<Uint8List> photoBytes(String id, {bool preview = false}) async =>
      (await _send(
        http.Request(
          'GET',
          _uri('/photos/$id/file${preview ? '?preview=true' : ''}'),
        )..headers.addAll(headersBuilder()),
      )).bodyBytes;
  Future<Map<String, dynamic>> upload(
    String jobId,
    int version,
    FieldProofPhoto photo, {
    required String key,
    required String tag,
    required String name,
    required String note,
  }) async {
    if (photo.bytes.isEmpty || photo.bytes.length > 10 * 1024 * 1024) {
      throw const FieldProofException(
        'Choose one JPG, PNG or WEBP photo under 10 MB.',
      );
    }
    final headers = Map<String, String>.from(headersBuilder())
      ..removeWhere((k, _) => k.toLowerCase() == 'content-type');
    final r = http.MultipartRequest('POST', _uri('/jobs/$jobId/photos'))
      ..headers.addAll(headers)
      ..fields.addAll({
        'version': '$version',
        'request_key': key,
        'tag': tag,
        'name': name,
        'note': note,
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          photo.bytes,
          filename: photo.name,
        ),
      );
    return _snapshot(_json(await _send(r)), jobId);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    _accessListeners.clear();
    if (_ownsClient) _http.close();
  }
}

class FieldProofPhoto {
  const FieldProofPhoto(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
