import 'dart:async';

import '../../../lib/meeting_copilot/k135z_copilot_contract.dart';
import '../../../lib/meeting_copilot/k135z_notes_projection.dart';
import '../../../lib/meeting_copilot/k135z_workspace_controller.dart';

K135zMeetingContext k135zTestContext({
  int generation = 1,
  String sessionId = 'session-1',
  String streamId = 'stream-1',
}) => K135zMeetingContext(
  tenantId: 'tenant-1',
  accountId: 'account-1',
  agentId: 'nova-agent',
  meetingUuid: 'meeting-uuid-1',
  sessionId: sessionId,
  streamId: streamId,
  generation: generation,
);

K135zTranscriptEvent k135zTestEvent(
  int index, {
  K135zMeetingContext? context,
  int revision = 1,
  bool isFinal = true,
  String? text,
  String? speaker,
}) => K135zTranscriptEvent(
  context: context ?? k135zTestContext(),
  eventId: 'event-$index-r$revision',
  segmentId: 'S$index',
  segmentRevision: revision,
  sequence: index,
  startMs: index * 10000,
  endMs: index * 10000 + 5000,
  speakerName: speaker ?? (index.isEven ? 'Alex' : 'Morgan'),
  text: text ?? 'Meeting statement $index.',
  isFinal: isFinal,
  receivedAtUtc: DateTime.utc(2026, 9, 15, 10, 0, index),
);

List<K135zTranscriptEvent> k135zFixtureEvents({
  K135zMeetingContext? context,
}) => <K135zTranscriptEvent>[
  k135zTestEvent(
    1,
    context: context,
    text: 'We agreed to keep the pilot notes-only.',
    speaker: 'Alex',
  ),
  k135zTestEvent(
    2,
    context: context,
    text: 'I will draft the pilot checklist.',
    speaker: 'Morgan',
  ),
  k135zTestEvent(
    3,
    context: context,
    text:
        'The pilot checklist is due September 18, 2026, at 3 PM America/New_York.',
    speaker: 'Alex',
  ),
  k135zTestEvent(
    4,
    context: context,
    text: 'Unstable Wi-Fi is a delivery risk.',
    speaker: 'Morgan',
  ),
  k135zTestEvent(
    5,
    context: context,
    text: 'We still need to decide the retention period.',
    speaker: 'Alex',
  ),
  k135zTestEvent(
    6,
    context: context,
    text: 'Host approval is required before listening.',
    speaker: 'Morgan',
  ),
];

List<K135zDraftInsight> k135zFixtureDraft() => <K135zDraftInsight>[
  K135zDraftInsight(
    category: K135zInsightCategory.decisions,
    title: 'Notes-only pilot',
    detail: 'Keep the pilot notes-only.',
    evidenceSegmentIds: const <String>['S1'],
  ),
  K135zDraftInsight(
    category: K135zInsightCategory.actionItems,
    title: 'Draft checklist',
    detail: 'Draft the pilot checklist.',
    owner: 'Morgan',
    evidenceSegmentIds: const <String>['S2'],
  ),
  K135zDraftInsight(
    category: K135zInsightCategory.deadlines,
    title: 'Checklist due',
    detail: 'Complete the pilot checklist by the stated deadline.',
    owner: 'Morgan',
    deadlineText: 'September 18, 2026, at 3 PM America/New_York',
    evidenceSegmentIds: const <String>['S2', 'S3'],
  ),
  K135zDraftInsight(
    category: K135zInsightCategory.risks,
    title: 'Wi-Fi stability',
    detail: 'Unstable Wi-Fi may affect delivery.',
    evidenceSegmentIds: const <String>['S4'],
  ),
  K135zDraftInsight(
    category: K135zInsightCategory.openQuestions,
    title: 'Retention period',
    detail: 'The retention period is not decided.',
    evidenceSegmentIds: const <String>['S5'],
  ),
  K135zDraftInsight(
    category: K135zInsightCategory.takeaways,
    title: 'Host control',
    detail: 'Host approval is required before listening.',
    evidenceSegmentIds: const <String>['S6'],
  ),
];

K135zMeetingMetadata k135zFixtureMetadata({K135zMeetingContext? context}) =>
    K135zMeetingMetadata(
      context: context ?? k135zTestContext(),
      title: 'KORLIX Pilot Planning',
      startedAtUtc: DateTime.utc(2026, 9, 15, 13),
      endedAtUtc: DateTime.utc(2026, 9, 15, 14),
      participants: const <String>['Alex', 'Morgan'],
      participantsComplete: false,
      timezone: 'America/New_York',
    );

class K135zFakeGateway implements K135zWorkspaceGateway {
  final List<K135zWorkspaceCommand> commands = <K135zWorkspaceCommand>[];
  final List<Completer<K135zWorkspaceAck>> _pending =
      <Completer<K135zWorkspaceAck>>[];

  @override
  Future<K135zWorkspaceAck> execute(K135zWorkspaceCommand command) {
    commands.add(command);
    final Completer<K135zWorkspaceAck> completer =
        Completer<K135zWorkspaceAck>();
    _pending.add(completer);
    return completer.future;
  }

  void acknowledgeNext({
    bool accepted = true,
    bool hostAuthorized = true,
    bool listeningAuthorized = true,
    String remoteState = 'listening',
  }) {
    final K135zWorkspaceCommand command =
        commands[commands.length - _pending.length];
    _pending
        .removeAt(0)
        .complete(
          K135zWorkspaceAck(
            operationId: command.operationId,
            context: command.context,
            accepted: accepted,
            hostAuthorized: hostAuthorized,
            listeningAuthorized: listeningAuthorized,
            remoteState: remoteState,
          ),
        );
  }

  void failNext(Object error) {
    _pending.removeAt(0).completeError(error);
  }
}
