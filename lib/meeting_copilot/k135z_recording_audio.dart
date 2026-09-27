import 'package:flutter/widgets.dart';
import 'k135z_recording_audio_stub.dart'
    if (dart.library.html) 'k135z_recording_audio_web.dart'
    as platform;

Widget recordingAudio(Uri url) => platform.recordingAudio(url);
