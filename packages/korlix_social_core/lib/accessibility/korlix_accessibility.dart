import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sounds/korlix_sound_service.dart';
import '../theme/korlix_theme.dart';

final kKorlixAccessibility = KorlixAccessibilityPreferences();

/// Device preferences apply before sign-in and never depend on a paid tier.
class KorlixAccessibilityPreferences extends ChangeNotifier {
  static const storageKey = 'korlix_accessibility_v1';
  bool highContrast = false;
  bool reduceMotion = false;
  bool largerControls = false;
  bool quietSounds = false;
  bool keepAlertsVisible = false;
  double textScale = 1;
  Future<void>? _restore;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;

  Future<void> restore() => _restore ??= _load();
  Future<void> _load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = jsonDecode(prefs.getString(storageKey) ?? '{}');
      if (revision != _revision || value is! Map) return;
      highContrast = value['highContrast'] == true;
      reduceMotion = value['reduceMotion'] == true;
      largerControls = value['largerControls'] == true;
      quietSounds = value['quietSounds'] == true;
      keepAlertsVisible = value['keepAlertsVisible'] == true;
      final scale = value['textScale'];
      textScale = scale is num ? scale.toDouble().clamp(1, 1.5) : 1;
      kKorlixSounds.setQuiet(this, quietSounds);
      notifyListeners();
    } catch (_) {
      // System accessibility continues working if local storage is unavailable.
    }
  }

  Future<void> update({
    bool? contrast,
    bool? motion,
    bool? controls,
    bool? quiet,
    bool? keepAlerts,
    double? scale,
  }) {
    _revision++;
    highContrast = contrast ?? highContrast;
    reduceMotion = motion ?? reduceMotion;
    largerControls = controls ?? largerControls;
    quietSounds = quiet ?? quietSounds;
    keepAlertsVisible = keepAlerts ?? keepAlertsVisible;
    textScale = (scale ?? textScale).clamp(1, 1.5);
    kKorlixSounds.setQuiet(this, quietSounds);
    notifyListeners();
    final encoded = jsonEncode({
      'highContrast': highContrast,
      'reduceMotion': reduceMotion,
      'largerControls': largerControls,
      'quietSounds': quietSounds,
      'keepAlertsVisible': keepAlertsVisible,
      'textScale': textScale,
    });
    final write = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, encoded)) {
        throw StateError('Could not save accessibility settings.');
      }
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  @override
  void dispose() {
    kKorlixSounds.setQuiet(this, false);
    super.dispose();
  }

  ThemeData theme(ThemeData original, {bool forceHighContrast = false}) {
    final base = highContrast || forceHighContrast
        ? korlixBuildTheme(
            original.brightness == Brightness.light
                ? 'pure_white'
                : 'pure_black',
          )
        : original;
    if (!largerControls) return base;
    final minimum = WidgetStatePropertyAll(const Size(56, 56));
    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(minimumSize: minimum),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(minimumSize: minimum),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(minimumSize: minimum),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: minimum,
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(minVerticalPadding: 16),
    );
  }
}

/// Preserve nonlinear system scaling, including sizes larger than our presets.
class KorlixAccessibleTextScaler extends TextScaler {
  const KorlixAccessibleTextScaler(this.system, this.minimum);
  final TextScaler system;
  final double minimum;
  @override
  double scale(double fontSize) =>
      system.scale(fontSize).clamp(fontSize * minimum, double.infinity);
  @override
  double get textScaleFactor => scale(14) / 14;
}

class KorlixAccessibilityHost extends StatefulWidget {
  const KorlixAccessibilityHost({super.key, required this.child});
  final Widget child;
  @override
  State<KorlixAccessibilityHost> createState() => _AccessibilityHostState();
}

class _AccessibilityHostState extends State<KorlixAccessibilityHost> {
  @override
  void initState() {
    super.initState();
    unawaited(kKorlixAccessibility.restore());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kKorlixAccessibility,
    builder: (context, _) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: KorlixAccessibleTextScaler(
            media.textScaler,
            kKorlixAccessibility.textScale,
          ),
          highContrast: media.highContrast || kKorlixAccessibility.highContrast,
          disableAnimations:
              media.disableAnimations || kKorlixAccessibility.reduceMotion,
          boldText: media.boldText,
        ),
        child: widget.child,
      );
    },
  );
}

void openKorlixAccessibility(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const KorlixAccessibilitySettings(),
      ),
    );

class KorlixAccessibilitySettings extends StatelessWidget {
  const KorlixAccessibilitySettings({super.key});
  Future<void> _save(BuildContext context, Future<void> result) async {
    try {
      await result;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Applied for now, but could not save. Please try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accessibility')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: kKorlixAccessibility,
        builder: (context, _) {
          final prefs = kKorlixAccessibility;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Make KORLIX work for you',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Available on every plan. Changes apply immediately on this device. '
                'Your device’s larger text and reduced-motion settings are always respected.',
              ),
              const SizedBox(height: 24),
              const Text(
                'Text size',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    1.0: 'System',
                    1.25: 'Large',
                    1.5: 'Extra large',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: prefs.textScale == entry.key,
                      onSelected: (_) =>
                          _save(context, prefs.update(scale: entry.key)),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('High contrast'),
                subtitle: const Text(
                  'Stronger light or dark surfaces and readable text.',
                ),
                value: prefs.highContrast,
                onChanged: (v) => _save(context, prefs.update(contrast: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                subtitle: const Text(
                  'Reduce character motion and stop smoke and shaking effects.',
                ),
                value: prefs.reduceMotion,
                onChanged: (v) => _save(context, prefs.update(motion: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Larger controls'),
                subtitle: const Text('More space around buttons and settings.'),
                value: prefs.largerControls,
                onChanged: (v) => _save(context, prefs.update(controls: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet interface sounds'),
                subtitle: const Text(
                  'Mute interface effects. Call and conversation controls stay separate.',
                ),
                value: prefs.quietSounds,
                onChanged: (v) => _save(context, prefs.update(quiet: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep message alerts visible'),
                subtitle: const Text(
                  'Message and online alerts stay until you dismiss them.',
                ),
                value: prefs.keepAlertsVisible,
                onChanged: (v) => _save(context, prefs.update(keepAlerts: v)),
              ),
              const Divider(height: 32),
              const Text(
                'Reading, hearing & navigation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Live Convo opens with a readable transcript and typed input. '
                'Use Show transcript if you have hidden it. Alerts include visible text.\n\n'
                'Enable VoiceOver, TalkBack, Switch Control or Switch Access in your device’s '
                'Accessibility settings. Use Tab and Shift+Tab to move through controls with '
                'a keyboard, then Enter or Space to activate them.',
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: const Text('Preview: Clear text. Comfortable controls.'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
