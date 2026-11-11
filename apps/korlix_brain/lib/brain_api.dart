import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'brain_auth.dart';

class BrainApiException implements Exception {
  const BrainApiException(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// Every request is authenticated natively. No token crosses the WebView bridge.
class BrainApi {
  BrainApi(this.auth, {http.Client? client}) : client = client ?? http.Client();
  final BrainAuthController auth;
  final http.Client client;
  static const agentPath = '/api/live-convo/agents/general';

  Future<http.Response> send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 40),
    bool acceptErrors = false,
  }) async {
    final revision = auth.revision;
    var session = await auth.sessions.ensureFresh();
    if (session == null || revision != auth.revision) {
      throw const BrainApiException('Please sign in again.', status: 401);
    }
    Future<http.Response> attempt(String token) async {
      final request = http.Request(
        method,
        Uri.parse('${auth.backendUrl}$path'),
      );
      request.headers.addAll({
        ...auth.deviceHeaders,
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...headers,
      });
      if (body != null) request.body = body is String ? body : jsonEncode(body);
      return http.Response.fromStream(
        await client.send(request).timeout(timeout),
      );
    }

    var response = await attempt(session.accessToken).timeout(timeout);
    // A rejected access token means the mutation was not authorized. Retry only
    // that case; never replay writes on timeout or an ambiguous server error.
    if (response.statusCode == 401 && revision == auth.revision) {
      session = await auth.sessions.ensureFresh(
        force: true,
        rejectedAccessToken: session.accessToken,
      );
      if (session != null && revision == auth.revision) {
        response = await attempt(session.accessToken).timeout(timeout);
      }
    }
    if (revision != auth.revision || auth.session == null) {
      throw const BrainApiException(
        'Your account changed. Please reopen this screen.',
      );
    }
    if (!acceptErrors && (response.statusCode < 200 || response.statusCode >= 300)) {
      String message =
          'KORLIX could not complete the request (${response.statusCode}).';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] is String) message = data['error'];
      } catch (_) {
        /* Do not show HTML or server internals. */
      }
      throw BrainApiException(message, status: response.statusCode);
    }
    return response;
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, [
    Object? body,
  ]) async {
    final response = await send(method, path, body: body);
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const BrainApiException(
        'KORLIX returned an unreadable response. Refresh before trying again.',
      );
    }
  }

  /// Stream only the user's authenticated voice turn. Retry solely a rejected
  /// token, never a partial stream or ambiguous mutation.
  Future<Map<String, dynamic>> voiceTurn(
    Map<String, dynamic> body,
    void Function(Map<String, dynamic>) onDelta,
  ) async {
    final revision = auth.revision;
    void check() {
      if (revision != auth.revision || auth.session == null) {
        throw const BrainApiException('Your account changed. Reconnect Rici.');
      }
    }

    var session = await auth.sessions.ensureFresh();
    check();
    if (session == null) throw const BrainApiException('Please sign in again.');
    Future<http.StreamedResponse> attempt(String token) {
      final request =
          http.Request(
              'POST',
              Uri.parse('${auth.backendUrl}/api/brain-voice/turn'),
            )
            ..headers.addAll({
              ...auth.deviceHeaders,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/x-ndjson',
            })
            ..body = jsonEncode(body);
      return client.send(request).timeout(const Duration(seconds: 40));
    }

    var response = await attempt(session.accessToken);
    if (response.statusCode == 401 && revision == auth.revision) {
      await response.stream.drain<void>();
      session = await auth.sessions.ensureFresh(
        force: true,
        rejectedAccessToken: session.accessToken,
      );
      check();
      if (session == null) {
        throw const BrainApiException('Please sign in again.');
      }
      response = await attempt(session.accessToken);
    }
    check();
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw BrainApiException(
        'Rici could not complete that turn (${response.statusCode}).',
        status: response.statusCode,
      );
    }
    if (!(response.headers['content-type'] ?? '').contains(
      'application/x-ndjson',
    )) {
      // Backwards-compatible response from a server still draining a rollout.
      final result = await http.Response.fromStream(response)
          .timeout(const Duration(seconds: 155));
      check();
      return Map<String, dynamic>.from(jsonDecode(result.body) as Map);
    }
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 155))) {
      check();
      if (line.isEmpty) continue;
      final event = Map<String, dynamic>.from(jsonDecode(line) as Map);
      if (event['type'] == 'answer.delta') {
        onDelta(event);
      } else if (event['type'] == 'turn.completed') {
        return event;
      } else if (event['type'] == 'turn.error') {
        throw BrainApiException(
          event['error']?.toString() ?? 'Rici could not finish that turn.',
        );
      }
    }
    throw const BrainApiException(
      'The voice reply was interrupted. Please try again.',
    );
  }

  Future<Map<String, dynamic>> analyze(
    String kind,
    String filename,
    Uint8List bytes,
  ) async {
    if (!{'memory', 'training'}.contains(kind) ||
        bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024) {
      throw const BrainApiException(
        'Choose a nonempty file smaller than 10 MB.',
      );
    }
    final revision = auth.revision;
    void checkAccount() {
      if (revision != auth.revision || auth.session == null) {
        throw const BrainApiException('Your account changed. Choose the document again.');
      }
    }
    var session = await auth.sessions.ensureFresh();
    if (session == null || revision != auth.revision) {
      throw const BrainApiException('Please sign in again.', status: 401);
    }
    Future<http.Response> attempt(String token) async {
      checkAccount();
      final request = http.MultipartRequest('POST',
        Uri.parse('${auth.backendUrl}$agentPath/$kind-files/analyze'))
        ..headers.addAll({...auth.deviceHeaders,
          'Authorization': 'Bearer $token', 'Accept': 'application/json'})
        ..files.add(http.MultipartFile.fromBytes('files', bytes, filename: filename));
      try {
        return await client.send(request).then(http.Response.fromStream)
            .timeout(const Duration(minutes: 10));
      } on TimeoutException {
        checkAccount();
        throw const BrainApiException(
          'Document analysis timed out. The preview was not confirmed. Check your connection before trying again.',
        );
      } on http.ClientException {
        checkAccount();
        throw const BrainApiException(
          'The document connection was interrupted. The preview was not confirmed. Check your connection before trying again.',
        );
      }
    }
    var response = await attempt(session.accessToken);
    if (response.statusCode == 401 && revision == auth.revision) {
      session = await auth.sessions.ensureFresh(force: true,
        rejectedAccessToken: session.accessToken);
      checkAccount();
      if (session == null) throw const BrainApiException('Please sign in again.', status: 401);
      response = await attempt(session.accessToken);
    }
    checkAccount();
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw BrainApiException('Document analysis returned an unreadable response. Please try again.',
        status: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['error'];
      throw BrainApiException(message is String && message.length <= 1200
          ? message : 'Document analysis could not finish. Please try again.', status: response.statusCode);
    }
    final retention = data['sourceRetention'];
    if (data['requiresApproval'] != true ||
        data['autoSaved'] != false ||
        retention is! Map || retention['storedByKorlix'] != false) {
      throw const BrainApiException(
        'This server does not support reviewed file imports.',
      );
    }
    return data;
  }

  void dispose() => client.close();
}
