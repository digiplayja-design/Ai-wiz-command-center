import 'dart:convert';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'logo_model.dart';
import 'logo_render.dart';

/// Verify optional AI artwork is a complete, decodable PNG before download.
Future<void> validateLogoArtwork(Uint8List bytes) async {
  const message =
      'This artwork could not be opened. Generate a new AI concept.';
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 || bytes.length > 32 * 1024 * 1024) {
    throw const FormatException(message);
  }
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw const FormatException(message);
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(16), height = header.getUint32(20);
  if (header.getUint32(8) != 13 ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR' ||
      width == 0 ||
      height == 0 ||
      width * height > 32000000) {
    throw const FormatException(message);
  }
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    if (image.width != width || image.height != height) {
      throw const FormatException(message);
    }
  } catch (_) {
    throw const FormatException(message);
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

Future<String> logoSvg(
  LogoDesign design, {
  LogoSurface surface = LogoSurface.transparent,
  LogoInk ink = LogoInk.color,
  bool iconOnly = false,
  int? width,
  int? height,
}) async {
  await ensureLogoFonts();
  final regular = (await rootBundle.load(
    'assets/fieldproof/Roboto-Regular.ttf',
  )).buffer.asUint8List();
  final bold = (await rootBundle.load(
    'assets/fieldproof/Roboto-Bold.ttf',
  )).buffer.asUint8List();
  final fonts =
      '<defs><style>@font-face{font-family:KorlixLogo;src:url(data:font/ttf;base64,${base64Encode(regular)}) format("truetype");font-weight:400;}@font-face{font-family:KorlixLogo;src:url(data:font/ttf;base64,${base64Encode(bold)}) format("truetype");font-weight:700;}</style></defs>';
  return LogoComposition(
    design,
    surface: surface,
    ink: ink,
    iconOnly: iconOnly,
  ).svg(fontStyle: fonts, width: width, height: height);
}

Future<Uint8List> logoBrandGuide(
  LogoDesign design, {
  Uint8List? preview,
}) async {
  final image =
      preview ??
      await logoPng(
        design,
        surface: LogoSurface.light,
        width: 1200,
        height: 800,
      );
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'),
  );
  final doc = pw.Document(
    title: '${design.name} brand guide',
    author: 'KORLIX Logo Studio',
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'BRAND NOTES / KORLIX LOGO STUDIO',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            design.name,
            style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
          ),
          if (design.tagline.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                design.tagline,
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
          pw.SizedBox(height: 22),
          pw.Image(pw.MemoryImage(image), height: 240, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 24),
          pw.Text(
            'COLOR PALETTE',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              for (final hex in [
                design.primary,
                design.secondary,
                design.paper,
              ])
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        height: 38,
                        margin: const pw.EdgeInsets.only(right: 8),
                        color: PdfColor.fromHex(hex),
                      ),
                      pw.SizedBox(height: 7),
                      pw.Text('#$hex', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.Text(
            'TYPOGRAPHY & COMPOSITION',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Roboto / ${design.typeface}\n${design.layout} composition / ${design.mark} symbol\nLetter spacing: ${design.tracking.toStringAsFixed(1)}',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'USING YOUR LOGO',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Keep clear space around the mark. Use the transparent PNG on compatible backgrounds and the light or dark version for strong contrast. Avoid stretching, cropping, or adding effects. Test readability at the size you will use.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
          ),
          pw.Spacer(),
          pw.Text(
            'SVG contains vector shapes and editable text. The matching Roboto fonts are included in the kit. PNG exports are raster images. Keep your project JSON to edit again in KORLIX.',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
              lineSpacing: 3,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

Future<Uint8List> logoBrandKit(
  LogoDesign design, {
  void Function()? checkCurrent,
}) async {
  checkCurrent?.call();
  final archive = Archive();
  void add(String name, List<int> bytes) {
    checkCurrent?.call();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  void text(String name, String value) => add(name, utf8.encode(value));
  for (final entry in [
    ('primary', LogoInk.color),
    ('black', LogoInk.black),
    ('white', LogoInk.white),
  ]) {
    text('logos/${entry.$1}.svg', await logoSvg(design, ink: entry.$2));
  }
  add('logos/transparent-2400.png', await logoPng(design));
  add('logos/black-2400.png', await logoPng(design, ink: LogoInk.black));
  add('logos/white-2400.png', await logoPng(design, ink: LogoInk.white));
  final light = await logoPng(design, surface: LogoSurface.light);
  add('logos/light-2400.png', light);
  add('logos/dark-2400.png', await logoPng(design, surface: LogoSurface.dark));
  // Export the same identity in useful lockups, without changing the project.
  for (final layout in ['Horizontal', 'Stacked', 'Wordmark', 'Monogram']) {
    final variant = design.copy(layout: layout);
    final name = layout.toLowerCase();
    text('layouts/$name.svg', await logoSvg(variant));
    add('layouts/$name-2400.png', await logoPng(variant));
  }
  text('social/icon.svg', await logoSvg(design, iconOnly: true));
  add(
    'social/avatar-1024.png',
    await logoPng(
      design,
      surface: LogoSurface.light,
      width: 1024,
      height: 1024,
      iconOnly: true,
    ),
  );
  add(
    'social/icon-transparent-512.png',
    await logoPng(design, width: 512, height: 512, iconOnly: true),
  );
  add(
    'social/cover-1500x500.png',
    await logoPng(
      design.copy(layout: 'Horizontal'),
      surface: LogoSurface.dark,
      width: 1500,
      height: 500,
    ),
  );
  add('brand-guide.pdf', await logoBrandGuide(design, preview: light));
  text(
    'project.korlix-logo.json',
    const JsonEncoder.withIndent('  ').convert(design.json),
  );
  for (final style in ['Regular', 'Bold']) {
    add(
      'fonts/Roboto-$style.ttf',
      (await rootBundle.load(
        'assets/fieldproof/Roboto-$style.ttf',
      )).buffer.asUint8List(),
    );
  }
  text(
    'fonts/LICENSE.txt',
    await rootBundle.loadString('assets/fieldproof/Roboto_LICENSE.txt'),
  );
  text(
    'READ-ME.txt',
    '${design.name} / KORLIX Logo Studio\n\nYour editable logo collection and brand guide.\n\nPalette: #${design.primary}, #${design.secondary}, #${design.paper}\nTypography: Roboto ${design.typeface}. Some SVG editors may require installing the bundled fonts to preserve lettering.\n\nSVG logos contain real vector shapes and editable text; PNG files are raster images. The primary PNG is 2400 x 1600 pixels. Transparent black and white PNGs are included for single-color use. The layouts folder includes horizontal, stacked, wordmark and monogram SVG/PNG versions of your identity.\n\nAvatar and icon SVG are square, with proportional safe space. Avatar is 1024 x 1024; cover is 1500 x 500. Social sizes are general-purpose canvases; check each platform before publishing. White transparent logos need a dark background to be visible.\n\nTo edit again, open Logo Studio > Saved > Import project and choose project.korlix-logo.json. Saved projects in the app stay in this browser/device and account. Keep this backup.\n\nOptional AI artwork is exported separately as a PNG; it is not vectorized by this kit.\n\nRoboto font licensing: https://www.apache.org/licenses/LICENSE-2.0\n',
  );
  checkCurrent?.call();
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
