import 'dart:async';
import 'dart:convert';
// Matches the app's existing web file-download implementation.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui';

Future<void> saveFunnelCsv(String csv, String filename, Rect origin) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([utf8.encode(csv)], 'text/csv;charset=utf-8'),
  );
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
