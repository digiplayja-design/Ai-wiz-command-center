import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/auth/korlix_signup_eligibility.dart';
import 'package:ai_wiz_command_center/auth/korlix_welcome_confirmation.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

import 'helpers/signup_eligibility.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> mountSignup(
  WidgetTester tester,
  List<http.Request> requests,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: app.AuthScreen(
        seasonalDate: DateTime(2026, 11, 1),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"session":null,"user":{"email":"member@example.test"}}',
            200,
          );
        }),
        onSignedIn: (_) async =>
            fail('Email confirmation must still be required'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('auth-age-notice')), findsOneWidget);
  expect(find.byKey(const Key('auth-terms-link')), findsOneWidget);
  expect(find.byKey(const Key('auth-privacy-link')), findsOneWidget);
  expect(find.byKey(const Key('signup-age-range')), findsNothing);
  await tap(tester, find.text('New here? Create account'));
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signup needs an age range and explicit policy acceptance', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mountSignup(tester, requests);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('signup-policy-acceptance')),
          )
          .value,
      isFalse,
    );
    await tap(tester, find.text('Create account'));
    expect(requests, isEmpty);
    expect(find.text('Select your age range to continue.'), findsOneWidget);
    await selectSignupAge(tester, '18 or older');
    await tap(tester, find.text('Create account'));
    expect(requests, isEmpty);
    expect(
      find.text(
        'Please agree to the Terms of Use and acknowledge the Privacy Policy.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('signup-policy-acceptance')));
    await tap(tester, find.text('Create account'));
    expect(requests.single.url.path, '/api/auth/signup');
    final signupBody = jsonDecode(requests.single.body);
    final deviceId = app.KorlixDeviceStore.headers()['X-Korlix-Device-Id'];
    expect(deviceId, isNotEmpty);
    expect(requests.single.headers['X-Korlix-Device-Id'], deviceId);
    expect(signupBody['device_id'], deviceId);
    expect(jsonDecode(requests.single.body)['signup_eligibility'], {
      'age_band': '18_plus',
      'terms_accepted': true,
      'privacy_acknowledged': true,
      'parent_permission': false,
      'policy_version': '2026-10-06',
    });
    expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
  });

  testWidgets('under-16 cannot submit by button or keyboard', (tester) async {
    final requests = <http.Request>[];
    await mountSignup(tester, requests);
    await selectSignupAge(tester, 'Under 16');
    expect(find.byKey(const Key('signup-underage-message')), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Create account'),
    );
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('auth-password')));
    await tester.showKeyboard(find.byKey(const Key('auth-password')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.byType(KorlixWelcomeConfirmation), findsNothing);
  });

  testWidgets(
    '16–17 requires guardian acknowledgment and preserves confirmation',
    (tester) async {
      final requests = <http.Request>[];
      await mountSignup(tester, requests);
      await selectSignupAge(tester, '16–17');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('signup-parent-permission')),
            )
            .value,
        isFalse,
      );
      await tap(tester, find.byKey(const Key('signup-policy-acceptance')));
      await tap(tester, find.text('Create account'));
      expect(requests, isEmpty);
      expect(
        find.text(
          'Users aged 16–17 need permission from a parent or guardian.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('signup-parent-permission')));
      await tap(tester, find.text('Create account'));
      final eligibility = jsonDecode(
        requests.single.body,
      )['signup_eligibility'];
      expect(eligibility['age_band'], '16_17');
      expect(eligibility['parent_permission'], isTrue);
      expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
    },
  );

  testWidgets('switching age or leaving signup resets acknowledgments', (
    tester,
  ) async {
    await mountSignup(tester, []);
    await acceptAdultSignup(tester);
    await selectSignupAge(tester, '16–17');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('signup-policy-acceptance')),
          )
          .value,
      isFalse,
    );
    await tap(tester, find.text('Already have an account? Sign in'));
    await tap(tester, find.text('New here? Create account'));
    expect(find.byKey(const Key('signup-parent-permission')), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('signup-policy-acceptance')),
          )
          .value,
      isFalse,
    );
  });

  test(
    'web policy URLs stay on the serving origin and native URLs use the website',
    () {
      expect(
        korlixSignupPolicyUri(
          'terms.html',
          isWeb: true,
          webBase: Uri.parse(
            'https://korlixdeveloper-website.onrender.com/app/?old=true#route',
          ),
        ).toString(),
        'https://korlixdeveloper-website.onrender.com/terms.html',
      );
      expect(
        korlixSignupPolicyUri('privacy-policy.html', isWeb: false).toString(),
        'https://www.korlixdeveloper.com/privacy-policy.html',
      );
    },
  );

  testWidgets(
    'policy links open independently and failed launch keeps a visible address',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KorlixSignupPolicyLinks(
              openPolicy: (uri) async {
                opened.add(uri);
                return false;
              },
            ),
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('auth-terms-link')));
      expect(opened.single.path, '/terms.html');
      expect(
        find.textContaining('Could not open this policy.'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('auth-privacy-link')));
      expect(opened.last.path, '/privacy-policy.html');
    },
  );

  for (final scenario in [
    (320.0, 1.8, 'korlix_blue'),
    (390.0, 1.0, 'pure_white'),
    (1024.0, 1.0, 'korlix_blue'),
  ]) {
    testWidgets(
      'signup is scrollable at ${scenario.$1}px and text scale ${scenario.$2}',
      (tester) async {
        tester.view.physicalSize = Size(scenario.$1, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme(scenario.$3),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(scenario.$1, 844),
                textScaler: TextScaler.linear(scenario.$2),
              ),
              child: app.AuthScreen(
                seasonalDate: DateTime(2026, 10, 6),
                onSignedIn: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text('New here? Create account'));
        await selectSignupAge(tester, '16–17');
        await tap(tester, find.byKey(const Key('signup-parent-permission')));
        await tap(tester, find.byKey(const Key('signup-policy-acceptance')));
        await tester.ensureVisible(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.text('Create account').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
