import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_forms.dart';
import 'package:ai_wiz_command_center/bookkeeping/ledger_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/mileage_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/reports_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_preview.dart';
import 'bookkeeping_test.dart' as f;
import 'bookkeeping_ledger_test.dart' as ledger;
import 'bookkeeping_mileage_test.dart' as mileage;
import 'bookkeeping_receipts_test.dart' as receipts;
import 'bookkeeping_reports_test.dart' as reports;

Future<void> choose(WidgetTester t, String label, String value) async {
  final selector = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  await t.ensureVisible(selector);
  await t.tap(selector);
  await t.pumpAndSettle();
  await f.tap(t, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(f.loadBookkeepingFonts);
  for (final receipt in [false, true]) {
    testWidgets(
      '${receipt ? 'receipt' : 'cash'} confirmed failed save reopens its month; cancellation keeps the current month',
      (t) async {
        await f.size(t, const Size(1100, 1200));
        final months = <String>[], writes = <String>[];
        final c = f.client((r) {
          if (r.method == 'POST') {
            writes.add(r.body);
            return f.reply({'error': 'Response lost'}, 503);
          }
          if (r.url.path.endsWith('/overview')) {
            months.add(r.url.queryParameters['month']!);
            return f.reply(f.overview());
          }
          return receipts.baseReply(r);
        });
        addTearDown(c.dispose);
        await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
        await t.pumpAndSettle();
        final originalMonth = months.last;
        await f.tap(t, 'Record expense');
        await f.fill(t, 'Date received / paid', '2028-02-12');
        await f.tap(t, 'Close');
        expect(months.last, originalMonth);
        if (receipt) {
          await f.tap(t, 'Receipt inbox');
          await f.tap(t, 'Record expense');
        } else {
          await f.tap(t, 'Record expense');
        }
        await f.fill(t, 'Date received / paid', '2027-02-12');
        await f.fill(t, 'Amount (USD)', '12.34');
        await f.fill(t, 'Business purpose', 'Fixture purchase');
        if (receipt) {
          await f.tap(
            t,
            'I checked the receipt, amount, currency and date paid / received.',
          );
        }
        await f.tap(t, 'Review entry');
        await f.tap(t, 'Confirm and save');
        expect(writes.length, 1);
        await f.tap(t, 'Close');
        if (receipt) {
          await t.tap(find.byTooltip('Close receipts'));
          await t.pumpAndSettle();
        }
        expect(months.last, '2027-02');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'journal uncertain save refreshes its month and account editing adds no date hint',
    (t) async {
      await f.size(t, const Size(1100, 1200));
      final months = <String>[];
      final c = f.client((r) {
        if (r.method == 'POST') return f.reply({'error': 'Response lost'}, 503);
        months.add(r.url.queryParameters['month']!);
        return f.reply(ledger.list());
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingLedger(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture',
        ),
      );
      final initial = months.last;
      await f.tap(t, 'Add account');
      await f.tap(t, 'Close');
      expect(months.last, initial);
      await f.tap(t, 'Record journal');
      await ledger.fillJournal(t);
      await f.tap(t, 'Review');
      await f.tap(t, 'Confirm and save');
      await f.tap(t, 'Close');
      expect(months.last, '2027-01');
      expect(t.takeException(), isNull);
    },
  );
  for (final annual in [false, true]) {
    testWidgets(
      'mileage uncertain save preserves ${annual ? 'annual' : 'monthly'} scope and clears vehicle filter only after an attempt',
      (t) async {
        await f.size(t, const Size(1100, 1200));
        final reads = <Map<String, String>>[];
        final c = f.client((r) {
          if (r.method == 'POST') {
            return f.reply({'error': 'Response lost'}, 503);
          }
          reads.add(r.url.queryParameters);
          return f.reply(mileage.list());
        });
        addTearDown(c.dispose);
        await f.mountDialog(
          t,
          BookkeepingMileage(
            client: c,
            businessId: f.businessId,
            businessName: 'Fixture',
          ),
        );
        await f.fill(
          t,
          'Period (YYYY or YYYY-MM)',
          annual ? '2026' : '2026-09',
        );
        await f.fill(t, 'Vehicle filter (optional)', 'Blue hatchback');
        await f.tap(t, 'Apply filters');
        final original = reads.last;
        await f.tap(t, 'Record trip');
        await f.tap(t, 'Close');
        expect(reads.last, original);
        await f.tap(t, 'Record trip');
        await mileage.fillTrip(t);
        await f.tap(t, 'Review trip');
        await f.tap(t, 'Confirm and save trip');
        await f.tap(t, 'Close');
        expect(reads.last['period'], annual ? '2027' : '2027-01');
        expect(reads.last['vehicle'] ?? '', isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'confirmed cash save blocks Back, times out and retries the identical request',
    (t) async {
      await f.size(t, const Size(390, 1000));
      final pending = Completer<http.Response>(), writes = <String>[];
      final c = f.client((r) {
        writes.add(r.body);
        return writes.length == 1
            ? pending.future
            : f.reply({'entry': f.savedEntry()}, 201);
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: f.businessId,
          categories: f.categories(),
          kind: 'income',
        ),
      );
      await f.fill(t, 'Date received / paid', '2027-01-15');
      await f.fill(t, 'Amount (USD)', '1250');
      await f.fill(t, 'Business purpose', 'Fixture income');
      await f.tap(t, 'Review entry');
      await t.tap(find.text('Confirm and save'));
      await t.pump();
      final context = t.element(find.byType(BookkeepingEntryDialog));
      await Navigator.of(context).maybePop();
      await t.pump();
      expect(find.byType(BookkeepingEntryDialog), findsOneWidget);
      await t.pump(const Duration(seconds: 101));
      await t.pumpAndSettle();
      await f.tap(t, 'Retry same save');
      expect(writes[0], writes[1]);
      expect(find.byType(BookkeepingEntryDialog), findsNothing);
      pending.complete(f.reply({'entry': f.savedEntry()}, 201));
      await t.pumpAndSettle();
      expect(find.byType(BookkeepingEntryDialog), findsNothing);
    },
  );
  testWidgets(
    'export failure stays by report controls, clears after scope change and success confirms preparation',
    (t) async {
      await f.size(t, const Size(390, 1000));
      var fail = true, shares = 0;
      final c = f.client(
        (r) => r.url.path.endsWith('/export')
            ? fail
                  ? f.reply({'error': 'Export unavailable'}, 503)
                  : f.reply({'csv': 'recorded,USD', 'filename': 'report.csv'})
            : reports.base(r),
      );
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReports(
          client: c,
          businessId: f.businessId,
          businessName: 'Fixture',
          initialPeriod: '2027-01',
          onExport: (_, _) async {
            shares++;
          },
        ),
      );
      await f.tap(t, 'Export report CSV');
      final error = find.text('Export unavailable');
      expect(error, findsOneWidget);
      expect(t.getRect(error).top, greaterThanOrEqualTo(0));
      expect(t.getRect(error).bottom, lessThanOrEqualTo(1000));
      expect(shares, 0);
      await f.fill(t, 'Month or year', '2027');
      await f.tap(t, 'View period');
      expect(error, findsNothing);
      fail = false;
      await f.tap(t, 'Export ledger CSV');
      expect(shares, 1);
      expect(find.textContaining('CSV prepared'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'partial statement overlap requires exact reviewed rows and explanation',
    (t) async {
      await f.size(t, const Size(390, 1000));
      final overlap = [
        {'line': 2, 'statement_id': 'prior-statement', 'existing_line': 7},
      ];
      Map<String, dynamic>? sent;
      final c = f.client((r) {
        if (r.url.path.endsWith('/import')) {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return f.reply({
            'statement': {'id': 'new', 'row_count': 2},
          }, 201);
        }
        return f.reply({
          'row_count': 2,
          'invalid_count': 0,
          'duplicate_count': 0,
          'overlap_count': 1,
          'fully_overlapping': false,
          'overlap_snapshot': overlap,
          'entries': [
            {
              'line': 2,
              'date': '2027-01-15',
              'description': 'Deposit',
              'amount_cents': '100',
              'status': 'unmatched',
              'candidates': [],
            },
          ],
        });
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingStatementPreview(
          client: c,
          businessId: f.businessId,
          cashAccounts: [
            {'code': '1000', 'name': 'Cash', 'kind': 'cash'},
          ],
          pickCsv: () async => (
            'bank.csv',
            Uint8List.fromList(
              utf8.encode(
                'Date,Memo,Amount\n2027-01-15,Deposit,1.00\n2027-01-16,Payment,-1.00',
              ),
            ),
          ),
        ),
      );
      await f.tap(t, 'Choose CSV');
      await choose(t, 'Date column (YYYY-MM-DD)', 'Date');
      await choose(t, 'Description column', 'Memo');
      await choose(t, 'Signed amount column', 'Amount');
      await f.fill(t, 'Calendar year (YYYY)', '2027');
      await f.tap(t, 'Preview possible matches');
      await f.tap(
        t,
        'I reviewed the statement rows and selected cash account.',
      );
      await f.tap(t, 'Import reviewed rows');
      expect(sent, isNull);
      await f.tap(
        t,
        'I reviewed these overlaps against the original statements.',
      );
      await f.fill(
        t,
        'Reason for partial overlap',
        'This export spans both statement periods.',
      );
      await f.tap(t, 'Import reviewed rows');
      expect(sent?['overlap_snapshot'], overlap);
      expect(
        sent?['overlap_review_reason'],
        'This export spans both statement periods.',
      );
      expect(t.takeException(), isNull);
    },
  );
}
