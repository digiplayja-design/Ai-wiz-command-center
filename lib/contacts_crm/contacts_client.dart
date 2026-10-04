import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const contactCategories = [
  'friend',
  'family',
  'customer',
  'unknown',
  'lead',
  'partner',
  'vendor',
];
String contactLabel(String value) => value.isEmpty
    ? ''
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';

class ContactsException implements Exception {
  const ContactsException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

typedef CrmJson = Map<String, dynamic>;
CrmJson crmClone(CrmJson value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
CrmJson crmMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<CrmJson> crmRows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((x) => Map<String, dynamic>.from(x))
    .toList();

class ContactsClient {
  ContactsClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.sessionChanges,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null {
    _scope = _readScope();
    sessionChanges?.addListener(_checkSession);
    if(sessionChanges == null && _scope != null) {
      _sessionTimer = Timer.periodic(const Duration(seconds:1), (_) => _checkSession());
    }
  }
  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final http.Client _http;
  final bool _ownsClient;
  void Function()? onAccessDenied;
  final Listenable? sessionChanges;
  String? _scope;
  Timer? _sessionTimer;
  bool _closed = false, _changed = false;
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
        (_scope != null || sessionChanges != null) &&
        (_scope == null || _scope != _readScope())) {
      _changed = true;
      _deny();
    }
  }

  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const ContactsException('Reopen CRM to continue.');
    }
    _checkSession();
    if (!_changed &&
        (_scope != null || sessionChanges != null) &&
        headers != null &&
        _scope != _readScope(headers)) {
      _changed = true;
      _deny();
    }
    if (_changed) {
      throw const ContactsException('Sign in again and reopen CRM.', 401);
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _sessionTimer?.cancel();
    sessionChanges?.removeListener(_checkSession);
    _accessListeners.clear();
    if (_ownsClient) _http.close();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    CrmJson? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/contacts$path',
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
        if (res.statusCode == 401 || res.statusCode == 403) {
          _changed = true;
          _deny();
        }
        String message =
            'CRM could not complete this request. Please try again.';
        try {
          message =
              (jsonDecode(res.body) as Map)['error']?.toString() ?? message;
        } catch (_) {}
        throw ContactsException(message, res.statusCode);
      }
      return res;
    } on TimeoutException {
      _guard();
      throw const ContactsException(
        'Connection timed out. Refresh to check whether your action was saved before trying again.',
      );
    } on http.ClientException {
      _guard();
      throw const ContactsException(
        'Check your connection, then refresh your shift.',
      );
    }
  }

  Future<CrmJson> request(
    String method,
    String path, {
    CrmJson? body,
    Map<String, String>? query,
  }) async {
    final res = await _send(method, path, body: body, query: query);
    try {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      throw const ContactsException(
        'CRM returned an unreadable response. Refresh and try again.',
      );
    }
  }
}
