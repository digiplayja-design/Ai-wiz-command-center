import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/ledger_form.dart';
import 'package:ai_wiz_command_center/bookkeeping/ledger_models.dart';
import 'package:ai_wiz_command_center/bookkeeping/ledger_screen.dart';
import 'bookkeeping_test.dart' as f;

const jid = '33333333-3333-4333-8333-333333333333';
List<Map<String, dynamic>> accounts() => [
  {
    'code': '1000',
    'name': 'Recorded cash control',
    'kind': 'cash',
    'balance_cents': '100000',
  },
  {
    'code': '1001',
    'name': 'Business savings',
    'kind': 'cash',
    'balance_cents': '0',
  },
  {'code': '1200', 'name': 'Equipment', 'kind': 'asset', 'balance_cents': '0'},
  {
    'code': '2000',
    'name': 'Loans payable',
    'kind': 'liability',
    'balance_cents': '0',
  },
  {
    'code': '3000',
    'name': 'Owner / shareholder capital',
    'kind': 'equity',
    'balance_cents': '-100000',
  },
  {
    'code': '3100',
    'name': 'Owner draws / distributions',
    'kind': 'equity',
    'balance_cents': '0',
  },
  {
    'code': '3200',
    'name': 'Retained earnings',
    'kind': 'equity',
    'balance_cents': '0',
  },
  {'code': '4000', 'name': 'Services', 'kind': 'income', 'balance_cents': '0'},
];
Map<String, dynamic> journal() => {
  'id': jid,
  'entry_date': '2027-01-15',
  'kind': 'contribution',
  'purpose': 'Owner startup funding',
  'lines': [
    {'account': '1000', 'debit_cents': '100000', 'credit_cents': '0'},
    {'account': '3000', 'debit_cents': '0', 'credit_cents': '100000'},
  ],
  'reversed_by': null,
};
Map<String, dynamic> list() => {
  'accounts': accounts(),
  'journals': [journal()],
  'journal_count': 1,
  'as_of': '2027-01-31',
  'opening': null,
};
http.Response base(http.Request r) {
  if (r.url.path.endsWith('/businesses')) {
    return f.reply({
      'businesses': [f.business()],
    });
  }
  if (r.url.path.endsWith('/overview')) return f.reply(f.overview());
  return f.reply(list());
}

Future<void> fillJournal(WidgetTester t) async {
  await f.fill(t, 'Journal date (YYYY-MM-DD)', '2027-01-15');
  await f.fill(t, 'Description', 'Owner startup funding');
  await f.fill(t, 'Amount (USD)', '1000');
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
  test('exact debit/credit display and guided account restrictions', () {
    expect(
      ledgerBalance('-9007199254740993'),
      r'$90,071,992,547,409.93 credit',
    );
    expect(ledgerCents('0.29'), BigInt.from(29));
    expect(ledgerAllowed('loan_received', 'credit'), ['liability']);
    expect(ledgerAllowed('loan_principal', 'debit'), ['liability']);
    expect(ledgerAllowed('transfer', 'credit'), ['cash']);
    expect(ledgerAllowed('asset_purchase', 'credit'), ['cash', 'liability']);
  });
  testWidgets(
    'review precedes journal write and lost response retry preserves exact payload',
    (t) async {
      await f.size(t, const Size(1100, 1100));
      final sent = <Map<String, dynamic>>[];
      final c = f.client((r) {
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        return sent.length == 1
            ? f.reply({'error': 'Interrupted'}, 503)
            : f.reply({'journal': journal()}, 201);
      });
      await f.mountDialog(
        t,
        LedgerForm(client: c, businessId: f.businessId, accounts: accounts()),
      );
      await f.tap(t, 'Review');
      expect(sent, isEmpty);
      await fillJournal(t);
      await f.tap(t, 'Review');
      expect(find.text(r'Balanced · $1,000.00 each side'), findsOneWidget);
      expect(sent, isEmpty);
      await f.tap(t, 'Confirm and save');
      await f.tap(t, 'Retry same save');
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(sent[0]['lines'], [
        {'account': '1000', 'side': 'debit', 'amount': '1000'},
        {'account': '3000', 'side': 'credit', 'amount': '1000'},
      ]);
      c.dispose();
    },
  );
  testWidgets(
    'opening balances reject mismatch then review and save balanced document',
    (t) async {
      await f.size(t, const Size(1100, 1100));
      http.Request? sent;
      final c = f.client((r) {
        sent = r;
        return f.reply({
          'journal': {
            ...journal(),
            'kind': 'opening',
            'entry_date': '2026-12-31',
          },
        });
      });
      await f.mountDialog(
        t,
        LedgerForm(
          client: c,
          businessId: f.businessId,
          accounts: accounts(),
          initialKind: 'opening',
        ),
      );
      await f.fill(t, 'Prior closing date (YYYY-MM-DD)', '2026-12-31');
      await f.fill(t, 'Description', 'Prior year closing balances');
      await f.fill(t, 'Amount 1 (USD)', '1000');
      await f.fill(t, 'Amount 2 (USD)', '999.99');
      await f.tap(t, 'Review');
      expect(
        find.textContaining('Debits and credits must balance'),
        findsOneWidget,
      );
      expect(sent, isNull);
      await f.fill(t, 'Amount 2 (USD)', '1000');
      await f.tap(t, 'Review');
      expect(find.text('Opening balances'), findsOneWidget);
      await f.tap(t, 'Confirm and save');
      final p = jsonDecode(sent!.body) as Map;
      expect(p['kind'], 'opening');
      expect(p['lines'][1]['account'], '3200');
      c.dispose();
    },
  );
  testWidgets('named account requires confirmation and keeps reviewed kind', (
    t,
  ) async {
    await f.size(t, const Size(1000, 900));
    http.Request? sent;
    final c = f.client((r) {
      sent = r;
      return f.reply({'account': accounts()[1]});
    });
    await f.mountDialog(
      t,
      LedgerForm(
        client: c,
        businessId: f.businessId,
        accounts: accounts(),
        accountOnly: true,
      ),
    );
    await f.fill(t, 'Account name', 'Business savings');
    await f.tap(t, 'Review');
    expect(sent, isNull);
    await f.tap(t, 'Confirm and save');
    expect(sent!.url.path, endsWith('/ledger/accounts'));
    expect(jsonDecode(sent!.body)['kind'], 'cash');
    c.dispose();
  });
  testWidgets(
    'reversal reviews swapped sides and original date before saving',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      http.Request? sent;
      final c = f.client((r) {
        sent = r;
        return f.reply({
          'journal': {...journal(), 'kind': 'reversal'},
        });
      });
      await f.mountDialog(
        t,
        LedgerForm(
          client: c,
          businessId: f.businessId,
          accounts: accounts(),
          original: journal(),
        ),
      );
      await f.fill(t, 'Reason for reversal', 'Wrong amount');
      await f.tap(t, 'Review');
      expect(find.text('Date: 2027-01-15'), findsOneWidget);
      expect(
        find.textContaining('Credit \$1,000.00\nRecorded cash control'),
        findsOneWidget,
      );
      expect(sent, isNull);
      await f.tap(t, 'Confirm and save');
      expect(sent!.url.path, endsWith('/journals/$jid/reverse'));
      expect(jsonDecode(sent!.body)['reason'], 'Wrong amount');
      c.dispose();
    },
  );
  testWidgets(
    'month filter drives combined export and existing opening disables duplicate setup',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      final requests = <http.Request>[];
      String? exported;
      final c = f.client((r) {
        requests.add(r);
        return f.reply(
          r.url.path.endsWith('/export')
              ? {'csv': 'debit,credit\r\n1000,1000', 'filename': 'ledger.csv'}
              : {
                  ...list(),
                  'opening': {'id': jid, 'entry_date': '2026-12-31'},
                },
        );
      });
      await f.mountDialog(
        t,
        BookkeepingLedger(
          client: c,
          businessId: f.businessId,
          businessName: 'Harbor Creative LLC',
          onExport: (csv, name) async {
            exported = csv;
          },
        ),
      );
      await f.fill(t, 'Ledger month (YYYY-MM)', '2027-02');
      await f.tap(t, 'Apply month');
      expect(requests.last.url.queryParameters['month'], '2027-02');
      await t.drag(find.byType(ListView).last, const Offset(0, 1800));
      await t.pumpAndSettle();
      await f.tap(t, 'Export combined ledger');
      expect(requests.last.url.queryParameters['month'], '2027-02');
      expect(exported, contains('1000,1000'));
      final button = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Set opening balances'),
      );
      expect(button.onPressed, isNull);
      c.dispose();
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('ledger and reviewed journal fit $width in actual theme', (
      t,
    ) async {
      await f.size(t, Size(width, 1100));
      final c = f.client(base);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(home: BookkeepingScreen(client: c)),
        ),
      );
      await t.pumpAndSettle();
      await f.tap(t, 'Accounts & journals');
      expect(find.text('Give every business dollar a place.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'k201-ledger-${width.toInt()}', key);
      await f.tap(t, 'Record journal');
      await fillJournal(t);
      await f.tap(t, 'Review');
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'k201-review-${width.toInt()}', key);
      c.dispose();
    });
  }
  testWidgets(
    'session change clears ledger and nested private journal inputs',
    (t) async {
      await f.size(t, const Size(1100, 1000));
      final changes = ValueNotifier(0);
      String identity = f.token('owner');
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'Bearer $identity'},
        sessionChanges: changes,
        client: MockClient((r) async => base(r)),
      );
      await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
      await t.pumpAndSettle();
      await f.tap(t, 'Accounts & journals');
      await f.tap(t, 'Record journal');
      await fillJournal(t);
      identity = f.token('other');
      changes.value++;
      await t.pumpAndSettle();
      expect(find.textContaining('Your session changed.'), findsOneWidget);
      expect(find.text('Owner startup funding'), findsNothing);
      expect(find.text('Review'), findsNothing);
      expect(t.takeException(), isNull);
      c.dispose();
      changes.dispose();
    },
  );
}
