import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'korlix_zoom_connection_client.dart';
import 'k135z_capture_controller.dart';
import 'k135z_meeting_response.dart';
import 'k135z_spoken_player.dart';
import 'korlix_zoom_connection_controller.dart';

// Account discovery is read-only. Only the explicit Start listening action starts capture.
class K135zZoomLaunch {
  K135zZoomLaunch({
    required this.agentId,
    required this.backendBaseUri,
    required this.headersBuilder,
    required this.isCurrent,
  }) : _authorization = authorization(headersBuilder()) {
    if (agentId.trim() != agentId || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(agentId) ||
        backendBaseUri.scheme != 'https' || backendBaseUri.host.isEmpty ||
        backendBaseUri.userInfo.isNotEmpty || backendBaseUri.hasQuery ||
        backendBaseUri.hasFragment || !isCurrent()) {
      throw StateError('Open Copilot from the current authenticated Agent Hub.');
    }
  }

  final String agentId;
  final Uri backendBaseUri;
  final Map<String, String> Function() headersBuilder;
  final bool Function() isCurrent;
  // In-memory comparison only; never persisted, displayed, or logged.
  final String _authorization;

  static String authorization(Map<String, String> headers) {
    final values = headers.entries
        .where((e) => e.key.toLowerCase() == 'authorization')
        .map((e) => e.value).toList();
    if (values.length != 1 ||
        !RegExp(r'^Bearer [^\s]+$', caseSensitive: false).hasMatch(values.single)) {
      throw StateError('A current authenticated session is required.');
    }
    return values.single;
  }

  bool get current {
    try {
      return isCurrent() && authorization(headersBuilder()) == _authorization;
    } catch (_) {
      return false;
    }
  }
}

class K135zZoomRuntimeBinding extends ChangeNotifier {
  K135zZoomRuntimeBinding({
    required this.launch,
    KorlixZoomJsonTransport? transport,
    K135zSpokenPlayer? spokenPlayer,
    Future<bool> Function(Uri)? openUrl,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : _openUrl = openUrl ?? _openExternal, _now = now ?? DateTime.now {
    _controller = KorlixZoomConnectionController(
      client: KorlixZoomConnectionClient(
        backendBaseUri: launch.backendBaseUri,
        agentId: launch.agentId,
        stillCurrent: () => usable,
        headersBuilder: () async => launch.headersBuilder(),
        transport: transport ?? _send,
        timeout: timeout,
      ),
    );
    capture = K135zCaptureController(agentId:launch.agentId, baseUri:launch.backendBaseUri,
      headers:launch.headersBuilder, isCurrent:() => usable,
      transport:transport ?? _send, cancelRequests:_cancelCaptureRequests);
    response = K135zMeetingResponse(capture:capture, cancelRequest:_cancelResponseRequests,
      spokenPlayer:spokenPlayer);
    response.addListener(_changed);
    capture.addListener(_changed);
    _controller.addListener(_changed);
    _watch = Timer.periodic(const Duration(seconds: 1), (_) => checkContext());
    checkContext();
  }

  final K135zZoomLaunch launch;
  final Duration timeout;
  final Future<bool> Function(Uri) _openUrl;
  final DateTime Function() _now;
  final Set<http.Client> _requests = <http.Client>{};
  late final KorlixZoomConnectionController _controller;
  late final K135zCaptureController capture;
  late final K135zMeetingResponse response;
  final Set<http.Client> _responseRequests = <http.Client>{};
  void _cancelResponseRequests() {
    for (final client in _responseRequests.toList()) { client.close(); }
    _responseRequests.clear();
  }
  final Set<http.Client> _captureRequests = <http.Client>{};
  void _cancelCaptureRequests() {
    for (final client in _captureRequests.toList()) { client.close(); }
    _captureRequests.clear();
  }
  Timer? _watch;
  bool _invalid = false, _disposed = false, _opening = false;
  Uri? _authorizationUri;
  DateTime? _preparedAt;
  String? _localMessage;

  bool get usable => !_disposed && !_invalid && launch.current;
  bool get busy => usable && (_controller.isBusy || _opening);
  bool get connected => usable &&
      _controller.phase != KorlixZoomConnectionPhase.error &&
      _controller.status?.connected == true &&
      _controller.status?.requiresReauthorization == false &&
      _controller.status?.accessTokenExpired == false;
  List<KorlixZoomMeetingSummary> get meetings => connected
      ? _controller.meetings : const <KorlixZoomMeetingSummary>[];
  String? _chosenMeetingUuid;
  KorlixZoomMeetingSummary? get listeningMeeting {
    final choices = meetings.where((m) => m.uuid != null).toList();
    final preferred = _chosenMeetingUuid ?? capture.meetingUuid;
    for (final meeting in choices) {
      if (meeting.uuid == preferred) return meeting;
    }
    if (_chosenMeetingUuid != null) return null;
    return choices.length == 1 ? choices.single : null;
  }
  void chooseListeningMeeting(String uuid) {
    if (!usable || busy || capture.busy || !meetings.any((m) => m.uuid == uuid)) return;
    _chosenMeetingUuid = uuid;
    notifyListeners();
  }
  bool get canStartListening => connected && !busy && capture.usable && !capture.busy &&
      listeningMeeting != null && !(capture.statusLabel == 'Listening' &&
      capture.meetingUuid == listeningMeeting!.uuid);
  Future<void> startListening() async {
    if (!canStartListening) return;
    final uuid = listeningMeeting!.uuid!;
    await capture.listenTo(uuid);
  }
  bool get canStartNova => connected && !busy && !capture.busy && capture.usable &&
      response.spoken.player.supported && !response.spoken.busy && listeningMeeting != null &&
      (!response.spoken.enabled || capture.meetingUuid != listeningMeeting!.uuid);
  Future<void> startNova() async {
    if (!canStartNova) return;
    final uuid = listeningMeeting!.uuid!;
    await response.spoken.startWithListening(() async {
      if (capture.statusLabel != 'Listening' || capture.meetingUuid != uuid) {
        await capture.listenTo(uuid);
      }
    });
  }
  Future<void> stopListening() async {
    response.stop();
    await capture.stop();
  }
  bool get canOpenAuthorization => usable && !busy && _authorizationUri != null &&
      _preparedAt != null && _now().difference(_preparedAt!).inSeconds >= 0 &&
      _now().difference(_preparedAt!).inSeconds < 60;
  String get message {
    if (!usable) return 'Session or selected agent changed. Reopen from Agent Hub.';
    if (_localMessage != null) return _localMessage!;
    if (busy) return 'Waiting for the backend response...';
    if (_controller.phase == KorlixZoomConnectionPhase.error) {
      return 'Zoom request failed. Remote connection state is not confirmed.';
    }
    if (_controller.status == null) return 'Connection not checked. Refresh status.';
    if (_controller.status!.requiresReauthorization) return 'Zoom authorization must be renewed.';
    if (_controller.status!.accessTokenExpired) return 'Zoom access has expired. Refresh or reconnect.';
    return connected ? (capture.meetingUuid == null ? 'Zoom account connected. No meeting is being captured.' : 'Zoom account connected. See session status below.')
        : 'Backend reports no Zoom account connection.';
  }

  void _changed() {
    checkContext();
    if (!_disposed) notifyListeners();
  }

  void checkContext() {
    if (_disposed || _invalid) return;
    if (!launch.current) invalidate();
    if (_authorizationUri != null && _preparedAt != null &&
        (_now().difference(_preparedAt!).inSeconds >= 60 ||
         _now().isBefore(_preparedAt!))) {
      _authorizationUri = null;
      _preparedAt = null;
      if (!_disposed) notifyListeners();
    }
  }

  void invalidate() {
    if (_disposed || _invalid) return;
    _invalid = true;
    capture.suspend(clearConsent:true);
    _authorizationUri = null;
    _watch?.cancel();
    for (final client in _requests.toList()) { client.close(); }
    _requests.clear();
    notifyListeners();
  }

  int _pageEpoch = 0;
  void leavePage({bool keepVoiceActive = false}) {
    _pageEpoch++;
    capture.leavePage();
    response.spoken.leavePage(keepVoiceActive: keepVoiceActive);
  }
  Future<void>? _returning;
  Future<void> returnToPage() => _returning ??= _restorePage().whenComplete(() { _returning = null; });
  Future<void> _restorePage() async {
    final epoch = _pageEpoch;
    checkContext();
    if (!usable) return;
    final restored = await capture.returnToPage();
    if (!usable || epoch != _pageEpoch) return;
    if (restored) {
      await response.spoken.returnToPage();
    } else if (response.spoken.suspended) {
      response.spoken.stop('Listening changed while away. Tap Start listening, then enable voice.');
    }
  }

  Future<void> initialize() async {
    await refresh();
    if (connected && !busy) await loadMeetings();
  }

  Future<void> refresh() async {
    checkContext();
    if (!usable || busy) return;
    _localMessage = null;
    _authorizationUri = null;
    await _controller.refreshStatus();
    checkContext();
  }

  Future<void> loadMeetings() async {
    checkContext();
    if (!connected || busy) return;
    _localMessage = null;
    await _controller.loadUpcomingMeetings();
    checkContext();
  }

  Future<void> disconnect() async {
    checkContext();
    if (!usable || busy) return;
    _authorizationUri = null;
    _localMessage = null;
    capture.suspend(clearConsent:true);
    await _controller.disconnect();
    checkContext();
  }

  Future<void> prepareAuthorization() async {
    checkContext();
    if (!usable || busy) return;
    _authorizationUri = null;
    _localMessage = null;
    try {
      final uri = await _controller.beginAuthorization();
      checkContext();
      if (!usable) return;
      _authorizationUri = uri;
      _preparedAt = _now();
      _localMessage = 'Authorization prepared. Use Open Zoom authorization within 60 seconds.';
    } catch (_) {
      if (usable) _localMessage = 'Authorization could not be prepared. No connection is confirmed.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> openAuthorization() async {
    checkContext();
    if (!canOpenAuthorization) return;
    final uri = _authorizationUri!;
    _authorizationUri = null;
    _opening = true;
    try {
      // Invoke before the first await: the user's button action opens the tab.
      final launched = _openUrl(uri);
      notifyListeners();
      final ok = await launched.timeout(timeout);
      checkContext();
      if (usable) _localMessage = ok
          ? 'Finish authorization in Zoom, then return here and Refresh status.'
          : 'The browser did not open Zoom. Prepare authorization again when ready.';
    } catch (_) {
      if (usable) _localMessage = 'The authorization window could not be opened.';
    } finally {
      _opening = false;
      if (!_disposed) notifyListeners();
    }
  }

  static Future<bool> _openExternal(Uri uri) => launchUrl(
      uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');

  Future<KorlixZoomTransportResponse> _send({required String method,
      required Uri uri, required Map<String, String> headers, Object? body}) async {
    if (!usable || uri.origin != launch.backendBaseUri.origin ||
        !((<String>{'GET', 'DELETE'}.contains(method) && body == null) ||
          (method == 'POST' && body is Map<String, dynamic> &&
           <String>{'bind','status','consent','command','transcript','audio-level','response','response-voice','spoken-reply','waiting-voice'}.any((p) => uri.path == '/api/k135z/zoom/workspace/$p')))) {
      throw StateError('Zoom request binding is unavailable.');
    }
    final isResponse = uri.path.endsWith('/response') || uri.path.endsWith('/response-voice') || uri.path.endsWith('/spoken-reply') || uri.path.endsWith('/waiting-voice');
    final isStartConsent = uri.path.endsWith('/consent') &&
        body is Map<String, dynamic> && body['action'] == 'consent';
    final client = http.Client();
    if (isResponse) _responseRequests.add(client);
    _requests.add(client);
    if (method == 'POST') _captureRequests.add(client);
    Future<KorlixZoomTransportResponse> request() async {
      final req = http.Request(method, uri)..followRedirects = false;
      req.headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final response = await client.send(req);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 512 * 1024) {
          throw StateError('Zoom response exceeded the supported size.');
        }
        bytes.add(chunk);
      }
      return KorlixZoomTransportResponse(statusCode: response.statusCode,
          body: utf8.decode(bytes.takeBytes()), headers: response.headers);
    }
    try {
      return await request().timeout(uri.path.endsWith('/spoken-reply') ? const Duration(seconds:125)
          : isResponse ? const Duration(seconds:35)
          : isStartConsent ? const Duration(seconds:28) : timeout);
    } finally {
      _requests.remove(client);
      _responseRequests.remove(client);
      _captureRequests.remove(client);
      client.close();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _authorizationUri = null;
    _watch?.cancel();
    for (final client in _requests.toList()) { client.close(); }
    _requests.clear();
    capture.removeListener(_changed);
    response.removeListener(_changed);
    response.dispose();
    capture.dispose();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }
}
