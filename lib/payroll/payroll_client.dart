import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../live_convo/agent_studio_client.dart' show agentAccountScope;

typedef PayrollMap = Map<String, dynamic>;
PayrollMap payrollMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<PayrollMap> payrollItems(dynamic value) =>
    value is List ? value.map(payrollMap).toList() : [];

class PayrollException implements Exception {
  const PayrollException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class PayrollClient extends ChangeNotifier {
  PayrollClient({
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
      throw const PayrollException(
        'Sign in with an active Enterprise business account and reopen Payroll.',
        401,
      );
    }
  }

  Future<PayrollMap> get(String path) => _request('GET', path, null);
  Future<PayrollMap> post(String path, [PayrollMap body = const {}]) =>
      _request('POST', path, body);
  Future<PayrollMap> _request(
    String method,
    String path,
    PayrollMap? body,
  ) async {
    guard();
    try {
      final request =
          http.Request(
              method,
              Uri.parse(
                '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/payroll/$path',
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
          .timeout(const Duration(seconds: 70));
      guard();
      if (response.statusCode == 401 || response.statusCode == 403) _deny();
      final data = payrollMap(jsonDecode(response.body));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PayrollException(
          data['error']?.toString() ??
              'Payroll could not complete this request.',
          response.statusCode,
        );
      }
      return data;
    } on PayrollException {
      rethrow;
    } on TimeoutException {
      throw const PayrollException(
        'Payroll took too long to respond. Refresh the workspace before retrying.',
      );
    } catch (_) {
      throw const PayrollException(
        'Payroll is unavailable. Check your connection and refresh.',
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

Uri payrollFlowUri(PayrollMap session) {
  final uri = Uri.tryParse('${session['url']}');
  final host = session['environment'] == 'production'
      ? 'flows.gusto.com'
      : session['environment'] == 'demo'
      ? 'flows.gusto-demo.com'
      : '';
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != host ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      !uri.path.startsWith('/flows/')) {
    throw const PayrollException(
      'The provider did not return a valid secure session.',
    );
  }
  return uri;
}
