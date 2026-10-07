import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class KorlixAiReportException implements Exception {
  const KorlixAiReportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sends one authenticated request to the durable reporting endpoint. In
/// particular, a missing response must never trigger alias retries: the first
/// request may already have been recorded.
Future<String> submitKorlixAiReport({
  required Uri endpoint,
  required Map<String, String> headers,
  required String reason,
  required String details,
  required String prompt,
  required String outputSummary,
  String? contentId,
  String? imageUrl,
  String? videoId,
  String? language,
  String? platform,
  String contentType = 'ai_output',
  String appArea = 'saved_history',
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final ownedClient = client == null;
  final transport = client ?? http.Client();
  try {
    final body = jsonEncode({
      'contentType': contentType,
      'appArea': appArea,
      'contentId': contentId,
      'reason': reason,
      'details': details,
      'prompt': _reportExcerpt(prompt, 6000),
      'outputSummary': _reportExcerpt(outputSummary, 12000),
      'imageUrl': ?imageUrl,
      'videoId': ?videoId,
      'language': ?language,
      'platform': ?platform,
    });
    if (utf8.encode(body).length > 28 * 1024) {
      throw const KorlixAiReportException(
        'This report is too long to send. Shorten your details and try again.',
      );
    }
    final response = await transport
        .post(
          endpoint,
          headers: Map<String, String>.from(headers)
            ..['Content-Type'] = 'application/json',
          body: body,
        )
        .timeout(timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const KorlixAiReportException(
        'Sign in again before submitting this report.',
      );
    }
    if (response.statusCode == 429) {
      throw const KorlixAiReportException(
        'Too many reports were submitted recently. Please try again later.',
      );
    }
    if (response.statusCode == 413) {
      throw const KorlixAiReportException(
        'This report is too long. Shorten your details and try again.',
      );
    }
    if (response.statusCode == 503) {
      throw const KorlixAiReportException(
        'Reporting is temporarily unavailable. Your report was not confirmed. '
        'Please try again later.',
      );
    }
    final dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw const KorlixAiReportException(_unconfirmedMessage);
    }
    final id = data is Map ? data['reportId'] : null;
    if ((response.statusCode != 200 && response.statusCode != 202) ||
        data is! Map ||
        data['ok'] != true ||
        id is! String ||
        !RegExp(r'^korlix_report_[0-9a-fA-F-]{36}$').hasMatch(id)) {
      throw const KorlixAiReportException(_unconfirmedMessage);
    }
    return id;
  } on KorlixAiReportException {
    rethrow;
  } catch (_) {
    throw const KorlixAiReportException(_unconfirmedMessage);
  } finally {
    if (ownedClient) transport.close();
  }
}

const _unconfirmedMessage =
    'We could not confirm whether your report was received. '
    'It may already be saved. Contact support@korlixdeveloper.com for help '
    'before submitting it again.';

// Bound encoded bytes, including escaped control characters and emoji, so a
// long saved response cannot exceed the server's report size limit.
String _reportExcerpt(String value, int maxBytes) {
  if (utf8.encode(jsonEncode(value)).length <= maxBytes) return value;
  const suffix = '\n[Excerpt shortened]';
  final budget = maxBytes - utf8.encode(jsonEncode(suffix)).length;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final bytes = utf8.encode(jsonEncode(character)).length - 2;
    if (used + bytes > budget) break;
    buffer.write(character);
    used += bytes;
  }
  return '$buffer$suffix';
}
