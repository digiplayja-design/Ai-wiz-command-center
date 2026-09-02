// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_TEST_V1_BEGIN

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _screenPath = 'lib/live_convo/korlix_live_convo_test_screen.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(_screenPath).readAsStringSync();
  });

  group('K134B LIVE CONVO Agent Email schedule screen wiring', () {
    test('imports the schedule voice module exactly once', () {
      expect(
        "import 'korlix_live_convo_agent_email_schedule_voice.dart';"
            .allMatches(source),
        hasLength(1),
      );
    });

    test('declares initializes and disposes one schedule client', () {
      expect(
        'KorlixLiveConvoAgentEmailScheduleVoiceClient'.allMatches(source),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(source, contains('_agentEmailScheduleVoiceClient ='));
      expect(source, contains('_agentEmailScheduleVoiceClient.close();'));
    });

    test('publishes both protected Agent Email tools', () {
      expect(
        source,
        contains('KorlixLiveConvoAgentEmailVoiceBridge.toolDefinition'),
      );
      expect(source, contains('KorlixLiveConvoAgentEmailScheduleVoiceBridge'));
      expect(source, contains('.toolDefinition'));
    });

    test('decodes and dispatches schedule calls from response done', () {
      expect(
        source,
        contains('KorlixLiveConvoAgentEmailScheduleToolCall.fromResponseDone('),
      );
      expect(
        source,
        contains('agentEmailScheduleCalls: agentEmailScheduleCalls'),
      );
      expect(
        source,
        contains('_handleAgentEmailScheduleRealtimeFunctionCalls('),
      );
    });

    test('prepares a schedule without creating it', () {
      expect(source, contains('prepareScheduleToolCall('));
      expect(
        source,
        contains(
          'KorlixLiveConvoAgentEmailPendingSchedule.fromPreparationOutput(',
        ),
      );
      expect(source, contains("'scheduleCreated': false"));
      expect(source, contains("'sent': false"));
    });

    test('requires a separate spoken yes before rule creation', () {
      expect(
        source,
        contains('_handleAgentEmailScheduleConfirmationTranscript('),
      );
      expect(source, contains('createApprovedSchedule('));
      expect(source, contains('Should I create this exact email schedule?'));
    });

    test('gives schedule confirmation priority over immediate send', () {
      const marker = '// K134A_LIVE_CONVO_AGENT_EMAIL_TRANSCRIPT_PRIORITY_V1';
      final start = source.indexOf(marker);
      final end = source.indexOf('_appendUserTranscript(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      final schedule = block.indexOf(
        '_handleAgentEmailScheduleConfirmationTranscript(',
      );
      final immediate = block.indexOf(
        '_handleAgentEmailVoiceConfirmationTranscript(',
      );
      expect(schedule, greaterThanOrEqualTo(0));
      expect(immediate, greaterThan(schedule));
    });

    test('new immediate draft safely clears a pending schedule', () {
      expect(
        source,
        contains(
          '_clearPendingAgentEmailSchedule();\n'
          '      _pendingAgentEmailSend = null;',
        ),
      );
    });

    test('clears pending schedule state when session resources release', () {
      expect(source, contains('if (!_agentEmailScheduleCreationInFlight)'));
      expect(source, contains("_pendingAgentEmailScheduleAgentId = '';"));
      expect(source, contains('_pendingAgentEmailScheduleExpiresAt = null;'));
    });

    test('preserves the existing immediate draft and spoken send flow', () {
      expect(source, contains('executeDraftToolCall('));
      expect(source, contains('approveAndSendPending('));
      expect(source, contains('Should I send this exact email now?'));
    });

    test('keeps schedule creation separate from email sending', () {
      const begin =
          '// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_V2_BEGIN';
      const end =
          '// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_V2_STATE_END';
      final start = source.indexOf(begin);
      final finish = source.indexOf(end, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(finish, greaterThan(start));
      final block = source.substring(start, finish);
      expect(block, isNot(contains('approveAndSendPending(')));
      expect(block, isNot(contains("'/send'")));
      expect(block, contains('No email was sent'));
    });

    test('contains one complete K134B state and handler boundary', () {
      expect(
        'K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_V2_BEGIN'
            .allMatches(source),
        hasLength(1),
      );
      expect(
        'K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_V2_HANDLER_END'
            .allMatches(source),
        hasLength(1),
      );
    });
  });
}

// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_SCREEN_WIRING_TEST_V1_END
