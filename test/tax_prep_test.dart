import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/tax_prep/tax_prep_models.dart';
import 'package:ai_wiz_command_center/tax_prep/tax_prep_screen.dart';
import 'package:ai_wiz_command_center/tax_prep/tax_prep_report.dart';
import 'bookkeeping_test.dart' as bk;

const wid = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> organizer() => {
  'filingStatus': 'not_chosen',
  'states': ['NY'],
  'notes': 'Ask about equipment placed in service.',
  'checklist': {for (final k in taxChecklist.keys) k: 'needed'},
  'reviews': <String, dynamic>{},
};
Map<String, dynamic> packet() => {
  'workspace': {
    'id': wid,
    'year': 2026,
    'country': 'US',
    'version': 1,
    'businessIds': [bk.businessId],
    'fingerprint': 'a' * 64,
    'snapshotAt': '2026-09-27T20:00:00Z',
    'updatedAt': '2026-09-27T20:00:00Z',
    'data': organizer(),
    'books': [
      {
        'business': bk.business(),
        'summary': {
          'income_cents': '125000',
          'expense_cents': '150099',
          'net_cents': '-25099',
        },
        'accounts': [
          {
            'code': '4000',
            'name': 'Services',
            'kind': 'income',
            'book_cents': '125000',
            'review': {'status': 'pending', 'note': ''},
          },
          {
            'code': '5010',
            'name': 'Software and subscriptions',
            'kind': 'expense',
            'book_cents': '150099',
            'review': {'status': 'ask_preparer', 'note': 'Check business use.'},
          },
        ],
        'warnings': [
          'No opening balances are recorded. Confirm the starting position.',
        ],
        'mileage': {
          'distance_tenths': '1325',
          'trip_count': 4,
          'excluded_count': 1,
        },
        'receipts': {'expense_count': 5, 'without_receipt': 2},
        'treatmentNote':
            'Separate S corporation preparation. Confirm entity and owner treatment.',
        'cashEntryCount': 7,
        'journalCount': 2,
      },
    ],
  },
  'stale': false,
  'checkedAt': '2026-09-27T20:05:00Z',
  'progress': {
    'organized': 0,
    'notApplicable': 0,
    'toGather': 12,
    'accountsToReview': 2,
  },
  'filingEnabled': false,
  'scope':
      'U.S. preparation organizer. Recorded USD books only; not taxable income, allowed deductions or a filed return.',
  'sources': [
    {
      'label': 'IRS recordkeeping guidance',
      'url': 'https://www.irs.gov/publications/p583',
    },
  ],
};
Map<String, dynamic> clone(Map<String, dynamic> x) =>
    taxMap(jsonDecode(jsonEncode(x)));

class FakeTax extends BookkeepingClient {
  FakeTax()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  Map<String, dynamic> p = packet();
  bool empty = false, failSave = false, failBooks = false, badExport = false;
  int creates = 0, saves = 0, refreshes = 0, exports = 0, deletes = 0;
  List<Map<String, dynamic>> saveBodies = [],
      bookBodies = [],
      createBodies = [];
  Completer<Map<String, dynamic>>? exportGate;
  final listeners = <VoidCallback>[];
  @override
  void addAccessDeniedListener(VoidCallback f) => listeners.add(f);
  @override
  void removeAccessDeniedListener(VoidCallback f) => listeners.remove(f);
  void lock() {
    for (final f in listeners.toList()) {
      f();
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    if (path == '/businesses') {
      return {
        'businesses': [bk.business()],
      };
    }
    if (path.endsWith('/overview')) return bk.overview();
    if (path == '/tax-prep' && method == 'GET') {
      return {
        'workspaces': empty
            ? []
            : [
                {
                  'id': wid,
                  'year': 2026,
                  'version': taxMap(p['workspace'])['version'],
                },
              ],
        'businesses': [bk.business()],
      };
    }
    if (path == '/tax-prep' && method == 'POST') {
      creates++;
      createBodies.add(clone(body!));
      empty = false;
      p['workspace']['year'] = body['year'];
      return clone(p);
    }
    if (method == 'PUT') {
      saves++;
      saveBodies.add(clone(body!));
      if (failSave) {
        throw const BookkeepingException(
          'Save interrupted. Retry the same changes.',
        );
      }
      p['workspace']['data'] = clone(body['data']);
      p['workspace']['version']++;
      return clone(p);
    }
    if (path.endsWith('/books')) {
      refreshes++;
      bookBodies.add(clone(body!));
      if (failBooks) {
        throw const BookkeepingException('Book refresh interrupted. Retry.');
      }
      p['workspace']['businessIds'] = List.from(body['business_ids']);
      if ((body['business_ids'] as List).isEmpty) p['workspace']['books'] = [];
      p['workspace']['version']++;
      p['stale'] = false;
      return clone(p);
    }
    if (path.endsWith('/export')) {
      exports++;
      if (exportGate != null) return exportGate!.future;
      if (body!['format'] == 'csv') {
        return {
          'csv': 'Recorded book figures\r\n1250.00',
          'year': 2026,
          'version': badExport ? 999 : p['workspace']['version'],
        };
      }
      return {'packet': clone(p)};
    }
    if (method == 'DELETE') {
      deletes++;
      empty = true;
      return {'deleted': true};
    }
    if (method == 'GET') return clone(p);
    throw StateError('Unexpected fixture route $method $path');
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeTax c, {
  double width = 390,
  double scale = 1,
  String? initialBusiness,
  Future<void> Function(Uint8List, String, String, Rect)? saver,
  Future<Uint8List> Function(Map<String, dynamic>)? render,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: TaxPrepScreen(
            client: c,
            initialYear: 2026,
            initialBusinessId: initialBusiness,
            saveFile: saver,
            renderPdf: render,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

Future<void> notes(WidgetTester t, String s) async {
  await tap(t, find.byKey(const ValueKey('tax-edit-notes')));
  await t.enterText(find.byType(TextField), s);
  await tap(t, find.text('Keep note'));
}

Future<void> tab(WidgetTester t, int n) =>
    tap(t, find.byKey(ValueKey('tax-tab-$n')));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test(
    'packet validation rejects wrong workspace and unconfirmed fingerprints',
    () {
      taxPacket(packet(), expectedId: wid);
      expect(
        () => taxPacket(packet(), expectedId: 'foreign'),
        throwsA(isA<BookkeepingException>()),
      );
      final p = packet();
      p['workspace']['fingerprint'] = 'wrong';
      expect(() => taxPacket(p), throwsA(isA<BookkeepingException>()));
      expect(taxMiles('9007199254740993'), '900719925474099.3');
    },
  );
  testWidgets(
    'start from Bookkeeping carries the chosen business and calendar year',
    (t) async {
      final c = FakeTax()..empty = true;
      await show(t, c, initialBusiness: bk.businessId);
      await tap(t, find.byKey(const ValueKey('tax-create')));
      expect(c.creates, 1);
      expect(c.createBodies.single['business_ids'], [bk.businessId]);
      expect(c.createBodies.single['year'], 2026);
      expect(find.text('Your 2026 preparation workspace'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('personal-only start sends an empty link list', (t) async {
    final c = FakeTax()..empty = true;
    await show(t, c);
    await tap(t, find.byKey(const ValueKey('tax-create')));
    expect(c.createBodies.single['business_ids'], isEmpty);
    await close(t);
  });
  testWidgets(
    'save keeps edits on failure and retries the exact request before enabling exports',
    (t) async {
      final c = FakeTax()..failSave = true;
      await show(t, c);
      await notes(t, 'Discuss equipment');
      await tab(t, 2);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('tax-export-pdf')))
            .onPressed,
        isNull,
      );
      await tap(t, find.byKey(const ValueKey('tax-save')));
      expect(
        find.text('Save interrupted. Retry the same changes.'),
        findsOneWidget,
      );
      c.failSave = false;
      await tap(t, find.byKey(const ValueKey('tax-save')));
      expect(c.saveBodies[0], c.saveBodies[1]);
      expect(c.p['workspace']['data']['notes'], 'Discuss equipment');
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('tax-export-pdf')))
            .onPressed,
        isNotNull,
      );
      await close(t);
    },
  );
  testWidgets('editing after a failed save creates a new idempotency payload', (
    t,
  ) async {
    final c = FakeTax()..failSave = true;
    await show(t, c);
    await notes(t, 'First note');
    await tap(t, find.byKey(const ValueKey('tax-save')));
    await notes(t, 'Second note');
    c.failSave = false;
    await tap(t, find.byKey(const ValueKey('tax-save')));
    expect(
      c.saveBodies[0]['request_key'],
      isNot(c.saveBodies[1]['request_key']),
    );
    expect(c.saveBodies[1]['data']['notes'], 'Second note');
    await close(t);
  });
  testWidgets(
    'stale books block exports until the explicit refresh completes',
    (t) async {
      final c = FakeTax();
      c.p['stale'] = true;
      await show(t, c);
      await tab(t, 2);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('tax-export-pdf')))
            .onPressed,
        isNull,
      );
      await tap(t, find.byKey(const ValueKey('tax-link')));
      await tap(t, find.text('Link and refresh'));
      expect(c.refreshes, 1);
      expect(c.bookBodies.single['confirmed'], true);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('tax-export-pdf')))
            .onPressed,
        isNotNull,
      );
      await close(t);
    },
  );
  testWidgets('book refresh retry preserves its reviewed selection and key', (
    t,
  ) async {
    final c = FakeTax()..failBooks = true;
    await show(t, c);
    await tap(t, find.byKey(const ValueKey('tax-link')));
    await tap(t, find.text('Link and refresh'));
    c.failBooks = false;
    await tap(t, find.byKey(const ValueKey('tax-link')));
    await tap(t, find.text('Link and refresh'));
    expect(c.bookBodies[0], c.bookBodies[1]);
    await close(t);
  });
  testWidgets(
    'account reviews save notes without posting or changing book amounts',
    (t) async {
      final c = FakeTax();
      await show(t, c);
      await tab(t, 1);
      await tap(t, find.byKey(const ValueKey('review-${bk.businessId}-4000')));
      await t.enterText(find.byType(TextField), 'Compare payer statements');
      await tap(t, find.text('Keep review'));
      await tap(t, find.byKey(const ValueKey('tax-save')));
      expect(
        c.saveBodies.single['data']['reviews'][bk.businessId]['4000']['note'],
        'Compare payer statements',
      );
      expect(c.p['workspace']['books'][0]['summary']['income_cents'], '125000');
      await close(t);
    },
  );
  testWidgets('switching years requires a choice about unsaved edits', (
    t,
  ) async {
    final c = FakeTax();
    await show(t, c);
    await notes(t, 'Unsaved note');
    await tap(t, find.byKey(const ValueKey('tax-year-2026')));
    await tap(t, find.text('2025').last);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tap(t, find.text('Cancel'));
    expect(find.text('Your 2026 preparation workspace'), findsOneWidget);
    expect(c.saves, 0);
    await close(t);
  });
  testWidgets('session change clears the organizer and closes note dialogs', (
    t,
  ) async {
    final c = FakeTax();
    await show(t, c);
    await tap(t, find.byKey(const ValueKey('tax-edit-notes')));
    c.lock();
    await t.pumpAndSettle();
    expect(find.text('Questions for your preparer'), findsNothing);
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(find.textContaining('Ask about equipment'), findsNothing);
    await close(t);
  });
  testWidgets(
    'late export after account change cannot invoke the save action',
    (t) async {
      final c = FakeTax()..exportGate = Completer<Map<String, dynamic>>();
      int saved = 0;
      await show(
        t,
        c,
        saver: (b, n, m, r) async {
          saved++;
        },
      );
      await tab(t, 2);
      final f = find.byKey(const ValueKey('tax-export-csv'));
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pump();
      c.lock();
      c.exportGate!.complete({'csv': 'private', 'year': 2026, 'version': 1});
      await t.pumpAndSettle();
      expect(saved, 0);
      await close(t);
    },
  );
  testWidgets(
    'CSV export validates revision and only saves the explicit download',
    (t) async {
      final c = FakeTax();
      int saved = 0;
      await show(
        t,
        c,
        saver: (b, n, m, r) async {
          saved++;
          expect(utf8.decode(b), contains('Recorded book figures'));
          expect(n, 'KORLIX-Tax-Prep-2026-r1.csv');
          expect(m, 'text/csv');
        },
      );
      await tab(t, 2);
      await tap(t, find.byKey(const ValueKey('tax-export-csv')));
      expect(saved, 1);
      c.badExport = true;
      await tap(t, find.byKey(const ValueKey('tax-export-csv')));
      expect(saved, 1);
      expect(
        find.textContaining('did not match your organizer'),
        findsOneWidget,
      );
      await close(t);
    },
  );
  testWidgets(
    'PDF export uses the verified server packet and renders before saving',
    (t) async {
      final c = FakeTax();
      int saved = 0;
      await show(
        t,
        c,
        render: (p) async {
          expect(p['workspace']['id'], wid);
          return Uint8List.fromList([37, 80, 68, 70]);
        },
        saver: (b, n, m, r) async {
          saved++;
          expect(m, 'application/pdf');
          expect(n, 'KORLIX-Tax-Prep-2026-r1.pdf');
        },
      );
      await tab(t, 2);
      await tap(t, find.byKey(const ValueKey('tax-export-pdf')));
      expect(saved, 1);
      await close(t);
    },
  );
  testWidgets('removal requires confirmation and removes only the organizer', (
    t,
  ) async {
    final c = FakeTax();
    await show(t, c);
    await tab(t, 2);
    await tap(t, find.text('Remove this organizer'));
    await tap(t, find.text('Cancel'));
    expect(c.deletes, 0);
    await tap(t, find.text('Remove this organizer'));
    await tap(t, find.text('Continue'));
    expect(c.deletes, 1);
    expect(find.text('Start your 2026 tax organizer'), findsOneWidget);
    expect(c.p['workspace']['books'][0]['summary']['income_cents'], '125000');
    await close(t);
  });
  testWidgets('Bookkeeping dashboard opens the linked Tax Prep screen', (
    t,
  ) async {
    final c = FakeTax();
    t.view.physicalSize = const Size(1200, 1000);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
    await t.pumpAndSettle();
    await tap(t, find.text('Tax preparation'));
    expect(find.text('KORLIX Tax Prep'), findsOneWidget);
    expect(find.text('Your 2026 preparation workspace'), findsOneWidget);
    await close(t);
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('all preparation tabs fit ${width.toInt()} px at 125% text', (
      t,
    ) async {
      final c = FakeTax();
      await show(t, c, width: width, scale: 1.25);
      expect(t.takeException(), isNull);
      for (final n in [1, 2]) {
        await tab(t, n);
        expect(t.takeException(), isNull);
      }
      await close(t);
    });
  }
  test(
    'actual PDF retains checklist, separate business figures, long notes and provenance',
    () async {
      final p = packet();
      p['workspace']['data']['notes'] = List.filled(
        12,
        'Review equipment records and business use with the preparer.',
      ).join(' ');
      final bytes = await buildTaxPrepPdf(p);
      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(10000));
      final path = Platform.environment['TAX_PREP_PDF_OUTPUT'];
      if (path != null) await File(path).writeAsBytes(bytes);
    },
  );
  testWidgets('optional actual screen captures', (t) async {
    final dir = Platform.environment['TAX_PREP_CAPTURE_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf')))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '${Platform.environment['KORLIX_FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    });
    for (final width in [390.0, 1440.0]) {
      await show(t, FakeTax(), width: width);
      await tab(t, 1);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/tax-prep-${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      await close(t);
    }
  });
}
