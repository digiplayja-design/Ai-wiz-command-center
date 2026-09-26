import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'k135z_capture_controller.dart';
import 'k135z_spoken_player.dart';
import 'k135z_waiting_voice.dart';
import 'k135z_remember_memory.dart';
import '../live_convo/k136s_learning_panel.dart';

class K135zSpokenReplies extends ChangeNotifier {
  K135zSpokenReplies({
    required this.capture,
    required this.cancelRequest,
    required this.beforeEnable,
    K135zSpokenPlayer? player,
    Future<List<K135zWaitingClip>> Function()? loadWaitingVoice,
    K136sLearningApiBase? learningApi,
    int Function()? milliseconds,
    bool watch = true,
  }) : player = player ?? createSpokenPlayer() {
    _loadWaitingVoice = loadWaitingVoice ?? (() => loadK135zWaitingVoice(capture));
    _now = milliseconds ?? (() => _clock.elapsedMilliseconds);
    memory = K135zRememberMemory(agentId:capture.agentId,
      currentBinding:() => enabled && !suspended ? _currentBinding : null,
      api:learningApi ?? K136sLearningApi(baseUrl:capture.baseUri.resolve('/').toString(),
        headersBuilder:() => capture.headers()));
    memory.addListener(_memoryChanged);
    capture.addListener(_scan);
    _watch = watch;
  }
  final K135zCaptureController capture;
  final VoidCallback cancelRequest, beforeEnable;
  final K135zSpokenPlayer player;
  late final Future<List<K135zWaitingClip>> Function() _loadWaitingVoice;
  List<K135zWaitingClip> _waitingClips = const [];
  int? _replyBeganAt;
  int? _preparingWaitingEpoch;
  int _waitingStage = 0, _waitingEpoch = 0;
  bool smallTalk = true, waitingSpeaking = false, starting = false;
  late final K135zRememberMemory memory;
  void _memoryChanged() {
    if (_dead) return;
    if (memory.visible) message = memory.message;
    if (memory.phase == 'saved') memoryStatus = null;
    notifyListeners();
  }
  final Stopwatch _clock = Stopwatch()..start();
  late final int Function() _now;
  Timer? _timer;
  late final bool _watch;
  int _epoch = 0, _seen = 0, _changedAt = 0, _beganAt = 0, _quietUntil = 0;
  bool _dead = false, enabled = false, busy = false, playing = false;
  String? _binding, _window, answer;
  String? memoryStatus;
  bool suspended = false, needsAudioTap = false;
  Map<String, dynamic>? _returnContext;
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

  Future<void> enable() => _enable();
  Future<void> startWithListening(Future<void> Function() startListening) =>
      _enable(startListening: startListening);

  Future<void> _enable({Future<void> Function()? startListening}) async {
    if (startListening == null ? !canEnable :
        _dead || busy || !player.supported || !capture.usable) return;
    beforeEnable();
    _binding = startListening == null ? _currentBinding : null;
    String? activationBinding = _binding;
    final epoch = ++_epoch;
    busy = true;
    starting = true;
    answer = null;
    memoryStatus = null;
    message = startListening == null ? 'Enabling Nova’s voice…' : 'Starting Nova…';
    notifyListeners();
    try {
      final activated = player.enable(); // Preserve the direct user gesture.
      // Begin audio activation and listening together from the same explicit tap.
      final listening = () async {
        if (startListening == null) return;
        await startListening();
        if (_dead || epoch != _epoch) return;
        activationBinding = _currentBinding;
        _binding = activationBinding;
      }();
      await Future.wait<void>([activated, listening]);
      if (_dead || epoch != _epoch) return;
      if (!capture.usable || activationBinding == null || activationBinding != _currentBinding) {
        throw StateError('Listening unavailable');
      }
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
      if (_watch) _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => unawaited(tick()));
      capture.fastTranscript = true;
      message = 'Spoken replies on. Say “Nova” and your question.';
      if (smallTalk) unawaited(_prepareWaitingVoice(epoch));
    } catch (_) {
      if (!_dead && epoch == _epoch)
        stop(
          'Nova’s voice could not start. Check listening, then tap Start Nova or Enable spoken replies again.',
        );
    } finally {
      if (!_dead && epoch == _epoch) {
        busy = false;
        starting = false;
        notifyListeners();
      }
    }
  }

  Future<void> _prepareWaitingVoice(int epoch) async {
    if (_preparingWaitingEpoch == epoch) return;
    _preparingWaitingEpoch = epoch;
    try {
      final clips = await _loadWaitingVoice();
      if (_current(epoch) && enabled) _waitingClips = clips;
    } catch (_) { /* Optional preparation never interrupts the actual answer. */ }
    finally { if (_preparingWaitingEpoch == epoch) _preparingWaitingEpoch = null; }
  }

  void setSmallTalk(bool value) {
    if (_dead || value == smallTalk) return;
    smallTalk = value;
    if (!value) _interruptWaiting();
    if (value && enabled && !suspended && _waitingClips.isEmpty) unawaited(_prepareWaitingVoice(_epoch));
    notifyListeners();
  }

  void _interruptWaiting() {
    _waitingEpoch++;
    if (waitingSpeaking) player.interrupt();
    waitingSpeaking = false;
  }

  void _maybeSpeakWaiting() {
    if (!enabled || suspended || !busy || playing || !smallTalk ||
        waitingSpeaking || _replyBeganAt == null || _waitingClips.length != 2 ||
        _waitingStage >= 2) return;
    final elapsed = _now() - _replyBeganAt!;
    if (elapsed < (_waitingStage == 0 ? 1000 : 9000)) return;
    // If preparation was slow, skip the initial acknowledgment instead of
    // delivering two pieces of chatter back to back.
    if (_waitingStage == 0 && elapsed >= 6000) { _waitingStage = 1; return; }
    final clip = _waitingClips[_waitingStage++];
    final epoch = _epoch, waitingEpoch = ++_waitingEpoch;
    waitingSpeaking = true;
    message = clip.text;
    notifyListeners();
    unawaited(() async {
      if (!_current(epoch) || waitingEpoch != _waitingEpoch) return;
      try { await player.play(clip.audio); } catch (_) { /* The answer still has priority. */ }
      if (_current(epoch) && waitingEpoch == _waitingEpoch) {
        waitingSpeaking = false;
        message = 'Nova is preparing your answer…';
        notifyListeners();
      }
    }());
  }

  // Keep the opt-in and unlocked AudioContext across a window switch. Do not
  // queue questions heard while away or replay an interrupted answer on return.
  void leavePage() {
    if (_dead) return;
    if (memory.active) memory.cancel();
    if (suspended) {
      // A second switch while automatic audio activation is in flight cancels
      // that activation, but keeps the original session opt-in for the next return.
      _epoch++; busy = false; needsAudioTap = false;
      player.interrupt();
      message = 'Voice will resume when you return.';
      notifyListeners();
      return;
    }
    if (!enabled) { if (busy) stop(); return; }
    final binding = capture.responseBinding;
    if (binding == null) { stop('Listening needs to reconnect before voice can resume.'); return; }
    _returnContext = Map<String, dynamic>.from(binding['context']);
    suspended = true;
    capture.fastTranscript = false;
    needsAudioTap = false;
    _epoch++;
    _replyBeganAt = null;
    _interruptWaiting();
    busy = false; playing = false;
    _question.clear();
    player.interrupt();
    cancelRequest();
    message = 'Voice will resume when you return. Listening stays connected while your browser allows it.';
    notifyListeners();
  }

  Future<void> returnToPage({bool userGesture = false}) async {
    if (_dead || !enabled || !suspended || busy) return;
    final binding = capture.responseBinding;
    if (binding == null || !mapEquals(binding['context'], _returnContext)) {
      stop('Listening changed while away. Tap Start listening, then enable voice.');
      return;
    }
    _binding = jsonEncode(binding);
    final epoch = _epoch;
    busy = true;
    message = 'Resuming Nova’s voice…';
    notifyListeners();
    try {
      // On a fallback tap, create/unlock audio directly in the gesture stack.
      final activated = userGesture ? player.enable().then((_) => player.ready) : player.resume();
      final ready = await activated;
      if (!_current(epoch)) return;
      if (!ready) {
        needsAudioTap = true;
        message = 'Listening is connected. Tap Resume voice to let this browser play audio again.';
        return;
      }
      await capture.prepareSpokenTranscript();
      if (!_current(epoch)) return;
      _window = capture.transcriptWindowId;
      if (_window == null) throw StateError('Captions unavailable');
      _seen = capture.transcriptLines.isEmpty ? 0 : capture.transcriptLines.last.sequence;
      _question.clear(); _quietUntil = 0;
      suspended = false; needsAudioTap = false; _returnContext = null;
      capture.fastTranscript = true;
      message = 'Nova is ready again. Say “Nova” and your next question.';
      if (smallTalk && _waitingClips.isEmpty) unawaited(_prepareWaitingVoice(epoch));
    } catch (_) {
      if (_current(epoch)) {
        needsAudioTap = true;
        message = 'Tap Resume voice to try again. Listening does not need to be restarted.';
      }
    } finally {
      if (!_dead && epoch == _epoch) {
        if (!_current(epoch)) {
          stop('Listening changed while resuming. Tap Start listening, then enable voice.');
        } else { busy = false; notifyListeners(); }
      }
    }
  }

  void _scan() {
    if (_dead) return;
    memory.checkContext();
    if (suspended) {
      if (!capture.isCurrent()) stop();
      return;
    }
    if (_binding != null && _binding != _currentBinding) {
      stop(
        'Spoken replies stopped because listening or meeting permission changed.',
      );
      return;
    }
    if (!enabled) return;
    if (!player.ready) {
      leavePage();
      needsAudioTap = true;
      message = 'Listening is connected. Tap Resume voice to restore browser audio.';
      notifyListeners();
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
      if (busy || playing || memory.active || _now() < _quietUntil) continue;
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
    _maybeSpeakWaiting();
    if (enabled && !suspended && !busy && !playing && !memory.active && _quietUntil > 0 && _now() >= _quietUntil) {
      _quietUntil = 0;
      message = 'Ready for your next question. Start with “Nova”.';
      notifyListeners();
    }
    if (!enabled || suspended || busy || playing || memory.active || _question.isEmpty) return;
    final bareWake = _question.length == 1 && _question.first.text.trim().replaceFirst(_wake, '').trim().isEmpty;
    final completeQuestion = RegExp(r'[?？]\s*$').hasMatch(_question.last.text);
    final pause = bareWake ? 2800 : completeQuestion ? 700 : 1600;
    if (_now() - _changedAt < pause && _now() - _beganAt < 12000) return;
    final first = _question.first.sequence, last = _question.last.sequence;
    _question.clear();
    final epoch = _epoch,
        context = capture.responseBinding!['context'],
        window = _window;
    busy = true;
    answer = null;
    memoryStatus = null;
    _replyBeganAt = _now();
    _waitingStage = 0;
    message = 'Nova is preparing your answer…';
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
          .timeout(const Duration(seconds: 125));
      if (!_current(epoch) || !enabled) return;
      _replyBeganAt = null;
      _interruptWaiting(); // Stop chatter before validating/playing the answer.
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
        if (code == 'K135Z_RESPONSE_AGENT_UNAVAILABLE') {
          stop('Could not load your selected agent’s memory and training. Enable spoken replies to retry.');
          return;
        }
        if (<String>{'K135Z_WORKSPACE_TIMEOUT','K135Z_RESPONSE_PROVIDER_FAILED',
            'K135Z_RESPONSE_INVALID_DRAFT','K135Z_RESPONSE_INVALID_AUDIO',
            'K135Z_RESPONSE_QUESTION_EXPIRED'}.contains(code)) {
          message = 'That reply could not finish. Voice is still on—say “Nova” and ask again.';
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
      final agent = r['agent'];
      if (agent is Map) {
        if (agent['id'] != capture.agentId ||
            agent['name'] is! String || (agent['name'] as String).length > 80 ||
            agent['memoryEnabled'] is! bool || agent['memoryCount'] is! int ||
            agent['memoryCount'] < 0 || agent['memoryCount'] > 100) {
          throw StateError('Invalid agent memory binding');
        }
        memoryStatus = agent['memoryEnabled'] == true
            ? '${agent['name']} · ${agent['memoryCount']} saved memories loaded for this reply'
            : '${agent['name']} · saved memory is off in Agent Hub';
      }
      if (r['memoryRequest'] != null) {
        final request = r['memoryRequest'];
        if (request is! Map || request.length != 1 || request['text'] is! String ||
            (request['text'] as String).length > 1600 || agent is! Map || agent['memoryEnabled'] != true) {
          throw StateError('Invalid memory proposal');
        }
        memory.propose(request['text'], agent['name']);
      }
      playing = true;
      message = 'Nova is speaking…';
      notifyListeners();
      await player.play(audio);
      if (_current(epoch) && enabled)
        message = memory.visible ? memory.message : 'Reply finished. Ready for another question in a few seconds…';
    } catch (_) {
      if (_current(epoch))
        stop('Reply interrupted. Enable spoken replies, then ask again.');
    } finally {
      if (!_dead && epoch == _epoch) {
        busy = false;
        playing = false;
        _replyBeganAt = null;
        _interruptWaiting();
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
    _replyBeganAt = null;
    _interruptWaiting();
    _waitingClips = const [];
    starting = false;
    enabled = false;
    memory.cancel();
    suspended = false; needsAudioTap = false; _returnContext = null;
    busy = false;
    playing = false;
    capture.fastTranscript = false;
    answer = null;
    memoryStatus = null;
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
    memory.removeListener(_memoryChanged);
    memory.dispose();
    _dead = true;
    _clock.stop();
    super.dispose();
  }
}
