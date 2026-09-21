import 'dart:async';
import 'dart:convert';

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

class ContactsClient {
  ContactsClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null;
  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final http.Client _http;
  final bool _ownsClient;
  void Function()? onAccessDenied;
  void dispose() {
    if (_ownsClient) _http.close();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/contacts$path',
    ).replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers.addAll({
        ...headersBuilder(),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await (() async => http.Response.fromStream(
        await _http.send(req),
      ))().timeout(const Duration(seconds: 40));
      Map<String, dynamic>? result;
      try {
        result = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        /* Handle invalid upstream responses below. */
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          onAccessDenied?.call();
        }
        throw ContactsException(
          result?['error']?.toString() ??
              'Contacts could not complete this request. Please try again.',
          response.statusCode,
        );
      }
      if (result == null) {
        throw const ContactsException(
          'Contacts returned an unreadable response. Please try again.',
        );
      }
      return result;
    } on TimeoutException {
      throw const ContactsException(
        'This is taking longer than expected. Refresh before trying again.',
      );
    } on http.ClientException {
      throw const ContactsException('Check your connection and try again.');
    }
  }
}
