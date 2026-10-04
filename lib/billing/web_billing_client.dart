import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef BillingJson = Map<String, dynamic>;

class WebBillingException implements Exception {
  const WebBillingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebBillingClient {
  WebBillingClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null {
    _scope = _readScope();
    sessionChanges?.addListener(_checkSession);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _ownsHttp;
  String? _scope;
  bool _closed = false, _denied = false;
  VoidCallback? onAccessChanged;
  bool get active => !_closed && !_denied;
  String? _readScope() {
    try {
      final h = headersBuilder().entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value;
      final p = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(h.split(' ').last.split('.')[1]),
          ),
        ),
      );
      final parts = [p['iss'], p['sub'], p['session_id']];
      return parts.every((x) => x is String && x.isNotEmpty)
          ? jsonEncode(parts)
          : null;
    } catch (_) {
      return null;
    }
  }

  void _checkSession() {
    if (!_closed && !_denied && (_scope == null || _readScope() != _scope)) {
      _denied = true;
      onAccessChanged?.call();
    }
  }

  void _guard() {
    _checkSession();
    if (!active) {
      throw const WebBillingException(
        'Your account changed. Close billing and sign in again.',
      );
    }
  }

  Future<BillingJson> _request(
    String method,
    String path, [
    BillingJson? body,
  ]) async {
    _guard();
    try {
      final request =
          http.Request(
              method,
              Uri.parse(
                '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/billing/web$path',
              ),
            )
            ..headers.addAll({
              ...headersBuilder(),
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            });
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async => http.Response.fromStream(
        await _http.send(request),
      ))().timeout(const Duration(seconds: 60));
      _guard();
      BillingJson data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const WebBillingException(
          'Billing returned an unreadable response. Please refresh.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          _denied = true;
          onAccessChanged?.call();
        }
        throw WebBillingException(
          data['error'] is String
              ? data['error']
              : 'Billing is temporarily unavailable. Please retry.',
        );
      }
      return data;
    } on TimeoutException {
      _guard();
      throw const WebBillingException(
        'The connection timed out. Refresh billing before starting another purchase.',
      );
    } on http.ClientException {
      _guard();
      throw const WebBillingException(
        'Check your connection and refresh billing.',
      );
    }
  }

  Future<BillingJson> status({bool refresh = false}) =>
      _request(refresh ? 'POST' : 'GET', refresh ? '/refresh' : '/status');
  Future<Uri> checkout(String tier, String version) async => _link(
    await _request('POST', '/checkout', {
      'tier': tier,
      'version': version,
      'acceptRecurring': true,
    }),
    'checkout.stripe.com',
  );
  Future<Uri> portal() async =>
      _link(await _request('POST', '/portal'), 'billing.stripe.com');
  Future<BillingJson> cancelRenewal() =>
      _request('POST', '/cancel', {'confirm': true});
  Future<BillingJson> abandonCheckout() =>
      _request('POST', '/abandon-checkout', {'confirm': true});
  Uri _link(BillingJson data, String host) {
    _guard();
    final uri = Uri.tryParse(data['url'] is String ? data['url'] : '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != host ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443) {
      throw const WebBillingException(
        'The payment link could not be verified. Please refresh billing.',
      );
    }
    return uri;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessChanged = null;
    if (_ownsHttp) _http.close();
  }
}
