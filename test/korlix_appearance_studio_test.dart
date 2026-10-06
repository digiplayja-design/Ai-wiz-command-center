import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/theme/korlix_screen_skin.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_picker.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_look_library.dart';

Future<void> mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  int tab = 2,
  double keyboard = 0,
  KorlixAppearanceChoice? current,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: const Key('studio-export'),
          child: KorlixAppearancePicker(
            current:
                current ?? KorlixAppearanceChoice('korlix_blue', 'classic'),
            initialTab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every curated look is a distinct valid color and skin combination', () {
    expect(korlixLookTemplates.length, 18);
    expect(
      korlixLookTemplates
          .map((look) => '${look.themeId}/${look.skinId}')
          .toSet()
          .length,
      18,
    );
    for (final look in korlixLookTemplates) {
      expect(korlixThemeIds, contains(look.themeId));
      expect(korlixScreenSkinIds, contains(look.skinId));
    }
  });

  test(
    'bookmarks survive reload and rapid saves without changing applied appearance',
    () async {
      final theme = kKorlixThemeNotifier.value,
          skin = kKorlixScreenSkinNotifier.value;
      final library = KorlixLookLibrary();
      await library.restore();
      final first = KorlixAppearanceChoice('pure_white', 'linen');
      final second = KorlixAppearanceChoice('lavender_mist', 'mesh');
      await Future.wait([
        library.toggle(first),
        library.toggle(second),
        library.toggle(first),
      ]);
      final restored = KorlixLookLibrary();
      await restored.restore();
      expect(restored.items, hasLength(1));
      expect(restored.contains(second), isTrue);
      expect(restored.contains(first), isFalse);
      expect(kKorlixThemeNotifier.value, theme);
      expect(kKorlixScreenSkinNotifier.value, skin);
    },
  );

  test(
    'bookmark restore rejects corrupt, duplicate and unknown entries',
    () async {
      SharedPreferences.setMockInitialValues({
        KorlixLookLibrary.storageKey: jsonEncode([
          {'theme': 'pure_white', 'skin': 'linen'},
          {'theme': 'pure_white', 'skin': 'linen'},
          {'theme': 'no-such-theme', 'skin': 'glass'},
          {'theme': 'pure_white', 'skin': 'no-such-skin'},
          null,
          42,
        ]),
      });
      final library = KorlixLookLibrary();
      await library.restore();
      expect(library.items, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(KorlixLookLibrary.storageKey, '{broken');
      await KorlixLookLibrary().restore();
    },
  );

  test(
    'late bookmark restore cannot overwrite a new choice; storage failure is reported',
    () async {
      final gate = Completer<SharedPreferences>();
      final library = KorlixLookLibrary(load: () => gate.future);
      final restoring = library.restore();
      final choice = KorlixAppearanceChoice('ocean_blue', 'orbit');
      final saving = library.toggle(choice);
      gate.complete(await SharedPreferences.getInstance());
      await restoring;
      expect(await saving, isTrue);
      expect(library.contains(choice), isTrue);
      final failed = KorlixLookLibrary(
        load: () async => throw StateError('Unavailable'),
      );
      await failed.restore();
      expect(await failed.toggle(choice), isFalse);
      expect(failed.contains(choice), isTrue);
    },
  );

  testWidgets(
    'template discovery filters, saves without applying, and restores the current preview',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      await tap(tester, find.byKey(const Key('appearance-filter-Light')));
      expect(find.byKey(const Key('template-Crimson Orbit')), findsNothing);
      await tap(tester, find.byKey(const Key('appearance-search')));
      await tester.enterText(
        find.byKey(const Key('appearance-search')),
        'Crimson',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-empty')), findsOneWidget);
      await tap(tester, find.byKey(const Key('appearance-filter-Dark')));
      expect(find.byKey(const Key('template-Crimson Orbit')), findsOneWidget);
      await tap(tester, find.byTooltip('Save Crimson Orbit'));
      expect(find.text('KORLIX Midnight · Classic'), findsOneWidget);
      await tap(tester, find.byKey(const Key('template-Crimson Orbit')));
      expect(find.text('Crimson Ice · Orbit'), findsOneWidget);
      await tap(tester, find.byKey(const Key('reset-appearance')));
      expect(find.text('KORLIX Midnight · Classic'), findsOneWidget);
      await tap(tester, find.byKey(const Key('appearance-filter-Saved')));
      expect(find.byKey(const Key('saved-dark_crimson-orbit')), findsOneWidget);
      final library = KorlixLookLibrary();
      await library.restore();
      expect(
        library.contains(KorlixAppearanceChoice('dark_crimson', 'orbit')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom mixes can be saved and previews switch between Home and Chat',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        current: KorlixAppearanceChoice('mint_cloud', 'orbit'),
      );
      await tap(tester, find.byKey(const Key('appearance-preview-Chat')));
      expect(
        tester
            .widgetList<KorlixAppearancePreview>(
              find.byType(KorlixAppearancePreview),
            )
            .first
            .chat,
        isTrue,
      );
      await tap(tester, find.byKey(const Key('save-appearance')));
      await tap(tester, find.byKey(const Key('appearance-filter-Saved')));
      expect(find.byKey(const Key('saved-mint_cloud-orbit')), findsOneWidget);
      await tap(tester, find.byTooltip('Unsave Mint Cloud · Orbit'));
      expect(find.byKey(const Key('appearance-empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone gallery uses two columns and keeps the Apply control visible with the keyboard',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, tab: 1);
      final classic = tester.getRect(find.byKey(const Key('skin-classic')));
      final glass = tester.getRect(find.byKey(const Key('skin-glass')));
      expect(classic.top, glass.top);
      expect(glass.left, greaterThan(classic.right));
      await tester.pumpWidget(const SizedBox());
      await mount(tester, keyboard: 300);
      final apply = tester.getRect(find.byKey(const Key('apply-appearance')));
      expect(apply.bottom, lessThanOrEqualTo(544));
      expect(
        find.byKey(const Key('apply-appearance')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gallery fits small phones, landscape and tablets at larger text sizes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(844, 390),
        const Size(1024, 1366),
      ]) {
        for (final scale in [1.0, 1.8]) {
          for (final tab in [1, 2]) {
            await tester.pumpWidget(const SizedBox());
            await mount(
              tester,
              size: size,
              scale: scale,
              tab: tab,
              current: KorlixAppearanceChoice(
                tab == 1 ? 'pure_white' : 'korlix_blue',
                'mesh',
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size / $scale / $tab',
            );
            await tap(
              tester,
              find.byKey(
                Key(tab == 1 ? 'skin-linen' : 'template-Pure & Simple'),
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size / $scale / $tab after selection',
            );
            expect(
              find.byKey(const Key('apply-appearance')).hitTestable(),
              findsOneWidget,
            );
          }
        }
      }
    },
  );

  testWidgets('export appearance review screens', (tester) async {
    final output = Platform.environment['KORLIX_APPEARANCE_PREVIEWS']!;
    await tester.runAsync(() async {
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
      if (sdk == null) {
        throw StateError('Set KORLIX_FLUTTER_ROOT for review exports.');
      }
      Future<ByteData> font(String path) async =>
          ByteData.sublistView(await File(path).readAsBytes());
      await (FontLoader('Roboto')
            ..addFont(font('assets/fieldproof/Roboto-Regular.ttf'))
            ..addFont(font('assets/fieldproof/Roboto-Bold.ttf')))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            font(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
          ))
          .load();
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (name, size, theme, skin, tab) in [
      ('phone-orbit', const Size(390, 844), 'korlix_blue', 'orbit', 2),
      ('phone-linen', const Size(390, 844), 'pure_white', 'linen', 1),
      ('tablet-mesh', const Size(1024, 1366), 'lavender_mist', 'mesh', 2),
      ('tablet-contour', const Size(1024, 1366), 'sunset_copper', 'contour', 1),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        size: size,
        tab: tab,
        current: KorlixAppearanceChoice(theme, skin),
      );
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('studio-export')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  }, skip: Platform.environment['KORLIX_APPEARANCE_PREVIEWS'] == null);
}
