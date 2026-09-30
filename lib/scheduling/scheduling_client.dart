import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../live_convo/agent_studio_client.dart' show agentAccountScope;

typedef SchedulingMap = Map<String, dynamic>;
SchedulingMap schedulingMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<SchedulingMap> schedulingItems(dynamic value) =>
    value is List ? value.map(schedulingMap).toList() : [];

class SchedulingException implements Exception {
  const SchedulingException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SchedulingClient extends ChangeNotifier {
  SchedulingClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _owns = client == null {
    _scope = agentAccountScope(headersBuilder());
    sessionChanges?.addListener(_check);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _owns;
  late final String _scope;
  bool _closed = false, _denied = false;
  bool get available => !_closed && !_denied;
  void _deny() {
    if (!_denied && !_closed) {
      _denied = true;
      notifyListeners();
    }
  }

  void _check() {
    if (_scope.isEmpty || _scope != agentAccountScope(headersBuilder())) {
      _deny();
    }
  }

  void guard() {
    _check();
    if (!available) {
      throw const SchedulingException(
        'Sign in with an active verified account and reopen Scheduling.',
        401,
      );
    }
  }

  Future<SchedulingMap> get(String path) => _request('GET', path, null);
  Future<SchedulingMap> post(String path, [SchedulingMap body = const {}]) =>
      _request('POST', path, body);
  Future<SchedulingMap> _request(
    String method,
    String path,
    SchedulingMap? body,
  ) async {
    guard();
    try {
      final request =
          http.Request(
              method,
              Uri.parse(
                '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/scheduling/$path',
              ),
            )
            ..headers.addAll({
              ...headersBuilder(),
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            });
      if (body != null) request.body = jsonEncode(body);
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: path.startsWith('ai/') ? 120 : 70));
      guard();
      if (response.statusCode == 401 || response.statusCode == 403) _deny();
      final data = schedulingMap(jsonDecode(response.body));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SchedulingException(
          data['error']?.toString() ??
              'Scheduling could not complete this request.',
          response.statusCode,
        );
      }
      return data;
    } on SchedulingException {
      rethrow;
    } on TimeoutException {
      throw const SchedulingException(
        'Scheduling took too long to respond. Refresh the workspace before retrying.',
      );
    } catch (_) {
      throw const SchedulingException(
        'Scheduling is unavailable. Check your connection and refresh.',
      );
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_check);
    if (_owns) _http.close();
    super.dispose();
  }
}
