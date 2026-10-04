import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../sounds/korlix_sound_service.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_call_controller.dart';

class SocialCallScreen extends StatefulWidget {
  const SocialCallScreen({
    super.key,
    required this.client,
    required this.peer,
    required this.video,
    this.incoming,
    this.media,
    this.sounds,
    this.ringExpiresAt,
    this.controller,
    this.onMinimize,
  });
  final SocialClient client;
  final SocialMap peer;
  final bool video;
  final SocialMap? incoming;
  final SocialCallMedia? media;
  final KorlixSoundService? sounds;
  final DateTime? ringExpiresAt;

  /// A hosted controller belongs to the app, not this temporary route.
  final SocialCallController? controller;
  final VoidCallback? onMinimize;
  @override
  State<SocialCallScreen> createState() => _SocialCallScreenState();
}

class _SocialCallScreenState extends State<SocialCallScreen>
    with WidgetsBindingObserver {
  late SocialMap _displayPeer = widget.peer;
  Timer? _presencePoll;
  bool _checkingPresence = false, _foreground = true;
  late final call =
      widget.controller ??
      SocialCallController(
        client: widget.client,
        peer: widget.peer,
        video: widget.video,
        incoming: widget.incoming,
        media: widget.media,
        sounds: widget.sounds,
        ringExpiresAt: widget.ringExpiresAt,
      );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    call.addListener(_change);
    unawaited(call.initialize());
    unawaited(_refreshPeer());
    _presencePoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground &&
          !call.ended &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refreshPeer());
      }
    });
  }

  Future<void> _refreshPeer() async {
    if (_checkingPresence || !widget.client.available) return;
    _checkingPresence = true;
    try {
      final result = await widget.client.get('member', {
        'peer': widget.peer['id'],
      });
      if (!mounted || !widget.client.available) return;
      final profile = socialMap(result['profile']);
      if (profile['id'] == widget.peer['id']) {
        setState(() => _displayPeer = profile);
      } else {
        setState(() => _displayPeer = {..._displayPeer, 'online': null});
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _displayPeer =
              e is SocialException && [401, 403, 404].contains(e.status)
              ? {'name': 'Unavailable member', 'color': 'cyan'}
              : {..._displayPeer, 'online': null},
        );
      }
    } finally {
      _checkingPresence = false;
    }
  }

  void _change() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) call.resume();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      call.backgrounded();
    }
    if (state == AppLifecycleState.detached) unawaited(call.end('Call ended'));
  }

  @override
  void dispose() {
    _presencePoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    call.removeListener(_change);
    if (widget.controller == null) call.dispose();
    super.dispose();
  }

  Widget _control(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
    bool danger = false,
  }) {
    final s = korlixSkinOf(context);
    return SizedBox(
      width: 82,
      child: Column(
        children: [
          IconButton.filledTonal(
            tooltip: label,
            isSelected: selected,
            onPressed: action,
            style: IconButton.styleFrom(
              minimumSize: const Size(58, 58),
              backgroundColor: danger
                  ? const Color(0xFFE55068)
                  : selected
                  ? s.primary
                  : s.panelSoft,
              foregroundColor: danger
                  ? Colors.white
                  : selected
                  ? s.textOnAccent
                  : s.text,
            ),
            icon: Icon(
              icon,
              color: danger
                  ? Colors.white
                  : selected
                  ? s.textOnAccent
                  : s.text,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: s.mutedText),
          ),
        ],
      ),
    );
  }

  bool _soundPanelOpen = false;
  Widget _microphoneCheck({bool controls = false}) {
    final m = call.media, s = korlixSkinOf(context);
    return SocialPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                m.microphone && !m.microphoneInterrupted
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                color: m.microphoneSoundDetected
                    ? s.success
                    : m.microphoneInterrupted
                    ? s.danger
                    : s.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.microphoneStatus,
                  style: TextStyle(
                    color: s.text,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (m.microphoneLevel != null &&
              m.microphone &&
              !m.microphoneInterrupted) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (m.microphoneLevel! * 4).clamp(0, 1),
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
              color: s.success,
              backgroundColor: s.panelSoft,
              semanticsLabel: 'Microphone input level',
              semanticsValue: m.microphoneSoundDetected
                  ? 'Sound detected'
                  : 'Waiting for speech',
            ),
          ],
          if (controls ||
              m.microphoneInterrupted ||
              m.microphoneIssue.isNotEmpty) ...[
            const SizedBox(height: 12),
            KorlixActionButton(
              label: m.repairingMicrophone
                  ? 'Reconnecting microphone…'
                  : 'Reconnect microphone',
              icon: Icons.mic_external_on_rounded,
              busy: m.repairingMicrophone,
              tile: MediaQuery.textScalerOf(context).scale(1) > 1.3,
              onPressed: call.ended || m.repairingMicrophone
                  ? null
                  : () => unawaited(call.reconnectMicrophone()),
              expand: true,
            ),
            const SizedBox(height: 8),
            Text(
              m.microphoneIssue.isNotEmpty
                  ? m.microphoneIssue
                  : 'Reopens the microphone without ending this call. If you muted it, tap Unmute to speak.',
              style: TextStyle(
                color: m.microphoneIssue.isNotEmpty ? s.danger : s.mutedText,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _speakerPressed() {
    final a = call.media.audio;
    if (a.canRouteSpeaker) {
      unawaited(a.routeSpeaker(!a.speaker));
      unawaited(a.resume());
    } else {
      _speaker();
    }
  }

  void _speaker() {
    if (_soundPanelOpen) return;
    setState(() => _soundPanelOpen = true);
    // Keep this invocation inside the tap, before opening an asynchronous sheet.
    unawaited(call.media.audio.resume());
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: call,
        builder: (context, _) {
          final a = call.media.audio, s = korlixSkinOf(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.spatial_audio_off_rounded,
                        color: s.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Speaker & sound',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close sound controls',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    call.ended
                        ? 'This call has ended.'
                        : a.blocked
                        ? 'Your browser needs a tap to play the call.'
                        : a.selected
                        ? 'Sound enabled · using your device’s audio output.'
                        : 'Control how you hear the other person.',
                    style: TextStyle(color: s.mutedText, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  if (call.media.ready && !call.ended) ...[
                    _microphoneCheck(controls: true),
                    const SizedBox(height: 16),
                  ],
                  KorlixActionButton(
                    label: 'Resume sound',
                    icon: Icons.volume_up_rounded,
                    onPressed: call.ended ? null : () => unawaited(a.resume()),
                  ),
                  if (a.canTestSound) ...[
                    const SizedBox(height: 12),
                    KorlixActionButton(
                      label: a.testing ? 'Playing test sound…' : 'Test sound',
                      icon: Icons.music_note_rounded,
                      onPressed: call.ended || a.testing
                          ? null
                          : () => unawaited(a.testSound()),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plays three tones on your device to check sound. This does not call anyone.',
                      style: TextStyle(
                        color: s.mutedText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    call.state == 'ringing'
                        ? 'Waiting for the other person to answer. You will hear their voice after they answer and the call connects.'
                        : !call.connected
                        ? 'Connecting the call…'
                        : !call.media.audioStatsAvailable
                        ? 'Connected · tap Test sound if you cannot hear them.'
                        : call.media.incomingAudioBytes > 0
                        ? 'Incoming audio received · check your volume and output if it is silent.'
                        : 'Connected, but no incoming audio has arrived yet. Ask the other person to check their microphone.',
                    style: TextStyle(color: s.mutedText, height: 1.4),
                  ),
                  if (a.canRouteSpeaker)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Speakerphone'),
                      subtitle: const Text(
                        'Play through the phone’s loudspeaker',
                      ),
                      value: a.speaker,
                      onChanged: call.ended
                          ? null
                          : (v) => unawaited(a.routeSpeaker(v)),
                    ),
                  if (a.canSetVolume) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Call volume · ${(a.volume * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Slider(
                      semanticFormatterCallback: (v) =>
                          '${(v * 100).round()} percent',
                      value: a.volume,
                      onChanged: call.ended
                          ? null
                          : (v) => unawaited(a.setVolume(v)),
                    ),
                  ],
                  if (a.canChooseOutput)
                    TextButton.icon(
                      icon: const Icon(Icons.headphones_rounded),
                      label: const Text('Choose speaker or headphones'),
                      onPressed: call.ended
                          ? null
                          : () => unawaited(a.chooseOutput()),
                    ),
                  if (a.issue.isNotEmpty && !call.ended)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        a.issue,
                        style: TextStyle(color: s.primary, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SocialPanel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: s.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            a.guidance,
                            style: TextStyle(color: s.mutedText, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _soundPanelOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context), m = call.media;
    final displayPeer = widget.client.available
        ? _displayPeer
        : <String, dynamic>{'name': 'Connection', 'color': 'cyan'};
    final incoming = call.incoming && call.state == 'ringing' && !call.ended;
    final time =
        '${call.elapsed.inMinutes.toString().padLeft(2, '0')}:${(call.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.video ? 'Video call' : 'Audio call'),
        actions: [
          if (widget.onMinimize != null && !call.ended)
            IconButton(
              tooltip: 'Minimize call and keep using KORLIX',
              onPressed: widget.onMinimize,
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.people_alt_outlined, color: s.primary),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  children: [
                    Text(
                      'KORLIX SOCIAL',
                      style: TextStyle(
                        letterSpacing: 3,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: s.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.onMinimize != null && !call.ended)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          kIsWeb
                              ? 'Minimize to keep using KORLIX during your call. Keep this browser open; device sleep or closing the tab can interrupt it.'
                              : call.background.ready
                              ? 'Your audio can continue when KORLIX is in the background. Your camera turns off; tap Camera to turn it back on after returning.'
                              : 'Minimize to keep using KORLIX. Keep the app in the foreground on this device. Background audio also needs notification permission on Android.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: s.mutedText, height: 1.4),
                        ),
                      ),
                    SocialPanel(
                      padding: EdgeInsets.zero,
                      accent: s.primary,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(27),
                        child: SizedBox(
                          height: (box.maxHeight * .52).clamp(220, 460),
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      colors: [
                                        s.primary.withValues(alpha: .17),
                                        s.panelDeep,
                                      ],
                                      radius: 1,
                                    ),
                                  ),
                                ),
                              ),
                              if (!call.ended &&
                                  widget.video &&
                                  m.ready &&
                                  m.remoteCamera &&
                                  m.remote.srcObject != null)
                                Positioned.fill(
                                  child: rtc.RTCVideoView(
                                    m.remote,
                                    objectFit: rtc
                                        .RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitContain,
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: s.primary.withValues(
                                              alpha: .2,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: s.primary.withValues(
                                                alpha: .12,
                                              ),
                                              blurRadius: 45,
                                            ),
                                          ],
                                        ),
                                        child: SocialAvatar(
                                          member: displayPeer,
                                          size: box.maxHeight < 600 ? 70 : 100,
                                          showStatus: false,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      SocialMemberName(
                                        member: displayPeer,
                                        alignment: WrapAlignment.center,
                                        style: const TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if ('${displayPeer['profession'] ?? ''}'
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          displayPeer['profession'],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: s.mutedText),
                                        ),
                                      ],
                                      if (call.connected &&
                                          !m.remoteCamera &&
                                          widget.video) ...[
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Their camera is off',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (!call.ended &&
                                  widget.video &&
                                  m.ready &&
                                  m.camera)
                                Positioned(
                                  right: 12,
                                  top: 12,
                                  width: 88,
                                  height: 112,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: ColoredBox(
                                      color: s.panelDeep,
                                      child: rtc.RTCVideoView(
                                        m.local,
                                        mirror: true,
                                        objectFit: rtc
                                            .RTCVideoViewObjectFit
                                            .RTCVideoViewObjectFitCover,
                                      ),
                                    ),
                                  ),
                                ),
                              if (call.connected && !m.remoteMicrophone)
                                const Positioned(
                                  bottom: 12,
                                  child: Chip(
                                    avatar: Icon(
                                      Icons.mic_off_rounded,
                                      size: 16,
                                    ),
                                    label: Text('Their microphone is muted'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        call.status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: call.ended ? s.mutedText : s.text,
                        ),
                      ),
                    ),
                    if (call.connected)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          time,
                          style: TextStyle(color: s.primary, fontSize: 16),
                        ),
                      ),
                    if (!call.ended && m.ready && !incoming) ...[
                      const SizedBox(height: 16),
                      _microphoneCheck(),
                    ],
                    const SizedBox(height: 22),
                    if (call.ended)
                      KorlixActionButton(
                        label: 'Back to Social',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.pop(context),
                      )
                    else if (incoming)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          _control(
                            'Decline',
                            Icons.call_end_rounded,
                            () => unawaited(call.end('Call declined')),
                            danger: true,
                          ),
                          _control(
                            call.busy ? 'Preparing…' : 'Answer',
                            widget.video
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            call.busy ? null : () => unawaited(call.accept()),
                            selected: true,
                          ),
                        ],
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 16,
                        children: [
                          _control(
                            m.microphone ? 'Mute' : 'Unmute',
                            m.microphone
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            m.ready && !m.repairingMicrophone
                                ? call.toggleMicrophone
                                : null,
                            selected: !m.microphone,
                          ),
                          _control(
                            'Speaker',
                            Icons.volume_up_rounded,
                            m.ready ? _speakerPressed : null,
                            selected: _soundPanelOpen || m.audio.selected,
                          ),
                          if (widget.video)
                            _control(
                              m.camera ? 'Camera off' : 'Camera on',
                              m.camera
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              m.ready ? call.toggleCamera : null,
                              selected: !m.camera,
                            ),
                          _control(
                            'End call',
                            Icons.call_end_rounded,
                            () => unawaited(call.end('Call ended')),
                            danger: true,
                          ),
                        ],
                      ),
                    if (!call.ended && m.ready && !incoming) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Sound settings & test'),
                        onPressed: _speaker,
                      ),
                      if (call.state == 'ringing')
                        Text(
                          'Waiting for an answer',
                          style: TextStyle(color: s.mutedText, fontSize: 13),
                        ),
                    ],
                    if (!call.ended && m.audio.blocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: KorlixActionButton(
                          label: 'Tap to hear the call',
                          icon: Icons.volume_up_rounded,
                          onPressed: () => unawaited(m.audio.resume()),
                        ),
                      ),
                    if (!call.ended && widget.video && m.ready && m.camera)
                      TextButton.icon(
                        icon: const Icon(
                          Icons.flip_camera_ios_outlined,
                          size: 18,
                        ),
                        label: const Text('Switch camera'),
                        onPressed: () async {
                          try {
                            await m.switchCamera();
                          } catch (_) {
                            if (context.mounted) {
                              socialNotice(
                                context,
                                'Another camera is not available on this device.',
                              );
                            }
                          }
                        },
                      ),
                    const SizedBox(height: 20),
                    Text(
                      incoming
                          ? 'Your microphone${widget.video ? ' and camera' : ''} start only after you answer.'
                          : 'Calls are not recorded by KORLIX. Leaving this screen or putting Social in the background ends the call.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: s.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
