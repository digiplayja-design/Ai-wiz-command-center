import 'bookkeeping_models.dart';

const ledgerKinds = <String, String>{
  'contribution': 'Owner contribution',
  'distribution': 'Owner draw / distribution',
  'loan_received': 'Loan received',
  'loan_principal': 'Loan principal repayment',
  'asset_purchase': 'Asset purchase',
  'transfer': 'Cash account transfer',
  'adjustment': 'Balance sheet adjustment',
  'opening': 'Opening balances',
  'reversal': 'Reversal',
};
const ledgerAccountKinds = <String, String>{
  'cash': 'Cash / bank control',
  'asset': 'Asset',
  'liability': 'Liability',
  'equity': 'Equity',
};
List<String> ledgerAllowed(String kind, String side) => switch ((kind, side)) {
  ('contribution', 'debit') ||
  ('loan_received', 'debit') ||
  ('transfer', _) => ['cash'],
  ('contribution', 'credit') || ('distribution', 'debit') => ['equity'],
  ('loan_received', 'credit') || ('loan_principal', 'debit') => ['liability'],
  ('distribution', 'credit') || ('loan_principal', 'credit') => ['cash'],
  ('asset_purchase', 'debit') => ['asset'],
  ('asset_purchase', 'credit') => ['cash', 'liability'],
  _ => ledgerAccountKinds.keys.toList(),
};
String ledgerHelp(String kind) => switch (kind) {
  'opening' =>
    'Enter closing balances from your prior records, dated the day before you begin recording activity here. Include assets, liabilities and equity. Debits must equal credits; there is no automatic balancing amount. Only one active opening document is allowed. Midyear income and expense carry-forwards are not supported yet.',
  'loan_principal' =>
    'Record principal only. Record interest and fees separately as operating expenses. Confirm the split using your lender statement.',
  'asset_purchase' =>
    'Record the asset cost and the cash paid or liability incurred. This does not calculate depreciation or decide tax treatment.',
  'transfer' =>
    'Move an amount between two different cash control accounts. This does not create income or an expense.',
  'adjustment' =>
    'Enter balanced asset, cash, liability and equity changes from your records. Use accountant-reviewed account classifications. Operating income and expenses use the main entry forms.',
  'distribution' =>
    'Record money taken out by an owner or shareholder. Confirm the appropriate equity classification; payroll and tax treatment are separate.',
  'loan_received' =>
    'Record borrowed funds as cash and a liability. Borrowing does not add operating income.',
  _ =>
    'Record funds contributed by an owner or shareholder as cash and equity. Confirm the appropriate capital account.',
};
BigInt ledgerCents(String value) {
  final parts = value.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
}

String ledgerAmount(Object? cents) {
  final n = BigInt.parse('$cents');
  return '${n ~/ BigInt.from(100)}.${(n % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String ledgerBalance(Object? cents) {
  final n = BigInt.tryParse('$cents') ?? BigInt.zero;
  return '${bookkeepingMoney(n.abs())}${n == BigInt.zero
      ? ''
      : n.isNegative
      ? ' credit'
      : ' debit'}';
}

String? ledgerText(String? value, int max) =>
    value == null ||
        value.trim().isEmpty ||
        value.trim().length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
    ? 'Use 1–$max characters on one line.'
    : null;
