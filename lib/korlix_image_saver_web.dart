import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveKorlixGeneratedImage({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final blob = html.Blob(<Object>[bytes], mimeType);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: objectUrl)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();

  Timer(const Duration(seconds: 1), () {
    anchor.remove();
    html.Url.revokeObjectUrl(objectUrl);
  });
}
