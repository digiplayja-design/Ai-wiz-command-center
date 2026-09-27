import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'korlix_theme.dart';
import 'korlix_screen_skin.dart';

class KorlixAppearanceChoice {
  KorlixAppearanceChoice(String theme, String skin)
    : themeId = korlixNormalizeSkinId(theme),
      skinId = korlixNormalizeScreenSkin(skin);
  final String themeId, skinId;
}

class KorlixAppearancePreferences {
  KorlixAppearancePreferences({
    required this.theme,
    required this.screenSkin,
    Future<SharedPreferences> Function()? load,
  }) : _load = load ?? SharedPreferences.getInstance;
  final ValueNotifier<String> theme, screenSkin;
  final Future<SharedPreferences> Function() _load;
  static const storageKey = 'korlix_appearance_v2';
  int _revision = 0;
  Future<void> _writes = Future.value();
  KorlixAppearanceChoice get current =>
      KorlixAppearanceChoice(theme.value, screenSkin.value);

  Future<void> restore() async {
    final revision = _revision;
    try {
      final prefs = await _load();
      var choice = KorlixAppearanceChoice(
        prefs.getString('korlix_ui_theme') ?? theme.value,
        'classic',
      );
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        try {
          final data = jsonDecode(raw);
          if (data is Map &&
              data['theme'] is String &&
              data['skin'] is String) {
            choice = KorlixAppearanceChoice(data['theme'], data['skin']);
          }
        } catch (_) {
          /* Fall back to the earlier saved theme. */
        }
      }
      if (_revision != revision) return;
      theme.value = choice.themeId;
      screenSkin.value = choice.skinId;
    } catch (_) {
      /* Appearance works even if browser storage is unavailable. */
    }
  }

  Future<bool> apply(KorlixAppearanceChoice choice) {
    final revision = ++_revision;
    theme.value = choice.themeId;
    screenSkin.value = choice.skinId;
    final result = _writes.then((_) async {
      if (revision != _revision) return true;
      try {
        final prefs = await _load();
        if (revision != _revision) return true;
        // One record keeps a template's palette and wrapper together.
        final saved = await prefs.setString(
          storageKey,
          jsonEncode({'theme': choice.themeId, 'skin': choice.skinId}),
        );
        await prefs.setString('korlix_ui_theme', choice.themeId);
        return saved;
      } catch (_) {
        return false;
      }
    });
    _writes = result.then((_) {});
    return result;
  }
}

final kKorlixAppearancePreferences = KorlixAppearancePreferences(
  theme: kKorlixThemeNotifier,
  screenSkin: kKorlixScreenSkinNotifier,
);
