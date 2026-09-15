import 'dart:convert';

import 'k135z_copilot_contract.dart';

class K135zDraftInsight {
  K135zDraftInsight({
    required this.category,
    required this.title,
    required this.detail,
    required List<String> evidenceSegmentIds,
    this.owner,
    this.deadlineText,
  }) : evidenceSegmentIds = List<String>.unmodifiable(evidenceSegmentIds);

  final K135zInsightCategory category;
  final String title;
  final String detail;
  final String? owner;
  final String? deadlineText;
  final List<String> evidenceSegmentIds;
}

abstract final class K135zNotesProjection {
  static K135zNotesRequest? prepare(
    K135zTranscriptState transcript, {
    required String requestId,
  }) {
    final List<K135zTranscriptSegment> finalized = transcript.segments
        .where((K135zTranscriptSegment segment) => segment.isFinal)
        .toList(growable: false);
    if (finalized.isEmpty) {
      return null;
    }

    final List<K135zTranscriptSegment> selected = <K135zTranscriptSegment>[];
    int bytes = 0;
    for (final K135zTranscriptSegment segment in finalized.reversed) {
      final int nextBytes = utf8.encode(segment.text).length;
      if (selected.length >= kK135zMaximumNotesSegments ||
          bytes + nextBytes > kK135zMaximumNotesTextBytes) {
        break;
      }
      selected.add(segment);
      bytes += nextBytes;
    }
    final List<K135zTranscriptSegment> source = selected.reversed.toList(
      growable: false,
    );
    return K135zNotesRequest(
      context: transcript.context,
      requestId: requestId,
      source: source,
      manifest: <String, int>{
        for (final K135zTranscriptSegment segment in source)
          segment.segmentId: segment.segmentRevision,
      },
    );
  }

  static K135zNotesResult accept({
    required K135zTranscriptState transcript,
    required K135zNotesRequest request,
    required Iterable<K135zDraftInsight> draft,
  }) {
    if (transcript.context != request.context) {
      throw const K135zProtocolException(
        'K135Z_NOTES_CONTEXT_MISMATCH',
        'Notes request belongs to a different meeting context.',
      );
    }
    final Map<String, K135zTranscriptSegment> source =
        <String, K135zTranscriptSegment>{
          for (final K135zTranscriptSegment segment in request.source)
            segment.segmentId: segment,
        };
    _requireManifest(request, source);

    final Map<K135zInsightCategory, List<K135zInsight>> categories =
        <K135zInsightCategory, List<K135zInsight>>{
          for (final K135zInsightCategory value in K135zInsightCategory.values)
            value: <K135zInsight>[],
        };
    int total = 0;
    for (final K135zDraftInsight raw in draft) {
      if (raw.evidenceSegmentIds.isEmpty ||
          raw.evidenceSegmentIds.length > kK135zMaximumEvidencePerInsight) {
        throw const K135zProtocolException(
          'K135Z_EVIDENCE_COUNT_INVALID',
          'Every insight requires bounded source evidence.',
        );
      }
      final List<K135zEvidenceReference> evidence = <K135zEvidenceReference>[];
      final Set<String> seen = <String>{};
      for (final String segmentId in raw.evidenceSegmentIds) {
        if (!seen.add(segmentId)) {
          throw const K135zProtocolException(
            'K135Z_DUPLICATE_EVIDENCE',
            'An insight cannot cite the same segment twice.',
          );
        }
        final K135zTranscriptSegment? segment = source[segmentId];
        if (segment == null) {
          throw const K135zProtocolException(
            'K135Z_UNSUPPORTED_EVIDENCE',
            'An insight cited transcript content outside its request window.',
          );
        }
        evidence.add(
          K135zEvidenceReference(
            segmentId: segment.segmentId,
            segmentRevision: segment.segmentRevision,
            quote: segment.text,
            startMs: segment.startMs,
            endMs: segment.endMs,
            speakerName: segment.speakerName,
          ),
        );
      }
      final List<K135zInsight> bucket = categories[raw.category]!;
      if (bucket.length >= kK135zMaximumInsightsPerCategory ||
          total >= kK135zMaximumInsights) {
        throw const K135zProtocolException(
          'K135Z_INSIGHT_LIMIT',
          'The bounded notes result limit was exceeded.',
        );
      }
      final String id = k135zStableId(<Object?>[
        request.context.meetingUuid,
        raw.category.name,
        raw.title.trim(),
        raw.detail.trim(),
        ...evidence.map(
          (K135zEvidenceReference value) =>
              '${value.segmentId}:${value.segmentRevision}',
        ),
      ]);
      bucket.add(
        K135zInsight(
          id: id,
          category: raw.category,
          title: raw.title,
          detail: raw.detail,
          owner: _nullable(raw.owner),
          deadlineText: _nullable(raw.deadlineText),
          evidence: evidence,
        ),
      );
      total += 1;
    }

    return K135zNotesResult(
      context: request.context,
      requestId: request.requestId,
      status: total == 0 ? K135zNotesStatus.empty : K135zNotesStatus.ready,
      freshness: K135zFreshness.current,
      sourceManifest: request.manifest,
      insights: categories,
      message: total == 0 ? 'The validated notes result is empty.' : null,
    );
  }

  static K135zNotesResult reconcile(
    K135zTranscriptState transcript,
    K135zNotesResult result,
  ) {
    if (transcript.context != result.context) {
      return result.copyWith(
        status: K135zNotesStatus.invalidated,
        freshness: K135zFreshness.invalidated,
        message: 'The meeting context changed.',
      );
    }
    final Map<String, K135zTranscriptSegment> current =
        <String, K135zTranscriptSegment>{
          for (final K135zTranscriptSegment segment in transcript.segments)
            segment.segmentId: segment,
        };
    for (final MapEntry<String, int> entry in result.sourceManifest.entries) {
      final K135zTranscriptSegment? segment = current[entry.key];
      if (segment == null || segment.segmentRevision != entry.value) {
        return result.copyWith(
          status: K135zNotesStatus.invalidated,
          freshness: K135zFreshness.invalidated,
          message: 'A source transcript segment changed.',
        );
      }
    }
    final bool hasNewFinalized = transcript.segments.any(
      (K135zTranscriptSegment segment) =>
          segment.isFinal &&
          !result.sourceManifest.containsKey(segment.segmentId),
    );
    return result.copyWith(
      freshness: hasNewFinalized
          ? K135zFreshness.notReflected
          : K135zFreshness.current,
      message: hasNewFinalized
          ? 'New finalized transcript content is not reflected.'
          : result.message,
    );
  }

  static void _requireManifest(
    K135zNotesRequest request,
    Map<String, K135zTranscriptSegment> source,
  ) {
    if (request.manifest.length != source.length) {
      throw const K135zProtocolException(
        'K135Z_MANIFEST_MISMATCH',
        'The notes request manifest does not match its source window.',
      );
    }
    for (final MapEntry<String, int> entry in request.manifest.entries) {
      if (source[entry.key]?.segmentRevision != entry.value) {
        throw const K135zProtocolException(
          'K135Z_MANIFEST_MISMATCH',
          'The notes request manifest does not match its source window.',
        );
      }
    }
  }

  static String? _nullable(String? value) {
    final String normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
