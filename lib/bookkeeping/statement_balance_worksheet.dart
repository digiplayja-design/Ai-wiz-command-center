import 'package:flutter/material.dart';
import 'bookkeeping_models.dart';

BigInt parseStatementBalanceCents(String value) {
  final input = value.trim();
  if (!RegExp(r'^-?(?:0|[1-9]\d{0,9})(?:\.\d{1,2})?$').hasMatch(input)) {
    throw const FormatException(
      'Enter an exact USD balance with up to two decimal places.',
    );
  }
  final negative = input.startsWith('-');
  final parts = (negative ? input.substring(1) : input).split('.');
  final cents =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (cents > BigInt.parse('999999999999')) {
    throw const FormatException('Balance exceeds the supported amount.');
  }
  return negative ? -cents : cents;
}

class StatementBalanceWorksheet extends StatefulWidget {
  const StatementBalanceWorksheet({super.key, required this.statementNetCents});
  final String statementNetCents;

  @override
  State<StatementBalanceWorksheet> createState() =>
      _StatementBalanceWorksheetState();
}

class _StatementBalanceWorksheetState extends State<StatementBalanceWorksheet> {
  final _opening = TextEditingController(), _closing = TextEditingController();
  BigInt? _expected, _difference;
  String? _error;

  @override
  void dispose() {
    _opening.dispose();
    _closing.dispose();
    super.dispose();
  }

  void _clear() {
    if (_expected != null || _error != null) {
      setState(() {
        _expected = null;
        _difference = null;
        _error = null;
      });
    }
  }

  void _compare() {
    try {
      final opening = parseStatementBalanceCents(_opening.text);
      final closing = parseStatementBalanceCents(_closing.text);
      final net = BigInt.parse(widget.statementNetCents);
      setState(() {
        _expected = opening + net;
        _difference = closing - _expected!;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _expected = null;
        _difference = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      const Text(
        'Bank balance worksheet',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const Text(
        'Enter the opening and closing USD balances from the original bank statement for exactly the period represented by these imported rows. The comparison stays on this screen and is not saved.',
      ),
      TextField(
        controller: _opening,
        onChanged: (_) => _clear(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: 'Bank opening balance (USD)',
        ),
      ),
      TextField(
        controller: _closing,
        onChanged: (_) => _clear(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: 'Bank closing balance (USD)',
        ),
      ),
      TextButton(
        onPressed: _compare,
        child: const Text('Compare bank balances'),
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Color(0xff9c2525))),
      if (_difference != null) ...[
        Text(
          'Expected closing from imported rows: ${bookkeepingMoney(_expected!)}',
        ),
        Text('Bank closing less expected: ${bookkeepingMoney(_difference!)}'),
        Text(
          _difference == BigInt.zero
              ? 'The balance arithmetic agrees. This alone does not prove that all bank activity was imported or matched to the books.'
              : 'The balances differ. Check the statement period, omitted or duplicate rows, signs, and the original bank statement before proceeding.',
        ),
      ],
      const Text(
        'This worksheet does not reconcile the book balance, post adjustments, or certify the bank statement.',
      ),
    ],
  );
}
