import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_forms.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_receipts.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_guide.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_ui.dart';
import 'package:ai_wiz_command_center/bookkeeping/file_reader.dart';
import 'package:ai_wiz_command_center/bookkeeping/receipt_picker.dart';
import 'package:ai_wiz_command_center/bookkeeping/receipt_viewer.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_history.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_preview.dart';
import 'bookkeeping_test.dart' as f;
import 'bookkeeping_receipts_test.dart' as receipts;
import 'bookkeeping_ledger_test.dart' as ledger;

const statementId = '44444444-4444-4444-8444-444444444444';
final previewKey = GlobalKey();
final revision = List.filled(64, 'a').join();
Map<String, dynamic> candidate(int n) => {
  'entry_id': 'record-$n',
  'date': '2027-01-15',
  'kind': 'income',
  'source': 'cash',
  'amount_cents': '10000',
  'purpose': 'Recorded purpose $n',
};
Map<String, dynamic> statement({bool paging = true}) => {
  'statement': {
    'id': statementId,
    'statement_year': 2027,
    'cash_account': '1000',
    'rows': [
      {
        'line': 2,
        'date': '2027-01-15',
        'description': 'Bank deposit',
        'amount_cents': '10000',
        'status': 'ambiguous',
        'candidates': List.generate(5, (i) => candidate(i + 1)),
        if (paging) ...{
          'candidate_total': 13,
          'candidate_next_offset': 5,
          'candidate_revision': revision,
        },
      },
    ],
  },
  'decisions': <Map<String, dynamic>>[],
};
Map<String, dynamic> statementList() => {
  'statements': [
    {
      'id': statementId,
      'statement_year': 2027,
      'row_count': 1,
      'cash_account': '1000',
    },
  ],
};
Future<void> mountLargeText(
  WidgetTester t,
  Widget child, {
  double width = 390,
}) async {
  await f.size(t, Size(width, 1000));
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepaintBoundary(
        key: previewKey,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showDialog<void>(
              context: c,
              barrierDismissible: false,
              builder: (_) => child,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await f.tap(t, 'Open');
}

Future<void> tapPartial(WidgetTester t, String text) async {
  final finder = find.textContaining(text).last;
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(f.loadBookkeepingFonts);
  test(
    'complete file reader rejects partial, empty, extra and oversized bytes and copies reused buffers',
    () async {
      Future<Uint8List> read(
        int size, {
        Uint8List? bytes,
        Stream<List<int>>? stream,
        int limit = 8,
      }) => readBookkeepingFile(
        advertisedSize: size,
        maxBytes: limit,
        limitMessage: 'File exceeds limit',
        bytes: bytes,
        stream: stream,
      );
      for (final pair in [
        (0, <int>[]),
        (4, [1, 2]),
        (2, [1, 2, 3]),
        (9, List.filled(9, 1)),
      ]) {
        await expectLater(
          read(pair.$1, bytes: Uint8List.fromList(pair.$2)),
          throwsA(isA<BookkeepingException>()),
        );
      }
      Stream<List<int>> reused() async* {
        final buffer = Uint8List.fromList([1, 2]);
        yield buffer;
        buffer.setAll(0, [3, 4]);
        yield buffer;
      }

      expect(await read(4, stream: reused()), [1, 2, 3, 4]);
      await expectLater(
        read(4, stream: Stream.value([1, 2])),
        throwsA(isA<BookkeepingException>()),
      );
      await expectLater(
        read(2, stream: Stream.value([1, 2, 3])),
        throwsA(isA<BookkeepingException>()),
      );
      await expectLater(
        read(2, stream: Stream.error(Exception('Cannot read'))),
        throwsA(isA<BookkeepingException>()),
      );
    },
  );
  test(
    'statement header validation preserves embedded BOM and matches server uniqueness and length',
    () {
      expect(statementHeaders('\uFEFFDate,Me\uFEFFmo,Amount\n2027-01-01,x,1'), [
        'Date',
        'Me\uFEFFmo',
        'Amount',
      ]);
      for (final csv in [
        'Date,date,Amount\n1,x,1',
        'Date,${List.filled(81, 'x').join()},Amount\n1,x,1',
      ]) {
        expect(() => statementHeaders(csv), throwsFormatException);
      }
    },
  );
  test(
    'denied response headers revoke concurrent records before a stalled body is read',
    () async {
      final body = StreamController<List<int>>(),
          delayed = Completer<http.StreamedResponse>();
      var sends = 0, denied = 0;
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient.streaming((request, _) async {
          sends++;
          if (request.url.path.endsWith('/denied')) {
            return http.StreamedResponse(body.stream, 403);
          }
          return delayed.future;
        }),
      );
      addTearDown(c.dispose);
      c.addAccessDeniedListener(() => denied++);
      final pending = c.request('GET', '/pending');
      final pendingCheck = expectLater(
        pending,
        throwsA(isA<BookkeepingException>()),
      );
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<BookkeepingException>()),
      );
      expect(denied, 1);
      delayed.complete(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"private":"must not escape"}')),
          200,
        ),
      );
      await pendingCheck;
      await expectLater(
        c.request('GET', '/again'),
        throwsA(isA<BookkeepingException>()),
      );
      expect(sends, 2);
      await body.close();
    },
  );
  testWidgets('expired headers cannot revoke a successful retry', (t) async {
    final old = Completer<http.StreamedResponse>();
    var sends = 0, denials = 0, cancelled = false;
    final oldBody = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final c = BookkeepingClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {'Authorization': 'Bearer fixture'},
      client: MockClient.streaming(
        (_, _) async => ++sends == 1
            ? old.future
            : http.StreamedResponse(
                Stream.value(utf8.encode('{"ok":true}')),
                200,
              ),
      ),
    );
    c.addAccessDeniedListener(() => denials++);
    addTearDown(c.dispose);
    final first = expectLater(
      c.request('GET', '/records'),
      throwsA(isA<BookkeepingException>()),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 101));
    await first;
    final retry = c.request('GET', '/records');
    await t.pump();
    expect((await retry)['ok'], true);
    old.complete(http.StreamedResponse(oldBody.stream, 401));
    await t.pump();
    expect(denials, 0);
    expect(cancelled, true);
    unawaited(oldBody.close());
  });
  testWidgets(
    'owner reaches twelfth candidate on narrow large-text screen and retries exact reviewed record',
    (t) async {
      final offsets = <int>[], writes = <String>[];
      var pageFails = true;
      final c = f.client((r) {
        if (r.method == 'POST') {
          writes.add(r.body);
          return writes.length == 1
              ? f.reply({'error': 'Response lost'}, 503)
              : f.reply({
                  'decision': {'id': 'saved'},
                }, 201);
        }
        if (r.url.path.endsWith('/candidates')) {
          final n = int.parse(r.url.queryParameters['offset']!);
          offsets.add(n);
          if (pageFails) {
            pageFails = false;
            return f.reply({'error': 'Connection interrupted'}, 503);
          }
          return f.reply({
            'statement_id': statementId,
            'cash_account': '1000',
            'row_line': 2,
            'revision': revision,
            'offset': n,
            'total': 13,
            'next_offset': n == 5 ? 10 : null,
            'candidates': List.generate(
              n == 5 ? 5 : 3,
              (i) => candidate(n + i + 1),
            ),
          });
        }
        return f.reply(
          r.url.path.endsWith('/statements') ? statementList() : statement(),
        );
      });
      addTearDown(c.dispose);
      await mountLargeText(
        t,
        BookkeepingStatementHistory(client: c, businessId: f.businessId),
      );
      await f.tap(t, '2027 · 1 rows · cash account 1000');
      await f.tap(t, 'Show more candidates');
      expect(find.text('5 of 13 candidates loaded'), findsOneWidget);
      await f.tap(t, 'Show more candidates');
      await f.tap(t, 'Show more candidates');
      expect(offsets, [5, 5, 10]);
      expect(find.text('13 of 13 candidates loaded'), findsOneWidget);
      await tapPartial(t, 'Review match: Recorded purpose 12');
      expect(find.textContaining('Record ID: record-12'), findsOneWidget);
      await f.screenshot(
        t,
        'rebuilt-candidate-confirmation-390-large-text',
        previewKey,
      );
      expect(writes, isEmpty);
      await f.tap(t, 'Cancel');
      expect(writes, isEmpty);
      await tapPartial(t, 'Review match: Recorded purpose 12');
      await f.tap(t, 'Confirm decision');
      expect(find.textContaining('Recorded purpose 12'), findsNothing);
      await f.tap(t, 'Retry same decision');
      expect(writes.length, 2);
      expect(writes[0], writes[1]);
      expect(jsonDecode(writes.first)['entry_id'], 'record-12');
      expect(t.takeException(), isNull);
    },
  );
  for (final mismatch in [false, true]) {
    testWidgets(
      'candidate ${mismatch ? 'response mismatch' : 'revision conflict'} clears old choices and permits refresh',
      (t) async {
        final c = f.client(
          (r) => r.url.path.endsWith('/candidates')
              ? f.reply(
                  mismatch
                      ? {'statement_id': 'other', 'candidates': [], 'total': 13}
                      : {'error': 'Books changed'},
                  mismatch ? 200 : 409,
                )
              : f.reply(
                  r.url.path.endsWith('/statements')
                      ? statementList()
                      : statement(),
                ),
        );
        addTearDown(c.dispose);
        await f.mountDialog(
          t,
          BookkeepingStatementHistory(client: c, businessId: f.businessId),
        );
        await f.tap(t, '2027 · 1 rows · cash account 1000');
        await f.tap(t, 'Show more candidates');
        expect(find.textContaining('Review match:'), findsNothing);
        expect(find.text('Export review CSV'), findsNothing);
        await f.tap(t, 'Refresh statement');
        expect(find.text('5 of 13 candidates loaded'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'legacy statement responses never invent paging metadata or purpose',
    (t) async {
      final legacy = statement(paging: false);
      for (final row in (legacy['statement'] as Map)['rows']) {
        for (final c in row['candidates']) {
          c.remove('purpose');
        }
      }
      final c = f.client(
        (r) => f.reply(
          r.url.path.endsWith('/statements') ? statementList() : legacy,
        ),
      );
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingStatementHistory(client: c, businessId: f.businessId),
      );
      await f.tap(t, '2027 · 1 rows · cash account 1000');
      expect(find.text('Show more candidates'), findsNothing);
      expect(find.text('5 candidate(s)'), findsOneWidget);
      expect(find.textContaining('Purpose unavailable'), findsNWidgets(5));
    },
  );
  testWidgets(
    'slow preview does not delay scan status, and a lost scan retries the exact key',
    (t) async {
      await f.size(t, const Size(390, 1000));
      final preview = Completer<http.Response>();
      final keys = <String>[];
      var statusCalls = 0;
      final c = f.client((r) {
        if (r.url.path.endsWith('/preview')) return preview.future;
        if (r.method == 'POST') {
          keys.add((jsonDecode(r.body) as Map)['request_key'] as String);
          return keys.length == 1
              ? f.reply({'error': 'Lost scan response'}, 503)
              : f.reply({
                  'scan': {
                    'state': 'ready',
                    'suggestions': receipts.suggestions(),
                  },
                });
        }
        statusCalls++;
        if (statusCalls == 1) {
          return f.reply({
            'scan': {'state': 'ready', 'suggestions': receipts.suggestions()},
          });
        }
        expect(r.url.queryParameters['request_key'], keys.first);
        return f.reply({'scan': null});
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReceiptViewer(
          client: c,
          businessId: f.businessId,
          receipt: {...receipts.receipt(), 'preview_size': 10},
          scanning: {'available': true},
          canCreate: true,
        ),
      );
      expect(find.text('Vendor: Fixture Store'), findsOneWidget);
      await f.tap(t, 'Scan again');
      await f.tap(t, 'Scan now');
      expect(find.text('Vendor: Fixture Store'), findsNothing);
      expect(find.text('Use fields for expense'), findsNothing);
      await f.tap(t, 'Retry same scan');
      await f.tap(t, 'Retry same scan');
      expect(keys.length, 2);
      expect(keys.first, keys.last);
      expect(find.text('Vendor: Fixture Store'), findsOneWidget);
      preview.complete(f.reply({'error': 'Preview failed'}, 503));
      await t.pumpAndSettle();
      expect(find.text('Retry preview'), findsOneWidget);
      expect(find.text('Vendor: Fixture Store'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'confirmed scan keeps Back open through status recovery and releases navigation after timeout',
    (t) async {
      final posted = Completer<http.Response>(),
          recovery = Completer<http.Response>();
      var reads = 0;
      final c = f.client(
        (r) => r.method == 'POST'
            ? posted.future
            : ++reads == 1
            ? f.reply({'scan': null})
            : recovery.future,
      );
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReceiptViewer(
          client: c,
          businessId: f.businessId,
          receipt: receipts.receipt(),
          scanning: {'available': true},
        ),
      );
      await f.tap(t, 'Scan receipt');
      await t.tap(find.text('Scan now'));
      await t.pump();
      final context = t.element(find.byType(BookkeepingReceiptViewer));
      expect(await Navigator.of(context).maybePop(), true);
      await t.pump();
      expect(find.byType(BookkeepingReceiptViewer), findsOneWidget);
      await t.pump(const Duration(seconds: 101));
      await t.pump();
      expect(reads, 2);
      expect(find.byType(BookkeepingReceiptViewer), findsOneWidget);
      await t.pump(const Duration(seconds: 101));
      await t.pumpAndSettle();
      await f.tap(t, 'Close');
      expect(find.byType(BookkeepingReceiptViewer), findsNothing);
      posted.complete(
        f.reply({
          'scan': {'state': 'ready', 'suggestions': receipts.suggestions()},
        }),
      );
      recovery.complete(f.reply({'scan': null}));
      await t.pumpAndSettle();
      expect(find.byType(BookkeepingReceiptViewer), findsNothing);
    },
  );
  testWidgets(
    'known pending upload resolves only by exact receipt ID and final-page deletion reloads valid page',
    (t) async {
      await f.size(t, const Size(390, 1000));
      var uploaded = false, deleted = false, ready = false;
      final pages = <String>[];
      final c = f.client((r) {
        if (r.method == 'POST') {
          uploaded = true;
          return f.reply({
            'receipt': {...receipts.receipt(), 'state': 'uploading'},
          }, 202);
        }
        if (r.method == 'DELETE') {
          deleted = true;
          return f.reply({'removed': true});
        }
        pages.add(r.url.queryParameters['offset'] ?? '0');
        if (!uploaded) return f.reply({...receipts.inbox(), 'total': 31});
        return f.reply({
          ...receipts.inbox([
            if (deleted && (r.url.queryParameters['offset'] ?? '0') == '0')
              {
                ...receipts.receipt(),
                'id': 'remaining-id',
                'filename': 'remaining.pdf',
              },
            if (!deleted)
              {
                ...receipts.receipt(),
                'state': ready ? 'ready' : 'uploading',
                'id': ready ? receipts.rid : 'different-id',
              },
          ]),
          'total': deleted ? 30 : 31,
        });
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReceipts(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture',
          categories: f.categories(),
          picker: ({bool camera = false}) async => BookkeepingPickedReceipt(
            'original.pdf',
            Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await f.tap(t, 'Choose file');
      await f.tap(t, 'Upload original');
      expect(find.text('Retry same upload'), findsOneWidget);
      ready = true;
      await t.drag(find.byType(ListView).last, const Offset(0, 1500));
      await t.pumpAndSettle();
      await f.tap(t, 'Refresh receipts');
      expect(find.text('Retry same upload'), findsNothing);
      await f.tap(t, 'Next page');
      await f.tap(t, 'Delete unused');
      await f.tap(t, 'Delete receipt');
      expect(pages.sublist(pages.length - 2), ['30', '0']);
      expect(find.text('remaining.pdf'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'journal attachment recovery keeps identity and clears stale inbox on failed history',
    (t) async {
      await f.size(t, const Size(390, 1000));
      final writes = <String>[];
      var historyFails = false;
      final c = f.client((r) {
        if (r.method == 'POST') {
          writes.add(r.body);
          return f.reply({'error': 'Response lost'}, 503);
        }
        if (r.url.path.contains('/journals/')) {
          return historyFails
              ? f.reply({'error': 'History unavailable'}, 503)
              : f.reply({'receipts': []});
        }
        return f.reply(receipts.inbox());
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReceipts(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture',
          categories: const [],
          journal: ledger.journal(),
        ),
      );
      await f.tap(t, 'Choose from receipt inbox');
      await f.tap(t, 'Attach to this journal');
      await f.tap(t, 'Confirm attachment');
      await f.tap(t, 'Attach to this journal');
      await f.tap(t, 'Confirm attachment');
      expect(writes[0], writes[1]);
      expect((jsonDecode(writes.first) as Map)['journal_id'], ledger.jid);
      historyFails = true;
      await t.drag(find.byType(ListView).last, const Offset(0, 1500));
      await t.pumpAndSettle();
      await f.tap(t, 'Back to entry history');
      expect(find.text('supplies.pdf'), findsNothing);
      expect(find.textContaining('No receipt history'), findsNothing);
      expect(find.text('Refresh history'), findsOneWidget);
    },
  );
  testWidgets(
    'mobile validation fully wraps and scrolls the first error into view',
    (t) async {
      final c = f.client(
        (_) => throw StateError('No write before confirmation'),
      );
      addTearDown(c.dispose);
      await mountLargeText(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: f.businessId,
          categories: f.categories(),
          kind: 'expense',
        ),
        width: 320,
      );
      await f.fill(t, 'Amount (USD)', 'invalid');
      await f.fill(t, 'Business purpose', 'Test purchase');
      await f.tap(t, 'Review entry');
      final error = find.text(
        'Use a positive USD amount with up to 2 decimal places.',
      );
      expect(error, findsOneWidget);
      final rect = t.getRect(error);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(1000));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'guide fits a narrow large-text screen and only returns a selected tool',
    (t) async {
      await mountLargeText(
        t,
        const BookkeepingGuide(businessName: 'Fixture books'),
        width: 320,
      );
      await f.screenshot(t, 'rebuilt-guide-320-large-text', previewKey);
      await f.tap(t, 'Reports');
      expect(find.byType(BookkeepingGuide), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'share anchor is measured from the current layout after rotation',
    (t) async {
      final key = GlobalKey();
      await f.size(t, const Size(390, 844));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: TextButton(
                key: key,
                onPressed: () {},
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      );
      final context = t.element(find.byKey(key));
      final before = bookkeepingShareOrigin(key, context);
      t.view.physicalSize = const Size(844, 390);
      await t.pumpAndSettle();
      final after = bookkeepingShareOrigin(key, context);
      expect(after, isNot(before));
      expect(after.right, lessThanOrEqualTo(844));
      expect(after.bottom, lessThanOrEqualTo(390));
    },
  );
}
