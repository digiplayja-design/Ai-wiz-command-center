import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef KorlixLiveConvoLimitCallback = Future<void> Function(String message);
typedef BrainUsageReporter = Future<http.Response> Function(
  Map<String, dynamic> body,
);

/// One cumulative, authenticated report at a time. The server owns allowances;
/// this guard keeps the session alive and closes local audio on a real limit.
class KorlixLiveConvoUsageGuard {
  KorlixLiveConvoUsageGuard({
    this.reportUsage,
    DateTime Function()? now,
    this.scheduleHeartbeat = true,
  }) : _now = now ?? DateTime.now;

  final BrainUsageReporter? reportUsage;
  final DateTime Function() _now;
  final bool scheduleHeartbeat;
  Timer? _timer;
  Uri? _usageUri;
  Map<String, String> _headers = {};
  KorlixLiveConvoLimitCallback? _onLimitReached;
  String? _sessionId;
  DateTime? _startedAt, _endedAt, _lastReportAt;
  int _maxSessionSeconds = 0, _maxResponses = 0, _responseCount = 0;
  final _brainTurns = <String>{}, _responseIds = <String>{};
  int _totalTokens = 0, _inputTokens = 0, _outputTokens = 0;
  int _inputAudioTokens = 0, _outputAudioTokens = 0;
  int _imageTokens = 0, _transcriptionTokens = 0;
  int _consecutiveReportFailures = 0;
  bool _ended = true, _limitFired = false, _endConfirmed = true;
  Future<void>? _reporting, _ending;

  String? get sessionId => _sessionId;
  bool get endConfirmed => _endConfirmed;
  int get elapsedSeconds => _startedAt == null
      ? 0
      : (_endedAt ?? _now())
            .difference(_startedAt!)
            .inSeconds
            .clamp(0, 86400)
            .toInt();

  int _readInt(Object? value) => value is num
      ? value.toInt().clamp(0, 2000000000).toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;

  Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : <String, dynamic>{};

  String? _header(http.Response response, String name) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Future<void> beginFromSessionResponse(
    http.Response response, {
    required KorlixLiveConvoLimitCallback onLimitReached,
  }) async {
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    if (!_ended) await end(reason: 'replaced_by_new_session');
    _timer?.cancel();
    _onLimitReached = onLimitReached;
    _sessionId = _header(response, 'x-korlix-live-convo-session-id')?.trim();
    _maxSessionSeconds = _readInt(
      _header(response, 'x-korlix-live-convo-max-seconds'),
    );
    _maxResponses = _readInt(
      _header(response, 'x-korlix-live-convo-max-responses'),
    );
    _responseCount = 0;
    _brainTurns.clear();
    _responseIds.clear();
    _totalTokens = _inputTokens = _outputTokens = 0;
    _inputAudioTokens = _outputAudioTokens = 0;
    _imageTokens = _transcriptionTokens = 0;
    _consecutiveReportFailures = 0;
    _limitFired = false;
    _startedAt = _now();
    _endedAt = _lastReportAt = null;
    _endConfirmed = false;
    final request = response.request;
    if (_sessionId == null || _sessionId!.isEmpty ||
        (request == null && reportUsage == null)) {
      _ended = true;
      throw StateError('Voice usage controls could not be confirmed. Reconnect Rici.');
    }
    if (request != null) {
      _usageUri = request.url.replace(path: '/api/live-convo/usage', query: null);
      _headers = Map<String, String>.from(request.headers)
        ..removeWhere((key, _) => const {
          'content-type', 'content-length', 'accept',
        }.contains(key.toLowerCase()))
        ..['Content-Type'] = 'application/json'
        ..['Accept'] = 'application/json';
    }
    _ended = false;
    if (_maxSessionSeconds <= 0 || _maxResponses <= 0) {
      await end(reason: 'invalid_session_limits');
      throw StateError('Voice limits could not be confirmed. Reconnect Rici.');
    }
    if (scheduleHeartbeat) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(heartbeat());
      });
    }
    await _report();
  }

  Future<void> observeServerEvent(Object? rawEvent) async {
    if (_ended || _sessionId == null) return;
    final event = _map(rawEvent);
    if (event['type'] == 'response.done') {
      final response = _map(event['response']);
      final id = response['id']?.toString();
      if (id != null && !_responseIds.add(id)) return;
      final turn = _map(response['metadata'])['brain_turn']?.toString();
      if (turn == null || _brainTurns.add(turn)) _responseCount++;
      final usage = _map(response['usage'] ?? event['usage']);
      _totalTokens += _readInt(usage['total_tokens']);
      _inputTokens += _readInt(usage['input_tokens']);
      _outputTokens += _readInt(usage['output_tokens']);
      _inputAudioTokens += _readInt(_map(usage['input_token_details'])['audio_tokens']);
      _outputAudioTokens += _readInt(_map(usage['output_token_details'])['audio_tokens']);
      _imageTokens += _readInt(_map(usage['input_token_details'])['image_tokens']);
      await _report();
      if (!_ended && _responseCount >= _maxResponses) {
        await _fireLimit('This conversation reached its response limit. Start a new conversation when your allowance permits.');
      }
    } else if (event['type'] == 'conversation.item.input_audio_transcription.completed') {
      _transcriptionTokens += _readInt(_map(event['usage'])['total_tokens']);
      await _report();
    }
  }

  /// Uses elapsed time instead of an exact modulo tick, so a delayed timer or
  /// a foreground transition cannot skip a heartbeat for another 15 seconds.
  Future<void> heartbeat({bool force = false}) async {
    if (_ended || _limitFired || _sessionId == null) return;
    if (elapsedSeconds >= _maxSessionSeconds) {
      await _fireLimit('This conversation reached its time limit and has ended.');
    } else if (force || _lastReportAt == null ||
        _now().difference(_lastReportAt!) >= const Duration(seconds: 15)) {
      await _report();
    }
  }

  Future<void> _fireLimit(String message) async {
    if (_limitFired || _ended) return;
    _limitFired = true;
    _timer?.cancel();
    // The callback closes local media immediately. Never leave a microphone
    // running while waiting for a final HTTP request to finish.
    try {
      await _onLimitReached?.call(message);
    } finally {
      await end(reason: 'fair_use_limit_reached');
    }
  }

  Map<String, dynamic> _body({bool finalReport = false, String? endReason}) => {
    'sessionId': _sessionId,
    'durationSeconds': elapsedSeconds,
    'responseCount': _responseCount,
    'totalTokens': _totalTokens,
    'inputTokens': _inputTokens,
    'outputTokens': _outputTokens,
    'inputAudioTokens': _inputAudioTokens,
    'outputAudioTokens': _outputAudioTokens,
    'imageTokens': _imageTokens,
    'transcriptionTokens': _transcriptionTokens,
    'ended': finalReport,
    'endReason': endReason,
  };

  Future<http.Response> _send(Map<String, dynamic> body) {
    final send = reportUsage;
    if (send != null) return send(body).timeout(const Duration(seconds: 12));
    return http.post(_usageUri!, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
  }

  Map<String, dynamic> _data(http.Response response) {
    try { return _map(jsonDecode(response.body)); } catch (_) { return {}; }
  }

  Future<void> _report() {
    if (_ended || _limitFired || _sessionId == null) return Future.value();
    if (_reporting != null) return _reporting!;
    final completion = Completer<void>();
    _reporting = completion.future;
    _lastReportAt = _now();
    unawaited(() async {
      String? limit;
      try {
        final response = await _send(_body());
        final data = _data(response);
        if ({401, 402, 403, 429}.contains(response.statusCode) ||
            data['allowed'] == false || data['limitReached'] == true) {
          final message = data['error'] ?? _map(data['usage'])['message'];
          limit = message is String && message.trim().isNotEmpty
              ? message
              : 'Your Live Conversation allowance is unavailable. Check Plan & AI GAS.';
        } else if (response.statusCode < 200 || response.statusCode >= 300 ||
            data['ok'] != true || data['allowed'] != true) {
          throw StateError('Usage report failed.');
        } else {
          _consecutiveReportFailures = 0;
        }
      } catch (_) {
        _consecutiveReportFailures++;
        if (_consecutiveReportFailures >= 3) {
          limit = 'Voice paused because the minute balance could not be reached. Check your connection and tap Resume.';
        }
      }
      _reporting = null;
      try {
        if (limit != null && !_ended) await _fireLimit(limit);
      } catch (_) {
        // Media cleanup failures cannot leave an unhandled background future.
      } finally {
        completion.complete();
      }
    }());
    return completion.future;
  }

  /// Idempotent and retryable. Resume waits for this acknowledgment before
  /// allocating another billable session. No heartbeat remains active on Pause.
  Future<void> end({String reason = 'user_ended'}) {
    if (_ending != null) return _ending!;
    if (_endConfirmed || _sessionId == null || _sessionId!.isEmpty) {
      _timer?.cancel();
      return Future.value();
    }
    _ended = true;
    _endedAt ??= _now();
    _timer?.cancel();
    _timer = null;
    final pending = _reporting;
    final completion = Completer<void>();
    _ending = completion.future;
    unawaited(() async {
      try {
        await pending;
        for (var attempt = 0; attempt < 2 && !_endConfirmed; attempt++) {
          try {
            final response = await _send(_body(finalReport: true, endReason: reason));
            final data = _data(response);
            final usage = _map(data['usage']);
            _endConfirmed = (response.statusCode >= 200 && response.statusCode < 300 && data['ok'] == true) ||
                (response.statusCode == 429 && usage['sessionId'] == _sessionId &&
                    (usage['limitReached'] == true || usage['allowed'] == false));
            if (!_endConfirmed && response.statusCode < 500) break;
          } catch (_) { /* A final report is idempotent; retry once. */ }
        }
      } finally {
        _ending = null;
        completion.complete();
      }
    }());
    return completion.future;
  }
}
