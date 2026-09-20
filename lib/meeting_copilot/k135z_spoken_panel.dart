import 'package:flutter/material.dart';

import 'k135z_spoken_replies.dart';
import 'k135z_feedback_button.dart';

class K135zSpokenPanel extends StatelessWidget {
  const K135zSpokenPanel({super.key, required this.spoken, this.onStop});
  final K135zSpokenReplies spoken;
  final VoidCallback? onStop;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: spoken,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A223A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: spoken.enabled
              ? const Color(0xFF63E6A1)
              : const Color(0xFF1A5872),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Talk to Nova',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Say “Nova, what have we decided?” She replies aloud after your question.',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enable spoken replies to let Nova answer anyone who addresses her, without reviewing each reply. '
            'Answers are AI-generated; meeting context comes from recent captions only.',
            style: TextStyle(color: Color(0xFF9CB8CA)),
          ),
          const SizedBox(height: 8),
          const Text(
            'For others to hear Nova, start Zoom screen broadcast with device audio. '
            'The meeting can see this screen. Keep this page visible.',
            style: TextStyle(color: Color(0xFF9CB8CA)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              K135zFeedbackButton.filled(
                buttonKey: const Key('nova-enable-spoken'),
                onPressed: spoken.canEnable ? spoken.enable : null,
                selected: spoken.enabled,
                activeColor: const Color(0xFF63E6A1),
                pendingLabel: 'Enabling…',
                child: Text(
                  spoken.enabled
                      ? 'Spoken replies on'
                      : 'Enable spoken replies',
                ),
              ),
              K135zFeedbackButton.outlined(
                buttonKey: const Key('nova-stop-spoken'),
                onPressed: onStop ?? () => spoken.stop(),
                child: const Text('Stop Nova'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              spoken.message,
              style: const TextStyle(color: Color(0xFF22D8FF)),
            ),
          ),
          if (spoken.answer != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                spoken.answer!,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
        ],
      ),
    ),
  );
}
