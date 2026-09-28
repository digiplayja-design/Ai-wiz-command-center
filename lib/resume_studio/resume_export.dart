import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'resume_model.dart';

/// PDF, Word, preview and text all use the same ordered content blocks.
Future<Uint8List> resumePdf(ResumeDraft draft, {bool letter = false}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'),
  );
  final doc = pw.Document(
    title: letter ? 'Cover letter' : 'Resume',
    author: draft.get('name'),
  );
  final accent = PdfColor.fromHex(
    draft.template == 'minimal' ? '#1E293B' : '#${draft.accent}',
  );
  final size = draft.compact ? 10.0 : 10.5;
  final widgets = <pw.Widget>[];
  if (draft.template == 'modern') {
    widgets.add(
      pw.Container(
        width: double.infinity,
        height: 4,
        color: accent,
        margin: const pw.EdgeInsets.only(bottom: 14),
      ),
    );
  }
  for (final b in draft.blocks(letter: letter)) {
    final name = b.kind == 'name',
        heading = b.kind == 'heading',
        title = b.kind == 'title';
    final top = name
        ? 0.0
        : heading
        ? 14.0
        : title
        ? 7.0
        : 3.0;
    final style = pw.TextStyle(
      fontSize: name
          ? 26
          : heading
          ? 11
          : title
          ? 11
          : b.kind == 'contact' || b.kind == 'meta'
          ? 9
          : size,
      fontWeight: name || heading || title
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
      color: name || heading || b.kind == 'role' ? accent : PdfColors.grey900,
      lineSpacing: draft.compact ? 1.5 : 2.8,
    );
    final chunks = _chunks(b.text);
    for (var i = 0; i < chunks.length; i++) {
      if (heading) {
        widgets.add(
          pw.Header(
            level: 1,
            margin: pw.EdgeInsets.only(top: top, bottom: 5),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: accent, width: .6),
              ),
            ),
            textStyle: style,
            text: chunks[i].toUpperCase(),
          ),
        );
      } else {
        widgets.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(
              top: i == 0 ? top : 1,
              bottom: 2,
              left: b.kind == 'bullet' ? 9 : 0,
            ),
            child: pw.SizedBox(
              width: double.infinity,
              child: pw.Text(
                '${b.kind == 'bullet' && i == 0 ? '• ' : ''}${chunks[i]}',
                style: style,
                textAlign:
                    draft.template == 'executive' &&
                        ['name', 'role', 'contact'].contains(b.kind)
                    ? pw.TextAlign.center
                    : pw.TextAlign.left,
              ),
            ),
          ),
        );
      }
    }
  }
  doc.addPage(
    pw.MultiPage(
      pageFormat: draft.paper == 'a4' ? PdfPageFormat.a4 : PdfPageFormat.letter,
      maxPages: 50,
      margin: pw.EdgeInsets.all(draft.compact ? 38 : 44),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${c.pageNumber}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (_) => widgets,
    ),
  );
  return doc.save();
}

List<String> _chunks(String text) {
  // Large pasted paragraphs must be able to flow across pages.
  final out = <String>[];
  var rest = text;
  while (rest.length > 900) {
    var end = rest.lastIndexOf(' ', 900);
    if (end < 400) end = 900;
    out.add(rest.substring(0, end));
    rest = rest.substring(end).trimLeft();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

Uint8List resumeDocx(ResumeDraft draft, {bool letter = false}) {
  String xml(String s) => const HtmlEscape(
    HtmlEscapeMode.element,
  ).convert(s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''));
  final color = draft.template == 'minimal' ? '1E293B' : draft.accent;
  final paragraphs = draft.blocks(letter: letter).map((b) {
    final heading = b.kind == 'heading',
        name = b.kind == 'name',
        title = b.kind == 'title';
    final size = name
        ? 52
        : heading || title
        ? 22
        : b.kind == 'contact' || b.kind == 'meta'
        ? 18
        : draft.compact
        ? 20
        : 21;
    final centered =
        draft.template == 'executive' &&
        ['name', 'role', 'contact'].contains(b.kind);
    final style =
        '<w:pPr>${heading ? '<w:pStyle w:val="Heading1"/>' : ''}${heading || title ? '<w:keepNext/>' : ''}<w:spacing w:before="${heading
            ? 200
            : title
            ? 100
            : 0}" w:after="${draft.compact ? 60 : 90}" w:line="260" w:lineRule="auto"/>${centered ? '<w:jc w:val="center"/>' : ''}${b.kind == 'bullet' ? '<w:ind w:left="180" w:hanging="180"/>' : ''}${name && draft.template == 'modern' ? '<w:pBdr><w:top w:val="single" w:sz="24" w:space="12" w:color="$color"/></w:pBdr>' : ''}${heading ? '<w:pBdr><w:bottom w:val="single" w:sz="4" w:space="4" w:color="$color"/></w:pBdr>' : ''}</w:pPr>';
    final runs = (b.kind == 'bullet' ? '• ${b.text}' : b.text)
        .split('\n')
        .map(
          (s) =>
              '<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="$size"/>${name || heading || title ? '<w:b/>' : ''}<w:color w:val="${name || heading || b.kind == 'role' ? color : '182333'}"/></w:rPr><w:t xml:space="preserve">${xml(heading ? s.toUpperCase() : s)}</w:t></w:r>',
        )
        .join('<w:r><w:br/></w:r>');
    return '<w:p>$style$runs</w:p>';
  }).join();
  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels':
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'word/styles.xml':
        '<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="21"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr></w:style></w:styles>',
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$paragraphs<w:sectPr><w:pgSz w:w="${draft.paper == 'a4' ? 11906 : 12240}" w:h="${draft.paper == 'a4' ? 16838 : 15840}"/><w:pgMar w:top="880" w:right="880" w:bottom="880" w:left="880" w:header="400" w:footer="400" w:gutter="0"/></w:sectPr></w:body></w:document>',
  };
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
