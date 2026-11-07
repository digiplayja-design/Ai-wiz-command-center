import 'dart:async';
import 'dart:convert';

import 'brain_pronunciation.dart';
import 'brain_voice_session.dart';

/// Native Realtime replies are never held behind ASR, HTTP or Sol. Only an
/// explicit tool waits for the original, item-bound user transcript.
class BrainLiveTurns {
  BrainLiveTurns({
    required this.send,
    required this.requestMemory,
    required this.emit,
    required this.saved,
    required this.isCurrent,
    required this.reportTiming,
    this.onProjection,
    DateTime Function()? now,
    this.transcriptionTimeout = const Duration(seconds: 15),
  }) : now = now ?? DateTime.now;
  final Future<void> Function(Map<String, dynamic>) send;
  final Future<Map<String, dynamic>> Function(String, String) requestMemory;
  final void Function(Map<String, dynamic>) emit;
  final Future<void> Function(Map<String, dynamic>) saved;
  final bool Function() isCurrent;
  final Future<void> Function(String, int) reportTiming;
  final Future<Map<String, dynamic>?> Function(
    String turnId,
    String transcript,
    Map<String, dynamic>? arguments,
  )?
  onProjection;
  final DateTime Function() now;
  final Duration transcriptionTimeout;
  final _turns = <String, _LiveTurn>{};
  final _waitingResponses = <String>[];
  final _responses = <String, String>{};
  final _calls = <String>{}, _savedTurns = <String>{};
  Future<void> _toolQueue = Future.value();
  int _epoch = 0;
  bool _disposed = false;
  String? _activeResponse;
  bool get current => !_disposed && isCurrent();

  void speechStarted(String id) {
    if (!current || id.isEmpty || _turns.containsKey(id)) return;
    final active = _activeResponse;
    ++_epoch;
    _turns[id] = _LiveTurn(_epoch);
    if (active != null) {
      unawaited(
        send({'type': 'response.cancel', 'response_id': active})
            .catchError((Object _) {}),
      );
    }
    // The provider's interrupt_response clears playback at the VAD boundary.
    // An explicit Stop closes microphone, renderer and peer in BrainVoice.
  }

  void speechStopped(String id) {
    if (!current || id.isEmpty) return;
    final turn = _turns.putIfAbsent(id, () => _LiveTurn(_epoch));
    if (turn.stoppedAt != null) return;
    turn.stoppedAt = now();
    _waitingResponses.add(id);
  }

  void accept(String id, String text) {
    if (!current || id.isEmpty) return;
    final turn = _turns.putIfAbsent(id, () => _LiveTurn(_epoch));
    if (turn.transcript.isCompleted) return;
    turn.transcript.complete(text.trim().isEmpty ? null : text);
    if (text.trim().isNotEmpty) {
      emit({'type': 'transcript', 'role': 'you', 'text': text});
    }
  }

  void transcriptionFailed(String id) {
    final turn = _turns[id];
    if (turn != null && !turn.transcript.isCompleted) {
      turn.transcript.complete(null);
    }
    // Direct audio conversation can continue even when display ASR fails.
  }

  void responseStarted(Map response) {
    if (!current) return;
    final id = response['id']?.toString();
    if (id == null || _responses.containsKey(id)) return;
    final metadata = response['metadata'];
    final continuation = metadata is Map
        ? metadata['brain_turn']?.toString()
        : null;
    final turnId =
        continuation ??
        (_waitingResponses.isEmpty ? null : _waitingResponses.removeAt(0));
    if (turnId == null || !_turns.containsKey(turnId)) return;
    _responses[id] = turnId;
    if (_turns[turnId]!.epoch != _epoch) {
      unawaited(
        send({'type': 'response.cancel', 'response_id': id})
            .catchError((Object _) {}),
      );
      return;
    }
    _activeResponse = id;
  }

  /// Count a tool exchange and its spoken acknowledgment as one user turn,
  /// while the usage guard still meters tokens from both provider responses.
  Map<String, dynamic> usageEvent(Map<String, dynamic> event) {
    final response = event['response'];
    final turnId = response is Map ? _responses[response['id']] : null;
    if (event['type'] != 'response.done' ||
        response is! Map ||
        turnId == null) {
      return event;
    }
    return {
      ...event,
      'response': {
        ...response,
        'metadata': {
          ...?((response['metadata'] is Map)
              ? response['metadata'] as Map
              : null),
          'brain_turn': turnId,
        },
      },
    };
  }

  void audioStarted(String? responseId) {
    final id = _responses[responseId ?? _activeResponse];
    final turn = _turns[id];
    if (!current ||
        id == null ||
        turn == null ||
        turn.epoch != _epoch ||
        turn.audioReported ||
        turn.stoppedAt == null) {
      return;
    }
    turn.audioReported = true;
    final ms = now().difference(turn.stoppedAt!).inMilliseconds;
    if (ms >= 0 && ms <= 120000) {
      unawaited(reportTiming(id, ms).catchError((Object _) {}));
    }
  }

  Future<void> responseDone(Map response) async {
    final responseId = response['id']?.toString();
    if (_activeResponse == responseId) _activeResponse = null;
    if (!current || response['status'] != 'completed') return;
    final turnId = _responses[responseId];
    if (turnId == null) return;
    final output = response['output'];
    if (output is! List) return;
    final calls = output
        .whereType<Map>()
        .where((item) => item['type'] == 'function_call')
        .toList();
    if (calls.isEmpty) return;
    if (calls.every((call) => call['name'] == 'control_projection')) {
      // A newer spoken search/close must reach the controller immediately so
      // it can invalidate an older lookup. The turn epoch still gates speech.
      await _completeTools(turnId, calls);
      return;
    }
    // Serialize writes; a newer utterance must not change which transcript
    // authorizes an in-flight save. Duplicate call IDs never replay it.
    final task = _toolQueue.then((_) => _completeTools(turnId, calls));
    _toolQueue = task.catchError((Object _) {});
    await task;
  }

  Future<void> _completeTools(String turnId, List<Map> calls) async {
    final turn = _turns[turnId];
    if (!current || turn == null) return;
    var wroteOutput = false;
    var usedProjection = false;
    for (final call in calls) {
      final callId = call['call_id']?.toString();
      if (callId == null || !_calls.add(callId)) continue;
      final projection = call['name'] == 'control_projection';
      usedProjection = usedProjection || projection;
      Map<String, dynamic> result;
      try {
        final args = jsonDecode(call['arguments']?.toString() ?? '{}');
        if (projection) {
          if (onProjection == null || !_projectionArguments(args)) {
            throw StateError('Unsupported projection request');
          }
        } else {
          if (call['name'] != 'remember_in_brain' ||
              args is! Map ||
              args.isNotEmpty) {
            throw StateError('Unsupported memory request');
          }
        }
        final transcript = await turn.transcript.future.timeout(
          transcriptionTimeout,
          onTimeout: () => null,
        );
        if (!current) return;
        if (transcript == null) throw StateError('Missing original transcript');
        if (projection) {
          // A delayed navigation must not replace a newer place or utterance.
          // The controller also invalidates in-flight work on Stop/selection.
          if (turn.epoch != _epoch) {
            result = _interruptedProjection;
          } else {
            result =
                await onProjection!(
                  turnId,
                  transcript,
                  Map<String, dynamic>.from(args as Map),
                ) ??
                {
                  'ok': false,
                  'handled': false,
                  'answer': 'That request was not recognized as a projection command. Please say what you want to open or explore.',
                };
            if (!current) return;
            if (turn.epoch != _epoch) result = _interruptedProjection;
          }
          // Explicit place notes are saved and refreshed by the controller.
          // A projection result must never replay the existing memory handler.
        } else {
          // The server validates the command and owns idempotency and allowance.
          result = await requestMemory(turnId, transcript);
          if (!current) return;
          if (result['saved'] == true && _savedTurns.add(turnId)) {
            unawaited(saved(result).catchError((Object _) {}));
            emit({
              'type': 'voiceSaved',
              'message': result['answer'],
              'memory': result['memory'],
            });
          }
        }
      } catch (_) {
        result = projection
            ? {
                'ok': false,
                'handled': false,
                'saved': false,
                'answer': 'The projection request could not be confirmed. Please repeat the command.',
              }
            : {
                'ok': false,
                'saved': false,
                'answer': 'The save was not confirmed. Check My Brain before repeating it.',
              };
        if (current && (!projection || turn.epoch == _epoch)) {
          emit({'type': 'voiceNotice', 'message': result['answer']});
        }
      }
      if (!current) return;
      await send({
        'type': 'conversation.item.create',
        'item': {
          'type': 'function_call_output',
          'call_id': callId,
          'output': jsonEncode({
            for (final key in [
              'ok',
              'saved',
              'handled',
              'answer',
              'awaitingMemory',
              'kind',
              if (projection) ...[
                'sources',
                'scope',
                'date',
                'isLive',
                'imageryDate',
              ],
            ])
              if (result.containsKey(key)) key: result[key],
          }),
        },
      });
      wroteOutput = true;
    }
    if (wroteOutput && current && turn.epoch == _epoch) {
      await send({
        'type': 'response.create',
        'response': {
          'metadata': {'brain_turn': turnId},
          'instructions': usedProjection
              ? 'Briefly relay the tool result accurately, including its scope and source limits. Do not add unverified location facts or describe map imagery as live video. Confirm a save only when saved is true. Do not call another tool for the same utterance. Your name is Ree-see. $brainPronunciation'
              : 'Briefly relay the memory tool result accurately. Confirm a save only when saved is true. Do not call another tool for the same utterance. Your name is Ree-see. $brainPronunciation',
          'tool_choice': 'none',
        },
      });
    }
  }

  bool _projectionArguments(Object? value) =>
      value is Map &&
      value.length == 2 &&
      BrainVoiceSessionGate.projectionActions.contains(value['action']) &&
      value['value'] is String &&
      (value['value'] as String).length <=
          BrainVoiceSessionGate.projectionValueLimit;

  static const _interruptedProjection = <String, dynamic>{
    'ok': false,
    'handled': true,
    'answer': 'That projection reply was interrupted by a newer request.',
  };

  void dispose() {
    _disposed = true;
    for (final turn in _turns.values) {
      if (!turn.transcript.isCompleted) turn.transcript.complete(null);
    }
    _waitingResponses.clear();
  }
}

class _LiveTurn {
  _LiveTurn(this.epoch);
  final int epoch;
  final transcript = Completer<String?>();
  DateTime? stoppedAt;
  bool audioReported = false;
}
