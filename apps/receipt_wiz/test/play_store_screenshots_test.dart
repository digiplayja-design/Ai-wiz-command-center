// Optional store-assets export of the real app UI with local sample data.
// No production service is contacted and no real account credentials are used.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_receipt_core/auth/korlix_http.dart' as korlix_http;
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:korlix_receipt_wiz/receipt_app.dart';
import 'package:korlix_receipt_wiz/receipt_auth.dart';
import 'package:korlix_receipt_core/bookkeeping/receipt_picker.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_batch.dart';

import '../../../packages/korlix_receipt_core/test/receipt_wiz_test.dart'
    show FakeVault;
import 'receipt_billing_test.dart' show Fixture;

import 'package:korlix_receipt_wiz/receipt_plan_screen.dart';

import 'receipt_auth_test.dart' show signedIn, response;

void main() {
  testWidgets('export actual app screens for Google Play', (tester) async {
    final destination = Platform.environment['RECEIPT_WIZ_PLAY_ASSETS']!;
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final auth = ReceiptAuthController(
      backendUrl: 'https://receipt-preview.example.test',
      client: MockClient((_) async => response(signedIn())),
      tokenStore: KorlixTokenStore(useSecureStorage: false),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('play-screenshot'),
        child: ReceiptWizApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/korlix_logo.png'),
        tester.element(find.byType(MaterialApp)),
      );
    });

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('play-screenshot')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$destination/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await capture('04-shared-account');
    final vault = FakeVault();
    korlix_http.configureClientFactory(() => MockClient(vault.handle));
    await auth.authenticate(email: 'sample@example.test', password: 'fixture');
    await tester.pumpAndSettle();
    await capture('01-scan');
    await tester.tap(find.text('Receipts'));
    await tester.pumpAndSettle();
    await capture('02-receipts');
    await tester.ensureVisible(find.text('The Paper Shop'));
    await tester.tap(find.text('The Paper Shop'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-merchant')));
    await capture('03-review');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final billing = Fixture();
    billing.store.monthlyPrice = r'$8.99';
    await billing.service.start();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('play-screenshot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFFFFAF5),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7145C7),
            ),
          ),
          home: ReceiptPlanScreen(billing: billing.service),
        ),
      ),
    );
    await capture('05-full-plan');
    await tester.pumpWidget(const SizedBox());
    billing.dispose();
    final batchClient = vault.client();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('play-screenshot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReceiptWizBatchImport(
            client: batchClient,
            files: [
              for (final name in ['Office supplies.pdf', 'Travel receipt.pdf'])
                BookkeepingPickedReceipt(
                  name,
                  Uint8List.fromList([37, 80, 68, 70]),
                ),
            ],
            ensureConsent: () async => false,
            scanAvailable: true,
          ),
        ),
      ),
    );
    await capture('06-file-import');
    await tester.pumpWidget(const SizedBox());
    batchClient.dispose();
    korlix_http.configureClientFactory(null);
  }, skip: Platform.environment['RECEIPT_WIZ_PLAY_ASSETS'] == null);
}
