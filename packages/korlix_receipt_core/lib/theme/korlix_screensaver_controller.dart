import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KorlixScreensaverController extends ChangeNotifier {
  KorlixScreensaverController({
    bool initiallyEnabled = true,
    Future<SharedPreferences> Function()? load,
  }) : _enabled = initiallyEnabled,
       _load = load ?? SharedPreferences.getInstance;
  static const storageKey = 'korlix_smoke_screensaver_v1';
  static const idleDuration = Duration(seconds: 30);
  final Future<SharedPreferences> Function() _load;
  bool _enabled, _disposed = false;
  int _revision = 0, activityRevision = 0, previewRevision = 0;
  Future<void>? _restoring;
  Future<void> _writes = Future.value();
  bool get enabled => _enabled;

  /// Activity accounting must pause while the visual screensaver is covering
  /// the app, even though media and the navigator remain mounted.
  final ValueNotifier<bool> visibility = ValueNotifier<bool>(false);

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final prefs = await _load();
      if (_disposed || revision != _revision) return;
      _enabled = prefs.getBool(storageKey) ?? _enabled;
      notifyListeners();
    } catch (_) {
      /* The screensaver remains usable without device storage. */
    }
  }

  Future<bool> setEnabled(bool value) {
    final revision = ++_revision;
    _enabled = value;
    if (!_disposed) notifyListeners();
    final saving = _writes.then((_) async {
      if (_disposed || revision != _revision) return true;
      try {
        final prefs = await _load();
        if (_disposed || revision != _revision) return true;
        return await prefs.setBool(storageKey, value);
      } catch (_) {
        return false;
      }
    });
    _writes = saving.then((_) {});
    return saving;
  }

  void activity() {
    if (_disposed) return;
    activityRevision++;
    notifyListeners();
  }

  void preview() {
    if (_disposed) return;
    previewRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    visibility.dispose();
    super.dispose();
  }
}

final kKorlixScreensaver = KorlixScreensaverController();

/// Route changes reveal the destination without popping/replacing any route.
class KorlixScreensaverObserver extends NavigatorObserver {
  KorlixScreensaverObserver(this.controller);
  final KorlixScreensaverController controller;
  bool _queued = false;
  void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      controller.activity();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
}
