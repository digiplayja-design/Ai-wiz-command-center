import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum NovaMeetingCopilotStatus {
  disconnected,
  ready,
  listening,
  paused,
  speaking,
  stopped,
  error,
}

extension NovaMeetingCopilotStatusLabel on NovaMeetingCopilotStatus {
  String get label {
    switch (this) {
      case NovaMeetingCopilotStatus.disconnected:
        return 'Zoom not connected';
      case NovaMeetingCopilotStatus.ready:
        return 'Ready — host approval required';
      case NovaMeetingCopilotStatus.listening:
        return 'Nova is listening';
      case NovaMeetingCopilotStatus.paused:
        return 'Nova is paused';
      case NovaMeetingCopilotStatus.speaking:
        return 'Nova is speaking';
      case NovaMeetingCopilotStatus.stopped:
        return 'Listening stopped';
      case NovaMeetingCopilotStatus.error:
        return 'Meeting Copilot needs attention';
    }
  }
}

@immutable
class NovaMeetingInsight {
  const NovaMeetingInsight({
    required this.title,
    required this.detail,
    this.owner,
    this.deadline,
  });

  final String title;
  final String detail;
  final String? owner;
  final DateTime? deadline;
}

@immutable
class NovaTranscriptLine {
  const NovaTranscriptLine({
    required this.speaker,
    required this.text,
    required this.timestamp,
  });

  final String speaker;
  final String text;
  final Duration timestamp;

  String get timestampLabel {
    final int hours = timestamp.inHours;
    final int minutes = timestamp.inMinutes.remainder(60);
    final int seconds = timestamp.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

@immutable
class NovaMeetingCopilotState {
  NovaMeetingCopilotState({
    required this.status,
    required this.zoomConnected,
    required this.hostAuthorized,
    required this.novaMuted,
    required this.hostInvitedToSpeak,
    required this.meetingTitle,
    required this.participantCount,
    required this.activeSeconds,
    required List<NovaTranscriptLine> transcript,
    required List<NovaMeetingInsight> decisions,
    required List<NovaMeetingInsight> actionItems,
    required List<NovaMeetingInsight> deadlines,
    required List<NovaMeetingInsight> risks,
    required List<NovaMeetingInsight> openQuestions,
    required List<NovaMeetingInsight> takeaways,
  }) : transcript = List<NovaTranscriptLine>.unmodifiable(transcript),
       decisions = List<NovaMeetingInsight>.unmodifiable(decisions),
       actionItems = List<NovaMeetingInsight>.unmodifiable(actionItems),
       deadlines = List<NovaMeetingInsight>.unmodifiable(deadlines),
       risks = List<NovaMeetingInsight>.unmodifiable(risks),
       openQuestions = List<NovaMeetingInsight>.unmodifiable(openQuestions),
       takeaways = List<NovaMeetingInsight>.unmodifiable(takeaways);

  factory NovaMeetingCopilotState.initial() {
    return NovaMeetingCopilotState(
      status: NovaMeetingCopilotStatus.disconnected,
      zoomConnected: false,
      hostAuthorized: false,
      novaMuted: true,
      hostInvitedToSpeak: false,
      meetingTitle: 'No active meeting',
      participantCount: 0,
      activeSeconds: 0,
      transcript: const <NovaTranscriptLine>[],
      decisions: const <NovaMeetingInsight>[],
      actionItems: const <NovaMeetingInsight>[],
      deadlines: const <NovaMeetingInsight>[],
      risks: const <NovaMeetingInsight>[],
      openQuestions: const <NovaMeetingInsight>[],
      takeaways: const <NovaMeetingInsight>[],
    );
  }

  final NovaMeetingCopilotStatus status;
  final bool zoomConnected;
  final bool hostAuthorized;
  final bool novaMuted;
  final bool hostInvitedToSpeak;
  final String meetingTitle;
  final int participantCount;
  final int activeSeconds;
  final List<NovaTranscriptLine> transcript;
  final List<NovaMeetingInsight> decisions;
  final List<NovaMeetingInsight> actionItems;
  final List<NovaMeetingInsight> deadlines;
  final List<NovaMeetingInsight> risks;
  final List<NovaMeetingInsight> openQuestions;
  final List<NovaMeetingInsight> takeaways;

  NovaMeetingCopilotState copyWith({
    NovaMeetingCopilotStatus? status,
    bool? zoomConnected,
    bool? hostAuthorized,
    bool? novaMuted,
    bool? hostInvitedToSpeak,
    String? meetingTitle,
    int? participantCount,
    int? activeSeconds,
    List<NovaTranscriptLine>? transcript,
    List<NovaMeetingInsight>? decisions,
    List<NovaMeetingInsight>? actionItems,
    List<NovaMeetingInsight>? deadlines,
    List<NovaMeetingInsight>? risks,
    List<NovaMeetingInsight>? openQuestions,
    List<NovaMeetingInsight>? takeaways,
  }) {
    return NovaMeetingCopilotState(
      status: status ?? this.status,
      zoomConnected: zoomConnected ?? this.zoomConnected,
      hostAuthorized: hostAuthorized ?? this.hostAuthorized,
      novaMuted: novaMuted ?? this.novaMuted,
      hostInvitedToSpeak: hostInvitedToSpeak ?? this.hostInvitedToSpeak,
      meetingTitle: meetingTitle ?? this.meetingTitle,
      participantCount: participantCount ?? this.participantCount,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      transcript: transcript ?? this.transcript,
      decisions: decisions ?? this.decisions,
      actionItems: actionItems ?? this.actionItems,
      deadlines: deadlines ?? this.deadlines,
      risks: risks ?? this.risks,
      openQuestions: openQuestions ?? this.openQuestions,
      takeaways: takeaways ?? this.takeaways,
    );
  }
}

class NovaMeetingCopilotController extends ChangeNotifier {
  NovaMeetingCopilotController({NovaMeetingCopilotState? initialState})
    : _state = initialState ?? NovaMeetingCopilotState.initial();

  NovaMeetingCopilotState _state;

  NovaMeetingCopilotState get state => _state;

  bool get canStartListening {
    return _state.zoomConnected &&
        _state.hostAuthorized &&
        <NovaMeetingCopilotStatus>{
          NovaMeetingCopilotStatus.ready,
          NovaMeetingCopilotStatus.paused,
          NovaMeetingCopilotStatus.stopped,
        }.contains(_state.status);
  }

  bool get canPauseListening {
    return _state.status == NovaMeetingCopilotStatus.listening;
  }

  bool get canStopListening {
    return <NovaMeetingCopilotStatus>{
      NovaMeetingCopilotStatus.listening,
      NovaMeetingCopilotStatus.paused,
      NovaMeetingCopilotStatus.speaking,
    }.contains(_state.status);
  }

  bool get canAskNova {
    return <NovaMeetingCopilotStatus>{
      NovaMeetingCopilotStatus.listening,
      NovaMeetingCopilotStatus.paused,
    }.contains(_state.status);
  }

  bool get canSpeakNow {
    return _state.hostAuthorized &&
        _state.hostInvitedToSpeak &&
        _state.status == NovaMeetingCopilotStatus.listening;
  }

  void setConnection({
    required bool connected,
    String meetingTitle = 'No active meeting',
    int participantCount = 0,
  }) {
    _setState(
      _state.copyWith(
        zoomConnected: connected,
        hostAuthorized: connected ? _state.hostAuthorized : false,
        novaMuted: true,
        hostInvitedToSpeak: false,
        meetingTitle: connected ? meetingTitle : 'No active meeting',
        participantCount: connected ? participantCount : 0,
        status: connected
            ? NovaMeetingCopilotStatus.ready
            : NovaMeetingCopilotStatus.disconnected,
      ),
    );
  }

  void setHostAuthorization(bool authorized) {
    if (!_state.zoomConnected && authorized) {
      throw StateError('Zoom must be connected before host authorization.');
    }

    _setState(
      _state.copyWith(
        hostAuthorized: authorized,
        novaMuted: authorized ? _state.novaMuted : true,
        hostInvitedToSpeak: authorized ? _state.hostInvitedToSpeak : false,
        status: _state.zoomConnected
            ? NovaMeetingCopilotStatus.ready
            : NovaMeetingCopilotStatus.disconnected,
      ),
    );
  }

  void startListening() {
    if (!canStartListening) {
      throw StateError('Host-approved Zoom access is required.');
    }

    _setState(
      _state.copyWith(
        status: NovaMeetingCopilotStatus.listening,
        novaMuted: true,
        hostInvitedToSpeak: false,
      ),
    );
  }

  void pauseListening() {
    if (!canPauseListening) {
      throw StateError('Nova is not actively listening.');
    }

    _setState(
      _state.copyWith(
        status: NovaMeetingCopilotStatus.paused,
        novaMuted: true,
        hostInvitedToSpeak: false,
      ),
    );
  }

  void stopListening() {
    if (!canStopListening) {
      throw StateError('There is no active meeting session to stop.');
    }

    _setState(
      _state.copyWith(
        status: NovaMeetingCopilotStatus.stopped,
        novaMuted: true,
        hostInvitedToSpeak: false,
      ),
    );
  }

  void grantHostSpeechInvite(bool invited) {
    if (!_state.hostAuthorized && invited) {
      throw StateError(
        'Host authorization is required before a speech invite.',
      );
    }

    _setState(
      _state.copyWith(
        hostInvitedToSpeak: invited,
        novaMuted: invited ? _state.novaMuted : true,
      ),
    );
  }

  void beginSpeaking() {
    if (!canSpeakNow) {
      throw StateError('Nova may speak only after an explicit host invite.');
    }

    _setState(
      _state.copyWith(
        status: NovaMeetingCopilotStatus.speaking,
        novaMuted: false,
      ),
    );
  }

  void muteNova() {
    final NovaMeetingCopilotStatus nextStatus =
        _state.status == NovaMeetingCopilotStatus.speaking
        ? NovaMeetingCopilotStatus.listening
        : _state.status;

    _setState(
      _state.copyWith(
        status: nextStatus,
        novaMuted: true,
        hostInvitedToSpeak: false,
      ),
    );
  }

  void updateActiveSeconds(int seconds) {
    if (seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'Must not be negative.');
    }

    _setState(_state.copyWith(activeSeconds: seconds));
  }

  void addTranscriptLine(NovaTranscriptLine line) {
    _setState(
      _state.copyWith(
        transcript: <NovaTranscriptLine>[..._state.transcript, line],
      ),
    );
  }

  void replaceInsights({
    List<NovaMeetingInsight>? decisions,
    List<NovaMeetingInsight>? actionItems,
    List<NovaMeetingInsight>? deadlines,
    List<NovaMeetingInsight>? risks,
    List<NovaMeetingInsight>? openQuestions,
    List<NovaMeetingInsight>? takeaways,
  }) {
    _setState(
      _state.copyWith(
        decisions: decisions,
        actionItems: actionItems,
        deadlines: deadlines,
        risks: risks,
        openQuestions: openQuestions,
        takeaways: takeaways,
      ),
    );
  }

  void _setState(NovaMeetingCopilotState nextState) {
    _state = nextState;
    notifyListeners();
  }
}

class KorlixMeetingCopilotScreen extends StatelessWidget {
  const KorlixMeetingCopilotScreen({
    super.key,
    required this.controller,
    required this.korlixLogo,
    required this.novaPortrait,
    this.onConnectZoom,
    this.onAskNova,
    this.onThirtySecondUpdate,
    this.onSpeakNow,
  });

  final NovaMeetingCopilotController controller;
  final ImageProvider<Object> korlixLogo;
  final ImageProvider<Object> novaPortrait;
  final VoidCallback? onConnectZoom;
  final VoidCallback? onAskNova;
  final VoidCallback? onThirtySecondUpdate;
  final VoidCallback? onSpeakNow;

  static const Color _navy = Color(0xFF031426);
  static const Color _panel = Color(0xFF0A223A);
  static const Color _panelAlt = Color(0xFF0E2D49);
  static const Color _cyan = Color(0xFF22D8FF);
  static const Color _mutedText = Color(0xFF9CB8CA);
  static const Color _border = Color(0xFF1A5872);
  static const Color _danger = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final NovaMeetingCopilotState state = controller.state;

        return Scaffold(
          backgroundColor: _navy,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 980;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Header(korlixLogo: korlixLogo, state: state),
                      const SizedBox(height: 18),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 4,
                              child: _NovaControlPanel(
                                controller: controller,
                                novaPortrait: novaPortrait,
                                state: state,
                                onConnectZoom: onConnectZoom,
                                onAskNova: onAskNova,
                                onThirtySecondUpdate: onThirtySecondUpdate,
                                onSpeakNow: onSpeakNow,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 6,
                              child: _TranscriptPanel(state: state),
                            ),
                          ],
                        )
                      else ...<Widget>[
                        _NovaControlPanel(
                          controller: controller,
                          novaPortrait: novaPortrait,
                          state: state,
                          onConnectZoom: onConnectZoom,
                          onAskNova: onAskNova,
                          onThirtySecondUpdate: onThirtySecondUpdate,
                          onSpeakNow: onSpeakNow,
                        ),
                        const SizedBox(height: 18),
                        _TranscriptPanel(state: state),
                      ],
                      const SizedBox(height: 18),
                      _InsightGrid(state: state),
                      const SizedBox(height: 18),
                      const _PrivacyBanner(),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.korlixLogo, required this.state});

  final ImageProvider<Object> korlixLogo;
  final NovaMeetingCopilotState state;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KorlixMeetingCopilotScreen._panel,
        border: Border.all(color: KorlixMeetingCopilotScreen._border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Semantics(
              image: true,
              label: 'Official KORLIX logo',
              child: Image(
                image: korlixLogo,
                width: 58,
                height: 58,
                fit: BoxFit.contain,
              ),
            ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'KORLIX AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'NOVA MEETING COPILOT',
                  style: TextStyle(
                    color: KorlixMeetingCopilotScreen._cyan,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Semantics(
              label: 'Nova status: ${state.status.label}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: KorlixMeetingCopilotScreen._panelAlt,
                  border: Border.all(color: KorlixMeetingCopilotScreen._cyan),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  state.status.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NovaControlPanel extends StatelessWidget {
  const _NovaControlPanel({
    required this.controller,
    required this.novaPortrait,
    required this.state,
    required this.onConnectZoom,
    required this.onAskNova,
    required this.onThirtySecondUpdate,
    required this.onSpeakNow,
  });

  final NovaMeetingCopilotController controller;
  final ImageProvider<Object> novaPortrait;
  final NovaMeetingCopilotState state;
  final VoidCallback? onConnectZoom;
  final VoidCallback? onAskNova;
  final VoidCallback? onThirtySecondUpdate;
  final VoidCallback? onSpeakNow;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Nova Assistant Controls',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Semantics(
              image: true,
              label: 'Nova, KORLIX AI meeting assistant',
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KorlixMeetingCopilotScreen._cyan,
                    width: 3,
                  ),
                  image: DecorationImage(
                    image: novaPortrait,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            state.meetingTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.participantCount} participants • '
            '${state.activeSeconds}s active processing',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KorlixMeetingCopilotScreen._mutedText,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: state.novaMuted
                  ? const Color(0x3322D8FF)
                  : const Color(0x33FF6B6B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              state.novaMuted
                  ? 'NOVA IS MUTED — she may speak only after a host invite.'
                  : 'NOVA IS SPEAKING — host-controlled audio is active.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: state.novaMuted
                    ? KorlixMeetingCopilotScreen._cyan
                    : KorlixMeetingCopilotScreen._danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: <Widget>[
              ElevatedButton.icon(
                key: const Key('zoom-connect-button'),
                onPressed: onConnectZoom,
                icon: const Icon(Icons.link),
                label: const Text('Connect Zoom'),
              ),
              ElevatedButton.icon(
                key: const Key('start-listening-button'),
                onPressed: controller.canStartListening
                    ? controller.startListening
                    : null,
                icon: const Icon(Icons.hearing),
                label: const Text('Start Listening'),
              ),
              OutlinedButton.icon(
                key: const Key('pause-listening-button'),
                onPressed: controller.canPauseListening
                    ? controller.pauseListening
                    : null,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Pause Listening'),
              ),
              OutlinedButton.icon(
                key: const Key('stop-listening-button'),
                onPressed: controller.canStopListening
                    ? controller.stopListening
                    : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Listening'),
              ),
              OutlinedButton.icon(
                key: const Key('ask-nova-button'),
                onPressed: controller.canAskNova ? onAskNova : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Ask Nova'),
              ),
              OutlinedButton.icon(
                key: const Key('thirty-second-update-button'),
                onPressed: controller.canAskNova ? onThirtySecondUpdate : null,
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('30-Second Update'),
              ),
              ElevatedButton.icon(
                key: const Key('speak-now-button'),
                onPressed: controller.canSpeakNow && onSpeakNow != null
                    ? () {
                        controller.beginSpeaking();
                        onSpeakNow!();
                      }
                    : null,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('Speak Now'),
              ),
              OutlinedButton.icon(
                key: const Key('mute-nova-button'),
                onPressed: state.novaMuted ? null : controller.muteNova,
                icon: const Icon(Icons.mic_off_outlined),
                label: const Text('Mute Nova'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.state});

  final NovaMeetingCopilotState state;

  @override
  Widget build(BuildContext context) {
    final List<NovaTranscriptLine> lines = state.transcript;

    return _Panel(
      title: 'Live Transcript Preview',
      child: lines.isEmpty
          ? const _EmptyState(
              icon: Icons.subtitles_off_outlined,
              message:
                  'No transcript is being collected. Host approval and '
                  'an active listening session are required.',
            )
          : Column(
              children: lines
                  .map(
                    (NovaTranscriptLine line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: KorlixMeetingCopilotScreen._panelAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                line.timestampLabel,
                                style: const TextStyle(
                                  color: KorlixMeetingCopilotScreen._cyan,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: <InlineSpan>[
                                      TextSpan(
                                        text: '${line.speaker}: ',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      TextSpan(
                                        text: line.text,
                                        style: const TextStyle(
                                          color: KorlixMeetingCopilotScreen
                                              ._mutedText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _InsightGrid extends StatelessWidget {
  const _InsightGrid({required this.state});

  final NovaMeetingCopilotState state;

  @override
  Widget build(BuildContext context) {
    final List<_InsightGroup> groups = <_InsightGroup>[
      _InsightGroup('Decisions', Icons.fact_check_outlined, state.decisions),
      _InsightGroup('Action Items', Icons.task_alt_outlined, state.actionItems),
      _InsightGroup('Deadlines', Icons.event_outlined, state.deadlines),
      _InsightGroup('Risks', Icons.warning_amber_outlined, state.risks),
      _InsightGroup('Open Questions', Icons.help_outline, state.openQuestions),
      _InsightGroup('Key Takeaways', Icons.lightbulb_outline, state.takeaways),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 1100
            ? 3
            : width >= 700
            ? 2
            : 1;
        final double spacing = 14;
        final double itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: groups
              .map(
                (_InsightGroup group) => SizedBox(
                  width: itemWidth,
                  child: _InsightPanel(group: group),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _InsightGroup {
  const _InsightGroup(this.title, this.icon, this.items);

  final String title;
  final IconData icon;
  final List<NovaMeetingInsight> items;
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.group});

  final _InsightGroup group;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: group.title,
      leading: Icon(group.icon, color: KorlixMeetingCopilotScreen._cyan),
      child: group.items.isEmpty
          ? const Text(
              'Nothing captured yet.',
              style: TextStyle(color: KorlixMeetingCopilotScreen._mutedText),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: group.items
                  .map(
                    (NovaMeetingInsight item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '• ${item.title}: ${item.detail}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.leading});

  final String title;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KorlixMeetingCopilotScreen._panel,
        border: Border.all(color: KorlixMeetingCopilotScreen._border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: KorlixMeetingCopilotScreen._mutedText),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KorlixMeetingCopilotScreen._mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071C2D),
        border: Border.all(color: KorlixMeetingCopilotScreen._border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.verified_user_outlined,
              color: KorlixMeetingCopilotScreen._cyan,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Disclosure and host control are required. Nova remains muted '
                'by default. This foundation does not join meetings, collect '
                'media, save transcripts, or inject audio.',
                style: TextStyle(color: KorlixMeetingCopilotScreen._mutedText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
