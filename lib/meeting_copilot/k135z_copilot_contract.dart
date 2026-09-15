import 'dart:convert';

import 'package:flutter/foundation.dart';

const int kK135zMaximumEventTextBytes = 8 * 1024;
const int kK135zMaximumRetainedSegments = 2000;
const int kK135zMaximumRetainedTextBytes = 4 * 1024 * 1024;
const int kK135zMaximumEventIdentities = 20000;
const int kK135zMaximumRevisionIdentities = 20000;
const int kK135zMaximumNotesSegments = 500;
const int kK135zMaximumNotesTextBytes = 256 * 1024;
const int kK135zMaximumInsights = 100;
const int kK135zMaximumInsightsPerCategory = 25;
const int kK135zMaximumEvidencePerInsight = 16;

Never _invalid(String code, [String? detail]) =>
    throw K135zProtocolException(code, detail ?? code);

String _requiredText(String value, String field, {int maximumBytes = 32768}) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    _invalid('K135Z_REQUIRED_TEXT', field);
  }
  if (utf8.encode(normalized).length > maximumBytes) {
    _invalid('K135Z_TEXT_LIMIT', field);
  }
  return normalized;
}

@immutable
class K135zProtocolException implements Exception {
  const K135zProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'K135zProtocolException($code, $message)';
}

enum K135zInsightCategory {
  decisions,
  actionItems,
  deadlines,
  risks,
  openQuestions,
  takeaways,
}

extension K135zInsightCategoryLabel on K135zInsightCategory {
  String get label => switch (this) {
    K135zInsightCategory.decisions => 'Decisions',
    K135zInsightCategory.actionItems => 'Action Items',
    K135zInsightCategory.deadlines => 'Deadlines',
    K135zInsightCategory.risks => 'Risks',
    K135zInsightCategory.openQuestions => 'Open Questions',
    K135zInsightCategory.takeaways => 'Key Takeaways',
  };
}

enum K135zTranscriptDisposition {
  accepted,
  duplicate,
  stale,
  rejected,
  blocked,
}

enum K135zNotesStatus {
  idle,
  processing,
  ready,
  empty,
  invalidated,
  failed,
  noFinalizedInput,
}

enum K135zFreshness { current, notReflected, invalidated }

enum K135zWorkspacePhase {
  locked,
  disconnected,
  ready,
  starting,
  listening,
  pausing,
  paused,
  stopping,
  stopped,
  disconnecting,
  error,
}

enum K135zWorkspaceAction { start, pause, stop, disconnect }

@immutable
class K135zMeetingContext {
  K135zMeetingContext({
    required String tenantId,
    required String accountId,
    required String agentId,
    required String meetingUuid,
    required String sessionId,
    required String streamId,
    required this.generation,
  }) : tenantId = _requiredText(tenantId, 'tenantId', maximumBytes: 256),
       accountId = _requiredText(accountId, 'accountId', maximumBytes: 256),
       agentId = _requiredText(agentId, 'agentId', maximumBytes: 256),
       meetingUuid = _requiredText(
         meetingUuid,
         'meetingUuid',
         maximumBytes: 512,
       ),
       sessionId = _requiredText(sessionId, 'sessionId', maximumBytes: 512),
       streamId = _requiredText(streamId, 'streamId', maximumBytes: 512) {
    if (generation < 1) {
      _invalid('K135Z_GENERATION_INVALID', 'generation');
    }
  }

  final String tenantId;
  final String accountId;
  final String agentId;
  final String meetingUuid;
  final String sessionId;
  final String streamId;
  final int generation;

  K135zMeetingContext nextGeneration({
    required String sessionId,
    required String streamId,
  }) => K135zMeetingContext(
    tenantId: tenantId,
    accountId: accountId,
    agentId: agentId,
    meetingUuid: meetingUuid,
    sessionId: sessionId,
    streamId: streamId,
    generation: generation + 1,
  );

  @override
  bool operator ==(Object other) =>
      other is K135zMeetingContext &&
      tenantId == other.tenantId &&
      accountId == other.accountId &&
      agentId == other.agentId &&
      meetingUuid == other.meetingUuid &&
      sessionId == other.sessionId &&
      streamId == other.streamId &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(
    tenantId,
    accountId,
    agentId,
    meetingUuid,
    sessionId,
    streamId,
    generation,
  );
}

@immutable
class K135zTranscriptEvent {
  K135zTranscriptEvent({
    required this.context,
    required String eventId,
    required String segmentId,
    required this.segmentRevision,
    required this.sequence,
    required this.startMs,
    this.endMs,
    String? speakerName,
    required String text,
    required this.isFinal,
    required this.receivedAtUtc,
  }) : eventId = _requiredText(eventId, 'eventId', maximumBytes: 512),
       segmentId = _requiredText(segmentId, 'segmentId', maximumBytes: 512),
       speakerName = speakerName?.trim().isEmpty == true
           ? null
           : speakerName?.trim(),
       text = text {
    if (segmentRevision < 1 || sequence < 0 || startMs < 0) {
      _invalid('K135Z_TRANSCRIPT_NUMBER_INVALID');
    }
    if (endMs != null && endMs! < startMs) {
      _invalid('K135Z_TRANSCRIPT_RANGE_INVALID');
    }
    if (utf8.encode(text).length > kK135zMaximumEventTextBytes) {
      _invalid('K135Z_TRANSCRIPT_TEXT_LIMIT');
    }
    if (!receivedAtUtc.isUtc) {
      _invalid('K135Z_RECEIVED_AT_NOT_UTC');
    }
  }

  final K135zMeetingContext context;
  final String eventId;
  final String segmentId;
  final int segmentRevision;
  final int sequence;
  final int startMs;
  final int? endMs;
  final String? speakerName;
  final String text;
  final bool isFinal;
  final DateTime receivedAtUtc;

  String get fingerprint => k135zStableId(<Object?>[
    segmentId,
    segmentRevision,
    sequence,
    startMs,
    endMs,
    speakerName,
    text,
    isFinal,
  ]);
}

@immutable
class K135zTranscriptSegment {
  const K135zTranscriptSegment({
    required this.eventId,
    required this.segmentId,
    required this.segmentRevision,
    required this.sequence,
    required this.startMs,
    required this.endMs,
    required this.speakerName,
    required this.text,
    required this.isFinal,
    required this.receivedAtUtc,
  });

  factory K135zTranscriptSegment.fromEvent(K135zTranscriptEvent event) =>
      K135zTranscriptSegment(
        eventId: event.eventId,
        segmentId: event.segmentId,
        segmentRevision: event.segmentRevision,
        sequence: event.sequence,
        startMs: event.startMs,
        endMs: event.endMs,
        speakerName: event.speakerName,
        text: event.text,
        isFinal: event.isFinal,
        receivedAtUtc: event.receivedAtUtc,
      );

  final String eventId;
  final String segmentId;
  final int segmentRevision;
  final int sequence;
  final int startMs;
  final int? endMs;
  final String? speakerName;
  final String text;
  final bool isFinal;
  final DateTime receivedAtUtc;

  String get fingerprint => k135zStableId(<Object?>[
    segmentId,
    segmentRevision,
    sequence,
    startMs,
    endMs,
    speakerName,
    text,
    isFinal,
  ]);
}

@immutable
class K135zWarning {
  const K135zWarning({
    required this.code,
    required this.field,
    required this.message,
    this.occurrences = 1,
  });

  final String code;
  final String field;
  final String message;
  final int occurrences;

  K135zWarning increment() => K135zWarning(
    code: code,
    field: field,
    message: message,
    occurrences: occurrences + 1,
  );
}

@immutable
class K135zCoverage {
  const K135zCoverage({
    required this.retainedSegments,
    required this.omittedSegments,
    required this.ingestionBlocked,
    required this.complete,
    required this.observedStartMs,
    required this.observedEndMs,
  });

  final int retainedSegments;
  final int omittedSegments;
  final bool ingestionBlocked;
  final bool complete;
  final int? observedStartMs;
  final int? observedEndMs;
}

@immutable
class K135zTranscriptState {
  K135zTranscriptState({
    required this.context,
    required this.revision,
    required List<K135zTranscriptSegment> segments,
    required Map<String, String> eventFingerprints,
    required Map<String, int> segmentRevisions,
    required List<K135zWarning> warnings,
    required this.coverage,
    required this.accepted,
    required this.rejected,
    required this.lastDisposition,
  }) : segments = List<K135zTranscriptSegment>.unmodifiable(segments),
       eventFingerprints = Map<String, String>.unmodifiable(eventFingerprints),
       segmentRevisions = Map<String, int>.unmodifiable(segmentRevisions),
       warnings = List<K135zWarning>.unmodifiable(warnings);

  final K135zMeetingContext context;
  final int revision;
  final List<K135zTranscriptSegment> segments;
  final Map<String, String> eventFingerprints;
  final Map<String, int> segmentRevisions;
  final List<K135zWarning> warnings;
  final K135zCoverage coverage;
  final int accepted;
  final int rejected;
  final K135zTranscriptDisposition lastDisposition;

  K135zTranscriptState copyWith({
    K135zMeetingContext? context,
    int? revision,
    List<K135zTranscriptSegment>? segments,
    Map<String, String>? eventFingerprints,
    Map<String, int>? segmentRevisions,
    List<K135zWarning>? warnings,
    K135zCoverage? coverage,
    int? accepted,
    int? rejected,
    K135zTranscriptDisposition? lastDisposition,
  }) => K135zTranscriptState(
    context: context ?? this.context,
    revision: revision ?? this.revision,
    segments: segments ?? this.segments,
    eventFingerprints: eventFingerprints ?? this.eventFingerprints,
    segmentRevisions: segmentRevisions ?? this.segmentRevisions,
    warnings: warnings ?? this.warnings,
    coverage: coverage ?? this.coverage,
    accepted: accepted ?? this.accepted,
    rejected: rejected ?? this.rejected,
    lastDisposition: lastDisposition ?? this.lastDisposition,
  );
}

@immutable
class K135zNotesRequest {
  K135zNotesRequest({
    required this.context,
    required this.requestId,
    required List<K135zTranscriptSegment> source,
    required Map<String, int> manifest,
  }) : source = List<K135zTranscriptSegment>.unmodifiable(source),
       manifest = Map<String, int>.unmodifiable(manifest);

  final K135zMeetingContext context;
  final String requestId;
  final List<K135zTranscriptSegment> source;
  final Map<String, int> manifest;
}

@immutable
class K135zEvidenceReference {
  const K135zEvidenceReference({
    required this.segmentId,
    required this.segmentRevision,
    required this.quote,
    required this.startMs,
    required this.endMs,
    required this.speakerName,
  });

  final String segmentId;
  final int segmentRevision;
  final String quote;
  final int startMs;
  final int? endMs;
  final String? speakerName;
}

@immutable
class K135zInsight {
  K135zInsight({
    required this.id,
    required this.category,
    required String title,
    required String detail,
    this.owner,
    this.deadlineText,
    required List<K135zEvidenceReference> evidence,
  }) : title = _requiredText(title, 'title', maximumBytes: 4096),
       detail = _requiredText(detail, 'detail', maximumBytes: 32768),
       evidence = List<K135zEvidenceReference>.unmodifiable(evidence);

  final String id;
  final K135zInsightCategory category;
  final String title;
  final String detail;
  final String? owner;
  final String? deadlineText;
  final List<K135zEvidenceReference> evidence;
}

@immutable
class K135zNotesResult {
  K135zNotesResult({
    required this.context,
    required this.requestId,
    required this.status,
    required this.freshness,
    required Map<String, int> sourceManifest,
    required Map<K135zInsightCategory, List<K135zInsight>> insights,
    this.message,
  }) : sourceManifest = Map<String, int>.unmodifiable(sourceManifest),
       insights = Map<K135zInsightCategory, List<K135zInsight>>.unmodifiable(
         <K135zInsightCategory, List<K135zInsight>>{
           for (final MapEntry<K135zInsightCategory, List<K135zInsight>> entry
               in insights.entries)
             entry.key: List<K135zInsight>.unmodifiable(entry.value),
         },
       );

  final K135zMeetingContext context;
  final String requestId;
  final K135zNotesStatus status;
  final K135zFreshness freshness;
  final Map<String, int> sourceManifest;
  final Map<K135zInsightCategory, List<K135zInsight>> insights;
  final String? message;

  List<K135zInsight> category(K135zInsightCategory category) =>
      insights[category] ?? const <K135zInsight>[];

  int get insightCount => insights.values.fold<int>(
    0,
    (int total, List<K135zInsight> values) => total + values.length,
  );

  K135zNotesResult copyWith({
    K135zNotesStatus? status,
    K135zFreshness? freshness,
    String? message,
  }) => K135zNotesResult(
    context: context,
    requestId: requestId,
    status: status ?? this.status,
    freshness: freshness ?? this.freshness,
    sourceManifest: sourceManifest,
    insights: insights,
    message: message ?? this.message,
  );
}

@immutable
class K135zMeetingMetadata {
  K135zMeetingMetadata({
    required this.context,
    this.title,
    this.startedAtUtc,
    this.endedAtUtc,
    List<String> participants = const <String>[],
    this.participantsComplete = false,
    this.timezone,
  }) : participants = List<String>.unmodifiable(
         participants
             .map((String value) => value.trim())
             .where((String value) => value.isNotEmpty),
       ) {
    if (startedAtUtc != null && !startedAtUtc!.isUtc) {
      _invalid('K135Z_START_NOT_UTC');
    }
    if (endedAtUtc != null && !endedAtUtc!.isUtc) {
      _invalid('K135Z_END_NOT_UTC');
    }
    if (startedAtUtc != null &&
        endedAtUtc != null &&
        endedAtUtc!.isBefore(startedAtUtc!)) {
      _invalid('K135Z_MEETING_TIME_ORDER');
    }
  }

  final K135zMeetingContext context;
  final String? title;
  final DateTime? startedAtUtc;
  final DateTime? endedAtUtc;
  final List<String> participants;
  final bool participantsComplete;
  final String? timezone;
}

@immutable
class K135zMinutesSection {
  const K135zMinutesSection({required this.category, required this.items});

  final K135zInsightCategory category;
  final List<K135zInsight> items;
}

@immutable
class K135zMinutesPreview {
  K135zMinutesPreview({
    required this.ok,
    required this.title,
    required this.coverageNotice,
    required List<K135zMinutesSection> sections,
    required this.plainText,
    this.errorCode,
  }) : sections = List<K135zMinutesSection>.unmodifiable(sections);

  final bool ok;
  final String title;
  final String coverageNotice;
  final List<K135zMinutesSection> sections;
  final String plainText;
  final String? errorCode;
}

@immutable
class K135zWorkspaceCommand {
  const K135zWorkspaceCommand({
    required this.operationId,
    required this.context,
    required this.action,
  });

  final String operationId;
  final K135zMeetingContext context;
  final K135zWorkspaceAction action;
}

@immutable
class K135zWorkspaceAck {
  const K135zWorkspaceAck({
    required this.operationId,
    required this.context,
    required this.accepted,
    required this.hostAuthorized,
    required this.listeningAuthorized,
    required this.remoteState,
  });

  final String operationId;
  final K135zMeetingContext context;
  final bool accepted;
  final bool hostAuthorized;
  final bool listeningAuthorized;
  final String remoteState;
}

String k135zStableId(Iterable<Object?> parts) {
  int hash = 0x811c9dc5;
  for (final int unit in utf8.encode(
    parts.map((Object? v) => v ?? '').join('\u001f'),
  )) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
