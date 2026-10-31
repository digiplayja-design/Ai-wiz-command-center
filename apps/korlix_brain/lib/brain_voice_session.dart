enum BrainSessionAction { none, configure, ready, reject }

/// The first provider event can describe defaults. Keep the microphone muted
/// until session.updated acknowledges our speech-only configuration.
class BrainVoiceSessionGate {
  bool _requested = false;

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
            'keywords': ['Rici', 'KORLIX', 'Rici remember this'],
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
    return vad is Map &&
            (vad['type'] == 'semantic_vad' || vad['type'] == 'server_vad') &&
            vad['create_response'] == false &&
            transcription is Map &&
            transcription['model'] == 'gpt-transcribe'
        ? BrainSessionAction.ready
        : BrainSessionAction.reject;
  }
}
