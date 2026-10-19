import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

const maxKorlixReportImageBytes = 1024 * 1024;
const _maxOriginalBytes = 16 * 1024 * 1024;

class KorlixReportImageException implements Exception {
  const KorlixReportImageException();
  String get message =>
      'The image could not be attached. No report was sent. '
      'Open the image and try again, or contact support@korlixdeveloper.com.';
}

/// Send only a bounded review copy, removing metadata by decoding/re-encoding.
/// Remote images use a plain client: account credentials never leave the API.
Future<String> prepareKorlixReportImage({
  String? imageDataUrl,
  String? imageUrl,
  http.Client? client,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    final Uint8List bytes;
    if (imageDataUrl != null && imageDataUrl.isNotEmpty) {
      if (imageDataUrl.length > 64 + 4 * ((_maxOriginalBytes + 2) ~/ 3) ||
          !RegExp(
            r'^data:image/(png|jpeg|webp);base64,',
          ).hasMatch(imageDataUrl)) {
        throw const KorlixReportImageException();
      }
      bytes = base64Decode(
        imageDataUrl.substring(imageDataUrl.indexOf(',') + 1),
      );
    } else {
      final uri = Uri.tryParse(imageUrl ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const KorlixReportImageException();
      }
      final transport = client ?? http.Client();
      try {
        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await transport
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > _maxOriginalBytes) {
          throw const KorlixReportImageException();
        }
        final collected = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (collected.length + chunk.length > _maxOriginalBytes) {
            throw const KorlixReportImageException();
          }
          collected.add(chunk);
        }
        bytes = collected.takeBytes();
      } finally {
        if (client == null) transport.close();
      }
    }
    if (bytes.isEmpty || bytes.length > _maxOriginalBytes) {
      throw const KorlixReportImageException();
    }
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 16 * 1024 * 1024) {
      throw const KorlixReportImageException();
    }
    for (final dimension in [1280, 960, 640, 480]) {
      final width = descriptor.width >= descriptor.height;
      final longest = width ? descriptor.width : descriptor.height;
      final target = longest < dimension ? longest : dimension;
      final codec = await descriptor.instantiateCodec(
        targetWidth: width ? target : null,
        targetHeight: width ? null : target,
      );
      try {
        if (codec.frameCount != 1) throw const KorlixReportImageException();
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png != null && png.lengthInBytes <= maxKorlixReportImageBytes) {
            return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    throw const KorlixReportImageException();
  } catch (_) {
    throw const KorlixReportImageException();
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
