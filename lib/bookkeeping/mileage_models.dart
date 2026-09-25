import 'bookkeeping_models.dart';

String mileageDecimal(Object? value) {
  final n = BigInt.tryParse('$value');
  return n == null ? '' : '${n ~/ BigInt.from(10)}.${n % BigInt.from(10)}';
}

BigInt? mileageTenths(String value, {bool odometer = false}) {
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,6})(?:\.[0-9])?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final n =
      BigInt.parse(parts[0]) * BigInt.from(10) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1]);
  return n < (odometer ? BigInt.zero : BigInt.one) ||
          n > BigInt.from(odometer ? 99999999 : 99999)
      ? null
      : n;
}

String? validateMileage(String? v, {bool odometer = false}) =>
    mileageTenths(v ?? '', odometer: odometer) == null
    ? odometer
          ? 'Use 0–9,999,999.9 miles, up to one decimal.'
          : 'Use 0.1–9,999.9 miles, up to one decimal.'
    : null;
String? validateMileageText(String? v, int max) =>
    v == null ||
        v.trim().isEmpty ||
        v.trim().length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)
    ? 'Enter 1–$max characters on one line.'
    : null;
Map<String, String> tripFields(Map<String, dynamic>? t) => {
  'trip_date': t?['trip_date'] as String? ?? bookkeepingDate(DateTime.now()),
  'vehicle': t?['vehicle'] as String? ?? '',
  'origin': t?['origin'] as String? ?? '',
  'destination': t?['destination'] as String? ?? '',
  'purpose': t?['purpose'] as String? ?? '',
  'miles': mileageDecimal(t?['distance_tenths']),
  'odometer_start': mileageDecimal(t?['start_tenths']),
  'odometer_end': mileageDecimal(t?['end_tenths']),
  'reason': '',
};
