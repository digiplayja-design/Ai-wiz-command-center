import 'dart:async';

import 'package:flutter/material.dart';

import 'korlix_sound_service.dart';

/// Keeps the app's effects alive across routes without taking over input.
class KorlixSoundHost extends StatefulWidget {
  const KorlixSoundHost({super.key, required this.child, this.service});

  final Widget child;
  final KorlixSoundService? service;

  @override
  State<KorlixSoundHost> createState() => _KorlixSoundHostState();
}

class _KorlixSoundHostState extends State<KorlixSoundHost>
    with WidgetsBindingObserver {
  KorlixSoundService get _sounds => widget.service ?? kKorlixSounds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  void _prepare() {
    final state = WidgetsBinding.instance.lifecycleState;
    _sounds.setForeground(state == null || state == AppLifecycleState.resumed);
    unawaited(_sounds.restore());
  }

  @override
  void didUpdateWidget(covariant KorlixSoundHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      (oldWidget.service ?? kKorlixSounds).setForeground(false);
      _prepare();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sounds.setForeground(state == AppLifecycleState.resumed);
  }

  void _activate(PointerEvent _) {
    // Activation is silent. Only real action callbacks produce click sounds.
    // Keep this call synchronous with the gesture for mobile browser policies.
    if (!_sounds.ready && _sounds.settings.enabled && !_sounds.quiet) {
      unawaited(_sounds.activate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sounds.setForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _activate,
    // Touch-down is not an activation gesture in WebKit. Retry on release,
    // including after an interrupted/backgrounded audio context.
    onPointerUp: _activate,
    child: widget.child,
  );
}
