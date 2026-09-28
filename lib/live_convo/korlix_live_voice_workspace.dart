part of 'korlix_live_convo_character_stage.dart';

// K-Nova Live Voice: presentation only. Voice, approvals and tools remain owned
// by the session controller. The halo indicates state, never microphone volume.
extension _LiveVoiceWorkspace on _KorlixLiveConvoCharacterStageState {
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _canvas =>
      _dark ? const Color(0xFF080F19) : const Color(0xFFF4F7FA);
  Color get _surface => _dark ? const Color(0xFF101C29) : Colors.white;
  Color get _ink => _dark ? const Color(0xFFEAF2F6) : const Color(0xFF172B3A);
  Color get _secondary =>
      _dark ? const Color(0xFFA3B6C5) : const Color(0xFF506575);
  Color get _border =>
      _dark ? const Color(0xFF2A3B4D) : const Color(0xFFDCE5EA);
  Color get _accent =>
      _dark ? const Color(0xFF87E4D2) : const Color(0xFF006D62);
  Color get _onAccent => _dark ? const Color(0xFF072922) : Colors.white;
  Color get _danger =>
      _dark ? const Color(0xFFFFA8B1) : const Color(0xFFAB2941);
  String get _voiceDisplayName =>
      widget.activeAgentName.trim().isEmpty ||
          _activeAgentName == 'My Assistant' || _activeAgentName.toLowerCase() == 'nova' || widget.inventoryResults != null
      ? 'K-Nova'
      : _activeAgentName;

  Widget _panel(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(22),
  }) => Material(
    color: _surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: BorderSide(color: _border),
    ),
    child: Padding(padding: padding, child: child),
  );

  Widget _tag(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _voiceHeader() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close LIVE CONVO',
          onPressed: _closeStage,
          icon: const Icon(Icons.arrow_back_rounded),
          color: _ink,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'K-Nova',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'LIVE VOICE',
                style: TextStyle(
                  color: _secondary,
                  fontSize: 10,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Time in the current voice connection',
          child: _tag(
            _elapsedText,
            widget.connected
                ? Icons.graphic_eq_rounded
                : Icons.schedule_rounded,
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _voiceHero() {
    final phase = _phase;
    final micOn =
        widget.microphoneActive ??
        (widget.connected && !widget.muted && !widget.paused);
    final tone = phase == _KorlixLiveVisualPhase.disconnected
        ? _danger
        : _accent;
    return _panel(
      Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(
                'Voice · ${widget.selectedVoiceName}',
                Icons.spatial_audio_off_rounded,
              ),
              _tag('Avatar · ${_character.name}', Icons.face_rounded),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(244.0, constraints.maxWidth);
              return ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    child: SizedBox(
                      width: size * 0.63,
                      height: size * 0.63,
                      child: _characterPortrait(),
                    ),
                    builder: (context, portrait) => SizedBox(
                      width: size,
                      height: size,
                      child: CustomPaint(
                        painter: _NovaHaloPainter(
                          progress: _pulseController.value,
                          color: tone,
                          active: widget.connected && !widget.paused,
                          speaking: phase == _KorlixLiveVisualPhase.speaking,
                        ),
                        child: Center(child: portrait),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              _phaseTitle(phase),
              key: const Key('live-voice-status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: 25,
                height: 1.18,
                letterSpacing: -0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Text(
              _phaseSubtitle(phase),
              textAlign: TextAlign.center,
              style: TextStyle(color: _secondary, height: 1.5, fontSize: 14),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(
                micOn
                    ? 'Mic on'
                    : widget.muted
                    ? 'Mic muted'
                    : 'Mic off',
                micOn ? Icons.mic_none_rounded : Icons.mic_off_outlined,
              ),
              if (widget.connected)
                _tag('Interrupt naturally', Icons.waves_rounded),
            ],
          ),
          if (widget.error?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 18),
            Container(
              key: const Key('live-voice-error'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.error!,
                  style: TextStyle(color: _danger, height: 1.45),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Divider(color: _border),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: widget.onSendText == null
                    ? null
                    : () => unawaited(_openKeyboardComposer()),
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: const Text('Type a message'),
              ),
              TextButton.icon(
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
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Show a photo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conversationPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, color: _accent, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conversation',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
            ),
            IconButton(
              tooltip: _showTranscript ? 'Hide transcript' : 'Show transcript',
              onPressed: () =>
                  _updateStage(() => _showTranscript = !_showTranscript),
              icon: Icon(
                _showTranscript
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              color: _secondary,
            ),
          ],
        ),
        Text(
          'Your words, and the ideas they lead to.',
          style: TextStyle(color: _secondary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (_showTranscript) ...[
          if (widget.transcriptEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_outlined, color: _accent, size: 28),
                  const SizedBox(height: 18),
                  Text(
                    'What’s on your mind?',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Talk through an idea. Practice a conversation.\nMake a plan for what comes next.',
                    style: TextStyle(color: _secondary, height: 1.7),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Live captions will appear here once you start.',
                    style: TextStyle(
                      color: _secondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: Scrollbar(
                child: ListView.separated(
                  key: const Key('live-voice-transcript'),
                  shrinkWrap: true,
                  primary: false,
                  reverse: true,
                  itemCount: widget.transcriptEntries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final entry =
                        widget.transcriptEntries[widget
                                .transcriptEntries
                                .length -
                            1 -
                            index];
                    final user =
                        entry.role == KorlixLiveConvoTranscriptRole.user;
                    return Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: user ? _canvas : _accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              Text(
                                user ? 'You' : _voiceDisplayName,
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _transcriptClock(entry.timestamp),
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 11,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            entry.text.trim(),
                            style: TextStyle(
                              color: _ink,
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: widget.transcriptEntries.isEmpty
                    ? null
                    : () => unawaited(_copyAllConversation()),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy All'),
              ),
              OutlinedButton.icon(
                onPressed: widget.transcriptEntries.isEmpty
                    ? null
                    : () => unawaited(_shareFullConversation()),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Save / Share'),
              ),
            ],
          ),
        ] else
          Text(
            'Transcript hidden. Your conversation continues.',
            style: TextStyle(color: _secondary),
          ),
      ],
    ),
  );

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function()? action,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    leading: Icon(icon, color: _accent),
    title: Text(
      title,
      style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
    ),
    trailing: Icon(Icons.chevron_right_rounded, color: _secondary),
    onTap: action == null ? null : () => unawaited(action()),
  );

  Widget _voiceTools() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpansionTile(
          key: const Key('live-voice-tools'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: _secondary,
          collapsedIconColor: _secondary,
          title: Text(
            'Make it yours',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            widget.inventoryResults != null ? 'Voice & accent' : 'Voice, agent, files & documents',
            style: TextStyle(color: _secondary, fontSize: 12),
          ),
          children: [
            _settingsTile(
              icon: Icons.tune_rounded,
              title: 'Voice: ${widget.selectedVoiceName}',
              subtitle:
                  '${widget.selectedVoicePresentation} · ${widget.selectedAccentName}',
              action: widget.onOpenVoiceSelector,
            ),
            if (widget.inventoryResults == null) ...[
            _settingsTile(
              icon: _activeAgentIcon,
              title: _activeAgentName,
              subtitle:
                  '$_activeAgentDescription\nVersion $_activeAgentVersion · '
                  '${widget.activeAgentMemoryEnabled ? 'Memory on' : 'Memory off'}',
              action: widget.onOpenAgentHub,
            ),
            Divider(color: _border),
            _settingsTile(
              icon: Icons.attach_file_rounded,
              title: 'Files & attachments',
              subtitle: widget.liveDocsAttachments.isEmpty
                  ? 'Add context to your document'
                  : '${widget.liveDocsAttachments.length} files selected',
              action: widget.liveDocsFileSubmissionState.isSubmitting
                  ? null
                  : widget.onPickLiveDocsAttachments,
            ),
            _settingsTile(
              icon: Icons.description_outlined,
              title: widget.liveDocsGenerationState.isBusy
                  ? 'Preparing document…'
                  : widget.liveDocsGenerationResult != null
                  ? 'Document ready'
                  : widget.liveDocsBriefReady
                  ? 'Generate document'
                  : 'Create a document',
              subtitle: widget.liveDocsCaptureActive
                  ? '${widget.liveDocsCapturedTurnCount} conversation turns captured'
                  : 'Turn this conversation into something useful',
              action: widget.liveDocsGenerationState.isBusy
                  ? null
                  : widget.onCreateDocument,
            ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _updateStage(() => _showDiagnostics = !_showDiagnostics),
                icon: const Icon(Icons.info_outline_rounded, size: 17),
                label: Text(
                  _showDiagnostics
                      ? 'Hide connection details'
                      : 'Connection details',
                ),
              ),
            ),
            if (_showDiagnostics)
              SizedBox(
                width: double.infinity,
                child: SelectableText(
                  '${widget.status}\n${widget.eventLog.take(35).join('\n')}',
                  style: TextStyle(
                    color: _secondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
  );

  Widget _controlButton({
    required String label,
    required IconData icon,
    required Future<void> Function()? action,
    bool primary = false,
    bool danger = false,
  }) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, 54),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      backgroundColor: primary
          ? _accent
          : danger
          ? _danger.withValues(alpha: 0.1)
          : _canvas,
      foregroundColor: primary
          ? _onAccent
          : danger
          ? _danger
          : _ink,
      disabledBackgroundColor: _border.withValues(alpha: 0.4),
      disabledForegroundColor: _secondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    return FilledButton.icon(
      key: ValueKey('voice-$label'),
      onPressed: action == null ? null : () => unawaited(action()),
      style: style,
      icon: Icon(icon, size: 21),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _voiceControls() {
    final inactive = !widget.connected && !widget.connecting && !widget.paused;
    final hint = widget.paused
        ? 'Paused · microphone off · chat kept for this visit'
        : widget.connecting
        ? 'Allow microphone access when your browser asks.'
        : widget.connected
        ? 'Mute keeps the call open. Pause closes the voice connection.'
        : 'Your microphone turns on only after you start.';
    return Material(
      color: _surface,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inactive)
                    SizedBox(
                      width: 400,
                      child: _controlButton(
                        label: widget.error != null
                            ? 'Reconnect LIVE CONVO'
                            : 'Start LIVE CONVO',
                        icon: widget.error != null
                            ? Icons.refresh_rounded
                            : Icons.mic_rounded,
                        action: widget.onStart,
                        primary: true,
                      ),
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.paused)
                          _controlButton(
                            label: 'Resume',
                            icon: Icons.play_arrow_rounded,
                            action: widget.onTogglePause,
                            primary: true,
                          )
                        else
                          _controlButton(
                            label: widget.connecting ? 'Cancel' : 'Pause',
                            icon: widget.connecting
                                ? Icons.close_rounded
                                : Icons.pause_rounded,
                            action: widget.onTogglePause,
                          ),
                        if (!widget.paused && !widget.connecting)
                          _controlButton(
                            label: widget.muted ? 'Unmute' : 'Mute',
                            icon: widget.muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            action: widget.onToggleMute,
                            primary: true,
                          ),
                        _controlButton(
                          label: 'Stop',
                          icon: Icons.stop_rounded,
                          action: widget.onEnd,
                          danger: true,
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _secondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceWorkspace() => Theme(
    data: Theme.of(context).copyWith(
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: BorderSide(color: _border),
          minimumSize: const Size(48, 48),
        ),
      ),
    ),
    child: PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeStage());
      },
      child: Scaffold(
        backgroundColor: _canvas,
        bottomNavigationBar: _voiceControls(),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                children: [
                  _voiceHeader(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => ListView(
                        padding: EdgeInsets.fromLTRB(
                          constraints.maxWidth < 600 ? 12 : 24,
                          12,
                          constraints.maxWidth < 600 ? 12 : 24,
                          24,
                        ),
                        children: [
                          if (widget.inventoryResults != null) ...[widget.inventoryResults!(_closeInventoryView), const SizedBox(height: 16)],
                          if (constraints.maxWidth >= 850)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: _voiceHero()),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    children: [
                                      _conversationPanel(),
                                      const SizedBox(height: 16),
                                      _voiceTools(),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _voiceHero(),
                            const SizedBox(height: 16),
                            _conversationPanel(),
                            const SizedBox(height: 16),
                            _voiceTools(),
                          ],
                          if (widget.liveDocsAttachments.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: KorlixLiveConvoAttachmentTray(
                                attachments: widget.liveDocsAttachments,
                                submissionState:
                                    widget.liveDocsFileSubmissionState,
                                submissionError:
                                    widget.liveDocsFileSubmissionError,
                                onAddFiles: widget.onPickLiveDocsAttachments,
                                onRemoveFile: widget.onRemoveLiveDocsAttachment,
                                onClearFiles: widget.onClearLiveDocsAttachments,
                                onSubmitFiles:
                                    widget.onSubmitLiveDocsAttachments,
                              ),
                            ),
                          if (widget.liveDocsGenerationState !=
                                  KorlixLiveDocsGenerationState.idle ||
                              widget.liveDocsGenerationResult != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: KorlixLiveDocsReportCard(
                                state: widget.liveDocsGenerationState,
                                result: widget.liveDocsGenerationResult,
                                error: widget.liveDocsGenerationError,
                                onShareArtifact: widget.onShareLiveDocsArtifact,
                                onRevise: widget.onReviseLiveDocsReport,
                                onRetry: widget.onRetryLiveDocsReport,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.rendererReady)
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 1,
                        height: 1,
                        child: Opacity(
                          opacity: 0.01,
                          child: rtc.RTCVideoView(widget.remoteRenderer),
                        ),
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

class _NovaHaloPainter extends CustomPainter {
  const _NovaHaloPainter({
    required this.progress,
    required this.color,
    required this.active,
    required this.speaking,
  });
  final double progress;
  final Color color;
  final bool active, speaking;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.36;
    final breathe = active ? (math.sin(progress * math.pi * 2) + 1) / 2 : 0.0;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        radius + i * 11 + breathe * (speaking ? 5 : 2),
        Paint()
          ..color = color.withValues(alpha: 0.2 - i * 0.055)
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2 : 1,
      );
    }
    if (active) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 11),
        progress * math.pi * 2,
        math.pi * 0.48,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NovaHaloPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.active != active ||
      oldDelegate.speaking != speaking;
}
