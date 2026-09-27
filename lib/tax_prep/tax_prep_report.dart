import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../bookkeeping/bookkeeping_models.dart';
import 'tax_prep_models.dart';

Future<Uint8List> buildTaxPrepPdf(Map<String, dynamic> packet) async {
  taxPacket(packet);
  final w = taxMap(packet['workspace']), data = taxMap(w['data']);
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'),
  );
  final navy = PdfColor.fromHex('#152D46'),
      teal = PdfColor.fromHex('#087E91'),
      pale = PdfColor.fromHex('#EDF6F8');
  final doc = pw.Document(
    title: 'KORLIX Tax Prep ${w['year']} - preparation organizer',
    author: 'KORLIX',
  );
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  pw.Widget title(String s) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
    child: pw.Text(
      s,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: navy,
      ),
    ),
  );
  List<pw.Widget> paragraphs(String s) => s.split('\n').expand((line) {
    final parts = <String>[];
    var rest = line;
    while (rest.length > 240) {
      var end = rest.lastIndexOf(' ', 240);
      if (end < 80) end = 240;
      parts.add(rest.substring(0, end));
      rest = rest.substring(end).trimLeft();
    }
    if (rest.isNotEmpty) parts.add(rest);
    if (parts.isEmpty) parts.add('');
    return parts.map(
      (v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(
          v,
          style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
        ),
      ),
    );
  }).toList();
  pw.Widget footer(pw.Context c) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'KORLIX TAX PREP ${w['year']} | Draft organizer | Revision ${w['version']}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.Text(
          '${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme,
      maxPages: 120,
      footer: footer,
      build: (c) => [
        pw.Text(
          'KORLIX TAX PREP',
          style: pw.TextStyle(
            fontSize: 25,
            fontWeight: pw.FontWeight.bold,
            color: navy,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          '${w['year']} preparation packet',
          style: pw.TextStyle(fontSize: 15, color: teal),
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          color: pale,
          child: pw.Text(
            '${packet['scope']}',
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
        pw.SizedBox(height: 12),
        ...paragraphs(
          'Period: January 1 - December 31, ${w['year']} (calendar year)\nBook snapshot: ${w['snapshotAt']}\nSource check: ${packet['checkedAt'] ?? 'See export revision'}\nExpected filing status (unverified): ${taxFilingStatuses[data['filingStatus']] ?? 'Not chosen'}\nStates to discuss: ${(data['states'] as List? ?? []).join(', ')}\nPreparation only. No return has been filed and no tax liability is calculated.',
        ),
        title('Document organizer'),
        pw.Text(
          'Statuses are user reported. Original documents are not embedded in this packet.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Record to organize', 'Status'],
          data: taxChecklist.entries
              .map(
                (e) => [
                  e.value,
                  taxChecklistStatuses[taxMap(data['checklist'])[e.key]] ??
                      'To gather',
                ],
              )
              .toList(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 9,
          ),
          headerDecoration: pw.BoxDecoration(color: navy),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(6),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1.3),
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
        ),
        title('Questions and notes for the preparer'),
        ...paragraphs(
          '${data['notes'] ?? ''}'.isEmpty
              ? 'No notes entered.'
              : '${data['notes']}',
        ),
        if (taxRows(w['books']).isEmpty) ...[
          title('Business records'),
          ...paragraphs(
            'No businesses are linked to this organizer. Add businesses from KORLIX Bookkeeping if applicable.',
          ),
        ],
        for (final b in taxRows(w['books'])) ...[
          pw.NewPage(),
          title('${taxMap(b['business'])['name']}'),
          ...paragraphs(
            'Business ID: ${taxMap(b['business'])['id']}\nLegal structure: ${businessStructures[taxMap(b['business'])['legal_structure']] ?? taxMap(b['business'])['legal_structure']}\nRecorded tax treatment: ${taxTreatments[taxMap(b['business'])['tax_treatment']] ?? 'Confirm with preparer'}\n${b['treatmentNote']}',
          ),
          pw.TableHelper.fromTextArray(
            headers: ['Recorded book figure', 'USD'],
            data: [
              [
                'Income',
                bookkeepingMoney(taxMap(b['summary'])['income_cents']),
              ],
              [
                'Expenses',
                bookkeepingMoney(taxMap(b['summary'])['expense_cents']),
              ],
              [
                'Net book result (not taxable income)',
                bookkeepingMoney(taxMap(b['summary'])['net_cents']),
              ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(color: teal),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(7),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
          ),
          pw.SizedBox(height: 10),
          ...paragraphs(
            'Active recorded mileage: ${taxMiles(taxMap(b['mileage'])['distance_tenths'])} miles. No mileage deduction calculated.\nActive expenses without a linked receipt: ${taxMap(b['receipts'])['without_receipt']} of ${taxMap(b['receipts'])['expense_count']}. This identifies missing links, not deductibility.\nBookkeeping records are owner supplied; statement matching does not certify reconciliation. Inventory, depreciation, accrual, payroll, basis, entity and tax adjustments require separate review.',
          ),
          for (final warning in b['warnings'] as List? ?? [])
            ...paragraphs('Review: $warning'),
          title('Account review'),
          for (final a in taxRows(b['accounts'])) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              color: pale,
              child: pw.Text(
                '${a['code']}  ${a['name']} | ${a['kind']} | ${bookkeepingMoney(a['book_cents'])}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            ...paragraphs(
              'Status: ${taxReviewStatuses[taxMap(a['review'])['status']] ?? 'Needs review'}\n${taxMap(a['review'])['note'] ?? ''}',
            ),
            pw.SizedBox(height: 5),
          ],
          ...paragraphs(
            'Income and expense accounts show this calendar year. Assets, liabilities and equity show the recorded year-end balance. Separate-entity figures are not added to personal income. Export the general ledger and original supporting records from Bookkeeping when your preparer needs them.',
          ),
        ],
        title('Guidance and next steps'),
        ...paragraphs(
          'Confirm the correct jurisdiction, return type, period, classification and current-year rules with your preparer. A complete checklist does not establish filing readiness. Use an authorized filing workflow to calculate and submit a return.',
        ),
        for (final s in taxRows(packet['sources']))
          ...paragraphs('${s['label']}\n${s['url']}'),
      ],
    ),
  );
  return doc.save();
}
