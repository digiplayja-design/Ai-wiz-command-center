import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/auth/korlix_october_welcome.dart';
import 'package:ai_wiz_command_center/auth/korlix_welcome_confirmation.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Widget auth({
  required DateTime date,
  http.Client? client,
  Future<void> Function(app.KorlixAuthSession)? onSignedIn,
  String theme = 'korlix_blue',
  double scale = 1,
  double keyboard = 0,
  GlobalKey? boundary,
}) => MaterialApp(
  theme: korlixBuildTheme(theme),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
        disableAnimations: true,
      ),
      child: RepaintBoundary(
        key: boundary,
        child: app.AuthScreen(
          key: ValueKey('$date/$theme/$scale/$keyboard'),
          seasonalDate: date,
          client: client ?? MockClient((_) async => http.Response('{}', 500)),
          onSignedIn: onSignedIn ?? (_) async {},
        ),
      ),
    ),
  ),
);

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> credentials(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(TextField).first);
  await tester.enterText(find.byType(TextField).first, 'member@example.test');
  await tester.ensureVisible(find.byType(TextField).last);
  await tester.enterText(find.byType(TextField).last, 'test-password');
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('October form keeps password visibility and sign-in working', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    app.KorlixAuthSession? session;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'session': {
            'access_token': 'offline-test-token',
            'refresh_token': 'offline-refresh',
          },
          'user': {'email': 'member@example.test'},
        }),
        200,
      );
    });
    await tester.pumpWidget(
      auth(
        date: DateTime(2026, 10, 3),
        client: client,
        onSignedIn: (value) async => session = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KorlixOctoberGreeting), findsOneWidget);
    expect(find.text('A little October magic'), findsOneWidget);
    await credentials(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    await tap(tester, find.byTooltip('Show password'));
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
    await tap(tester, find.text('Sign in'));
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/auth/signin');
    expect(jsonDecode(requests.single.body), {
      'email': 'member@example.test',
      'password': 'test-password',
    });
    expect(session?.email, 'member@example.test');
    expect(session?.accessToken, 'offline-test-token');
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'October signup still requires email confirmation before sign-in',
    (tester) async {
      viewport(tester, const Size(390, 844));
      var signIns = 0;
      String? path;
      await tester.pumpWidget(
        auth(
          date: DateTime(2026, 10, 31),
          theme: 'pure_white',
          client: MockClient((request) async {
            path = request.url.path;
            return http.Response(
              '{"session":null,"user":{"email":"member@example.test"}}',
              200,
            );
          }),
          onSignedIn: (_) async {
            signIns++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('New here? Create account'));
      expect(find.text('Create your Korlix AI account'), findsOneWidget);
      expect(find.byType(KorlixOctoberGreeting), findsOneWidget);
      await credentials(tester);
      await tap(tester, find.text('Create account'));
      expect(path, '/api/auth/signup');
      expect(signIns, 0);
      expect(find.byType(KorlixWelcomeConfirmation), findsOneWidget);
      await tap(tester, find.text('Back to sign in'));
      expect(find.byType(KorlixOctoberGreeting), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'member@example.test',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('normal login returns automatically on November 1', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(auth(date: DateTime(2026, 11, 1)));
    await tester.pumpAndSettle();
    expect(find.byType(KorlixOctoberGreeting), findsNothing);
    expect(find.textContaining('Halloween'), findsNothing);
    expect(find.text('Sign in to Korlix AI'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tap(tester, find.text('Sign in'));
    expect(find.text('Enter your email and password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'October login and signup stay reachable with large text and keyboard',
    (tester) async {
      viewport(tester, const Size(390, 844));
      for (final size in const [
        Size(320, 844),
        Size(390, 844),
        Size(1024, 1100),
      ]) {
        tester.view.physicalSize = size;
        for (final theme in ['korlix_blue', 'pure_white']) {
          await tester.pumpWidget(
            auth(
              date: DateTime(2026, 10, 3),
              theme: theme,
              scale: 1.6,
              keyboard: 300,
            ),
          );
          await tester.pumpAndSettle();
          await credentials(tester);
          await tester.ensureVisible(find.text('Sign in'));
          await tester.pumpAndSettle();
          expect(
            find.text('Sign in').hitTestable(),
            findsOneWidget,
            reason: '$size/$theme',
          );
          await tap(tester, find.text('New here? Create account'));
          expect(find.text('Create your Korlix AI account'), findsOneWidget);
          await tester.ensureVisible(find.text('Create account'));
          await tester.pumpAndSettle();
          expect(
            find.text('Create account').hitTestable(),
            findsOneWidget,
            reason: '$size/$theme',
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'member@example.test',
          );
          expect(tester.takeException(), isNull, reason: '$size/$theme');
        }
      }
    },
  );

  testWidgets('real October login visual review on phone and tablet', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final output = Platform.environment['KORLIX_AUTH_REVIEW'];
    if (output != null) {
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        final font = FontLoader('Roboto')
          ..addFont(
            File(
              'assets/fieldproof/Roboto-Regular.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await icons.load();
        await font.load();
      });
    }
    for (final review in [
      ('korlix_blue', 320.0, 844.0),
      ('korlix_blue', 390.0, 844.0),
      ('pure_white', 390.0, 844.0),
      ('korlix_blue', 1024.0, 1100.0),
    ]) {
      tester.view.physicalSize = Size(review.$2, review.$3);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        auth(date: DateTime(2026, 10, 3), theme: review.$1, boundary: boundary),
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
      expect(
        tester.takeException(),
        isNull,
        reason: '${review.$1}/${review.$2}',
      );
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/${review.$1}-${review.$2.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
