import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../lib/meeting_copilot/k135z_notes_projection.dart';
import '../../lib/meeting_copilot/k135z_transcript_reducer.dart';
import 'helpers/k135z_korlixai_fakes.dart';

K135zTranscriptState _fixtureTranscript(K135zMeetingContext context) {
  K135zTranscriptState state = K135zTranscriptReducer.initial(context);
  for (final K135zTranscriptEvent event in k135zFixtureEvents(
    context: context,
  )) {
    state = K135zTranscriptReducer.ingest(state, event);
  }
  return state;
}

void main() {
  test('notes request keeps exact finalized source manifest', () {
    final K135zMeetingContext context = k135zTestContext();
    final K135zNotesRequest request = K135zNotesProjection.prepare(
      _fixtureTranscript(context),
      requestId: 'notes-1',
    )!;

    expect(request.source, hasLength(6));
    expect(request.manifest, <String, int>{
      'S1': 1,
      'S2': 1,
      'S3': 1,
      'S4': 1,
      'S5': 1,
      'S6': 1,
    });
  });

  test('six-category result is evidence-linked and deterministic', () {
    final K135zMeetingContext context = k135zTestContext();
    final K135zTranscriptState transcript = _fixtureTranscript(context);
    final K135zNotesRequest request = K135zNotesProjection.prepare(
      transcript,
      requestId: 'notes-1',
    )!;
    final K135zNotesResult first = K135zNotesProjection.accept(
      transcript: transcript,
      request: request,
      draft: k135zFixtureDraft(),
    );
    final K135zNotesResult second = K135zNotesProjection.accept(
      transcript: transcript,
      request: request,
      draft: k135zFixtureDraft(),
    );

    expect(first.status, K135zNotesStatus.ready);
    expect(first.insightCount, 6);
    expect(
      first.category(K135zInsightCategory.deadlines).single.evidence,
      hasLength(2),
    );
    expect(
      first.category(K135zInsightCategory.decisions).single.id,
      second.category(K135zInsightCategory.decisions).single.id,
    );
  });

  test('unsupported or duplicate evidence rejects the whole result', () {
    final K135zMeetingContext context = k135zTestContext();
    final K135zTranscriptState transcript = _fixtureTranscript(context);
    final K135zNotesRequest request = K135zNotesProjection.prepare(
      transcript,
      requestId: 'notes-1',
    )!;

    expect(
      () => K135zNotesProjection.accept(
        transcript: transcript,
        request: request,
        draft: <K135zDraftInsight>[
          K135zDraftInsight(
            category: K135zInsightCategory.decisions,
            title: 'Unsupported',
            detail: 'Unsupported evidence.',
            evidenceSegmentIds: const <String>['S99'],
          ),
        ],
      ),
      throwsA(isA<K135zProtocolException>()),
    );

    expect(
      () => K135zNotesProjection.accept(
        transcript: transcript,
        request: request,
        draft: <K135zDraftInsight>[
          K135zDraftInsight(
            category: K135zInsightCategory.decisions,
            title: 'Duplicate',
            detail: 'Duplicate evidence.',
            evidenceSegmentIds: const <String>['S1', 'S1'],
          ),
        ],
      ),
      throwsA(isA<K135zProtocolException>()),
    );
  });

  test(
    'correction invalidates while new outside material becomes not reflected',
    () {
      final K135zMeetingContext context = k135zTestContext();
      final K135zTranscriptState transcript = _fixtureTranscript(context);
      final K135zNotesRequest request = K135zNotesProjection.prepare(
        transcript,
        requestId: 'notes-1',
      )!;
      final K135zNotesResult result = K135zNotesProjection.accept(
        transcript: transcript,
        request: request,
        draft: k135zFixtureDraft(),
      );

      final K135zTranscriptState extra = K135zTranscriptReducer.ingest(
        transcript,
        k135zTestEvent(7, context: context, text: 'New finalized content.'),
      );
      expect(
        K135zNotesProjection.reconcile(extra, result).freshness,
        K135zFreshness.notReflected,
      );

      final K135zTranscriptState corrected = K135zTranscriptReducer.ingest(
        transcript,
        k135zTestEvent(
          1,
          context: context,
          revision: 2,
          text: 'Corrected decision.',
        ),
      );
      final K135zNotesResult invalidated = K135zNotesProjection.reconcile(
        corrected,
        result,
      );
      expect(invalidated.status, K135zNotesStatus.invalidated);
      expect(invalidated.freshness, K135zFreshness.invalidated);
    },
  );
}
