import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:video_player/video_player.dart';

import 'korlix_live_convo_attachment.dart';
import 'korlix_live_convo_attachment_tray.dart';
import 'korlix_live_convo_camera_sheet.dart';
import 'korlix_live_convo_agent_sheet.dart';
import 'korlix_live_convo_file_submission.dart';
import 'package:ai_wiz_command_center/live_docs/korlix_live_docs_generation.dart';

import 'korlix_live_convo_transcript_export.dart';
// KORLIX_LIVE_CONVO_CHARACTER_STAGE_V1_BEGIN

enum _KorlixLiveVisualPhase {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  interrupted,
  muted,
  disconnected,
}

class KorlixLiveConvoCharacterStage extends StatefulWidget {
  const KorlixLiveConvoCharacterStage({
    super.key,
    required this.characterId,
    required this.language,
    required this.status,
    required this.connecting,
    required this.connected,
    required this.muted,
    this.paused = false,
    required this.error,
    required this.userTranscript,
    required this.assistantTranscript,
    required this.transcriptEntries,
    required this.sessionStartedAt,
    required this.eventLog,
    required this.rendererReady,
    required this.remoteRenderer,
    required this.onStart,
    this.onTogglePause,
    required this.onToggleMute,
    required this.onSendText,
    required this.onSendImage,
    required this.onEnd,
    this.onRequestClose,
    // KORLIX_LIVE_CONVO_AGENT_HUB_STAGE_BUILD131_BEGIN
    this.activeAgentName = 'My Assistant',
    this.activeAgentDescription =
        'General-purpose Korlix help with private training and memory.',
    this.activeAgentIconName = 'auto_awesome',
    this.activeAgentAccentHex = '21D4F4',
    this.activeAgentMemoryEnabled = true,
    this.activeAgentVersion = 1,
    this.onOpenAgentHub,
    // KORLIX_LIVE_CONVO_VOICE_SELECTOR_STAGE_BUILD131_V1
    this.selectedVoiceName = 'Marin',
    this.selectedVoicePresentation = 'Feminine-presenting',
    this.selectedAccentName = 'Clear International',
    this.onOpenVoiceSelector,
    // KORLIX_LIVE_CONVO_AGENT_HUB_STAGE_BUILD131_CONSTRUCTOR_END
    this.liveDocsCaptureActive = false,
    this.liveDocsCapturedTurnCount = 0,
    this.liveDocsBriefReady = false,
    this.onCreateDocument,
    this.liveDocsAttachments = const <KorlixLiveConvoAttachment>[],
    this.onPickLiveDocsAttachments,
    this.onRemoveLiveDocsAttachment,
    this.onClearLiveDocsAttachments,
    this.liveDocsFileSubmissionState =
        KorlixLiveConvoFileSubmissionState.localOnly,
    this.liveDocsFileSubmissionError,
    this.onSubmitLiveDocsAttachments,
    this.liveDocsGenerationState = KorlixLiveDocsGenerationState.idle,
    this.liveDocsGenerationResult,
    this.liveDocsGenerationError,
    this.onShareLiveDocsArtifact,
    this.onReviseLiveDocsReport,
    this.onRetryLiveDocsReport,
  });

  final String characterId;
  final String language;
  final String status;

  final bool connecting;
  final bool connected;
  final bool muted;

  // KORLIX_LIVE_CONVO_HARD_LOCKED_PAUSE_STAGE_BUILD131_V1
  final bool paused;

  final String? error;
  final String userTranscript;
  final String assistantTranscript;
  final List<KorlixLiveConvoTranscriptEntry> transcriptEntries;
  final DateTime? sessionStartedAt;
  final List<String> eventLog;

  final bool rendererReady;
  final rtc.RTCVideoRenderer remoteRenderer;

  final Future<void> Function()? onStart;
  final Future<void> Function()? onTogglePause;
  final Future<void> Function()? onToggleMute;
  final Future<void> Function(String text)? onSendText;
  final KorlixLiveConvoImageSender? onSendImage;
  final Future<void> Function()? onEnd;
  final Future<bool> Function()? onRequestClose;

  final String activeAgentName;
  final String activeAgentDescription;
  final String activeAgentIconName;
  final String activeAgentAccentHex;
  final bool activeAgentMemoryEnabled;
  final int activeAgentVersion;
  final Future<void> Function()? onOpenAgentHub;
  final String selectedVoiceName;
  final String selectedVoicePresentation;
  final String selectedAccentName;
  final Future<void> Function()? onOpenVoiceSelector;

  final bool liveDocsCaptureActive;
  final int liveDocsCapturedTurnCount;
  final bool liveDocsBriefReady;
  final Future<void> Function()? onCreateDocument;

  final List<KorlixLiveConvoAttachment> liveDocsAttachments;
  final Future<void> Function()? onPickLiveDocsAttachments;
  final void Function(String attachmentId)? onRemoveLiveDocsAttachment;
  final VoidCallback? onClearLiveDocsAttachments;

  final KorlixLiveConvoFileSubmissionState liveDocsFileSubmissionState;

  final String? liveDocsFileSubmissionError;
  final Future<void> Function()? onSubmitLiveDocsAttachments;

  final KorlixLiveDocsGenerationState liveDocsGenerationState;
  final KorlixLiveDocsGenerationResult? liveDocsGenerationResult;
  final String? liveDocsGenerationError;
  final Future<void> Function(KorlixLiveDocsArtifact artifact)?
  onShareLiveDocsArtifact;
  final Future<void> Function()? onReviseLiveDocsReport;
  final Future<void> Function()? onRetryLiveDocsReport;

  @override
  State<KorlixLiveConvoCharacterStage> createState() =>
      _KorlixLiveConvoCharacterStageState();
}

class _KorlixLiveConvoCharacterStageState
    extends State<KorlixLiveConvoCharacterStage>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;

  VideoPlayerController? _characterController;
  int _characterLoadGeneration = 0;
  bool _characterReady = false;
  bool _characterFailed = false;

  Timer? _timer;
  int _elapsedSeconds = 0;

  bool _showTranscript = true;
  bool _showDiagnostics = false;

  // KORLIX_LIVE_CONVO_KEYBOARD_UI_V1
  final TextEditingController _typedMessageController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    unawaited(_loadCharacterFrame());
    _syncTimer(previousConnected: false);
  }

  @override
  void didUpdateWidget(covariant KorlixLiveConvoCharacterStage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.characterId != widget.characterId) {
      unawaited(_loadCharacterFrame());
    }

    if (oldWidget.connected != widget.connected) {
      _syncTimer(previousConnected: oldWidget.connected);
    }
  }

  _KorlixStageCharacter get _character {
    return _korlixStageCharacterFor(widget.characterId);
  }

  Color get _activeAgentAccent {
    return korlixLiveConvoAgentAccent(widget.activeAgentAccentHex);
  }

  IconData get _activeAgentIcon {
    return korlixLiveConvoAgentIcon(widget.activeAgentIconName);
  }

  String get _activeAgentName {
    final clean = widget.activeAgentName.trim();

    return clean.isEmpty ? 'My Assistant' : clean;
  }

  String get _activeAgentDescription {
    final clean = widget.activeAgentDescription.trim();

    return clean.isEmpty ? 'Private, trainable LIVE CONVO agent.' : clean;
  }

  int get _activeAgentVersion {
    return widget.activeAgentVersion < 1 ? 1 : widget.activeAgentVersion;
  }

  void _syncTimer({required bool previousConnected}) {
    if (widget.connected) {
      if (!previousConnected) {
        _elapsedSeconds = 0;
      }

      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !widget.connected) {
          return;
        }

        setState(() {
          _elapsedSeconds++;
        });
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _loadCharacterFrame() async {
    final generation = ++_characterLoadGeneration;
    final character = _character;

    final previous = _characterController;
    _characterController = null;

    if (mounted) {
      setState(() {
        _characterReady = false;
        _characterFailed = false;
      });
    }

    if (previous != null) {
      await previous.dispose();
    }

    final controller = VideoPlayerController.asset(
      character.assetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(false);

      final duration = controller.value.duration;

      final framePosition = duration.inMilliseconds > 900
          ? const Duration(milliseconds: 700)
          : Duration.zero;

      await controller.seekTo(framePosition);
      await controller.pause();

      if (!mounted || generation != _characterLoadGeneration) {
        await controller.dispose();
        return;
      }

      setState(() {
        _characterController = controller;
        _characterReady = true;
        _characterFailed = false;
      });
    } catch (_) {
      await controller.dispose();

      if (!mounted || generation != _characterLoadGeneration) {
        return;
      }

      setState(() {
        _characterReady = false;
        _characterFailed = true;
      });
    }
  }

  _KorlixLiveVisualPhase get _phase {
    final status = widget.status.toLowerCase();
    final error = widget.error?.trim();

    if (error != null && error.isNotEmpty) {
      return _KorlixLiveVisualPhase.disconnected;
    }

    if (status.contains('failed') ||
        status.contains('error') ||
        status.contains('disconnected')) {
      return _KorlixLiveVisualPhase.disconnected;
    }

    if (widget.paused || widget.muted) {
      return _KorlixLiveVisualPhase.muted;
    }

    if (widget.connecting ||
        status.contains('preparing') ||
        status.contains('requesting') ||
        status.contains('creating secure') ||
        status.contains('connecting')) {
      return _KorlixLiveVisualPhase.connecting;
    }

    if (status.contains('interrupted') || status.contains('cancelled')) {
      return _KorlixLiveVisualPhase.interrupted;
    }

    if (status.contains('speaking')) {
      return _KorlixLiveVisualPhase.speaking;
    }

    if (status.contains('thinking')) {
      return _KorlixLiveVisualPhase.thinking;
    }

    if (widget.connected ||
        status.contains('listening') ||
        status.contains('session ready')) {
      return _KorlixLiveVisualPhase.listening;
    }

    return _KorlixLiveVisualPhase.idle;
  }

  Color _phaseColor(_KorlixLiveVisualPhase phase) {
    switch (phase) {
      case _KorlixLiveVisualPhase.connecting:
      case _KorlixLiveVisualPhase.thinking:
        return const Color(0xFFB794F4);

      case _KorlixLiveVisualPhase.listening:
        return const Color(0xFF69D9E8);

      case _KorlixLiveVisualPhase.speaking:
        return const Color(0xFFFFD166);

      case _KorlixLiveVisualPhase.interrupted:
        return const Color(0xFFFF5E73);

      case _KorlixLiveVisualPhase.muted:
        return const Color(0xFF6C8B96);

      case _KorlixLiveVisualPhase.disconnected:
        return const Color(0xFF8B98A3);

      case _KorlixLiveVisualPhase.idle:
        return const Color(0xFF69D9E8);
    }
  }

  String _phaseTitle(_KorlixLiveVisualPhase phase) {
    switch (phase) {
      case _KorlixLiveVisualPhase.connecting:
        return 'Connecting to ${_character.name}…';

      case _KorlixLiveVisualPhase.listening:
        return '${_character.name} is listening';

      case _KorlixLiveVisualPhase.thinking:
        return '${_character.name} is thinking';

      case _KorlixLiveVisualPhase.speaking:
        return '${_character.name} is speaking';

      case _KorlixLiveVisualPhase.interrupted:
        return 'Interrupted — listening again';

      case _KorlixLiveVisualPhase.muted:
        return widget.paused
            ? 'LIVE CONVO paused and locked'
            : 'Microphone muted';

      case _KorlixLiveVisualPhase.disconnected:
        return 'LIVE CONVO disconnected';

      case _KorlixLiveVisualPhase.idle:
        return 'Ready for LIVE CONVO';
    }
  }

  String _phaseSubtitle(_KorlixLiveVisualPhase phase) {
    switch (phase) {
      case _KorlixLiveVisualPhase.connecting:
        return 'Preparing a secure live voice session.';

      case _KorlixLiveVisualPhase.listening:
        return 'Speak naturally. You can interrupt at any time.';

      case _KorlixLiveVisualPhase.thinking:
        return 'Preparing a clear response.';

      case _KorlixLiveVisualPhase.speaking:
        return 'Start talking to interrupt the response.';

      case _KorlixLiveVisualPhase.interrupted:
        return 'Continue speaking when ready.';

      case _KorlixLiveVisualPhase.muted:
        return widget.paused
            ? 'The provider voice session is closed. Tap Resume to '
                  'continue with the current temporary chat context.'
            : 'Unmute when you are ready to continue.';

      case _KorlixLiveVisualPhase.disconnected:
        return 'Check your connection, then reconnect.';

      case _KorlixLiveVisualPhase.idle:
        return 'Tap Start and begin a natural conversation.';
    }
  }

  String get _elapsedText {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _closeStage() async {
    final requestClose = widget.onRequestClose;
    final end = widget.onEnd;
    final hasCurrentChat =
        widget.connected ||
        widget.connecting ||
        widget.paused ||
        widget.transcriptEntries.isNotEmpty;

    if (hasCurrentChat) {
      if (requestClose != null) {
        final shouldClose = await requestClose();

        if (!shouldClose) {
          return;
        }
      } else if (end != null) {
        await end();
      }
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  Widget _characterPortrait() {
    final controller = _characterController;

    if (_characterReady &&
        controller != null &&
        controller.value.isInitialized) {
      final videoSize = controller.value.size;

      return ClipOval(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: videoSize.width <= 0 ? 320 : videoSize.width,
              height: videoSize.height <= 0 ? 320 : videoSize.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12364A), Color(0xFF09131E)],
        ),
      ),
      alignment: Alignment.center,
      child: _characterFailed
          ? Icon(
              Icons.person_rounded,
              size: 82,
              color: Colors.white.withValues(alpha: 0.78),
            )
          : const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF69D9E8),
              ),
            ),
    );
  }

  Future<void> _openKeyboardComposer() async {
    final sendText = widget.onSendText;

    if (sendText == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect LIVE CONVO before typing a message.'),
        ),
      );
      return;
    }

    _typedMessageController.clear();

    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF06131C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> submitTypedMessage() async {
              final text = _typedMessageController.text.trim();

              if (text.isEmpty || sending) {
                return;
              }

              setSheetState(() {
                sending = true;
              });

              try {
                await sendText(text);

                _typedMessageController.clear();

                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  sending = false;
                });

                final message = error
                    .toString()
                    .replaceFirst('Bad state: ', '')
                    .replaceFirst('StateError: ', '');

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }

            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.keyboard_rounded,
                        color: Color(0xFFB794F4),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Type to Korlix',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close keyboard message',
                        onPressed: sending
                            ? null
                            : () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFFA9C6CF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your typed message will join the same '
                    'LIVE CONVO and Korlix will answer aloud.',
                    style: TextStyle(color: Color(0xFFA9C6CF), height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _typedMessageController,
                    autofocus: true,
                    enabled: !sending,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      unawaited(submitTypedMessage());
                    },
                    style: const TextStyle(
                      color: Color(0xFFE4EBEE),
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your message to Korlix…',
                      hintStyle: const TextStyle(color: Color(0xFF78909B)),
                      filled: true,
                      fillColor: const Color(0xFF020A10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: const BorderSide(color: Color(0xFF345467)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: const BorderSide(color: Color(0xFF345467)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: const BorderSide(
                          color: Color(0xFFB794F4),
                          width: 1.7,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: sending
                        ? null
                        : () => unawaited(submitTypedMessage()),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB794F4),
                      foregroundColor: const Color(0xFF081019),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      sending ? 'Sending…' : 'Send to Korlix',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final button = filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              minimumSize: const Size(66, 58),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Icon(icon, size: 27),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              minimumSize: const Size(66, 58),
              side: BorderSide(color: color.withValues(alpha: 0.65)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Icon(icon, size: 27),
          );

    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcriptCard({
    required String label,
    required Color accent,
    required String text,
    required String emptyText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text.trim().isEmpty ? emptyText : text.trim(),
            style: TextStyle(
              color: text.trim().isEmpty
                  ? const Color(0xFF78909B)
                  : const Color(0xFFE4EBEE),
              height: 1.42,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _transcriptClock(DateTime timestamp) {
    final local = timestamp.toLocal();

    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  DateTime get _effectiveSessionStartedAt {
    return widget.sessionStartedAt ??
        DateTime.now().subtract(Duration(seconds: _elapsedSeconds));
  }

  Widget _fullConversationHistory() {
    final entries = widget.transcriptEntries;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF31566A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.forum_rounded,
                color: Color(0xFF69D9E8),
                size: 19,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'FULL CONVERSATION',
                  style: TextStyle(
                    color: Color(0xFF69D9E8),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              Text(
                '${entries.length} '
                '${entries.length == 1 ? 'turn' : 'turns'}',
                style: const TextStyle(
                  color: Color(0xFF78909B),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'The complete conversation will appear '
              'here as you speak, type, use the camera, '
              'and receive Korlix replies.',
              style: TextStyle(color: Color(0xFF78909B), height: 1.4),
            )
          else
            for (final entry in entries) ...[
              Builder(
                builder: (context) {
                  final isUser =
                      entry.role == KorlixLiveConvoTranscriptRole.user;

                  final accent = isUser
                      ? const Color(0xFF69D9E8)
                      : const Color(0xFFFFD166);

                  final label = isUser ? 'YOU' : _character.name.toUpperCase();

                  final source = korlixLiveConvoSourceLabel(entry.source);

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF020A10),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: accent.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                            if (isUser && source.isNotEmpty) ...[
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  source,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _transcriptClock(entry.timestamp),
                              style: const TextStyle(
                                color: Color(0xFF78909B),
                                fontSize: 10.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        SelectableText(
                          entry.text.trim(),
                          style: const TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontSize: 14,
                            height: 1.42,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Future<void> _copyAllConversation() async {
    if (widget.transcriptEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There is no LIVE CONVO transcript to copy yet.'),
        ),
      );

      return;
    }

    try {
      await copyKorlixLiveConvoTranscript(
        characterName: _character.name,
        startedAt: _effectiveSessionStartedAt,
        durationSeconds: _elapsedSeconds,
        entries: widget.transcriptEntries,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full LIVE CONVO transcript copied.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not copy transcript: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _shareFullConversation() async {
    if (widget.transcriptEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There is no LIVE CONVO transcript to share yet.'),
        ),
      );

      return;
    }

    try {
      await shareKorlixLiveConvoTranscript(
        context: context,
        characterName: _character.name,
        startedAt: _effectiveSessionStartedAt,
        durationSeconds: _elapsedSeconds,
        entries: widget.transcriptEntries,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share transcript: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _transcriptExportActions() {
    final hasEntries = widget.transcriptEntries.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: hasEntries
                ? () => unawaited(_copyAllConversation())
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF69D9E8),
              side: const BorderSide(color: Color(0xFF31566A)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text(
              'Copy All',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: hasEntries
                ? () => unawaited(_shareFullConversation())
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB794F4),
              foregroundColor: const Color(0xFF081019),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text(
              'Save / Share',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _agentStatusPill({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.54)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveAgentCard() {
    final accent = _activeAgentAccent;

    final enabled = widget.onOpenAgentHub != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled
            ? () {
                unawaited(widget.onOpenAgentHub!());
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: accent.withValues(alpha: 0.10),
            border: Border.all(
              color: accent.withValues(alpha: enabled ? 0.72 : 0.36),
              width: enabled ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 20),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: accent.withValues(alpha: 0.16),
                  border: Border.all(color: accent.withValues(alpha: 0.72)),
                ),
                child: Icon(_activeAgentIcon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _activeAgentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF0F7F8),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ACTIVE AGENT',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.65,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _activeAgentDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA9C6CF),
                        height: 1.35,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _agentStatusPill(
                          text:
                              'TRAINABLE · '
                              'V$_activeAgentVersion',
                          color: accent,
                          icon: Icons.school_rounded,
                        ),
                        _agentStatusPill(
                          text: widget.activeAgentMemoryEnabled
                              ? 'LONG-TERM MEMORY'
                              : 'MEMORY OFF',
                          color: widget.activeAgentMemoryEnabled
                              ? const Color(0xFF62D6A7)
                              : const Color(0xFF8299A2),
                          icon: widget.activeAgentMemoryEnabled
                              ? Icons.psychology_alt_rounded
                              : Icons.memory_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                enabled
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                color: enabled ? accent : const Color(0xFF718A96),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceSelectorCard() {
    const accent = Color(0xFF62D6A7);
    final enabled = widget.onOpenVoiceSelector != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled
            ? () {
                unawaited(widget.onOpenVoiceSelector!());
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: accent.withValues(alpha: 0.08),
            border: Border.all(
              color: accent.withValues(alpha: enabled ? 0.68 : 0.34),
              width: enabled ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.voice_chat_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice: ${widget.selectedVoiceName}',
                      style: const TextStyle(
                        color: Color(0xFFF1F6F8),
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.selectedVoicePresentation} • '
                      '${widget.selectedAccentName}',
                      style: const TextStyle(
                        color: Color(0xFFA9C6CF),
                        height: 1.3,
                        fontSize: 12.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: enabled ? 0.95 : 0.38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final phaseColor = _phaseColor(phase);

    final canStart =
        !widget.connecting &&
        !widget.connected &&
        !widget.paused &&
        widget.onStart != null;

    final canEnd = widget.onEnd != null;

    return Scaffold(
      backgroundColor: const Color(0xFF01060A),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.28),
                    radius: 1.05,
                    colors: [
                      phaseColor.withValues(alpha: 0.15),
                      const Color(0xFF04111A),
                      const Color(0xFF01060A),
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close LIVE CONVO',
                      onPressed: _closeStage,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: const Color(0xFFE4EBEE),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071722),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: phaseColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final alpha =
                                  0.45 +
                                  (math.sin(
                                            _pulseController.value *
                                                math.pi *
                                                2,
                                          ) +
                                          1) *
                                      0.22;

                              return Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: phaseColor.withValues(alpha: alpha),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: phaseColor.withValues(alpha: 0.65),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'LIVE CONVO',
                            style: TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _elapsedText,
                      style: const TextStyle(
                        color: Color(0xFFA9C6CF),
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  _character.eyebrow,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: phaseColor.withValues(alpha: 0.88),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _character.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF2F6F8),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return SizedBox(
                        width: 318,
                        height: 318,
                        child: CustomPaint(
                          painter: _KorlixLiveRingPainter(
                            progress: _pulseController.value,
                            color: phaseColor,
                            phase: phase,
                          ),
                          child: Center(
                            child: AnimatedScale(
                              scale:
                                  0.985 +
                                  0.018 *
                                      math.sin(
                                        _pulseController.value * math.pi * 2,
                                      ),
                              duration: const Duration(milliseconds: 160),
                              child: Container(
                                width: 222,
                                height: 222,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF06131C),
                                  border: Border.all(
                                    color: phaseColor.withValues(alpha: 0.76),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: phaseColor.withValues(alpha: 0.25),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: _characterPortrait(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _phaseTitle(phase),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: phaseColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _phaseSubtitle(phase),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    height: 1.35,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 14),
                _buildActiveAgentCard(),
                const SizedBox(height: 10),
                _buildVoiceSelectorCard(),
                const SizedBox(height: 18),
                if (widget.error != null &&
                    widget.error!.trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF35121A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF5E73).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      widget.error!,
                      style: const TextStyle(
                        color: Color(0xFFFFA7B1),
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!widget.connected && !widget.connecting && !widget.paused)
                  FilledButton.icon(
                    onPressed: canStart
                        ? () => unawaited(widget.onStart!())
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: phaseColor,
                      foregroundColor: const Color(0xFF031017),
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: Icon(
                      phase == _KorlixLiveVisualPhase.disconnected
                          ? Icons.refresh_rounded
                          : Icons.graphic_eq_rounded,
                    ),
                    label: Text(
                      phase == _KorlixLiveVisualPhase.disconnected
                          ? 'Reconnect LIVE CONVO'
                          : 'Start LIVE CONVO',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 16,
                    children: [
                      _circleAction(
                        icon: widget.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: widget.paused ? 'Resume' : 'Lock Pause',
                        color: widget.paused
                            ? const Color(0xFF62D6A7)
                            : const Color(0xFFFFD166),
                        filled: widget.paused,
                        onPressed: widget.onTogglePause == null
                            ? null
                            : () => unawaited(widget.onTogglePause!()),
                      ),
                      _circleAction(
                        icon: widget.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: widget.muted ? 'Unmute' : 'Mute',
                        color: const Color(0xFF69D9E8),
                        onPressed: widget.paused || widget.onToggleMute == null
                            ? null
                            : () => unawaited(widget.onToggleMute!()),
                      ),
                      _circleAction(
                        icon: _showTranscript
                            ? Icons.notes_rounded
                            : Icons.notes_outlined,
                        label: 'Transcript',
                        color: const Color(0xFFB794F4),
                        onPressed: () {
                          setState(() {
                            _showTranscript = !_showTranscript;
                          });
                        },
                      ),
                      // KORLIX_LIVE_CONVO_AGENT_HUB_ACTION_BUILD131
                      _circleAction(
                        icon: Icons.hub_rounded,
                        label: 'Agents',
                        color: _activeAgentAccent,
                        onPressed: widget.onOpenAgentHub == null
                            ? null
                            : () {
                                unawaited(widget.onOpenAgentHub!());
                              },
                      ),
                      // KORLIX_LIVE_CONVO_CAMERA_UI_V1
                      _circleAction(
                        icon: Icons.photo_camera_rounded,
                        label: 'Camera',
                        color: const Color(0xFFFFD166),
                        onPressed:
                            widget.onSendImage == null ||
                                phase == _KorlixLiveVisualPhase.speaking ||
                                phase == _KorlixLiveVisualPhase.thinking
                            ? null
                            : () => unawaited(
                                showKorlixLiveConvoCameraSheet(
                                  context: context,
                                  currentlyMuted: widget.muted,
                                  onToggleMute: widget.onToggleMute,
                                  onSendImage: widget.onSendImage!,
                                ),
                              ),
                      ),
                      _circleAction(
                        icon: Icons.keyboard_rounded,
                        label: 'Keyboard',
                        color: const Color(0xFFB794F4),
                        onPressed: widget.onSendText == null
                            ? null
                            : () => unawaited(_openKeyboardComposer()),
                      ),
                      // KORLIX_LIVE_CONVO_UPLOAD_ACTION_V1
                      _circleAction(
                        icon: Icons.attach_file_rounded,
                        label: widget.liveDocsAttachments.isEmpty
                            ? 'Upload'
                            : 'Files ${widget.liveDocsAttachments.length}',
                        color: const Color(0xFF69D9E8),
                        onPressed:
                            widget.liveDocsFileSubmissionState.isSubmitting ||
                                widget.onPickLiveDocsAttachments == null
                            ? null
                            : () => unawaited(
                                widget.onPickLiveDocsAttachments!(),
                              ),
                      ),
                      // KORLIX_LIVE_DOCS_ACTION_V1
                      _circleAction(
                        icon: widget.liveDocsGenerationResult != null
                            ? Icons.verified_rounded
                            : Icons.description_rounded,
                        label: widget.liveDocsGenerationState.isBusy
                            ? (widget.liveDocsGenerationState ==
                                      KorlixLiveDocsGenerationState.revising
                                  ? 'Revising'
                                  : 'Generating')
                            : widget.liveDocsGenerationResult != null
                            ? 'Report Ready'
                            : widget.liveDocsCaptureActive
                            ? (widget.liveDocsCapturedTurnCount == 0
                                  ? 'Doc Brief'
                                  : 'Turns ${widget.liveDocsCapturedTurnCount}')
                            : (widget.liveDocsBriefReady
                                  ? 'Generate Doc'
                                  : 'Create Doc'),
                        color: const Color(0xFF62D6A7),
                        onPressed:
                            widget.liveDocsGenerationState.isBusy ||
                                widget.onCreateDocument == null
                            ? null
                            : () => unawaited(widget.onCreateDocument!()),
                      ),
                      _circleAction(
                        icon: Icons.stop_rounded,
                        label: 'Stop',
                        color: const Color(0xFFFF5E73),
                        filled: true,
                        onPressed: canEnd
                            ? () => unawaited(widget.onEnd!())
                            : null,
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                if (widget.liveDocsAttachments.isNotEmpty) ...[
                  KorlixLiveConvoAttachmentTray(
                    attachments: widget.liveDocsAttachments,
                    submissionState: widget.liveDocsFileSubmissionState,
                    submissionError: widget.liveDocsFileSubmissionError,
                    onAddFiles: widget.onPickLiveDocsAttachments,
                    onRemoveFile: widget.onRemoveLiveDocsAttachment,
                    onClearFiles: widget.onClearLiveDocsAttachments,
                    onSubmitFiles: widget.onSubmitLiveDocsAttachments,
                  ),
                  const SizedBox(height: 14),
                ],
                if (widget.liveDocsGenerationState !=
                        KorlixLiveDocsGenerationState.idle ||
                    widget.liveDocsGenerationResult != null) ...[
                  KorlixLiveDocsReportCard(
                    state: widget.liveDocsGenerationState,
                    result: widget.liveDocsGenerationResult,
                    error: widget.liveDocsGenerationError,
                    onShareArtifact: widget.onShareLiveDocsArtifact,
                    onRevise: widget.onReviseLiveDocsReport,
                    onRetry: widget.onRetryLiveDocsReport,
                  ),
                  const SizedBox(height: 14),
                ],
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 240),
                  crossFadeState: _showTranscript
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Column(
                    children: [
                      _transcriptCard(
                        label: 'YOU SAID',
                        accent: const Color(0xFF69D9E8),
                        text: widget.userTranscript,
                        emptyText: 'Your live transcript will appear here.',
                      ),
                      const SizedBox(height: 12),
                      _transcriptCard(
                        label: '${_character.name.toUpperCase()} SAID',
                        accent: const Color(0xFFFFD166),
                        text: widget.assistantTranscript,
                        emptyText:
                            '${_character.name}’s live transcript will appear here.',
                      ),
                    ],
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
                // KORLIX_LIVE_CONVO_FULL_TRANSCRIPT_UI_V1
                if (_showTranscript) ...[
                  const SizedBox(height: 12),
                  _fullConversationHistory(),
                  const SizedBox(height: 12),
                  _transcriptExportActions(),
                ],
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showDiagnostics = !_showDiagnostics;
                    });
                  },
                  icon: Icon(
                    _showDiagnostics
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(
                    _showDiagnostics ? 'Hide diagnostics' : 'Show diagnostics',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF78909B),
                  ),
                ),
                if (_showDiagnostics)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06111A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF234454)),
                    ),
                    child: SelectableText(
                      widget.eventLog.isEmpty
                          ? 'No realtime events yet.'
                          : widget.eventLog.take(35).join('\n'),
                      style: const TextStyle(
                        color: Color(0xFF8BA7B0),
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                if (widget.rendererReady)
                  Opacity(
                    opacity: 0.01,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: rtc.RTCVideoView(widget.remoteRenderer),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _typedMessageController.dispose();
    _timer?.cancel();
    _pulseController.dispose();
    unawaited(_characterController?.dispose());
    super.dispose();
  }
}

class _KorlixLiveRingPainter extends CustomPainter {
  const _KorlixLiveRingPainter({
    required this.progress,
    required this.color,
    required this.phase,
  });

  final double progress;
  final Color color;
  final _KorlixLiveVisualPhase phase;

  bool get _showVoiceBars {
    return phase == _KorlixLiveVisualPhase.listening ||
        phase == _KorlixLiveVisualPhase.speaking ||
        phase == _KorlixLiveVisualPhase.thinking ||
        phase == _KorlixLiveVisualPhase.connecting;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide * 0.415;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.16);

    canvas.drawCircle(center, baseRadius, basePaint);
    canvas.drawCircle(
      center,
      baseRadius + 12,
      basePaint..color = color.withValues(alpha: 0.08),
    );

    const segmentCount = 44;

    for (var i = 0; i < segmentCount; i++) {
      final angle = -math.pi / 2 + i * (math.pi * 2 / segmentCount);

      final wave = (math.sin(progress * math.pi * 2 + i * 0.57) + 1) / 2;

      final activeStrength = _showVoiceBars ? 0.24 + wave * 0.72 : 0.23;

      final segmentPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = phase == _KorlixLiveVisualPhase.speaking ? 4.8 : 3.4
        ..color = color.withValues(alpha: activeStrength);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: baseRadius),
        angle,
        math.pi * 2 / segmentCount * 0.56,
        false,
        segmentPaint,
      );

      if (_showVoiceBars) {
        final barLength =
            5 + wave * (phase == _KorlixLiveVisualPhase.speaking ? 20 : 13);

        final start = Offset(
          center.dx + math.cos(angle) * (baseRadius + 15),
          center.dy + math.sin(angle) * (baseRadius + 15),
        );

        final end = Offset(
          center.dx + math.cos(angle) * (baseRadius + 15 + barLength),
          center.dy + math.sin(angle) * (baseRadius + 15 + barLength),
        );

        canvas.drawLine(
          start,
          end,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.3
            ..color = color.withValues(alpha: 0.18 + wave * 0.7),
        );
      }
    }

    final orbitAngle = progress * math.pi * 2 - math.pi / 2;

    final orbitPoint = Offset(
      center.dx + math.cos(orbitAngle) * (baseRadius + 28),
      center.dy + math.sin(orbitAngle) * (baseRadius + 28),
    );

    canvas.drawCircle(
      orbitPoint,
      4.5,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _KorlixLiveRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.phase != phase;
  }
}

class _KorlixStageCharacter {
  const _KorlixStageCharacter({
    required this.id,
    required this.name,
    required this.eyebrow,
    required this.assetPath,
  });

  final String id;
  final String name;
  final String eyebrow;
  final String assetPath;
}

_KorlixStageCharacter _korlixStageCharacterFor(String rawId) {
  final id = rawId
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  switch (id) {
    case 'chee_chai_chee':
    case 'cheechai':
    case 'cheechaichee':
      return const _KorlixStageCharacter(
        id: 'chee_chai_chee',
        name: 'Chee Chai Chee',
        eyebrow: 'PRO AI CHARACTER',
        assetPath: 'assets/characters/chee_chai_chee/intro.mp4',
      );

    case 'phil':
      return const _KorlixStageCharacter(
        id: 'phil',
        name: 'Phil',
        eyebrow: 'PRO AI CHARACTER',
        assetPath: 'assets/characters/phil/intro.mp4',
      );

    case 'yuna':
      return const _KorlixStageCharacter(
        id: 'yuna',
        name: 'Yuna',
        eyebrow: 'ULTRA PREMIUM CHARACTER',
        assetPath: 'assets/characters/yuna/intro.mp4',
      );

    case 'ji_a':
    case 'jia':
      return const _KorlixStageCharacter(
        id: 'ji_a',
        name: 'Ji-A',
        eyebrow: 'ULTRA PREMIUM CHARACTER',
        assetPath: 'assets/characters/ji-a/intro.mp4',
      );

    case 'jj':
    default:
      return const _KorlixStageCharacter(
        id: 'jj',
        name: 'JJ',
        eyebrow: 'FEATURED AI CHARACTER',
        assetPath: 'assets/characters/jj/intro.mp4',
      );
  }
}

// KORLIX_LIVE_CONVO_AGENT_HUB_STAGE_BUILD131_END
// KORLIX_LIVE_CONVO_CHARACTER_STAGE_V1_END
