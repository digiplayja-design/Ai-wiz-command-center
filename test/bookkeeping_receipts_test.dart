import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_forms.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_receipts.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/receipt_picker.dart';
import 'package:ai_wiz_command_center/bookkeeping/receipt_viewer.dart';
import 'bookkeeping_test.dart' as f;

const rid = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> receipt() => {
  'id': rid,
  'filename': 'supplies.pdf',
  'mime_type': 'application/pdf',
  'byte_size': 1024,
  'preview_size': 0,
  'state': 'ready',
  'link': null,
  'retained': false,
};
Map<String, dynamic> suggestions([String currency = 'USD']) => {
  'vendor': 'Fixture Store',
  'document_date': '2027-01-15',
  'total': '12.34',
  'currency': currency,
  'document_type': 'receipt',
  'payment_status': 'paid',
  'warnings': [],
};
Map<String, dynamic> inbox([List<Map<String, dynamic>>? rows]) => {
  'receipts': rows ?? [receipt()],
  'total': rows?.length ?? 1,
  'used_bytes': 1024,
  'scanning': {'available': true, 'credit_cost': 1},
};
http.Response baseReply(http.Request r) {
  if (r.url.path.endsWith('/businesses')) {
    return f.reply({
      'businesses': [f.business()],
    });
  }
  if (r.url.path.endsWith('/overview')) return f.reply(f.overview());
  if (r.url.path.endsWith('/scan')) return f.reply({'scan': null});
  return f.reply(inbox());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final entry in {
        'MaterialIcons': 'MaterialIcons-Regular.otf',
        'Roboto': 'Roboto-Regular.ttf',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${entry.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  test(
    'authenticated multipart upload keeps retry key and original bytes',
    () async {
      final seen = <http.Request>[];
      final c = f.client((r) {
        seen.add(r);
        return f.reply({'receipt': receipt()});
      });
      final bytes = Uint8List.fromList([0, 1, 2, 255]);
      await c.uploadReceipt(f.businessId, rid, 'original.pdf', bytes);
      await c.uploadReceipt(f.businessId, rid, 'original.pdf', bytes);
      expect(seen.length, 2);
      for (final r in seen) {
        expect(r.headers['authorization'], 'Bearer fixture');
        expect(r.headers['x-receipt-request-key'], rid);
        expect(r.headers['content-type'], startsWith('multipart/form-data'));
        expect(r.bodyBytes, containsAllInOrder(bytes));
        expect(latin1.decode(r.bodyBytes), contains('original.pdf'));
      }
      c.dispose();
    },
  );
  test(
    'binary downloads and upload responses are discarded after session replacement',
    () async {
      for (final upload in [false, true]) {
        final notifier = ValueNotifier(0);
        String identity = f.token('owner');
        final response = Completer<http.Response>();
        final c = BookkeepingClient(
          backendBaseUrl: 'https://example.com',
          headersBuilder: () => {'Authorization': 'Bearer $identity'},
          sessionChanges: notifier,
          client: MockClient((_) => response.future),
        );
        final pending = upload
            ? c.uploadReceipt(
                f.businessId,
                rid,
                'original.pdf',
                Uint8List.fromList([1]),
              )
            : c.receiptBytes(f.businessId, rid);
        final check = expectLater(
          pending,
          throwsA(isA<BookkeepingException>()),
        );
        identity = f.token('other');
        notifier.value++;
        response.complete(
          upload
              ? f.reply({'receipt': receipt()})
              : http.Response.bytes([1, 2], 200),
        );
        await check;
        c.dispose();
        notifier.dispose();
      }
    },
  );
  testWidgets(
    'receipt entry requires explicit review and atomically submits attachment',
    (t) async {
      await f.size(t, const Size(900, 1000));
      Map<String, dynamic>? body;
      String? path;
      final c = f.client((r) {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        path = r.url.path;
        return f.reply({'entry': f.savedEntry()});
      });
      await f.mountDialog(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: f.businessId,
          categories: f.categories(),
          kind: 'expense',
          receipt: receipt(),
          suggestions: suggestions(),
          cashAccounts: const [
            {'code': '1000', 'name': 'Recorded cash control'},
            {'code': '1001', 'name': 'Operating bank'},
          ],
        ),
      );
      expect(
        t.widget<TextField>(f.field('Amount (USD)')).controller!.text,
        '12.34',
      );
      await f.tap(t, 'Recorded cash control (1000)');
      await f.tap(t, 'Operating bank (1001)');
      await f.fill(t, 'Business purpose', 'Office supplies');
      await f.tap(t, 'Review entry');
      expect(
        find.text('Check the receipt details before reviewing this entry.'),
        findsOneWidget,
      );
      expect(body, isNull);
      await f.tap(
        t,
        'I checked the receipt, amount, currency and date paid / received.',
      );
      await f.tap(t, 'Review entry');
      expect(find.text('Attached original: supplies.pdf'), findsOneWidget);
      await f.tap(t, 'Confirm and save');
      expect(path, endsWith('/receipts/$rid/entries'));
      expect(body!['receipt_reviewed'], true);
      expect(body!['amount'], '12.34');
      expect(body!['cash_account'], '1001');
      c.dispose();
    },
  );
  testWidgets('foreign or unknown currency never prefills a USD amount', (
    t,
  ) async {
    final c = f.client(baseReply);
    for (final currency in ['CAD', 'unknown']) {
      await f.mountDialog(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: f.businessId,
          categories: f.categories(),
          kind: 'expense',
          receipt: receipt(),
          suggestions: suggestions(currency),
        ),
      );
      expect(
        t.widget<TextField>(f.field('Amount (USD)')).controller!.text,
        isEmpty,
      );
      await f.tap(t, 'Close');
    }
    c.dispose();
  });
  testWidgets(
    'file selection uploads only on confirmation and keeps original request on retry',
    (t) async {
      await f.size(t, const Size(1000, 1000));
      int uploads = 0;
      final keys = <String>[];
      final c = f.client((r) {
        if (r.method == 'POST') {
          uploads++;
          keys.add(r.headers['x-receipt-request-key']!);
          return uploads == 1
              ? f.reply({'error': 'Try again'}, 503)
              : f.reply({'receipt': receipt()}, 201);
        }
        return f.reply(inbox([]));
      });
      await f.mountDialog(
        t,
        BookkeepingReceipts(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture business',
          categories: f.categories(),
          picker: ({bool camera = false}) async => BookkeepingPickedReceipt(
            'supplies.pdf',
            Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await f.tap(t, 'Choose file');
      expect(uploads, 0);
      await f.tap(t, 'Upload original');
      expect(uploads, 1);
      expect(
        find.textContaining('Retry upload keeps the same request.'),
        findsOneWidget,
      );
      await f.tap(t, 'Upload original');
      expect(uploads, 2);
      expect(keys[0], keys[1]);
      expect(find.text('Upload original'), findsNothing);
      c.dispose();
    },
  );
  testWidgets(
    'scan requires confirmation, refreshes a lost response and never posts an entry',
    (t) async {
      await f.size(t, const Size(900, 1000));
      int scans = 0, entries = 0;
      Map<String, dynamic>? latest;
      final c = f.client((r) {
        if (r.method == 'POST' && r.url.path.endsWith('/scan')) {
          scans++;
          latest = {'state': 'ready', 'suggestions': suggestions()};
          return f.reply({'error': 'Response interrupted'}, 503);
        }
        if (r.method == 'POST') {
          entries++;
        }
        return f.reply({'scan': latest});
      });
      await f.mountDialog(
        t,
        BookkeepingReceiptViewer(
          client: c,
          businessId: f.businessId,
          receipt: receipt(),
          scanning: const {'available': true},
          canCreate: true,
        ),
      );
      await f.tap(t, 'Scan receipt');
      expect(scans, 0);
      await f.tap(t, 'Cancel');
      expect(scans, 0);
      await f.tap(t, 'Scan receipt');
      await f.tap(t, 'Scan now');
      expect(scans, 1);
      expect(entries, 0);
      expect(find.text('Vendor: Fixture Store'), findsOneWidget);
      await f.tap(t, 'Refresh scan status');
      expect(scans, 1);
      c.dispose();
    },
  );
  testWidgets('PDF download exports exact original bytes and filename', (
    t,
  ) async {
    List<int>? downloaded;
    String? filename;
    final c = f.client(
      (r) => r.url.path.endsWith('/file')
          ? http.Response.bytes([37, 80, 68, 70, 1], 200)
          : f.reply({'scan': null}),
    );
    await f.mountDialog(
      t,
      BookkeepingReceiptViewer(
        client: c,
        businessId: f.businessId,
        receipt: receipt(),
        scanning: const {'available': false},
        onDownload: (b, n) async {
          downloaded = b;
          filename = n;
        },
      ),
    );
    await f.tap(t, 'Download original');
    expect(downloaded, [37, 80, 68, 70, 1]);
    expect(filename, 'supplies.pdf');
    c.dispose();
  });
  testWidgets(
    'attachment has a separate confirmation and correction requires a reason',
    (t) async {
      await f.size(t, const Size(1000, 1000));
      Map<String, dynamic>? body;
      int writes = 0;
      bool linked = false;
      final c = f.client((r) {
        if (r.method == 'POST') {
          writes++;
          body = jsonDecode(r.body) as Map<String, dynamic>;
          linked = r.url.path.endsWith('/link');
          return f.reply({'ok': true});
        }
        if (r.url.path.endsWith('/overview')) return f.reply(f.overview());
        return f.reply(
          inbox([
            {
              ...receipt(),
              if (linked)
                'link': {
                  'id': rid,
                  'entry_id': f.savedEntry()['id'],
                  'unlinked_at': null,
                },
              'retained': linked,
            },
          ]),
        );
      });
      await f.mountDialog(
        t,
        BookkeepingReceipts(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture',
          categories: f.categories(),
        ),
      );
      await f.tap(t, 'Link existing entry');
      await f.tap(t, r'$1,250.00 · income');
      expect(writes, 0);
      await f.tap(t, 'Confirm attachment');
      expect(writes, 1);
      expect(body!['confirmed'], true);
      expect(find.text('Delete unused'), findsNothing);
      await f.tap(t, 'Correct link');
      await f.tap(t, 'Confirm correction');
      expect(writes, 1);
      await f.fill(t, 'Reason for correction', 'Wrong entry');
      await f.tap(t, 'Confirm correction');
      expect(writes, 2);
      expect(body!['reason'], 'Wrong entry');
      c.dispose();
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('receipt inbox and viewer fit width $width', (t) async {
      await f.size(t, Size(width, 900));
      final c = f.client(baseReply);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: BookkeepingReceipts(
                client: c,
                businessId: f.businessId,
                businessName: 'Harbor Creative LLC',
                categories: f.categories(),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'k199-inbox-${width.toInt()}', key);
      await f.tap(t, 'View / scan');
      expect(t.takeException(), isNull);
      await f.tap(t, 'Scan receipt');
      expect(t.takeException(), isNull);
      c.dispose();
    });
  }
  testWidgets(
    'logout closes nested receipt confirmation and clears owner data',
    (t) async {
      await f.size(t, const Size(1000, 1000));
      final changes = ValueNotifier(0);
      String identity = f.token('owner');
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'Bearer $identity'},
        sessionChanges: changes,
        client: MockClient((r) async => baseReply(r)),
      );
      await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
      await t.pumpAndSettle();
      await f.tap(t, 'Receipt inbox');
      await f.tap(t, 'View / scan');
      await f.tap(t, 'Scan receipt');
      expect(find.text('Scan receipt with AI?'), findsOneWidget);
      identity = f.token('other');
      changes.value++;
      await t.pumpAndSettle();
      expect(find.textContaining('Your session changed.'), findsOneWidget);
      expect(find.text('Scan receipt with AI?'), findsNothing);
      expect(find.text('supplies.pdf'), findsNothing);
      expect(t.takeException(), isNull);
      c.dispose();
      changes.dispose();
    },
  );
}
