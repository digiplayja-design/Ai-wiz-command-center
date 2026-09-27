// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/widgets.dart';

int _next = 0;
Widget recordingAudio(Uri url) =>
    _RecordingAudio(key: ValueKey(url.toString()), url: url);

class _RecordingAudio extends StatefulWidget {
  const _RecordingAudio({super.key, required this.url});
  final Uri url;
  @override
  State<_RecordingAudio> createState() => _RecordingAudioState();
}

class _RecordingAudioState extends State<_RecordingAudio> {
  late final String _type;
  late final html.AudioElement _audio;
  @override
  void initState() {
    super.initState();
    _type = 'nova-recording-${_next++}';
    _audio = html.AudioElement()
      ..controls = true
      ..autoplay = false
      ..preload = 'metadata'
      ..src = widget.url.toString()
      ..style.width = '100%';
    _audio.setAttribute('aria-label', 'Meeting recording playback');
    _audio.setAttribute('playsinline', '');
    ui.platformViewRegistry.registerViewFactory(_type, (_) => _audio);
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 56, child: HtmlElementView(viewType: _type));
  @override
  void dispose() {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    _audio.remove();
    super.dispose();
  }
}
