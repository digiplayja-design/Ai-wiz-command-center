import 'package:flutter/material.dart';
import 'package:korlix_pos_core/korlix_pos_core.dart';

/// Opt-in development entry. Production builds do not expose practice checkout.
const korlixPosPracticeEnabled = bool.fromEnvironment('KORLIX_POS_PRACTICE');

Future<void> openKorlixPosPractice(
  BuildContext context, {
  required Listenable sessionChanges,
}) async {
  if (!korlixPosPracticeEnabled) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PosScreen(embedded: true, sessionChanges: sessionChanges),
    ),
  );
}
