// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_VOICE_TEST_V2_BEGIN

import 'dart:io';

// This import forces the schedule module to compile in Flutter's test runtime.
// ignore: unused_import
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_email_schedule_voice.dart';
import 'package:flutter_test/flutter_test.dart';

const String _modulePath =
    'lib/live_convo/korlix_live_convo_agent_email_schedule_voice.dart';

bool _field(String source, String key) =>
    source.contains("'$key':") || source.contains('"$key":');

void main() {
  late String source;

  setUpAll(() {
    source = File(_modulePath).readAsStringSync();
  });

  group('K134B LIVE CONVO email schedule voice module', () {
    test('publishes exactly one schedule tool name', () {
      expect(
        "static const String toolName = 'create_agent_email_schedule';"
            .allMatches(source),
        hasLength(1),
      );
    });

    test('publishes a strict Realtime function definition', () {
      expect(source, contains("'type': 'function'"));

      expect(
        source.contains("'name': toolName") ||
            source.contains("'name': 'create_agent_email_schedule'"),
        isTrue,
      );

      expect(source, contains("'additionalProperties': false"));
    });

    test('requires the core email and schedule fields', () {
      expect(source, contains("'required'"));

      for (final key in <String>[
        'recipient',
        'subject',
        'body',
        'scheduleType',
      ]) {
        expect(_field(source, key), isTrue, reason: 'Missing field: $key');
      }
    });

    test('supports one-time and weekly schedules', () {
      expect(RegExp(r'''["']once["']''').hasMatch(source), isTrue);

      expect(RegExp(r'''["']weekly["']''').hasMatch(source), isTrue);
    });

    test('publishes date time timezone and weekly-day inputs', () {
      expect(_field(source, 'scheduledFor'), isTrue);

      expect(_field(source, 'scheduleTimezone'), isTrue);

      expect(_field(source, 'scheduleLocalTime'), isTrue);

      expect(_field(source, 'scheduleDays'), isTrue);
    });

    test('prepares a separate spoken confirmation', () {
      expect(source, contains("'pendingConfirmation': true"));

      expect(source.toLowerCase(), contains('confirmation'));

      expect(source.toLowerCase(), contains('spoken'));
    });

    test('confirmed execution creates a preapproved autopilot rule', () {
      expect(source, contains(r"path: '${_basePath(pending.agentId)}/rules',"));

      expect(source, contains("'preapproved': true"));

      expect(source, contains("'sendMode': 'autopilot'"));
    });

    test('never invokes immediate send or approve endpoints', () {
      expect(source, isNot(contains('/send')));

      expect(source, isNot(contains('/approve')));

      expect(source, contains("'sent': false"));
    });
  });
}

// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_VOICE_TEST_V2_END
