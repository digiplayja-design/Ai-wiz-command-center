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
part 'korlix_live_voice_workspace.dart';

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
    this.microphoneActive,
    this.inventoryResults,
    this.schedulingPanel,
    this.schedulingMode = false,
    this.bookkeepingMode = false,
    this.bookkeepingPanelBuilder,
    this.crmMode = false,
    this.crmPanelBuilder,
    this.workforceMode = false,
    this.workforcePanelBuilder,
    this.fieldProofMode = false,
    this.fieldProofPanelBuilder,
    this.musicMode = false,
    this.musicPanelBuilder,
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

  final Widget Function(Future<bool> Function())? inventoryResults;
  final Widget? schedulingPanel;
  final bool schedulingMode;
  final bool crmMode;
  final Widget Function(Future<void> Function(Map<String, dynamic>))? crmPanelBuilder;
  final bool workforceMode;
  final Widget Function(Future<void> Function(Map<String, dynamic>))? workforcePanelBuilder;
  final bool fieldProofMode;
  final Widget Function(Future<void> Function(Map<String, dynamic>))? fieldProofPanelBuilder;
  final bool musicMode;
  final Widget Function(Future<void> Function(Map<String, dynamic>))?
  musicPanelBuilder;
  final bool bookkeepingMode;
  final Widget Function(Future<void> Function(Map<String, dynamic>))?
  bookkeepingPanelBuilder;
  final String characterId;
  final String language;
  final String status;

  final bool connecting;
  final bool connected;
  final bool muted;
  final bool? microphoneActive;

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
  bool _allowClose = false;
  bool _closing = false;
  bool _showDiagnostics = false;

  // KORLIX_LIVE_CONVO_KEYBOARD_UI_V1
  final TextEditingController _typedMessageController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    unawaited(_loadCharacterFrame());
    _syncTimer(previousConnected: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        (widget.connected || widget.connecting) &&
        !widget.paused;
    if (animate && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!animate) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant KorlixLiveConvoCharacterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();

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

    if (widget.paused) {
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

    if (widget.muted) {
      return _KorlixLiveVisualPhase.muted;
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

  String _phaseTitle(_KorlixLiveVisualPhase phase) {
    switch (phase) {
      case _KorlixLiveVisualPhase.connecting:
        return 'Connecting to $_voiceDisplayName…';

      case _KorlixLiveVisualPhase.listening:
        return '$_voiceDisplayName is listening';

      case _KorlixLiveVisualPhase.thinking:
        return '$_voiceDisplayName is thinking';

      case _KorlixLiveVisualPhase.speaking:
        return '$_voiceDisplayName is speaking';

      case _KorlixLiveVisualPhase.interrupted:
        return 'Interrupted — listening again';

      case _KorlixLiveVisualPhase.muted:
        return widget.paused ? 'Conversation paused' : 'Microphone muted';

      case _KorlixLiveVisualPhase.disconnected:
        return 'LIVE CONVO disconnected';

      case _KorlixLiveVisualPhase.idle:
        return 'A little space to think out loud.';
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
            ? 'Your microphone is off and the voice session is closed. '
                  'Resume whenever you are ready.'
            : 'Unmute when you are ready to continue.';

      case _KorlixLiveVisualPhase.disconnected:
        return 'Your chat stays here. Check your connection, then try again.';

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

  Future<void> _finishCrmAction(Map<String, dynamic> result) async {
    if (_closing || !mounted || !widget.crmMode || widget.connected ||
        widget.connecting || !widget.paused || widget.microphoneActive == true)
      return;
    _closing = true;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop<Map<String, dynamic>>(result);
  }

  Future<void> _finishWorkforceAction(Map<String, dynamic> result) async {
    if (_closing || !mounted || !widget.workforceMode || widget.connected ||
        widget.connecting || !widget.paused || widget.microphoneActive == true)
      return;
    _closing = true;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop<Map<String, dynamic>>(result);
  }

  Future<void> _finishFieldProofAction(Map<String, dynamic> result) async {
    if (_closing || !mounted || !widget.fieldProofMode || widget.connected ||
        widget.connecting || !widget.paused || widget.microphoneActive == true)
      return;
    _closing = true;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop<Map<String, dynamic>>(result);
  }

  Future<void> _finishMusicAction(Map<String, dynamic> result) async {
    if (_closing || !mounted || !widget.musicMode || widget.connected ||
        widget.connecting || !widget.paused || widget.microphoneActive == true)
      return;
    _closing = true;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop<Map<String, dynamic>>(result);
  }

  Future<void> _finishBookkeepingReview(Map<String, dynamic> draft) async {
    if (_closing ||
        !mounted ||
        !widget.bookkeepingMode ||
        widget.connected ||
        widget.connecting ||
        !widget.paused ||
        widget.microphoneActive == true)
      return;
    _closing = true;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop<Map<String, dynamic>>(draft);
  }

  Future<bool> _closeInventoryView() async {
    await _closeStage();
    if (!_allowClose) return false;
    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  Future<void> _closeStage() async {
    if (_closing) return;
    _closing = true;
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
          _closing = false;
          return;
        }
      } else if (end != null) {
        await end();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
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
          : const Icon(
              Icons.graphic_eq_rounded,
              size: 54,
              color: Color(0xFF87E4D2),
            ),
    );
  }

  Future<void> _openKeyboardComposer() async {
    final sendText = widget.onSendText;

    if (sendText == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect LIVE CONVO before typing a message.')),
      );
      return;
    }

    _typedMessageController.clear();

    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
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
                if (!mounted || !sheetContext.mounted) {
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

            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.keyboard_rounded, color: _accent),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Type to $_voiceDisplayName',
                            style: TextStyle(
                              color: _ink,
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
                          icon: Icon(Icons.close_rounded),
                          color: _secondary,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your typed message will join the same '
                      'conversation and $_voiceDisplayName will answer aloud.',
                      style: TextStyle(color: _secondary, height: 1.35),
                    ),
                    SizedBox(height: 14),
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
                      style: TextStyle(color: _ink, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Type your message…',
                        hintStyle: TextStyle(color: _secondary),
                        filled: true,
                        fillColor: _canvas,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(color: _accent, width: 1.7),
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: sending
                          ? null
                          : () => unawaited(submitTypedMessage()),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: _onAccent,
                        minimumSize: Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                      icon: sending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send_rounded),
                      label: Text(
                        sending ? 'Sending…' : 'Send message',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
        characterName: _voiceDisplayName,
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
        characterName: _voiceDisplayName,
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

  void _updateStage(VoidCallback action) => setState(action);

  @override
  Widget build(BuildContext context) => _buildVoiceWorkspace();

  @override
  void dispose() {
    _typedMessageController.dispose();
    _timer?.cancel();
    _pulseController.dispose();
    unawaited(_characterController?.dispose());
    super.dispose();
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
