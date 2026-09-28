import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../live_convo/agent_studio_client.dart'
    show agentAccountScope, agentStudioKey;

typedef SocialMap = Map<String, dynamic>;
SocialMap socialMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};
List<SocialMap> socialItems(dynamic v) =>
    v is List ? v.map(socialMap).toList() : [];
String socialId() => agentStudioKey();

class SocialException implements Exception {
  const SocialException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SocialClient extends ChangeNotifier {
  SocialClient({
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
  void _check() {
    if (!_closed &&
        !_denied &&
        (_scope.isEmpty || _scope != agentAccountScope(headersBuilder()))) {
      _denied = true;
      notifyListeners();
    }
  }

  void _guard() {
    _check();
    if (!available) {
      throw const SocialException(
        'Your session changed. Sign in and reopen KORLIX Social.',
        401,
      );
    }
  }

  Future<SocialMap> get(String action, [SocialMap data = const {}]) =>
      _request('GET', action, data);
  Future<SocialMap> post(String action, [SocialMap data = const {}]) =>
      _request('POST', action, data);
  Future<SocialMap> _request(
    String method,
    String action,
    SocialMap data,
  ) async {
    _guard();
    final uri = Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/social/$action',
    );
    final request =
        http.Request(
            method,
            method == 'GET'
                ? uri.replace(
                    queryParameters: data.map((k, v) => MapEntry(k, '$v')),
                  )
                : uri,
          )
          ..headers.addAll({
            ...headersBuilder(),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          });
    if (method == 'POST') request.body = jsonEncode(data);
    try {
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
      _guard();
      if (response.statusCode == 401) {
        _denied = true;
        notifyListeners();
      }
      SocialMap result;
      try {
        result = socialMap(jsonDecode(response.body));
      } catch (_) {
        throw const SocialException(
          'The response could not be read. Refresh and try again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SocialException(
          result['error']?.toString() ??
              'KORLIX Social is unavailable. Try again.',
          response.statusCode,
        );
      }
      return result;
    } on TimeoutException {
      _guard();
      throw const SocialException(
        'Still waiting for a response. Refresh before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const SocialException('Check your connection and refresh.');
    }
  }

  @override
  void dispose() {
    _closed = true;
    sessionChanges?.removeListener(_check);
    if (_owns) _http.close();
    super.dispose();
  }
}
