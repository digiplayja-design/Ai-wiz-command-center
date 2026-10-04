import 'package:flutter/material.dart';
import 'fieldproof_report.dart';
import 'fieldproof_voice.dart';

class FieldProofVoicePanel extends StatelessWidget {
  const FieldProofVoicePanel({
    super.key,
    required this.controller,
    this.onReview,
    this.onOpen,
  });
  final FieldProofVoiceController controller;
  final Future<void> Function()? onReview, onOpen;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final result = controller.result,
          draft = fpMap(controller.pendingDraft?['draft']),
          selected = fpMap(
            result['selected'] ?? controller.context['selected'],
          );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rici · FieldProof',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Describe a job, dictate exact readings, find a work order, or prepare a follow-up list. Review drafts in FieldProof before saving.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Uses your existing LIVE CONVO allowance.',
                style: TextStyle(fontSize: 12),
              ),
              if (controller.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (result['success'] == false)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(fpText(result['message'])),
                ),
              if (draft.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'UNSAVED JOB DRAFT',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  fpText(draft['title']).isEmpty
                      ? 'New field job'
                      : fpText(draft['title']),
                ),
                Text('${draft['customer'] ?? ''} · ${draft['site'] ?? ''}'),
                if (fpText(draft['summary']).isNotEmpty)
                  Text(
                    fpText(draft['summary']),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${fpRows(draft['readings']).length} readings · ${fpRows(draft['issues']).length} follow-up items',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('fieldproof-voice-review'),
                  onPressed: controller.busy ? null : onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review in FieldProof'),
                ),
              ],
              if (controller.pendingOpen != null && draft.isEmpty)
                OutlinedButton(
                  key: const Key('fieldproof-voice-open'),
                  onPressed: controller.busy ? null : onOpen,
                  child: const Text('Open job in FieldProof'),
                ),
              for (final item
                  in (fpMap(selected['readiness'])['missing'] as List? ?? [])
                      .take(8))
                Text('• $item'),
              if (result['kind'] == 'search') ...[
                const Divider(),
                Text(
                  '${result['total'] ?? 0} matching jobs${result['has_more'] == true ? ' · showing the first 15' : ''}',
                ),
                for (final job in fpRows(result['jobs']).take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${job['title']} · ${job['customer']} · ${job['stage'] ?? 'planned'}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
