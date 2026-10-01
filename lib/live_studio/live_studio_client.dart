import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String liveStudioRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class LiveStudioException implements Exception {
  const LiveStudioException(this.message, [this.status = 0, this.code]);
  final String message;
  final int status;
  final String? code;
  @override
  String toString() => message;
}

/// Authenticated, non-retrying transport. A changed login invalidates this client,
/// including responses already in flight. Reopen the screen after signing in.
class LiveStudioClient {
  LiveStudioClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null {
    _scope = _readScope();
    sessionChanges?.addListener(_checkSession);
  }

  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _ownsClient;
  String? _scope;
  bool _closed = false, _changed = false;
  VoidCallback? onAccessDenied;

  String? _readScope([Map<String, String>? headers]) {
    try {
      final token = (headers ?? headersBuilder()).entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value;
      final payload = token.split(' ').last.split('.')[1];
      final data = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
      final scope = [data['iss'], data['sub'], data['session_id']];
      if (scope.any((v) => v is! String || v.isEmpty)) return null;
      return jsonEncode(scope);
    } catch (_) {
      return null;
    }
  }

  void _checkSession() {
    if (!_closed &&
        !_changed &&
        (sessionChanges != null || _scope != null) &&
        (_scope == null || _scope != _readScope())) {
      _changed = true;
      onAccessDenied?.call();
    }
  }

  void checkAccess() => _guard();
  void _guard([Map<String, String>? headers]) {
    if (_closed) {
      throw const LiveStudioException('Reopen Live Studio to continue.');
    }
    _checkSession();
    if (!_changed &&
        (sessionChanges != null || _scope != null) &&
        headers != null &&
        _scope != _readScope(headers)) {
      _changed = true;
      onAccessDenied?.call();
    }
    if (_changed) {
      throw const LiveStudioException(
        'Sign in again and reopen Live Studio.',
        401,
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 25),
  ]) async {
    _guard();
    final uri = Uri.parse(
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/live-studio$path',
    );
    final request = http.Request(method, uri)
      ..headers.addAll({
        ...headersBuilder(),
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      });
    if (body != null) request.body = jsonEncode(body);
    final watch = Stopwatch()..start();
    try {
      _guard(request.headers);
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      _guard();
      if (response.statusCode == 401) {
        _changed = true;
        onAccessDenied?.call();
        throw const LiveStudioException(
          'Your sign-in expired. Sign in again and reopen Live Studio.',
          401,
        );
      }
      Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const LiveStudioException(
          'The response could not be read. Check show status before trying again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LiveStudioException(
          data['error']?.toString() ??
              'This request could not finish. Check your connection and show status.',
          response.statusCode,
          data['code']?.toString(),
        );
      }
      // Conservative bound for establishing a first local deadline. A screen
      // that already has an anchor must not subtract provider processing again.
      final elapsed = watch.elapsedMilliseconds;
      final episode = data['episode'];
      if (episode is Map) {
        data['episode'] = {...episode, '_responseElapsedMs': elapsed};
      }
      final episodes = data['episodes'];
      if (episodes is List) {
        data['episodes'] = episodes
            .map((e) => e is Map ? {...e, '_responseElapsedMs': elapsed} : e)
            .toList();
      }
      return data;
    } on TimeoutException {
      _guard();
      throw const LiveStudioException(
        'The request timed out. Check show status before starting again; nothing is retried automatically.',
      );
    } on http.ClientException {
      _guard();
      throw const LiveStudioException(
        'Connection lost. Reconnect and check show status before trying again.',
      );
    }
  }

  Future<Map<String, dynamic>> load() => _request('GET', '');
  Future<Uri> startYouTubeConnection() async {
    final result = await _request('POST', '/connections/youtube/start', {
      'confirmed': true,
    });
    _guard();
    final uri = Uri.tryParse(result['url']?.toString() ?? '');
    final base = Uri.tryParse(backendBaseUrl);
    if (uri == null ||
        base == null ||
        uri.scheme != 'https' ||
        uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/api/live-studio/connect/youtube/launch' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['ticket']?.length != 1 ||
        (uri.queryParameters['ticket']?.isEmpty ?? true)) {
      throw const LiveStudioException(
        'The YouTube connection link could not be verified.',
      );
    }
    return uri;
  }

  Future<void> confirmYouTubeConnection(String id) async {
    await _request('POST', '/connections/youtube/confirm', {
      'id': id,
      'confirmed': true,
    });
  }

  Future<Map<String, dynamic>> disconnectYouTube() =>
      _request('DELETE', '/connections/youtube', {'confirmed': true});

  Future<Map<String, dynamic>> save(
    Map<String, dynamic> input,
    String requestId,
  ) async => Map<String, dynamic>.from(
    (await _request('POST', '/shows', {
      ...input,
      'requestId': requestId,
    }))['show'],
  );
  Future<Map<String, dynamic>> start(
    String id,
    String mode,
    String requestId, {
    DateTime? scheduledAt,
    String? connectionId,
    int? connectionRevision,
  }) async => Map<String, dynamic>.from(
    (await _request('POST', '/shows/${Uri.encodeComponent(id)}/start', {
      'mode': mode,
      'requestId': requestId,
      'consent': true,
      'confirmed': true,
      'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
      if (mode == 'youtube') ...{
        'connectionId': connectionId,
        'connectionRevision': connectionRevision,
      },
    }))['show'],
  );
  Future<Map<String, dynamic>> control(
    String id,
    String action, {
    String? text,
  }) async => Map<String, dynamic>.from(
    (await _request('POST', '/shows/${Uri.encodeComponent(id)}/control', {
      'action': action,
      'requestId': liveStudioRequestId(),
      'confirmed': true,
      if (text != null) 'text': text,
    }))['show'],
  );
  Future<String> replay(String id) async =>
      (await _request('GET', '/shows/${Uri.encodeComponent(id)}/replay'))['url']
          as String;
  Future<void> remove(String id) async {
    await _request('DELETE', '/shows/${Uri.encodeComponent(id)}', {
      'confirmed': true,
    });
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    if (_ownsClient) _http.close();
  }
}
