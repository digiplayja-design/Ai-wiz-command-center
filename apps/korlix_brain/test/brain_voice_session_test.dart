import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_voice_session.dart';

void main() {
  Map<String, dynamic> acknowledged({Object? automatic = false}) => {
    'type': 'session.updated',
    'session': {
      'audio': {
        'input': {
          'transcription': {'model': 'gpt-transcribe'},
          'turn_detection': {
            'type': 'semantic_vad',
            'create_response': automatic,
          },
        },
      },
    },
  };

  test(
    'initial defaults require acknowledgement before opening microphone',
    () {
      final gate = BrainVoiceSessionGate();
      expect(
        gate.observe({'type': 'session.created', 'session': {}}),
        BrainSessionAction.configure,
      );
      expect(
        gate.observe({'type': 'input_audio_buffer.speech_started'}),
        BrainSessionAction.none,
      );
      expect(gate.observe(acknowledged()), BrainSessionAction.ready);
    },
  );

  test(
    'even a preconfigured created event waits for the update acknowledgement',
    () {
      final gate = BrainVoiceSessionGate();
      expect(
        gate.observe({...acknowledged(), 'type': 'session.created'}),
        BrainSessionAction.configure,
      );
      expect(
        gate.observe({'type': 'session.created'}),
        BrainSessionAction.none,
      );
      expect(gate.observe(acknowledged()), BrainSessionAction.ready);
    },
  );

  test('unsolicited acknowledgement cannot open microphone', () {
    expect(
      BrainVoiceSessionGate().observe(acknowledged()),
      BrainSessionAction.none,
    );
  });

  test(
    'automatic replies enabled or omitted fail closed, including after ready',
    () {
      for (final value in [true, null, 'false']) {
        final gate = BrainVoiceSessionGate()
          ..observe({'type': 'session.created'});
        expect(gate.observe(acknowledged()), BrainSessionAction.ready);
        expect(
          gate.observe(acknowledged(automatic: value)),
          BrainSessionAction.reject,
        );
      }
    },
  );

  test(
    'flat event serializer is accepted only with explicit safe settings',
    () {
      final gate = BrainVoiceSessionGate()
        ..observe({'type': 'session.created'});
      final event = {
        'type': 'session.updated',
        'session': {
          'turn_detection': {'type': 'server_vad', 'create_response': false},
          'input_audio_transcription': {'model': 'gpt-transcribe'},
        },
      };
      expect(gate.observe(event), BrainSessionAction.ready);
      (event['session'] as Map)['audio'] = {
        'input': {
          'turn_detection': {'create_response': true},
        },
      };
      expect(gate.observe(event), BrainSessionAction.reject);
    },
  );

  test('missing transcription or malformed configuration fails closed', () {
    final gate = BrainVoiceSessionGate()..observe({'type': 'session.created'});
    for (final session in [
      null,
      'invalid',
      <String, dynamic>{},
      {
        'audio': {
          'input': {
            'turn_detection': {
              'type': 'semantic_vad',
              'create_response': false,
            },
          },
        },
      },
    ]) {
      expect(
        gate.observe({'type': 'session.updated', 'session': session}),
        BrainSessionAction.reject,
      );
    }
  });
}
