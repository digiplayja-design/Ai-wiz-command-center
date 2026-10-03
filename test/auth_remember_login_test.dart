import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The plugin's test store lets a real preference load finish after user input.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:ai_wiz_command_center/auth/korlix_login_preferences.dart';
import 'package:ai_wiz_command_center/auth/korlix_welcome_confirmation.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const emailKey = ValueKey('auth-email');
const passwordKey = ValueKey('auth-password');
const rememberKey = ValueKey('remember-email');
const passwordSaveKey = ValueKey('offer-password-save');
const testEmail = 'member@example.test';
const testPassword = 'only-the-password-manager-should-save-this';

class DelayedPreferenceStore extends InMemorySharedPreferencesStore {
  DelayedPreferenceStore(super.data) : super.withData();

  final ready = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    await ready.future;
    return super.getAll();
  }
}

Widget login({
  http.Client? client,
  Future<void> Function(app.KorlixAuthSession)? onSignedIn,
}) => MaterialApp(
  theme: korlixBuildTheme('korlix_blue'),
  home: app.AuthScreen(
    seasonalDate: DateTime(2026, 10, 3),
    client: client ?? MockClient((_) async => http.Response('{}', 500)),
    onSignedIn: onSignedIn ?? (_) async {},
  ),
);

http.Response signedInResponse() => http.Response(
  jsonEncode({
    'session': {
      'access_token': 'offline-test-token',
      'refresh_token': 'offline-test-refresh',
    },
    'user': {'email': testEmail},
  }),
  200,
);

Future<void> mount(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterCredentials(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(emailKey));
  await tester.enterText(find.byKey(emailKey), testEmail);
  await tester.ensureVisible(find.byKey(passwordKey));
  await tester.enterText(find.byKey(passwordKey), testPassword);
  await tester.pumpAndSettle();
}

TextField emailField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(emailKey));

TextField passwordField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(passwordKey));

bool checked(WidgetTester tester, Key key) =>
    tester.widget<CheckboxListTile>(find.byKey(key)).value!;

List<bool> finishedAutofill(WidgetTester tester) => tester.testTextInput.log
    .where((call) => call.method == 'TextInput.finishAutofillContext')
    .map((call) => call.arguments as bool)
    .toList();

Future<void> expectPasswordNotPersisted(WidgetTester tester) async {
  final preferences = (await tester.runAsync(SharedPreferences.getInstance))!;
  for (final key in preferences.getKeys()) {
    expect(preferences.get(key).toString(), isNot(contains(testPassword)));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'login has independent email memory and password-manager defaults',
    (tester) async {
      await mount(tester, login());
      expect(checked(tester, rememberKey), isFalse);
      expect(checked(tester, passwordSaveKey), isTrue);
      expect(emailField(tester).controller!.text, isEmpty);
      expect(passwordField(tester).controller!.text, isEmpty);
      expect(
        emailField(tester).autofillHints,
        containsAll([AutofillHints.username, AutofillHints.email]),
      );
      expect(passwordField(tester).autofillHints, [AutofillHints.password]);
      expect(passwordField(tester).obscureText, isTrue);
      expect(
        tester
            .widget<AutofillGroup>(find.byType(AutofillGroup))
            .onDisposeAction,
        AutofillContextAction.cancel,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('email opt-in survives remount and opt-out forgets it', (
    tester,
  ) async {
    await mount(tester, login());
    await enterCredentials(tester);
    await tap(tester, find.byKey(rememberKey));
    var saved = (await tester.runAsync(KorlixLoginPreferences.load))!;
    expect(saved.rememberEmail, isTrue);
    expect(saved.email, testEmail);
    await tester.enterText(find.byKey(emailKey), 'changed@example.test');
    await tester.pumpAndSettle();
    saved = (await tester.runAsync(KorlixLoginPreferences.load))!;
    expect(saved.email, 'changed@example.test');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(login());
    await tester.pumpAndSettle();
    expect(emailField(tester).controller!.text, 'changed@example.test');
    expect(passwordField(tester).controller!.text, isEmpty);
    expect(checked(tester, rememberKey), isTrue);
    await tap(tester, find.byKey(rememberKey));
    saved = (await tester.runAsync(KorlixLoginPreferences.load))!;
    expect(saved.rememberEmail, isFalse);
    expect(saved.email, isEmpty);
    final preferences = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(
      preferences.getString(KorlixLoginPreferences.storageKey),
      isNot(contains('changed@example.test')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(login());
    await tester.pumpAndSettle();
    expect(emailField(tester).controller!.text, isEmpty);
    expect(checked(tester, rememberKey), isFalse);
    await expectPasswordNotPersisted(tester);
  });

  testWidgets(
    'successful sign-in offers password save without remembering email',
    (tester) async {
      final sessions = <app.KorlixAuthSession>[];
      final requests = <http.Request>[];
      await mount(
        tester,
        login(
          client: MockClient((request) async {
            requests.add(request);
            return signedInResponse();
          }),
          onSignedIn: (session) async => sessions.add(session),
        ),
      );
      await enterCredentials(tester);
      tester.testTextInput.log.clear();
      await tap(tester, find.text('Sign in'));
      expect(sessions.single.email, testEmail);
      expect(requests.single.url.path, '/api/auth/signin');
      expect(jsonDecode(requests.single.body), {
        'email': testEmail,
        'password': testPassword,
      });
      expect(finishedAutofill(tester).where((save) => save), hasLength(1));
      final saved = (await tester.runAsync(KorlixLoginPreferences.load))!;
      expect(saved.rememberEmail, isFalse);
      expect(saved.email, isEmpty);
      await expectPasswordNotPersisted(tester);
    },
  );

  testWidgets(
    'password-save opt-out persists independently and cancels commit',
    (tester) async {
      await mount(tester, login());
      await enterCredentials(tester);
      await tap(tester, find.byKey(rememberKey));
      await tap(tester, find.byKey(passwordSaveKey));
      final saved = (await tester.runAsync(KorlixLoginPreferences.load))!;
      expect(saved.offerPasswordSave, isFalse);
      expect(saved.rememberEmail, isTrue);
      expect(saved.email, testEmail);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        login(client: MockClient((_) async => signedInResponse())),
      );
      await tester.pumpAndSettle();
      expect(checked(tester, passwordSaveKey), isFalse);
      expect(checked(tester, rememberKey), isTrue);
      expect(passwordField(tester).autofillHints, [AutofillHints.password]);
      await tester.enterText(find.byKey(passwordKey), testPassword);
      tester.testTextInput.log.clear();
      await tap(tester, find.text('Sign in'));
      expect(finishedAutofill(tester), contains(false));
      expect(finishedAutofill(tester), isNot(contains(true)));
      await expectPasswordNotPersisted(tester);
    },
  );

  testWidgets('failed login and form validation never offer a password save', (
    tester,
  ) async {
    var requests = 0;
    var signIns = 0;
    await mount(
      tester,
      login(
        client: MockClient((_) async {
          requests++;
          return http.Response('{"error":"Invalid credentials"}', 401);
        }),
        onSignedIn: (_) async => signIns++,
      ),
    );
    tester.testTextInput.log.clear();
    await tap(tester, find.text('Sign in'));
    expect(requests, 0);
    expect(find.text('Enter your email and password.'), findsOneWidget);
    await enterCredentials(tester);
    await tap(tester, find.text('Sign in'));
    expect(requests, 1);
    expect(signIns, 0);
    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(finishedAutofill(tester), isNot(contains(true)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(finishedAutofill(tester), contains(false));
    expect(finishedAutofill(tester), isNot(contains(true)));
    await expectPasswordNotPersisted(tester);
  });

  testWidgets(
    'signup uses new password hints and saves only after acceptance',
    (tester) async {
      var signIns = 0;
      String? path;
      await mount(
        tester,
        login(
          client: MockClient((request) async {
            path = request.url.path;
            return http.Response(
              '{"session":null,"user":{"email":"$testEmail"}}',
              200,
            );
          }),
          onSignedIn: (_) async => signIns++,
        ),
      );
      await enterCredentials(tester);
      tester.testTextInput.log.clear();
      await tap(tester, find.text('New here? Create account'));
      expect(finishedAutofill(tester), contains(false));
      expect(finishedAutofill(tester), isNot(contains(true)));
      expect(passwordField(tester).autofillHints, [AutofillHints.newPassword]);
      await enterCredentials(tester);
      tester.testTextInput.log.clear();
      await tap(tester, find.text('Create account'));
      expect(path, '/api/auth/signup');
      expect(signIns, 0);
      expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
      expect(finishedAutofill(tester).where((save) => save), hasLength(1));
      await tap(tester, find.text('Back to sign in'));
      expect(passwordField(tester).controller!.text, isEmpty);
      expect(passwordField(tester).autofillHints, [AutofillHints.password]);
      await expectPasswordNotPersisted(tester);
    },
  );

  testWidgets('leaving before a sign-in response never commits autofill', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var signIns = 0;
    await mount(
      tester,
      login(
        client: MockClient((_) => response.future),
        onSignedIn: (_) async => signIns++,
      ),
    );
    await enterCredentials(tester);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    response.complete(signedInResponse());
    await tester.pumpAndSettle();
    expect(signIns, 0);
    expect(finishedAutofill(tester), contains(false));
    expect(finishedAutofill(tester), isNot(contains(true)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late saved email never overwrites an email already being typed',
    (tester) async {
      final store = DelayedPreferenceStore({
        'flutter.${KorlixLoginPreferences.storageKey}': jsonEncode({
          'rememberEmail': true,
          'email': 'previous@example.test',
          'offerPasswordSave': false,
        }),
      });
      SharedPreferencesStorePlatform.instance = store;
      await mount(tester, login());
      await tester.enterText(find.byKey(emailKey), 'current@example.test');
      await tester.pump();
      store.ready.complete();
      await tester.pumpAndSettle();
      expect(emailField(tester).controller!.text, 'current@example.test');
      expect(checked(tester, rememberKey), isTrue);
      expect(checked(tester, passwordSaveKey), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
