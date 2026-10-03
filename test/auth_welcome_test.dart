import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/auth/korlix_welcome_confirmation.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Future<void> credentials(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(TextField).first);
  await tester.enterText(find.byType(TextField).first, 'member@example.test');
  await tester.ensureVisible(find.byType(TextField).last);
  await tester.enterText(find.byType(TextField).last, 'test-password');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'signup without session shows confirmation steps and never signs in',
    (tester) async {
      var signedIn = false;
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({
            'session': null,
            'user': {'email': 'member@example.test'},
          }),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('korlix_blue'),
          home: app.AuthScreen(
            seasonalDate: DateTime(2026, 11, 1),
            client: client,
            onSignedIn: (_) async {
              signedIn = true;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('New here? Create account'));
      await tester.tap(find.text('New here? Create account'));
      await tester.pumpAndSettle();
      await credentials(tester);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(path, '/api/auth/signup');
      expect(signedIn, isFalse);
      expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
      expect(find.text('Welcome to KORLIX AI'), findsOneWidget);
      expect(find.text('Look for Supabase'), findsOneWidget);
      expect(find.textContaining('before you can log in'), findsOneWidget);
      await tester.ensureVisible(find.text('Back to sign in'));
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'member@example.test',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      expect(find.text('Sign in to Korlix AI'), findsOneWidget);
    },
  );

  testWidgets(
    'signin with missing session shows an error instead of a signup success',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: app.AuthScreen(
            seasonalDate: DateTime(2026, 11, 1),
            client: MockClient(
              (_) async => http.Response('{"session":null}', 200),
            ),
            onSignedIn: (_) async => fail('No session'),
          ),
        ),
      );
      await credentials(tester);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(KorlixWelcomeConfirmation), findsNothing);
      expect(
        find.textContaining('Sign-in did not return a session'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unconfirmed email error opens guidance and changing email clears credentials',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: korlixBuildTheme('pure_white'),
          home: app.AuthScreen(
            seasonalDate: DateTime(2026, 11, 1),
            client: MockClient(
              (_) async =>
                  http.Response('{"error":"Email not confirmed"}', 400),
            ),
            onSignedIn: (_) async => fail('No session'),
          ),
        ),
      );
      await credentials(tester);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
      await tester.ensureVisible(find.text('Use a different email address'));
      await tester.tap(find.text('Use a different email address'));
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(find.text('Create your Korlix AI account'), findsOneWidget);
    },
  );
}
