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
    if (response.statusCode < 200 || response.statusCode >= 300) {
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
    final session = await auth.sessions.ensureFresh();
    if (session == null || revision != auth.revision) {
      throw const BrainApiException('Please sign in again.');
    }
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${auth.backendUrl}$agentPath/$kind-files/analyze'),
          )
          ..headers.addAll({
            ...auth.deviceHeaders,
            'Authorization': 'Bearer ${session.accessToken}',
          })
          ..files.add(
            http.MultipartFile.fromBytes('files', bytes, filename: filename),
          );
    final response = await http.Response.fromStream(await client.send(request))
        .timeout(const Duration(minutes: 10));
    if (revision != auth.revision) {
      throw const BrainApiException('Your account changed.');
    }
    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode >= 400) {
      throw BrainApiException(
        data['error']?.toString() ?? 'File analysis failed.',
      );
    }
    if (data['requiresApproval'] != true ||
        data['autoSaved'] != false ||
        (data['sourceRetention'] as Map?)?['storedByKorlix'] == true) {
      throw const BrainApiException(
        'This server does not support reviewed file imports.',
      );
    }
    return data;
  }

  void dispose() => client.close();
}
