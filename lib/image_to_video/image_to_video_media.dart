import '../korlix_video_preview_source.dart';

typedef ImageToVideoMediaHeaders = Future<Map<String, String>> Function();

class ImageToVideoMedia {
  ImageToVideoMedia({required String url, required String backendBaseUrl})
    : uri = Uri.parse(url.trim()) {
    final backend = Uri.parse(backendBaseUrl);
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('The video link is not a secure video URL.');
    }
    protected = uri.origin == backend.origin;
    if (protected &&
        !RegExp(
          r'^/api/video/image-to-video/content/[^/]+$',
        ).hasMatch(uri.path)) {
      throw const FormatException('The protected video link is not valid.');
    }
  }

  final Uri uri;
  late final bool protected;

  Future<Map<String, String>> headers(ImageToVideoMediaHeaders builder) async {
    // Kling's external signed URLs must never receive a KORLIX bearer token,
    // device identifier or account email. Only our exact API origin gets auth.
    if (!protected) return const {};
    final headers = Map<String, String>.from(await builder());
    final authorization = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'authorization')
        .map((entry) => entry.value)
        .firstOrNull;
    if (authorization == null ||
        !authorization.startsWith('Bearer ') ||
        authorization.substring(7).trim().isEmpty) {
      throw StateError('Sign in again to open your private video.');
    }
    headers.removeWhere((key, _) => key.toLowerCase() == 'content-type');
    headers['Accept'] = 'video/*';
    return headers;
  }

  Future<KorlixVideoPreviewSource> preparePreview(
    ImageToVideoMediaHeaders builder,
  ) async {
    if (!protected) return KorlixVideoPreviewSource(url: uri.toString());
    // Browsers cannot attach bearer headers to <video>; the web helper fetches
    // authenticated bytes into a blob URL and supplies a revocation callback.
    return prepareKorlixVideoPreviewSource(
      url: uri.toString(),
      headers: await headers(builder),
    );
  }
}
