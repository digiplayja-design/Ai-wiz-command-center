import 'dart:convert';

import 'k135z_copilot_contract.dart';

abstract final class K135zTranscriptReducer {
  static K135zTranscriptState initial(K135zMeetingContext context) =>
      K135zTranscriptState(
        context: context,
        revision: 0,
        segments: const <K135zTranscriptSegment>[],
        eventFingerprints: const <String, String>{},
        segmentRevisions: const <String, int>{},
        warnings: const <K135zWarning>[],
        coverage: const K135zCoverage(
          retainedSegments: 0,
          omittedSegments: 0,
          ingestionBlocked: false,
          complete: true,
          observedStartMs: null,
          observedEndMs: null,
        ),
        accepted: 0,
        rejected: 0,
        lastDisposition: K135zTranscriptDisposition.accepted,
      );

  static K135zTranscriptState ingest(
    K135zTranscriptState state,
    K135zTranscriptEvent event,
  ) {
    _requireContext(state.context, event.context);

    final Map<String, String> events = Map<String, String>.from(
      state.eventFingerprints,
    );
    final String? priorEvent = events[event.eventId];
    if (priorEvent != null) {
      return state.copyWith(
        lastDisposition: priorEvent == event.fingerprint
            ? K135zTranscriptDisposition.duplicate
            : K135zTranscriptDisposition.blocked,
        warnings: priorEvent == event.fingerprint
            ? state.warnings
            : _warning(
                state.warnings,
                'EVENT_ID_CONFLICT',
                'eventId',
                'The same event identity carried different content.',
              ),
        rejected: priorEvent == event.fingerprint
            ? state.rejected
            : state.rejected + 1,
        coverage: priorEvent == event.fingerprint
            ? state.coverage
            : _coverage(state.segments, state.coverage.omittedSegments, true),
      );
    }

    if (events.length >= kK135zMaximumEventIdentities) {
      return _blocked(
        state,
        'EVENT_HISTORY_LIMIT',
        'eventId',
        'The bounded event identity history is full.',
      );
    }

    final Map<String, int> revisions = Map<String, int>.from(
      state.segmentRevisions,
    );
    final int? knownRevision = revisions[event.segmentId];
    if (knownRevision == null &&
        revisions.length >= kK135zMaximumRevisionIdentities) {
      return _blocked(
        state,
        'REVISION_HISTORY_LIMIT',
        'segmentId',
        'The bounded segment revision history is full.',
      );
    }

    final int index = state.segments.indexWhere(
      (K135zTranscriptSegment value) => value.segmentId == event.segmentId,
    );
    final K135zTranscriptSegment? current = index < 0
        ? null
        : state.segments[index];

    if (knownRevision != null && event.segmentRevision < knownRevision) {
      events[event.eventId] = event.fingerprint;
      return state.copyWith(
        eventFingerprints: events,
        lastDisposition: K135zTranscriptDisposition.stale,
      );
    }

    if (current != null && event.segmentRevision == current.segmentRevision) {
      events[event.eventId] = event.fingerprint;
      if (current.fingerprint == event.fingerprint) {
        return state.copyWith(
          eventFingerprints: events,
          lastDisposition: K135zTranscriptDisposition.duplicate,
        );
      }
      return state.copyWith(
        eventFingerprints: events,
        warnings: _warning(
          state.warnings,
          'SEGMENT_REVISION_CONFLICT',
          'segmentRevision',
          'A segment revision carried conflicting content.',
        ),
        rejected: state.rejected + 1,
        lastDisposition: K135zTranscriptDisposition.blocked,
        coverage: _coverage(
          state.segments,
          state.coverage.omittedSegments,
          true,
        ),
      );
    }

    if (current != null && current.isFinal && !event.isFinal) {
      events[event.eventId] = event.fingerprint;
      return state.copyWith(
        eventFingerprints: events,
        warnings: _warning(
          state.warnings,
          'FINALITY_DOWNGRADE',
          'isFinal',
          'A finalized segment cannot be replaced by provisional content.',
        ),
        rejected: state.rejected + 1,
        lastDisposition: K135zTranscriptDisposition.rejected,
      );
    }

    if (event.text.trim().isEmpty) {
      events[event.eventId] = event.fingerprint;
      return state.copyWith(
        eventFingerprints: events,
        warnings: _warning(
          state.warnings,
          'EMPTY_TEXT',
          'text',
          'Empty transcript content was rejected.',
        ),
        rejected: state.rejected + 1,
        lastDisposition: K135zTranscriptDisposition.rejected,
      );
    }

    events[event.eventId] = event.fingerprint;
    revisions[event.segmentId] = event.segmentRevision;
    final List<K135zTranscriptSegment> segments = <K135zTranscriptSegment>[
      ...state.segments,
    ];
    final K135zTranscriptSegment replacement = K135zTranscriptSegment.fromEvent(
      event,
    );
    if (index < 0) {
      segments.add(replacement);
    } else {
      segments[index] = replacement;
    }
    segments.sort(_segmentOrder);

    int omitted = state.coverage.omittedSegments;
    while (segments.length > kK135zMaximumRetainedSegments ||
        _retainedBytes(segments) > kK135zMaximumRetainedTextBytes) {
      segments.removeAt(0);
      omitted += 1;
    }

    return K135zTranscriptState(
      context: state.context,
      revision: state.revision + 1,
      segments: segments,
      eventFingerprints: events,
      segmentRevisions: revisions,
      warnings: state.warnings,
      coverage: _coverage(segments, omitted, state.coverage.ingestionBlocked),
      accepted: state.accepted + 1,
      rejected: state.rejected,
      lastDisposition: K135zTranscriptDisposition.accepted,
    );
  }

  static K135zTranscriptState reset(
    K135zTranscriptState state,
    K135zMeetingContext context,
  ) => initial(context);

  static int _segmentOrder(
    K135zTranscriptSegment left,
    K135zTranscriptSegment right,
  ) {
    final int sequence = left.sequence.compareTo(right.sequence);
    if (sequence != 0) {
      return sequence;
    }
    final int start = left.startMs.compareTo(right.startMs);
    if (start != 0) {
      return start;
    }
    return left.segmentId.compareTo(right.segmentId);
  }

  static int _retainedBytes(List<K135zTranscriptSegment> segments) =>
      segments.fold<int>(
        0,
        (int total, K135zTranscriptSegment value) =>
            total + utf8.encode(value.text).length,
      );

  static K135zCoverage _coverage(
    List<K135zTranscriptSegment> segments,
    int omitted,
    bool blocked,
  ) {
    int? start;
    int? end;
    for (final K135zTranscriptSegment segment in segments) {
      start = start == null || segment.startMs < start
          ? segment.startMs
          : start;
      if (segment.endMs != null) {
        end = end == null || segment.endMs! > end ? segment.endMs : end;
      }
    }
    return K135zCoverage(
      retainedSegments: segments.length,
      omittedSegments: omitted,
      ingestionBlocked: blocked,
      complete: omitted == 0 && !blocked,
      observedStartMs: start,
      observedEndMs: end,
    );
  }

  static K135zTranscriptState _blocked(
    K135zTranscriptState state,
    String code,
    String field,
    String message,
  ) => state.copyWith(
    warnings: _warning(state.warnings, code, field, message),
    rejected: state.rejected + 1,
    lastDisposition: K135zTranscriptDisposition.blocked,
    coverage: _coverage(state.segments, state.coverage.omittedSegments, true),
  );

  static List<K135zWarning> _warning(
    List<K135zWarning> warnings,
    String code,
    String field,
    String message,
  ) {
    final List<K135zWarning> next = <K135zWarning>[...warnings];
    final int index = next.indexWhere(
      (K135zWarning warning) => warning.code == code && warning.field == field,
    );
    if (index < 0) {
      next.add(K135zWarning(code: code, field: field, message: message));
    } else {
      next[index] = next[index].increment();
    }
    return next;
  }

  static void _requireContext(
    K135zMeetingContext expected,
    K135zMeetingContext actual,
  ) {
    if (expected != actual) {
      throw const K135zProtocolException(
        'K135Z_CONTEXT_MISMATCH',
        'Transcript input belongs to a different meeting context.',
      );
    }
  }
}
