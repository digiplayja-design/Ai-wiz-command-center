import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'k135z_capture_controller.dart';
import 'k135z_response_player.dart';
import 'k135z_spoken_replies.dart';

// Reviewed updates stay explicit; spoken replies require their own session opt-in.
class K135zMeetingResponse extends ChangeNotifier {
  K135zMeetingResponse({
    required this.capture,
    required this.cancelRequest,
    K135zResponsePlayer? player,
    int Function()? milliseconds,
  }) : player = player ?? createResponsePlayer() {
    _now = milliseconds ?? (() => _clock.elapsedMilliseconds);
    spoken = K135zSpokenReplies(capture: capture, cancelRequest: cancelRequest, beforeEnable: () => stop());
    spoken.addListener(notifyListeners);
    capture.addListener(_check);
  }
  late final K135zSpokenReplies spoken;
  final K135zCaptureController capture;
  final VoidCallback cancelRequest;
  final K135zResponsePlayer player;
  final Stopwatch _clock = Stopwatch()..start();
  late final int Function() _now;
  int _epoch = 0, _expires = 0;
  bool _dead = false, busy = false, playing = false, broadcast = false;
  String? _binding, id, text;
  Uint8List? _audio;
  String message =
      'Start listening, then draft a short update from recent captions.';
  bool get available => !_dead && capture.responseBinding != null;
  bool get canDraft => available && !busy && !playing;
  bool get canPrepare =>
      available &&
      !busy &&
      !playing &&
      id != null &&
      _audio == null &&
      _now() < _expires;
  bool get canSpeak =>
      player.supported &&
      available &&
      !busy &&
      !playing &&
      broadcast &&
      _audio != null &&
      _now() < _expires;
  String? get _currentBinding => capture.responseBinding == null
      ? null
      : jsonEncode(capture.responseBinding);
  void _check() {
    if (_dead) return;
    if (_binding != null &&
        (_currentBinding != _binding || _now() >= _expires)) {
      stop(
        'Meeting permission changed or the draft expired. Draft a new update.',
      );
      return;
    }
    // Start/Stop can change button availability before a draft exists.
    if (!available && broadcast) broadcast = false;
    notifyListeners();
  }

  void setBroadcast(bool value) {
    if (_dead) return;
    if (!value && playing) {
      stop();
      return;
    }
    broadcast = value;
    notifyListeners();
  }

  bool _current(int e) =>
      !_dead &&
      e == _epoch &&
      _binding != null &&
      _currentBinding == _binding &&
      _now() < _expires;
  void _need(bool ok) {
    if (!ok) throw StateError('Response not confirmed');
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = Map<String, String>.from(capture.headers());
    headers.removeWhere(
      (k, _) => ['content-type', 'x-korlix-agent-id'].contains(k.toLowerCase()),
    );
    headers['content-type'] = 'application/json';
    headers['x-korlix-agent-id'] = capture.agentId;
    final r = await capture
        .transport(
          method: 'POST',
          uri: capture.baseUri.resolve('/api/k135z/zoom/workspace/$path'),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 35));
    _need(utf8.encode(r.body).length <= 512 * 1024);
    final decoded = jsonDecode(r.body);
    if (r.statusCode != 200) {
      const messages = {
        'K135Z_RESPONSE_NO_CAPTIONS':
            'No recent captions yet. Speak in the meeting, then draft again.',
        'K135Z_RESPONSE_LIMIT':
            'Response limit reached. Wait before drafting again.',
        'K135Z_RESPONSE_HOST_REQUIRED':
            'The current meeting host must have an active listening session.',
        'K135Z_RESPONSE_DRAFT_EXPIRED':
            'This draft expired. Draft a new update.',
        'KORLIX_AUTH_REQUIRED':
            'Reopen Meeting Copilot from your signed-in Agent Hub.',
      };
      final code = decoded is Map && decoded['error'] is Map
          ? decoded['error']['code']
          : null;
      throw _ResponseFailure(
        messages[code] ?? 'The response could not be prepared. Nothing will play. Draft again when ready.',
      );
    }
    _need(decoded is Map<String, dynamic> && decoded['ok'] == true);
    return decoded as Map<String, dynamic>;
  }

  Future<void> draft() async {
    if (!canDraft) return;
    stop();
    final binding = capture.responseBinding!;
    _binding = jsonEncode(binding);
    _expires = _now() + 120000;
    final e = ++_epoch;
    busy = true;
    message = 'Drafting a short update…';
    notifyListeners();
    try {
      final d = (await _request('response', {
        'context': binding['context'],
      }))['draft'];
      if (!_current(e)) return;
      _need(
        d is Map &&
            d['id'] is String &&
            RegExp(r'^[a-f0-9]{32}$').hasMatch(d['id']) &&
            d['text'] is String &&
            (d['text'] as String).trim().isNotEmpty &&
            (d['text'] as String).length <= 700 &&
            d['coverage'] == 'partial' &&
            d['validForMs'] == 90000 &&
            d['context'] is Map &&
            mapEquals(d['context'] as Map, binding['context'] as Map),
      );
      id = d['id'];
      text = d['text'];
      _expires = _now() + 80000;
      message = 'Review this draft. Approve it to prepare Nova’s voice; preparation is silent.';
    } catch (error) {
      if (_current(e))
        message = error is _ResponseFailure
            ? error.message
            : 'Draft unavailable. Nothing will play.';
    } finally {
      if (!_dead && e == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> prepare() async {
    if (!canPrepare) return;
    final e = ++_epoch, draftId = id!;
    final context = capture.responseBinding!['context'];
    busy = true;
    message = 'Preparing the approved words…';
    notifyListeners();
    try {
      final v = (await _request('response-voice', {
        'context': context,
        'draftId': draftId,
        'approved': true,
      }))['voice'];
      if (!_current(e)) return;
      _need(
        v is Map &&
            v['draftId'] == draftId &&
            v['context'] is Map &&
            mapEquals(v['context'] as Map, context as Map) &&
            v['mimeType'] == 'audio/mpeg' &&
            v['audio'] is String,
      );
      final bytes = base64Decode(v['audio']);
      _need(
        bytes.length >= 64 &&
            bytes.length <= 350000 &&
            ((bytes[0] == 73 && bytes[1] == 68 && bytes[2] == 51) ||
                (bytes[0] == 255 && (bytes[1] & 224) == 224)),
      );
      _audio = bytes;
      message = 'Voice prepared. Confirm Zoom screen broadcast with device audio, then tap Speak.';
    } catch (error) {
      if (_current(e)) {
        id = null;
        message = error is _ResponseFailure
            ? error.message
            : 'Voice unavailable. Draft again to retry.';
      }
    } finally {
      if (!_dead && e == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> speak() async {
    _check();
    if (!canSpeak) return;
    final e = ++_epoch, bytes = _audio!;
    _audio = null;
    playing = true;
    message = 'Nova is speaking. Zoom must be broadcasting device audio.';
    try {
      final played = player.play(bytes); // Keep the direct user gesture.
      notifyListeners();
      await played;
      if (_current(e)) message = 'Playback finished. Confirm with a participant that they heard Nova.';
    } catch (_) {
      if (_current(e))
        message = 'Playback was interrupted. Draft again when ready.';
    } finally {
      if (!_dead && e == _epoch) {
        playing = false;
        id = null;
        notifyListeners();
      }
    }
  }

  void stop([
    String feedback =
        'Nova stopped. Use Stop Share in Zoom to end the screen broadcast.',
  ]) {
    if (_dead) return;
    _epoch++;
    spoken.stop();
    cancelRequest();
    player.stop();
    _audio = null;
    id = null;
    text = null;
    _binding = null;
    busy = false;
    playing = false;
    broadcast = false;
    message = feedback;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_dead) return;
    capture.removeListener(_check);
    stop();
    _dead = true;
    spoken.removeListener(notifyListeners);
    spoken.dispose();
    _clock.stop();
    super.dispose();
  }
}

class _ResponseFailure implements Exception {
  const _ResponseFailure(this.message);
  final String message;
}
