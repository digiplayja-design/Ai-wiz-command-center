import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../lib/meeting_copilot/k135z_transcript_reducer.dart';
import 'helpers/k135z_korlixai_fakes.dart';

void main() {
  test(
    'normalized transcript accepts final input and preserves source identity',
    () {
      final K135zMeetingContext context = k135zTestContext();
      final K135zTranscriptState state = K135zTranscriptReducer.ingest(
        K135zTranscriptReducer.initial(context),
        k135zTestEvent(1, context: context),
      );

      expect(state.segments, hasLength(1));
      expect(state.segments.single.segmentId, 'S1');
      expect(state.segments.single.segmentRevision, 1);
      expect(state.lastDisposition, K135zTranscriptDisposition.accepted);
      expect(state.coverage.complete, isTrue);
    },
  );

  test(
    'exact redelivery is a no-op while conflicting event identity blocks',
    () {
      final K135zMeetingContext context = k135zTestContext();
      final K135zTranscriptEvent event = k135zTestEvent(1, context: context);
      final K135zTranscriptState first = K135zTranscriptReducer.ingest(
        K135zTranscriptReducer.initial(context),
        event,
      );
      final K135zTranscriptState duplicate = K135zTranscriptReducer.ingest(
        first,
        event,
      );
      final K135zTranscriptEvent conflict = K135zTranscriptEvent(
        context: context,
        eventId: event.eventId,
        segmentId: event.segmentId,
        segmentRevision: event.segmentRevision,
        sequence: event.sequence,
        startMs: event.startMs,
        endMs: event.endMs,
        speakerName: event.speakerName,
        text: 'Conflicting text',
        isFinal: event.isFinal,
        receivedAtUtc: event.receivedAtUtc,
      );
      final K135zTranscriptState blocked = K135zTranscriptReducer.ingest(
        duplicate,
        conflict,
      );

      expect(duplicate.lastDisposition, K135zTranscriptDisposition.duplicate);
      expect(duplicate.revision, first.revision);
      expect(blocked.lastDisposition, K135zTranscriptDisposition.blocked);
      expect(blocked.coverage.ingestionBlocked, isTrue);
    },
  );

  test(
    'higher revision replaces content and stale or provisional downgrade cannot restore it',
    () {
      final K135zMeetingContext context = k135zTestContext();
      K135zTranscriptState state = K135zTranscriptReducer.initial(context);
      state = K135zTranscriptReducer.ingest(
        state,
        k135zTestEvent(1, context: context, text: 'Original'),
      );
      state = K135zTranscriptReducer.ingest(
        state,
        k135zTestEvent(1, context: context, revision: 2, text: 'Corrected'),
      );
      expect(state.segments.single.text, 'Corrected');

      final K135zTranscriptState stale = K135zTranscriptReducer.ingest(
        state,
        K135zTranscriptEvent(
          context: context,
          eventId: 'late-stale',
          segmentId: 'S1',
          segmentRevision: 1,
          sequence: 1,
          startMs: 10000,
          endMs: 15000,
          speakerName: 'Alex',
          text: 'Old content',
          isFinal: true,
          receivedAtUtc: DateTime.utc(2026, 9, 15, 10, 1),
        ),
      );
      expect(stale.lastDisposition, K135zTranscriptDisposition.stale);
      expect(stale.segments.single.text, 'Corrected');

      final K135zTranscriptState downgrade = K135zTranscriptReducer.ingest(
        stale,
        k135zTestEvent(
          1,
          context: context,
          revision: 3,
          isFinal: false,
          text: 'Provisional',
        ),
      );
      expect(downgrade.lastDisposition, K135zTranscriptDisposition.rejected);
      expect(downgrade.segments.single.text, 'Corrected');
    },
  );

  test('cross-context input is rejected', () {
    final K135zTranscriptState state = K135zTranscriptReducer.initial(
      k135zTestContext(),
    );
    expect(
      () => K135zTranscriptReducer.ingest(
        state,
        k135zTestEvent(
          1,
          context: k135zTestContext(sessionId: 'other-session'),
        ),
      ),
      throwsA(isA<K135zProtocolException>()),
    );
  });
}
