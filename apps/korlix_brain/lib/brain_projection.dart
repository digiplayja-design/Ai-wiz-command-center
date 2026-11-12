import 'dart:async';

import 'package:flutter/foundation.dart';

import 'brain_api.dart';

typedef ProjectionRequest = Future<Map<String, dynamic>> Function(
  String method,
  String path,
  Map<String, dynamic>? body,
);

/// Session-local projection state. Account credentials and map tiles never
/// enter this model or the bundled view. Native voice remains its owner.
class BrainProjection extends ChangeNotifier {
  BrainProjection({
    required this.backendUrl,
    required this.request,
    required this.onOpen,
    required this.onClose,
    required this.onStartVoice,
    required this.onStopVoice,
    required this.onSave,
    this.onPauseVoice,
    this.onResumeVoice,
    this.onDirections,
  });

  final String backendUrl;
  final ProjectionRequest request;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final Future<void> Function() onStartVoice;
  final Future<void> Function() onStopVoice;
  final Future<void> Function()? onPauseVoice;
  final Future<void> Function()? onResumeVoice;
  final void Function(String destination)? onDirections;
  final Future<bool> Function(String text, bool fromVoice) onSave;

  bool _disposed = false;
  bool _open = false;
  bool _loading = false;
  bool _rendererReady = false;
  bool _awaitingDestination = false;
  bool _continuousZoom = false;
  bool _foreground = true;
  String _rendererStatus = 'loading';
  String _room = 'command';
  String _notice = 'Say “Rici, project virtual reality” to explore together.';
  int _generation = 0;
  int _configGeneration = 0;
  int _cameraSequence = 0;
  int _voiceCommandGeneration = 0;
  int? _voiceCommandCameraSequence;
  Map<String, dynamic>? _place;
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _answer;
  Map<String, dynamic> _camera = {
    'sequence': 0,
    'operation': 'reset',
    'viewMode': 'street',
  };
  Map<String, dynamic> _lastVoiceCommand = {
    'heard': '',
    'action': '',
    'result': '',
    'status': 'idle',
  };
  static Map<String, dynamic> _emptyConfig() => {
    'rendererUrl': null,
    'mapAvailable': false,
    'geocodingAvailable': false,
    'directionsAvailable': false,
    'answersAvailable': false,
    'checking': false,
    'checkFailed': false,
  };
  Map<String, dynamic> _config = _emptyConfig();
  Map<String, dynamic> _voice = {
    'active': false,
    'phase': 'complete',
    'message': 'Microphone off',
  };
  final List<Map<String, dynamic>> _transcript = [];
  Future<void>? _configPending;
  bool _configured = false;
  final Map<String, Future<Map<String, dynamic>?>> _voiceTurns = {};

  bool get isOpen => _open;
  Map<String, dynamic> get snapshot => {
    'open': _open,
    'room': _room,
    'loading': _loading,
    'selectedPlace': _place,
    'candidates': _candidates,
    'answer': _answer,
    'notice': _notice,
    'camera': _camera,
    'config': _config,
    'voice': _voice,
    'lastVoiceCommand': Map<String, dynamic>.of(_lastVoiceCommand),
    'transcript': List<Map<String, dynamic>>.of(_transcript),
  };

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void cancelPending() {
    ++_generation;
    ++_voiceCommandGeneration;
    _voiceCommandCameraSequence = null;
    if (_lastVoiceCommand['status'] == 'running') {
      _lastVoiceCommand = {
        ..._lastVoiceCommand,
        'status': 'interrupted',
        'result': 'The pending view request was interrupted.',
      };
    }
    _loading = false;
    _stopCameraIfMoving();
    _changed();
  }

  void _stopCameraIfMoving() {
    if (!_continuousZoom) return;
    _continuousZoom = false;
    _camera = {
      ..._camera,
      'sequence': ++_cameraSequence,
      'operation': 'stopCamera',
    };
  }

  void open({String? room}) {
    if (_disposed) {
      return;
    }
    if (room == 'command' || room == 'discovery') {
      _room = room!;
    }
    if (!_open) {
      // Capabilities can change while the view is closed. A new opening owns
      // its own request; an older response must never configure this view.
      _resetConfig();
      ++_generation;
      _loading = false;
      _rendererReady = false;
      _rendererStatus = 'loading';
      _awaitingDestination = _place == null && _candidates.isEmpty;
      if (_place != null) {
        // Closing destroys the property view. Restore the selected destination
        // before a new frame receives any relative camera operation.
        _camera = {
          'sequence': ++_cameraSequence,
          'operation': 'flyTo',
          'viewMode': _camera['viewMode'] ?? 'street',
          'latitude': _place!['latitude'],
          'longitude': _place!['longitude'],
          'height': 650,
          'heading': 0,
          'pitch': -45,
        };
      }
      _open = true;
      onOpen();
    }
    _changed();
    if (_open) unawaited(_ensureConfig());
  }

  void close() {
    if (_disposed || !_open) {
      return;
    }
    _open = false;
    _awaitingDestination = false;
    _rendererReady = false;
    _rendererStatus = 'loading';
    _resetConfig();
    cancelPending();
    onClose();
  }

  /// A stop, failed connection or account teardown invalidates late lookups.
  /// Moving between rooms never touches the microphone or session meter.
  void receiveVoice(Map<String, dynamic> event) {
    if (_disposed) {
      return;
    }
    if (event['type'] == 'voice') {
      final phase = event['phase'];
      _voice = {
        'active': !{'complete', 'error', 'idle', 'paused'}.contains(phase),
        'paused': event['paused'] == true || phase == 'paused',
        'phase': phase,
        'message': event['message'],
      };
      if (_voice['active'] != true ||
          phase == 'pausing' ||
          phase == 'stopping') {
        cancelPending();
      }
      _changed();
    } else if (event['type'] == 'appLifecycle') {
      _foreground = event['active'] == true;
      if (!_foreground) {
        _stopCameraIfMoving();
        _changed();
      }
    } else if (event['type'] == 'voiceNotice' && event['message'] is String) {
      final message = _boundedText(event['message'], 1000);
      _notice = message;
      ++_voiceCommandGeneration;
      _voiceCommandCameraSequence = null;
      _lastVoiceCommand =
          {
            'transcription_failed',
            'transcription_timeout',
          }.contains(event['code'])
          ? {
              'heard': '',
              'action': 'Speech recognition',
              'result': message,
              'status': 'failed',
            }
          : {..._lastVoiceCommand, 'result': message, 'status': 'failed'};
      _changed();
    } else if (event['type'] == 'transcript' && event['text'] is String) {
      _transcript.add({
        'role': event['role'] == 'rici' ? 'rici' : 'you',
        'text': event['text'],
      });
      if (_transcript.length > 12) {
        _transcript.removeAt(0);
      }
      if (event['role'] != 'rici' && event['current'] != false) {
        final heard = _boundedText(event['text'], 2000);
        final control = _parseVoiceControl(heard);
        ++_voiceCommandGeneration;
        _voiceCommandCameraSequence = null;
        _lastVoiceCommand = {
          'heard': heard,
          'action': _controlLabel(control),
          'result': control == null
              ? 'No view command recognized. You can keep talking to Rici.'
              : 'View command recognized.',
          'status': control == null ? 'unrecognized' : 'heard',
        };
      }
      _changed();
    }
  }

  static String _boundedText(Object? value, int maximum) {
    final text = value is String ? value.trim() : '';
    return text.length <= maximum ? text : text.substring(0, maximum);
  }

  static String _controlLabel(_ProjectionVoiceControl? control) =>
      switch (control?.action) {
        'open' => 'Open Projection',
        'close' => 'Close Projection',
        'search' => 'Find destination',
        'select' => 'Confirm destination',
        'room' => 'Change room',
        'camera' => switch (control!.value) {
          'streetView' => 'Street View',
          'earthView' => 'Overhead view',
          'closer' => 'Zoom in',
          'farther' => 'Zoom out',
          'zoomInContinuous' => 'Keep zooming in',
          'zoomOutContinuous' => 'Keep zooming out',
          'stopCamera' => 'Stop zooming',
          'left' => 'Turn left',
          'right' => 'Turn right',
          _ => 'Reset view',
        },
        _ => 'Conversation',
      };

  static String _text(Object? value, int max, {bool empty = false}) {
    final text = value is String ? value.trim() : '';
    if ((!empty && text.isEmpty) || text.length > max) {
      throw const BrainApiException(
        'Please shorten the request and try again.',
      );
    }
    return text;
  }

  static bool _https(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  /// Only the dedicated renderer on the configured first-party API origin can
  /// be embedded. A compromised source result cannot become executable UI.
  String? checkedRenderer(Object? value) {
    if (value is! String || value.length > 2048) {
      return null;
    }
    final uri = Uri.tryParse(value);
    final backend = Uri.tryParse(backendUrl);
    if (!_https(uri) ||
        !_https(backend) ||
        uri!.origin != backend!.origin ||
        uri.path != '/brain-projection/earth.html' ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.toString();
  }

  void _resetConfig() {
    ++_configGeneration;
    _configPending = null;
    _configured = false;
    _config = _emptyConfig();
  }

  bool _currentConfig(int generation) =>
      !_disposed && generation == _configGeneration;

  Future<void> _ensureConfig() {
    if (_configured || _disposed) {
      return Future.value();
    }
    if (_configPending != null) {
      return _configPending!;
    }
    final generation = _configGeneration;
    _config = {..._config, 'checking': true, 'checkFailed': false};
    _notice = 'Checking address search and property imagery…';
    final pending = _loadConfig(generation).whenComplete(() {
      if (_currentConfig(generation)) {
        _configPending = null;
      }
    });
    _configPending = pending;
    _changed();
    return pending;
  }

  Future<void> _loadConfig(int generation) async {
    try {
      final data = await request('GET', '/api/brain-projection/config', null);
      if (!_currentConfig(generation)) {
        return;
      }
      final renderer = checkedRenderer(data['rendererUrl']);
      _config = {
        'rendererUrl': renderer,
        'mapAvailable': data['mapAvailable'] == true && renderer != null,
        'geocodingAvailable': data['geocodingAvailable'] == true,
        'directionsAvailable': data['directionsAvailable'] == true,
        'answersAvailable': data['answersAvailable'] == true,
        'checking': false,
        'checkFailed': false,
        if (data['answerCredits'] is num)
          'answerCredits': data['answerCredits'],
        if (data['answerCostLabel'] is String)
          'answerCostLabel': data['answerCostLabel'],
      };
      _configured = true;
      if (_config['mapAvailable'] == true &&
          _config['geocodingAvailable'] == true) {
        _notice = 'Explore recorded property imagery. Live cameras are a separate source.';
      } else if (_config['geocodingAvailable'] == true) {
        _notice = 'Property imagery is not connected yet. You can still look up and confirm an address.';
      } else if (_config['mapAvailable'] == true) {
        _notice = 'Property imagery is available. Address search is not connected yet. You can still talk to Rici.';
      } else {
        _notice = 'Address search and property imagery are not connected yet. You can still talk to Rici.';
      }
    } catch (_) {
      if (!_currentConfig(generation)) {
        return;
      }
      _config = {..._emptyConfig(), 'checkFailed': true};
      _configured = true;
      _notice = 'Could not check address search and property imagery. Close and reopen Projection to try again. You can still talk to Rici.';
    }
    _changed();
  }

  Map<String, dynamic>? _checkedPlace(Object? value, String userQuery) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    final address = value['address'];
    final lat = value['latitude'];
    final lon = value['longitude'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 256 ||
        address is! String ||
        address.isEmpty ||
        address.length > 1000 ||
        lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }
    return {
      'id': id,
      'address': address,
      'label': value['label'] is String ? value['label'] : address,
      'latitude': lat.toDouble(),
      'longitude': lon.toDouble(),
      'userQuery': userQuery,
      'provider': value['provider'] is String ? value['provider'] : 'unknown',
      'partialMatch': value['partialMatch'] == true,
    };
  }

  Map<String, dynamic> _result(String text, {bool ok = true}) => {
    'ok': ok,
    'handled': true,
    'answer': text,
  };

  Future<Map<String, dynamic>> search(String query) async {
    query = _text(query, 500);
    _stopCameraIfMoving();
    _awaitingDestination = false;
    final generation = ++_generation;
    _loading = true;
    _place = null;
    _candidates = [];
    _answer = null;
    _notice = 'Checking the destination…';
    _changed();
    try {
      await _ensureConfig();
      if (!_current(generation)) {
        return _result('That lookup was canceled.', ok: false);
      }
      if (_config['geocodingAvailable'] != true) {
        _notice = _config['checkFailed'] == true
            ? 'Could not check address search. Close and reopen Projection to try again. No destination has been selected.'
            : 'Address search is not connected yet. No destination has been selected. You can still talk to Rici.';
        return _result(_notice, ok: false);
      }
      final data = await request('POST', '/api/brain-projection/resolve', {
        'query': query,
      });
      if (!_current(generation)) {
        return _result('That lookup was canceled.', ok: false);
      }
      final raw = data['candidates'];
      _candidates = raw is List
          ? raw
                .take(5)
                .map((p) => _checkedPlace(p, query))
                .whereType<Map<String, dynamic>>()
                .toList()
          : [];
      if (_candidates.isEmpty) {
        _awaitingDestination = true;
        _notice = 'I could not verify that destination. Please check the street, city and postal code.';
      } else {
        // Always confirm a destination; even a single geocoder result can be a
        // partial or corrected address. Never silently relocate the user.
        // Keep provider-returned address text in the visual candidate cards.
        // This status also becomes a voice tool result, so it must not turn
        // Google Maps Content into synthesized speech.
        _notice = _candidates.length == 1
            ? 'I found a possible destination. Review the full address on screen. Is this the place you mean?'
            : 'I found ${_candidates.length} possible places. Choose one on screen, or say “choose the first result”.';
      }
      return _result(_notice);
    } on BrainApiException catch (error) {
      if (_current(generation)) {
        _notice = error.message;
      }
      return _result(error.message, ok: false);
    } catch (_) {
      const message =
          'The destination lookup could not finish. Please try again.';
      if (_current(generation)) {
        _notice = message;
      }
      return _result(message, ok: false);
    } finally {
      if (_current(generation)) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<Map<String, dynamic>> directions(String query) async {
    query = _text(query, 300, empty: true);
    final generation = _generation;
    await _ensureConfig();
    if (!_current(generation)) {
      return _result('That directions request was canceled.', ok: false);
    }
    if (_config['directionsAvailable'] != true || onDirections == null) {
      return _result(
        'Address routing is not enabled for this account.',
        ok: false,
      );
    }
    onDirections!(query);
    return _result(
      'Review the full address on screen and choose Apple Maps or Google Maps for directions.',
    );
  }

  Map<String, dynamic> select(String placeId) {
    final matches = _candidates.where((p) => p['id'] == placeId);
    if (matches.isEmpty) {
      throw const BrainApiException(
        'Search again and choose a current result.',
      );
    }
    ++_generation;
    _continuousZoom = false;
    _rendererReady = false;
    _rendererStatus = 'loading';
    _awaitingDestination = false;
    _loading = false;
    _place = Map<String, dynamic>.of(matches.first);
    _candidates = [];
    _answer = null;
    _camera = {
      'sequence': ++_cameraSequence,
      'operation': 'flyTo',
      'viewMode': 'street',
      'latitude': _place!['latitude'],
      'longitude': _place!['longitude'],
      'height': 650,
      'heading': 0,
      'pitch': -45,
    };
    _notice = 'The destination you confirmed is selected. Requesting recorded Street View near the property.';
    _changed();
    return _result(_notice);
  }

  Map<String, dynamic> camera(String operation) {
    if (!{
      'closer',
      'farther',
      'left',
      'right',
      'reset',
      'zoomInContinuous',
      'zoomOutContinuous',
      'stopCamera',
      'streetView',
      'earthView',
    }.contains(operation)) {
      throw const BrainApiException('Choose a supported camera control.');
    }
    if (operation == 'stopCamera') {
      _continuousZoom = false;
      _camera = {
        ..._camera,
        'sequence': ++_cameraSequence,
        'operation': operation,
      };
      _notice = 'Camera motion stopped. Our conversation can continue.';
      _changed();
      return _result(_notice);
    }
    if (!_foreground || !_open) {
      return _result('Open Projection to move the view.', ok: false);
    }
    if (_place == null) {
      return _result('Choose a destination first.', ok: false);
    }
    if (_config['mapAvailable'] != true) {
      return _result(
        _config['checking'] == true
            ? 'Property imagery is still connecting. I cannot move the view yet.'
            : _config['checkFailed'] == true
            ? 'Could not check property imagery. Close and reopen Projection to try again.'
            : 'Property imagery is not connected yet. You can still talk to Rici.',
        ok: false,
      );
    }
    if (operation == 'streetView' || operation == 'earthView') {
      // A failed or still-loading Street View must not trap the user. This
      // explicit switch is a fresh destination request, not a relative move.
      final mode = operation == 'streetView' ? 'street' : 'earth';
      _continuousZoom = false;
      _rendererReady = false;
      _rendererStatus = 'loading';
      _camera = {
        'sequence': ++_cameraSequence,
        'operation': 'flyTo',
        'viewMode': mode,
        'latitude': _place!['latitude'],
        'longitude': _place!['longitude'],
        'height': 650,
        'heading': 0,
        'pitch': -45,
      };
      _notice = mode == 'street'
          ? 'Requesting recorded Street View near the selected property.'
          : 'Requesting the recorded overhead 3D view of the selected property.';
      _changed();
      return _result(_notice);
    }
    if (!_rendererReady) {
      return _result(
        _rendererStatus == 'error'
            ? 'The property view is unavailable right now. Choose Street View or Overhead to try another view.'
            : 'The property view is still connecting. I cannot move the view yet.',
        ok: false,
      );
    }
    _camera = {
      ..._camera,
      'sequence': ++_cameraSequence,
      'operation': operation,
    };
    _continuousZoom =
        operation == 'zoomInContinuous' || operation == 'zoomOutContinuous';
    _notice = switch (operation) {
      'closer' => 'Moving closer to the selected place.',
      'farther' => 'Pulling back from the selected place.',
      'zoomInContinuous' => 'Zooming in. Say “stop zooming” to hold this view.',
      'zoomOutContinuous' =>
        'Zooming out. Say “stop zooming” to hold this view.',
      'left' => 'Rotating the view left.',
      'right' => 'Rotating the view right.',
      _ => 'Resetting the view of the selected place.',
    };
    _changed();
    return _result(_notice);
  }

  List<Map<String, dynamic>> _sources(Object? value) {
    if (value is! List) {
      return [];
    }
    final seen = <String>{};
    return value
        .take(12)
        .whereType<Map>()
        .map((item) {
          final url = item['url'];
          if (url is! String ||
              url.length > 2048 ||
              !_https(Uri.tryParse(url)) ||
              !seen.add(url)) {
            return null;
          }
          return <String, dynamic>{
            'title': item['title'] is String
                ? (item['title'] as String).substring(
                    0,
                    (item['title'] as String).length.clamp(0, 250),
                  )
                : Uri.parse(url).host,
            'url': url,
            if (item['date'] is String) 'date': item['date'],
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  bool mayOpenSource(String url) =>
      (_answer?['sources'] as List? ?? []).any(
        (s) => s is Map && s['url'] == url,
      ) &&
      _https(Uri.tryParse(url));

  Map<String, dynamic> unavailableLive() {
    const text =
        'There is no connected, permitted live camera for this place. Map and Street View imagery are recorded, not a live feed.';
    _answer = {'text': text, 'sources': <Object>[], 'isLive': false};
    _changed();
    return {..._result(text), 'isLive': false};
  }

  Map<String, dynamic> imageryAge() {
    const text =
        'An imagery capture date is not available in this view. I cannot verify how old the imagery is.';
    _answer = {
      'text': text,
      'sources': <Object>[],
      'imageryDate': null,
      'isLive': false,
    };
    _changed();
    return {..._result(text), 'imageryDate': null, 'isLive': false};
  }

  Future<Map<String, dynamic>> ask(String question) async {
    question = _text(question, 1000);
    if (RegExp(
      r'\b(live|real[ -]?time)\b.*\b(view|camera|feed|video|imagery)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return unavailableLive();
    }
    if (RegExp(
      r'\b(imagery|image|images|satellite)\b.*\b(old|age|date|taken|captured)\b|\b(how old|when)\b.*\b(imagery|image|images|satellite)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return imageryAge();
    }
    if (_place == null) {
      return _result(
        'Choose and confirm a destination before asking about the place.',
        ok: false,
      );
    }
    final place = Map<String, dynamic>.of(_place!);
    final generation = ++_generation;
    _loading = true;
    _answer = null;
    _notice = 'Checking sources for the selected place…';
    _changed();
    try {
      await _ensureConfig();
      if (!_current(generation)) {
        return _result('That question was canceled.', ok: false);
      }
      if (_config['answersAvailable'] != true) {
        _notice = 'Sourced place answers are not available on this server yet.';
        return _result(_notice, ok: false);
      }
      final data = await request('POST', '/api/brain-projection/answer', {
        'question': question,
        'place': place,
      });
      if (!_current(generation)) {
        return _result('That question was canceled.', ok: false);
      }
      final sources = _sources(data['sources']);
      final raw = data['text'];
      final text = sources.isEmpty
          ? 'I could not verify an answer from sources for this place. Try a more specific question.'
          : _text(raw, 14000);
      _answer = {
        'text': text,
        'sources': sources,
        if (data['scope'] is String) 'scope': data['scope'],
        if (data['date'] is String) 'date': data['date'],
        'isLive': false,
      };
      _notice = sources.isEmpty
          ? 'No verified answer available.'
          : 'Sources are attached to Rici’s answer.';
      return {
        ..._result(text, ok: sources.isNotEmpty),
        'sources': sources,
        if (_answer!['scope'] != null) 'scope': _answer!['scope'],
        if (_answer!['date'] != null) 'date': _answer!['date'],
        'isLive': false,
      };
    } on BrainApiException catch (error) {
      if (_current(generation)) {
        _notice = error.message;
      }
      return _result(error.message, ok: false);
    } catch (_) {
      const text = 'I could not verify that answer. Please try again.';
      if (_current(generation)) {
        _notice = text;
      }
      return _result(text, ok: false);
    } finally {
      if (_current(generation)) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<Map<String, dynamic>> savePlace(
    String note, {
    required bool fromVoice,
  }) async {
    if (_place == null) {
      return _result('Choose a place before saving a place note.', ok: false);
    }
    note = _text(note, 3000, empty: true);
    final place = _place!;
    // Persist the user's words and permitted place ID, not provider imagery,
    // geocoder details, generated facts, or an inferred personal preference.
    final text =
        'Place: ${place['userQuery']}\nPlace ID: ${place['id']}${note.isEmpty ? '' : '\nMy note: $note'}';
    final saved = await onSave(text, fromVoice);
    return {
      ..._result(
        saved
            ? 'Your place note is saved in My Brain.'
            : 'The place note was not saved.',
      ),
      'saved': saved,
    };
  }

  Future<Object?> dispatch(String action, Map<String, dynamic> payload) async {
    if (_disposed) {
      throw const BrainApiException('Please reopen Projection.');
    }
    switch (action) {
      case 'close':
        close();
        return null;
      case 'room':
        final room = payload['room'];
        if (room != 'command' && room != 'discovery') {
          throw const BrainApiException('Choose a projection room.');
        }
        _room = room as String;
        _changed();
        return null;
      case 'directions':
        return directions(
          _text(
            payload['query'] ?? _place?['userQuery'] ?? '',
            300,
            empty: true,
          ),
        );
      case 'pauseVoice':
        cancelPending();
        if (onPauseVoice != null) await onPauseVoice!();
        return {
          'active': _voice['active'] == true,
          'paused': _voice['paused'] == true,
        };
      case 'resumeVoice':
        if (onResumeVoice != null) await onResumeVoice!();
        return {
          'active': _voice['active'] == true,
          'paused': _voice['paused'] == true,
        };
      case 'search':
        return search(_text(payload['query'], 500));
      case 'select':
        return select(_text(payload['placeId'], 256));
      case 'camera':
        return camera(_text(payload['operation'], 20));
      case 'ask':
        return ask(_text(payload['question'], 1000));
      case 'savePlace':
        return savePlace(
          _text(payload['note'], 3000, empty: true),
          fromVoice: false,
        );
      case 'startVoice':
        if (_voice['active'] != true) {
          await onStartVoice();
        }
        return {'active': _voice['active'] == true};
      case 'stopVoice':
        cancelPending();
        await onStopVoice();
        return {'active': false};
      case 'rendererReady':
        if ((payload['sequence'] != null &&
                payload['sequence'] != _cameraSequence) ||
            (payload['viewMode'] != null &&
                payload['viewMode'] != _camera['viewMode'])) {
          return null;
        }
        final status = payload['status'] ?? 'ready';
        if (!{'ready', 'loading', 'error'}.contains(status)) {
          throw const BrainApiException('Unknown property view status.');
        }
        if (_open) {
          if (_voiceCommandCameraSequence == _cameraSequence) {
            if (status == 'error') {
              _lastVoiceCommand = {
                ..._lastVoiceCommand,
                'status': 'failed',
                'result': 'The property imagery could not load. Choose Street View or Overhead to try another view.',
              };
            } else if (status == 'ready' &&
                {
                  'Street View',
                  'Overhead view',
                }.contains(_lastVoiceCommand['action'])) {
              _lastVoiceCommand = {
                ..._lastVoiceCommand,
                'status': 'completed',
                'result': _camera['viewMode'] == 'street'
                    ? 'Recorded Street View is ready.'
                    : 'The recorded overhead view is ready.',
              };
            }
          }
          if (status != 'ready') _stopCameraIfMoving();
          _rendererStatus = status as String;
          _rendererReady = status == 'ready';
          _changed();
        }
        return null;
      case 'cameraStatus':
        if (!_open ||
            payload['sequence'] != _cameraSequence ||
            (payload['viewMode'] != null &&
                payload['viewMode'] != _camera['viewMode'])) {
          return null;
        }
        final state = payload['state'];
        final reason = payload['reason'];
        if (!{'stopped', 'limit'}.contains(state) ||
            !{
              'closest',
              'farthest',
              'stopped',
              'interrupted',
            }.contains(reason)) {
          throw const BrainApiException('Unknown camera status.');
        }
        // A later snapshot must not replay a completed continuous command.
        _continuousZoom = false;
        _camera = {..._camera, 'operation': 'stopCamera'};
        _notice = state == 'limit'
            ? reason == 'closest'
                  ? 'You have reached the closest view. More detail depends on the imagery available for this location.'
                  : 'You have reached the farthest view.'
            : 'Camera motion stopped. Our conversation can continue.';
        if (_voiceCommandCameraSequence == _cameraSequence) {
          _lastVoiceCommand = {
            ..._lastVoiceCommand,
            'status': state == 'limit' ? 'limit' : 'completed',
            'result': _notice,
          };
        }
        _changed();
        return null;
      default:
        throw const BrainApiException(
          'This Projection control is unavailable.',
        );
    }
  }

  /// Tool arguments are proposals. The original item-bound transcript is the
  /// authority for entering, navigating, and especially saving a place.
  Future<Map<String, dynamic>?> voiceTurn(
    String turnId,
    String transcript,
    Map<String, dynamic>? arguments,
  ) {
    if (_disposed) {
      return Future.value(null);
    }
    if (_voiceTurns.containsKey(turnId)) {
      return _voiceTurns[turnId]!;
    }
    final command = ++_voiceCommandGeneration;
    final control = _parseVoiceControl(transcript);
    _voiceCommandCameraSequence = null;
    _lastVoiceCommand = {
      'heard': _boundedText(transcript, 2000),
      'action': _controlLabel(control),
      'result': control == null
          ? 'Checking the request.'
          : 'Applying the view command.',
      'status': 'running',
    };
    _changed();
    final future = _observeVoiceTurn(command, transcript, arguments, control);
    _voiceTurns[turnId] = future;
    if (_voiceTurns.length > 64) {
      _voiceTurns.remove(_voiceTurns.keys.first);
    }
    return future;
  }

  Future<Map<String, dynamic>?> _observeVoiceTurn(
    int command,
    String transcript,
    Map<String, dynamic>? arguments,
    _ProjectionVoiceControl? control,
  ) async {
    try {
      final result = await _voiceTurn(transcript, arguments);
      if (_disposed || command != _voiceCommandGeneration) return result;
      if (result == null || result['handled'] != true) {
        _lastVoiceCommand = {
          ..._lastVoiceCommand,
          'status': 'unrecognized',
          'result': 'No view command recognized. You can keep talking to Rici.',
        };
      } else {
        final cameraSent = control?.action == 'camera' && result['ok'] == true;
        if (cameraSent) _voiceCommandCameraSequence = _cameraSequence;
        _lastVoiceCommand = {
          ..._lastVoiceCommand,
          'action': control == null ? 'Place request' : _controlLabel(control),
          // A camera request is not proof that provider imagery has moved.
          'status': result['ok'] == false
              ? 'failed'
              : cameraSent
              ? 'sent'
              : 'completed',
          'result': _boundedText(result['answer'], 2000),
        };
      }
      _changed();
      return result;
    } catch (_) {
      if (!_disposed && command == _voiceCommandGeneration) {
        _lastVoiceCommand = {
          ..._lastVoiceCommand,
          'status': 'failed',
          'result': 'The view command could not finish. Please try again.',
        };
        _changed();
      }
      rethrow;
    }
  }

  static const _riciVocative =
      r'(?:rici|risi|reese|reece|resee|risee|ree[ -]?see)';

  static String _originalCommand(String transcript) {
    var command = transcript.trim();
    final wrapper = RegExp(
      r'^(?:(?:hey|okay|ok|please|'
      '$_riciVocative'
      r')[,.:!?\s]+|'
      r'(?:can|could|would|will)\s+you[,.:!?\s]+|'
      r'i(?:\s+would|[\x27’]d)?\s+like\s+you\s+to\s+|'
      r'i\s+(?:want|need)\s+you\s+to\s+)',
      caseSensitive: false,
    );
    // ASR may place the name before or after a polite request. Remove only
    // bounded address-to-assistant wrappers; the explicit action parser below
    // still decides whether the remaining words authorize any movement.
    for (var i = 0; i < 8; i++) {
      final next = command.replaceFirst(wrapper, '').trimLeft();
      if (next == command) break;
      command = next;
    }
    return command;
  }

  static String _viewCommand(String command) {
    final wrapper = RegExp(
      r'[,.:!?\s]+(?:'
      '$_riciVocative'
      r'|please|for me)[.!?\s]*$',
      caseSensitive: false,
    );
    // A trailing “Rici” is a vocative for explicit view controls only. Keep
    // the original destination text intact when searching for an address.
    for (var i = 0; i < 4; i++) {
      final next = command.replaceFirst(wrapper, '').trimRight();
      if (next == command) break;
      command = next;
    }
    return command;
  }

  static String _cleanDestination(String value) => value
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .replaceFirst(RegExp(r'\s+please$', caseSensitive: false), '')
      .replaceFirst(
        RegExp(
          r'\s+(?:in|on)\s+(?:(?:the|a)\s+)?(?:3[ -]?d|vr|virtual reality|map)$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  static bool _researchOrConversation(String value) => RegExp(
    r'^(?:how|why|what|who|when|where|which|can|could|would|do|does|did|is|are|am|will|should|tell|explain|remember|save|write|read|play|stop|pause|resume|hello|hi|thanks|thank you|yes|no|that|it|i|you|we|my|your)\b|^(?:a |the )?(?:joke|story|code|email|message|photo|picture|video|fact|example|recipe|song|weather|history|news|directions)\b|\b(?:live|real[ -]?time)\b.*\b(?:view|camera|feed|video|imagery)\b|\b(?:facts?|photos?|pictures?|images?|videos?|details?|information|history|weather|news|crime|statistics|reasons?|examples?|reviews?|directions|population)\s+(?:of|about|on|for|in|near|from)\b|\b(?:show|tell|give)\s+me\b|\b(?:do not|don\x27t|don’t|never|instead)\b',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _namedPlace(String value) => RegExp(
    r'\b(?:tower|building|bridge|park|museum|airport|station|square|cathedral|stadium|theat(?:er|re)|monument|memorial|palace|castle|beach|island|harbou?r|pier|mountain|lake|avenue|street|road|boulevard|highway)\b|,\s*[a-z]',
    caseSensitive: false,
  ).hasMatch(value);

  static String? _displayAddress(
    String command, {
    bool awaitingDestination = false,
  }) {
    final show = RegExp(
      r'^show( me)?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(command);
    if (show == null) return null;
    var address = show.group(2)!.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    final in3d = RegExp(r'\s+in\s+3[ -]?d$', caseSensitive: false);
    if (show.group(1) == null && !in3d.hasMatch(address)) return null;
    final explicit3d = in3d.hasMatch(address);
    address = _cleanDestination(address);

    // “Show me” also starts research and media requests. Named landmarks and
    // places are valid destinations, but questions and media requests are not.
    // Keep the entire address, including unit, city and postal code, and never
    // substitute a model-proposed substring for these original user words.
    final street = RegExp(
      r'^\d+[a-z]?(?:[-/]\d+[a-z]?)?\s+(?:[a-z0-9.\x27’\-]+\s+){1,8}?(?:street|st|avenue|ave|road|rd|drive|dr|lane|ln|boulevard|blvd|court|ct|place|pl|terrace|ter|way|circle|cir|square|sq|parkway|pkwy|highway|hwy|route|rte|trail|trl|crescent|cres|close|row|walk)\b',
      caseSensitive: false,
    ).firstMatch(address);
    if (street == null) {
      if (address.isEmpty ||
          address.length > 500 ||
          _researchOrConversation(address) ||
          RegExp(
            r'^\d+\s+(?:facts?|photos?|pictures?|images?|videos?|buildings|houses|homes)\b|\b(?:printing|examples?)\b',
            caseSensitive: false,
          ).hasMatch(address)) {
        return null;
      }
      return explicit3d || awaitingDestination || _namedPlace(address)
          ? address
          : null;
    }
    if (RegExp(
      r'^\d+\s+(?:[a-z]+\s+){0,2}(?:facts?|photos?|pictures?|images?|videos?|details?|reasons?|examples?|reviews?|things|buildings|houses|homes)\s+(?:of|about|near|on|in|for)\b',
      caseSensitive: false,
    ).hasMatch(address)) {
      return null;
    }
    // Look for question phrasing after the street name, not isolated keywords
    // inside an address: “Live Oak Road” and “Newport News” are valid names.
    final remainder = address.substring(street.end);
    if (RegExp(
      r'\b(?:live|real[ -]?time)\b.*\b(?:view|camera|feed|video|imagery)\b|\b(?:facts?|photos?|pictures?|images?|videos?|details?|information|history|weather|news|crime|statistics|reasons?|examples?|reviews?|directions|population)\s+(?:of|about|on|for|in|near|from)\b|\b(?:show|tell|give)\s+me\b|\b(?:do not|don\x27t|don’t|never|instead)\b',
      caseSensitive: false,
    ).hasMatch(remainder)) {
      return null;
    }
    if (RegExp(
      r'^[\s.,]*(?:[\x27’]s\s+)?(?:(?:the|its)\s+)?(?:facts?|photos?|pictures?|images?|videos?|details?|information|history|weather|news|crime|statistics|reasons?|examples?|reviews?|directions|population)(?:\s+please)?$',
      caseSensitive: false,
    ).hasMatch(remainder)) {
      return null;
    }
    return address;
  }

  /// Live mode classifies the original transcript before the model starts a
  /// speculative reply. The same parser executes it, so recognition cannot
  /// authorize a broader action than the original words permit.
  bool recognizesVoiceControl(String transcript) =>
      !_disposed && _parseVoiceControl(transcript) != null;

  _ProjectionVoiceControl? _parseVoiceControl(String transcript) {
    final original = _originalCommand(transcript);
    final command = original.toLowerCase();
    final viewCommand = _viewCommand(command);
    if (original.isEmpty ||
        original.length > 2000 ||
        RegExp(r'\b(?:remember|save)\b').hasMatch(command) ||
        RegExp(
          r'\b(?:do not|don\x27t|don’t|never)\s+(?:open|close|zoom|move|go|show|switch|face|turn|rotate|pan|take|fly|start|stop|keep|continue)\b|[,;—]\s*(?:no|actually|instead)\b',
        ).hasMatch(command)) {
      return null;
    }
    if (RegExp(
      r'^(?:close|exit|leave|dismiss)\s+(?:the\s+)?(?:projection|vr|virtual reality|room)\b',
    ).hasMatch(command)) {
      return const _ProjectionVoiceControl('close');
    }
    final opening = RegExp(
      r'^(?:project|open|start|enter|show(?: me)?)\s+(?:(?:the|a|my)\s+)?(?:vr|virtual reality|projection(?: mode)?|command center|discovery theat(?:er|re))(?=[.!?, ]|$)',
      caseSensitive: false,
    ).firstMatch(original);
    if (opening != null) {
      final room = command.contains('discovery')
          ? 'discovery'
          : command.contains('command center')
          ? 'command'
          : null;
      final rest = original
          .substring(opening.end)
          .replaceFirst(RegExp(r'^[, ]*(?:and\s+)?', caseSensitive: false), '')
          .trim();
      final destination = _destinationCommand(rest, awaitingDestination: true);
      if (destination != null) {
        return _ProjectionVoiceControl('search', destination, room);
      }
      return _ProjectionVoiceControl('open', '', room);
    }
    if (_open && _candidates.isNotEmpty) {
      final confirmation = RegExp(
        r'^(?:(?:yes|yeah|correct)[,.! ]*)?(?:that(?: is|’s|\x27s) (?:it|right|correct|the (?:place|one))|use (?:that|this) (?:place|address|one)|confirm(?: (?:that|this) (?:place|address))?|yes|yeah|correct)[.! ]*$',
      ).hasMatch(viewCommand);
      final ordinal = RegExp(
        r'^(?:(?:choose|select|use|go to)\s+)?(?:the\s+)?(first|second|third|fourth|fifth|1|2|3|4|5)\s*(?:result|place|one)(?:\s+please)?[.!? ]*$|^(?:choose|select|use)\s+(?:the\s+)?(first|second|third|fourth|fifth|1|2|3|4|5)(?:\s+please)?[.!? ]*$',
      ).firstMatch(viewCommand);
      int? index;
      if (confirmation && _candidates.length == 1) index = 0;
      if (ordinal != null) {
        final value = ordinal.group(1) ?? ordinal.group(2)!;
        const ordinals = ['first', 'second', 'third', 'fourth', 'fifth'];
        index = int.tryParse(value) != null
            ? int.parse(value) - 1
            : ordinals.indexOf(value);
      }
      if (index != null && index >= 0 && index < _candidates.length) {
        return _ProjectionVoiceControl(
          'select',
          _candidates[index]['id'] as String,
        );
      }
    }
    // Directions remain owned by their existing review-and-launch flow.
    if (onDirections != null &&
        RegExp(
          r'^(?:route to|navigate to|(?:give|show) me directions to|directions to)\b',
        ).hasMatch(command)) {
      return null;
    }
    if (RegExp(
      r'^(?:(?:(?:show|open)(?: me)?|switch to)\s+(?:the\s+)?street[ -]?view|(?:show(?: me)?\s+(?:the\s+)?front(?:al)?(?:\s+view)?\s+of|face)\s+(?:the|this|that|selected)\s+(?:property|building|house))(?:\s+(?:please|for me))?[.!? ]*$',
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'streetView');
    }
    if (RegExp(
      r'^(?:(?:show|open)(?: me)?|switch to)\s+(?:the\s+)?(?:overhead(?:\s+(?:view|map))?|3[ -]?d\s+(?:map|view)|earth\s+(?:view|map))(?:\s+(?:please|for me))?[.!? ]*$',
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'earthView');
    }
    final destination = _destinationCommand(
      original,
      awaitingDestination: _awaitingDestination,
    );
    if (destination != null) {
      return _ProjectionVoiceControl('search', destination);
    }
    if (!_open) return null;
    if (RegExp(
      r'^(?:switch|change|show|enter|open)\s+(?:(?:me|rooms?|the room)\s+)?(?:to\s+)?(?:the\s+)?(?:command center|discovery theat(?:er|re))(?:[.!? ]|$)',
    ).hasMatch(viewCommand)) {
      return _ProjectionVoiceControl(
        'room',
        command.contains('discovery') ? 'discovery' : 'command',
      );
    }
    if (RegExp(
          r'^(?:(?:stop|pause|cancel)(?:\s+the)?\s+(?:zoom(?:ing)?(?:\s+(?:in|out))?|camera(?:\s+motion)?|moving(?:\s+(?:the\s+)?(?:view|camera))?)|hold(?:\s+(?:this|that|the))?\s+view)(?:\s+please)?[.!? ]*$',
        ).hasMatch(viewCommand) ||
        (_continuousZoom &&
            RegExp(r'^(?:stop|hold|that(?:\x27s|’s| is) enough)[.!? ]*$')
                .hasMatch(viewCommand))) {
      return const _ProjectionVoiceControl('camera', 'stopCamera');
    }
    if (RegExp(
      r'^(?:(?:keep|continue|start)\s+(?:zooming|moving|going)(?:\s+(?:in|closer))|zoom\s+(?:all the way\s+in|in\s+(?:continuously|all the way)))(?:\s+(?:on|to|towards?)\s+(?:the|this|that|selected|current)\s+(?:building|property|house|place|address|location|map|view))?(?:[, ]+please|\s+for me|\s+until I (?:say )?stop)?[.!? ]*$',
      caseSensitive: false,
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'zoomInContinuous');
    }
    if (RegExp(
      r'^(?:(?:keep|continue|start)\s+(?:zooming|moving|going)(?:\s+(?:out|farther|further))|zoom\s+(?:all the way\s+out|out\s+(?:continuously|all the way)))(?:\s+from\s+(?:the|this|that|selected|current)\s+(?:building|property|house|place|address|location|map|view))?(?:[, ]+please|\s+for me|\s+until I (?:say )?stop)?[.!? ]*$',
      caseSensitive: false,
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'zoomOutContinuous');
    }
    if (RegExp(
          r'^(?:(?:(?:go|move|come|get)\s+)?closer|zoom\s+in)(?:\s+(?:a little(?:\s+bit)?|more|(?:on|to|towards?)\s+(?:the|this|that|selected|current)\s+(?:building|property|house|place|address|location|map|view))){0,2}(?:[, ]+please|\s+for me)?[.!? ]*$',
        ).hasMatch(viewCommand) ||
        RegExp(
          r'^zoom\s+into\s+(?:the|this|that|selected|current)\s+(?:building|property|house|place|address|location|map|view)[.!? ]*$',
        ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'closer');
    }
    if (RegExp(
      r'^(?:(?:(?:go|move|get)\s+)?(?:farther|further)|zoom\s+out|pull\s+back)(?:\s+(?:a little(?:\s+bit)?|more|from\s+(?:the|this|that|selected|current)\s+(?:building|property|house|place|address|location|map|view))){0,2}(?:[, ]+please|\s+for me)?[.!? ]*$',
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'farther');
    }
    for (final direction in ['left', 'right']) {
      if (RegExp(
        '^(?:rotate|turn|pan)(?:\\s+(?:the\\s+)?(?:view|camera))?\\s+(?:to\\s+the\\s+)?$direction(?:\\s+please)?[.!? ]*\$',
      ).hasMatch(viewCommand)) {
        return _ProjectionVoiceControl('camera', direction);
      }
    }
    if (RegExp(
      r'^(?:reset|recenter)(?:\s+(?:the\s+)?(?:view|camera|place))?[.!? ]*$',
    ).hasMatch(viewCommand)) {
      return const _ProjectionVoiceControl('camera', 'reset');
    }
    final bare = _cleanDestination(original);
    if (_awaitingDestination &&
        bare.isNotEmpty &&
        bare.length <= 500 &&
        !_researchOrConversation(bare) &&
        (_namedPlace(bare) ||
            RegExp(r'^\d+[a-z]?\s+\S+', caseSensitive: false).hasMatch(bare))) {
      return _ProjectionVoiceControl('search', bare);
    }
    return null;
  }

  static String? _destinationCommand(
    String command, {
    required bool awaitingDestination,
  }) {
    final explicit = RegExp(
      r'^(go to|take me to|fly to|navigate to|find(?: the)?(?: address(?: of| for)?)?|search for|explore|look up)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(command);
    if (explicit != null) {
      final verb = explicit.group(1)!.toLowerCase();
      final destination = _cleanDestination(explicit.group(2)!);
      final explicitTravel = {
        'go to',
        'take me to',
        'fly to',
        'navigate to',
      }.contains(verb);
      final destinationCue =
          verb.contains('address') ||
          _namedPlace(destination) ||
          RegExp(
            r'^\d+[a-z]?\s+\S+',
            caseSensitive: false,
          ).hasMatch(destination) ||
          RegExp(
            r'\s+(?:in|on)\s+(?:3[ -]?d|vr|the map)[.!? ]*$',
            caseSensitive: false,
          ).hasMatch(explicit.group(2)!);
      if (destination.isNotEmpty &&
          destination.length <= 500 &&
          !_researchOrConversation(destination) &&
          (explicitTravel || awaitingDestination || destinationCue)) {
        return destination;
      }
      return null;
    }
    return _displayAddress(command, awaitingDestination: awaitingDestination);
  }

  Future<Map<String, dynamic>?> _voiceTurn(
    String transcript,
    Map<String, dynamic>? arguments,
  ) async {
    final text = transcript.trim();
    final lower = text.toLowerCase();
    final originalCommand = _originalCommand(text);
    final command = originalCommand.toLowerCase();
    final action = arguments?['action'];
    final placeSave = RegExp(
      r'^(?:save|remember)\s+(?:(?:this|the|selected)\s+(?:place|address|building|location)|(?:this|this note|a note)\s+(?:about|for)\s+(?:this|the|selected)\s+(?:place|address|building|location))\b',
    ).hasMatch(command);
    if (RegExp(r'\b(?:remember|save)\b').hasMatch(lower) && !placeSave) {
      return null;
    }
    final control = _parseVoiceControl(text);
    if (control != null) {
      switch (control.action) {
        case 'open':
          open(room: control.room);
          _awaitingDestination = true;
          return _result(
            'Projection is open. Say “go to” followed by an address or place.',
          );
        case 'close':
          close();
          return _result(
            'Projection is closed. Our conversation can continue.',
          );
        case 'search':
          open(room: control.room);
          return search(control.value);
        case 'select':
          return select(control.value);
        case 'camera':
          return camera(control.value);
        case 'room':
          _room = control.value;
          _changed();
          return _result(
            _room == 'command'
                ? 'Command Center is open.'
                : 'Discovery Theater is open.',
          );
      }
    }
    final route = RegExp(
      r'^(?:route to|navigate to|(?:give|show) me directions to|directions to)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(originalCommand);
    if (route != null && onDirections != null) {
      return directions(_cleanDestination(route.group(1)!));
    }
    if (!_open) return null;
    if (placeSave) {
      return savePlace(text, fromVoice: true);
    }
    if (RegExp(
      r'\b(live|real[ -]?time)\b.*\b(view|camera|feed|video|imagery)\b',
    ).hasMatch(lower)) {
      return unavailableLive();
    }
    if (RegExp(
      r'\b(imagery|image|images|satellite)\b.*\b(old|age|date|taken|captured)\b|\b(how old|when)\b.*\b(imagery|image|images|satellite)\b',
    ).hasMatch(lower)) {
      return imageryAge();
    }
    final placeQuestion = RegExp(
      r'\b(building|address|area|neighbou?rhood|mayor|population|crime|next to|nearby|this city|this place|built)\b',
    ).hasMatch(lower);
    if (placeQuestion &&
        (action == 'ask' ||
            RegExp(r'\b(what|when|who|how|where|tell me|do you know)\b')
                .hasMatch(lower))) {
      return ask(text);
    }
    if (arguments != null) {
      return _result(
        'Please say the Projection action you want, or use its on-screen controls.',
        ok: false,
      );
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    ++_configGeneration;
    _configPending = null;
    _voiceTurns.clear();
    super.dispose();
  }
}

class _ProjectionVoiceControl {
  const _ProjectionVoiceControl(this.action, [this.value = '', this.room]);
  final String action;
  final String value;
  final String? room;
}
