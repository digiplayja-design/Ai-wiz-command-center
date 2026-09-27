import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'models/portrait_studio_callback.dart';

class PictureEditOptions {
  const PictureEditOptions({
    this.preset = 'enhance',
    this.strength = 'balanced',
    this.size = 'auto',
    this.preserveIdentity = true,
    this.prompt = '',
    this.language = 'en',
  });
  final String preset, strength, size, prompt, language;
  final bool preserveIdentity;
  Map<String, String> get fields => {
    'preset': preset,
    'strength': strength,
    'imageSize': size,
    'preserveIdentity': '$preserveIdentity',
    'prompt': prompt,
    'language': language,
  };
}

class PictureEditResult {
  const PictureEditResult({
    required this.bytes,
    this.summary = '',
    this.quality = '',
    this.size = '',
  });
  final Uint8List bytes;
  final String summary, quality, size;
}

String? pictureFileError(PlatformFile file) {
  if (file.bytes == null || file.bytes!.isEmpty)
    return 'This photo could not be read. Choose it again.';
  if (file.bytes!.length > 15 * 1024 * 1024)
    return 'Choose a photo under 15 MB.';
  final ext = file.name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext))
    return 'Choose a JPG, PNG, or WEBP photo.';
  return null;
}

class PictureStudioClient {
  PictureStudioClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String backendBaseUrl;
  final KorlixPreviewHeadersBuilder headersBuilder;
  final http.Client _client;

  Future<PictureEditResult> improve(
    PlatformFile file,
    PictureEditOptions options,
  ) async {
    final problem = pictureFileError(file);
    if (problem != null) throw Exception(problem);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/image/improve',
      ),
    );
    final headers = Map<String, String>.from(await headersBuilder())
      ..removeWhere((name, _) => name.toLowerCase() == 'content-type');
    request.headers.addAll(headers);
    request.fields.addAll(options.fields);
    final ext = file.name.split('.').last.toLowerCase();
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
      ),
    );
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 430));
    } on TimeoutException {
      throw Exception(
        'This edit took longer than expected. Keep your original and try again shortly.',
      );
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'The photo service did not return a valid result. Please try again.',
      );
    }
    if (response.statusCode == 401)
      throw Exception(
        'Your session expired. Sign in again to improve your picture.',
      );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['details'] ?? data['error'] ?? 'The edit could not be completed.',
      );
    }
    final url = data['imageDataUrl'];
    if (url is! String || !url.startsWith('data:image/png;base64,')) {
      throw Exception(
        'No finished PNG picture was returned. Please try again.',
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(url.substring('data:image/png;base64,'.length));
    } catch (_) {
      throw Exception(
        'The returned picture could not be read. Please try again.',
      );
    }
    if (bytes.length < 8 ||
        bytes[0] != 137 ||
        bytes[1] != 80 ||
        bytes[2] != 78 ||
        bytes[3] != 71) {
      throw Exception(
        'The returned picture could not be read. Please try again.',
      );
    }
    return PictureEditResult(
      bytes: bytes,
      summary: data['editSummary']?.toString() ?? '',
      quality: data['imageQuality']?.toString() ?? '',
      size: data['imageSize']?.toString() ?? '',
    );
  }

  void dispose() => _client.close();
}
