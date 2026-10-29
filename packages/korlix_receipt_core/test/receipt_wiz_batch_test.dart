import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_receipt_core/bookkeeping/receipt_picker.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_batch.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_client.dart';

BookkeepingPickedReceipt file(String name) =>
    BookkeepingPickedReceipt(name, Uint8List.fromList([37, 80, 68, 70]));
http.Response response(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);
Map<String, dynamic> saved(String id) => {
  'id': id,
  'state': 'ready',
  'scan': {'state': 'ready'},
};

void main() {
  test(
    'selection limits reject unsupported, empty, oversized and excessive files',
    () {
      expect(
        () => validateReceiptBatch([file('receipt.exe')]),
        throwsFormatException,
      );
      expect(
        () => validateReceiptBatch([
          BookkeepingPickedReceipt('r.pdf', Uint8List(0)),
        ]),
        throwsFormatException,
      );
      expect(
        () => validateReceiptBatch([
          BookkeepingPickedReceipt('r.pdf', Uint8List(receiptFileLimit + 1)),
        ]),
        throwsFormatException,
      );
      expect(
        () => validateReceiptBatch(List.generate(11, (i) => file('$i.pdf'))),
        throwsFormatException,
      );
      expect(
        () => validateReceiptBatch(
          List.generate(
            6,
            (i) =>
                BookkeepingPickedReceipt('$i.pdf', Uint8List(receiptFileLimit)),
          ),
        ),
        throwsFormatException,
      );
      validateReceiptBatch([file('RECEIPT.PDF'), file('photo.JPEG')]);
    },
  );

  test(
    'failed upload does not stop batch; retry reuses its key and skips saved files',
    () async {
      final keys = <String>[];
      var fail = true;
      final client = ReceiptWizClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'fixture'},
        client: MockClient((r) async {
          keys.add(r.headers['x-receipt-request-key']!);
          if (fail && keys.length == 1) {
            return response({'error': 'Offline'}, 503);
          }
          return response({'receipt': saved('receipt'), 'reused': false});
        }),
      );
      final queue = ReceiptImportQueue(
        client: client,
        files: [file('one.pdf'), file('two.pdf')],
      );
      addTearDown(() {
        queue.dispose();
        client.dispose();
      });
      await queue.start(scan: false);
      expect(queue.savedCount, 1);
      expect(queue.items.first.file, isNotNull);
      expect(queue.items.last.file, isNull);
      fail = false;
      await queue.start(scan: false);
      expect(queue.savedCount, 2);
      expect(keys.length, 3);
      expect(keys[2], keys[0]);
      expect(keys[0], isNot(keys[1]));
    },
  );

  test(
    'duplicates do not scan; scan failure keeps originals without reupload',
    () async {
      var uploads = 0, scans = 0;
      final client = ReceiptWizClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'fixture'},
        client: MockClient((r) async {
          if (r.url.path.endsWith('/scan')) {
            scans++;
            return response({'error': 'Scan limit reached'}, 429);
          }
          uploads++;
          return response({
            'receipt': saved('$uploads'),
            'reused': uploads == 1,
          });
        }),
      );
      final queue = ReceiptImportQueue(
        client: client,
        files: [file('one.pdf'), file('two.pdf')],
      );
      addTearDown(() {
        queue.dispose();
        client.dispose();
      });
      await queue.start(scan: true);
      expect(queue.savedCount, 2);
      expect(scans, 1);
      expect(queue.items.last.status, contains('Original saved'));
      await queue.start(scan: true);
      expect(uploads, 2);
      expect(scans, 1);
    },
  );

  test(
    'stop waits for current original and leaves remaining files retryable',
    () async {
      final gate = Completer<http.Response>();
      var uploads = 0;
      final client = ReceiptWizClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'fixture'},
        client: MockClient((r) {
          uploads++;
          return gate.future;
        }),
      );
      final queue = ReceiptImportQueue(
        client: client,
        files: [file('one.pdf'), file('two.pdf')],
      );
      addTearDown(() {
        queue.dispose();
        client.dispose();
      });
      final done = queue.start(scan: false);
      await Future<void>.delayed(Duration.zero);
      queue.stop();
      gate.complete(response({'receipt': saved('one')}));
      await done;
      expect(uploads, 1);
      expect(queue.savedCount, 1);
      expect(queue.items.last.file, isNotNull);
    },
  );

  test(
    'account change clears file names and bytes and blocks later uploads',
    () async {
      final gate = Completer<http.Response>();
      final session = ValueNotifier(0);
      var current = 'one', uploads = 0;
      String token() =>
          'e30.${base64UrlEncode(utf8.encode(jsonEncode({'iss': 'test', 'sub': current, 'session_id': current})))}.signature';
      final client = ReceiptWizClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer ${token()}'},
        sessionChanges: session,
        client: MockClient((r) {
          uploads++;
          return gate.future;
        }),
      );
      final queue = ReceiptImportQueue(
        client: client,
        files: [file('private.pdf'), file('two.pdf')],
      );
      addTearDown(() {
        queue.dispose();
        client.dispose();
        session.dispose();
      });
      final done = queue.start(scan: true);
      await Future<void>.delayed(Duration.zero);
      current = 'two';
      session.value++;
      gate.complete(response({'receipt': saved('one')}));
      await done;
      expect(queue.locked, isTrue);
      expect(queue.items, isEmpty);
      expect(queue.running, isFalse);
      expect(uploads, 1);
    },
  );

  testWidgets('batch waits for confirmation; consent denial saves without AI', (
    tester,
  ) async {
    var uploads = 0, scans = 0, consent = 0;
    final client = ReceiptWizClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': 'fixture'},
      client: MockClient((r) async {
        if (r.url.path.endsWith('/scan')) {
          scans++;
        } else {
          uploads++;
        }
        return response({'receipt': saved('one')});
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptWizBatchImport(
          client: client,
          files: [file('one.pdf'), file('two.pdf')],
          scanAvailable: true,
          ensureConsent: () async {
            consent++;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(uploads, 0);
    await tester.tap(find.byKey(const Key('receipt-batch-start')));
    await tester.pumpAndSettle();
    expect(consent, 1);
    expect(uploads, 2);
    expect(scans, 0);
    expect(find.text('2 of 2 originals saved'), findsOneWidget);
    expect(find.text('View receipts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
