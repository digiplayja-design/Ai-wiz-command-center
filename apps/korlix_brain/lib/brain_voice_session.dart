import 'brain_model.dart';

enum BrainSessionAction { none, configure, ready, reject }

/// The first provider event can describe defaults. Keep the microphone muted
/// until session.updated acknowledges our speech-only configuration.
class BrainVoiceSessionGate {
  BrainVoiceSessionGate({this.mode = BrainVoiceMode.deep});
  final BrainVoiceMode mode;
  bool _requested = false;

  Map<String, dynamic> get configuration => mode.isLive
      ? {
          'type': 'session.update',
          'session': {
            'type': 'realtime',
            'reasoning': {'effort': 'low'},
            'tool_choice': 'auto',
            'audio': {
              'input': {
                'transcription': {
                  'model': 'gpt-transcribe',
                  'keywords': ['Rici', 'Risi', 'KORLIX', 'Rici remember this'],
                },
                'turn_detection': {
                  'type': 'semantic_vad',
                  'eagerness': 'high',
                  'create_response': true,
                  'interrupt_response': true,
                },
              },
            },
          },
        }
      : update;

  static const update = <String, dynamic>{
    'type': 'session.update',
    'session': {
      'type': 'realtime',
      'tools': <Object>[],
      'tool_choice': 'none',
      'audio': {
        'input': {
          'transcription': {
            'model': 'gpt-transcribe',
            'keywords': ['Rici', 'Risi', 'KORLIX', 'Rici remember this'],
          },
          'turn_detection': {
            'type': 'semantic_vad',
            'eagerness': 'high',
            'create_response': false,
            'interrupt_response': true,
          },
        },
      },
    },
  };

  BrainSessionAction observe(Map<String, dynamic> event) {
    if (event['type'] == 'session.created') {
      if (_requested) return BrainSessionAction.none;
      _requested = true;
      return BrainSessionAction.configure;
    }
    if (event['type'] != 'session.updated' || !_requested) {
      return BrainSessionAction.none;
    }
    final session = event['session'];
    if (session is! Map) return BrainSessionAction.reject;
    final audio = session['audio'];
    final input = audio is Map ? audio['input'] : null;
    // GA uses audio.input; older event serializers used the flat fields.
    // A present GA field is authoritative, even if a flat field disagrees.
    final vad = session.containsKey('audio')
        ? (input is Map ? input['turn_detection'] : null)
        : session['turn_detection'];
    final transcription = session.containsKey('audio')
        ? (input is Map ? input['transcription'] : null)
        : session['input_audio_transcription'];
    final tools = session['tools'];
    final liveContract =
        !mode.isLive ||
        (session['model'] is String &&
            (session['model'] == mode.model ||
                (session['model'] as String).startsWith('${mode.model}-')) &&
            session['reasoning'] is Map &&
            (session['reasoning'] as Map)['effort'] == 'low' &&
            session['tool_choice'] == 'auto' &&
            tools is List &&
            tools.length == 1 &&
            tools.first is Map &&
            (tools.first as Map)['name'] == 'remember_in_brain');
    return liveContract &&
            vad is Map &&
            (vad['type'] == 'semantic_vad' || vad['type'] == 'server_vad') &&
            vad['create_response'] == mode.isLive &&
            transcription is Map &&
            transcription['model'] == 'gpt-transcribe'
        ? BrainSessionAction.ready
        : BrainSessionAction.reject;
  }
}
