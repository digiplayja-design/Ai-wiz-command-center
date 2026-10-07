import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../lib/privacy/korlix_third_party_ai_consent.dart';

/// Existing capture tests begin with an account's explicit provider grant.
/// The consent integration suite separately exercises the actual dialog.
void seedMeetingAiConsent() {
  const scope = 'meeting-consent-test-account';
  KorlixThirdPartyAiConsent.setAccountScope(scope);
  SharedPreferences.setMockInitialValues({
    KorlixThirdPartyAiConsent.accountStorageKey(scope): jsonEncode({
      'version': KorlixThirdPartyAiConsent.consentNoticeVersion,
      'grants': [
        'openAi:voiceAudioAndTranscripts',
        'openAi:agentTrainingAndMemory',
      ],
      'acceptedAt': '2026-10-07T00:00:00.000Z',
    }),
  });
}
