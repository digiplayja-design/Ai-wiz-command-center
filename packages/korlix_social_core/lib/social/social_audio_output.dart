import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Listening controls never change the microphone or stop remote tracks.
abstract class SocialAudioOutput extends ChangeNotifier {
  bool blocked = false, playing = false, speaker = false, closed = false;
  bool activated = false, ringing = false, testing = false;
  bool get selected => canRouteSpeaker ? speaker : activated;
  double volume = 1;
  String issue = '';
  bool get canRouteSpeaker;
  bool get canChooseOutput => false;
  bool get canTestSound => false;
  bool get canSetVolume => true;
  String get guidance;

  /// Called synchronously from the call/answer button, before network awaits.
  Future<void> activate() async {}
  Future<void> prepareCapture() async {}
  Future<void> setRinging(bool value) async {
    ringing = value;
  }

  Future<void> testSound() async {}
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
