import 'dart:async';

import 'brain_speech_queue.dart';
import 'brain_model.dart';

/// Routes completed user transcripts to the account-bound Sol 6.1 Max backend.
/// Realtime delivers speech only; it is never asked to answer a user question.
class BrainVoiceTurns {
  BrainVoiceTurns({
    required this.request,
    required this.send,
    required this.emit,
    required this.isCurrent,
    required this.saved,
    this.onProjection,
  }) {
    _speech = BrainSpeechQueue(
      send,
      () => current,
      () => emit({
        'type': 'voiceNotice',
        'message': 'Speech was interrupted. Please try again.',
      }),
    );
  }
  final Future<Map<String, dynamic>> Function(
    String id,
    String text,
    void Function(Map<String, dynamic>) onDelta,
  )
  request;
  final Future<void> Function(Map<String, dynamic> event) send;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isCurrent;
  final Future<void> Function(Map<String, dynamic>) saved;
  final Future<Map<String, dynamic>?> Function(
    String turnId,
    String transcript,
    Map<String, dynamic>? arguments,
  )?
  onProjection;
  final _items = <String, _Turn>{};
  final _order = <String>[];
  final _seen = <String>{};
  int _epoch = 0;
  late final BrainSpeechQueue _speech;
  final _transcriptionTimers = <String, Timer>{};
  bool _busy = false, _disposed = false;
  bool get current => !_disposed && isCurrent();

  void speechStarted(String id) {
    if (!current) return;
    ++_epoch;
    if (id.isNotEmpty && !_seen.contains(id) && !_items.containsKey(id)) {
      _items[id] = _Turn(_epoch);
      _order.add(id);
    }
    // VAD interrupts playback; cancel generation too, so an old answer cannot
    // resume after the new utterance. Do not cancel an already authorized save.
    _speech.interrupt(_epoch);
  }

  void responseStarted(Map response) {
    _speech.started(response);
  }

  void responseDone(String? id) {
    _speech.done(id);
  }

  void speechStopped(String id) {
    if (!current || id.isEmpty || _seen.contains(id)) return;
    _transcriptionTimers.remove(id)?.cancel();
    _transcriptionTimers[id] = Timer(
      const Duration(seconds: 25),
      () => transcriptionFailed(id),
    );
  }

  void transcriptionFailed(String id) {
    _transcriptionTimers.remove(id)?.cancel();
    _seen.add(id);
    _items.remove(id);
    _order.remove(id);
    if (current) {
      emit({
        'type': 'voiceNotice',
        'message': 'I could not hear that clearly. Please repeat it.',
      });
    }
    unawaited(_drain());
  }

  void accept(String id, String text) {
    if (!current || id.isEmpty || _seen.contains(id)) return;
    if (text.trim().isEmpty) {
      transcriptionFailed(id);
      return;
    }
    if (!_items.containsKey(id)) {
      _items[id] = _Turn(_epoch);
      _order.add(id);
    }
    if (_items[id]!.text != null) return;
    _transcriptionTimers.remove(id)?.cancel();
    _items[id]!.text = text;
    emit({'type': 'transcript', 'role': 'you', 'text': text});
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_busy || !current) return;
    _busy = true;
    try {
      while (current && _order.isNotEmpty) {
        final id = _order.first;
        final turn = _items[id]!;
        if (turn.text == null) {
          break; // ASR completion events can arrive out of order.
        }
        _order.removeAt(0);
        _items.remove(id);
        _seen.add(id);
        if (turn.epoch == _epoch) {
          emit({
            'type': 'voice',
            'phase': 'thinking',
            'message': 'Rici is thinking · $brainModelLabel',
          });
        }
        try {
          if (onProjection != null && turn.epoch == _epoch) {
            // The controller handles only an explicit projection/place intent;
            // ordinary conversation and ordinary memories return null. It owns
            // explicit place-note writes, so never repeat the saved callback.
            final projection = await onProjection!(id, turn.text!, null);
            if (!current) break;
            if (projection?['handled'] == true) {
              if (turn.epoch != _epoch) continue;
              final answer = projection!['answer'];
              if (answer is! String || answer.trim().isEmpty) {
                throw StateError('Missing projection answer');
              }
              _speech.add(answer, turn.epoch, id);
              continue;
            }
          }
          var streamedText = '';
          final buffer = BrainSpeechBuffer((text) {
            if (current && turn.epoch == _epoch) {
              _speech.add(text, turn.epoch, id);
            }
          });
          final result = await request(id, turn.text!, (event) {
            if (!current || turn.epoch != _epoch) return;
            _verifyModel(event, required: true);
            final text = event['text'];
            if (text is! String) {
              throw StateError('Invalid streamed answer');
            }
            streamedText += text;
            buffer.add(text);
          });
          if (!current) break;
          if (result['saved'] == true) {
            // The server has acknowledged the durable write. A newer utterance
            // suppresses stale speech, but the saved record still updates My Brain.
            // Refresh My Brain independently; its network reads must not delay
            // the already verified spoken save acknowledgement.
            unawaited(saved(result).catchError((Object _) {}));
            emit({
              'type': 'voiceSaved',
              'message': result['answer'],
              'memory': result['memory'],
            });
          }
          if (turn.epoch != _epoch) continue;
          final answer = result['answer'];
          if (answer is! String || answer.isEmpty) {
            throw StateError('Missing answer');
          }
          _verifyModel(result);
          if (streamedText.isNotEmpty) {
            if (streamedText.trim() != answer.trim()) {
              throw StateError('Incomplete streamed answer');
            }
            buffer.finish();
          } else {
            _speech.add(answer, turn.epoch, id);
          }
        } catch (_) {
          if (current && turn.epoch == _epoch) {
            _speech.interrupt(_epoch);
            emit({
              'type': 'voiceNotice',
              'message':
                  'Rici could not finish that turn. Check My Brain before repeating a save. Your reasoning model is still $brainModelLabel.',
            });
            emit({
              'type': 'voice',
              'phase': 'listening',
              'message': 'Ready to try again · $brainModelLabel',
            });
          }
        }
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _speech.dispose();
    ++_epoch;
    _order.clear();
    _items.clear();
    for (final timer in _transcriptionTimers.values) {
      timer.cancel();
    }
    _transcriptionTimers.clear();
  }

  void _verifyModel(Map event, {bool required = false}) {
    final model = event['model'];
    if ((required || model != null) &&
        (!isBrainReasoningModel(model) ||
            event['reasoningEffort'] != brainReasoningEffort)) {
      throw StateError('$brainModelLabel was not verified');
    }
  }
}

class _Turn {
  _Turn(this.epoch);
  final int epoch;
  String? text;
}
