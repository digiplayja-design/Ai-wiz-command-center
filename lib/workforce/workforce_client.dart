import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

typedef WfJson = Map<String, dynamic>;
List<WfJson> wfRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
WfJson wfMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String wfId() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class WorkforceException implements Exception {
  const WorkforceException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class WorkforceClient {
  WorkforceClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null;
  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final http.Client _http;
  final bool _ownsClient;
  void Function()? onSignedOut;
  void dispose() {
    if (_ownsClient) _http.close();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    WfJson? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/workforce$path',
    ).replace(queryParameters: query);
    try {
      final req = http.Request(method, uri)
        ..headers.addAll({
          ...headersBuilder(),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        });
      if (body != null) req.body = jsonEncode(body);
      final res = await (() async => http.Response.fromStream(
        await _http.send(req),
      ))().timeout(const Duration(seconds: 40));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 401) onSignedOut?.call();
        String message =
            'Workforce could not complete this request. Please try again.';
        try {
          message =
              (jsonDecode(res.body) as Map)['error']?.toString() ?? message;
        } catch (_) {}
        throw WorkforceException(message, res.statusCode);
      }
      return res;
    } on TimeoutException {
      throw const WorkforceException(
        'Connection timed out. Refresh to check whether your action was saved before trying again.',
      );
    } on http.ClientException {
      throw const WorkforceException(
        'Check your connection, then refresh your shift.',
      );
    }
  }

  Future<WfJson> request(
    String method,
    String path, {
    WfJson? body,
    Map<String, String>? query,
  }) async {
    final res = await _send(method, path, body: body, query: query);
    try {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      throw const WorkforceException(
        'Workforce returned an unreadable response. Refresh and try again.',
      );
    }
  }

  Future<Uint8List> bytes(String path, {Map<String, String>? query}) async =>
      (await _send('GET', path, query: query)).bodyBytes;
}

String wfDuration(num seconds) {
  final n = seconds.toInt().clamp(0, 99999999);
  return '${(n ~/ 3600).toString().padLeft(2, '0')}:${((n % 3600) ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
}

String wfLabel(dynamic value) => (value ?? '')
    .toString()
    .split('_')
    .map((e) => e.isEmpty ? '' : '${e[0].toUpperCase()}${e.substring(1)}')
    .join(' ');
