import 'korlix_appearance_preferences.dart';
import 'korlix_theme.dart';

const kKorlixDefaultThemeId = 'christmas_red';

/// The main hub owns its default. Companion apps keep their own appearance.
/// Saved choices win, including choices made while storage is still loading.
Future<void> restoreKorlixDefaultAppearance() {
  kKorlixThemeNotifier.value = kKorlixDefaultThemeId;
  return kKorlixAppearancePreferences.restore();
}
