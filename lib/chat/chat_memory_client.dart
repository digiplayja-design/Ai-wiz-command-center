import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../live_convo/agent_studio_client.dart'
    show agentAccountScope, agentStudioKey;

typedef MemoryNote = Map<String, dynamic>;

/// Local cache namespace only; the server still verifies every request.
/// Excludes credentials and session IDs so the same account survives sign-in.
String chatAccountStorageKey(Map<String, String> headers) {
  try {
    final token = headers.entries
        .firstWhere((e) => e.key.toLowerCase() == 'authorization')
        .value
        .split(' ')
        .last;
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    if (claims['sub'] is String &&
        '${claims['sub']}'.isNotEmpty &&
        claims['iss'] is String) {
      return base64Url.encode(
        utf8.encode(jsonEncode([claims['iss'], claims['sub']])),
      );
    }
  } catch (_) {}
  return 'unassigned-${agentStudioKey()}';
}

class ChatMemoryClient extends ChangeNotifier {
  ChatMemoryClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _owns = client == null {
    _scope = agentAccountScope(headersBuilder());
    sessionChanges?.addListener(_checkSession);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _owns;
  late final String _scope;
  bool _closed = false, _denied = false;
  bool busy = false, loaded = false, enabled = true;
  String? error;
  List<MemoryNote> items = [];
  bool get available => !_closed && !_denied;

  void _checkSession() {
    if (!_closed &&
        !_denied &&
        (_scope.isEmpty || _scope != agentAccountScope(headersBuilder()))) {
      _deny();
      notifyListeners();
    }
  }

  void _deny() {
    _denied = true;
    items = [];
    loaded = false;
    error = 'Your session changed. Sign in again to open your memories.';
  }

  void _guard() {
    _checkSession();
    if (!available) throw StateError('Your session changed. Sign in again.');
  }

  Future<bool> load() => _request('list');
  Future<bool> setEnabled(bool value) =>
      _request('settings', {'enabled': value});
  Future<bool> save(String text, String category, {MemoryNote? previous}) =>
      _request('save', {
        'id': previous?['id'] ?? agentStudioKey(),
        'body': text.trim(),
        'category': category,
        if (previous != null) 'version': previous['version'],
      });
  Future<bool> forget(String id) => _request('delete', {'id': id});
  Future<bool> clear() => _request('clear', {'confirm': true});

  Future<bool> _request(String action, [MemoryNote? data]) async {
    if (busy || !available) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      _guard();
      final uri = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/chat-memory/$action',
      );
      final headers = {...headersBuilder(), 'Content-Type': 'application/json'};
      final response =
          await (data == null
                  ? _http.get(uri, headers: headers)
                  : _http.post(uri, headers: headers, body: jsonEncode(data)))
              .timeout(const Duration(seconds: 25));
      _guard();
      if (response.statusCode == 401) {
        _deny();
        return false;
      }
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        error = result is Map
            ? '${result['error'] ?? 'Memory could not be confirmed. Refresh and try again.'}'
            : 'Memory is unavailable.';
        return false;
      }
      if (result is! Map ||
          result['items'] is! List ||
          result['enabled'] is! bool) {
        throw const FormatException();
      }
      items = (result['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      enabled = result['enabled'] as bool;
      loaded = true;
      return true;
    } catch (_) {
      if (available) {
        error =
            'Memory could not be confirmed. Check your connection and refresh before retrying.';
      }
      return false;
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    items = [];
    sessionChanges?.removeListener(_checkSession);
    if (_owns) _http.close();
    super.dispose();
  }
}
