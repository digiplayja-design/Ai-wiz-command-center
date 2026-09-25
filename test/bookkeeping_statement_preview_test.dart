import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/bookkeeping/statement_preview.dart';
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
  testWidgets(
    'owner maps columns and sees preview without saving a financial record',
    (t) async {
      Map<String, dynamic>? sent;
      final c = f.client((r) {
        expect(r.url.path, contains('/statements/preview'));
        sent = jsonDecode(r.body) as Map<String, dynamic>;
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
      expect(t.takeException(), isNull);
    },
  );
}
