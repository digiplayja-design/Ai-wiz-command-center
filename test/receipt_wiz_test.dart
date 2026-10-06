import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/receipt_wiz/receipt_wiz_client.dart';
import 'package:ai_wiz_command_center/receipt_wiz/receipt_wiz_screen.dart';
import 'package:ai_wiz_command_center/receipt_wiz/receipt_wiz_review.dart';
import 'package:ai_wiz_command_center/receipt_wiz/receipt_wiz_style.dart';
import 'package:ai_wiz_command_center/bookkeeping/receipt_picker.dart';

const rid = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> details() => {
  'merchant': 'The Paper Shop',
  'date': '2026-10-06',
  'total': '28.40',
  'subtotal': '26.00',
  'tax': '2.40',
  'tip': '',
  'currency': 'USD',
  'category': 'Office supplies',
  'description': 'Printer paper and pens',
  'items': ['Printer paper', 'Pens'],
  'warnings': [],
};
Map<String, dynamic> receipt({bool reviewed = false}) => {
  'id': rid,
  'version': 1,
  'filename': 'receipt.png',
  'state': 'ready',
  'mime_type': 'image/png',
  'preview_size': 0,
  'details': details(),
  'reviewed': reviewed,
  'scan': {'state': 'ready'},
};

class FakeVault {
  Map<String, dynamic> saved = receipt();
  final requests = <http.Request>[];
  int uploads = 0, scans = 0;
  bool duplicate = false,
      failScan = false,
      failUpload = false,
      failSave = false;
  Completer<void>? saveGate;
  Map<String, dynamic>? scanResult;
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    Map<String, dynamic> data = {};
    if (path.endsWith('/export')) {
      data = {
        'csv': 'Merchant,Total\nThe Paper Shop,28.40',
        'filename': 'receipts.csv',
        'count': 1,
      };
    } else if (r.method == 'POST' && path.endsWith('/scan')) {
      scans++;
      if (failScan) {
        return http.Response(
          jsonEncode({'error': 'Scan temporarily unavailable.'}),
          503,
        );
      }
      data = {'receipt': scanResult ?? saved, 'integrations': {}};
    } else if (r.method == 'POST') {
      uploads++;
      if (failUpload) {
        return http.Response(jsonEncode({'error': 'Upload interrupted.'}), 503);
      }
      data = {'receipt': saved, 'reused': duplicate, 'integrations': {}};
    } else if (r.method == 'PUT') {
      await saveGate?.future;
      if (failSave) {
        return http.Response(
          jsonEncode({'error': 'Save interrupted. Try again.'}),
          503,
        );
      }
      final b = jsonDecode(r.body);
      saved = {
        ...saved,
        'details': b['details'],
        'version': (saved['version'] as int) + 1,
        'reviewed': b['reviewed'],
      };
      data = {'receipt': saved, 'integrations': {}};
    } else if (r.method == 'DELETE') {
      data = {'deleted': true};
    } else if (path.endsWith(rid)) {
      data = {'receipt': saved, 'integrations': {}};
    } else {
      data = {
        'receipts': [saved],
        'total': 1,
        'offset': 0,
        'used_bytes': 4000,
        'scans_today': 1,
        'credit_cost': 0,
        'categories': wizCategories,
        'scanning_available': true,
        'integrations': {
          'bookkeeping': [
            {'id': 'b', 'name': 'My business'},
          ],
          'tax_prep': [
            {'id': 't', 'year': 2026},
          ],
        },
      };
    }
    return http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  ReceiptWizClient client({
    Listenable? session,
    Map<String, String> Function()? headers,
  }) => ReceiptWizClient(
    backendBaseUrl: 'https://example.test',
    headersBuilder: headers ?? () => {'Authorization': 'fixture'},
    sessionChanges: session,
    client: MockClient(handle),
  );
}

String token(String id) =>
    'e30.${base64UrlEncode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': id, 'session_id': 'session-$id'})))}.fixture';
Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: const Key('receipt-export'), child: w!),
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {});
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'save, scan next and view inbox form one continuous capture flow',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault();
      var captures = 0;
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => true,
          capture: () async {
            captures++;
            return BookkeepingPickedReceipt(
              'receipt.pdf',
              Uint8List.fromList([37, 80, 68, 70]),
            );
          },
        ),
      );
      await tapVisible(tester, find.byKey(const Key('receipt-wiz-camera')));
      await tapVisible(tester, find.text('Save receipt'));
      expect(find.byKey(const Key('scan-next-receipt')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('save-reviewed-receipt')));
      expect(find.text('Receipt saved'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-next-receipt')));
      await tester.pumpAndSettle();
      expect(captures, 2);
      expect(f.uploads, 1);
      expect(find.text('Check your receipt'), findsOneWidget);
      await tapVisible(tester, find.text('Save receipt'));
      await tapVisible(tester, find.text('Save for later'));
      expect(find.text('Saved for later review'), findsOneWidget);
      expect(f.uploads, 2);
      await tester.tap(find.byKey(const Key('view-saved-receipts')));
      await tester.pumpAndSettle();
      expect(find.text('Your receipt inbox'), findsOneWidget);
      expect(find.byType(ReceiptWizReview), findsNothing);
      expect(find.byType(ReceiptWizPhotoReview), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed or pending saves cannot advance; existing receipts can scan next',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault()..failSave = true;
      var captures = 0;
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => true,
          inboxOnly: true,
          capture: () async {
            captures++;
            return null;
          },
        ),
      );
      await tapVisible(tester, find.text('The Paper Shop'));
      await tapVisible(tester, find.byKey(const Key('save-reviewed-receipt')));
      expect(find.byKey(const Key('scan-next-receipt')), findsNothing);
      expect(find.textContaining('Save interrupted.'), findsOneWidget);
      f.failSave = false;
      f.saveGate = Completer<void>();
      await tester.tap(find.byKey(const Key('save-reviewed-receipt')));
      await tester.pump();
      expect(find.byKey(const Key('scan-next-receipt')), findsNothing);
      await tester.pageBack();
      await tester.pump();
      expect(find.byType(ReceiptWizReview), findsOneWidget);
      f.saveGate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-next-receipt')));
      await tester.pumpAndSettle();
      expect(captures, 1);
      expect(find.text('Your receipt inbox'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'vault lock explains account access without asking for a password',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault();
      await mount(
        tester,
        ReceiptWizScreen(client: f.client(), ensureConsent: () async => true),
      );
      await tester.tap(find.text('PRIVATE VAULT'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('There is no separate vault password.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'rescan suggestions include editable items and notes; validation protects saved data',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault()..saved = receipt(reviewed: true);
      f.scanResult = {
        ...f.saved,
        'scan': {
          'state': 'ready',
          'suggestion': {
            ...details(),
            'items': ['Blue pens'],
            'warnings': ['Check the faded date.'],
          },
        },
      };
      final client = f.client();
      await mount(
        tester,
        ReceiptWizReview(
          client: client,
          receipt: f.saved,
          ensureConsent: () async => true,
        ),
      );
      await tapVisible(tester, find.text('Read receipt again'));
      await tapVisible(tester, find.text('More receipt details'));
      final items = find.byKey(const Key('receipt-items'));
      expect(tester.widget<TextFormField>(items).controller!.text, 'Blue pens');
      expect(find.text('Check the faded date.'), findsOneWidget);
      await tester.ensureVisible(items);
      await tester.enterText(items, 'Blue pens\nPrinter paper');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final date = find.byKey(const Key('receipt-date'));
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-02-30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('save-reviewed-receipt')));
      expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.text('Use a valid date: YYYY-MM-DD'), findsOneWidget);
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-10-06');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('save-reviewed-receipt')));
      expect(f.saved['details']['items'], ['Blue pens', 'Printer paper']);
      expect(f.saved['details']['warnings'], ['Check the faded date.']);
      expect(find.byKey(const Key('scan-next-receipt')), findsOneWidget);
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-10-07');
      await tester.pump();
      expect(find.byKey(const Key('scan-next-receipt')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    },
  );

  testWidgets('save confirmation fits narrow phones and enlarged text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (size, scale) in [
      (const Size(320, 568), 1.0),
      (const Size(390, 844), 1.8),
      (const Size(844, 390), 1.0),
    ]) {
      final f = FakeVault();
      final client = f.client();
      await mount(
        tester,
        ReceiptWizReview(
          client: client,
          receipt: f.saved,
          ensureConsent: () async => true,
        ),
        size: size,
        textScale: scale,
      );
      await tapVisible(tester, find.byKey(const Key('save-reviewed-receipt')));
      expect(find.byKey(const Key('scan-next-receipt')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    }
  });
  testWidgets(
    'free scanner and inbox fit phones, landscape, tablets and large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (size, scale) in [
        (const Size(320, 568), 1.0),
        (const Size(390, 844), 1.8),
        (const Size(844, 390), 1.0),
        (const Size(1024, 1366), 1.0),
      ]) {
        final f = FakeVault();
        await mount(
          tester,
          ReceiptWizScreen(client: f.client(), ensureConsent: () async => true),
          size: size,
          textScale: scale,
        );
        expect(find.byKey(const Key('receipt-wiz-camera')), findsOneWidget);
        expect(find.text('FREE · EVERY PLAN'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Receipts'));
        await tester.pumpAndSettle();
        expect(find.text('The Paper Shop'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'shared inbox keeps workspace/year scope and search filters on export',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault();
      String? exported;
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => true,
          inboxOnly: true,
          businessId: 'business',
          taxWorkspaceId: 'tax',
          initialYear: 2026,
          saveFile: (b, n, m, r) async {
            exported = utf8.decode(b);
          },
        ),
      );
      expect(f.requests.first.url.queryParameters['business_id'], 'business');
      expect(f.requests.first.url.queryParameters['year'], '2026');
      await tester.enterText(
        find.byKey(const Key('receipt-wiz-search')),
        'printer',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['query'], 'printer');
      final export = find.byTooltip('Export filtered receipts as CSV');
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(exported, contains('The Paper Shop'));
      expect(f.requests.last.url.queryParameters['tax_workspace_id'], 'tax');
      await tapVisible(tester, find.text('Reset filters'));
      expect(f.requests.last.url.queryParameters.containsKey('query'), isFalse);
      expect(f.requests.last.url.queryParameters['year'], '2026');
      expect(f.requests.last.url.queryParameters['business_id'], 'business');
    },
  );
  testWidgets(
    'description and category corrections persist as a reviewed receipt',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault();
      final client = f.client();
      await mount(
        tester,
        ReceiptWizReview(
          client: client,
          receipt: f.saved,
          ensureConsent: () async => true,
        ),
      );
      final description = find.byKey(const ValueKey('receipt-description'));
      await tester.ensureVisible(description);
      await tester.enterText(description, 'Supplies for the team');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('save-reviewed-receipt'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(f.saved['details']['description'], 'Supplies for the team');
      expect(f.saved['reviewed'], isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    },
  );
  testWidgets(
    'capture requires photo review; a duplicate never triggers a second AI read',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault()..duplicate = true;
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jY1sAAAAASUVORK5CYII=',
      );
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => true,
          capture: () async => BookkeepingPickedReceipt('receipt.png', image),
        ),
      );
      final camera = find.byKey(const Key('receipt-wiz-camera'));
      await tester.ensureVisible(camera);
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(f.uploads, 0);
      expect(find.text('Check your receipt'), findsOneWidget);
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(f.uploads, 1);
      expect(f.scans, 0);
      expect(
        find.text(
          'This exact receipt is already saved. We opened the existing copy.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'scan failure retains the original and offers editable manual details',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault()..failScan = true;
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => true,
          picker: () async => BookkeepingPickedReceipt(
            'receipt.pdf',
            Uint8List.fromList([37, 80, 68, 70]),
          ),
        ),
      );
      final upload = find.byKey(const Key('receipt-wiz-upload'));
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(f.uploads, 1);
      expect(f.scans, 1);
      expect(find.byKey(const ValueKey('receipt-description')), findsOneWidget);
      expect(find.textContaining('Your original is saved.'), findsOneWidget);
    },
  );
  testWidgets(
    'declining optional AI analysis still saves a free manual receipt',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FakeVault();
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(),
          ensureConsent: () async => false,
          picker: () async => BookkeepingPickedReceipt(
            'receipt.pdf',
            Uint8List.fromList([37, 80, 68, 70]),
          ),
        ),
      );
      final upload = find.byKey(const Key('receipt-wiz-upload'));
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(f.uploads, 1);
      expect(f.scans, 0);
      expect(
        find.text(
          'Original saved. Add the details below; automatic reading is optional.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'account switching clears receipt data and ignores late results',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ValueNotifier(0);
      var user = 'one';
      final f = FakeVault();
      await mount(
        tester,
        ReceiptWizScreen(
          client: f.client(
            session: session,
            headers: () => {'Authorization': 'Bearer ${token(user)}'},
          ),
          ensureConsent: () async => true,
          inboxOnly: true,
        ),
      );
      expect(find.text('The Paper Shop'), findsOneWidget);
      user = 'two';
      session.value++;
      await tester.pumpAndSettle();
      expect(find.text('The Paper Shop'), findsNothing);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'receipt review clears typed private details when the session changes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ValueNotifier(0);
      var user = 'one';
      final f = FakeVault();
      final client = f.client(
        session: session,
        headers: () => {'Authorization': 'Bearer ${token(user)}'},
      );
      await mount(
        tester,
        ReceiptWizReview(
          client: client,
          receipt: f.saved,
          ensureConsent: () async => true,
        ),
      );
      user = 'two';
      session.value++;
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
      session.dispose();
    },
  );
  test('client rejects a late response from the prior account', () async {
    var user = 'one';
    final session = ValueNotifier(0);
    final gate = Completer<http.Response>();
    final client = ReceiptWizClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': 'Bearer ${token(user)}'},
      sessionChanges: session,
      client: MockClient((_) => gate.future),
    );
    final pending = client.request('GET', '');
    final check = expectLater(pending, throwsA(isA<ReceiptWizException>()));
    await Future<void>.delayed(Duration.zero);
    user = 'two';
    session.value++;
    gate.complete(
      http.Response(
        jsonEncode({
          'receipts': [receipt()],
        }),
        200,
      ),
    );
    await check;
    client.dispose();
    session.dispose();
  });
  testWidgets('export receipt UI review', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final out = Platform.environment['RECEIPT_WIZ_PREVIEWS']!;
    await tester.runAsync(() async {
      await (FontLoader('Roboto')..addFont(
            File(
              'assets/fieldproof/Roboto-Regular.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
      if (sdk != null) {
        await (FontLoader('MaterialIcons')..addFont(
              File(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    });
    for (final (name, size) in [
      ('phone', const Size(390, 844)),
      ('tablet', const Size(1024, 1366)),
    ]) {
      final f = FakeVault();
      await mount(
        tester,
        ReceiptWizScreen(client: f.client(), ensureConsent: () async => true),
        size: size,
      );
      for (final tab in ['scan', 'inbox', 'saved']) {
        if (tab == 'inbox') {
          await tester.tap(find.text('Receipts'));
          await tester.pumpAndSettle();
        }
        if (tab == 'saved') {
          await tapVisible(tester, find.text('The Paper Shop'));
          await tapVisible(
            tester,
            find.byKey(const Key('save-reviewed-receipt')),
          );
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('receipt-export')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$out/$name-$tab.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  }, skip: Platform.environment['RECEIPT_WIZ_PREVIEWS'] == null);
}
