import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

String agentStudioKey() {
  final r = Random.secure(), b = List.generate(16, (_) => 0);
  for (var i = 0; i < 16; i++) {
    b[i] = r.nextInt(256);
  }
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String agentAccountScope(Map<String, String> headers) {
  final token =
      headers.entries
          .where((h) => h.key.toLowerCase() == 'authorization')
          .map((h) => h.value)
          .firstOrNull ??
      '';
  try {
    final p = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(token.split(' ').last.split('.')[1]),
        ),
      ),
    );
    if (p['sub'] is String && p['session_id'] is String && p['iss'] is String) {
      return jsonEncode([p['iss'], p['sub'], p['session_id']]);
    }
  } catch (_) {}
  return token;
}

class AgentStudioException implements Exception {
  const AgentStudioException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class AgentStudioClient {
  AgentStudioClient({
    required this.baseUrl,
    required this.headersBuilder,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _owns = client == null {
    _scope = agentAccountScope(headersBuilder());
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final http.Client _http;
  final bool _owns;
  late final String _scope;
  bool _closed = false, _expired = false;
  bool get current =>
      !_closed && !_expired && _scope == agentAccountScope(headersBuilder());
  void guard() {
    if (!current) {
      _expired = true;
      throw const AgentStudioException(
        'Your account changed. Close and reopen Agent Studio.',
        401,
      );
    }
  }

  void dispose() {
    _closed = true;
    if (_owns) _http.close();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    guard();
    final headers = headersBuilder();
    if (agentAccountScope(headers) != _scope) {
      throw const AgentStudioException('Reopen Agent Studio to continue.', 401);
    }
    final req =
        http.Request(
            method,
            Uri.parse(
              '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/agent-studio/workflows$path',
            ),
          )
          ..headers.addAll({
            ...headers,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          });
    if (body != null) req.body = jsonEncode(body);
    late http.Response response;
    try {
      response = await _http
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      guard();
      throw const AgentStudioException(
        'The request is taking longer than expected. Refresh to check its status before retrying.',
      );
    } on http.ClientException {
      guard();
      throw const AgentStudioException(
        'Check your connection and refresh this workflow.',
      );
    }
    guard();
    if (response.statusCode == 401) _expired = true;
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const AgentStudioException(
        'Agent Studio returned an unreadable response. Refresh and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgentStudioException(
        data['error']?.toString() ?? 'This workflow could not be updated.',
        response.statusCode,
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> list() async =>
      ((await request('GET', ''))['workflows'] as List)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from((await request('GET', '/$id'))['workflow']);
  Future<Map<String, dynamic>> create(Map<String, dynamic> plan) async =>
      Map<String, dynamic>.from((await request('POST', '', plan))['workflow']);
  Future<Map<String, dynamic>> run(Map<String, dynamic> w, String key) async =>
      Map<String, dynamic>.from(
        (await request('POST', '/${w['id']}/run', {
          'revision': w['revision'],
          'attempt_id': key,
        }))['workflow'],
      );
  Future<Map<String, dynamic>> act(
    Map<String, dynamic> w,
    String action, {
    String? feedback,
  }) async => Map<String, dynamic>.from(
    (await request('POST', '/${w['id']}/actions', {
      'revision': w['revision'],
      'action': action,
      'confirmed': true,
      'feedback': ?feedback,
    }))['workflow'],
  );
}
