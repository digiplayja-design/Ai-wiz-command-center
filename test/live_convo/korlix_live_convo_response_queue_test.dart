import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_response_queue.dart';

void main() {
  group('KorlixLiveConvoResponseQueue', () {
    test('queues requests while a response is active', () {
      final queue = KorlixLiveConvoResponseQueue()..markBusy();

      final queued = queue.enqueue(
        const KorlixLiveConvoResponseRequest(
          source: 'LIVE DOCS',
          dedupeKey: 'doc-1',
          instructions: 'Ask the next document question.',
        ),
      );

      expect(queued, isTrue);
      expect(queue.pendingCount, 1);
      expect(queue.takeNextIfIdle(), isNull);

      queue.markResponseDone();

      final next = queue.takeNextIfIdle();

      expect(next?.source, 'LIVE DOCS');
      expect(queue.pendingCount, 0);
    });

    test('deduplicates identical pending response requests', () {
      final queue = KorlixLiveConvoResponseQueue()..markBusy();

      const request = KorlixLiveConvoResponseRequest(
        source: 'attachments',
        dedupeKey: 'attachments-1',
      );

      expect(queue.enqueue(request), isTrue);
      expect(queue.enqueue(request), isFalse);
      expect(queue.pendingCount, 1);
    });

    test('requeues the request that collided with an active response', () {
      final queue = KorlixLiveConvoResponseQueue();

      const request = KorlixLiveConvoResponseRequest(
        source: 'Create Doc',
        dedupeKey: 'create-doc-1',
      );

      queue.markDispatched(request);

      expect(queue.busy, isTrue);
      expect(queue.requeueLastDispatched(), isTrue);
      expect(queue.pendingCount, 1);

      queue.markResponseDone();

      expect(queue.takeNextIfIdle()?.dedupeKey, 'create-doc-1');
    });

    test('recognizes the provider active-response error', () {
      expect(
        korlixLiveConvoIsActiveResponseError(
          'Conversation already has an active response in progress. '
          'Wait until the response is finished before creating a new one.',
        ),
        isTrue,
      );

      expect(
        korlixLiveConvoIsActiveResponseError(
          'Microphone permission was denied.',
        ),
        isFalse,
      );
    });
  });
}
