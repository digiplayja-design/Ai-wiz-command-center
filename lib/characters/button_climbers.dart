import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'button_climber_painter.dart';
import 'button_climbers_settings.dart';

/// One transparent, noninteractive animation layer for the home viewport.
/// The real button render boxes supply its footholds, including after scrolling.
class KorlixButtonClimbers extends StatefulWidget {
  const KorlixButtonClimbers({super.key, required this.child, this.controller});
  final Widget child;
  final KorlixClimbersController? controller;
  @override
  State<KorlixButtonClimbers> createState() => _KorlixButtonClimbersState();
}

class _KorlixButtonClimbersState extends State<KorlixButtonClimbers>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _viewport = GlobalKey();
  final _seconds = ValueNotifier<double>(0);
  final _buttons = ValueNotifier<List<Rect>>(const []);
  final _visible = ValueNotifier<bool>(false);
  late final _ClimberAnchors _anchors;
  late final Ticker _ticker;
  Duration _lastPaint = Duration.zero;
  double _epoch = 0;
  bool _measurementQueued = false, _foreground = true, _editing = false;
  bool _motion = true, _current = true, _tickers = true, _keyboard = false;
  KorlixClimbersController get _controller =>
      widget.controller ?? kKorlixClimbers;

  @override
  void initState() {
    super.initState();
    _anchors = _ClimberAnchors(_queueMeasurement);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ticker = createTicker((elapsed) {
      // Only repaint the two figures, at most 30fps. The app never rebuilds per frame.
      if (elapsed - _lastPaint < const Duration(milliseconds: 33)) return;
      _lastPaint = elapsed;
      _seconds.value =
          _epoch + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
    _controller.addListener(_syncPlayback);
    unawaited(_controller.restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    _keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    _current = ModalRoute.isCurrentOf(context) ?? true;
    _tickers = TickerMode.valuesOf(context).enabled;
    _syncPlayback();
    _queueMeasurement();
  }

  @override
  void didUpdateWidget(covariant KorlixButtonClimbers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? kKorlixClimbers).removeListener(_syncPlayback);
      _controller.addListener(_syncPlayback);
      unawaited(_controller.restore());
    }
    _syncPlayback();
    _queueMeasurement();
  }

  void _focusChanged() {
    _editing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    _syncPlayback();
  }

  void _syncPlayback() {
    if (!mounted) return;
    final show =
        _controller.enabled &&
        _foreground &&
        _motion &&
        _current &&
        _tickers &&
        !_keyboard &&
        !_editing &&
        _buttons.value.isNotEmpty;
    _visible.value = show;
    if (show && !_ticker.isActive) {
      _epoch = _seconds.value;
      _lastPaint = Duration.zero;
      _ticker.start();
    } else if (!show && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _queueMeasurement() {
    if (!mounted || _measurementQueued) return;
    _measurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementQueued = false;
      if (!mounted) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final bounds = Offset.zero & viewport.size;
      final buttons = <Rect>[];
      for (final box in _anchors.boxes) {
        if (!box.attached || !box.hasSize) continue;
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(viewport),
          Offset.zero & box.size,
        );
        // Ignore tiny icons and mostly clipped controls. Prefer their outer edges.
        final visible = rect.intersect(bounds);
        if (rect.width >= 90 &&
            visible.width >= 80 &&
            visible.height >= 36 &&
            rect.top >= 76 &&
            rect.top < bounds.height - 72) {
          buttons.add(rect);
        }
      }
      buttons.sort(
        (a, b) =>
            a.top == b.top ? a.left.compareTo(b.left) : a.top.compareTo(b.top),
      );
      if (!listEquals(_buttons.value, buttons)) {
        _buttons.value = List.unmodifiable(buttons);
      }
      _syncPlayback();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
    if (_foreground) _queueMeasurement();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    _controller.removeListener(_syncPlayback);
    _anchors.onChanged = null;
    _ticker.dispose();
    _seconds.dispose();
    _buttons.dispose();
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ClimberScope(
    anchors: _anchors,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _queueMeasurement();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _queueMeasurement();
          return false;
        },
        child: Stack(
          key: _viewport,
          fit: StackFit.expand,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('button-climbers-canvas'),
                      painter: KorlixButtonClimbersPainter(
                        seconds: _seconds,
                        buttons: _buttons,
                        visible: _visible,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClimberAnchors {
  _ClimberAnchors(this.onChanged);
  VoidCallback? onChanged;
  final boxes = <RenderBox>{};
}

class _ClimberScope extends InheritedWidget {
  const _ClimberScope({required this.anchors, required super.child});
  final _ClimberAnchors anchors;
  @override
  bool updateShouldNotify(_ClimberScope oldWidget) =>
      oldWidget.anchors != anchors;
}

/// Outside the home scope this is just its child: no keys, ticker or registration.
class KorlixClimberAnchor extends StatelessWidget {
  const KorlixClimberAnchor({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ClimberScope>();
    return scope == null
        ? child
        : _ClimberTarget(anchors: scope.anchors, child: child);
  }
}

class _ClimberTarget extends SingleChildRenderObjectWidget {
  const _ClimberTarget({required this.anchors, required super.child});
  final _ClimberAnchors anchors;
  @override
  RenderObject createRenderObject(BuildContext context) => _ClimberBox(anchors);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ClimberBox renderObject,
  ) => renderObject.registry = anchors;
}

class _ClimberBox extends RenderProxyBox {
  _ClimberBox(this._registry);
  _ClimberAnchors _registry;
  set registry(_ClimberAnchors value) {
    if (identical(value, _registry)) return;
    _registry.boxes.remove(this);
    _registry.onChanged?.call();
    _registry = value;
    if (attached) _registry.boxes.add(this);
    _registry.onChanged?.call();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registry.boxes.add(this);
    _registry.onChanged?.call();
  }

  @override
  void detach() {
    _registry.boxes.remove(this);
    _registry.onChanged?.call();
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _registry.onChanged?.call();
  }
}
