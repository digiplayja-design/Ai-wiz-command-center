import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme_picker.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_screen.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  for (final id in korlixThemeIds) {
    test('$id has readable shared text, accents, inputs and button labels', () {
      final skin = korlixSkinPaletteFor(id);
      final surfaces = [
        skin.backgroundTop,
        skin.backgroundMid,
        skin.backgroundBottom,
        skin.panel,
        skin.panelDeep,
        skin.panelSoft,
        skin.inputFill,
        skin.buttonFill,
      ];
      for (final background in surfaces) {
        for (final foreground in [
          skin.text,
          skin.mutedText,
          skin.hintText,
          skin.primary,
          skin.secondary,
          skin.danger,
        ]) {
          expect(
            contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '$id $foreground on $background',
          );
        }
      }
      expect(
        contrast(skin.textOnAccent, skin.primary),
        greaterThanOrEqualTo(4.5),
      );
      final bubble = Color.alphaBlend(
        skin.primary.withValues(alpha: .13),
        skin.panelDeep,
      );
      expect(contrast(skin.text, bubble), greaterThanOrEqualTo(4.5));
      final theme = korlixBuildTheme(id);
      expect(
        contrast(
          theme.inputDecorationTheme.focusedBorder!.borderSide.color,
          skin.inputFill,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(
        theme.brightness,
        skin.isLight ? Brightness.light : Brightness.dark,
      );
      expect(theme.colorScheme.onSurface, skin.text);
      expect(theme.colorScheme.onPrimary, skin.textOnAccent);
    });
  }

  test('saved theme IDs and earlier aliases retain their meaning', () {
    for (final entry in {
      'blue': 'korlix_blue',
      'purple_green': 'matrix_green',
      'black_gold': 'ultra_gold',
      'pink_luxe': 'pink_white',
      'red_ice': 'dark_crimson',
      'black_white': 'white_gray',
    }.entries) {
      expect(korlixNormalizeSkinId(entry.key), entry.value);
    }
    expect(korlixNormalizeSkinId('unknown'), 'korlix_blue');
  });

  testWidgets(
    'changing theme updates route controls without losing navigation or a typed draft',
    (tester) async {
      final selection = ValueNotifier('korlix_blue');
      final controller = TextEditingController();
      addTearDown(selection.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        KorlixThemeScope(
          selection: selection,
          builder: (context, theme) => MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Column(
                          children: [
                            TextField(controller: controller),
                            FilledButton(
                              onPressed: () {},
                              child: const Text('Create'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open workspace'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Keep this conversation draft.',
      );
      selection.value = 'pink_white';
      await tester.pumpAndSettle();
      expect(find.text('Create'), findsOneWidget);
      expect(controller.text, 'Keep this conversation draft.');
      final theme = Theme.of(tester.element(find.byType(TextField)));
      expect(theme.brightness, Brightness.light);
      expect(
        theme.colorScheme.primary,
        korlixSkinPaletteFor('pink_white').primary,
      );
      selection.value = 'ultra_gold';
      await tester.pumpAndSettle();
      expect(controller.text, 'Keep this conversation draft.');
      expect(
        Theme.of(tester.element(find.byType(TextField))).brightness,
        Brightness.dark,
      );
    },
  );

  testWidgets(
    'preview is reversible and apply returns the selected theme on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showKorlixThemePicker(
                    context,
                    currentId: 'korlix_blue',
                  );
                },
                child: const Text('Themes'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Themes'));
      await tester.pumpAndSettle();
      final rose = find.byKey(const ValueKey('theme-preview-pink_white'));
      await tester.ensureVisible(rose);
      await tester.tap(rose);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.byTooltip('Close theme preview'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Themes'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(rose);
      await tester.tap(rose);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-theme')));
      await tester.pumpAndSettle();
      expect(selected, 'pink_white');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme previews remain usable with large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('white_gray'),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.6),
          ),
          child: const KorlixThemePicker(currentId: 'white_gray'),
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-preview-white_gray')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('apply-theme')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shortcut controls offer six 48-pixel targets and a named preview action',
    (tester) async {
      String? selected;
      var previews = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: Scaffold(
            body: KorlixThemeShortcuts(
              selectedId: 'korlix_blue',
              onSelect: (id) => selected = id,
              onPreview: () => previews++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Rose Quartz'));
      await tester.pump();
      expect(selected, 'pink_white');
      await tester.tap(find.text('KORLIX Midnight · Preview themes'));
      expect(previews, 1);
      final targets = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == 48 && box.height == 48);
      expect(targets.length, 6);
    },
  );

  testWidgets('picture workspace follows each selected palette', (
    tester,
  ) async {
    for (final id in korlixThemeIds) {
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme(id),
          home: PictureStudioScreen(
            onImprove: (_, _) async =>
                throw StateError('No edit in a theme test'),
            ensureConsent: () async => true,
            onOpenTemplates: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actual = Theme.of(tester.element(find.byType(TextField)));
      expect(actual.colorScheme.primary, korlixSkinPaletteFor(id).primary);
      expect(
        actual.brightness,
        korlixSkinPaletteFor(id).isLight ? Brightness.light : Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
