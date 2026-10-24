import 'dart:math';

const businessStructures = <String, String>{
  'sole_proprietor': 'Sole proprietor / sole trader',
  'llc': 'LLC',
  'corporation': 'Corporation',
  'partnership': 'Partnership',
  'other': 'Other',
};
const taxTreatments = <String, String>{
  'unsure': 'Not sure / confirm with accountant',
  'sole_proprietor': 'Sole proprietor',
  'partnership': 'Partnership',
  'c_corporation': 'C corporation',
  's_corporation': 'S corporation',
};
List<String> allowedTreatments(String structure) => switch (structure) {
  'sole_proprietor' => ['unsure', 'sole_proprietor'],
  'partnership' => ['unsure', 'partnership'],
  'corporation' => ['unsure', 'c_corporation', 's_corporation'],
  _ => taxTreatments.keys.toList(),
};
String bookkeepingRequestKey() {
  final r = Random.secure();
  final bytes = List.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String bookkeepingDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String bookkeepingMoney(Object? value) {
  final amount = BigInt.tryParse('$value') ?? BigInt.zero;
  final n = amount.abs();
  final digits = (n ~/ BigInt.from(100)).toString();
  final groups = <String>[];
  for (int end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(max(0, end - 3), end));
  }
  return '${amount.isNegative ? '-' : ''}\$${groups.join(',')}.${(n % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String? validateBookkeepingAmount(String? value) {
  if (value == null ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$').hasMatch(value)) {
    return 'Use a positive USD amount with up to 2 decimal places.';
  }
  final parts = value.split('.');
  final cents =
      BigInt.parse(parts.first) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  return cents < BigInt.one || cents > BigInt.parse('999999999999')
      ? r'Enter $0.01 to $9,999,999,999.99.'
      : null;
}

String? validateBookkeepingDate(String? value) {
  if (value == null || !RegExp(r'^20\d\d-\d\d-\d\d$').hasMatch(value)) {
    return 'Use YYYY-MM-DD (2000–2099).';
  }
  final date = DateTime.tryParse(value);
  return date == null || bookkeepingDate(date) != value
      ? 'Enter a valid calendar date.'
      : null;
}

List<Map<String, dynamic>> bookkeepingRows(dynamic value) =>
    (value as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
