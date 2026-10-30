import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_wiz_command_center/auth/korlix_http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../live_convo/agent_studio_client.dart' show agentAccountScope;
import '../support/korlix_ai_report_client.dart';
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
    this.submitReport,
    this.reportChanges,
    this.isReportCurrent,
  });
  final Uint8List bytes;
  final String summary, quality, size;
  final Future<String> Function(String reason, String details)? submitReport;
  final Listenable? reportChanges;
  final bool Function()? isReportCurrent;
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

class PictureStudioClient extends ChangeNotifier {
  PictureStudioClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    this.isSessionCurrent,
    http.Client? client,
  }) : _client = client ?? http.createClient();
  final String backendBaseUrl;
  final KorlixPreviewHeadersBuilder headersBuilder;
  final bool Function()? isSessionCurrent;
  final http.Client _client;
  bool _closed = false, _sessionChanged = false;

  bool get _reportCurrent =>
      !_closed && !_sessionChanged && isSessionCurrent?.call() != false;

  void _invalidate() {
    if (_sessionChanged) return;
    _sessionChanged = true;
    notifyListeners();
  }

  void _guard() {
    if (_closed) {
      throw Exception('Reopen Picture Studio to continue.');
    }
    if (isSessionCurrent?.call() == false) _invalidate();
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
          .timeout(const Duration(seconds: 490));
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
      _invalidate();
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
    final summary = data['editSummary']?.toString() ?? '';
    final reportScope = agentAccountScope(headers);
    final contentId = data['generationId']?.toString();
    return PictureEditResult(
      bytes: bytes,
      summary: summary,
      quality: data['imageQuality']?.toString() ?? '',
      size: data['imageSize']?.toString() ?? '',
      reportChanges: this,
      isReportCurrent: () => _reportCurrent,
      submitReport: (reason, details) => _report(
        bytes: bytes,
        options: options,
        summary: summary,
        scope: reportScope,
        headers: headers,
        contentId: contentId,
        reason: reason,
        details: details,
      ),
    );
  }

  Future<String> _report({
    required Uint8List bytes,
    required PictureEditOptions options,
    required String summary,
    required String scope,
    required Map<String, String> headers,
    required String? contentId,
    required String reason,
    required String details,
  }) async {
    _guard();
    Future<Map<String, String>> checkedHeaders() async {
      _guard();
      final fresh = Map<String, String>.from(await headersBuilder());
      _guard();
      if (scope.isEmpty || agentAccountScope(fresh) != scope) {
        _invalidate();
        throw const KorlixAiReportException(
          'Your account changed. Reopen Picture Studio to report an image.',
        );
      }
      return fresh;
    }

    final reportId = await submitKorlixAiReport(
      endpoint: Uri.parse(
        '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/report-output',
      ),
      headers: headers,
      reason: reason,
      details: details,
      prompt: options.prompt,
      outputSummary: '$summary\n${jsonEncode(options.fields)}',
      contentId: contentId,
      contentType: 'image',
      appArea: 'picture_studio',
      imageDataUrl: 'data:image/png;base64,${base64Encode(bytes)}',
      language: options.language,
      platform: defaultTargetPlatform.name,
      isCurrent: () => _reportCurrent,
      // Check async auth again after image preparation, immediately before POST.
      client: _PictureReportTransport(_client, checkedHeaders),
    );
    await checkedHeaders();
    return reportId;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    notifyListeners();
    _client.close();
    super.dispose();
  }
}

class _PictureReportTransport extends http.BaseClient {
  _PictureReportTransport(this.inner, this.checkedHeaders);
  final http.Client inner;
  final Future<Map<String, String>> Function() checkedHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await checkedHeaders();
    // Header keys are case-insensitive. Replace the bearer directly, retaining
    // the JSON content type set by the report client.
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'content-type') {
        request.headers[entry.key] = entry.value;
      }
    }
    return inner.send(request);
  }
}
