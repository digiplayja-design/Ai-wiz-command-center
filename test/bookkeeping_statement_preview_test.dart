import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_preview.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_history.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_balance_worksheet.dart';
import 'bookkeeping_test.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CSV headers handle quotes and refuse duplicate names', () {
    expect(
      statementHeaders('\uFEFFDate,"Memo, detail",Amount\n2027-01-15,x,1'),
      ['Date', 'Memo, detail', 'Amount'],
    );
    expect(
      () => statementHeaders('Date,Date,Amount\na,b,1'),
      throwsFormatException,
    );
  });
  test(
    'bank balances parse exact signed cents and reject rounded or unsafe input',
    () {
      expect(
        parseStatementBalanceCents('-9000000000.01'),
        BigInt.parse('-900000000001'),
      );
      expect(parseStatementBalanceCents('0.9'), BigInt.from(90));
      for (final value in ['1.234', '1e3', '1,000.00', '10000000000.00', '']) {
        expect(() => parseStatementBalanceCents(value), throwsFormatException);
      }
    },
  );
  testWidgets(
    'bank worksheet shows a discrepancy and clears stale results on edit',
    (t) async {
      await f.size(t, const Size(390, 844));
      await f.mountDialog(
        t,
        const AlertDialog(
          content: SingleChildScrollView(
            child: StatementBalanceWorksheet(statementNetCents: '-125'),
          ),
        ),
      );
      await f.fill(t, 'Bank opening balance (USD)', '100.00');
      await f.fill(t, 'Bank closing balance (USD)', '98.00');
      await f.tap(t, 'Compare bank balances');
      expect(
        find.textContaining('Expected closing from imported rows: \$98.75'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bank closing less expected: -\$0.75'),
        findsOneWidget,
      );
      await f.fill(t, 'Bank closing balance (USD)', '98.75');
      expect(find.textContaining('Bank closing less expected:'), findsNothing);
      await f.tap(t, 'Compare bank balances');
      expect(find.textContaining('balance arithmetic agrees'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'owner maps columns, confirms import and sends exact reviewed CSV',
    (t) async {
      Map<String, dynamic>? sent;
      Map<String, dynamic>? firstImport;
      var importAttempts = 0;
      final c = f.client((r) {
        sent = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.url.path.endsWith('/import')) {
          importAttempts++;
          if (importAttempts == 1) {
            firstImport = sent;
            return f.reply({'error': 'Response lost'}, 503);
          }
          return f.reply({
            'statement': {
              'id': '33333333-3333-4333-8333-333333333333',
              'row_count': 1,
            },
          }, 201);
        }
        expect(r.url.path, contains('/statements/preview'));
        return f.reply({
          'row_count': 1,
          'invalid_count': 0,
          'duplicate_count': 0,
          'entries': [
            {
              'line': 2,
              'date': '2027-01-15',
              'description': 'Customer deposit',
              'amount_cents': '12345',
              'status': 'suggested',
              'candidates': [
                {'entry_id': 'example'},
              ],
            },
          ],
        });
      });
      addTearDown(c.dispose);
      await f.size(t, const Size(390, 844));
      await f.mountDialog(
        t,
        BookkeepingStatementPreview(
          client: c,
          businessId: f.businessId,
          cashAccounts: [
            {'code': '1000', 'name': 'Recorded cash control', 'kind': 'cash'},
          ],
          pickCsv: () async => (
            'statement.csv',
            Uint8List.fromList(
              utf8.encode(
                'Date,Memo,Amount\n2027-01-15,Customer deposit,123.45',
              ),
            ),
          ),
        ),
      );
      await f.tap(t, 'Choose CSV');
      Future<void> choose(String label, String value) async {
        final selector = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == label,
        );
        await t.ensureVisible(selector);
        await t.tap(selector);
        await t.pumpAndSettle();
        await f.tap(t, value);
      }

      await choose('Date column (YYYY-MM-DD)', 'Date');
      await choose('Description column', 'Memo');
      await choose('Signed amount column', 'Amount');
      await f.fill(t, 'Calendar year (YYYY)', '2027');
      await f.tap(t, 'Preview possible matches');
      expect(sent?['mapping'], {
        'date': 'Date',
        'description': 'Memo',
        'amount': 'Amount',
      });
      expect(sent?['cash_account'], '1000');
      expect(find.textContaining('Customer deposit'), findsOneWidget);
      expect(find.textContaining('Nothing'), findsNothing);
      await f.tap(
        t,
        'I reviewed the statement rows and selected cash account.',
      );
      await f.tap(t, 'Import reviewed rows');
      expect(find.textContaining('Response lost'), findsWidgets);
      await f.tap(t, 'Retry same import');
      expect(importAttempts, 2);
      expect(sent, firstImport);
      expect(sent?['confirmed'], true);
      expect(sent?['csv'], contains('Customer deposit'));
      expect(find.textContaining('Imported 1 rows'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'saved import requires reviewed match and retains correction history',
    (t) async {
      final decisions = <Map<String, dynamic>>[];
      final writes = <Map<String, dynamic>>[];
      String? exportedCsv, exportedName;
      final c = f.client((r) {
        if (r.method == 'POST') {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          writes.add(body);
          final d = {
            'id': writes.length == 1
                ? '44444444-4444-4444-8444-444444444444'
                : '55555555-5555-4555-8555-555555555555',
            'row_line': 2,
            'action': r.url.path.endsWith('/unmatch') ? 'unmatch' : 'match',
            if (r.url.path.endsWith('/match')) 'entry_id': body['entry_id'],
          };
          decisions.add(d);
          return f.reply({'decision': d}, 201);
        }
        if (r.url.path.endsWith('/statements')) {
          return f.reply({
            'statements': [
              {
                'id': '33333333-3333-4333-8333-333333333333',
                'statement_year': 2027,
                'row_count': 1,
                'cash_account': '1000',
                'created_at': '2027-01-20',
              },
            ],
          });
        }
        if (r.url.path.endsWith('/export')) {
          return f.reply({
            'filename': 'korlix-statement-review-example.csv',
            'csv': '\uFEFF"Line","Status"\r\n"2","open"\r\n',
          });
        }
        return f.reply({
          'coverage': {
            'row_count': 1,
            'matched_count':
                decisions.isNotEmpty && decisions.last['action'] == 'match'
                ? 1
                : 0,
            'open_count':
                decisions.isNotEmpty && decisions.last['action'] == 'match'
                ? 0
                : 1,
            'statement_net_cents': '12345',
            'matched_net_cents':
                decisions.isNotEmpty && decisions.last['action'] == 'match'
                ? '12345'
                : '0',
            'open_net_cents':
                decisions.isNotEmpty && decisions.last['action'] == 'match'
                ? '0'
                : '12345',
            'from_date': '2027-01-15',
            'through_date': '2027-01-15',
            'scope': 'Review progress only; not a cleared bank balance.',
          },
          'statement': {
            'id': '33333333-3333-4333-8333-333333333333',
            'statement_year': 2027,
            'cash_account': '1000',
            'rows': [
              {
                'line': 2,
                'date': '2027-01-15',
                'description': 'Customer deposit',
                'amount_cents': '12345',
                'status': 'suggested',
                'candidates': [
                  {
                    'entry_id': '22222222-2222-4222-8222-222222222222',
                    'date': '2027-01-15',
                    'kind': 'income',
                    'amount_cents': '12345',
                  },
                ],
              },
            ],
          },
          'decisions': decisions,
        });
      });
      addTearDown(c.dispose);
      await f.size(t, const Size(390, 844));
      await f.mountDialog(
        t,
        BookkeepingStatementHistory(
          client: c,
          businessId: f.businessId,
          onExport: (csv, name) async {
            exportedCsv = csv;
            exportedName = name;
          },
        ),
      );
      await f.tap(t, '2027 · 1 rows · cash account 1000');
      expect(find.text('Bank balance worksheet'), findsOneWidget);
      await f.tap(t, 'Export review CSV');
      expect(exportedName, 'korlix-statement-review-example.csv');
      expect(exportedCsv, contains('"2","open"'));
      expect(find.textContaining('0 matched · 1 open'), findsOneWidget);
      await f.tap(
        t,
        'Review match: 2027-01-15 · income · 22222222-2222-4222-8222-222222222222',
      );
      expect(writes, isEmpty);
      await f.tap(t, 'Confirm decision');
      expect(writes.first['entry_id'], '22222222-2222-4222-8222-222222222222');
      expect(find.textContaining('1 matched · 0 open'), findsOneWidget);
      await f.tap(t, 'Correct match');
      await f.fill(t, 'Reason for correction', 'Wrong match');
      await f.tap(t, 'Review correction');
      await f.tap(t, 'Confirm decision');
      expect(writes.last['reason'], 'Wrong match');
      expect(writes.last['previous_match_id'], decisions.first['id']);
      expect(find.textContaining('Unmatched after correction'), findsOneWidget);
      expect(find.textContaining('0 matched · 1 open'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
