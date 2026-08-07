import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// KORLIX_THIRD_PARTY_AI_PRIVACY_STATEMENT_TEST_BUILD131_V1_BEGIN

void main() {
  late String privacySource;

  setUpAll(() {
    final privacyFile = File('website/privacy-policy.html');

    expect(
      privacyFile.existsSync(),
      isTrue,
      reason: 'The public KORLIX Privacy Policy file must exist.',
    );

    privacySource = privacyFile.readAsStringSync();
  });

  test('third-party AI privacy disclosure is versioned and unique', () {
    const begin = 'KORLIX_THIRD_PARTY_AI_PRIVACY_DISCLOSURE_BUILD131_V1_BEGIN';
    const end = 'KORLIX_THIRD_PARTY_AI_PRIVACY_DISCLOSURE_BUILD131_V1_END';

    expect(begin.allMatches(privacySource), hasLength(1));
    expect(end.allMatches(privacySource), hasLength(1));
    expect(privacySource, contains('<section id="third-party-ai-processing">'));
    expect(privacySource, contains('<h2>Third-Party AI Processing</h2>'));
    expect(privacySource.indexOf(begin), lessThan(privacySource.indexOf(end)));
  });

  test(
    'privacy disclosure names providers and transmitted data categories',
    () {
      for (final statement in <String>[
        'OpenAI',
        'Kling AI',
        'MusicAPI.ai',
        'typed text, questions, instructions, and prompts',
        'images, photos, and camera content you select',
        'files and documents you attach',
        'voice, audio, speech, and transcripts used in LIVE CONVO',
        'agent training and long-term memories that you explicitly approve',
      ]) {
        expect(privacySource, contains(statement), reason: statement);
      }
    },
  );

  test(
    'privacy disclosure explains permission, decline, and renewed consent',
    () {
      for (final statement in <String>[
        'explicit permission',
        'You may decline',
        'the AI request is not sent',
        'Non-AI portions of Korlix remain available',
        'A new permission request is shown when the disclosure changes or when a',
        'new provider or data category is needed',
      ]) {
        expect(privacySource, contains(statement), reason: statement);
      }
    },
  );
}

// KORLIX_THIRD_PARTY_AI_PRIVACY_STATEMENT_TEST_BUILD131_V1_END
