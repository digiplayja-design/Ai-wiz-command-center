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
    this.look = 'original',
    this.lighting = 'original',
  });
  final String preset, strength, size, prompt, language, look, lighting;
  final bool preserveIdentity;
  Map<String, String> get fields => {
    'preset': preset,
    'strength': strength,
    'imageSize': size,
    'preserveIdentity': '$preserveIdentity',
    'prompt': prompt,
    'language': language,
    'look': look,
    'lighting': lighting,
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
  if (file.bytes == null || file.bytes!.isEmpty) {
    return 'This photo could not be read. Choose it again.';
  }
  if (file.bytes!.length > 15 * 1024 * 1024) {
    return 'Choose a photo under 15 MB.';
  }
  final ext = file.name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
    return 'Choose a JPG, PNG, or WEBP photo.';
  }
  return null;
}

class PictureStudioClient {
  PictureStudioClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    this.isSessionCurrent,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String backendBaseUrl;
  final KorlixPreviewHeadersBuilder headersBuilder;
  final bool Function()? isSessionCurrent;
  final http.Client _client;
  bool _closed = false, _sessionChanged = false;

  void _guard() {
    if (_closed) {
      throw Exception('Reopen Picture Studio to continue.');
    }
    if (isSessionCurrent?.call() == false) _sessionChanged = true;
    if (_sessionChanged) {
      throw Exception(
        'Your session changed. Sign in again and reopen Picture Studio.',
      );
    }
  }

  Future<PictureEditResult> improve(
    PlatformFile file,
    PictureEditOptions options,
  ) async {
    _guard();
    final problem = pictureFileError(file);
    if (problem != null) throw Exception(problem);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/image/improve',
      ),
    );
    final Map<String, String> headers;
    try {
      headers = Map<String, String>.from(await headersBuilder())
        ..removeWhere((name, _) => name.toLowerCase() == 'content-type');
    } catch (_) {
      _guard();
      rethrow;
    }
    _guard();
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
      _guard();
      throw Exception(
        'This edit took longer than expected. Keep your original and try again shortly.',
      );
    } on http.ClientException {
      _guard();
      throw Exception(
        'The photo service connection was interrupted. Check your connection and try again.',
      );
    } catch (_) {
      _guard();
      rethrow;
    }
    _guard();
    if ([401, 419, 440].contains(response.statusCode)) {
      _sessionChanged = true;
      throw Exception(
        'Your session expired. Sign in again to improve your picture.',
      );
    }
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      for (final value in [data?['details'], data?['error']]) {
        if (value is String && value.trim().isNotEmpty) {
          message = value;
          break;
        }
      }
      throw Exception(
        message ??
            (response.statusCode == 429
                ? 'The photo service is busy. Please wait a moment and try again.'
                : 'The edit could not be completed. Please try again.'),
      );
    }
    if (data == null) {
      throw Exception(
        'The photo service did not return a valid result. Please try again.',
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
    const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < pngSignature.length ||
        !Iterable<int>.generate(
          pngSignature.length,
        ).every((index) => bytes[index] == pngSignature[index])) {
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

  void dispose() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
