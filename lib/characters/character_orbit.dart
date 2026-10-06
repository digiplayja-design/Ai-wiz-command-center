import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sounds/korlix_sound_service.dart';
import '../theme/korlix_theme.dart';
import 'character_catalog.dart';
import 'character_orbit_wind.dart';

/// Drag to rotate; release to snap and save. No timer or perpetual motion.
class KorlixCharacterOrbit extends StatefulWidget {
  const KorlixCharacterOrbit({
    super.key,
    required this.selectedId,
    required this.availableIds,
    required this.onSelected,
    this.loading = false,
    this.saving = false,
    this.error,
    this.onRetry,
    this.previewBuilder,
    this.soundService,
  });
  final String selectedId;
  final Set<String> availableIds;
  final Future<void> Function(String) onSelected;
  final bool loading, saving;
  final String? error;
  final VoidCallback? onRetry;
  final Widget Function(KorlixCharacter)? previewBuilder;
  final KorlixSoundService? soundService;
  @override
  State<KorlixCharacterOrbit> createState() => _KorlixCharacterOrbitState();
}

class _KorlixCharacterOrbitState extends State<KorlixCharacterOrbit>
    with TickerProviderStateMixin {
  static const _step = 2 * math.pi / 5;
  late final AnimationController _rotation;
  late final AnimationController _wind;
  double _windDirection = 1;
  bool _dragging = false;
  bool _dragBreezeStarted = false;
  int _breezeRequest = 0;
  KorlixSoundService get _sounds => widget.soundService ?? kKorlixSounds;
  int get _selectedIndex =>
      korlixCharacters.indexWhere((c) => c.id == widget.selectedId).clamp(0, 4);
  bool get _enabled =>
      !widget.loading && !widget.saving && widget.availableIds.isNotEmpty;
  @override
  void initState() {
    super.initState();
    _rotation = AnimationController.unbounded(
      vsync: this,
      value: -_selectedIndex * _step,
    );
    _wind = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didUpdateWidget(KorlixCharacterOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        (oldWidget.saving && !widget.saving)) {
      _snap(_selectedIndex);
    }
  }

  double _targetFor(int index) {
    final target = -index * _step;
    return target +
        ((_rotation.value - target) / (2 * math.pi)).round() * 2 * math.pi;
  }

  void _snap(int index) {
    final target = _targetFor(index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.value = target;
      return;
    }
    unawaited(
      _rotation.animateTo(
        target,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _playBreeze() {
    final sounds = _sounds;
    if (!sounds.settings.enabled || !sounds.settings.clicks || sounds.quiet) {
      return;
    }
    final request = ++_breezeRequest;
    final elapsed = Stopwatch()..start();
    // Activate within the gesture for mobile browsers. Sound never delays
    // selection, and a late activation must not play after the spin or teardown.
    unawaited(() async {
      try {
        final ready = sounds.ready || await sounds.activate();
        if (!ready ||
            !mounted ||
            request != _breezeRequest ||
            !identical(sounds, _sounds) ||
            elapsed.elapsed > const Duration(milliseconds: 250)) {
          return;
        }
        await sounds.play(KorlixSound.orbitBreeze);
      } catch (_) {
        // Audio availability must not interfere with choosing a character.
      } finally {
        elapsed.stop();
      }
    }());
  }

  void _showWind(double movement) {
    if (movement == 0 || MediaQuery.disableAnimationsOf(context)) return;
    _windDirection = movement.sign;
    // A bounded pulse: fresh movement refreshes the mist, then it disperses.
    _wind.forward(from: 0);
  }

  void _choose(int index, {bool breeze = true}) {
    if (!_enabled ||
        !widget.availableIds.contains(korlixCharacters[index].id)) {
      _snap(_selectedIndex);
      return;
    }
    final movement = _targetFor(index) - _rotation.value;
    if (movement.abs() > 0.01) {
      if (breeze) _playBreeze();
      _showWind(movement);
    }
    _snap(index);
    unawaited(widget.onSelected(korlixCharacters[index].id));
  }

  void _advance(int direction) {
    if (!_enabled) return;
    for (var n = 1; n <= 5; n++) {
      final index = (_selectedIndex + direction * n) % 5;
      if (widget.availableIds.contains(korlixCharacters[index].id)) {
        _choose(index);
        return;
      }
    }
  }

  void _finishDrag([double velocity = 0]) {
    setState(() => _dragging = false);
    final projected = _rotation.value + (velocity / 2200).clamp(-_step, _step);
    final available = [
      for (var i = 0; i < 5; i++)
        if (widget.availableIds.contains(korlixCharacters[i].id)) i,
    ];
    if (available.isEmpty) {
      _snap(_selectedIndex);
      return;
    }
    double distance(int index) =>
        ((_targetFor(index) - projected + math.pi) % (2 * math.pi) - math.pi)
            .abs();
    available.sort((a, b) => distance(a).compareTo(distance(b)));
    _choose(available.first, breeze: !_dragBreezeStarted);
  }

  @override
  void dispose() {
    _breezeRequest++;
    _rotation.dispose();
    _wind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final character = korlixCharacterFor(widget.selectedId);
    return Container(
      key: const ValueKey('character-orbit-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [skin.panelSoft, skin.panel, skin.panelDeep],
        ),
        border: Border.all(color: skin.primary.withValues(alpha: .3)),
        boxShadow: [
          BoxShadow(
            color: character.color.withValues(alpha: skin.isLight ? .08 : .12),
            blurRadius: 32,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 660;
          final details = Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MEET YOUR AI',
                style: TextStyle(
                  color: skin.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                MediaQuery.textScalerOf(context).scale(23) > 30
                    ? 'Choose your AI.'
                    : 'A world of personalities.',
                textAlign: wide ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  color: skin.text,
                  fontSize: wide ? 30 : 23,
                  fontWeight: FontWeight.w800,
                  height: 1.16,
                ),
              ),
              if (wide) ...[
                const SizedBox(height: 28),
                _identity(character, skin, wide: true),
              ],
            ],
          );
          final orbit = _orbit(skin);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(flex: 4, child: details),
                    const SizedBox(width: 24),
                    Expanded(flex: 6, child: orbit),
                  ],
                )
              else ...[
                details,
                orbit,
                _identity(character, skin, wide: false),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('orbit-previous'),
                    tooltip: 'Previous character',
                    enableFeedback: false,
                    onPressed: _enabled ? () => _advance(-1) : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Spin to choose',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: skin.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Swipe, drag or tap a character',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: skin.mutedText, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  IconButton.filledTonal(
                    key: const ValueKey('orbit-next'),
                    tooltip: 'Next character',
                    enableFeedback: false,
                    onPressed: _enabled ? () => _advance(1) : null,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
              if (widget.loading || widget.saving)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.saving
                          ? 'Saving your character…'
                          : 'Loading your characters…',
                      style: TextStyle(color: skin.mutedText, fontSize: 12),
                    ),
                  ),
                ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      children: [
                        Text(
                          widget.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: skin.danger, fontSize: 13),
                        ),
                        if (widget.availableIds.isEmpty &&
                            widget.onRetry != null)
                          TextButton(
                            onPressed: widget.onRetry,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _identity(
    KorlixCharacter character,
    KorlixSkinPalette skin, {
    required bool wide,
  }) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          character.role,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: skin.primary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          character.name,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: skin.text,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          character.description,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(color: skin.mutedText, fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );

  Widget _orbit(KorlixSkinPalette skin) => Focus(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _advance(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _advance(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final radiusX = (width / 2 - 57).clamp(38.0, 188.0);
        const radiusY = 68.0;
        const centerY = 139.0;
        return MouseRegion(
          cursor: _enabled
              ? (_dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab)
              : SystemMouseCursors.basic,
          child: GestureDetector(
            key: const ValueKey('character-orbit-drag'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _enabled
                ? (_) {
                    _rotation.stop();
                    _dragBreezeStarted = false;
                    setState(() => _dragging = true);
                  }
                : null,
            onHorizontalDragUpdate: _enabled
                ? (event) {
                    _rotation.value += event.delta.dx / (radiusX * 1.1);
                    _showWind(event.delta.dx);
                    if (!_dragBreezeStarted && event.delta.dx != 0) {
                      _dragBreezeStarted = true;
                      _playBreeze();
                    }
                  }
                : null,
            onHorizontalDragEnd: _enabled
                ? (event) => _finishDrag(event.primaryVelocity ?? 0)
                : null,
            onHorizontalDragCancel: _enabled
                ? () {
                    setState(() => _dragging = false);
                    _snap(_selectedIndex);
                  }
                : null,
            child: SizedBox(
              height: 318,
              child: AnimatedBuilder(
                animation: Listenable.merge([_rotation, _wind]),
                builder: (context, _) {
                  final showWind =
                      _wind.value < 1 &&
                      !MediaQuery.disableAnimationsOf(context);
                  final positions = [
                    for (var index = 0; index < 5; index++)
                      (index: index, angle: index * _step + _rotation.value),
                  ];
                  positions.sort(
                    (a, b) => math.cos(a.angle).compareTo(math.cos(b.angle)),
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _OrbitRings(
                              skin,
                              radiusX,
                              radiusY,
                              centerY,
                            ),
                          ),
                        ),
                      ),
                      if (showWind)
                        _windLayer(
                          skin,
                          radiusX,
                          radiusY,
                          centerY,
                          front: false,
                        ),
                      Positioned(
                        left: width / 2 - 22,
                        top: centerY - 22,
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: skin.primary.withValues(alpha: .35),
                            size: 44,
                          ),
                        ),
                      ),
                      for (final point in positions)
                        _satellite(
                          point.index,
                          point.angle,
                          width,
                          radiusX,
                          radiusY,
                          centerY,
                          skin,
                        ),
                      if (showWind)
                        _windLayer(
                          skin,
                          radiusX,
                          radiusY,
                          centerY,
                          front: true,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _windLayer(
    KorlixSkinPalette skin,
    double rx,
    double ry,
    double cy, {
    required bool front,
  }) => Positioned.fill(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: KorlixOrbitWindPainter(
                skin: skin,
                radiusX: rx,
                radiusY: ry,
                centerY: cy,
                rotation: _rotation.value,
                progress: _wind.value,
                direction: _windDirection,
                front: front,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _satellite(
    int index,
    double angle,
    double width,
    double rx,
    double ry,
    double cy,
    KorlixSkinPalette skin,
  ) {
    final character = korlixCharacters[index];
    final depth = (math.cos(angle) + 1) / 2;
    final cardWidth = 64 + depth * 44;
    final cardHeight = cardWidth * 1.38;
    final selected = character.id == widget.selectedId;
    final available = widget.availableIds.contains(character.id);
    return Positioned(
      key: ValueKey('orbit-position-${character.id}'),
      left: width / 2 + math.sin(angle) * rx - cardWidth / 2,
      top: cy + math.cos(angle) * ry - cardHeight / 2,
      width: cardWidth,
      height: cardHeight,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: _enabled && available,
        label: '${character.name}${selected ? ", selected" : ""}',
        onTap: _enabled && available ? () => _choose(index) : null,
        child: Tooltip(
          message: character.name,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: _enabled && available ? () => _choose(index) : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: character.color.withValues(
                      alpha: selected ? .35 : .13,
                    ),
                    blurRadius: selected ? 22 : 10,
                    spreadRadius: selected ? 2 : 0,
                  ),
                ],
              ),
              child: Container(
                padding: EdgeInsets.all(selected ? 2.5 : 1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      character.color,
                      character.color.withValues(alpha: .3),
                      character.color.withValues(alpha: .85),
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        character.portrait,
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -.5),
                      ),
                      if (selected && widget.previewBuilder != null)
                        widget.previewBuilder!(character),
                      if (!selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                              alpha: (1 - depth) * .18,
                            ),
                          ),
                        ),
                      if (!selected)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(5, 17, 5, 6),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xDD030B19),
                                  ],
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  selected
                                      ? '✓ ${character.name}'
                                      : character.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
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
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitRings extends CustomPainter {
  const _OrbitRings(this.skin, this.rx, this.ry, this.cy);
  final KorlixSkinPalette skin;
  final double rx, ry, cy;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, cy);
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    canvas.drawOval(
      rect.inflate(14),
      Paint()
        ..color = skin.primary.withValues(alpha: .04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20,
    );
    for (final expansion in [-13.0, 0.0, 14.0]) {
      canvas.drawOval(
        rect.inflate(expansion),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = expansion == 0 ? 1.8 : .7
          ..shader = LinearGradient(
            colors: [
              skin.primary.withValues(alpha: .08),
              skin.primary.withValues(alpha: .7),
              skin.secondary.withValues(alpha: .65),
              skin.primary.withValues(alpha: .08),
            ],
          ).createShader(rect),
      );
    }
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      canvas.drawCircle(
        center +
            Offset(math.sin(angle) * (rx + 14), math.cos(angle) * (ry + 14)),
        i % 3 == 0 ? 2 : 1,
        Paint()..color = skin.primary.withValues(alpha: i % 3 == 0 ? .6 : .22),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitRings oldDelegate) =>
      oldDelegate.skin != skin || oldDelegate.rx != rx;
}
