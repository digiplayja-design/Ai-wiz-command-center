import 'dart:convert';

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
  bool _projectionAcknowledged = false;
  int _earlierAcknowledgements = 0;
  Map<String, dynamic>? _memoryTool;
  String? _originalInstructions;
  String? _instructions;
  String? _rejectionCode;

  /// A fixed diagnostic code; never includes provider or account content.
  String? get rejectionCode => _rejectionCode;

  // Initial server setup and an earlier client update can still be awaiting
  // acknowledgement when Projection is appended. Waiting must remain bounded.
  static const _maximumEarlierAcknowledgements = 2;

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
    'description': 'Open or close Projection Mode from Home during an active conversation, look up a spoken address or named landmark, move its camera, ask about the selected place, or prepare directions when explicitly requested. Camera values include closer, farther, left, right, reset, zoomInContinuous, zoomOutContinuous, stopCamera, streetView and earthView. Use directions for route to, navigate to, or directions to an address. The app checks the original user transcript before acting.',
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
      'This client adds control_projection alongside remember_in_brain. Earlier references to having only the memory tool do not include this optional capability. Projection Mode is a view inside KORLIX. You can open it from Home while this conversation is active, even when Projection is closed. For an explicit request such as "Rici, can you open projection mode?", "open VR" or "enter projection", use action open with an empty value. For "close projection" or "exit VR", use action close with an empty value. Do not tell the user you cannot open this app view or redirect a supported request to onscreen controls unless the tool reports a failure. Confirm that the view opened or closed only after the controller result confirms it. Use control_projection only for the user\'s explicit projection, map, place, camera or room request, or a question about the selected place. Use an empty value when no value is needed. Spoken addresses and named landmarks can be searched without typing: use action search with the whole original destination, including unit, city and postal code. When the user confirms a displayed place or chooses a displayed result, use action search with their original confirmation as value, for example "yes, that is the place" or "choose the first result". The app validates the original user transcript. For show street view, show the front of the property or face the building, use action camera with value streetView. For show overhead or show the 3D map, use action camera with value earthView. Street View is recorded imagery and may be unavailable near a property; do not call it live or promise an exact front-door view. For zoom in or move closer, use action camera with value closer; for zoom out, use farther. For keep zooming in or keep zooming out, use zoomInContinuous or zoomOutContinuous. For stop zooming or stop moving the view, use stopCamera. These controls affect only the map camera, not the voice session. Zooming can continue within the available camera range; do not promise infinite zoom or imagery detail that is not available. For an explicit route to, navigate to, or directions to a destination, use action directions with that destination. This opens a route review screen; the user starts navigation with a tap. Do not claim navigation has started. For an explicit request to remember or save this place, address, building or location, use action savePlace. All ordinary memory commands still use remember_in_brain. Relay the returned answer and its scope/source limits accurately. Never describe map imagery as live video or invent a location, camera feed, date, population, mayor, crime statistic or building record. If a tool fails or has no verified data, say so. Do not start or stop the voice session when opening or closing Projection Mode.';

  Map<String, dynamic> get configuration => mode.isLive
      ? {
          'type': 'session.update',
          'session': {
            'type': 'realtime',
            'reasoning': {'effort': 'low'},
            'tool_choice': 'auto',
            if (_memoryTool != null) ...{
              'tools': [_copyTool(_memoryTool!), projectionTool],
              'instructions': _instructions,
            },
            'audio': {
              'input': {
                'transcription': {
                  'model': 'gpt-transcribe',
                  'keywords': [
                    'Rici',
                    'Risi',
                    'Reese',
                    'Reece',
                    'KORLIX',
                    'Rici remember this',
                  ],
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
            'keywords': [
              'Rici',
              'Risi',
              'Reese',
              'Reece',
              'KORLIX',
              'Rici remember this',
            ],
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
    if (_rejectionCode != null) return BrainSessionAction.reject;
    final session = event['session'];
    if (session is! Map) return _reject('malformed_session');
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
    if (mode.isLive) {
      if (!_matchesModel(session['model'])) return _reject('model_mismatch');
      if (session['reasoning'] is! Map ||
          (session['reasoning'] as Map)['effort'] != 'low') {
        return _reject('reasoning_mismatch');
      }
      if (session['tool_choice'] != 'auto') {
        return _reject('tool_choice_mismatch');
      }
    }
    if (vad is! Map ||
        (vad['type'] != 'semantic_vad' && vad['type'] != 'server_vad') ||
        vad['create_response'] != mode.isLive) {
      return _reject('vad_mismatch');
    }
    if (transcription is! Map || transcription['model'] != 'gpt-transcribe') {
      return _reject('transcription_mismatch');
    }
    if (!mode.isLive) return BrainSessionAction.ready;
    if (!projectionEnabled) {
      return _hasTools(tools, const {'remember_in_brain'})
          ? BrainSessionAction.ready
          : _reject('memory_tools_mismatch');
    }
    if (_memoryTool == null) {
      // Some providers send defaults in session.created. First acknowledge the
      // server's real memory configuration, then append to that configuration.
      // Never reconstruct or replace its account-bound memory instructions.
      return _prepareProjection(session)
          ? BrainSessionAction.configure
          : _reject('missing_server_context');
    }
    if (_hasTools(tools, const {'remember_in_brain', 'control_projection'}) &&
        session['instructions'] == _instructions) {
      _projectionAcknowledged = true;
      return BrainSessionAction.ready;
    }
    if (_hasTools(tools, const {'remember_in_brain'}) &&
        _sameJson((tools as List).single, _memoryTool) &&
        session['instructions'] == _originalInstructions) {
      if (_projectionAcknowledged) return _reject('configuration_downgrade');
      if (++_earlierAcknowledgements > _maximumEarlierAcknowledgements) {
        return _reject('stale_configuration_limit');
      }
      // This acknowledges an earlier configuration, not a rejected latest
      // update. Keep the microphone muted and the existing deadline running.
      // In particular, do not resend or restart the setup timer here.
      return BrainSessionAction.none;
    }
    if (session['instructions'] != _instructions &&
        session['instructions'] != _originalInstructions) {
      return _reject('projection_context_mismatch');
    }
    return _reject('projection_tools_mismatch');
  }

  bool _prepareProjection(Map session) {
    final tools = session['tools'];
    final instructions = session['instructions'];
    if (!_hasTools(tools, const {'remember_in_brain'}) ||
        instructions is! String ||
        instructions.trim().isEmpty ||
        !_matchesModel(session['model'])) {
      return false;
    }
    _memoryTool = _copyTool((tools as List).single as Map);
    _originalInstructions = instructions;
    _instructions = '$instructions\n\n$projectionInstructions';
    return true;
  }

  BrainSessionAction _reject(String code) {
    _rejectionCode ??= code;
    return BrainSessionAction.reject;
  }

  bool _matchesModel(Object? model) =>
      model is String &&
      (model == mode.model || model.startsWith('${mode.model}-'));

  static Map<String, dynamic> _copyTool(Map tool) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(tool)) as Map);

  static bool _sameJson(Object? first, Object? second) {
    if (first is Map && second is Map) {
      return first.length == second.length &&
          first.keys.every(
            (key) =>
                second.containsKey(key) && _sameJson(first[key], second[key]),
          );
    }
    if (first is List && second is List) {
      return first.length == second.length &&
          Iterable<int>.generate(first.length)
              .every((i) => _sameJson(first[i], second[i]));
    }
    return first == second;
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
