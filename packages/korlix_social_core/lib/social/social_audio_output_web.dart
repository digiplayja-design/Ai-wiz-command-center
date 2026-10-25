import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:web/web.dart' as web;
import 'social_audio_output.dart';
import 'social_call_tones.dart';

@JS()
extension type _OutputDevices(JSObject _) implements JSObject {
  external JSPromise<web.MediaDeviceInfo> selectAudioOutput();
}

@JS()
extension type _AudioSession(JSObject _) implements JSObject {
  external String get type;
  external set type(String value);
}

SocialAudioOutput createSocialAudioOutput() => WebSocialAudioOutput();

class WebSocialAudioOutput extends SocialAudioOutput {
  WebSocialAudioOutput() {
    _audio.addEventListener(
      'playing',
      ((web.Event _) {
        if (closed) return;
        playing = _stream != null || ringing;
        activated = true;
        blocked = false;
        if (issue.startsWith('Tap Resume sound')) issue = '';
        changed();
      }).toJS,
    );
    _audio.addEventListener(
      'pause',
      ((web.Event _) {
        if (closed) return;
        playing = false;
        changed();
      }).toJS,
    );
  }
  // One explicit audio sink, independent of the video renderer and its hidden
  // autoplay element. Retain it across track events and user-gesture retries.
  final _audio = web.HTMLAudioElement()..autoplay = true;
  final _testAudio = web.HTMLAudioElement();
  rtc.MediaStream? _stream;
  String? _previousSession;
  int _playRevision = 0;
  Timer? _testTimer;
  static final _silence =
      'data:audio/wav;base64,${base64Encode(socialCallTone(silent: true))}';
  static final _ringTone =
      'data:audio/wav;base64,${base64Encode(socialCallTone(ringing: true))}';
  static final _testTone =
      'data:audio/wav;base64,${base64Encode(socialCallTone())}';
  _AudioSession? get _session {
    final value = web.window.navigator.getProperty<JSAny?>('audioSession'.toJS);
    return value == null ? null : _AudioSession(value as JSObject);
  }

  @override
  Future<void> prepareCapture() async {
    if (closed) return;
    try {
      final session = _session;
      if (session != null) {
        _previousSession ??= session.type;
        session.type = 'play-and-record';
      }
    } catch (_) {
      /* Optional API: normal capture remains available. */
    }
  }

  @override
  Future<void> activate() {
    if (closed) return Future.value();
    if (_stream != null || ringing) return resume();
    _audio.src = _silence;
    return _play(confirmation: false);
  }

  @override
  Future<void> setRinging(bool value) async {
    if (closed || ringing == value) return;
    ringing = value;
    if (value && _stream == null) {
      _audio.src = _ringTone;
      _audio.loop = true;
      await _play();
    } else if (!value && _stream == null) {
      _playRevision++;
      _audio.pause();
      _audio.loop = false;
      _audio.removeAttribute('src');
      playing = false;
      blocked = false;
      issue = '';
      changed();
    }
  }

  @override
  Future<void> testSound() async {
    if (closed) return;
    _testTimer?.cancel();
    _testAudio.pause();
    if (ringing && _stream == null) {
      _playRevision++;
      _audio.pause();
      playing = false;
    }
    _testAudio.src = _testTone;
    _testAudio.muted = false;
    if (canSetVolume) _testAudio.volume = volume > 0 ? volume : 1;
    try {
      await _testAudio.play().toDart.timeout(const Duration(seconds: 4));
      if (closed) return;
      testing = true;
      activated = true;
      issue = 'Playing three test tones on this device.';
      changed();
      _testTimer = Timer(const Duration(milliseconds: 1200), () {
        testing = false;
        if (issue == 'Playing three test tones on this device.') issue = '';
        if (ringing && _stream == null && !closed) unawaited(_play());
        changed();
      });
    } catch (_) {
      if (closed) return;
      _testAudio.pause();
      testing = false;
      issue =
          'Sound is blocked. Check device volume and your browser’s audio permission, then tap Test sound again.';
      changed();
    }
  }

  @override
  bool get canRouteSpeaker => false;
  @override
  bool get canTestSound => true;
  @override
  bool get canChooseOutput =>
      web.window.isSecureContext &&
      web.window.navigator.mediaDevices
          .hasProperty('selectAudioOutput'.toJS)
          .toDart &&
      _audio.hasProperty('setSinkId'.toJS).toDart;
  @override
  bool get canSetVolume {
    final n = web.window.navigator;
    return !RegExp('iPhone|iPad|iPod').hasMatch(n.userAgent) &&
        !(n.platform == 'MacIntel' && n.maxTouchPoints > 1);
  }

  @override
  String get guidance =>
      'Use your device’s volume buttons to listen louder. On iPhone or iPad, select the audio output in Control Center and check Bluetooth.';
  @override
  Future<void> attach(rtc.MediaStream stream) {
    if (closed) return Future.value();
    if (_stream != stream) {
      _stream = stream;
      ringing = false;
      _playRevision++;
      _audio.pause();
      _audio.loop = false;
      _audio.removeAttribute('src');
      _audio.srcObject = (stream as MediaStreamWeb).jsStream;
      _audio.style.display = 'none';
      web.document.body?.appendChild(_audio);
    }
    return resume();
  }

  @override
  Future<void> resume() {
    if (closed) return Future.value();
    if (_stream == null && !ringing) return activate();
    if (volume == 0) volume = 1;
    return _play();
  }

  Future<void> _play({bool confirmation = true}) async {
    if (closed) return;
    final revision = ++_playRevision;
    _audio.muted = false;
    if (canSetVolume) _audio.volume = volume;
    try {
      // The call is made before awaiting, preserving the tap's activation.
      await _audio.play().toDart.timeout(const Duration(seconds: 5));
      if (closed || revision != _playRevision) return;
      playing = confirmation;
      activated = true;
      blocked = false;
      issue = '';
    } catch (_) {
      if (closed || revision != _playRevision) return;
      playing = false;
      activated = false;
      blocked = true;
      issue = 'Tap Resume sound to allow call audio in your browser.';
    }
    changed();
  }

  @override
  Future<void> chooseOutput() async {
    if (closed || !canChooseOutput) return;
    try {
      final device = await _OutputDevices(
        web.window.navigator.mediaDevices,
      ).selectAudioOutput().toDart;
      if (closed) return;
      await _audio.setSinkId(device.deviceId).toDart;
      await _testAudio.setSinkId(device.deviceId).toDart;
      if (closed) return;
      await resume();
    } catch (_) {
      if (closed) return;
      issue =
          'Output was not changed. You can choose it again or use your device’s sound settings.';
      changed();
    }
  }

  @override
  Future<void> setVolume(double value) async {
    if (closed) return;
    volume = value.clamp(0, 1);
    if (canSetVolume) _audio.volume = volume;
    changed();
  }

  @override
  Future<void> close() async {
    closed = true;
    playing = activated = ringing = testing = false;
    _playRevision++;
    _testTimer?.cancel();
    _testAudio.pause();
    _testAudio.removeAttribute('src');
    _testAudio.remove();
    try {
      if (_previousSession != null && _session?.type == 'play-and-record') {
        _session?.type = _previousSession!;
      }
    } catch (_) {}
    _audio.pause();
    _audio.srcObject = null;
    _audio.remove();
    _stream = null;
  }
}
