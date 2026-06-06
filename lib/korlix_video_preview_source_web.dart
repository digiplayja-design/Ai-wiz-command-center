import 'dart:html' as html;

class KorlixVideoPreviewSource {
  final String url;
  final Map<String, String> headers;
  final Future<void> Function()? release;

  const KorlixVideoPreviewSource({
    required this.url,
    this.headers = const <String, String>{},
    this.release,
  });
}

Map<String, String> _cleanVideoPreviewHeaders(Map<String, String> headers) {
  final cleaned = Map<String, String>.from(headers);
  cleaned.removeWhere((key, _) => key.toLowerCase() == 'content-type');
  return cleaned;
}

Future<KorlixVideoPreviewSource> prepareKorlixVideoPreviewSource({
  required String url,
  required Map<String, String> headers,
}) async {
  final request = await html.HttpRequest.request(
    url,
    method: 'GET',
    requestHeaders: _cleanVideoPreviewHeaders(headers),
    responseType: 'blob',
  );

  final status = request.status ?? 0;
  final response = request.response;

  if (status < 200 || status >= 300 || response is! html.Blob) {
    throw Exception('Video preview fetch failed. Status code: $status');
  }

  final objectUrl = html.Url.createObjectUrlFromBlob(response);

  return KorlixVideoPreviewSource(
    url: objectUrl,
    headers: const <String, String>{},
    release: () async {
      html.Url.revokeObjectUrl(objectUrl);
    },
  );
}

Future<void> releaseKorlixVideoPreviewSource(
  KorlixVideoPreviewSource? source,
) async {
  final release = source?.release;

  if (release != null) {
    await release();
  }
}
