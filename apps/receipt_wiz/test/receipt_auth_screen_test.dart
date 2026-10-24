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
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:korlix_receipt_wiz/receipt_app.dart';
import 'package:korlix_receipt_wiz/receipt_auth.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (Platform.environment['RECEIPT_WIZ_PREVIEWS'] != null && sdk != null) {
      await tester.runAsync(() async {
        for (final (family, file) in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('Ahem', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(family)..addFont(
                File('$sdk/bin/cache/artifacts/material_fonts/$file')
                    .readAsBytes()
                    .then(ByteData.sublistView),
              ))
              .load();
        }
      });
    }
    final client = MockClient(handler ?? (_) async => http.Response('{}', 200));
    addTearDown(client.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: ReceiptWizApp(
          auth: ReceiptAuthController(
            client: client,
            tokenStore: KorlixTokenStore(useSecureStorage: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/korlix_logo.png'),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> signup(WidgetTester tester, {String age = '18 or older'}) async {
    await tap(tester, find.text('New to KORLIX? Create free account'));
    await tester.enterText(
      find.byKey(const Key('receipt-email')),
      'same@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('receipt-password-true')),
      'new-password',
    );
    await tap(tester, find.byKey(const Key('receipt-age')));
    await tester.tap(find.text(age).last);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('receipt-policies')));
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final path = Platform.environment['RECEIPT_WIZ_PREVIEWS'];
    if (path == null) return;
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'duplicate signup returns to sign-in with email and no attempted new password',
    (tester) async {
      await mount(
        tester,
        handler: (_) async => http.Response(
          jsonEncode({
            'code': 'KORLIX_ACCOUNT_EXISTS',
            'error': existingKorlixAccountMessage,
          }),
          409,
        ),
      );
      await preview(tester, 'sign-in');
      await signup(tester);
      await tap(tester, find.byKey(const Key('receipt-auth-submit')));
      expect(find.byKey(const Key('existing-account-dialog')), findsOneWidget);
      expect(find.text(existingKorlixAccountMessage), findsOneWidget);
      await preview(tester, 'existing-account');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('existing-account-dialog')),
          matching: find.widgetWithText(FilledButton, 'Sign In'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-email')))
            .controller!
            .text,
        'same@example.test',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('receipt-password-false')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('existing-account-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate-account recovery sends reset for the retained email', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mount(
      tester,
      handler: (r) async {
        requests.add(r);
        return r.url.path.endsWith('signup')
            ? http.Response(
                jsonEncode({
                  'code': 'KORLIX_ACCOUNT_EXISTS',
                  'error': 'Account exists',
                }),
                409,
              )
            : http.Response('{"success":true}', 200);
      },
    );
    await signup(tester);
    await tap(tester, find.byKey(const Key('receipt-auth-submit')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('existing-account-dialog')),
        matching: find.text('Forgot Password?'),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.last.url.path, '/api/auth/password-reset');
    expect(jsonDecode(requests.last.body)['email'], 'same@example.test');
    expect(
      find.textContaining('The new password will also work in KORLIX AI.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('underage registration is blocked before contacting auth', (
    tester,
  ) async {
    int requests = 0;
    await mount(
      tester,
      handler: (_) async {
        requests++;
        return http.Response('{}', 200);
      },
    );
    await signup(tester, age: 'Under 16');
    await tap(tester, find.byKey(const Key('receipt-auth-submit')));
    expect(requests, 0);
    expect(
      find.text('You must be at least 16 to create a KORLIX account.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'new signup explains email verification and return to the standalone app',
    (tester) async {
      await mount(
        tester,
        handler: (_) async => http.Response('{"session":null}', 200),
      );
      await signup(tester);
      await tap(tester, find.byKey(const Key('receipt-auth-submit')));
      expect(
        find.textContaining('Then return to Receipt Wiz and sign in.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('receipt-password-false')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (820.0, 2.0)]) {
    testWidgets('registration fits width $width with text scale $scale', (
      tester,
    ) async {
      await mount(tester, size: Size(width, 844), scale: scale);
      await signup(tester);
      await tap(tester, find.byKey(const Key('receipt-auth-submit')));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sign-in controls have accessible labels and touch targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, size: const Size(390, 1200));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });
}
