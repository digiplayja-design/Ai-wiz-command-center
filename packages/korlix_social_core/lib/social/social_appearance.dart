import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/korlix_appearance_picker.dart';
import '../theme/korlix_appearance_preferences.dart';
import '../theme/korlix_screen_skin.dart';
import '../theme/korlix_theme.dart';

/// A device preference, separate from both the app look and member profiles.
/// Null means follow the app. One record keeps color and finish together.
class SocialAppearancePreferences extends ChangeNotifier {
  SocialAppearancePreferences({Future<SharedPreferences> Function()? load})
    : _load = load ?? SharedPreferences.getInstance;
  static const storageKey = 'korlix_social_appearance_v1';
  final Future<SharedPreferences> Function() _load;
  KorlixAppearanceChoice? _choice;
  KorlixAppearanceChoice? get choice => _choice;
  Future<void>? _restoring;
  Future<void> _writes = Future.value();
  int _revision = 0;

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final raw = (await _load()).getString(storageKey);
      if (raw == null || _revision != revision) return;
      final data = jsonDecode(raw);
      if (data is! Map ||
          !korlixThemeIds.contains(data['theme']) ||
          !korlixScreenSkinIds.contains(data['skin'])) {
        return;
      }
      _choice = KorlixAppearanceChoice(data['theme'], data['skin']);
      notifyListeners();
    } catch (_) {
      // An unavailable or outdated device store must not block Social.
    }
  }

  Future<bool> apply(KorlixAppearanceChoice? choice) {
    final revision = ++_revision;
    _choice = choice;
    notifyListeners();
    final result = _writes.then((_) async {
      if (revision != _revision) return true;
      try {
        final prefs = await _load();
        if (revision != _revision) return true;
        return choice == null
            ? await prefs.remove(storageKey)
            : await prefs.setString(
                storageKey,
                jsonEncode({'theme': choice.themeId, 'skin': choice.skinId}),
              );
      } catch (_) {
        return false;
      }
    });
    _writes = result.then((_) {});
    return result;
  }
}

final kSocialAppearance = SocialAppearancePreferences();
final messengerDefaultAppearance = KorlixAppearanceChoice(
  'sunset_copper',
  'contour',
);

/// Every Social route gets its own live theme boundary. Updating the look
/// keeps the same child element, so drafts, scroll positions and calls survive.
class SocialAppearance extends StatefulWidget {
  const SocialAppearance({
    super.key,
    required this.child,
    this.preferences,
    this.defaultChoice,
  });
  final Widget child;
  final SocialAppearancePreferences? preferences;
  final KorlixAppearanceChoice? defaultChoice;
  @override
  State<SocialAppearance> createState() => _SocialAppearanceState();
}

class _SocialAppearanceState extends State<SocialAppearance> {
  SocialAppearancePreferences get preferences =>
      widget.preferences ??
      SocialAppearanceScope.maybeOf(context)?.preferences ??
      kSocialAppearance;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(preferences.restore());
  }

  @override
  void didUpdateWidget(covariant SocialAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      unawaited(preferences.restore());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([preferences, kKorlixScreenSkinNotifier]),
    builder: (context, _) {
      final inherited = Theme.of(context);
      final choice =
          preferences.choice ??
          widget.defaultChoice ??
          SocialAppearanceScope.maybeOf(context)?.choice ??
          KorlixAppearanceChoice(
            korlixSkinOf(context).id,
            kKorlixScreenSkinNotifier.value,
          );
      return Theme(
        data: preferences.choice == null && widget.defaultChoice == null
            ? inherited
            : korlixBuildTheme(choice.themeId),
        child: SocialAppearanceScope(
          choice: choice,
          preferences: preferences,
          child: widget.child,
        ),
      );
    },
  );
}

class SocialAppearanceScope extends InheritedTheme {
  const SocialAppearanceScope({
    super.key,
    required this.choice,
    required this.preferences,
    required super.child,
  });
  final KorlixAppearanceChoice choice;
  final SocialAppearancePreferences preferences;
  static SocialAppearanceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SocialAppearanceScope>();
  @override
  bool updateShouldNotify(SocialAppearanceScope oldWidget) =>
      oldWidget.choice.themeId != choice.themeId ||
      oldWidget.choice.skinId != choice.skinId ||
      oldWidget.preferences != preferences;
  @override
  Widget wrap(BuildContext context, Widget child) => SocialAppearanceScope(
    choice: choice,
    preferences: preferences,
    child: child,
  );
}

class SocialPageRoute<T> extends MaterialPageRoute<T> {
  SocialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
         builder: (context) =>
             SocialAppearance(child: Builder(builder: builder)),
       );
}

String socialScreenSkinOf(BuildContext context) =>
    SocialAppearanceScope.maybeOf(context)?.choice.skinId ?? 'classic';

/// A static backdrop behind content, with no hit targets or expensive blur.
class SocialScaffold extends StatelessWidget {
  const SocialScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    backgroundColor: backgroundColor,
    resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
    body: body == null || backgroundColor != null
        ? body
        : KorlixScreenBackdrop(
            palette: korlixSkinOf(context),
            skinId: socialScreenSkinOf(context),
            child: body!,
          ),
  );
}

double socialSurfaceRadius(String skin) => switch (skin) {
  'bubbles' || 'mesh' => 30,
  'prism' || 'glass_break' => 14,
  'linen' || 'contour' => 18,
  _ => 26,
};

BoxDecoration socialSurfaceDecoration(
  KorlixSkinPalette palette,
  String skin, {
  Color? accent,
  bool message = false,
  bool mine = false,
}) {
  final color = accent ?? palette.primary;
  final radius = message
      ? socialSurfaceRadius(skin) - 4
      : socialSurfaceRadius(skin);
  final base = message && !mine ? palette.panelDeep : palette.panel;
  final quiet = skin == 'linen' || skin == 'contour';
  final glass = skin == 'glass' || skin == 'glass_break';
  final top = Color.alphaBlend(
    color.withValues(
      alpha: message ? (mine ? .16 : .025) : (quiet ? .035 : .09),
    ),
    base,
  );
  return BoxDecoration(
    borderRadius: message
        ? BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(mine ? radius : 5),
            bottomRight: Radius.circular(mine ? 5 : radius),
          )
        : BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        top,
        glass
            ? Color.alphaBlend(palette.secondary.withValues(alpha: .045), base)
            : base,
      ],
    ),
    border: Border.all(
      color: (glass || skin == 'prism' ? color : palette.border).withValues(
        alpha: glass ? .4 : .45,
      ),
      width: skin == 'prism' ? 1.4 : 1,
    ),
    boxShadow: message && skin == 'classic'
        ? null
        : [
            BoxShadow(
              color: (glass || skin == 'orbit' ? palette.glow : Colors.black)
                  .withValues(
                    alpha: palette.isLight ? .06 : (quiet ? .12 : .2),
                  ),
              blurRadius: quiet ? 8 : 20,
              offset: Offset(0, message ? 3 : 7),
            ),
          ],
  );
}

/// Messages, quotes, receipts and media controls use the selected palette.
ThemeData socialMessageTheme(BuildContext context) => Theme.of(context);

Future<void> showSocialAppearancePicker(BuildContext context) async {
  final scope = SocialAppearanceScope.maybeOf(context);
  final preferences = scope?.preferences ?? kSocialAppearance;
  await preferences.restore();
  if (!context.mounted) return;
  final current =
      preferences.choice ??
      scope?.choice ??
      KorlixAppearanceChoice(
        korlixSkinOf(context).id,
        kKorlixScreenSkinNotifier.value,
      );
  var followApp = false;
  final selected = await showModalBottomSheet<KorlixAppearanceChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => KorlixAppearancePicker(
      current: current,
      title: 'Style your Social',
      subtitle: 'Your colors. Your space. Saved on this device.',
      showScreensaver: false,
      previewBuilder: (context, choice) =>
          SocialAppearancePreview(choice: choice),
      additionalControls: TextButton.icon(
        key: const Key('social-use-app-appearance'),
        onPressed: () {
          followApp = true;
          Navigator.pop(sheetContext);
        },
        icon: const Icon(Icons.sync_rounded),
        label: Text(
          preferences.choice == null
              ? 'Following app appearance'
              : 'Use app appearance',
        ),
      ),
    ),
  );
  if (!context.mounted || (selected == null && !followApp)) return;
  final saved = await preferences.apply(followApp ? null : selected);
  if (!context.mounted) return;
  final message = !saved
      ? 'Social look applied for this visit. Device storage could not save it.'
      : followApp
      ? 'Social now follows your app appearance.'
      : 'Social look saved: ${korlixThemeLabelFor(selected!.themeId)} · '
            '${korlixScreenSkinLabel(selected.skinId)}';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class SocialAppearanceButton extends StatelessWidget {
  const SocialAppearanceButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('social-appearance-button'),
    tooltip: 'Social themes & skins',
    onPressed: () => showSocialAppearancePicker(context),
    icon: const Icon(Icons.palette_outlined),
  );
}

/// A decorative sample, never a real conversation or presence indicator.
class SocialAppearancePreview extends StatelessWidget {
  const SocialAppearancePreview({super.key, required this.choice});
  final KorlixAppearanceChoice choice;
  @override
  Widget build(BuildContext context) {
    final palette = korlixSkinPaletteFor(choice.themeId);
    return Semantics(
      label:
          'Social preview: ${palette.label}, ${korlixScreenSkinLabel(choice.skinId)}. Sample messages.',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 280,
            child: KorlixScreenBackdrop(
              palette: palette,
              skinId: choice.skinId,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: MediaQuery.withNoTextScaling(
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.people_alt_rounded,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'KORLIX Social',
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.palette_outlined,
                                color: palette.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _message(
                            palette,
                            'Your people. Your kind of space.',
                            false,
                          ),
                          const SizedBox(height: 12),
                          _message(
                            palette,
                            'A little more color, a lot more me.',
                            true,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: palette.inputFill,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: palette.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 19,
                                  color: palette.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Write a message…',
                                  style: TextStyle(color: palette.hintText),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.send_rounded,
                                  size: 19,
                                  color: palette.primary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              for (final icon in [
                                Icons.dynamic_feed_outlined,
                                Icons.people_outline,
                                Icons.chat_bubble_outline,
                                Icons.forum_outlined,
                                Icons.groups_outlined,
                              ])
                                Icon(icon, size: 19, color: palette.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(KorlixSkinPalette palette, String text, bool mine) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 265),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: socialSurfaceDecoration(
        palette,
        choice.skinId,
        message: true,
        mine: mine,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.text,
          fontSize: 14,
          height: 1.35,
        ),
      ),
    ),
  );
}
