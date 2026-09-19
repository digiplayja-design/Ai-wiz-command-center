import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'korlix_zoom_connection_client.dart';

// Gate6N: the server owns identity, permission, revisions and capture state.
class K135zCaptureController extends ChangeNotifier {
  K135zCaptureController({required this.agentId, required this.baseUri,
    required this.headers, required this.isCurrent, required this.transport,
    required this.cancelRequests, int Function()? milliseconds, bool watch = true}) {
    _clock = milliseconds ?? (() => _stopwatch.elapsedMilliseconds);
    if (watch) _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(tick()));
  }
  final String agentId;
  final Uri baseUri;
  final Map<String, String> Function() headers;
  final bool Function() isCurrent;
  final KorlixZoomJsonTransport transport;
  final VoidCallback cancelRequests;
  final Stopwatch _stopwatch = Stopwatch()..start();
  late final int Function() _clock;
  final String _id = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  Map<String,dynamic>? _preview;
  bool _previewBusy = false, _previewFailed = false;
  int _previewPolled = 0;
  String _previewMessage = 'No captured captions loaded yet.';
  bool get canRefreshTranscript => _safe && !_previewBusy && _row?['snapshot']['context']['streamId'] != null;
  bool get _previewVisible => usable && _confirmed && !_previewFailed && _row?['pending'] == false &&
      _row?['uncertain'] == false && _preview != null && _same(_preview!['context'], _row!['snapshot']['context']);
  List<K135zTranscriptPreviewLine> get transcriptLines => !_previewVisible ? const [] :
      List.unmodifiable((_preview!['lines'] as List).map((x) => K135zTranscriptPreviewLine(
        sequence:x['sequence'] as int, speaker:x['speaker'] as String, text:x['text'] as String)));
  bool get transcriptTruncated => _previewVisible && _preview!['truncated'] == true;
  String get transcriptMessage => !usable || !_confirmed ? 'Refresh the session to view captured captions.' : _previewMessage;
  void _clearPreview() { _preview = null; _previewFailed = false; _previewPolled = 0;
    _previewMessage = 'No captured captions loaded yet.'; }
  Future<void> refreshTranscript({bool automatic = false}) async {
    if (!canRefreshTranscript || (automatic && _previewFailed)) return;
    final e = _epoch, context = Map<String,dynamic>.from(_row!['snapshot']['context']);
    _previewBusy = true; notifyListeners();
    try {
      final p = _map((await _post('transcript', {'context':context}, e))['transcript'],
          'schemaVersion context windowId revision lines truncated persisted coverage');
      _current(e); _need(_confirmed && _same(context, _row!['snapshot']['context']));
      _context(p['context']);
      _need(_same(p['context'], context) && p['schemaVersion'] == 1 &&
        p['windowId'] is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(p['windowId']) &&
        _uint(p['revision']) && p['truncated'] is bool && p['persisted'] == false && p['coverage'] == 'partial' &&
        p['lines'] is List && (p['lines'] as List).length <= 50);
      int previous = 0;
      for (final raw in p['lines'] as List) {
        final line = _map(raw, 'sequence text speaker providerTimestamp startTs endTs');
        _need(_uint(line['sequence']) && line['sequence'] > previous && line['sequence'] <= p['revision'] &&
          line['text'] is String && (line['text'] as String).trim().isNotEmpty && utf8.encode(line['text']).length <= 8192 &&
          line['speaker'] is String && utf8.encode(line['speaker']).length <= 256 &&
          _uint(line['providerTimestamp']) && _uint(line['startTs']) && _uint(line['endTs']) && line['endTs'] >= line['startTs']);
        previous = line['sequence'] as int;
      }
      if (_preview != null && _preview!['windowId'] == p['windowId']) {
        _need(p['revision'] >= _preview!['revision']);
        if (p['revision'] == _preview!['revision']) _need(_same(p, _preview));
      }
      _preview = p; _previewFailed = false;
      _previewMessage = (p['lines'] as List).isEmpty ? 'No captured captions received yet.' : 'Recent captions received from Zoom.';
    } catch (_) {
      if (!_dead && e == _epoch && _same(context, _row?['snapshot']['context'])) { _previewFailed = true;
        _previewMessage = 'Transcript preview unavailable. Tap Refresh captions to retry.'; }
    } finally {
      if (!_dead && e == _epoch) { _previewBusy = false; _previewPolled = _clock(); notifyListeners(); }
    }
  }
  Timer? _timer;
  Map<String, dynamic>? _row;
  bool _dead = false, _foreground = true, _confirmed = false, _renew = false;
  bool _busy = false, _consent = false;
  int _epoch = 0, _number = 0, _deadline = 0, _polled = 0, _renewed = 0;
  String _message = 'Select a meeting, then confirm listening consent.';
  bool get usable => !_dead && _foreground && isCurrent();
  bool get busy => _busy;
  bool get consent => _consent;
  String get message => _message;
  String? get meetingUuid => _row?['snapshot']['context']['meetingUuid'] as String?;
  int? get activeSeconds => _confirmed && usable ? (_row?['snapshot']['activeSeconds'] as int?) : null;
  String get _state => _row?['snapshot']['state'] as String? ?? '';
  bool get _safe => usable && !_busy && _confirmed && _row?['pending'] == false && _row?['uncertain'] == false;
  bool get canStart => _safe && _consent && ['ready', 'paused'].contains(_state);
  bool get canPause => _safe && _state == 'listening';
  bool get canStop => _safe && ['ready', 'paused', 'listening'].contains(_state);
  String get statusLabel {
    if (!usable || !_confirmed) return _row == null ? 'No session selected' : 'Session unconfirmed';
    if (_row!['pending'] == true || _row!['uncertain'] == true) return 'Session needs review';
    if (_state == 'listening') return _row!['captureActive'] == true && _clock() < _deadline
        ? 'Listening' : 'Capture interrupted';
    return {'ready':'Ready', 'paused':'Paused', 'stopped':'Stopped'}[_state] ?? 'Session unconfirmed';
  }
  static void _need(bool ok) { if (!ok) throw StateError('Workspace response is unconfirmed.'); }
  static Map<String, dynamic> _map(dynamic x, String keys) {
    _need(x is Map<String, dynamic>);
    final m = x as Map<String, dynamic>, expected = keys.split(' ');
    _need(m.length == expected.length && expected.every(m.containsKey)); return m;
  }
  static bool _uint(dynamic x) => x is int && x >= 0 && x <= 9007199254740991;
  static bool _text(dynamic x) => x is String && x.trim().isNotEmpty && utf8.encode(x).length <= 256;
  static bool _same(dynamic a, dynamic b) {
    if (a is List && b is List) return a.length == b.length && List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    if (a is Map && b is Map) return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    return a == b;
  }
  Map<String, dynamic> _context(dynamic x) {
    final c = _map(x, 'tenantId userId agentId sessionId meetingUuid streamId generation');
    _need(['tenantId','userId','agentId','sessionId','meetingUuid'].every((k) => _text(c[k])) &&
      (c['streamId'] == null || _text(c['streamId'])) && _uint(c['generation']) && c['generation'] > 0 &&
      c['tenantId'] == c['userId'] && c['agentId'] == agentId); return c;
  }
  Map<String, dynamic> _snapshot(dynamic x) {
    final s = _map(x, 'schemaVersion context revision state hostAuthorized listeningAuthorized activeSeconds capabilities');
    _context(s['context']);
    _need(s['schemaVersion'] == 1 && _uint(s['revision']) && _uint(s['activeSeconds']) &&
      ['ready','listening','paused','stopped'].contains(s['state']) &&
      s['hostAuthorized'] is bool && s['listeningAuthorized'] is bool &&
      _map(s['capabilities'], 'canSpeak')['canSpeak'] == false); return s;
  }
  Map<String, dynamic> _workspace(dynamic x) {
    final w = _map(x, 'snapshot authority bindingRevision authorityRevision validForMs pending uncertain captureActive');
    final s = _snapshot(w['snapshot']), a = _map(w['authority'], 'context viewerAuthorized hostAuthorized listeningAuthorized');
    _context(a['context']);
    _need(_same(s['context'], a['context']) && a['viewerAuthorized'] == true &&
      a['hostAuthorized'] is bool && a['listeningAuthorized'] is bool &&
      _uint(w['bindingRevision']) && w['bindingRevision'] == s['context']['generation'] &&
      _uint(w['authorityRevision']) && _uint(w['validForMs']) && w['validForMs'] <= 30000 &&
      w['pending'] is bool && w['uncertain'] is bool && w['captureActive'] is bool); return w;
  }
  void _current(int epoch) => _need(usable && epoch == _epoch);
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, int epoch) async {
    _current(epoch);
    final h = Map<String, String>.from(headers());
    h.removeWhere((k, _) => ['content-type','x-korlix-agent-id'].contains(k.toLowerCase()));
    h['content-type'] = 'application/json'; h['x-korlix-agent-id'] = agentId;
    final response = await transport(method:'POST', uri:baseUri.resolve('/api/k135z/zoom/workspace/$path'),
      headers:h, body:body).timeout(const Duration(seconds: 12));
    _current(epoch); _need(utf8.encode(response.body).length <= 65536);
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 409 && path == 'status' && decoded is Map &&
      decoded['ok'] == false && decoded['error'] is Map &&
      decoded['error']['code'] == 'K135Z_WORKSPACE_BINDING_MISMATCH') throw const _NoCaptureBinding();
    _need(response.statusCode == 200);
    final result = _map(decoded, path == 'command' ? 'ok reply' : path == 'transcript' ? 'ok transcript' : 'ok workspace');
    _need(result['ok'] == true); return result;
  }
  void _accept(Map<String, dynamic> row, int started, {bool newBinding = false}) {
    if (_row != null && !newBinding) {
      _need(_same(row['snapshot']['context'], _row!['snapshot']['context']) &&
        row['snapshot']['revision'] >= _row!['snapshot']['revision'] &&
        row['authorityRevision'] >= _row!['authorityRevision'] &&
        (row['snapshot']['revision'] != _row!['snapshot']['revision'] || _same(row['snapshot'], _row!['snapshot'])));
    }
    if (_row == null || !_same(row['snapshot']['context'], _row!['snapshot']['context'])) _clearPreview();
    _row = row; _deadline = started + (row['validForMs'] as int); _confirmed = true; _polled = _clock();
    if (row['pending'] == true || row['uncertain'] == true || _state != 'listening' ||
        row['captureActive'] != true || _clock() >= _deadline ||
        row['authority']['hostAuthorized'] != true || row['authority']['listeningAuthorized'] != true) _renew = false;
  }
  Future<void> _run(Future<void> Function(int) action) async {
    if (!usable || _busy) return;
    _busy = true; final e = _epoch; notifyListeners();
    try { await action(e); _current(e); }
    catch (_) {
      if (!_dead && e == _epoch) { _confirmed = false; _renew = false; _consent = false;
        _message = 'Request unconfirmed. Refresh session before continuing. No automatic restart.'; cancelRequests(); }
    } finally { if (!_dead && e == _epoch) { _busy = false; notifyListeners(); } }
  }
  Future<void> selectMeeting(String uuid) => _run((e) async {
    _need(_text(uuid)); _renew = false; _consent = false;
    Map<String, dynamic>? prior;
    final started = _clock();
    try { prior = _workspace((await _post('status', {}, e))['workspace']); }
    on _NoCaptureBinding { _need(_row == null); }
    if (prior != null && prior['snapshot']['state'] != 'stopped') {
      _accept(prior, started, newBinding:true);
      _need(prior['snapshot']['context']['meetingUuid'] == uuid);
    } else {
      final began = _clock();
      final row = _workspace((await _post('bind', {'meetingUuid':uuid,
        'expectedBindingRevision':prior?['bindingRevision'] ?? 0}, e))['workspace']);
      _need(row['snapshot']['context']['meetingUuid'] == uuid && row['snapshot']['state'] == 'ready' &&
        row['bindingRevision'] == (prior?['bindingRevision'] ?? 0) + 1 && !row['pending'] && !row['uncertain'] &&
        row['authority']['hostAuthorized'] == false && row['authority']['listeningAuthorized'] == false);
      _accept(row, began, newBinding:true);
    }
    _message = 'Session selected. Start requires explicit consent and backend host approval.';
  });
  Future<void> refresh() => _run((e) async {
    final started = _clock();
    _accept(_workspace((await _post('status', {}, e))['workspace']), started);
    _message = 'Session status confirmed by the backend.';
  });
  Future<void> setConsent(bool value) async {
    if (!usable || _busy) return;
    _consent = value;
    if (!value) {
      _renew = false;
      if (_row != null) await _run((e) async { await _permission('revoke', e); _message = 'Consent withdrawn. Refresh to confirm capture has ended.'; });
    }
    if (!_dead) notifyListeners();
  }
  Future<void> _permission(String action, int e) async {
    final before = _row!, started = _clock();
    final row = _workspace((await _post('consent', {'action':action,'context':before['snapshot']['context'],
      'bindingRevision':before['bindingRevision'],'authorityRevision':before['authorityRevision'],
      if (action == 'consent') 'listeningConsent':true}, e))['workspace']);
    _need(_same(row['snapshot'], before['snapshot']) &&
      row['authorityRevision'] == before['authorityRevision'] + (action == 'renew' ? 0 : 1));
    _accept(row, started);
    if (action != 'revoke') _need(_clock() < _deadline && row['authority']['hostAuthorized'] == true && row['authority']['listeningAuthorized'] == true);
    else _need(row['validForMs'] == 0 && row['authority']['hostAuthorized'] == false && row['authority']['listeningAuthorized'] == false);
    _renewed = _clock();
  }
  Future<void> start() async { if (canStart) await _command('start'); }
  Future<void> pause() async { if (canPause) await _command('pause'); }
  Future<void> stop() async { if (canStop) await _command('stop'); }
  Future<void> _command(String action) => _run((e) async {
    _renew = false;
    if (action == 'start') { _need(_consent); await _permission('consent', e); _current(e); _need(_consent); }
    final old = _row!['snapshot'] as Map<String, dynamic>;
    final op = {'requestId':'$_id-${++_number}', 'localEpoch':e, 'operationNumber':_number};
    final reply = _map((await _post('command', {'schemaVersion':1,'operation':op,'action':action,
      'expectedContext':old['context'],'expectedSnapshotRevision':old['revision']}, e))['reply'],
      'schemaVersion operation action outcome');
    _need(reply['schemaVersion'] == 1 && _same(reply['operation'], op) && reply['action'] == action);
    final out = _map(reply['outcome'], 'kind snapshot'); _need(out['kind'] == 'acknowledged');
    final next = _snapshot(out['snapshot']), expected = Map<String, dynamic>.from(old['context']);
    if (action == 'start' && expected['streamId'] == null) expected['streamId'] = next['context']['streamId'];
    _need(_same(expected, next['context']) && next['revision'] == old['revision'] + 1 &&
      next['activeSeconds'] >= old['activeSeconds'] && next['state'] == {'start':'listening','pause':'paused','stop':'stopped'}[action]);
    if (action == 'start') _need(next['context']['streamId'] != null && next['hostAuthorized'] == true &&
      next['listeningAuthorized'] == true && _clock() < _deadline);
    _row = {..._row!, 'snapshot':next, 'authority':{..._row!['authority'], 'context':next['context']},
      'captureActive':action == 'start'};
    _confirmed = true; _renew = action == 'start'; _polled = _clock();
    if (action != 'start') _consent = false;
    _message = '${statusLabel}. Backend acknowledged ${action == 'start' ? 'Start' : action}.';
  });
  Future<void> tick() async {
    if (_dead) return;
    if (!isCurrent()) { suspend(); return; }
    if (!usable) return;
    if (_state == 'listening' && _clock() >= _deadline) {
      _renew = false; _consent = false; _message = 'Consent expired. Capture needs confirmation.'; notifyListeners();
    }
    if (_busy || !_confirmed || _row == null) return;
    if (_renew && _consent && _clock() - _renewed >= 10000) {
      await _run((e) async { await _permission('renew', e); });
    } else if (_clock() - _polled >= 5000) { await refresh(); }
    else if (_clock() - _previewPolled >= 5000) { await refreshTranscript(automatic:true); }
  }
  void suspend() {
    if (_dead) return;
    _clearPreview(); _previewBusy = false;
    _foreground = false; _epoch++; _busy = false; _renew = false; _consent = false; _confirmed = false;
    cancelRequests(); _message = 'Capture status unconfirmed. Return and refresh; listening will not restart automatically.';
    notifyListeners();
  }
  void resume() { if (!_dead) { _foreground = true; notifyListeners(); } }
  @override
  void dispose() { if (_dead) return; _dead = true; _epoch++; _preview = null; _timer?.cancel(); cancelRequests(); _stopwatch.stop(); super.dispose(); }
}
class _NoCaptureBinding implements Exception { const _NoCaptureBinding(); }

class K135zTranscriptPreviewLine {
  const K135zTranscriptPreviewLine({required this.sequence,required this.speaker,required this.text});
  final int sequence;
  final String speaker, text;
}
