import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String podRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class PodException implements Exception {
  const PodException(this.message, [this.status = 0, this.code]);
  final String message;
  final int status;
  final String? code;
  @override
  String toString() => message;
}

/// Authenticated, non-retrying transport. A changed login invalidates this client,
/// including responses already in flight. Reopen the screen after signing in.
class PodClient {
  PodClient({
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
      throw const PodException('Reopen The Pod and You to continue.');
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
      throw const PodException(
        'Sign in again and reopen The Pod and You.',
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
      '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/pod$path',
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
        throw const PodException(
          'Your sign-in expired. Sign in again and reopen The Pod and You.',
          401,
        );
      }
      Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const PodException(
          'The response could not be read. Check episode status before trying again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PodException(
          data['error']?.toString() ??
              'This request could not finish. Check your connection and episode status.',
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
      throw const PodException(
        'The request timed out. Playback is paused. Check episode status before choosing Resume; nothing is retried automatically.',
      );
    } on http.ClientException {
      _guard();
      throw const PodException(
        'Connection lost. Playback is paused. Reconnect and check episode status to continue.',
      );
    }
  }

  Map<String, dynamic> _episode(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['state'] is! String ||
        value['version'] is! num) {
      throw const PodException(
        'Episode status could not be confirmed. Refresh to check it before continuing.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> load() => _request('GET', '');
  Future<Map<String, dynamic>> create({
    required String requestId,
    required String category,
    required String topic,
    required int durationSeconds,
    required int hostCount,
    required String style,
  }) async => _episode(
    (await _request('POST', '/episodes', {
      'requestId': requestId,
      'category': category,
      'topic': topic,
      'durationSeconds': durationSeconds,
      'hostCount': hostCount,
      'style': style,
      'consent': true,
    }))['episode'],
  );
  Future<Map<String, dynamic>> episode(String id) async => _episode(
    (await _request('GET', '/episodes/${Uri.encodeComponent(id)}'))['episode'],
  );
  Future<Map<String, dynamic>> next(
    String id, {
    required String requestId,
    required int version,
  }) async {
    final result = await _request(
      'POST',
      '/episodes/${Uri.encodeComponent(id)}/next',
      {'requestId': requestId, 'version': version},
      const Duration(seconds: 225),
    );
    result['episode'] = _episode(result['episode']);
    return result;
  }

  /// Prepares at most one future turn without publishing it to the transcript.
  /// The request ID also identifies that prepared turn for playback.
  Future<Map<String, dynamic>> prepare(
    String id, {
    required String requestId,
    required int version,
  }) async {
    final result = await _request(
      'POST',
      '/episodes/${Uri.encodeComponent(id)}/prepare',
      {'requestId': requestId, 'version': version},
      const Duration(seconds: 225),
    );
    result['episode'] = _episode(result['episode']);
    return result;
  }

  /// Claims already generated audio. A missing cache entry never regenerates
  /// speech and this transport never retries either endpoint automatically.
  Future<Map<String, dynamic>> playPrepared(
    String id, {
    required String requestId,
    required int version,
  }) async {
    final result = await _request(
      'POST',
      '/episodes/${Uri.encodeComponent(id)}/play-prepared',
      {'requestId': requestId, 'version': version},
    );
    result['episode'] = _episode(result['episode']);
    return result;
  }

  Future<Map<String, dynamic>> control(String id, String action) async =>
      _episode(
        (await _request(
          'POST',
          '/episodes/${Uri.encodeComponent(id)}/control',
          {'action': action},
          action == 'heartbeat'
              ? const Duration(seconds: 8)
              : const Duration(seconds: 25),
        ))['episode'],
      );
  Future<Map<String, dynamic>> smallTalk(String id, String clip) => _request(
    'POST',
    '/episodes/${Uri.encodeComponent(id)}/small-talk/${Uri.encodeComponent(clip)}',
    {},
    const Duration(seconds: 40),
  );
  Future<Map<String, dynamic>> contribute(
    String id,
    String text, {
    required String requestId,
  }) async => _episode(
    (await _request(
      'POST',
      '/episodes/${Uri.encodeComponent(id)}/contributions',
      {'requestId': requestId, 'text': text},
    ))['episode'],
  );
  Future<String> transcribe(
    String id,
    Uint8List wav, {
    required String requestId,
  }) async {
    if (wav.lengthInBytes > 1440044 || wav.isEmpty) {
      throw const PodException('Record a contribution of 30 seconds or less.');
    }
    final result = await _request(
      'POST',
      '/episodes/${Uri.encodeComponent(id)}/transcribe',
      {'requestId': requestId, 'audioBase64': base64Encode(wav)},
      const Duration(seconds: 70),
    );
    if (result['text'] is! String) {
      throw const PodException(
        'The recording could not be transcribed. You can type your contribution instead.',
      );
    }
    return result['text'] as String;
  }

  Future<void> remove(String id) async {
    await _request('DELETE', '/episodes/${Uri.encodeComponent(id)}', {
      'confirmed': true,
    });
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    onAccessDenied = null;
    if (_ownsClient) _http.close();
  }
}

/// Only public HTTPS citations are navigable. Literal IPs, user info, local
/// hostnames and ambiguous host syntax are excluded even if returned by a server.
Uri? podPublicSourceUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!RegExp(
        r'^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?)+$',
      ).hasMatch(host) ||
      !RegExp(
        r'^[a-z]{2,63}$|^xn--[a-z0-9-]+$',
      ).hasMatch(host.split('.').last) ||
      RegExp(r'^\d+(?:\.\d+)*$').hasMatch(host) ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.test') ||
      host.endsWith('.invalid') ||
      host.endsWith('.example') ||
      host.endsWith('.lan') ||
      host.endsWith('.home') ||
      host.endsWith('.corp') ||
      host.endsWith('.onion')) {
    return null;
  }
  return uri;
}
