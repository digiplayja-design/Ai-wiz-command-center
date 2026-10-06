import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'korlix_screensaver_controller.dart';
import 'korlix_smoke_veil.dart';

/// Keeps the navigator and its media mounted. This is a visual effect, not a
/// device lock or app lifecycle change. Social alerts are rendered above it.
class KorlixSmokeScreensaver extends StatefulWidget {
  const KorlixSmokeScreensaver({
    super.key,
    required this.child,
    this.controller,
    this.sessionChanges,
    this.idleDuration = KorlixScreensaverController.idleDuration,
  });
  final Widget child;
  final KorlixScreensaverController? controller;
  final Listenable? sessionChanges;
  final Duration idleDuration;
  @override
  State<KorlixSmokeScreensaver> createState() => _KorlixSmokeScreensaverState();
}

class _KorlixSmokeScreensaverState extends State<KorlixSmokeScreensaver>
    with WidgetsBindingObserver {
  KorlixScreensaverController get _controller =>
      widget.controller ?? kKorlixScreensaver;
  Timer? _timer;
  bool _visible = false, _foreground = true, _accessibleNavigation = false;
  int _activityRevision = 0, _previewRevision = 0;
  final _pointers = <int>{};
  final _keys = <PhysicalKeyboardKey>{}, _wakeKeys = <PhysicalKeyboardKey>{};
  final _wakeFocus = FocusNode(debugLabel: 'Smoke screensaver');
  FocusNode? _previousFocus;
  TextEditingController? _editor;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    FocusManager.instance.addListener(_focusChanged);
    widget.sessionChanges?.addListener(_sessionChanged);
    _bindController();
  }

  void _bindController() {
    _activityRevision = _controller.activityRevision;
    _previewRevision = _controller.previewRevision;
    _controller.addListener(_settingsChanged);
    unawaited(_controller.restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    if (accessible && !_accessibleNavigation && _visible) {
      _dismiss(restoreFocus: false);
    }
    _accessibleNavigation = accessible;
    if (!_visible) _arm();
  }

  @override
  void didUpdateWidget(covariant KorlixSmokeScreensaver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? kKorlixScreensaver).removeListener(
        _settingsChanged,
      );
      _bindController();
      _dismiss(restoreFocus: false);
    }
    if (oldWidget.sessionChanges != widget.sessionChanges) {
      oldWidget.sessionChanges?.removeListener(_sessionChanged);
      widget.sessionChanges?.addListener(_sessionChanged);
    }
    if (oldWidget.idleDuration != widget.idleDuration) _arm();
  }

  void _settingsChanged() {
    if (!mounted) return;
    if (_previewRevision != _controller.previewRevision) {
      _previewRevision = _controller.previewRevision;
      _show(preview: true);
      return;
    }
    final navigation = _activityRevision != _controller.activityRevision;
    _activityRevision = _controller.activityRevision;
    if (navigation || !_controller.enabled) _dismiss(restoreFocus: !navigation);
    if (!_visible) _arm();
  }

  void _sessionChanged() => _dismiss(restoreFocus: false);

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        !_controller.enabled ||
        !_foreground ||
        _visible ||
        _accessibleNavigation ||
        _pointers.isNotEmpty ||
        _keys.isNotEmpty) {
      return;
    }
    _timer = Timer(widget.idleDuration, _show);
  }

  void _show({bool preview = false}) {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        _visible ||
        !_foreground ||
        (!preview &&
            (!_controller.enabled ||
                _accessibleNavigation ||
                _pointers.isNotEmpty ||
                _keys.isNotEmpty))) {
      return;
    }
    _previousFocus = FocusManager.instance.primaryFocus;
    setState(() => _visible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) _wakeFocus.requestFocus();
    });
  }

  void _dismiss({bool restoreFocus = true}) {
    if (!mounted) return;
    if (_visible) {
      final previous = _previousFocus;
      _previousFocus = null;
      setState(() => _visible = false);
      if (restoreFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_visible &&
              _foreground &&
              previous?.context?.mounted == true &&
              previous!.canRequestFocus) {
            previous.requestFocus();
          }
        });
      }
    }
    _arm();
  }

  void _focusChanged() {
    final next = _visible
        ? null
        : FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>()
              ?.widget
              .controller;
    if (identical(next, _editor)) return;
    _editor?.removeListener(_editing);
    _editor = next;
    _editor?.addListener(_editing);
  }

  void _editing() {
    if (!_visible) _arm();
  }

  KeyEventResult _key(KeyEvent event) {
    if (!_foreground) return KeyEventResult.ignored;
    final consume = _visible || _wakeKeys.contains(event.physicalKey);
    if (event is KeyUpEvent) {
      _keys.remove(event.physicalKey);
      _wakeKeys.remove(event.physicalKey);
    } else {
      _keys.add(event.physicalKey);
      if (_visible) _wakeKeys.add(event.physicalKey);
    }
    _dismiss();
    return consume ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _down(PointerEvent event) {
    _pointers.add(event.pointer);
    _dismiss();
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    _dismiss();
  }

  void _move(PointerEvent event) {
    if (event.delta != Offset.zero) _dismiss();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pointers.clear();
    _keys.clear();
    _wakeKeys.clear();
    _dismiss(restoreFocus: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_settingsChanged);
    widget.sessionChanges?.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    FocusManager.instance.removeListener(_focusChanged);
    _editor?.removeListener(_editing);
    _wakeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: _up,
    onPointerMove: _move,
    onPointerHover: _move,
    onPointerSignal: (_) => _dismiss(),
    onPointerPanZoomStart: _down,
    onPointerPanZoomUpdate: (_) => _dismiss(),
    onPointerPanZoomEnd: _up,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: _visible,
          child: IgnorePointer(ignoring: _visible, child: widget.child),
        ),
        if (_visible)
          Positioned.fill(
            child: Focus(
              focusNode: _wakeFocus,
              child: Semantics(
                key: const Key('smoke-screensaver'),
                button: true,
                container: true,
                label: 'Smoke screensaver. Tap anywhere to return to KORLIX.',
                onTap: _dismiss,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: const KorlixSmokeVeil(),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
