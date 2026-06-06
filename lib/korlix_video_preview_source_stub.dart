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

Future<KorlixVideoPreviewSource> prepareKorlixVideoPreviewSource({
  required String url,
  required Map<String, String> headers,
}) async {
  return KorlixVideoPreviewSource(url: url, headers: headers);
}

Future<void> releaseKorlixVideoPreviewSource(
  KorlixVideoPreviewSource? source,
) async {
  final release = source?.release;

  if (release != null) {
    await release();
  }
}
