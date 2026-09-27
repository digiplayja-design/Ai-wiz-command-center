import '../bookkeeping/bookkeeping_client.dart';

Map<String, dynamic> taxMap(dynamic v) =>
    Map<String, dynamic>.from(v as Map? ?? {});
List<Map<String, dynamic>> taxRows(dynamic v) =>
    (v as List? ?? []).map(taxMap).toList();
Map<String, dynamic> taxPacket(Map<String, dynamic> p, {String? expectedId}) {
  final w = taxMap(p['workspace']);
  if (w['id'] is! String ||
      (expectedId != null && w['id'] != expectedId) ||
      w['year'] is! int ||
      w['version'] is! int ||
      w['version'] < 1 ||
      w['books'] is! List ||
      w['data'] is! Map ||
      w['businessIds'] is! List ||
      w['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(w['fingerprint'])) {
    throw const BookkeepingException(
      'The tax organizer was not confirmed. Refresh before retrying.',
    );
  }
  return p;
}

String taxMiles(dynamic value) {
  final n = BigInt.tryParse('$value') ?? BigInt.zero;
  return '${n ~/ BigInt.from(10)}.${n % BigInt.from(10)}';
}

const taxChecklist = {
  'identity': 'Identity, household and dependent details held securely',
  'prior_return': 'Prior-year returns and carryover records',
  'wages': 'W-2 wage statements',
  'contractor': '1099-NEC / 1099-K and other business income records',
  'investments': 'Interest, dividends, investments and digital asset records',
  'retirement': 'Retirement, Social Security and benefit statements',
  'property': 'Rental, property sale and mortgage records',
  'deductions':
      'Education, health coverage, charitable and other deduction records',
  'payments': 'Estimated payments, withholding and extension payments',
  'business_records': 'Business receipts, invoices and statement review',
  'assets': 'Equipment, depreciation, inventory and loan records',
  'state_local':
      'State, local and other-country filing requirements checked with preparer',
};
const taxChecklistStatuses = {
  'needed': 'To gather',
  'ready': 'Organized',
  'not_applicable': 'Not applicable',
};
const taxReviewStatuses = {
  'pending': 'Needs review',
  'reviewed': 'Reviewed',
  'ask_preparer': 'Ask preparer',
};
const taxFilingStatuses = {
  'not_chosen': 'Not chosen',
  'single': 'Single',
  'married_joint': 'Married filing jointly',
  'married_separate': 'Married filing separately',
  'head_household': 'Head of household',
  'qualifying_survivor': 'Qualifying surviving spouse',
};
const taxStates = [
  'AL',
  'AK',
  'AZ',
  'AR',
  'CA',
  'CO',
  'CT',
  'DE',
  'DC',
  'FL',
  'GA',
  'HI',
  'ID',
  'IL',
  'IN',
  'IA',
  'KS',
  'KY',
  'LA',
  'ME',
  'MD',
  'MA',
  'MI',
  'MN',
  'MS',
  'MO',
  'MT',
  'NE',
  'NV',
  'NH',
  'NJ',
  'NM',
  'NY',
  'NC',
  'ND',
  'OH',
  'OK',
  'OR',
  'PA',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VT',
  'VA',
  'WA',
  'WV',
  'WI',
  'WY',
];
