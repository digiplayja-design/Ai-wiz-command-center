// KORLIX_THIRD_PARTY_AI_CONSENT_BUILD131_V1_BEGIN

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum KorlixThirdPartyAiProvider { openAi, klingAi, musicApiAi }

extension KorlixThirdPartyAiProviderLabel on KorlixThirdPartyAiProvider {
  String get label {
    switch (this) {
      case KorlixThirdPartyAiProvider.openAi:
        return 'OpenAI';
      case KorlixThirdPartyAiProvider.klingAi:
        return 'Kling AI';
      case KorlixThirdPartyAiProvider.musicApiAi:
        return 'MusicAPI.ai';
    }
  }
}

enum KorlixThirdPartyAiDataCategory {
  typedTextAndPrompts,
  imagesAndPhotos,
  filesAndDocuments,
  voiceAudioAndTranscripts,
  agentTrainingAndMemory,
}

extension KorlixThirdPartyAiDataCategoryLabel
    on KorlixThirdPartyAiDataCategory {
  String get label {
    switch (this) {
      case KorlixThirdPartyAiDataCategory.typedTextAndPrompts:
        return 'Typed text and prompts';
      case KorlixThirdPartyAiDataCategory.imagesAndPhotos:
        return 'Images and photos';
      case KorlixThirdPartyAiDataCategory.filesAndDocuments:
        return 'Files and documents';
      case KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts:
        return 'Voice, audio, and transcripts';
      case KorlixThirdPartyAiDataCategory.agentTrainingAndMemory:
        return 'Agent training and approved memory';
    }
  }
}

class KorlixThirdPartyAiConsent {
  const KorlixThirdPartyAiConsent._();

  static const String consentNoticeVersion =
      'build131.apple-third-party-ai-consent.v1';

  static const String consentVersionKey =
      'korlix.third_party_ai_consent.version';

  static const String providersKey = 'korlix.third_party_ai_consent.providers';

  static const String dataCategoriesKey =
      'korlix.third_party_ai_consent.data_categories';

  static const String acceptedAtKey =
      'korlix.third_party_ai_consent.accepted_at';

  static final Uri privacyPolicyUri = Uri.parse(
    'https://www.korlixdeveloper.com/privacy-policy.html',
  );

  static Future<bool> ensure({
    required BuildContext context,
    required String featureName,
    required Set<KorlixThirdPartyAiProvider> providers,
    required Set<KorlixThirdPartyAiDataCategory> dataCategories,
  }) async {
    if (providers.isEmpty || dataCategories.isEmpty) {
      return false;
    }

    final preferences = await SharedPreferences.getInstance();
    final versionMatches =
        preferences.getString(consentVersionKey) == consentNoticeVersion;

    final acceptedProviders = versionMatches
        ? _readProviders(preferences)
        : <KorlixThirdPartyAiProvider>{};

    final acceptedCategories = versionMatches
        ? _readDataCategories(preferences)
        : <KorlixThirdPartyAiDataCategory>{};

    if (acceptedProviders.containsAll(providers) &&
        acceptedCategories.containsAll(dataCategories)) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    final combinedProviders = <KorlixThirdPartyAiProvider>{
      ...acceptedProviders,
      ...providers,
    };

    final combinedCategories = <KorlixThirdPartyAiDataCategory>{
      ...acceptedCategories,
      ...dataCategories,
    };

    final accepted = await _showConsentDialog(
      context: context,
      featureName: featureName,
      providers: combinedProviders,
      dataCategories: combinedCategories,
    );

    if (accepted != true) {
      return false;
    }

    final providerNames =
        combinedProviders.map((provider) => provider.name).toList()..sort();

    final categoryNames =
        combinedCategories.map((category) => category.name).toList()..sort();

    await preferences.setString(consentVersionKey, consentNoticeVersion);

    await preferences.setStringList(providersKey, providerNames);

    await preferences.setStringList(dataCategoriesKey, categoryNames);

    await preferences.setString(
      acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );

    return true;
  }

  static Future<void> revoke() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(consentVersionKey);
    await preferences.remove(providersKey);
    await preferences.remove(dataCategoriesKey);
    await preferences.remove(acceptedAtKey);
  }

  static Set<KorlixThirdPartyAiProvider> _readProviders(
    SharedPreferences preferences,
  ) {
    final stored = preferences.getStringList(providersKey) ?? const <String>[];

    return KorlixThirdPartyAiProvider.values
        .where((provider) => stored.contains(provider.name))
        .toSet();
  }

  static Set<KorlixThirdPartyAiDataCategory> _readDataCategories(
    SharedPreferences preferences,
  ) {
    final stored =
        preferences.getStringList(dataCategoriesKey) ?? const <String>[];

    return KorlixThirdPartyAiDataCategory.values
        .where((category) => stored.contains(category.name))
        .toSet();
  }

  static Future<bool?> _showConsentDialog({
    required BuildContext context,
    required String featureName,
    required Set<KorlixThirdPartyAiProvider> providers,
    required Set<KorlixThirdPartyAiDataCategory> dataCategories,
  }) {
    final providerLabels = providers.map((provider) => provider.label).toList()
      ..sort();

    final categoryLabels =
        dataCategories.map((category) => category.label).toList()..sort();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('korlix-third-party-ai-consent-dialog'),
          title: const Text('Share data with AI providers?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'To use $featureName, Korlix needs your permission '
                    'before sending the content you choose to third-party '
                    'AI providers.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Providers that may process this request:',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...providerLabels.map(_bullet),
                  const SizedBox(height: 14),
                  const Text(
                    'Content that may be sent for the requested feature:',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...categoryLabels.map(_bullet),
                  const SizedBox(height: 14),
                  const Text(
                    'The selected providers process this content to '
                    'produce the response, image, video, audio, document, '
                    'or other result you requested. Declining stops this '
                    'AI request and leaves non-AI parts of Korlix available.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your choice is stored on this device. Korlix asks '
                    'again when this notice changes or when a new provider '
                    'or data category is needed.',
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                try {
                  await launchUrl(
                    privacyPolicyUri,
                    mode: LaunchMode.platformDefault,
                  );
                } catch (_) {
                  // The consent choice remains available even if the
                  // external browser cannot be opened on this device.
                }
              },
              child: const Text('Privacy Policy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text("Don't Allow"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Allow & Continue'),
            ),
          ],
        );
      },
    );
  }

  static Widget _bullet(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('• '),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

Future<bool> ensureKorlixThirdPartyAiConsent({
  required BuildContext context,
  required String featureName,
  required Set<KorlixThirdPartyAiProvider> providers,
  required Set<KorlixThirdPartyAiDataCategory> dataCategories,
}) {
  return KorlixThirdPartyAiConsent.ensure(
    context: context,
    featureName: featureName,
    providers: providers,
    dataCategories: dataCategories,
  );
}

// KORLIX_THIRD_PARTY_AI_CONSENT_BUILD131_V1_END
