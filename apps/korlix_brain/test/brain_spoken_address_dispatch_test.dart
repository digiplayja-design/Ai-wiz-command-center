import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_live_turns.dart';
import 'package:korlix_brain/brain_model.dart';
import 'package:korlix_brain/brain_projection.dart';
import 'package:korlix_brain/brain_voice_turns.dart';

const _firstAddress = '20 Resee Street, Unit 4, Reece, NY 10012';
const _nextAddress = '14360 Jupiter Road, Suite 8, Brooklyn, NY 10012';
const _config = <String, dynamic>{
  'rendererUrl': 'https://api.example.com/brain-projection/earth.html',
  'mapAvailable': true,
  'geocodingAvailable': true,
  'answersAvailable': false,
};

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Uses the same controller callbacks and transcript forwarding as the native
/// workspace. Only provider events and backend replies are in-memory fixtures.
class _SpokenAddressHarness {
  _SpokenAddressHarness(this.mode) {
    projection = BrainProjection(
      backendUrl: 'https://api.example.com',
      request: _request,
      onOpen: () => opens++,
      onClose: () {},
      onStartVoice: () async {
        voiceStarts++;
      },
      onStopVoice: () async {},
      onSave: (_, _) async => throw StateError('No place save expected'),
    );
    projection.receiveVoice({
      'type': 'voice',
      'phase': 'listening',
      'message': 'Rici is listening',
    });
    if (mode == BrainVoiceMode.live) {
      live = BrainLiveTurns(
        send: (event) async => sent.add(event),
        requestMemory: (_, text) async {
          memoryRequests.add(text);
          throw StateError('No memory request expected');
        },
        emit: projection.receiveVoice,
        saved: (_) async {},
        isCurrent: () => true,
        reportTiming: (_, _) async {},
        onProjection: projection.voiceTurn,
        recognizesProjection: projection.recognizesVoiceControl,
      );
    } else {
      deep = BrainVoiceTurns(
        request: (_, text, _) async {
          reasoningRequests.add(text);
          return {
            'answer': 'What would you like to do with that address?',
            'model': brainModel,
            'reasoningEffort': brainReasoningEffort,
          };
        },
        send: (event) async => sent.add(event),
        emit: projection.receiveVoice,
        saved: (_) async {},
        isCurrent: () => true,
        onProjection: projection.voiceTurn,
        recognizesProjection: projection.recognizesVoiceControl,
      );
    }
  }

  final BrainVoiceMode mode;
  late final BrainProjection projection;
  BrainLiveTurns? live;
  BrainVoiceTurns? deep;
  final queries = <String>[];
  final memoryRequests = <String>[];
  final reasoningRequests = <String>[];
  final sent = <Map<String, dynamic>>[];
  int opens = 0;
  int voiceStarts = 0;

  Map get camera => projection.snapshot['camera'] as Map;
  Map? get selected => projection.snapshot['selectedPlace'] as Map?;
  List get candidates => projection.snapshot['candidates'] as List;
  Map get feedback => projection.snapshot['lastVoiceCommand'] as Map;

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    if (method == 'GET' && path == '/api/brain-projection/config') {
      return _config;
    }
    if (method == 'POST' && path == '/api/brain-projection/resolve') {
      final query = body!['query'] as String;
      queries.add(query);
      final index = queries.length;
      return {
        'candidates': [
          {
            'id': 'place-$index',
            'label': 'Fixture property $index',
            'address': query,
            'latitude': 40.70 + index / 100,
            'longitude': -74.0 + index / 100,
          },
        ],
      };
    }
    throw StateError('Unexpected backend request: $method $path');
  }

  void begin(String id) {
    live?.speechStarted(id);
    deep?.speechStarted(id);
    live?.speechStopped(id);
    deep?.speechStopped(id);
    live?.responseStarted({'id': 'auto-$id'});
  }

  void accept(String id, String text) {
    live?.accept(id, text);
    deep?.accept(id, text);
  }

  List<Map<String, dynamic>> repliesFor(String id) => sent.where((event) {
    final response = event['response'];
    final metadata = response is Map ? response['metadata'] : null;
    return event['type'] == 'response.create' &&
        metadata is Map &&
        metadata['brain_turn'] == id;
  }).toList();

  Future<void> speak(
    String id,
    String text, {
    bool duplicateProjectionTool = false,
  }) async {
    begin(id);
    accept(id, text);
    accept(id, text);
    await _flush();
    if (live != null) {
      final call = {
        'type': 'function_call',
        'status': 'completed',
        'name': 'control_projection',
        'call_id': 'projection-$id',
        'arguments': jsonEncode({
          'action': 'search',
          'value': '999 Model Changed Road, Different City',
        }),
      };
      final response = {
        'id': 'auto-$id',
        'status': duplicateProjectionTool ? 'completed' : 'cancelled',
        'output': duplicateProjectionTool ? [call, call] : <Object>[],
      };
      await live!.responseDone(response);
      if (duplicateProjectionTool) await live!.responseDone(response);
    }
    await _flush();

    // Complete the real acknowledgment lifecycle before the next utterance.
    // Deep Think reserves its speech queue until response.done arrives.
    final replies = repliesFor(id);
    for (var index = 0; index < replies.length; index++) {
      final response = replies[index]['response'] as Map;
      final responseId = 'spoken-$id-$index';
      final started = {'id': responseId, 'metadata': response['metadata']};
      live?.responseStarted(started);
      deep?.responseStarted(started);
      if (live != null) {
        await live!.responseDone({
          'id': responseId,
          'status': 'completed',
          'output': <Object>[],
        });
      }
      deep?.responseDone(responseId);
    }
    await _flush();
  }

  void retire(String id) {
    live?.transcriptionFailed(id);
    deep?.transcriptionFailed(id);
  }

  void dispose() {
    live?.dispose();
    deep?.dispose();
    projection.dispose();
  }
}

void main() {
  for (final mode in BrainVoiceMode.values) {
    final label = mode == BrainVoiceMode.live ? 'Live' : 'Deep Think';
    for (final firstUtterance in [
      'Go to $_firstAddress',
      'Rici, search this address: $_firstAddress',
    ]) {
      test('$label opens Projection from home for "$firstUtterance" and '
          'searches the next spoken address without typing', () async {
        final h = _SpokenAddressHarness(mode);
        addTearDown(h.dispose);
        final initialCamera = Map.of(h.camera);
        expect(h.projection.isOpen, false);

        // No model tool and no UI open/search action are supplied here.
        await h.speak('first-address', firstUtterance);

        expect(h.projection.isOpen, true);
        expect(h.opens, 1);
        expect(h.voiceStarts, 0, reason: 'Keep the home voice session');
        expect(h.queries, [_firstAddress]);
        expect(h.feedback['heard'], firstUtterance);
        expect(h.feedback['action'], 'Find destination');
        expect(h.selected, isNull);
        expect(h.candidates, hasLength(1));
        expect(h.camera, initialCamera, reason: 'Wait for confirmation');
        expect(h.repliesFor('first-address'), hasLength(1));

        await h.speak('confirm-first', 'Yes, that is the place');

        expect(h.selected!['id'], 'place-1');
        expect(h.selected!['userQuery'], _firstAddress);
        expect(h.candidates, isEmpty);
        expect(h.camera['operation'], 'flyTo');
        expect(h.camera['viewMode'], 'street');
        expect(h.camera['sequence'], initialCamera['sequence'] + 1);
        final firstCamera = Map.of(h.camera);

        // The previous Street View is selected. A full standalone address
        // must now start a new lookup without opening Projection again.
        await h.speak(
          'next-address',
          _nextAddress,
          duplicateProjectionTool: true,
        );

        expect(h.queries, [_firstAddress, _nextAddress]);
        expect(h.opens, 1);
        expect(h.feedback['heard'], _nextAddress);
        expect(h.feedback['action'], 'Find destination');
        expect(h.selected, isNull);
        expect(h.candidates, hasLength(1));
        expect(h.candidates.single['id'], 'place-2');
        expect(h.camera, firstCamera, reason: 'Do not relocate on lookup');
        expect(h.repliesFor('next-address'), hasLength(1));
        if (mode == BrainVoiceMode.live) {
          expect(
            h.sent.where(
              (event) =>
                  event['type'] == 'conversation.item.create' &&
                  (event['item'] as Map)['call_id'] ==
                      'projection-next-address',
            ),
            hasLength(1),
            reason: 'Duplicate model calls share the direct ASR result',
          );
        }

        await h.speak('confirm-next', 'Choose the first result');

        expect(h.selected!['id'], 'place-2');
        expect(h.selected!['userQuery'], _nextAddress);
        expect(h.camera['operation'], 'flyTo');
        expect(h.camera['viewMode'], 'street');
        expect(h.camera['sequence'], firstCamera['sequence'] + 1);
        expect(h.camera['latitude'], h.selected!['latitude']);
        expect(h.camera['longitude'], h.selected!['longitude']);
        expect(h.queries, [_firstAddress, _nextAddress]);
        expect(h.memoryRequests, isEmpty);
        expect(h.reasoningRequests, isEmpty);
      });
    }

    test(
      '$label ignores a stale address transcript after a newer utterance',
      () async {
        final h = _SpokenAddressHarness(mode);
        addTearDown(h.dispose);
        await h.speak('first-address', 'Go to $_firstAddress');
        await h.speak('confirm-first', 'Yes, that is the place');
        final selected = Map.of(h.selected!);
        final camera = Map.of(h.camera);
        final feedback = Map.of(h.feedback);

        h.begin('stale-address');
        h.begin('newer-utterance');
        h.accept('stale-address', _nextAddress);
        h.accept('stale-address', _nextAddress);
        await _flush();

        expect(h.queries, [_firstAddress]);
        expect(h.selected, selected);
        expect(h.camera, camera);
        expect(h.feedback, feedback);
        expect(h.repliesFor('stale-address'), isEmpty);
        expect(h.memoryRequests, isEmpty);
        expect(h.reasoningRequests, isEmpty);
        h.retire('newer-utterance');
      },
    );

    test('$label keeps a bare address in ordinary home conversation', () async {
      final h = _SpokenAddressHarness(mode);
      addTearDown(h.dispose);
      expect(h.projection.recognizesVoiceControl(_nextAddress), false);

      await h.speak('home-address', _nextAddress);

      expect(h.projection.isOpen, false);
      expect(h.opens, 0);
      expect(h.queries, isEmpty);
      expect(h.selected, isNull);
      expect(h.memoryRequests, isEmpty);
      expect(
        h.reasoningRequests,
        mode == BrainVoiceMode.deep ? [_nextAddress] : isEmpty,
      );
    });
  }
}
