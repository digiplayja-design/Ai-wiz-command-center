import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_docs/korlix_live_docs_live_convo_bridge.dart';

void main() {
  group('KorlixLiveDocsConversationBridge', () {
    test('ignores user turns while capture is inactive', () {
      final bridge = KorlixLiveDocsConversationBridge();

      final captured = bridge.captureUserTurn(
        'Create a quarterly report.',
        source: 'voice',
        eventId: 'event-1',
      );

      expect(captured, isFalse);
      expect(bridge.capturedTurnCount, 0);
    });

    test('captures finalized turns and rejects duplicate event IDs', () {
      final bridge = KorlixLiveDocsConversationBridge()..startCapture();

      expect(
        bridge.captureUserTurn(
          'Create a quarterly board report for the leadership team.',
          source: 'voice',
          eventId: 'event-1',
          timestamp: DateTime.utc(2026, 7, 15, 22),
        ),
        isTrue,
      );

      expect(
        bridge.captureUserTurn(
          'This duplicate should not be added.',
          source: 'voice',
          eventId: 'event-1',
        ),
        isFalse,
      );

      expect(
        bridge.captureUserTurn(
          'Include revenue charts and recommendations.',
          source: 'keyboard',
          eventId: 'event-2',
        ),
        isTrue,
      );

      expect(bridge.capturedTurnCount, 2);

      expect(
        bridge.combinedInstructions,
        contains(
          '1. [voice] Create a quarterly board report '
          'for the leadership team.',
        ),
      );

      expect(
        bridge.combinedInstructions,
        contains('2. [keyboard] Include revenue charts and recommendations.'),
      );
    });

    test('suggests a title and goal from captured conversation', () {
      final bridge = KorlixLiveDocsConversationBridge()..startCapture();

      bridge.captureUserTurn(
        'Create a quarterly board report for the leadership team. '
        'Compare Q1 and Q2.',
        source: 'voice',
      );

      expect(
        bridge.suggestedTitle,
        'Create a quarterly board report for the leadership team',
      );

      expect(bridge.suggestedGoal, contains('Compare Q1 and Q2'));
    });

    test('stops capture without deleting the collected brief', () {
      final bridge = KorlixLiveDocsConversationBridge()..startCapture();

      bridge.captureUserTurn('Draft a client proposal.', source: 'voice');

      bridge.stopCapture();

      expect(bridge.captureActive, isFalse);
      expect(bridge.capturedTurnCount, 1);

      expect(
        bridge.captureUserTurn('This should not be captured.', source: 'voice'),
        isFalse,
      );

      expect(bridge.capturedTurnCount, 1);
    });

    test('can start a clean replacement brief', () {
      final bridge = KorlixLiveDocsConversationBridge()..startCapture();

      bridge.captureUserTurn('First document.', source: 'voice');

      bridge.startCapture(clearExisting: true);

      expect(bridge.captureActive, isTrue);
      expect(bridge.capturedTurnCount, 0);

      bridge.captureUserTurn('Second document.', source: 'voice');

      expect(bridge.capturedTurnCount, 1);
      expect(bridge.combinedInstructions, contains('Second document.'));
      expect(bridge.combinedInstructions, isNot(contains('First document.')));
    });
  });
}
