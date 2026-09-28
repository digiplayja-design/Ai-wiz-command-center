import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String inventoryRequestKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class InventoryException implements Exception {
  const InventoryException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class InventoryClient {
  InventoryClient({
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
      throw const InventoryException('Reopen Inventory to continue.');
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
      throw const InventoryException(
        'Sign in again and reopen Inventory.',
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
    '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/inventory$path',
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
        throw InventoryException(
          error ??
              'Inventory could not finish this request. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const InventoryException(
        'This is taking longer than expected. Refresh to check whether it finished before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const InventoryException(
        'Check your connection, then refresh your Inventory.',
      );
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const InventoryException(
        'The Inventory returned an unreadable response. Refresh and try again.',
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

  Future<Map<String, dynamic>> workspace() => _request('GET', '');
  Future<Map<String, dynamic>> search(Map<String, dynamic> filters) => _request(
    'GET',
    '/search?${Uri(queryParameters: filters.map((k, v) => MapEntry(k, '$v'))).query}',
  );
  Future<Map<String, dynamic>> item(String id) => _request('GET', '/items/$id');
  Future<Map<String, dynamic>> change(Map<String, dynamic> body) =>
      _request('POST', '/changes', body);
  Future<Map<String, dynamic>> events({int offset = 0, String? item}) =>
      _request(
        'GET',
        '/events?offset=$offset${item == null ? '' : '&item=$item'}',
      );
  Future<List<Map<String, dynamic>>> importPreview(String csv) async =>
      inventoryItems(
        (await _request('POST', '/import/preview', {'csv': csv}))['products'],
      );
  Future<Map<String, dynamic>> scan(String id) =>
      _request('GET', '/vision/$id');
  Future<Map<String, dynamic>> upload(
    String path,
    Uint8List bytes,
    String name,
    Map<String, String> fields,
  ) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(headersBuilder())
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: name));
    return _json(await _send(request));
  }

  Future<Uint8List> export() async {
    final request = http.Request('GET', _uri('/export'))
      ..headers.addAll(headersBuilder());
    final response = await _send(request);
    if (!response.headers['content-type'].toString().contains('text/csv') ||
        response.bodyBytes.isEmpty) {
      throw const InventoryException(
        'The export could not be verified. Try again.',
      );
    }
    return response.bodyBytes;
  }
}

Map<String, dynamic> inventoryMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> inventoryItems(dynamic value) =>
    value is List ? value.map(inventoryMap).toList() : [];
double inventoryNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String inventoryQuantity(dynamic value) {
  final n = inventoryNumber(value);
  return n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
}
