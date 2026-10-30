import 'package:flutter/material.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';

import 'magic_client.dart';
import 'magic_screen.dart';
import 'magic_theme.dart';

Future<void> openMagicCamera(
  BuildContext context, {
  required String backendBaseUrl,
  required Map<String, String> Function() headersBuilder,
  Listenable? sessionChanges,
  VoidCallback? onUpgrade,
}) async {
  final client = MagicClient(
    backendUrl: backendBaseUrl,
    headers: headersBuilder,
    sessionChanges: sessionChanges,
  );
  try {
    final route = MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: magicTheme(),
        child: MagicScreen(
          client: client,
          onUpgrade: onUpgrade,
          ensureConsent: () => ensureKorlixThirdPartyAiConsent(
            context: context,
            featureName: 'Korlix Magic Camera',
            providers: const {KorlixThirdPartyAiProvider.openAi},
            dataCategories: const {
              KorlixThirdPartyAiDataCategory.imagesAndPhotos,
              KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            },
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  } finally {
    client.dispose();
  }
}
