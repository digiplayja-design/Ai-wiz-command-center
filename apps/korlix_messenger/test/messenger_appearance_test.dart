import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_social_core/social/social_appearance.dart';
import 'package:korlix_social_core/theme/korlix_appearance_preferences.dart';
import 'package:korlix_social_core/theme/korlix_look_catalog.dart';
import 'package:korlix_social_core/theme/korlix_screen_skin.dart';
import 'package:korlix_social_core/theme/korlix_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AppearanceProbe extends StatelessWidget {
  const _AppearanceProbe({required this.chat});
  final bool chat;

  @override
  Widget build(BuildContext context) => SocialScaffold(
    appBar: AppBar(title: Text(chat ? 'Conversation' : 'Messenger')),
    body: Column(
      children: [
        Text(
          '${korlixSkinOf(context).id}/${socialScreenSkinOf(context)}',
          key: const Key('active-look'),
        ),
        const TextField(key: Key('draft')),
        TextButton(
          onPressed: () => showSocialAppearancePicker(context),
          child: const Text('Choose appearance'),
        ),
        if (!chat)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              SocialPageRoute<void>(
                builder: (_) => const _AppearanceProbe(chat: true),
              ),
            ),
            child: const Text('Open conversation'),
          ),
      ],
    ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  SocialAppearancePreferences preferences,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(messengerDefaultAppearance.themeId),
      builder: (_, child) => SocialAppearance(
        preferences: preferences,
        defaultChoice: messengerDefaultAppearance,
        child: child!,
      ),
      home: const _AppearanceProbe(chat: false),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('new and reset Messenger appearances use Sunset Copper', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = SocialAppearancePreferences();
    await _mount(tester, preferences);
    expect(find.text('sunset_copper/contour'), findsOneWidget);
    await preferences.apply(KorlixAppearanceChoice('pure_white', 'glass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose appearance'));
    await tester.pumpAndSettle();
    final reset = find.byKey(const Key('social-use-app-appearance'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('sunset_copper/contour'), findsOneWidget);
    expect(preferences.choice, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
  });

  for (final look in korlixLookTemplates) {
    testWidgets('${look.name}: swatch tap, apply, routes and restart', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = SocialAppearancePreferences();
      await _mount(tester, preferences);
      await tester.tap(find.text('Open conversation'));
      await tester.pumpAndSettle();
      final draft = find.byKey(const Key('draft'));
      await tester.enterText(draft, 'Keep this unsent draft');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final draftState = tester.state(draft);
      await tester.tap(find.text('Choose appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-tab-2')));
      await tester.pumpAndSettle();
      final swatches = find.byKey(Key('template-${look.name}-swatches'));
      await tester.ensureVisible(swatches);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(swatches);
      await tester.tapAt(Offset(bounds.left + 18, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('appearance-selection'))).data,
        '${korlixThemeLabelFor(look.themeId)} · ${korlixScreenSkinLabel(look.skinId)}',
      );
      await tester.tap(find.byKey(const Key('apply-appearance')));
      await tester.pumpAndSettle();
      expect(find.text('${look.themeId}/${look.skinId}'), findsOneWidget);
      expect(preferences.choice!.themeId, look.themeId);
      expect(preferences.choice!.skinId, look.skinId);
      expect(identical(tester.state(draft), draftState), isTrue);
      expect(find.text('Keep this unsent draft'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('${look.themeId}/${look.skinId}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      preferences.dispose();
      final restored = SocialAppearancePreferences();
      await _mount(tester, restored);
      expect(find.text('${look.themeId}/${look.skinId}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
    });
  }

  test('every palette and finish renders bubbles without the yellow override', () {
    for (final theme in korlixThemeIds) {
      for (final skin in korlixScreenSkinIds) {
        for (final mine in [false, true]) {
          final palette = korlixSkinPaletteFor(theme);
          final decoration = socialSurfaceDecoration(
            palette,
            skin,
            message: true,
            mine: mine,
          );
          final colors = (decoration.gradient! as LinearGradient).colors;
          expect(colors, isNot(contains(const Color(0xFFFFDD00))));
          for (final background in colors) {
            final a = palette.text.computeLuminance();
            final b = background.computeLuminance();
            final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
            expect(ratio, greaterThanOrEqualTo(4.5), reason: '$theme/$skin/$mine');
          }
        }
      }
    }
  });

  testWidgets('all template previews render for visual inspection', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 380);
    tester.view.devicePixelRatio = 1;
    for (final look in korlixLookTemplates) {
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme(look.themeId),
          home: RepaintBoundary(
            key: const Key('preview-export'),
            child: Scaffold(
              appBar: AppBar(title: Text(look.name)),
              body: SocialAppearancePreview(choice: look.choice),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: look.name);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('preview-export')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final path = 'build/theme-previews/${look.themeId}-${look.skinId}.png';
        await File(path).parent.create(recursive: true);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
