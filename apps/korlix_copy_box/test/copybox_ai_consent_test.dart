import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_auth_core/auth/korlix_token_store.dart';
import 'package:korlix_auth_core/privacy/korlix_third_party_ai_consent.dart';
import 'package:korlix_copy_box/copybox_auth.dart';
import 'package:korlix_copy_box/copybox_home.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:korlix_copy_box/copybox_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _original = 'A synthetic meeting note for tomorrow.';
final _dialog = find.byKey(
  const ValueKey('korlix-third-party-ai-consent-dialog'),
);

String _fixtureToken() {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({
    'iss': 'https://auth.example.test',
    'sub': 'consent-fixture-user',
    'session_id': 'consent-fixture-login',
    'email': 'person@example.test',
    'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  })}.fixture';
}

class _Fixture {
  _Fixture(this.prefs, this.auth, this.requests);

  final SharedPreferences prefs;
  final CopyBoxAuthController auth;
  final List<http.Request> requests;

  String get consentKey =>
      KorlixThirdPartyAiConsent.accountStorageKey(auth.accountScope!);

  CopyBoxStore get store => CopyBoxStore(prefs, auth.accountScope!);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
            'appName': 'KORLIX COPY Box',
            'packageName': 'com.korlixdeveloper.copybox',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );
  });
  tearDown(() => KorlixThirdPartyAiConsent.setAccountScope(null));

  Future<_Fixture> mount(
    WidgetTester tester, {
    bool previousGrant = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/signin') {
        return http.Response(
          jsonEncode({
            'success': true,
            'user': {'id': 'consent-fixture-user'},
            'session': {
              'access_token': _fixtureToken(),
              'refresh_token': 'consent-fixture-refresh',
            },
          }),
          200,
        );
      }
      requests.add(request);
      expect(request.url.path, '/api/generate');
      return http.Response(jsonEncode({'content': 'A polished meeting note.'}), 200);
    });
    final auth = CopyBoxAuthController(
      client: client,
      backendUrl: 'https://backend.example.test',
      tokenStore: KorlixTokenStore(
        useSecureStorage: false,
        namespace: 'korlix_copybox',
      ),
    );
    addTearDown(() {
      auth.dispose();
      client.close();
    });
    expect(
      await auth.authenticate(
        email: 'person@example.test',
        password: 'fixture-password',
      ),
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    final fixture = _Fixture(prefs, auth, requests);
    fixture.store.load();
    await fixture.store.save([
      CopyBoxEntry(id: 'one', title: 'Meeting note', text: _original),
    ]);
    if (previousGrant) {
      await prefs.setString(
        fixture.consentKey,
        jsonEncode({
          'version': 'copybox.third-party-ai-consent.v3.history-disclosure',
          'grants': ['openAi:typedTextAndPrompts'],
        }),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: copyboxTheme(Brightness.light),
        home: CopyBoxHome(
          prefs: prefs,
          auth: auth,
          themeMode: ThemeMode.light,
          onThemeChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/copybox_mark.png'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  Future<void> click(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> refine(WidgetTester tester) async {
    await click(tester, find.byTooltip('Improve with AI'));
    await click(tester, find.text('Polish'));
  }

  testWidgets('old consent cannot send text and declining preserves local writing', (
    tester,
  ) async {
    final fixture = await mount(tester, previousGrant: true);
    await refine(tester);
    expect(_dialog, findsOneWidget);
    expect(find.text('Allow AI and model training?'), findsOneWidget);
    expect(find.text(copyBoxAiTrainingIntroduction), findsOneWidget);
    expect(find.text(copyBoxAiConsentDetails), findsOneWidget);
    expect(fixture.requests, isEmpty);

    await click(tester, find.text('Use local only'));
    expect(_dialog, findsNothing);
    expect(fixture.requests, isEmpty);
    expect(fixture.store.load().single.text, _original);
    expect(
      (jsonDecode(fixture.prefs.getString(fixture.consentKey)!) as Map)['version'],
      'copybox.third-party-ai-consent.v3.history-disclosure',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('text-one')));
    await tester.enterText(
      find.byKey(const ValueKey('text-one')),
      'Still writing locally after declining.',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(fixture.store.load().single.text, 'Still writing locally after declining.');
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewed consent gates AI and Settings revocation asks again', (
    tester,
  ) async {
    final fixture = await mount(tester, previousGrant: true);
    await refine(tester);
    expect(fixture.requests, isEmpty);
    await click(tester, find.text('Allow AI and training'));
    expect(fixture.requests, hasLength(1));
    final body = jsonDecode(fixture.requests.single.body) as Map;
    expect(body['prompt'], contains(_original));
    expect(body['source'], 'korlix_copybox');
    expect(body['purpose'], 'copy_box_rewrite');
    expect(
      (jsonDecode(fixture.prefs.getString(fixture.consentKey)!) as Map)['version'],
      copyBoxAiConsentNoticeVersion,
    );
    await click(tester, find.text('Keep original'));
    expect(fixture.store.load().single.text, _original);

    await refine(tester);
    expect(_dialog, findsNothing);
    expect(fixture.requests, hasLength(2));
    await click(tester, find.text('Keep original'));
    await click(tester, find.widgetWithText(NavigationDestination, 'Settings'));
    await click(tester, find.byKey(const Key('revoke-ai-consent')));
    expect(fixture.prefs.getString(fixture.consentKey), isNull);
    expect(fixture.requests, hasLength(2));
    await click(tester, find.widgetWithText(NavigationDestination, 'Workspace'));
    await refine(tester);
    expect(_dialog, findsOneWidget);
    expect(fixture.requests, hasLength(2));
    await click(tester, find.text('Use local only'));
    expect(fixture.requests, hasLength(2));
    expect(fixture.store.load().single.text, _original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('training notice scrolls and both choices fit a small large-text phone', (
    tester,
  ) async {
    final fixture = await mount(
      tester,
      size: const Size(360, 740),
      scale: 1.8,
    );
    await refine(tester);
    expect(_dialog, findsOneWidget);
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: _dialog,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollable, findsOneWidget);
    final state = tester.state<ScrollableState>(
      find.descendant(of: scrollable, matching: find.byType(Scrollable)),
    );
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    expect(find.text('Allow AI and training').hitTestable(), findsOneWidget);
    expect(find.text('Use local only').hitTestable(), findsOneWidget);
    await click(tester, find.text('Use local only'));
    expect(_dialog, findsNothing);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
