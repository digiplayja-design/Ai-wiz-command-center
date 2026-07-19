import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_docs/korlix_live_docs.dart';
import 'package:ai_wiz_command_center/live_docs/korlix_live_docs_voice_first.dart';

void main() {
  group('Korlix LIVE DOCS voice-first plan', () {
    test('uses safe defaults and creates an approved Excel audit brief', () {
      final plan = korlixLiveDocsBuildVoiceFirstPlan(
        latestUserRequest:
            'Create a December 2024 technician audit summary in Excel only.',
        now: DateTime.utc(2026, 7, 18, 18),
      );

      expect(plan.brief.title, 'December 2024 Technician Audit Summary');
      expect(plan.brief.audience, 'Internal operations');
      expect(plan.brief.tone, 'Professional');
      expect(plan.brief.allowWebResearch, isFalse);
      expect(plan.brief.canStartJob, isTrue);
      expect(plan.formats, <KorlixLiveDocOutputFormat>[
        KorlixLiveDocOutputFormat.xlsx,
      ]);
      expect(plan.spokenConfirmation, contains('3 credits'));
      expect(plan.spokenConfirmation, contains('yes or no'));
    });

    test('latest spoken format overrides stale structured formats', () {
      final formats = korlixLiveDocsResolveVoiceFirstFormats(
        latestUserRequest:
            'Make Word and PDF. Actually, change that to Excel only.',
        toolFormats: const <String>['docx', 'pdf'],
      );

      expect(formats, <KorlixLiveDocOutputFormat>[
        KorlixLiveDocOutputFormat.xlsx,
      ]);
    });

    test('keeps multiple formats when the latest request asks for them', () {
      final formats = korlixLiveDocsResolveVoiceFirstFormats(
        latestUserRequest: 'Please deliver the final report in Word and PDF.',
        toolFormats: const <String>['xlsx'],
      );

      expect(formats, <KorlixLiveDocOutputFormat>[
        KorlixLiveDocOutputFormat.docx,
        KorlixLiveDocOutputFormat.pdf,
      ]);
    });
  });
}
