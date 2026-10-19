import 'package:flutter/material.dart';

/// Returns the user's choice; the caller opens billing after the dialog closes.
/// This never starts a purchase or changes the account's entitlement.
Future<bool> showKorlixPlanPrompt({
  required BuildContext context,
  required String title,
  required String description,
  required String availability,
  bool comingSoon = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            comingSoon
                ? '$description\n\nPlanned availability: $availability'
                : '$description\n\nAvailable on: $availability\n\n'
                      'See current pricing and full plan details.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(comingSoon ? 'Close' : 'Not now'),
          ),
          if (!comingSoon)
            FilledButton(
              key: const Key('premium-view-plans'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('View plans'),
            ),
        ],
      ),
    ) ??
    false;
