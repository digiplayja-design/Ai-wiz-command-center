import 'package:flutter/material.dart';

class BookkeepingGuide extends StatelessWidget {
  const BookkeepingGuide({super.key, this.businessName});
  final String? businessName;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start your books'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              businessName == null
                  ? 'A clear path from your first business to reviewed books.'
                  : 'Tools below open for $businessName. Nothing is recorded until you review and confirm.',
            ),
            for (final step in const [
              (
                'profile',
                '1. Separate each business',
                'Create a recordbook for each business. Legal structure and tax treatment are separate choices.',
                'Business profile',
              ),
              (
                'ledger',
                '2. Set your starting position',
                'Name your cash accounts. Review opening balances and the cutover date before adding later activity.',
                'Accounts & journals',
              ),
              (
                'entry',
                '3. Record money in and out',
                'Use income and expense entries for operating cash activity. Owner funding, borrowing, principal repayments, assets and transfers belong in journals.',
                'Record an entry',
              ),
              (
                'receipts',
                '4. Keep the original evidence',
                'Upload original receipts privately. KORLIX can suggest fields; verify them before saving. Attach supporting documents to a saved journal from Accounts & journals. Corrections preserve file and association history.',
                'Receipt inbox',
              ),
              (
                'mileage',
                '5. Record business travel',
                'Add each trip’s date, purpose, vehicle and distance. Mileage records do not automatically post an expense or calculate a deduction.',
                'Mileage log',
              ),
              (
                'statements',
                '6. Review your bank statement',
                'Map CSV columns, review repeated rows and partial overlaps, then confirm the import. Match the exact recorded purpose and ID. Show more candidates when needed. A reversed match needs review and a correction reason.',
                'Statement review',
              ),
              (
                'reports',
                '7. Review and export a period',
                'Review profit and loss, balance sheet and trial balance. Ledger CSVs include current receipt IDs, filenames and hashes. Original documents are downloaded separately.',
                'Reports',
              ),
              (
                'tax',
                '8. Prepare your tax organizer',
                'Bring recorded bookkeeping figures into Tax Prep and check for source changes. Organizers and exports support preparation; they do not calculate or file a tax return.',
                'Tax preparation',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(step.$3),
                    TextButton(
                      onPressed: businessName == null && step.$1 != 'profile'
                          ? null
                          : () => Navigator.pop(context, step.$1),
                      child: Text(step.$4),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              'If a save is interrupted, retry the same request or close and refresh the attempted period before entering it again. Reports cover recorded USD books; statement review does not prove complete bank reconciliation.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
