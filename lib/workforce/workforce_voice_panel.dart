import 'package:flutter/material.dart';
import 'workforce_voice.dart';
import 'workforce_client.dart';

class WorkforceVoicePanel extends StatelessWidget {
  const WorkforceVoicePanel({
    super.key,
    required this.controller,
    this.onReview,
  });
  final WorkforceVoiceController controller;
  final Future<void> Function()? onReview;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final contextData = controller.context,
          result = controller.result,
          pending = controller.pendingDraft,
          draft = wfMap(pending?['draft']);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rici · Workforce',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                wfMap(contextData['organization'])['name']?.toString() ??
                    'Your private business workspace',
              ),
              const SizedBox(height: 8),
              Text(
                controller.busy
                    ? 'Checking your workspace…'
                    : contextData['scope']?.toString() ??
                          'Ask about your work, find a task or prepare an assignment.',
              ),
              if (result['success'] == false && !controller.busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${result['message'] ?? 'Please try again.'}'),
                ),
              if (pending != null) ...[
                const Divider(height: 28),
                const Text(
                  'UNSAVED DRAFT',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(switch (pending['action']) {
                  'task_create' => 'Task: ${draft['title']}',
                  'schedule' =>
                    'Shift: ${draft['starts_at']} → ${draft['ends_at']}',
                  _ => 'Work update: ${draft['summary']}',
                }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: controller.busy ? null : onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review in Workforce'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Voice prepares drafts. You review and save in Workforce. Your usual LIVE CONVO allowance applies.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    },
  );
}
