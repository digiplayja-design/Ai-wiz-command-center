// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveFieldProofFile(
  Uint8List bytes,
  String name,
  String mime,
) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob(<Object>[bytes], mime),
  );
  final a = html.AnchorElement(href: url)
    ..download = name
    ..style.display = 'none';
  html.document.body?.children.add(a);
  a.click();
  Timer(const Duration(seconds: 2), () {
    a.remove();
    html.Url.revokeObjectUrl(url);
  });
}
