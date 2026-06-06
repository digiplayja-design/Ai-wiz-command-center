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
  return KorlixVideoPreviewSource(
    url: url,
    headers: _cleanVideoPreviewHeaders(headers),
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
