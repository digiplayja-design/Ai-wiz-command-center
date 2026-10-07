// KORLIX_THIRD_PARTY_AI_CONSENT_BUILD131_V1_BEGIN

import 'dart:convert';

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
  bookkeepingRecords,
  musicDraftsAndLibrary,
  fieldProofRecords,
  workforceRecords,
  crmRecords,
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
      case KorlixThirdPartyAiDataCategory.bookkeepingRecords:
        return 'Selected business bookkeeping records';
      case KorlixThirdPartyAiDataCategory.crmRecords:
        return 'Your CRM contact details, notes and follow-up records';
      case KorlixThirdPartyAiDataCategory.workforceRecords:
        return 'Authorized company, team, assignment, schedule and work-update records';
      case KorlixThirdPartyAiDataCategory.fieldProofRecords:
        return 'Private field-job details, readings, checklists, and evidence notes';
      case KorlixThirdPartyAiDataCategory.musicDraftsAndLibrary:
        return 'Music drafts, lyrics, and selected library details';
    }
  }
}

class KorlixThirdPartyAiConsent {
  const KorlixThirdPartyAiConsent._();

  static const String consentNoticeVersion =
      'build131.apple-third-party-ai-consent.v2';

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

  static String? _accountScope;
  static int _sessionRevision = 0;
  static Future<void>? _pending;
  static VoidCallback? _dismissActiveDialog;
  static final Set<String> _untrustedRecords = {};

  /// Call whenever the authenticated session is replaced or cleared. The scope
  /// must identify an account (for example issuer + subject), never a bearer
  /// token. A missing identity permits one-request consent only, without reuse.
  static void setAccountScope(String? scope) {
    _accountScope = scope == null || scope.trim().isEmpty ? null : scope.trim();
    _sessionRevision++;
    _dismissActiveDialog?.call();
  }

  static String accountStorageKey(String scope) =>
      'korlix.third_party_ai_consent.v2.account.${Uri.encodeComponent(scope)}';

  static Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _pending;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final waiting = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending = waiting;
    waiting.then((_) {
      if (identical(_pending, waiting)) _pending = null;
    });
    return result;
  }

  static Set<String> _requestedGrants(
    Set<KorlixThirdPartyAiProvider> providers,
    Set<KorlixThirdPartyAiDataCategory> categories,
  ) => {
    for (final provider in providers)
      for (final category in categories) '${provider.name}:${category.name}',
  };

  static Set<String> _readGrants(SharedPreferences preferences, String key) {
    if (_untrustedRecords.contains(key)) return {};
    try {
      final stored = preferences.getString(key);
      if (stored == null) return {};
      final record = jsonDecode(stored);
      if (record is! Map || record['version'] != consentNoticeVersion) {
        return {};
      }
      final grants = record['grants'];
      if (grants is! List || grants.any((grant) => grant is! String)) return {};
      final known = _requestedGrants(
        KorlixThirdPartyAiProvider.values.toSet(),
        KorlixThirdPartyAiDataCategory.values.toSet(),
      );
      return grants.whereType<String>().where(known.contains).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<bool> ensure({
    required BuildContext context,
    required String featureName,
    required Set<KorlixThirdPartyAiProvider> providers,
    required Set<KorlixThirdPartyAiDataCategory> dataCategories,
  }) {
    final scope = _accountScope;
    final revision = _sessionRevision;
    final requestedProviders = Set<KorlixThirdPartyAiProvider>.of(providers);
    final requestedCategories = Set<KorlixThirdPartyAiDataCategory>.of(
      dataCategories,
    );
    bool current() =>
        context.mounted &&
        revision == _sessionRevision &&
        scope == _accountScope;
    if (providers.isEmpty || dataCategories.isEmpty || !current()) {
      return Future.value(false);
    }

    return _serial(() async {
      if (!current()) return false;
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!context.mounted || !current()) return false;
        final key = scope == null ? null : accountStorageKey(scope);
        final grants = key == null ? <String>{} : _readGrants(preferences, key);
        final requested = _requestedGrants(
          requestedProviders,
          requestedCategories,
        );
        if (key != null && grants.containsAll(requested)) return true;

        // Legacy device-global lists have no trustworthy account or pairing
        // provenance, so they are never migrated into these scoped grants.
        final accepted = await _showConsentDialog(
          context: context,
          featureName: featureName,
          providers: requestedProviders,
          dataCategories: requestedCategories,
          rememberForAccount: scope != null,
        );
        if (accepted != true || !current()) return false;
        if (key == null) return true;

        final combined = {...grants, ...requested}.toList()..sort();
        // A single record prevents a partially saved version/provider/category
        // update from constructing a broader permission than the one accepted.
        _untrustedRecords.add(key);
        final saved = await preferences.setString(
          key,
          jsonEncode({
            'version': consentNoticeVersion,
            'grants': combined,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        if (!saved) return false;
        _untrustedRecords.remove(key);
        return current();
      } catch (_) {
        // A preference failure must not reuse a partially updated memory cache
        // or unexpectedly continue an AI request after its consent gate fails.
        return false;
      }
    });
  }

  /// Revokes this account's choices and invalidates pending consent immediately.
  /// Other accounts on the same device keep their separate choices.
  static Future<void> revoke() {
    final scope = _accountScope;
    final key = scope == null ? null : accountStorageKey(scope);
    _sessionRevision++;
    if (key != null) _untrustedRecords.add(key);
    _dismissActiveDialog?.call();
    return _serial(() async {
      final preferences = await SharedPreferences.getInstance();
      if (key != null && !await preferences.remove(key)) {
        throw StateError(
          'Your AI privacy choice could not be saved. Try again.',
        );
      }
      for (final legacyKey in [
        consentVersionKey,
        providersKey,
        dataCategoriesKey,
        acceptedAtKey,
      ]) {
        await preferences.remove(legacyKey);
      }
    });
  }

  static Future<bool?> _showConsentDialog({
    required BuildContext context,
    required String featureName,
    required Set<KorlixThirdPartyAiProvider> providers,
    required Set<KorlixThirdPartyAiDataCategory> dataCategories,
    required bool rememberForAccount,
  }) async {
    final providerLabels = providers.map((provider) => provider.label).toList()
      ..sort();

    final categoryLabels =
        dataCategories.map((category) => category.label).toList()..sort();

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: false,
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
                  Text(
                    rememberForAccount
                        ? 'Your choice is stored for this account on this device. '
                              'Korlix asks again when this notice changes or when a '
                              'provider needs a content category you have not approved '
                              'for that provider.'
                        : 'This choice applies to this request only. Sign in to '
                              'remember choices for your account on this device.',
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
    void dismiss() {
      if (route.isActive) navigator.removeRoute(route, false);
    }

    _dismissActiveDialog = dismiss;
    try {
      return await navigator.push<bool>(route);
    } finally {
      if (identical(_dismissActiveDialog, dismiss)) _dismissActiveDialog = null;
    }
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
