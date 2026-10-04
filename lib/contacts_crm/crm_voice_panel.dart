import 'package:flutter/material.dart';
import 'crm_voice.dart';
import 'contacts_client.dart';

class CrmVoicePanel extends StatelessWidget {
  const CrmVoicePanel({super.key, required this.controller, this.onReview});
  final CrmVoiceController controller;
  final Future<void> Function()? onReview;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final pending = controller.pendingDraft,
          result = controller.result,
          draft = crmMap(pending?['draft']);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'K-Nova · CRM',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                controller.busy
                    ? 'Checking your contacts…'
                    : 'Find contacts, summarize follow-ups, or prepare a note or email.',
              ),
              if (result['success'] == false)
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
                Text(
                  '${pending['contact_name']} · ${pending['action'] == 'email' ? draft['subject'] : 'Contact update'}',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: controller.busy ? null : onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review in CRM'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'You review and save every draft in CRM. Voice does not send email or enable rules. Your usual LIVE CONVO allowance applies.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    },
  );
}
