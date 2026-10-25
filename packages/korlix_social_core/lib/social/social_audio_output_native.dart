import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'social_audio_output.dart';

SocialAudioOutput createSocialAudioOutput() => NativeSocialAudioOutput();

class NativeSocialAudioOutput extends SocialAudioOutput {
  rtc.MediaStream? _stream;
  @override
  bool get canRouteSpeaker =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  @override
  String get guidance =>
      'Use your device’s volume buttons to listen louder. Check Bluetooth if sound is playing through a headset.';
  @override
  Future<void> attach(rtc.MediaStream stream) async {
    if (closed) return;
    _stream = stream;
    await resume();
  }

  @override
  Future<void> resume() async {
    if (closed) return;
    try {
      for (final track
          in _stream?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
        await rtc.Helper.setVolume(volume, track);
      }
      if (closed) return;
      playing = _stream?.getAudioTracks().isNotEmpty == true;
      blocked = false;
      issue = '';
    } catch (_) {
      issue = 'Check your device’s sound output and volume.';
    }
    changed();
  }

  @override
  Future<void> routeSpeaker(bool enabled) async {
    if (closed || !canRouteSpeaker) return;
    try {
      await rtc.Helper.setSpeakerphoneOn(enabled);
      if (closed) return;
      speaker = enabled;
      issue = '';
    } catch (_) {
      issue = 'Could not change the speaker. Check your device’s audio output.';
    }
    changed();
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    await resume();
  }

  @override
  Future<void> close() async {
    closed = true;
    playing = false;
    _stream = null;
  }
}
