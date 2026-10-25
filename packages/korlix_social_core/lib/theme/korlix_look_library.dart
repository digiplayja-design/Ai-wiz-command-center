import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'korlix_appearance_preferences.dart';
import 'korlix_screen_skin.dart';
import 'korlix_theme.dart';

/// Device-local bookmarks. Previewing or saving never applies an appearance.
class KorlixLookLibrary {
  KorlixLookLibrary({Future<SharedPreferences> Function()? load})
    : _load = load ?? SharedPreferences.getInstance;
  static const storageKey = 'korlix_saved_looks_v1';
  static final maximum = korlixThemeIds.length * korlixScreenSkinIds.length;
  final Future<SharedPreferences> Function() _load;
  final List<KorlixAppearanceChoice> _items = [];
  Future<void> _writes = Future.value();
  int _revision = 0;
  List<KorlixAppearanceChoice> get items => List.unmodifiable(_items);
  bool contains(KorlixAppearanceChoice choice) => _items.any(
    (item) => item.themeId == choice.themeId && item.skinId == choice.skinId,
  );

  Future<void> restore() async {
    final revision = _revision;
    try {
      final prefs = await _load();
      final decoded = jsonDecode(prefs.getString(storageKey) ?? '[]');
      if (revision != _revision || decoded is! List) return;
      _items.clear();
      for (final item in decoded.take(maximum)) {
        if (item is! Map ||
            !korlixThemeIds.contains(item['theme']) ||
            !korlixScreenSkinIds.contains(item['skin'])) {
          continue;
        }
        final choice = KorlixAppearanceChoice(item['theme'], item['skin']);
        if (!contains(choice)) _items.add(choice);
      }
    } catch (_) {
      // Browsing and previewing still work with unavailable device storage.
    }
  }

  Future<bool> toggle(KorlixAppearanceChoice choice) {
    final revision = ++_revision;
    if (contains(choice)) {
      _items.removeWhere(
        (item) =>
            item.themeId == choice.themeId && item.skinId == choice.skinId,
      );
    } else {
      _items.insert(0, choice);
      if (_items.length > maximum) _items.removeLast();
    }
    final write = _writes.then((_) async {
      if (revision != _revision) return true;
      try {
        final prefs = await _load();
        if (revision != _revision) return true;
        return await prefs.setString(
          storageKey,
          jsonEncode([
            for (final item in _items)
              {'theme': item.themeId, 'skin': item.skinId},
          ]),
        );
      } catch (_) {
        return false;
      }
    });
    _writes = write.then((_) {});
    return write;
  }
}
