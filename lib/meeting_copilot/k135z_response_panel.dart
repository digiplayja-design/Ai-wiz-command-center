import 'package:flutter/material.dart';

import 'k135z_meeting_response.dart';
import 'k135z_feedback_button.dart';

class K135zResponsePanel extends StatelessWidget {
  const K135zResponsePanel({super.key, required this.response});
  final K135zMeetingResponse response;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: response,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A223A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: response.playing
              ? const Color(0xFF63E6A1)
              : const Color(0xFF1A5872),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nova’s meeting update',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI-generated from recent captions only. Review for accuracy. Preparing a voice does not play it.',
            style: TextStyle(color: Color(0xFF9CB8CA)),
          ),
          const SizedBox(height: 12),
          if (response.text != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(
                response.text!,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
          Semantics(
            liveRegion: true,
            child: Text(
              response.message,
              style: const TextStyle(color: Color(0xFF22D8FF)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              K135zFeedbackButton.outlined(
                buttonKey: const Key('nova-draft-update'),
                onPressed: response.canDraft ? response.draft : null,
                pendingLabel: 'Drafting…',
                child: const Text('Draft short update'),
              ),
              K135zFeedbackButton.outlined(
                buttonKey: const Key('nova-approve-voice'),
                onPressed: response.canPrepare ? response.prepare : null,
                pendingLabel: 'Preparing voice…',
                child: const Text('Approve & prepare voice'),
              ),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: response.broadcast,
              onChanged: response.available && !response.busy
                  ? (v) => response.setBroadcast(v == true)
                  : null,
              title: const Text(
                'I started Zoom screen broadcast with device audio.',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'The meeting can see this screen. Keep this Chrome page open while Nova speaks.',
                style: TextStyle(color: Color(0xFF9CB8CA)),
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              K135zFeedbackButton.filled(
                buttonKey: const Key('nova-speak-update'),
                onPressed: response.canSpeak ? response.speak : null,
                selected: response.playing,
                activeColor: const Color(0xFF63E6A1),
                pendingLabel: 'Nova is speaking…',
                child: const Text('Speak approved update'),
              ),
              K135zFeedbackButton.outlined(
                buttonKey: const Key('nova-stop-response'),
                onPressed: () => response.stop(),
                child: const Text('Stop Nova'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Stop Nova silences this page. Use Stop Share in Zoom to end the broadcast.',
            style: TextStyle(color: Color(0xFF9CB8CA)),
          ),
        ],
      ),
    ),
  );
}
