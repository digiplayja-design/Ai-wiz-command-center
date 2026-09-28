import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:web/web.dart' as web;
import 'social_audio_output.dart';

@JS()
extension type _OutputDevices(JSObject _) implements JSObject {
  external JSPromise<web.MediaDeviceInfo> selectAudioOutput();
}

SocialAudioOutput createSocialAudioOutput() => WebSocialAudioOutput();

class WebSocialAudioOutput extends SocialAudioOutput {
  // One explicit audio sink, independent of the video renderer and its hidden
  // autoplay element. Retain it across track events and user-gesture retries.
  final _audio = web.HTMLAudioElement()..autoplay = true;
  rtc.MediaStream? _stream;
  @override
  bool get canRouteSpeaker => false;
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
      _audio.srcObject = (stream as MediaStreamWeb).jsStream;
      _audio.style.display = 'none';
      web.document.body?.appendChild(_audio);
    }
    return resume();
  }

  @override
  Future<void> resume() async {
    if (closed || _stream == null) return;
    _audio.muted = false;
    if (canSetVolume) _audio.volume = volume;
    try {
      // Invoke play before the first await to preserve the tap's activation.
      await _audio.play().toDart;
      if (closed) return;
      playing = true;
      blocked = false;
      issue = '';
    } catch (_) {
      if (closed) return;
      playing = false;
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
    playing = false;
    _audio.pause();
    _audio.srcObject = null;
    _audio.remove();
    _stream = null;
  }
}
