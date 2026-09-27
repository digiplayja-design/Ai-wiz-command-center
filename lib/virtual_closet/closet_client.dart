import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../improve_picture/picture_studio_client.dart';

String closetRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class ClosetException implements Exception {
  const ClosetException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class ClosetAsset {
  ClosetAsset.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      name = j['name'] as String,
      category = j['category'] as String,
      state = j['state'] as String,
      imageUrl = j['imageUrl'] as String?,
      thumbnailUrl = j['thumbnailUrl'] as String?;
  final String id, kind, name, category, state;
  final String? imageUrl, thumbnailUrl;
  bool get ready => state == 'ready';
}

class ClosetJob {
  ClosetJob.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      state = j['state'] as String,
      result = Map<String, dynamic>.from(j['result'] as Map? ?? {}),
      error = j['error'] as String?,
      prompt = j['prompt'] as String? ?? '',
      photoId = j['photo_id'] as String?,
      garmentIds = List<String>.from(j['garment_ids'] as List? ?? []);
  final String id, kind, state, prompt;
  final String? error, photoId;
  final List<String> garmentIds;
  final Map<String, dynamic> result;
  bool get running => state == 'running';
}

class ClosetSnapshot {
  ClosetSnapshot.fromJson(Map<String, dynamic> j)
    : assets = (j['assets'] as List)
          .map((v) => ClosetAsset.fromJson(Map<String, dynamic>.from(v)))
          .toList(),
      jobs = (j['jobs'] as List)
          .map((v) => ClosetJob.fromJson(Map<String, dynamic>.from(v)))
          .toList();
  final List<ClosetAsset> assets;
  final List<ClosetJob> jobs;
}

class ClosetClient {
  ClosetClient({
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
      throw const ClosetException('Reopen Virtual Closet to continue.');
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
      throw const ClosetException(
        'Sign in again and reopen Virtual Closet.',
        401,
      );
    }
  }

  Uri _uri(String path) => Uri.parse(
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/virtual-closet$path',
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
        throw ClosetException(
          error ??
              'Virtual Closet could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const ClosetException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const ClosetException(
        'Check your connection, then refresh your closet.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const ClosetException(
        'The closet returned an unreadable response. Refresh and try again.',
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

  Future<ClosetSnapshot> load() async =>
      ClosetSnapshot.fromJson(await _request('GET', ''));
  Future<ClosetAsset> upload({
    required PlatformFile file,
    required String key,
    required String kind,
    required String name,
    required String category,
  }) async {
    final error = pictureFileError(file);
    if (error != null) throw ClosetException(error);
    final headers = Map<String, String>.from(headersBuilder())
      ..removeWhere((k, _) => k.toLowerCase() == 'content-type');
    final r = http.MultipartRequest('POST', _uri('/assets'))
      ..headers.addAll(headers)
      ..fields.addAll({
        'request_key': key,
        'kind': kind,
        'name': name,
        'category': category,
      })
      ..files.add(
        http.MultipartFile.fromBytes('image', file.bytes!, filename: file.name),
      );
    return ClosetAsset.fromJson(
      Map<String, dynamic>.from(_json(await _send(r))['asset']),
    );
  }

  Future<void> remove(String id) async {
    await _request('DELETE', '/assets/$id', {'confirmed': true});
  }

  Future<ClosetJob> start({
    required String key,
    required String kind,
    required String prompt,
    String? photoId,
    List<String> garmentIds = const [],
  }) async {
    return ClosetJob.fromJson(
      Map<String, dynamic>.from(
        (await _request('POST', '/jobs', {
          'request_key': key,
          'kind': kind,
          'prompt': prompt,
          'photo_id': photoId,
          'garment_ids': garmentIds,
          'consent': true,
        }))['job'],
      ),
    );
  }

  Future<ClosetJob> job(String id) async => ClosetJob.fromJson(
    Map<String, dynamic>.from((await _request('GET', '/jobs/$id'))['job']),
  );
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
