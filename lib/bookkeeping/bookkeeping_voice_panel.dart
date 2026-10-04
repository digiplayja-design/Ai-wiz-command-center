import 'package:flutter/material.dart';

import 'bookkeeping_models.dart';
import 'bookkeeping_voice.dart';

class BookkeepingVoicePanel extends StatelessWidget {
  const BookkeepingVoicePanel({
    super.key,
    required this.controller,
    required this.onReview,
    required this.onDismiss,
  });

  final BookkeepingVoiceController controller;
  final Future<void> Function()? onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.available) return const SizedBox.shrink();
      final data = controller.context, result = controller.result;
      final draft = controller.pendingDraft;
      final summary = data['summary'] as Map?;
      final color = Theme.of(context).colorScheme;
      String label(String list, String code) {
        final rows = data[list];
        if (rows is List) {
          for (final row in rows) {
            if (row is Map && row['code'] == code)
              return '${row['name']} ($code)';
          }
        }
        return code;
      }

      Widget field(String name, Object? value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('$name: $value'),
      );
      return Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KORLIX Bookkeeping',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  controller.businessName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Reporting month: ${controller.month} · USD'),
                const SizedBox(height: 10),
                const Text(
                  'Ask Rici about your recorded totals or describe an income or expense.',
                ),
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Checking your bookkeeping…'),
                ],
                if (summary != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Recorded income: ${bookkeepingMoney(summary['income_cents'])}',
                      ),
                      Text(
                        'Recorded expenses: ${bookkeepingMoney(summary['expense_cents'])}',
                      ),
                      Text(
                        'Recorded net: ${bookkeepingMoney(summary['net_cents'])}',
                      ),
                    ],
                  ),
                  if (data['from_date'] is String && data['as_of'] is String)
                    field('Period', '${data['from_date']} to ${data['as_of']}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Recorded totals are not bank balances or tax calculations.',
                  ),
                  for (final warning in (data['warnings'] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('$warning'),
                    ),
                ],
                if (result['success'] == false &&
                    result['message'] is String) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      result['message'] as String,
                      style: TextStyle(color: color.error),
                    ),
                  ),
                ],
                if (draft != null) ...[
                  const Divider(height: 28),
                  Text(
                    'Draft only · Not saved',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  field('Business', controller.businessName),
                  field(
                    'Entry type',
                    draft['kind'] == 'income' ? 'Income' : 'Expense',
                  ),
                  field('Amount', '\$${draft['amount']} USD'),
                  field('Date received / paid', draft['entry_date']),
                  field(
                    'Category',
                    label('categories', '${draft['category']}'),
                  ),
                  field(
                    'Cash account',
                    label('cash_accounts', '${draft['cash_account']}'),
                  ),
                  field('Business purpose', draft['purpose']),
                  field(
                    'Customer / vendor',
                    draft['counterparty'] == ''
                        ? 'Not provided'
                        : draft['counterparty'],
                  ),
                  field(
                    'Receipt reference',
                    draft['receipt_reference'] == ''
                        ? 'Not provided'
                        : draft['receipt_reference'],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Review entry pauses voice and opens the bookkeeping form. Check every field, then confirm the save there.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: controller.busy ? null : onReview,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review entry'),
                      ),
                      TextButton(
                        onPressed: controller.busy ? null : onDismiss,
                        child: const Text('Dismiss draft'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
