import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../lib/meeting_copilot/k135z_minutes_preview.dart';
import '../../lib/meeting_copilot/k135z_notes_projection.dart';
import '../../lib/meeting_copilot/k135z_transcript_reducer.dart';
import 'helpers/k135z_korlixai_fakes.dart';

void main() {
  test(
    'minutes preserve exact section order and deadline timezone wording',
    () {
      final K135zMeetingContext context = k135zTestContext();
      K135zTranscriptState transcript = K135zTranscriptReducer.initial(context);
      for (final K135zTranscriptEvent event in k135zFixtureEvents(
        context: context,
      )) {
        transcript = K135zTranscriptReducer.ingest(transcript, event);
      }
      final K135zNotesRequest request = K135zNotesProjection.prepare(
        transcript,
        requestId: 'notes-1',
      )!;
      final K135zNotesResult notes = K135zNotesProjection.accept(
        transcript: transcript,
        request: request,
        draft: k135zFixtureDraft(),
      );
      final K135zMinutesPreview preview = K135zMinutesProjector.project(
        notes: notes,
        metadata: k135zFixtureMetadata(context: context),
      );

      expect(preview.ok, isTrue);
      expect(
        preview.sections.map((K135zMinutesSection section) => section.category),
        K135zInsightCategory.values,
      );
      expect(preview.plainText, contains('America/New_York'));
      expect(
        preview.plainText,
        contains('Participants (partial): Alex, Morgan'),
      );
    },
  );

  test('context mismatch cannot produce completed minutes', () {
    final K135zMeetingContext context = k135zTestContext();
    final K135zNotesResult notes = K135zNotesResult(
      context: context,
      requestId: 'notes-1',
      status: K135zNotesStatus.empty,
      freshness: K135zFreshness.current,
      sourceManifest: const <String, int>{},
      insights: <K135zInsightCategory, List<K135zInsight>>{
        for (final K135zInsightCategory category in K135zInsightCategory.values)
          category: const <K135zInsight>[],
      },
    );
    final K135zMinutesPreview preview = K135zMinutesProjector.project(
      notes: notes,
      metadata: k135zFixtureMetadata(
        context: k135zTestContext(sessionId: 'different'),
      ),
    );

    expect(preview.ok, isFalse);
    expect(preview.errorCode, 'K135Z_MINUTES_CONTEXT_MISMATCH');
  });
}
