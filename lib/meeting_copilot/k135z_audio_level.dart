import 'package:flutter/material.dart';
import 'k135z_capture_controller.dart';
import 'k135z_feedback_button.dart';

class K135zAudioLevel extends StatelessWidget {
  const K135zAudioLevel({super.key, required this.capture});
  final K135zCaptureController capture;
  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF22D8FF), green = Color(0xFF63E6A1);
    final recent = capture.audioRecent, level = capture.audioLevel;
    final color = recent ? green : cyan;
    return Container(
      key: const Key('k135z-audio-level'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF061B2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: recent ? 0.8 : 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(recent ? Icons.graphic_eq : Icons.mic_none, color: color),
          const SizedBox(width: 8),
          const Expanded(child: Text('Meeting audio level', style: TextStyle(color: Colors.white))),
          Text('${(level * 100).round()}%', style: TextStyle(color: color)),
        ]),
        const SizedBox(height: 10),
        Semantics(label: 'Incoming Zoom audio level', value: '${(level * 100).round()} percent',
          child: Row(children: List.generate(16, (i) => Expanded(child: Container(
            height: 16, margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
              color: level > i / 16 ? (i >= 14 ? const Color(0xFFFFCC66) : green)
                : const Color(0xFF203A4D)),
          ))))),
        const SizedBox(height: 8),
        Text(capture.audioMessage, key: const Key('k135z-audio-status'),
          style: TextStyle(color: color)),
        const SizedBox(height: 4),
        const Text('Measures audio received from the Zoom meeting. All speakers contribute.',
          style: TextStyle(color: Color(0xFF9BB7C8), fontSize: 12)),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: K135zFeedbackButton.outlined(
          buttonKey: const Key('k135z-check-audio'),
          onPressed: capture.canCheckAudio ? () => capture.refreshAudio() : null,
          icon: const Icon(Icons.mic_none), label: const Text('Check audio'), pendingLabel: 'Checking…',
        )),
      ]),
    );
  }
}
