import 'dart:async';
import 'dart:html' as html;

Future<void> downloadKorlixVideo({
  required String url,
  required Map<String, String> headers,
  required String filename,
}) async {
  final request = await html.HttpRequest.request(
    url,
    method: 'GET',
    requestHeaders: headers,
    responseType: 'blob',
  );

  final status = request.status ?? 0;
  final response = request.response;

  if (status < 200 || status >= 300 || response is! html.Blob) {
    throw Exception('Video download failed. Status code: $status');
  }

  final objectUrl = html.Url.createObjectUrlFromBlob(response);
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
