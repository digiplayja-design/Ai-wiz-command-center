import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/theme/korlix_screen_skin.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_picker.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_preferences.dart';

void main() {
  test(
    'Pure White has white surfaces and Classic paints an entirely white backdrop',
    () async {
      final palette = korlixSkinPaletteFor('pure_white');
      expect(korlixThemeIds.length, 12);
      expect(korlixScreenSkinIds.length, 6);
      for (final color in [
        palette.backgroundTop,
        palette.backgroundMid,
        palette.backgroundBottom,
        palette.panel,
        palette.panelDeep,
        palette.panelSoft,
        palette.inputFill,
        palette.buttonFill,
      ]) {
        expect(color, Colors.white);
      }
      final recorder = ui.PictureRecorder();
      KorlixScreenSkinPainter(
        palette,
        'classic',
      ).paint(Canvas(recorder), const Size(80, 80));
      final picture = recorder.endRecording();
      final image = await picture.toImage(80, 80);
      final bytes = await image.toByteData();
      expect(bytes!.buffer.asUint8List().every((v) => v == 255), isTrue);
      image.dispose();
      picture.dispose();
    },
  );

  test('old preference migrates without changing its palette', () async {
    SharedPreferences.setMockInitialValues({'korlix_ui_theme': 'pink_luxe'});
    final theme = ValueNotifier('korlix_blue'), skin = ValueNotifier('classic');
    final store = KorlixAppearancePreferences(theme: theme, screenSkin: skin);
    await store.restore();
    expect(theme.value, 'pink_white');
    expect(skin.value, 'classic');
    theme.dispose();
    skin.dispose();
  });

  test(
    'colors and skin survive reload together and latest rapid selection wins',
    () async {
      SharedPreferences.setMockInitialValues({});
      final theme = ValueNotifier('korlix_blue'),
          skin = ValueNotifier('classic');
      final store = KorlixAppearancePreferences(theme: theme, screenSkin: skin);
      final first = store.apply(
        KorlixAppearanceChoice('mint_cloud', 'bubbles'),
      );
      final last = store.apply(
        KorlixAppearanceChoice('pure_white', 'glass_break'),
      );
      expect(theme.value, 'pure_white');
      expect(skin.value, 'glass_break');
      expect(await first, isTrue);
      expect(await last, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(KorlixAppearancePreferences.storageKey)!),
        {'theme': 'pure_white', 'skin': 'glass_break'},
      );
      final restoredTheme = ValueNotifier('korlix_blue'),
          restoredSkin = ValueNotifier('classic');
      await KorlixAppearancePreferences(
        theme: restoredTheme,
        screenSkin: restoredSkin,
      ).restore();
      expect(restoredTheme.value, 'pure_white');
      expect(restoredSkin.value, 'glass_break');
      theme.dispose();
      skin.dispose();
      restoredTheme.dispose();
      restoredSkin.dispose();
    },
  );

  test(
    'late restoration does not overwrite a selection made during startup',
    () async {
      SharedPreferences.setMockInitialValues({'korlix_ui_theme': 'ultra_gold'});
      final gate = Completer<SharedPreferences>();
      final theme = ValueNotifier('korlix_blue'),
          skin = ValueNotifier('classic');
      final store = KorlixAppearancePreferences(
        theme: theme,
        screenSkin: skin,
        load: () => gate.future,
      );
      final restoration = store.restore();
      final saving = store.apply(
        KorlixAppearanceChoice('pure_white', 'bubbles'),
      );
      gate.complete(await SharedPreferences.getInstance());
      await restoration;
      await saving;
      expect(theme.value, 'pure_white');
      expect(skin.value, 'bubbles');
      theme.dispose();
      skin.dispose();
    },
  );

  test(
    'unavailable storage keeps the immediate visible selection and reports it was not saved',
    () async {
      final theme = ValueNotifier('korlix_blue'),
          skin = ValueNotifier('classic');
      final store = KorlixAppearancePreferences(
        theme: theme,
        screenSkin: skin,
        load: () async => throw StateError('Storage unavailable'),
      );
      expect(
        await store.apply(KorlixAppearanceChoice('pure_white', 'glass')),
        isFalse,
      );
      await store.restore();
      expect(theme.value, 'pure_white');
      expect(skin.value, 'glass');
      theme.dispose();
      skin.dispose();
    },
  );

  test(
    'corrupt storage falls back to the older theme and unknown choices are safe',
    () async {
      SharedPreferences.setMockInitialValues({
        'korlix_ui_theme': 'ultra_gold',
        KorlixAppearancePreferences.storageKey: 'not json',
      });
      final theme = ValueNotifier('korlix_blue'),
          skin = ValueNotifier('classic');
      await KorlixAppearancePreferences(
        theme: theme,
        screenSkin: skin,
      ).restore();
      expect(theme.value, 'ultra_gold');
      expect(skin.value, 'classic');
      expect(
        KorlixAppearanceChoice('missing', 'missing').themeId,
        'korlix_blue',
      );
      expect(KorlixAppearanceChoice('missing', 'missing').skinId, 'classic');
      theme.dispose();
      skin.dispose();
    },
  );

  testWidgets(
    'all 72 combinations paint and preserve interactive controls and drafts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: 'Keep my draft');
      addTearDown(controller.dispose);
      var taps = 0;
      for (final theme in korlixThemeIds) {
        for (final skin in korlixScreenSkinIds) {
          final palette = korlixSkinPaletteFor(theme);
          await tester.pumpWidget(
            MaterialApp(
              theme: korlixBuildTheme(theme),
              home: Scaffold(
                body: KorlixScreenBackdrop(
                  palette: palette,
                  skinId: skin,
                  child: Center(
                    child: KorlixSkinFrame(
                      palette: palette,
                      skinId: skin,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: controller),
                          FilledButton(
                            onPressed: () => taps++,
                            child: const Text('Send'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send'));
          expect(controller.text, 'Keep my draft');
          expect(tester.takeException(), isNull);
        }
      }
      expect(taps, 72);
    },
  );

  testWidgets(
    'previewing skins keeps colors; cancel is reversible; templates apply both',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      KorlixAppearanceChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('pure_white'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<KorlixAppearanceChoice>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => KorlixAppearancePicker(
                      current: KorlixAppearanceChoice('pure_white', 'classic'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-tab-1')));
      await tester.pumpAndSettle();
      final bubbles = find.byKey(const ValueKey('skin-bubbles'));
      await tester.ensureVisible(bubbles);
      await tester.tap(bubbles);
      await tester.pumpAndSettle();
      expect(find.text('Pure White · Bubbles'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.byTooltip('Close appearance preview'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Pure White · Classic'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('appearance-tab-2')));
      await tester.pumpAndSettle();
      final template = find.byKey(const ValueKey('template-Midnight Fracture'));
      await tester.ensureVisible(template);
      await tester.tap(template);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-appearance')));
      await tester.pumpAndSettle();
      expect(result!.themeId, 'korlix_blue');
      expect(result!.skinId, 'glass_break');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing only colors preserves the wrapper and large-text Apply stays usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.6),
            ),
            child: KorlixAppearancePicker(
              current: KorlixAppearanceChoice('korlix_blue', 'glass_break'),
            ),
          ),
        ),
      );
      final white = find.descendant(
        of: find.byKey(const ValueKey('theme-preview-pure_white')),
        matching: find.text('Pure White'),
      );
      await tester.ensureVisible(white);
      await tester.tap(white);
      await tester.pumpAndSettle();
      expect(find.text('Pure White · Glass Break'), findsOneWidget);
      expect(
        find.byKey(const Key('apply-appearance')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('appearance-tab-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
