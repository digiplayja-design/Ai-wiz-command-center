import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Map<String, dynamic> fpMap(dynamic v) =>
    Map<String, dynamic>.from(v as Map? ?? {});
List<Map<String, dynamic>> fpRows(dynamic v) =>
    (v as List? ?? []).map(fpMap).toList();
String fpText(dynamic v) => v?.toString() ?? '';
Map<String, dynamic>? fpCurrentReview(Map<String, dynamic> snapshot) {
  final version = fpMap(snapshot['job'])['version'];
  for (final r in fpRows(snapshot['reviews'])) {
    if (r['state'] == 'completed' && r['version'] == version) return r;
  }
  return null;
}

const fpTagNames = {
  'before': 'Before work',
  'after': 'Completed work',
  'serial': 'Asset / serial number',
  'test': 'Test / reading',
  'site': 'Site condition',
  'approval': 'Approval record',
  'other': 'Other evidence',
};
String fpDate(dynamic v) {
  final date = DateTime.tryParse(fpText(v));
  if (date == null) return fpText(v);
  return date.toLocal().toString().split('.').first;
}

String fpInvoiceText(Map<String, dynamic> snapshot) {
  final j = fpMap(snapshot['job']), d = fpMap(j['data']);
  return 'KORLIX FIELDPROOF - INVOICE HANDOFF DRAFT\n'
      'Job: ${d['title']}\nWork order: ${d['workOrder']}\nCustomer: ${d['customer']}\nSite: ${d['site']}\nWork date: ${d['performedOn']}\nTechnician: ${d['technician']}\n'
      'Work reported: ${d['summary']}\nHours (entered): ${d['hours'] ?? 'Not entered'}\nMaterials / quantities (entered): ${d['materials']}\nOutstanding items: ${d['exceptions']}\nBilling notes: ${d['billingNotes']}\n'
      'Job revision: ${j['version']} | ${j['state']}\nVerify scope, quantities, rates, customer terms and billing eligibility before preparing an invoice. This handoff does not issue an invoice or post to bookkeeping.';
}

String fpReportText(Map<String, dynamic> snapshot) {
  final j = fpMap(snapshot['job']),
      d = fpMap(j['data']),
      check = fpMap(snapshot['readiness']),
      approval = fpMap(j['approval']),
      review = fpCurrentReview(snapshot);
  final out =
      StringBuffer(
          'KORLIX FIELDPROOF - ${j['state'] == 'completed' ? 'TECHNICIAN-CLOSED JOB' : 'WORKING DRAFT'}\n',
        )
        ..writeln('${d['title']} | Revision ${j['version']}')
        ..writeln('Job ID: ${j['id']}')
        ..writeln('Snapshot: ${snapshot['snapshotAt']}')
        ..writeln(
          'Customer: ${d['customer']}\nSite: ${d['site']}\nWork order: ${d['workOrder']}\nTechnician: ${d['technician']}\nWork date (entered): ${d['performedOn']}',
        )
        ..writeln(
          'Asset / serial (entered): ${d['assetId']}\nPrevious serial (entered): ${d['oldAssetId']}',
        )
        ..writeln(
          '\nTECHNICIAN-REPORTED WORK\n${d['summary']}\nOutstanding items: ${d['exceptions']}',
        )
        ..writeln('\nREQUIRED RECORDS\n${check['label']}');
  for (final v in check['missing'] as List? ?? []) {
    out.writeln('- Missing: $v');
  }
  for (final c in fpRows(d['checks'])) {
    out.writeln(
      '${c['done'] == true ? '[x]' : '[ ]'} ${c['label']}${c['required'] == true ? ' (required)' : ''}',
    );
  }
  out.writeln('\nCUSTOMER APPROVAL RECORD');
  if (approval.isEmpty) {
    out.writeln('Not recorded.');
  } else {
    out.writeln(
      'Reported approver: ${approval['name']}\nRecorded by: ${approval['recordedBy']}\nRecorded: ${approval['recordedAt']}\nRevision: ${approval['version']}${approval['version'] == j['version'] ? '' : ' (earlier revision)'}\nNote: ${approval['note']}\nTechnician-recorded declaration; not an independently verified signature.',
    );
  }
  out.writeln('\nPHOTO MANIFEST');
  for (final p in fpRows(snapshot['evidence'])) {
    out.writeln(
      '${p['name']} | ${fpTagNames[p['tag']] ?? p['tag']} | ${p['state']}\nPhoto ID: ${p['id']}\nUpload time: ${p['uploadedAt']}\n${p['mime']} | ${p['bytes']} bytes | ${p['width']} x ${p['height']}\nOriginal SHA-256: ${p['sha256']}\nNote: ${p['note']}\n',
    );
  }
  if (review != null) {
    final r = fpMap(review['result']);
    out.writeln('\nKORLIX AI REVIEW - DRAFT\n${r['summary']}');
    for (final o in fpRows(r['observations'])) {
      out.writeln(
        '${o['detail']} | Photo IDs: ${(o['photoIds'] as List? ?? []).join(', ')}',
      );
    }
    for (final f in r['followUps'] as List? ?? []) {
      out.writeln('- Verify: $f');
    }
    out.writeln(
      '\nCUSTOMER REPORT DRAFT\n${r['customerReport']}\n\nAI INVOICE HANDOFF DRAFT\n${r['invoiceHandoff']}\n${r['limits']}',
    );
  }
  out.writeln('\n${fpInvoiceText(snapshot)}\n\nRECENT ACTIVITY');
  for (final e in fpRows(snapshot['events'])) {
    out.writeln(
      '${e['created_at']} | ${e['action']} | revision ${e['version']}',
    );
  }
  out.writeln(
    '\nReport fingerprint: ${snapshot['fingerprint']}\n${check['limits']}\nOriginal files are retained without editing. Hashes compare file bytes; they do not prove capture time, location, authenticity or workmanship. PDF photos are reduced-size previews.',
  );
  return out.toString();
}

List<String> _paragraphs(String value) {
  final out = <String>[];
  for (final line in value.split('\n')) {
    if (line.isEmpty) {
      out.add('');
      continue;
    }
    var rest = line;
    while (rest.length > 650) {
      var end = rest.lastIndexOf(' ', 650);
      if (end < 100) end = 650;
      out.add(rest.substring(0, end));
      rest = rest.substring(end).trimLeft();
    }
    out.add(rest);
  }
  return out;
}

Future<Uint8List> buildFieldProofPdf(
  Map<String, dynamic> snapshot,
  Map<String, Uint8List> previews,
) async {
  for (final p in fpRows(
    snapshot['evidence'],
  ).where((p) => p['state'] == 'ready')) {
    if (!previews.containsKey(p['id'])) {
      throw StateError('A photo preview is missing. Refresh and export again.');
    }
  }
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'),
  );
  final logo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/meeting_copilot/korlix_logo.jpeg',
    )).buffer.asUint8List(),
  );
  final navy = PdfColor.fromHex('#102F43'),
      cyan = PdfColor.fromHex('#087DA0'),
      light = PdfColor.fromHex('#EDF5F8');
  final pdf = pw.Document(
    title:
        'KORLIX FieldProof - ${fpMap(fpMap(snapshot['job'])['data'])['title']}',
    author: 'KORLIX',
  );
  final j = fpMap(snapshot['job']), d = fpMap(j['data']);
  pw.Widget footer(pw.Context c) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'KORLIX FIELDPROOF | Revision ${j['version']}',
          style: pw.TextStyle(fontSize: 8, color: navy),
        ),
        pw.Text(
          '${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      maxPages: 50,
      theme: theme,
      footer: footer,
      build: (c) => [
        pw.Row(
          children: [
            pw.Image(logo, width: 44, height: 44),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'KORLIX FIELDPROOF',
                  style: pw.TextStyle(
                    color: navy,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 23,
                  ),
                ),
                pw.Text(
                  'Job records and evidence report',
                  style: pw.TextStyle(color: cyan, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          color: light,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                fpText(d['title']),
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: navy,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                '${j['state'] == 'completed' ? 'Technician-closed job' : 'Working draft'} | ${fpMap(snapshot['readiness'])['label']}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
        ..._paragraphs(fpReportText(snapshot)).map(
          (p) => p.isEmpty
              ? pw.SizedBox(height: 7)
              : pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    p,
                    style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
                  ),
                ),
        ),
      ],
    ),
  );
  final photos = fpRows(
    snapshot['evidence'],
  ).where((p) => p['state'] == 'ready').toList();
  for (var i = 0; i < photos.length; i += 2) {
    final page = photos.skip(i).take(2).toList();
    for (final p in page) {
      if (!previews.containsKey(p['id'])) {
        throw StateError(
          'A photo preview is missing. Refresh and export again.',
        );
      }
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        theme: theme,
        footer: footer,
        build: (c) => [
          pw.Text(
            'PHOTO EVIDENCE',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 18,
              color: navy,
            ),
          ),
          pw.Text(
            'Reduced-size previews. Original file hashes appear in the manifest.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 14),
          for (final p in page) ...[
            pw.Text(
              '${p['name']} - ${fpTagNames[p['tag']] ?? p['tag']}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 5),
            pw.Container(
              height: 205,
              width: double.infinity,
              color: light,
              child: pw.Image(
                pw.MemoryImage(previews[p['id']]!),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'Photo ID: ${p['id']} | Uploaded: ${p['uploadedAt']}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 15),
          ],
        ],
      ),
    );
  }
  return pdf.save();
}
