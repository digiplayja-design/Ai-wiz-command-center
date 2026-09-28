import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Listening controls never change the microphone or stop remote tracks.
abstract class SocialAudioOutput extends ChangeNotifier {
  bool blocked = false, playing = false, speaker = false, closed = false;
  double volume = 1;
  String issue = '';
  bool get canRouteSpeaker;
  bool get canChooseOutput => false;
  bool get canSetVolume => true;
  String get guidance;
  Future<void> attach(rtc.MediaStream stream);
  Future<void> resume();
  Future<void> routeSpeaker(bool enabled) async {}
  Future<void> chooseOutput() async {}
  Future<void> setVolume(double value);
  Future<void> close();
  void changed() {
    if (!closed) notifyListeners();
  }
}
