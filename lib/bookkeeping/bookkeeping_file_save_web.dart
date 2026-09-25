import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> saveBookkeepingFile(
  Uint8List bytes,
  String filename,
  String mime,
  Rect origin,
) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  Timer(const Duration(seconds: 60), () {
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  });
}
