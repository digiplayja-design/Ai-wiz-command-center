import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// KORLIX_LIVE_CONVO_BUILD129_USAGE_GUARD_BEGIN
typedef KorlixLiveConvoLimitCallback = Future<void> Function(String message);

class KorlixLiveConvoUsageGuard {
  Timer? _timer;
  Uri? _usageUri;
  Map<String, String> _headers = <String, String>{};
  KorlixLiveConvoLimitCallback? _onLimitReached;
  String? _sessionId;
  DateTime? _startedAt;
  int _maxSessionSeconds = 0;
  int _maxResponses = 0;
  int _responseCount = 0;
  int _totalTokens = 0;
  int _inputTokens = 0;
  int _outputTokens = 0;
  int _inputAudioTokens = 0;
  int _outputAudioTokens = 0;
  int _imageTokens = 0;
  int _transcriptionTokens = 0;
  int _lastHeartbeatSecond = -1;
  int _consecutiveReportFailures = 0;
  bool _ended = true;
  bool _limitFired = false;

  String? get sessionId => _sessionId;

  int get elapsedSeconds {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return 0;
    }
    return DateTime.now()
        .difference(startedAt)
        .inSeconds
        .clamp(0, 86400)
        .toInt();
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String && value.trimLeft().startsWith('{')) {
      try {
        return _map(jsonDecode(value));
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  String? _header(http.Response response, String name) {
    final lowerName = name.toLowerCase();
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == lowerName) {
        return entry.value;
      }
    }
    return null;
  }

  String _firstNonEmpty(Iterable<Object?> values, String fallback) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return fallback;
  }

  Future<void> beginFromSessionResponse(
    http.Response response, {
    required KorlixLiveConvoLimitCallback onLimitReached,
  }) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    if (_sessionId != null && !_ended) {
      await end(reason: 'replaced_by_new_session');
    }

    _timer?.cancel();
    _timer = null;
    _onLimitReached = onLimitReached;
    _sessionId = _header(response, 'x-korlix-live-convo-session-id')?.trim();
    _maxSessionSeconds = _readInt(
      _header(response, 'x-korlix-live-convo-max-seconds'),
    );
    _maxResponses = _readInt(
      _header(response, 'x-korlix-live-convo-max-responses'),
    );
    _responseCount = 0;
    _totalTokens = 0;
    _inputTokens = 0;
    _outputTokens = 0;
    _inputAudioTokens = 0;
    _outputAudioTokens = 0;
    _imageTokens = 0;
    _transcriptionTokens = 0;
    _lastHeartbeatSecond = -1;
    _consecutiveReportFailures = 0;
    _ended = false;
    _limitFired = false;
    _startedAt = DateTime.now();

    final request = response.request;
    if (_sessionId == null || _sessionId!.isEmpty || request == null) {
      _ended = true;
      throw StateError(
        'LIVE CONVO usage controls are not active on the server. Deploy the Build 129 backend before testing this app build.',
      );
    }

    _usageUri = Uri.parse(
      '${request.url.scheme}://${request.url.authority}/api/live-convo/usage',
    );
    _headers = Map<String, String>.from(request.headers)
      ..removeWhere((key, value) {
        final lower = key.toLowerCase();
        return lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'accept';
      })
      ..['Content-Type'] = 'application/json'
      ..['Accept'] = 'application/json';

    if (_maxSessionSeconds <= 0 || _maxResponses <= 0) {
      _ended = true;
      throw StateError(
        'LIVE CONVO returned invalid fair-use limits. Update the backend configuration before testing.',
      );
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tick());
    });

    await _report();
  }

  Future<void> observeServerEvent(Object? rawEvent) async {
    if (_ended || _sessionId == null) {
      return;
    }

    final event = _map(rawEvent);
    final type = event['type']?.toString() ?? '';

    if (type == 'response.done') {
      _responseCount += 1;

      final response = _map(event['response']);
      final responseUsage = _map(response['usage']);
      final usage = responseUsage.isNotEmpty
          ? responseUsage
          : _map(event['usage']);
      final inputDetails = _map(usage['input_token_details']);
      final outputDetails = _map(usage['output_token_details']);

      _totalTokens += _readInt(usage['total_tokens']);
      _inputTokens += _readInt(usage['input_tokens']);
      _outputTokens += _readInt(usage['output_tokens']);
      _inputAudioTokens += _readInt(inputDetails['audio_tokens']);
      _outputAudioTokens += _readInt(outputDetails['audio_tokens']);
      _imageTokens += _readInt(inputDetails['image_tokens']);

      await _report();

      if (_responseCount >= _maxResponses) {
        await _fireLimit(
          'This LIVE CONVO session reached its response limit. Start a new session later if your monthly allowance permits.',
        );
      }
      return;
    }

    if (type == 'conversation.item.input_audio_transcription.completed') {
      final usage = _map(event['usage']);
      _transcriptionTokens += _readInt(usage['total_tokens']);
      await _report();
    }
  }

  Future<void> _tick() async {
    if (_ended || _sessionId == null) {
      return;
    }

    final seconds = elapsedSeconds;
    if (seconds >= _maxSessionSeconds) {
      await _fireLimit(
        'This LIVE CONVO session reached its time limit and has ended.',
      );
      return;
    }

    if (seconds > 0 && seconds % 15 == 0 && seconds != _lastHeartbeatSecond) {
      _lastHeartbeatSecond = seconds;
      await _report();
    }
  }

  Future<void> _fireLimit(String message) async {
    if (_limitFired) {
      return;
    }

    _limitFired = true;
    await end(reason: 'fair_use_limit_reached');
    await _onLimitReached?.call(message);
  }

  Future<void> _report({bool finalReport = false, String? endReason}) async {
    final usageUri = _usageUri;
    final sessionId = _sessionId;
    if (usageUri == null || sessionId == null || sessionId.isEmpty) {
      return;
    }

    try {
      final response = await http
          .post(
            usageUri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'sessionId': sessionId,
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
            }),
          )
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> data = <String, dynamic>{};
      try {
        data = _map(jsonDecode(response.body));
      } catch (_) {
        data = <String, dynamic>{};
      }

      if (response.statusCode >= 200 && response.statusCode < 500) {
        _consecutiveReportFailures = 0;
      }

      if (!finalReport &&
          (response.statusCode == 429 ||
              data['allowed'] == false ||
              data['limitReached'] == true)) {
        final usage = _map(data['usage']);
        final message = _firstNonEmpty(<Object?>[
          data['error'],
          usage['message'],
        ], 'Your LIVE CONVO allowance has been reached.');
        await _fireLimit(message);
        return;
      }

      if (!finalReport && response.statusCode >= 500) {
        throw StateError('LIVE CONVO usage meter unavailable.');
      }
    } catch (_) {
      _consecutiveReportFailures += 1;
      if (!finalReport && _consecutiveReportFailures >= 3) {
        await _fireLimit(
          'LIVE CONVO ended because the usage meter could not be reached safely. Please try again later.',
        );
      }
    }
  }

  Future<void> end({String reason = 'user_ended'}) async {
    if (_ended) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    _ended = true;
    _timer?.cancel();
    _timer = null;
    await _report(finalReport: true, endReason: reason);
  }
}

// KORLIX_LIVE_CONVO_BUILD129_USAGE_GUARD_END
