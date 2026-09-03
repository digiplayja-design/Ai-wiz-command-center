import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restored Agent sheet opens Nova Email Center and preserves K134B schedule voice wiring',
    () {
      final screen = File(
        'lib/live_convo/korlix_live_convo_test_screen.dart',
      ).readAsStringSync();

      final agentSheet = File(
        'lib/live_convo/korlix_live_convo_agent_sheet.dart',
      ).readAsStringSync();

      final emailSheet = File(
        'lib/live_convo/korlix_live_convo_agent_email_sheet.dart',
      );

      expect(emailSheet.existsSync(), isTrue);

      expect(agentSheet, contains('korlix_live_convo_agent_email_sheet.dart'));

      expect(agentSheet, contains('KORLIX_AGENT_EMAIL_BUTTON_BUILD133_BEGIN'));

      expect(agentSheet, contains('_openAgentEmail('));

      expect(agentSheet, contains('showKorlixLiveConvoAgentEmailSheet('));

      expect(
        screen,
        contains(
          'K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_V2_BEGIN',
        ),
      );

      expect(
        screen,
        contains('K134A_LIVE_CONVO_AGENT_EMAIL_SCREEN_WIRING_V1_BEGIN'),
      );
    },
  );
}
