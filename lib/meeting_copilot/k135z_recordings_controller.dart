import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'k135z_capture_controller.dart';
import 'k135z_played_pcm.dart';

class K135zRecording {
  K135zRecording(Map raw)
    : id = raw['id'],
      status = raw['status'],
      createdAt = DateTime.parse(raw['createdAt']),
      durationMs = raw['durationMs'],
      byteSize = raw['byteSize'],
      meetingUuid = raw['meetingUuid'],
      endReason = raw['endReason'] {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        ![
          'recording',
          'saving',
          'ready',
          'failed',
          'deleting',
        ].contains(status) ||
        durationMs < 0 ||
        durationMs > 3600000 ||
        byteSize < 0 ||
        byteSize > 33554432 ||
        meetingUuid.isEmpty ||
        meetingUuid.length > 2048) {
      throw const FormatException('Invalid recording');
    }
  }
  final String id, status, meetingUuid;
  final String? endReason;
  final DateTime createdAt;
  final int durationMs, byteSize;
  bool get active => status == 'recording' || status == 'saving';
  String get duration {
    final seconds = durationMs ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class K135zRecordingsController extends ChangeNotifier {
  K135zRecordingsController({required this.capture, bool watch = true}) {
    capture.addListener(_captureChanged);
    if (watch)
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_dead && !busy && hasActive && capture.isCurrent())
          unawaited(refresh(automatic: true));
      });
  }
  final K135zCaptureController capture;
  Timer? _timer;
  bool _dead = false,
      _polling = false,
      busy = false,
      consent = false,
      loaded = false;
  int _epoch = 0;
  String? _consentContext, playbackId;
  bool includeNova = true, _voiceClosing = false;
  String? voiceWarning;
  final Set<_PlaybackUpload> _uploads = {};
  Uri? playbackUrl, downloadUrl;
  List<K135zRecording> recordings = const [];
  String message =
      'Record only after telling participants and getting their permission.';
  bool get hasActive => recordings.any((r) => r.active);
  bool get canStart =>
      !_dead &&
      !busy &&
      !hasActive &&
      consent &&
      capture.responseBinding != null;
  bool get available => !_dead && capture.isCurrent();

  void setIncludeNova(bool value) {
    if (!available || busy || hasActive) return;
    includeNova = value;
    notifyListeners();
  }

  K135zPcmSink? beginPlayback(void Function() flush) {
    if (!available || busy || !includeNova || _voiceClosing) return null;
    final context = capture.responseBinding?['context'];
    if (context == null) return null;
    final matches = recordings.where((r) => r.status == 'recording' &&
      r.meetingUuid == context['meetingUuid']).toList();
    if (matches.length != 1) return null;
    final upload = _PlaybackUpload(this, matches.single.id,
      Map<String, dynamic>.from(context), flush);
    _uploads.add(upload);
    upload.begin();
    return upload;
  }

  Future<void> flushVoice() async {
    _voiceClosing = true;
    final uploads = _uploads.toList();
    for (final upload in uploads) {
      upload.flush();
      upload.close();
    }
    try {
      await Future.wait(uploads.map((u) => u.done)).timeout(const Duration(seconds: 5));
    } catch (_) { _voiceFailed(); }
  }

  void _voiceFailed() {
    if (!available) return;
    _voiceClosing = true;
    voiceWarning = 'Some of Nova’s voice could not be added. Check the saved recording.';
    notifyListeners();
  }

  void setConsent(bool value) {
    if (!available || busy) return;
    consent = value;
    _consentContext = value
        ? jsonEncode(capture.responseBinding?['context'])
        : null;
    notifyListeners();
  }

  void _captureChanged() {
    if (_dead) return;
    if (!capture.isCurrent()) {
      invalidate();
      return;
    }
    if (_consentContext != jsonEncode(capture.responseBinding?['context'])) {
      consent = false;
      _consentContext = null;
    }
    notifyListeners();
  }

  void invalidate() {
    if (_dead) return;
    _epoch++;
    for (final upload in _uploads.toList()) { upload.cancel(); }
    _uploads.clear();
    voiceWarning = null;
    busy = false;
    consent = false;
    loaded = false;
    recordings = const [];
    playbackUrl = null;
    downloadUrl = null;
    playbackId = null;
    message = 'Reopen Meeting Co-Pilot from your signed-in agent.';
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    final headers = Map<String, String>.from(capture.headers());
    headers.removeWhere(
      (k, _) => ['content-type', 'x-korlix-agent-id'].contains(k.toLowerCase()),
    );
    headers['content-type'] = 'application/json';
    headers['x-korlix-agent-id'] = capture.agentId;
    final r = await capture.transport(
      method: 'POST',
      uri: capture.baseUri.resolve('/api/k135z/zoom/workspace/recordings'),
      headers: headers,
      body: body,
    );
    if (utf8.encode(r.body).length > 65536)
      throw const FormatException('Oversized recording response');
    final data = jsonDecode(r.body);
    if (r.statusCode != 200 ||
        data is! Map<String, dynamic> ||
        data['ok'] != true) {
      final code = data is Map && data['error'] is Map
          ? data['error']['code']
          : null;
      const messages = {
        'K135Z_RECORDING_LIBRARY_FULL':
            'Your recording library is full. Delete an old recording before starting another.',
        'K135Z_RECORDING_CONFLICT':
            'A recording is already active or changed. Refresh recordings.',
        'K135Z_RECORDING_NOT_LOCAL':
            'The recording is reconnecting. Refresh shortly to check its status.',
        'K135Z_RECORDING_BUSY': 'Recording is busy. Try again shortly.',
        'K135Z_RECORDING_NOT_READY': 'This recording is not ready to play yet.',
        'K135Z_RECORDING_STILL_ACTIVE':
            'Stop and save the recording before deleting it.',
        'K135Z_RECORDING_STORAGE_UNAVAILABLE':
            'Recording storage is temporarily unavailable. Refresh before retrying.',
      };
      throw StateError(
        messages[code] ??
            'The recording request could not be confirmed. Refresh before retrying.',
      );
    }
    return data;
  }

  Future<void> _run(
    Future<void> Function(int) action, {
    bool automatic = false,
  }) async {
    if (!available || busy || (automatic && _polling)) return;
    if (automatic) {
      _polling = true;
    } else {
      busy = true;
    }
    final epoch = automatic ? _epoch : ++_epoch;
    if (!automatic) notifyListeners();
    try {
      await action(epoch);
    } catch (e) {
      if (_current(epoch))
        message = e is StateError
            ? '${e.message}'
            : 'Recording unavailable. Refresh before retrying.';
    } finally {
      if (automatic) _polling = false;
      if (_current(epoch)) {
        if (!automatic) busy = false;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => available && epoch == _epoch;
  void _replace(K135zRecording r) {
    recordings = [r, ...recordings.where((other) => other.id != r.id)];
    loaded = true;
  }

  Future<void> refresh({bool automatic = false}) => _run((epoch) async {
    final data = await _request({'action': 'list'});
    if (!_current(epoch)) return;
    if (data['recordings'] is! List || (data['recordings'] as List).length > 21)
      throw const FormatException();
    recordings = (data['recordings'] as List)
        .map((r) => K135zRecording(r as Map))
        .toList();
    if (!recordings.any((r) => r.id == playbackId && r.status == 'ready')) {
      playbackId = null;
      playbackUrl = null;
      downloadUrl = null;
    }
    loaded = true;
    if (!automatic)
      message = recordings.isEmpty
          ? 'No recordings saved for this agent yet.'
          : 'Recordings refreshed.';
  }, automatic: automatic);
  Future<void> start() async {
    if (!canStart) return;
    final context = Map<String, dynamic>.from(
      capture.responseBinding!['context'],
    );
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    playbackUrl = null;
    downloadUrl = null;
    playbackId = null;
    await _run((epoch) async {
      final data = await _request({
        'action': 'start',
        'id': id,
        'context': context,
        'consent': true,
      });
      if (!_current(epoch)) return;
      final r = K135zRecording(data['recording'] as Map);
      if (r.id != id || r.meetingUuid != context['meetingUuid'])
        throw const FormatException();
      _replace(r);
      _voiceClosing = false;
      voiceWarning = null;
      consent = false;
      _consentContext = null;
      message =
          'Recording started. Stop & save when finished. Listening must stay connected.';
    });
  }

  Future<void> stop(K135zRecording r) => _run((epoch) async {
    await flushVoice();
    if (!_current(epoch)) return;
    final data = await _request({'action': 'stop', 'id': r.id});
    if (!_current(epoch)) return;
    final next = K135zRecording(data['recording'] as Map);
    if (next.id != r.id) throw const FormatException();
    _replace(next);
    message = 'Recording stopped. Saving your audio…';
  });
  static Uri _mediaUrl(dynamic raw) {
    if (raw is! String || raw.length > 8192) throw const FormatException();
    final url = Uri.parse(raw);
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.startsWith(
          '/storage/v1/object/sign/korlix-meeting-recordings/',
        ))
      throw const FormatException();
    return url;
  }

  Future<void> open(K135zRecording r) async {
    if (hasActive || r.status != 'ready') return;
    await _run((epoch) async {
      final data = await _request({'action': 'play', 'id': r.id});
      if (!_current(epoch)) return;
      final current = K135zRecording(data['recording'] as Map);
      if (current.id != r.id || current.status != 'ready')
        throw const FormatException();
      final play = _mediaUrl(data['url']),
          download = _mediaUrl(data['downloadUrl']);
      if (play.origin != download.origin) throw const FormatException();
      playbackUrl = play;
      downloadUrl = download;
      playbackId = r.id;
      message = 'Recording ready. Press Play below or download the MP3.';
    });
  }

  Future<void> remove(K135zRecording r) async {
    if (r.active) return;
    if (playbackId == r.id) {
      playbackId = null;
      playbackUrl = null;
      downloadUrl = null;
    }
    await _run((epoch) async {
      final data = await _request({'action': 'delete', 'id': r.id});
      if (!_current(epoch)) return;
      if (data['deleted'] != true) throw const FormatException();
      recordings = recordings.where((other) => other.id != r.id).toList();
      message = 'Recording deleted.';
    });
  }

  @override
  void dispose() {
    if (_dead) return;
    _timer?.cancel();
    capture.removeListener(_captureChanged);
    _dead = true;
    for (final upload in _uploads.toList()) { upload.cancel(); }
    _uploads.clear();
    _epoch++;
    playbackUrl = null;
    downloadUrl = null;
    super.dispose();
  }
}

// Voice packets are independent of the UI's busy state. They never delay Nova
// playback, never retry after losing authority, and cannot start a recording.
class _PlaybackUpload implements K135zPcmSink {
  _PlaybackUpload(this.owner, this.recordingId, this.context, this.flush);
  final K135zRecordingsController owner;
  final String recordingId;
  final Map<String, dynamic> context;
  final void Function() flush;
  final String id = List.generate(16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  Future<void> done = Future.value();
  bool _closed = false, _cancelled = false;
  int _queued = 0, _sequence = 0;
  bool get _current => !_cancelled && owner.available &&
    jsonEncode(owner.capture.responseBinding?['context']) == jsonEncode(context) &&
    owner.recordings.any((r) => r.id == recordingId && r.status == 'recording');
  @override
  bool get active => !_closed && _current;
  void begin() => _enqueue({'action': 'voice-start'});
  void _enqueue(Map<String, dynamic> body) {
    if (!_current) return;
    if (_queued >= 8) { _cancelled = true; owner._voiceFailed(); return; }
    _queued++;
    done = done.then((_) async {
      if (!_current) return;
      final data = await owner._request({
        ...body, 'id': recordingId, 'playbackId': id, 'context': context,
      });
      if (data['accepted'] != true) throw const FormatException();
    }).catchError((Object _) {
      if (_current) owner._voiceFailed();
      _cancelled = true;
    }).whenComplete(() {
      _queued--;
      if (_closed && _queued == 0) owner._uploads.remove(this);
    });
  }
  @override
  void write(Uint8List pcm) {
    if (!active || pcm.isEmpty) return;
    if (pcm.length > 16000 || pcm.length.isOdd || ++_sequence > 180) {
      _cancelled = true; owner._voiceFailed(); return;
    }
    _enqueue({'action': 'voice-chunk', 'sequence': _sequence,
      'pcm': base64Encode(pcm)});
  }
  @override
  void close() {
    _closed = true;
    if (_queued == 0) owner._uploads.remove(this);
  }
  void cancel() { _cancelled = true; close(); }
}
