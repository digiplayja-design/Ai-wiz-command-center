import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'k135z_capture_controller.dart';
import 'k135z_spoken_player.dart';

class K135zSpokenReplies extends ChangeNotifier {
  K135zSpokenReplies({
    required this.capture,
    required this.cancelRequest,
    required this.beforeEnable,
    K135zSpokenPlayer? player,
    int Function()? milliseconds,
    bool watch = true,
  }) : player = player ?? createSpokenPlayer() {
    _now = milliseconds ?? (() => _clock.elapsedMilliseconds);
    capture.addListener(_scan);
    _watch = watch;
  }
  final K135zCaptureController capture;
  final VoidCallback cancelRequest, beforeEnable;
  final K135zSpokenPlayer player;
  final Stopwatch _clock = Stopwatch()..start();
  late final int Function() _now;
  Timer? _timer;
  late final bool _watch;
  int _epoch = 0, _seen = 0, _changedAt = 0, _beganAt = 0, _quietUntil = 0;
  bool _dead = false, enabled = false, busy = false, playing = false;
  String? _binding, _window, answer;
  final _question = <K135zTranscriptPreviewLine>[];
  static final _wake = RegExp(
    r'^(?:(?:hey|okay|ok)[,\s]+)?nova\b[\s,.:!?-]*',
    caseSensitive: false,
  );
  String message = 'Enable once, then say “Nova” followed by your question.';
  bool get canEnable =>
      !_dead &&
      !enabled &&
      !busy &&
      player.supported &&
      capture.responseBinding != null;
  String? get _currentBinding => capture.responseBinding == null
      ? null
      : jsonEncode(capture.responseBinding);
  bool _current(int epoch) =>
      !_dead &&
      epoch == _epoch &&
      _binding != null &&
      _binding == _currentBinding;

  Future<void> enable() async {
    if (!canEnable) return;
    beforeEnable();
    _binding = _currentBinding;
    final epoch = ++_epoch;
    busy = true;
    answer = null;
    message = 'Enabling Nova’s voice…';
    notifyListeners();
    try {
      final activated = player.enable(); // Preserve the direct user gesture.
      await activated;
      if (!_current(epoch)) return;
      await capture.prepareSpokenTranscript();
      if (!_current(epoch)) return;
      _window = capture.transcriptWindowId;
      if (_window == null || !player.ready)
        throw StateError('Captions unavailable');
      _seen = capture.transcriptLines.isEmpty
          ? 0
          : capture.transcriptLines.last.sequence;
      _question.clear();
      _quietUntil = 0;
      enabled = true;
      if (_watch) _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(tick()));
      capture.fastTranscript = true;
      message = 'Spoken replies on. Say “Nova” and your question. Keep this page visible.';
    } catch (_) {
      if (_current(epoch))
        stop(
          'Could not enable voice. Check listening, then tap Enable spoken replies again.',
        );
    } finally {
      if (!_dead && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _scan() {
    if (_dead) return;
    if (_binding != null && _binding != _currentBinding) {
      stop(
        'Spoken replies stopped because listening or meeting permission changed.',
      );
      return;
    }
    if (!enabled) return;
    if (!player.ready) {
      stop('Voice was interrupted. Tap Enable spoken replies to resume.');
      return;
    }
    final window = capture.transcriptWindowId;
    if (window == null) return;
    if (window != _window) {
      stop('The caption session changed. Enable spoken replies again.');
      return;
    }
    for (final line in capture.transcriptLines) {
      if (line.sequence <= _seen) continue;
      _seen = line.sequence;
      // Never queue calls heard while answering or during the echo cooldown.
      if (busy || playing || _now() < _quietUntil) continue;
      if (_wake.hasMatch(line.text.trim())) {
        _question
          ..clear()
          ..add(line);
        _beganAt = _changedAt = _now();
        message = 'I heard you. Waiting for your question to finish…';
        notifyListeners();
      } else if (_question.isNotEmpty &&
          line.speaker == _question.first.speaker &&
          line.sequence == _question.last.sequence + 1) {
        if (_question.length >= 8) {
          _question.clear();
          message = 'Please ask a shorter question, starting with “Nova”.';
          notifyListeners();
        } else {
          _question.add(line);
          _changedAt = _now();
        }
      }
    }
  }

  Future<void> tick() async {
    _scan();
    if (enabled && !busy && !playing && _quietUntil > 0 && _now() >= _quietUntil) {
      _quietUntil = 0;
      message = 'Ready for your next question. Start with “Nova”.';
      notifyListeners();
    }
    if (!enabled || busy || playing || _question.isEmpty) return;
    if (_now() - _changedAt < 2800 && _now() - _beganAt < 12000) return;
    final first = _question.first.sequence, last = _question.last.sequence;
    _question.clear();
    final epoch = _epoch,
        context = capture.responseBinding!['context'],
        window = _window;
    busy = true;
    message = 'Nova is thinking…';
    notifyListeners();
    try {
      final headers = Map<String, String>.from(capture.headers());
      headers.removeWhere(
        (k, _) =>
            ['content-type', 'x-korlix-agent-id'].contains(k.toLowerCase()),
      );
      headers['content-type'] = 'application/json';
      headers['x-korlix-agent-id'] = capture.agentId;
      final response = await capture
          .transport(
            method: 'POST',
            uri: capture.baseUri.resolve(
              '/api/k135z/zoom/workspace/spoken-reply',
            ),
            headers: headers,
            body: {
              'context': context,
              'windowId': window,
              'wakeSequence': first,
              'endSequence': last,
              'enabled': true,
            },
          )
          .timeout(const Duration(seconds: 35));
      if (!_current(epoch) || !enabled) return;
      if (utf8.encode(response.body).length > 512 * 1024)
        throw StateError('Reply too large');
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final code = decoded is Map && decoded['error'] is Map
            ? decoded['error']['code']
            : null;
        if (code == 'K135Z_RESPONSE_ALREADY_ANSWERED') {
          message =
              'That question was already handled. Say “Nova” to ask another.';
          return;
        }
        if (code == 'K135Z_RESPONSE_LIMIT') {
          stop('Spoken reply limit reached. Try again later.');
          return;
        }
        throw StateError('Reply unavailable');
      }
      final r = decoded is Map && decoded['ok'] == true
          ? decoded['reply']
          : null;
      if (r is! Map ||
          r['context'] is! Map ||
          !mapEquals(r['context'], context) ||
          r['windowId'] != window ||
          r['wakeSequence'] != first ||
          r['coverage'] != 'partial' ||
          r['text'] is! String ||
          (r['text'] as String).trim().isEmpty ||
          (r['text'] as String).length > 700 ||
          r['mimeType'] != 'audio/mpeg' ||
          r['audio'] is! String)
        throw StateError('Invalid reply');
      final audio = base64Decode(r['audio']);
      if (audio.length < 64 ||
          audio.length > 350000 ||
          !((audio[0] == 73 && audio[1] == 68 && audio[2] == 51) ||
              (audio[0] == 255 && (audio[1] & 224) == 224)))
        throw StateError('Invalid audio');
      answer = r['text'];
      playing = true;
      message = 'Nova is speaking…';
      notifyListeners();
      await player.play(audio);
      if (_current(epoch) && enabled)
        message = 'Reply finished. Ready for another question in a few seconds…';
    } catch (_) {
      if (_current(epoch))
        stop('Reply interrupted. Enable spoken replies, then ask again.');
    } finally {
      if (!_dead && epoch == _epoch) {
        busy = false;
        playing = false;
        _quietUntil = _now() + 4000;
        _scan();
        notifyListeners();
      }
    }
  }

  void stop([String feedback = 'Spoken replies off. Nova is silent.']) {
    if (_dead) return;
    _timer?.cancel(); _timer = null;
    final wasActive = enabled || busy || playing;
    _epoch++;
    enabled = false;
    busy = false;
    playing = false;
    capture.fastTranscript = false;
    answer = null;
    _binding = null;
    _window = null;
    _question.clear();
    player.stop();
    if (wasActive) cancelRequest();
    message = feedback;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_dead) return;
    capture.removeListener(_scan);
    _timer?.cancel();
    stop();
    _dead = true;
    _clock.stop();
    super.dispose();
  }
}
