import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'korlix_entry_intro_controller.dart';

class KorlixEntryIntro extends StatefulWidget {
  const KorlixEntryIntro({super.key, this.controller});

  final KorlixEntryIntroController? controller;

  @override
  State<KorlixEntryIntro> createState() => _KorlixEntryIntroState();
}

class _KorlixEntryIntroState extends State<KorlixEntryIntro>
    with WidgetsBindingObserver {
  late final KorlixEntryIntroController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? KorlixEntryIntroController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.stop();
    }
    super.dispose();
  }

  Widget _playButton() => TextButton.icon(
    key: const Key('entry-intro-play'),
    onPressed: () {
      if (_controller.active) {
        _controller.stop();
      } else {
        unawaited(_controller.listen());
      }
    },
    icon: Icon(
      _controller.active
          ? Icons.stop_circle_outlined
          : Icons.volume_up_outlined,
    ),
    label: Text(
      _controller.active
          ? 'Stop welcome'
          : _controller.hasPlayed
          ? 'Replay welcome'
          : 'Hear the welcome',
    ),
  );

  String? get _notice => switch (_controller.state) {
    KorlixEntryIntroState.loading => 'Preparing the welcome…',
    KorlixEntryIntroState.muted =>
      'Sound is off or busy. You can read the welcome instead.',
    KorlixEntryIntroState.blocked =>
      'Tap again to listen, or read the welcome.',
    KorlixEntryIntroState.unavailable =>
      'Audio is unavailable. The written welcome is still here.',
    _ => null,
  };

  Future<void> _readIntro() async {
    final skin = korlixSkinOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: skin.panel,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome to Korlix',
                        style: TextStyle(
                          color: skin.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close introduction',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'AI voice introduction · about 30 seconds',
                  style: TextStyle(color: skin.mutedText, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      korlixEntryIntroText,
                      key: const Key('entry-intro-transcript'),
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) => _playButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            children: [
              _playButton(),
              TextButton(
                key: const Key('entry-intro-read'),
                onPressed: _readIntro,
                child: const Text('Read intro'),
              ),
            ],
          ),
          Text(
            'AI voice · about 30 seconds',
            style: TextStyle(color: skin.mutedText, fontSize: 12),
          ),
          if (_notice case final notice?) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                notice,
                style: TextStyle(color: skin.mutedText, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
