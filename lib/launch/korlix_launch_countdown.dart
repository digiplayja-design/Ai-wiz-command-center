import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';

/// October 15, 2026 at 9:00 AM in America/New_York (UTC−04:00).
/// Keep this instant aligned with website/launch.js.
final korlixWebLaunchAt = DateTime.utc(2026, 10, 15, 13);
const korlixWebLaunchDateLabel = 'October 15, 2026 · 9 AM Eastern';

@immutable
class KorlixLaunchRemaining {
  const KorlixLaunchRemaining._(this.totalSeconds);

  factory KorlixLaunchRemaining.at(DateTime now) {
    final micros = korlixWebLaunchAt.difference(now.toUtc()).inMicroseconds;
    // Round up: the display must not say zero before the actual launch time.
    return KorlixLaunchRemaining._(
      micros <= 0 ? 0 : (micros + 999999) ~/ 1000000,
    );
  }

  final int totalSeconds;
  bool get complete => totalSeconds == 0;
  int get days => totalSeconds ~/ 86400;
  int get hours => (totalSeconds ~/ 3600) % 24;
  int get minutes => (totalSeconds ~/ 60) % 60;
  int get seconds => totalSeconds % 60;

  String get accessibleLabel => complete
      ? 'Web launch countdown complete. $korlixWebLaunchDateLabel.'
      : 'Web launch, $korlixWebLaunchDateLabel. '
            '$days days, $hours hours, $minutes minutes, $seconds seconds remaining.';
}

/// Only mounted by the web home screen. No sign-in, billing or feature gating.
class KorlixLaunchCountdown extends StatefulWidget {
  const KorlixLaunchCountdown({super.key, this.now});

  /// Allows deterministic clock and lifecycle tests without a ticking fake date.
  final DateTime Function()? now;

  @override
  State<KorlixLaunchCountdown> createState() => _KorlixLaunchCountdownState();
}

class _KorlixLaunchCountdownState extends State<KorlixLaunchCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  late KorlixLaunchRemaining _remaining;
  bool _foreground = true;
  bool _routeVisible = true;

  KorlixLaunchRemaining _readClock() =>
      KorlixLaunchRemaining.at((widget.now ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _remaining = _readClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = TickerMode.valuesOf(context).enabled;
    if (_foreground && _routeVisible) _remaining = _readClock();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant KorlixLaunchCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now) {
      _remaining = _readClock();
      _syncTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
    _syncTimer();
  }

  void _refresh() {
    if (!mounted) return;
    // Derive every frame from the deadline, never decrement a stored counter.
    // Browser timer throttling and time spent in other apps cannot create drift.
    final next = _readClock();
    if (next.totalSeconds != _remaining.totalSeconds) {
      setState(() => _remaining = next);
    }
    _syncTimer();
  }

  void _syncTimer() {
    if (!_foreground || !_routeVisible || _remaining.complete) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _remaining.complete ? 'Launch countdown complete' : 'Web launch',
          style: TextStyle(
            color: skin.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          korlixWebLaunchDateLabel,
          style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.4),
        ),
      ],
    );

    // A single readable node, without liveRegion: assistive technology should
    // not interrupt the user's work with an announcement every second.
    return Semantics(
      container: true,
      label: _remaining.accessibleLabel,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('web-launch-countdown'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [skin.panel, skin.panelSoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.primary.withValues(alpha: .4)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_remaining.complete) return heading;
              final digits = _CountdownDigits(remaining: _remaining);
              if (constraints.maxWidth >= 680 && scaler.scale(14) <= 18) {
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 20),
                    SizedBox(width: 300, child: digits),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [heading, const SizedBox(height: 12), digits],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CountdownDigits extends StatelessWidget {
  const _CountdownDigits({required this.remaining});
  final KorlixLaunchRemaining remaining;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reflow at large text sizes instead of clipping or shrinking text.
        final minCellWidth = scaler.scale(20) * 2 + 16;
        final columns = constraints.maxWidth >= minCellWidth * 4 + 24 ? 4 : 2;
        final cellWidth = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final unit in [
              (remaining.days, 'Days'),
              (remaining.hours, 'Hours'),
              (remaining.minutes, 'Minutes'),
              (remaining.seconds, 'Seconds'),
            ])
              Container(
                key: ValueKey('launch-${unit.$2.toLowerCase()}'),
                width: cellWidth,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: skin.panelDeep,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      unit.$1.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: skin.primary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      unit.$2,
                      style: TextStyle(color: skin.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
