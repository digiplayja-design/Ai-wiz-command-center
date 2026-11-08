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
  });

  final String backendUrl;
  final ProjectionRequest request;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final Future<void> Function() onStartVoice;
  final Future<void> Function() onStopVoice;
  final Future<bool> Function(String text, bool fromVoice) onSave;

  bool _disposed = false;
  bool _open = false;
  bool _loading = false;
  bool _rendererReady = false;
  String _rendererStatus = 'loading';
  String _room = 'command';
  String _notice = 'Say “Rici, project virtual reality” to explore together.';
  int _generation = 0;
  int _cameraSequence = 0;
  Map<String, dynamic>? _place;
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _answer;
  Map<String, dynamic> _camera = {'sequence': 0, 'operation': 'reset'};
  Map<String, dynamic> _config = {
    'rendererUrl': null,
    'mapAvailable': false,
    'geocodingAvailable': false,
    'answersAvailable': false,
  };
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
    _loading = false;
    _changed();
  }

  void open({String? room}) {
    if (_disposed) {
      return;
    }
    if (room == 'command' || room == 'discovery') {
      _room = room!;
    }
    if (!_open) {
      _rendererReady = false;
      _rendererStatus = 'loading';
      if (_place != null) {
        // Closing destroys the Earth frame. Restore the selected destination
        // before a new frame receives any relative camera operation.
        _camera = {
          'sequence': ++_cameraSequence,
          'operation': 'flyTo',
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
    unawaited(_ensureConfig());
  }

  void close() {
    if (_disposed || !_open) {
      return;
    }
    _open = false;
    _rendererReady = false;
    _rendererStatus = 'loading';
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
        'active': !{'complete', 'error', 'idle'}.contains(phase),
        'phase': phase,
        'message': event['message'],
      };
      if (_voice['active'] != true) {
        cancelPending();
      }
      _changed();
    } else if (event['type'] == 'transcript' && event['text'] is String) {
      _transcript.add({
        'role': event['role'] == 'rici' ? 'rici' : 'you',
        'text': event['text'],
      });
      if (_transcript.length > 12) {
        _transcript.removeAt(0);
      }
      _changed();
    }
  }

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

  Future<void> _ensureConfig() {
    if (_configured || _disposed) {
      return Future.value();
    }
    return _configPending ??= _loadConfig().whenComplete(() {
      _configPending = null;
    });
  }

  Future<void> _loadConfig() async {
    try {
      final data = await request('GET', '/api/brain-projection/config', null);
      if (_disposed) {
        return;
      }
      final renderer = checkedRenderer(data['rendererUrl']);
      _config = {
        'rendererUrl': renderer,
        'mapAvailable': data['mapAvailable'] == true && renderer != null,
        'geocodingAvailable': data['geocodingAvailable'] == true,
        'answersAvailable': data['answersAvailable'] == true,
        if (data['answerCredits'] is num)
          'answerCredits': data['answerCredits'],
        if (data['answerCostLabel'] is String)
          'answerCostLabel': data['answerCostLabel'],
      };
      _configured = true;
      _notice = _config['mapAvailable'] == true
          ? 'Explore recorded 3D imagery. Live cameras are a separate source.'
          : 'Earth imagery is not connected yet. Your Rici conversation is available.';
    } catch (_) {
      if (_disposed) {
        return;
      }
      _notice = 'Projection services are not available on this server yet. You can still talk to Rici.';
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
        _notice = 'Address lookup is not connected yet. No destination has been selected.';
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

  Map<String, dynamic> select(String placeId) {
    final matches = _candidates.where((p) => p['id'] == placeId);
    if (matches.isEmpty) {
      throw const BrainApiException(
        'Search again and choose a current result.',
      );
    }
    ++_generation;
    _loading = false;
    _place = Map<String, dynamic>.of(matches.first);
    _candidates = [];
    _answer = null;
    _camera = {
      'sequence': ++_cameraSequence,
      'operation': 'flyTo',
      'latitude': _place!['latitude'],
      'longitude': _place!['longitude'],
      'height': 650,
      'heading': 0,
      'pitch': -45,
    };
    _notice = 'The destination you confirmed is selected on screen.';
    _changed();
    return _result(_notice);
  }

  Map<String, dynamic> camera(String operation) {
    if (!{'closer', 'farther', 'left', 'right', 'reset'}.contains(operation)) {
      throw const BrainApiException('Choose a supported camera control.');
    }
    if (_place == null) {
      return _result('Choose a destination first.', ok: false);
    }
    if (_config['mapAvailable'] != true) {
      return _result(
        'Earth imagery is not connected yet, so I cannot move the view.',
        ok: false,
      );
    }
    if (!_rendererReady) {
      return _result(
        _rendererStatus == 'error'
            ? 'The Earth view is unavailable right now, so I cannot move the view. Please reopen Projection and try again.'
            : 'The Earth view is still connecting. I cannot move the view yet.',
        ok: false,
      );
    }
    _camera = {
      ..._camera,
      'sequence': ++_cameraSequence,
      'operation': operation,
    };
    _changed();
    return _result(switch (operation) {
      'closer' => 'Moving closer to the selected place.',
      'farther' => 'Pulling back from the selected place.',
      'left' => 'Rotating the view left.',
      'right' => 'Rotating the view right.',
      _ => 'Resetting the view of the selected place.',
    });
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
        'There is no connected, permitted live camera for this place. Earth imagery is recorded, not a live feed.';
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
        final status = payload['status'] ?? 'ready';
        if (!{'ready', 'loading', 'error'}.contains(status)) {
          throw const BrainApiException('Unknown Earth view status.');
        }
        if (_open) {
          _rendererStatus = status as String;
          _rendererReady = status == 'ready';
          _changed();
        }
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
    final future = _voiceTurn(transcript, arguments);
    _voiceTurns[turnId] = future;
    if (_voiceTurns.length > 64) {
      _voiceTurns.remove(_voiceTurns.keys.first);
    }
    return future;
  }

  Future<Map<String, dynamic>?> _voiceTurn(
    String transcript,
    Map<String, dynamic>? arguments,
  ) async {
    final text = transcript.trim();
    final lower = text.toLowerCase();
    final command = lower
        .replaceFirst(
          RegExp(r'^(?:(?:hey|okay|ok)\s+)?(?:rici|risi|ree[ -]?see)[, :]?\s+'),
          '',
        )
        .replaceFirst(
          RegExp(r'^(?:please\s+|(?:can|could|would) you (?:please )?)'),
          '',
        );
    final action = arguments?['action'];
    final openIntent = RegExp(
      r'^(?:project|open|start|enter|show(?: me)?)\s+(?:(?:the|a|my)\s+)?(?:virtual reality|projection(?: mode)?|command center|discovery theat(?:er|re))(?:[.!? ]|$)',
    ).hasMatch(command);
    final closeIntent = RegExp(
      r'^(?:close|exit|leave|dismiss)\s+(?:the\s+)?(?:projection|virtual reality|room)\b',
    ).hasMatch(command);
    final placeSave = RegExp(
      r'^(?:save|remember)\s+(?:(?:this|the|selected)\s+(?:place|address|building|location)|(?:this|this note|a note)\s+(?:about|for)\s+(?:this|the|selected)\s+(?:place|address|building|location))\b',
    ).hasMatch(command);
    final ordinaryMemory =
        RegExp(r'\b(remember|save)\b').hasMatch(lower) && !placeSave;
    if (ordinaryMemory) {
      return null;
    }
    if (closeIntent) {
      close();
      return _result('Projection is closed. Our conversation can continue.');
    }
    if (openIntent) {
      open(
        room: lower.contains('discovery')
            ? 'discovery'
            : lower.contains('command center')
            ? 'command'
            : null,
      );
      return _result('Projection is open. Tell me a place to explore.');
    }
    if (_open && _candidates.isNotEmpty) {
      final confirmation = RegExp(
        r'^(?:(?:yes|yeah|correct)[,.! ]*)?(?:that(?: is|’s|\x27s) (?:right|correct|the (?:place|one))|use (?:that|this) (?:place|address|one)|confirm (?:that|this) (?:place|address)|yes)[.! ]*$',
      ).hasMatch(command);
      final ordinal = RegExp(
        r'^(?:choose|select|use|go to)\s+(?:the\s+)?(first|second|third|fourth|fifth|1|2|3|4|5)\s*(?:result|place|one)?(?:\s+please)?[.!? ]*$',
      ).firstMatch(command);
      int? index;
      if (confirmation && _candidates.length == 1) {
        index = 0;
      }
      if (ordinal != null) {
        const ordinals = ['first', 'second', 'third', 'fourth', 'fifth'];
        index = int.tryParse(ordinal.group(1)!) != null
            ? int.parse(ordinal.group(1)!) - 1
            : ordinals.indexOf(ordinal.group(1)!);
      }
      if (index != null && index >= 0 && index < _candidates.length) {
        return select(_candidates[index]['id'] as String);
      }
    }
    final destination = RegExp(
      r'^(?:go to|take me to|fly to|navigate to|find the address|search for)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(command);
    if (destination != null) {
      open();
      // Keep the whole user destination, including street, city and postal code.
      // The model cannot silently replace it with a shorter substring.
      return search(
        destination.group(1)!.replaceAll(RegExp(r'[.!?]+$'), '').trim(),
      );
    }
    if (!_open) {
      return null;
    }
    if (placeSave) {
      return savePlace(text, fromVoice: true);
    }
    if (RegExp(
      r'^(?:switch|change|show|enter|open)\s+(?:(?:me|rooms?|the room)\s+)?(?:to\s+)?(?:the\s+)?(?:command center|discovery theat(?:er|re))(?:[.!? ]|$)',
    ).hasMatch(command)) {
      _room = lower.contains('discovery') ? 'discovery' : 'command';
      _changed();
      return _result(
        _room == 'command'
            ? 'Command Center is open.'
            : 'Discovery Theater is open.',
      );
    }
    if (RegExp(r'^(?:(?:go|move|come|get)\s+)?closer\b|^zoom\s+in\b')
        .hasMatch(command)) {
      return camera('closer');
    }
    if (RegExp(
      r'^(?:(?:go|move|get)\s+)?(?:farther|further)\b|^(?:zoom\s+out|pull\s+back)\b',
    ).hasMatch(command)) {
      return camera('farther');
    }
    if (RegExp(
      r'^(?:rotate|turn|pan)(?:\s+(?:the\s+)?(?:view|camera))?\s+(?:to\s+the\s+)?left\b',
    ).hasMatch(command)) {
      return camera('left');
    }
    if (RegExp(
      r'^(?:rotate|turn|pan)(?:\s+(?:the\s+)?(?:view|camera))?\s+(?:to\s+the\s+)?right\b',
    ).hasMatch(command)) {
      return camera('right');
    }
    if (RegExp(
      r'^(?:reset|recenter)(?:\s+(?:the\s+)?(?:view|camera|place))?[.!? ]*$',
    ).hasMatch(command)) {
      return camera('reset');
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
    _voiceTurns.clear();
    super.dispose();
  }
}
