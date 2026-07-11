import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:video_player/video_player.dart';

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
    required this.error,
    required this.userTranscript,
    required this.assistantTranscript,
    required this.eventLog,
    required this.rendererReady,
    required this.remoteRenderer,
    required this.onStart,
    required this.onToggleMute,
    required this.onSendText,
    required this.onEnd,
  });

  final String characterId;
  final String language;
  final String status;

  final bool connecting;
  final bool connected;
  final bool muted;

  final String? error;
  final String userTranscript;
  final String assistantTranscript;
  final List<String> eventLog;

  final bool rendererReady;
  final rtc.RTCVideoRenderer remoteRenderer;

  final Future<void> Function()? onStart;
  final Future<void> Function()? onToggleMute;
  final Future<void> Function(String text)? onSendText;
  final Future<void> Function()? onEnd;

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

    if (widget.muted) {
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
        return 'Microphone muted';

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
        return 'Unmute when you are ready to continue.';

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
    final end = widget.onEnd;

    if (end != null && (widget.connected || widget.connecting)) {
      await end();
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

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final phaseColor = _phaseColor(phase);

    final canStart =
        !widget.connecting && !widget.connected && widget.onStart != null;

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
                const SizedBox(height: 22),
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
                if (!widget.connected && !widget.connecting)
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
                        icon: widget.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: widget.muted ? 'Unmute' : 'Mute',
                        color: const Color(0xFF69D9E8),
                        onPressed: widget.onToggleMute == null
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
                      _circleAction(
                        icon: Icons.keyboard_rounded,
                        label: 'Keyboard',
                        color: const Color(0xFFB794F4),
                        onPressed: widget.onSendText == null
                            ? null
                            : () => unawaited(_openKeyboardComposer()),
                      ),
                      _circleAction(
                        icon: Icons.stop_rounded,
                        label: 'End',
                        color: const Color(0xFFFF5E73),
                        filled: true,
                        onPressed: canEnd
                            ? () => unawaited(widget.onEnd!())
                            : null,
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
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

// KORLIX_LIVE_CONVO_CHARACTER_STAGE_V1_END
