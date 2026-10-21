import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/accessibility/korlix_accessibility.dart';
import 'package:ai_wiz_command_center/auth/korlix_signup_plan.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/privacy/korlix_app_information.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'helpers/signup_eligibility.dart';

String token(String id, {String? intent}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
      'sub': id,
      'user_metadata': {'korlix_signup_plan': intent},
    })))}.signature';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'plan intent survives confirmation and cannot leak to another account',
    () async {
      await KorlixSignupPlanIntent.save('first', 'ultra');
      expect(await KorlixSignupPlanIntent.read(token('first')), 'ultra');
      expect(await KorlixSignupPlanIntent.read(token('second')), isNull);
      expect(
        await KorlixSignupPlanIntent.read(token('second', intent: 'pro')),
        'pro',
      );
      expect(
        await KorlixSignupPlanIntent.read(
          token('second', intent: 'enterprise'),
        ),
        isNull,
      );
      await KorlixSignupPlanIntent.clear(token('first'));
      expect(
        await KorlixSignupPlanIntent.read(token('first', intent: 'ultra')),
        isNull,
      );
    },
  );

  test(
    'accessibility persists while larger system text remains uncapped',
    () async {
      final prefs = KorlixAccessibilityPreferences();
      await prefs.update(
        contrast: true,
        motion: true,
        controls: true,
        scale: 1.25,
      );
      final restored = KorlixAccessibilityPreferences();
      await restored.restore();
      expect(restored.highContrast, isTrue);
      expect(restored.reduceMotion, isTrue);
      expect(restored.largerControls, isTrue);
      expect(restored.textScale, 1.25);
      expect(
        const KorlixAccessibleTextScaler(TextScaler.linear(2.5), 1.5).scale(20),
        50,
      );
      expect(
        const KorlixAccessibleTextScaler(TextScaler.noScaling, 1.5).scale(20),
        30,
      );
      prefs.dispose();
      restored.dispose();
    },
  );

  testWidgets(
    'Legal version displays runtime build instead of a release constant',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KorlixAppInformation(
              load: () async => PackageInfo(
                appName: 'KORLIX AI',
                packageName: 'test',
                version: '12.0.2',
                buildNumber: '987',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 12.0.2 • Build 987'), findsOneWidget);
      expect(find.byTooltip('Copy version and build number'), findsOneWidget);
    },
  );

  testWidgets(
    'white signup keeps plan choice through required email confirmation',
    (tester) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: app.AuthScreen(
            seasonalDate: DateTime(2026, 11, 1),
            client: MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode({
                  'session': null,
                  'user': {'id': 'new-member', 'email': 'member@example.test'},
                }),
                200,
              );
            }),
            onSignedIn: (_) async => fail('Email confirmation is required'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('New here? Create account'));
      final title = find.text('Create your account');
      expect(Theme.of(tester.element(title)).brightness, Brightness.light);
      final ultra = find.byKey(const Key('signup-plan-ultra'));
      final pro = find.byKey(const Key('signup-plan-pro'));
      final basic = find.byKey(const Key('signup-plan-basic'));
      expect(tester.getTopLeft(ultra).dy, lessThan(tester.getTopLeft(pro).dy));
      expect(tester.getTopLeft(pro).dy, lessThan(tester.getTopLeft(basic).dy));
      expect(find.text('Most features are extremely limited.'), findsOneWidget);
      await tap(tester, ultra);
      await tester.ensureVisible(find.byKey(const Key('auth-email')));
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'member@example.test',
      );
      await tester.ensureVisible(find.byKey(const Key('auth-password')));
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        'test-password',
      );
      await selectSignupAge(tester, '18 or older');
      await tap(tester, find.byKey(const Key('signup-policy-acceptance')));
      await tap(tester, find.byKey(const Key('auth-submit')));
      expect(jsonDecode(requests.single.body)['signup_plan'], 'ultra');
      expect(await KorlixSignupPlanIntent.read(token('new-member')), 'ultra');
      expect(
        find.textContaining('No subscription has started.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'registration controls remain usable at 320px and 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: app.AuthScreen(
            seasonalDate: DateTime(2026, 11, 1),
            onSignedIn: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('New here? Create account'));
      for (final tier in ['ultra', 'pro', 'basic']) {
        final card = find.byKey(Key('signup-plan-$tier'));
        await tap(tester, card);
        expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
      }
      await tap(tester, find.byKey(const Key('auth-accessibility')));
      expect(find.text('Make KORLIX work for you'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Done'), 300);
      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
