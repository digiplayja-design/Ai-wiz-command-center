import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/auth/korlix_entry_welcome.dart';
import 'package:ai_wiz_command_center/billing/korlix_plan_prompt.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/onboarding/korlix_starter_tasks.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget starters({
  String account = 'account-a',
  String? tier = 'basic',
  String theme = 'korlix_blue',
  double scale = 1,
  Future<bool> Function(KorlixStarterTask)? onTask,
  VoidCallback? onExplore,
  VoidCallback? onViewPlans,
}) => MaterialApp(
  theme: korlixBuildTheme(theme),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: KorlixStarterTasks(
            key: ValueKey(account),
            storageKey: account,
            tier: tier,
            onTask: onTask ?? (_) async => false,
            onExplore: onExplore ?? () {},
            onViewPlans: onViewPlans ?? () {},
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('welcome offers signup first without making an auth request', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('korlix_blue'),
        home: app.AuthScreen(
          showWelcome: true,
          seasonalDate: DateTime(2026, 11, 1),
          client: MockClient((_) async {
            requests++;
            return http.Response('{}', 500);
          }),
          onSignedIn: (_) async => fail('No credentials were submitted'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KorlixEntryWelcome), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tap(tester, find.byKey(const Key('welcome-create-account')));
    expect(find.text('Create your free account'), findsOneWidget);
    expect(find.byKey(const Key('signup-age-range')), findsOneWidget);
    expect(find.byKey(const Key('signup-policy-acceptance')), findsOneWidget);
    expect(find.byKey(const Key('remember-email')), findsNothing);
    await tap(tester, find.text('Login preferences'));
    expect(find.byKey(const Key('remember-email')), findsOneWidget);
    await tap(tester, find.byTooltip('Back to welcome'));
    await tap(tester, find.byKey(const Key('welcome-sign-in')));
    expect(find.text('Sign in to Korlix AI'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelled starter keeps guidance; accepted starter dismisses only its account',
    (tester) async {
      var accept = false;
      final selected = <KorlixStarterTask>[];
      Widget screen(String account) => starters(
        account: account,
        onTask: (task) async {
          selected.add(task);
          return accept;
        },
      );
      await tester.pumpWidget(screen('account-a'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('starter-email')));
      expect(selected, [KorlixStarterTask.email]);
      expect(find.byKey(const Key('first-use-panel')), findsOneWidget);
      accept = true;
      await tap(tester, find.byKey(const Key('starter-writing')));
      expect(selected.last, KorlixStarterTask.writing);
      expect(find.byKey(const Key('first-use-panel')), findsNothing);
      await tester.pumpWidget(screen('account-b'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('first-use-panel')), findsOneWidget);
      await tester.pumpWidget(screen('account-a'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('first-use-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Basic can inspect plans or continue free without choosing a task',
    (tester) async {
      var plans = 0;
      var explored = 0;
      await tester.pumpWidget(
        starters(
          onTask: (_) async => fail('No task was selected'),
          onViewPlans: () => plans++,
          onExplore: () => explored++,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('starter-view-plans')));
      expect(plans, 1);
      expect(explored, 0);
      expect(find.byKey(const Key('first-use-panel')), findsOneWidget);
      await tap(tester, find.byKey(const Key('starter-keep-basic')));
      expect(explored, 1);
      expect(plans, 1);
      expect(find.byKey(const Key('first-use-panel')), findsNothing);
    },
  );

  testWidgets('unknown and paid tiers never receive the Basic upsell', (
    tester,
  ) async {
    for (final tier in [null, 'pro', 'ultra', 'enterprise']) {
      await tester.pumpWidget(starters(account: 'account-$tier', tier: tier));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('starter-email')), findsOneWidget);
      expect(find.text('BASIC · FREE'), findsNothing);
      expect(find.byKey(const Key('starter-view-plans')), findsNothing);
    }
  });

  testWidgets(
    'welcome, signup and starter actions remain reachable with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final theme in ['korlix_blue', 'pure_white']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme(theme),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: app.AuthScreen(
                  key: ValueKey(theme),
                  showWelcome: true,
                  seasonalDate: DateTime(2026, 11, 1),
                  client: MockClient((_) async => http.Response('{}', 500)),
                  onSignedIn: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const Key('welcome-create-account')));
        expect(
          find.text('Create your free account').hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('auth-submit')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'signup/$theme');
        await tester.pumpWidget(starters(theme: theme, scale: 1.6));
        await tester.pumpAndSettle();
        for (final key in [
          'starter-email',
          'starter-writing',
          'starter-content',
          'starter-view-plans',
        ]) {
          await tester.ensureVisible(find.byKey(Key(key)));
          await tester.pumpAndSettle();
          expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull, reason: 'starters/$theme');
      }
    },
  );

  testWidgets('review welcome, registration and starter layouts', (
    tester,
  ) async {
    final output = Platform.environment['KORLIX_DISCOVERY_REVIEW'];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Visibility depends on real text metrics even when PNG capture is off.
    // Keep the release build and screenshot-review paths on the same font.
    await tester.runAsync(() async {
      final font = FontLoader('Roboto')
        ..addFont(
          File('assets/fieldproof/Roboto-Regular.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await font.load();
      if (output != null) {
        final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await icons.load();
      }
    });
    Future<void> capture(GlobalKey key, String name) async {
      if (output == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final theme in ['korlix_blue', 'pure_white']) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: korlixBuildTheme(theme),
            home: app.AuthScreen(
              showWelcome: true,
              seasonalDate: DateTime(2026, 11, 1),
              client: MockClient((_) async => http.Response('{}', 500)),
              onSignedIn: (_) async {},
            ),
          ),
        ),
      );
      if (output != null) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/korlix_mini_mark.png'),
            boundary.currentContext!,
          ),
        );
      }
      await tester.pumpAndSettle();
      await capture(boundary, '$theme-welcome');
      expect(
        find.byKey(const Key('welcome-create-account')).hitTestable(),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('entry-intro-read')));
      await capture(boundary, '$theme-welcome-transcript');
      await tap(tester, find.byTooltip('Close introduction'));
      await tap(tester, find.byKey(const Key('welcome-create-account')));
      expect(
        find.text('Create your free account').hitTestable(),
        findsOneWidget,
      );
      await capture(boundary, '$theme-signup-top');
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      await capture(boundary, '$theme-signup-bottom');
      final starterBoundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: starterBoundary,
          child: starters(theme: theme),
        ),
      );
      await tester.pumpAndSettle();
      await capture(starterBoundary, '$theme-starter');
      expect(tester.takeException(), isNull, reason: theme);
    }
  });

  testWidgets('premium prompt only requests plans after an explicit tap', (
    tester,
  ) async {
    bool? result;
    var comingSoon = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showKorlixPlanPrompt(
                  context: context,
                  title: 'PDF exports',
                  availability: 'Pro',
                  description: 'Save your work as a PDF.',
                  comingSoon: comingSoon,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Open'));
    expect(result, isNull);
    await tap(tester, find.text('Not now'));
    expect(result, isFalse);
    await tap(tester, find.text('Open'));
    await tap(tester, find.byKey(const Key('premium-view-plans')));
    expect(result, isTrue);
    comingSoon = true;
    await tap(tester, find.text('Open'));
    expect(find.byKey(const Key('premium-view-plans')), findsNothing);
    await tap(tester, find.text('Close'));
    expect(result, isFalse);
  });
}
