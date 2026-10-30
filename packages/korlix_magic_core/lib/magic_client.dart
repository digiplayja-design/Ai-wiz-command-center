import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:korlix_receipt_core/auth/korlix_http.dart' as transport;
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';

String magicRequestKey() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class MagicApiException implements Exception {
  const MagicApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class MagicClient extends ChangeNotifier {
  MagicClient({
    required this.backendUrl,
    required this.headers,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? transport.createClient() {
    _scope = _identity();
    sessionChanges?.addListener(_sessionChanged);
  }
  final String backendUrl;
  final Map<String, String> Function() headers;
  final Listenable? sessionChanges;
  final http.Client _http;
  String? _scope;
  bool _invalid = false, _disposed = false;
  String? _identity() {
    final h = headers()['Authorization'] ?? headers()['authorization'];
    return h?.startsWith('Bearer ') == true
        ? korlixSessionIdentity(h!.substring(7))
        : null;
  }

  String get accountScope {
    try {
      final h = headers()['Authorization'] ?? headers()['authorization'];
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(h!.substring(7).split('.')[1])),
        ),
      ) as Map;
      return jsonEncode([claims['iss'], claims['sub']]);
    } catch (_) {
      return 'signed-out';
    }
  }

  bool get valid =>
      !_disposed && !_invalid && _scope != null && _identity() == _scope;
  void _sessionChanged() {
    if (_identity() != _scope && !_invalid) {
      _invalid = true;
      notifyListeners();
    }
  }

  void check() {
    if (!valid) {
      throw const MagicApiException(
        'Your account changed. Reopen Magic Camera after signing in.',
        401,
      );
    }
  }

  Uri uri(String path) => Uri.parse(
    '${backendUrl.replaceFirst(RegExp(r'/+$'), '')}/api/magic-camera$path',
  );
  Future<http.Response> _send(
    http.BaseRequest request, {
    int seconds = 45,
  }) async {
    check();
    request.headers.addAll(headers());
    final r = await _http
        .send(request)
        .then(http.Response.fromStream)
        .timeout(Duration(seconds: seconds));
    check();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String message = 'Magic Camera could not connect. Please try again.';
      try {
        message = (jsonDecode(r.body) as Map)['error']?.toString() ?? message;
      } catch (_) {}
      throw MagicApiException(message, r.statusCode);
    }
    return r;
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final q = http.Request(method, uri(path));
    if (body != null) {
      q.headers['Content-Type'] = 'application/json';
      q.body = jsonEncode(body);
    }
    return Map<String, dynamic>.from(jsonDecode((await _send(q)).body) as Map);
  }

  Future<Map<String, dynamic>> snapshot() => request('');
  Future<Map<String, dynamic>> job(String id) async =>
      (await request('/$id'))['job'] as Map<String, dynamic>;
  Future<Map<String, dynamic>> generate(
    Uint8List bytes,
    Map<String, dynamic> options,
    String key,
  ) async {
    final q = http.MultipartRequest('POST', uri(''))
      ..headers['X-Magic-Request-Key'] = key
      ..fields['options'] = jsonEncode(options)
      ..files.add(
        http.MultipartFile.fromBytes('capture', bytes, filename: 'capture.jpg'),
      );
    return (jsonDecode((await _send(q, seconds: 90)).body) as Map)['job']
        as Map<String, dynamic>;
  }

  Future<Uint8List> image(String id) async =>
      (await _send(http.Request('GET', uri('/$id/image')))).bodyBytes;
  Future<void> report(String id, String reason, String details) async {
    await request(
      '/$id/report',
      method: 'POST',
      body: {'reason': reason, 'details': details},
    );
  }

  Future<void> delete(String id) async {
    await request('/$id', method: 'DELETE', body: {'confirmed': true});
  }

  @override
  void dispose() {
    _disposed = true;
    sessionChanges?.removeListener(_sessionChanged);
    _http.close();
    super.dispose();
  }
}
