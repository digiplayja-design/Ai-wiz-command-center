import 'brain_model.dart';

enum BrainSessionAction { none, configure, ready, reject }

/// The first provider event can describe defaults. Keep the microphone muted
/// until session.updated acknowledges the selected voice configuration.
class BrainVoiceSessionGate {
  BrainVoiceSessionGate({
    this.mode = BrainVoiceMode.deep,
    this.projectionEnabled = false,
  });
  final BrainVoiceMode mode;
  final bool projectionEnabled;
  bool _requested = false;
  Map<String, dynamic>? _memoryTool;
  String? _instructions;

  static const projectionActions = <String>[
    'open',
    'close',
    'room',
    'search',
    'camera',
    'ask',
    'savePlace',
    'imageryAge',
    'liveView',
    'directions',
  ];
  static const projectionValueLimit = 1000;
  static const projectionTool = <String, dynamic>{
    'type': 'function',
    'name': 'control_projection',
    'description': 'Control Projection Mode, ask about the selected place, or prepare directions when the user explicitly requests it. Use directions for route to, navigate to, or directions to an address. The app checks the original user transcript before acting.',
    'parameters': {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': projectionActions},
        'value': {'type': 'string', 'maxLength': projectionValueLimit},
      },
      'required': ['action', 'value'],
      'additionalProperties': false,
    },
  };
  static const projectionInstructions =
      '# Projection capability for this client\n'
      'This client adds control_projection alongside remember_in_brain. Earlier references to having only the memory tool do not include this optional capability. Projection Mode is a view inside KORLIX. Use control_projection only for the user\'s explicit projection, map, place, camera or room request, or a question about the selected place. Use an empty value when no value is needed. When the user confirms a displayed place or chooses a displayed result, use action search with their original confirmation as value, for example "yes, that is the place" or "choose the first result". The app validates the original user transcript. For an explicit route to, navigate to, or directions to a destination, use action directions with that destination. This opens a route review screen; the user starts navigation with a tap. Do not claim navigation has started. For an explicit request to remember or save this place, address, building or location, use action savePlace. All ordinary memory commands still use remember_in_brain. Relay the returned answer and its scope/source limits accurately. Never describe map imagery as live video or invent a location, camera feed, date, population, mayor, crime statistic or building record. If a tool fails or has no verified data, say so. Do not start or stop the voice session when opening or closing Projection Mode.';

  Map<String, dynamic> get configuration => mode.isLive
      ? {
          'type': 'session.update',
          'session': {
            'type': 'realtime',
            'reasoning': {'effort': 'low'},
            'tool_choice': 'auto',
            if (_memoryTool != null) ...{
              'tools': [_memoryTool, projectionTool],
              'instructions': _instructions,
            },
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
      if (mode.isLive && projectionEnabled && event['session'] is Map) {
        _prepareProjection(event['session'] as Map);
      }
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
            session['tool_choice'] == 'auto');
    final voiceContract =
        liveContract &&
        vad is Map &&
        (vad['type'] == 'semantic_vad' || vad['type'] == 'server_vad') &&
        vad['create_response'] == mode.isLive &&
        transcription is Map &&
        transcription['model'] == 'gpt-transcribe';
    if (!voiceContract) return BrainSessionAction.reject;
    if (!mode.isLive) return BrainSessionAction.ready;
    if (!projectionEnabled) {
      return _hasTools(tools, const {'remember_in_brain'})
          ? BrainSessionAction.ready
          : BrainSessionAction.reject;
    }
    if (_memoryTool == null) {
      // Some providers send defaults in session.created. First acknowledge the
      // server's real memory configuration, then append to that configuration.
      // Never reconstruct or replace its account-bound memory instructions.
      return _prepareProjection(session)
          ? BrainSessionAction.configure
          : BrainSessionAction.reject;
    }
    return _hasTools(tools, const {
              'remember_in_brain',
              'control_projection',
            }) &&
            session['instructions'] == _instructions
        ? BrainSessionAction.ready
        : BrainSessionAction.reject;
  }

  bool _prepareProjection(Map session) {
    final tools = session['tools'];
    final instructions = session['instructions'];
    final model = session['model'];
    if (!_hasTools(tools, const {'remember_in_brain'}) ||
        instructions is! String ||
        instructions.trim().isEmpty ||
        model is! String ||
        (model != mode.model && !model.startsWith('${mode.model}-'))) {
      return false;
    }
    _memoryTool = Map<String, dynamic>.from((tools as List).single as Map);
    _instructions = '$instructions\n\n$projectionInstructions';
    return true;
  }

  bool _hasTools(Object? tools, Set<String> expected) {
    if (tools is! List || tools.length != expected.length) return false;
    final names = <String>{};
    for (final tool in tools) {
      if (tool is! Map || tool['name'] is! String) return false;
      names.add(tool['name'] as String);
    }
    return names.length == expected.length && names.containsAll(expected);
  }
}
