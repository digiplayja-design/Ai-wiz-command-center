import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_docs/korlix_live_docs_brief_sheet.dart';

void main() {
  group('Korlix LIVE DOCS voice approval', () {
    test('accepts casual affirmative answers', () {
      for (final phrase in <String>[
        'yes',
        'Yeah.',
        'okay',
        'sure, go ahead',
        'do it',
        'sounds good',
        'no problem',
        'sí por favor',
        'oui',
      ]) {
        expect(
          korlixLiveDocsClassifyVoiceApproval(phrase),
          KorlixLiveDocsVoiceApprovalDecision.approve,
          reason: phrase,
        );
      }
    });

    test('declines negative or pause answers', () {
      for (final phrase in <String>[
        'no',
        'not yet',
        "okay but don't generate it",
        'hold on',
        'cancel it',
        'pas encore',
      ]) {
        expect(
          korlixLiveDocsClassifyVoiceApproval(phrase),
          KorlixLiveDocsVoiceApprovalDecision.decline,
          reason: phrase,
        );
      }
    });

    test('keeps unrelated speech unapproved', () {
      for (final phrase in <String>[
        'maybe later',
        'change the title first',
        'what formats are selected',
        '',
      ]) {
        expect(
          korlixLiveDocsClassifyVoiceApproval(phrase),
          KorlixLiveDocsVoiceApprovalDecision.unknown,
          reason: phrase,
        );
      }
    });
  });
}
