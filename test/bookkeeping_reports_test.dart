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
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/reports_screen.dart';
import 'bookkeeping_test.dart' as f;
import 'bookkeeping_ledger_test.dart' as l;

List<Map<String, dynamic>> cashAccounts() => [
  {'code': '1000', 'name': 'Recorded cash control', 'kind': 'cash'},
  {'code': '1001', 'name': 'Operating bank', 'kind': 'cash'},
];
Map<String, dynamic> report([String period = '2027-01']) => {
  'period': period,
  'from_date': period.length == 4 ? '$period-01-01' : '$period-01',
  'as_of': period.length == 4 ? '$period-12-31' : '$period-31',
  'generated_at': '2027-02-01T10:00:00Z',
  'cash_entry_count': 2,
  'journal_count': 1,
  'opening': null,
  'scope':
      'Recorded USD books only. Bank reconciliation and tax calculations are not performed.',
  'warnings': [
    'No opening balances are recorded. Confirm a zero starting position or add prior closing balances.',
  ],
  'summary': {
    'income_cents': '10000',
    'expense_cents': '3000',
    'net_cents': '7000',
    'assets_cents': '107000',
    'liabilities_cents': '0',
    'booked_equity_cents': '100000',
    'prior_earnings_cents': '0',
    'current_earnings_cents': '7000',
    'total_equity_cents': '107000',
    'balance_difference_cents': '0',
    'trial_debit_cents': '110000',
    'trial_credit_cents': '110000',
  },
  'accounts': [
    for (final a in [
      ['1001', 'Operating bank', 'cash', '107000', '0', '107000'],
      ['3000', 'Owner capital', 'equity', '0', '100000', '-100000'],
      ['4000', 'Services', 'income', '0', '10000', '-10000'],
      ['5000', 'Supplies', 'expense', '3000', '0', '3000'],
    ])
      {
        'code': a[0],
        'name': a[1],
        'kind': a[2],
        'beginning_cents': '0',
        'period_debit_cents': a[3],
        'period_credit_cents': a[4],
        'closing_cents': a[5],
        'prior_year_cents': '0',
      },
  ],
};
http.Response base(http.Request r) {
  if (r.url.path.endsWith('/businesses')) {
    return f.reply({
      'businesses': [f.business()],
    });
  }
  if (r.url.path.endsWith('/overview')) {
    return f.reply({...f.overview(), 'cash_accounts': cashAccounts()});
  }
  if (r.url.path.endsWith('/ledger')) return f.reply(l.list());
  return f.reply(report(r.url.queryParameters['period'] ?? '2027-01'));
}

Future<void> choose(WidgetTester t, String current, String next) async {
  final dropdown = find.widgetWithText(
    DropdownButtonFormField<String>,
    current,
  );
  await t.ensureVisible(dropdown);
  await t.tap(dropdown);
  await t.pumpAndSettle();
  await f.tap(t, next);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final e in {
        'MaterialIcons': 'MaterialIcons-Regular.otf',
        'Roboto': 'Roboto-Regular.ttf',
      }.entries) {
        await (FontLoader(e.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${e.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  testWidgets(
    'month/year validation and exports use the applied period and chosen report',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      final requests = <http.Request>[];
      final exports = <String>[];
      final c = f.client((r) {
        requests.add(r);
        return r.url.path.endsWith('/export')
            ? f.reply({'csv': 'recorded,USD', 'filename': 'report.csv'})
            : base(r);
      });
      addTearDown(c.dispose);
      await f.mountDialog(
        t,
        BookkeepingReports(
          client: c,
          businessId: f.businessId,
          businessName: 'Harbor Creative LLC',
          initialPeriod: '2027-01',
          onExport: (csv, name) async {
            exports.add(csv);
          },
        ),
      );
      expect(find.text(r'$70.00'), findsOneWidget);
      await f.fill(t, 'Month or year', '2027-13');
      await f.tap(t, 'View period');
      expect(requests.length, 1);
      expect(find.textContaining('Use YYYY'), findsOneWidget);
      await f.fill(t, 'Month or year', '2027');
      await f.tap(t, 'View period');
      expect(requests.last.url.queryParameters['period'], '2027');
      await choose(t, 'Profit & loss', 'Balance sheet');
      expect(find.text('As of 2027-12-31'), findsOneWidget);
      expect(
        find.text('Unclosed earnings · current calendar year to date'),
        findsOneWidget,
      );
      await f.fill(t, 'Month or year', '2028');
      await f.tap(t, 'Export report CSV');
      expect(requests.last.url.queryParameters, {
        'period': '2027',
        'kind': 'balance_sheet',
      });
      await f.tap(t, 'Export ledger CSV');
      expect(requests.last.url.queryParameters['kind'], 'ledger');
      expect(exports.length, 2);
      await choose(t, 'Balance sheet', 'Trial balance');
      expect(find.text('Total closing debits'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('report failure clears previous totals and supports retry', (
    t,
  ) async {
    await f.size(t, const Size(1000, 1000));
    var calls = 0;
    final c = f.client(
      (r) => ++calls == 2
          ? f.reply({'error': 'Reports unavailable'}, 503)
          : base(r),
    );
    addTearDown(c.dispose);
    await f.mountDialog(
      t,
      BookkeepingReports(
        client: c,
        businessId: f.businessId,
        businessName: 'Private business',
        initialPeriod: '2027-01',
      ),
    );
    expect(find.text(r'$70.00'), findsOneWidget);
    await f.tap(t, 'View period');
    expect(find.text(r'$70.00'), findsNothing);
    expect(find.textContaining('Reports unavailable'), findsOneWidget);
    await f.tap(t, 'View period');
    expect(find.text(r'$70.00'), findsOneWidget);
  });
  testWidgets('selected cash account survives review and same-request retry', (
    t,
  ) async {
    await f.size(t, const Size(390, 844));
    final sent = <Map<String, dynamic>>[];
    final c = f.client((r) {
      sent.add(jsonDecode(r.body) as Map<String, dynamic>);
      return sent.length == 1
          ? f.reply({'error': 'Retry'}, 503)
          : f.reply({'entry': f.savedEntry()}, 201);
    });
    addTearDown(c.dispose);
    await f.mountDialog(
      t,
      BookkeepingEntryDialog(
        client: c,
        businessId: f.businessId,
        categories: f.categories(),
        cashAccounts: cashAccounts(),
        kind: 'income',
      ),
    );
    await f.fill(t, 'Amount (USD)', '100');
    await f.fill(t, 'Date received / paid', '2027-01-15');
    await choose(t, 'Recorded cash control (1000)', 'Operating bank (1001)');
    await f.fill(t, 'Business purpose', 'Consulting');
    await f.tap(t, 'Review entry');
    expect(find.text('Cash account: Operating bank (1001)'), findsOneWidget);
    expect(sent, isEmpty);
    await f.tap(t, 'Confirm and save');
    await f.tap(t, 'Retry same save');
    expect(sent.first['cash_account'], '1001');
    expect(sent.first, sent.last);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'returning from accounts refreshes account choices on dashboard',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      var loads = 0;
      final c = f.client((r) {
        if (r.url.path.endsWith('/overview')) {
          loads++;
          return f.reply({
            ...f.overview(),
            'cash_accounts': loads > 1
                ? cashAccounts()
                : [cashAccounts().first],
          });
        }
        return base(r);
      });
      addTearDown(c.dispose);
      await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
      await t.pumpAndSettle();
      await f.tap(t, 'Accounts & journals');
      await t.tap(find.byTooltip('Close ledger'));
      await t.pumpAndSettle();
      expect(loads, 2);
      await f.tap(t, 'Record income');
      await f.tap(t, 'Recorded cash control (1000)');
      expect(find.text('Operating bank (1001)'), findsOneWidget);
    },
  );
  testWidgets(
    'session change removes report data and discards an in-flight export',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      final changes = ValueNotifier(0);
      String identity = f.token('owner');
      final pending = Completer<http.Response>();
      var downloaded = false;
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'Bearer $identity'},
        sessionChanges: changes,
        client: MockClient(
          (r) async =>
              r.url.path.endsWith('/export') ? pending.future : base(r),
        ),
      );
      await f.mountDialog(
        t,
        BookkeepingReports(
          client: c,
          businessId: f.businessId,
          businessName: 'Private business',
          initialPeriod: '2027-01',
          onExport: (csv, name) async {
            downloaded = true;
          },
        ),
      );
      final export = find.text('Export report CSV');
      await t.ensureVisible(export);
      await t.tap(export);
      await t.pump();
      identity = f.token('other');
      changes.value++;
      await t.pump();
      pending.complete(f.reply({'csv': 'private', 'filename': 'private.csv'}));
      await t.pumpAndSettle();
      expect(downloaded, false);
      expect(find.text('Private business'), findsNothing);
      expect(find.textContaining('Session changed'), findsOneWidget);
      expect(find.text(r'$70.00'), findsNothing);
      c.dispose();
      changes.dispose();
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('dashboard report and balance-sheet layout at $width', (
      t,
    ) async {
      await f.size(t, Size(width, 900));
      final c = f.client(base);
      addTearDown(c.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(home: BookkeepingScreen(client: c)),
        ),
      );
      await t.pumpAndSettle();
      await f.tap(t, 'Reports');
      await f.fill(t, 'Month or year', '2027-01');
      await f.tap(t, 'View period');
      expect(find.text(r'$70.00'), findsOneWidget);
      await t.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, 2000),
      );
      await t.pumpAndSettle();
      await f.screenshot(t, 'k202-profit-loss-${width.toInt()}', key);
      await choose(t, 'Profit & loss', 'Balance sheet');
      await t.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, 2000),
      );
      await t.pumpAndSettle();
      await f.screenshot(t, 'k202-balance-sheet-${width.toInt()}', key);
      await t.ensureVisible(find.text('Export ledger CSV'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
