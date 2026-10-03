import 'package:ai_wiz_command_center/auth/korlix_october_welcome.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget octoberFixture({
  required DateTime date,
  String theme = 'korlix_blue',
  String language = 'en',
  VoidCallback? onPressed,
}) => MaterialApp(
  theme: korlixBuildTheme(theme),
  home: Scaffold(
    body: KorlixOctoberWelcome(
      date: date,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                KorlixOctoberGreeting(date: date, languageCode: language),
                const TextField(
                  decoration: InputDecoration(labelText: 'Email'),
                ),
                FilledButton(
                  onPressed: onPressed,
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('season is precisely the local October calendar month', () {
    expect(korlixIsOctober(DateTime(2026, 9, 30, 23, 59, 59)), isFalse);
    expect(korlixIsOctober(DateTime(2026, 10, 1)), isTrue);
    expect(korlixIsOctober(DateTime(2026, 10, 31, 23, 59, 59)), isTrue);
    expect(korlixIsOctober(DateTime(2026, 11, 1)), isFalse);
    expect(korlixIsOctober(DateTime(2027, 10, 3)), isTrue);
  });

  testWidgets(
    'seasonal decorations leave login controls and semantics usable',
    (tester) async {
      var signIns = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        octoberFixture(date: DateTime(2026, 10, 3), onPressed: () => signIns++),
      );
      await tester.pumpAndSettle();
      expect(find.text('A little October magic'), findsOneWidget);
      expect(find.text('Happy Halloween season!'), findsOneWidget);
      expect(find.byType(IgnorePointer), findsWidgets);
      expect(find.byType(ExcludeSemantics), findsWidgets);
      await tester.enterText(find.byType(TextField), 'welcome@example.com');
      expect(find.text('welcome@example.com'), findsOneWidget);
      await tester.tap(find.text('Sign in'));
      expect(signIns, 1);
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        matchesSemantics(
          label: 'Sign in',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('November restores the selected theme without seasonal copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      octoberFixture(
        date: DateTime(2026, 11, 1),
        theme: 'pure_white',
        onPressed: () {},
      ),
    );
    expect(find.text('A little October magic'), findsNothing);
    expect(find.text('Happy Halloween season!'), findsNothing);
    final background = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(KorlixOctoberWelcome),
            matching: find.byType(Container),
          )
          .first,
    );
    final gradient =
        (background.decoration! as BoxDecoration).gradient! as LinearGradient;
    final skin = korlixSkinPaletteFor('pure_white');
    expect(gradient.colors, [
      skin.backgroundTop,
      skin.backgroundMid,
      skin.backgroundBottom,
    ]);
    await tester.tap(find.text('Sign in'));
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    ('es-MX', 'Un octubre lleno de magia'),
    ('Spanish', 'Un octubre lleno de magia'),
    ('fr-CA', 'Un peu de magie en octobre'),
    ('French', 'Un peu de magie en octobre'),
  ]) {
    testWidgets('greeting follows ${locale.$1}', (tester) async {
      await tester.pumpWidget(
        octoberFixture(date: DateTime(2026, 10, 3), language: locale.$1),
      );
      expect(find.text(locale.$2), findsOneWidget);
      expect(find.text('A little October magic'), findsNothing);
    });
  }

  for (final theme in ['pure_white', 'pure_black']) {
    testWidgets(
      'friendly banner fits narrow screens and enlarged text in $theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme(theme),
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: KorlixOctoberWelcome(
                  date: DateTime(2026, 10, 3),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(48),
                      child: KorlixOctoberGreeting(
                        date: DateTime(2026, 10, 3),
                        languageCode: 'fr',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Un peu de magie en octobre'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
