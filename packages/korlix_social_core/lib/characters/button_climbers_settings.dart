import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device preference, shared by the home animation and the appearance panel.
class KorlixClimbersController extends ChangeNotifier {
  KorlixClimbersController({Future<SharedPreferences> Function()? load})
    : _load = load ?? SharedPreferences.getInstance;

  static const storageKey = 'korlix_button_climbers_v1';
  final Future<SharedPreferences> Function() _load;
  bool _enabled = true, _disposed = false;
  int _revision = 0;
  Future<void>? _restoring;
  Future<void> _writes = Future.value();
  bool get enabled => _enabled;

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final prefs = await _load();
      if (_disposed || revision != _revision) return;
      _enabled = prefs.getBool(storageKey) ?? true;
      notifyListeners();
    } catch (_) {
      // A blocked browser preference must not prevent the home screen loading.
    }
  }

  Future<bool> setEnabled(bool enabled) {
    final revision = ++_revision;
    _enabled = enabled;
    if (!_disposed) notifyListeners();
    final saving = _writes.then((_) async {
      if (_disposed || revision != _revision) return true;
      try {
        final prefs = await _load();
        if (_disposed || revision != _revision) return true;
        return await prefs.setBool(storageKey, enabled);
      } catch (_) {
        return false;
      }
    });
    _writes = saving.then((_) {});
    return saving;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final kKorlixClimbers = KorlixClimbersController();

class KorlixClimbersSettings extends StatefulWidget {
  const KorlixClimbersSettings({super.key, this.controller});
  final KorlixClimbersController? controller;
  @override
  State<KorlixClimbersSettings> createState() => _KorlixClimbersSettingsState();
}

class _KorlixClimbersSettingsState extends State<KorlixClimbersSettings> {
  KorlixClimbersController get _controller =>
      widget.controller ?? kKorlixClimbers;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.restore());
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _notice = null);
    if (!await _controller.setEnabled(enabled) && mounted) {
      setState(
        () => _notice =
            'Changed for this visit. Device storage could not save this setting.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const Key('button-climbers-toggle'),
            title: const Text('Button climbers'),
            subtitle: Text(
              MediaQuery.disableAnimationsOf(context) ||
                      MediaQuery.accessibleNavigationOf(context)
                  ? 'Your device’s reduced motion or accessibility setting keeps the climbers hidden.'
                  : 'A tiny man and woman climb, wave and reach out from your home screen.',
            ),
            value: _controller.enabled,
            onChanged: (value) => unawaited(_toggle(value)),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(_notice!),
            ),
        ],
      ),
    ),
  );
}
