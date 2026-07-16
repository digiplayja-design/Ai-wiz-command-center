// KORLIX_LIVE_DOCS_REALTIME_GENERATION_BUILD131_BEGIN
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'korlix_live_docs.dart';

enum KorlixLiveDocsGenerationState { idle, generating, revising, ready, failed }

extension KorlixLiveDocsGenerationStateValues on KorlixLiveDocsGenerationState {
  bool get isBusy {
    return this == KorlixLiveDocsGenerationState.generating ||
        this == KorlixLiveDocsGenerationState.revising;
  }

  String get statusLabel {
    switch (this) {
      case KorlixLiveDocsGenerationState.idle:
        return 'Ready';
      case KorlixLiveDocsGenerationState.generating:
        return 'Generating report…';
      case KorlixLiveDocsGenerationState.revising:
        return 'Revising report…';
      case KorlixLiveDocsGenerationState.ready:
        return 'Report ready';
      case KorlixLiveDocsGenerationState.failed:
        return 'Report generation failed';
    }
  }
}

class KorlixLiveDocsUpload {
  KorlixLiveDocsUpload({
    required this.displayName,
    required this.mimeType,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes);

  final String displayName;
  final String mimeType;
  final Uint8List bytes;
}

class KorlixLiveDocsArtifact {
  KorlixLiveDocsArtifact({
    required this.format,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String format;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  int get byteLength => bytes.length;

  String get formatLabel {
    switch (format.toLowerCase()) {
      case 'xlsx':
        return 'Excel';
      case 'docx':
        return 'Word';
      case 'pdf':
        return 'PDF';
      default:
        return format.toUpperCase();
    }
  }

  IconData get icon {
    switch (format.toLowerCase()) {
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'docx':
        return Icons.description_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  factory KorlixLiveDocsArtifact.fromJson(Map<String, dynamic> json) {
    final encoded = (json['contentBase64'] ?? json['content_base64'] ?? '')
        .toString()
        .trim();

    if (encoded.isEmpty) {
      throw const FormatException(
        'A LIVE DOCS artifact was returned without file bytes.',
      );
    }

    late final Uint8List bytes;

    try {
      bytes = Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      throw const FormatException(
        'A LIVE DOCS artifact contained invalid file bytes.',
      );
    }

    final format = (json['format'] ?? '').toString().trim().toLowerCase();
    final rawName = (json['fileName'] ?? json['file_name'] ?? '').toString();
    final fallbackName = format.isEmpty
        ? 'korlix-report.bin'
        : 'korlix-report.$format';

    return KorlixLiveDocsArtifact(
      format: format.isEmpty ? 'file' : format,
      fileName: rawName.trim().isEmpty ? fallbackName : rawName.trim(),
      mimeType:
          (json['mimeType'] ?? json['mime_type'] ?? 'application/octet-stream')
              .toString()
              .trim(),
      bytes: bytes,
    );
  }
}

class KorlixLiveDocsGenerationResult {
  KorlixLiveDocsGenerationResult({
    required this.jobId,
    required this.status,
    required this.revision,
    required this.title,
    required this.formats,
    required this.sourceFiles,
    required this.executiveSummary,
    required this.artifacts,
    required this.creditsUsed,
    this.generationId,
    this.tier,
  });

  final String jobId;
  final String status;
  final int revision;
  final String title;
  final List<String> formats;
  final List<String> sourceFiles;
  final String executiveSummary;
  final List<KorlixLiveDocsArtifact> artifacts;
  final int creditsUsed;
  final String? generationId;
  final String? tier;

  bool get isReady =>
      status.toLowerCase() == 'completed' && artifacts.isNotEmpty;

  Map<String, dynamic> toRealtimeToolSummary() {
    return <String, dynamic>{
      'success': isReady,
      'job_id': jobId,
      'title': title,
      'revision': revision,
      'formats': formats,
      'files': artifacts.map((artifact) => artifact.fileName).toList(),
      'credits_used_total': creditsUsed,
    };
  }

  factory KorlixLiveDocsGenerationResult.fromJson(Map<String, dynamic> json) {
    final rawArtifacts = json['artifacts'];
    final artifacts = <KorlixLiveDocsArtifact>[];

    if (rawArtifacts is List) {
      for (final raw in rawArtifacts) {
        if (raw is Map) {
          artifacts.add(
            KorlixLiveDocsArtifact.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }

    final rawSourceFiles = json['sourceFiles'] ?? json['source_files'];
    final sourceFiles = <String>[];

    if (rawSourceFiles is List) {
      for (final raw in rawSourceFiles) {
        if (raw is Map) {
          final name = (raw['name'] ?? raw['fileName'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            sourceFiles.add(name);
          }
        } else {
          final name = raw.toString().trim();
          if (name.isNotEmpty) {
            sourceFiles.add(name);
          }
        }
      }
    }

    final rawFormats = json['formats'];
    final formats = <String>[];

    if (rawFormats is List) {
      for (final raw in rawFormats) {
        final value = raw.toString().trim().toLowerCase();
        if (value.isNotEmpty && !formats.contains(value)) {
          formats.add(value);
        }
      }
    }

    final rawReport = json['report'];
    final report = rawReport is Map
        ? Map<String, dynamic>.from(rawReport)
        : const <String, dynamic>{};

    final status = (json['status'] ?? '').toString().trim();
    final title =
        (json['title'] ?? report['title'] ?? 'Korlix LIVE DOCS Report')
            .toString()
            .trim();

    final result = KorlixLiveDocsGenerationResult(
      jobId: (json['jobId'] ?? json['job_id'] ?? '').toString().trim(),
      status: status,
      revision: _korlixInt(json['revision'], fallback: 1),
      title: title.isEmpty ? 'Korlix LIVE DOCS Report' : title,
      formats: List<String>.unmodifiable(formats),
      sourceFiles: List<String>.unmodifiable(sourceFiles),
      executiveSummary:
          (report['executiveSummary'] ?? report['executive_summary'] ?? '')
              .toString()
              .trim(),
      artifacts: List<KorlixLiveDocsArtifact>.unmodifiable(artifacts),
      creditsUsed: _korlixInt(
        json['creditsUsed'] ?? json['credits_used'],
        fallback: 0,
      ),
      generationId: _korlixNullableString(
        json['generationId'] ?? json['generation_id'],
      ),
      tier: _korlixNullableString(json['tier']),
    );

    if (!result.isReady) {
      final error = (json['details'] ?? json['error'] ?? '').toString().trim();
      throw FormatException(
        error.isEmpty
            ? 'The LIVE DOCS service did not return completed report files.'
            : error,
      );
    }

    return result;
  }
}

class KorlixLiveDocsRealtimeToolCall {
  const KorlixLiveDocsRealtimeToolCall({
    required this.name,
    required this.callId,
    required this.arguments,
  });

  final String name;
  final String callId;
  final Map<String, dynamic> arguments;

  static List<KorlixLiveDocsRealtimeToolCall> fromResponseDone(
    Map<String, dynamic> response,
  ) {
    final rawOutput = response['output'];

    if (rawOutput is! List) {
      return const <KorlixLiveDocsRealtimeToolCall>[];
    }

    final calls = <KorlixLiveDocsRealtimeToolCall>[];

    for (final rawItem in rawOutput) {
      if (rawItem is! Map) {
        continue;
      }

      final item = Map<String, dynamic>.from(rawItem);

      if ((item['type'] ?? '').toString() != 'function_call') {
        continue;
      }

      final name = (item['name'] ?? '').toString().trim();
      final callId = (item['call_id'] ?? item['callId'] ?? '')
          .toString()
          .trim();

      if (name.isEmpty || callId.isEmpty) {
        continue;
      }

      Map<String, dynamic> arguments = <String, dynamic>{};
      final rawArguments = item['arguments'];

      if (rawArguments is Map) {
        arguments = Map<String, dynamic>.from(rawArguments);
      } else {
        final encoded = (rawArguments ?? '').toString().trim();
        if (encoded.isNotEmpty) {
          try {
            final decoded = jsonDecode(encoded);
            if (decoded is Map) {
              arguments = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            arguments = <String, dynamic>{'raw': encoded};
          }
        }
      }

      calls.add(
        KorlixLiveDocsRealtimeToolCall(
          name: name,
          callId: callId,
          arguments: Map<String, dynamic>.unmodifiable(arguments),
        ),
      );
    }

    return List<KorlixLiveDocsRealtimeToolCall>.unmodifiable(calls);
  }
}

class KorlixLiveDocsGenerationException implements Exception {
  const KorlixLiveDocsGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef KorlixLiveDocsGenerationHeadersBuilder = Map<String, String> Function();

class KorlixLiveDocsGenerationClient {
  KorlixLiveDocsGenerationClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.timeout = const Duration(minutes: 4),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String backendBaseUrl;
  final KorlixLiveDocsGenerationHeadersBuilder headersBuilder;
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  static List<String> normalizeFormats(Iterable<Object?> rawFormats) {
    const supported = <String>{'xlsx', 'docx', 'pdf'};
    final formats = <String>[];

    for (final raw in rawFormats) {
      final value = (raw ?? '').toString().trim().toLowerCase();
      if (supported.contains(value) && !formats.contains(value)) {
        formats.add(value);
      }
    }

    if (formats.isEmpty) {
      return const <String>['xlsx', 'docx', 'pdf'];
    }

    return List<String>.unmodifiable(formats);
  }

  Future<KorlixLiveDocsGenerationResult> create({
    required KorlixLiveDocBrief brief,
    required List<KorlixLiveDocsUpload> uploads,
    required String sourceDossier,
    required String language,
    String? instructionsOverride,
    List<String>? formatsOverride,
  }) async {
    if (!brief.canStartJob) {
      throw const KorlixLiveDocsGenerationException(
        'Approve a complete LIVE DOCS brief before generating the report.',
      );
    }

    final dossier = sourceDossier.trim();

    if (dossier.isEmpty) {
      throw const KorlixLiveDocsGenerationException(
        'LIVE DOCS needs conversation or file source material first.',
      );
    }

    final cleanBase = backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (cleanBase.isEmpty) {
      throw const KorlixLiveDocsGenerationException(
        'The Korlix backend address is unavailable.',
      );
    }

    final formats = normalizeFormats(
      formatsOverride ?? brief.outputFormats.map((format) => format.wireValue),
    );

    final instructionParts = <String>[
      brief.goal.trim(),
      if (instructionsOverride?.trim().isNotEmpty == true)
        instructionsOverride!.trim(),
    ];

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$cleanBase/api/live-docs/jobs'),
    );

    final headers = Map<String, String>.from(headersBuilder())
      ..removeWhere((name, _) => name.trim().toLowerCase() == 'content-type')
      ..['Accept'] = 'application/json';

    request.headers.addAll(headers);
    request.fields['title'] = brief.title.trim();
    request.fields['instructions'] = instructionParts.join('\n\n');
    request.fields['brief'] = jsonEncode(_briefPayload(brief));
    request.fields['sourceDossier'] = dossier;
    request.fields['formats'] = jsonEncode(formats);
    request.fields['language'] = language.trim().isEmpty
        ? 'en'
        : language.trim();

    final usableUploads = uploads
        .where((upload) => upload.bytes.isNotEmpty)
        .toList(growable: false);

    if (usableUploads.isEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          Uint8List.fromList(utf8.encode(dossier)),
          filename: 'korlix-live-convo-source.txt',
        ),
      );
    } else {
      for (final upload in usableUploads) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            upload.bytes,
            filename: upload.displayName,
          ),
        );
      }
    }

    late final http.StreamedResponse streamedResponse;

    try {
      streamedResponse = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const KorlixLiveDocsGenerationException(
        'Report generation timed out. Please try again.',
      );
    } catch (error) {
      throw KorlixLiveDocsGenerationException(
        'Could not reach the Korlix LIVE DOCS service: $error',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);
    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KorlixLiveDocsGenerationException(
        _responseError(
          response,
          decoded,
          fallback: 'LIVE DOCS report generation failed.',
        ),
      );
    }

    if (decoded == null) {
      throw const KorlixLiveDocsGenerationException(
        'The LIVE DOCS service returned an invalid response.',
      );
    }

    try {
      return KorlixLiveDocsGenerationResult.fromJson(decoded);
    } on FormatException catch (error) {
      throw KorlixLiveDocsGenerationException(error.message);
    }
  }

  Future<KorlixLiveDocsGenerationResult> revise({
    required KorlixLiveDocsGenerationResult current,
    required String instruction,
    List<String>? formatsOverride,
  }) async {
    final cleanInstruction = instruction.trim();

    if (cleanInstruction.isEmpty) {
      throw const KorlixLiveDocsGenerationException(
        'Describe the report revision first.',
      );
    }

    final cleanBase = backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (cleanBase.isEmpty) {
      throw const KorlixLiveDocsGenerationException(
        'The Korlix backend address is unavailable.',
      );
    }

    final headers = Map<String, String>.from(headersBuilder())
      ..['Content-Type'] = 'application/json'
      ..['Accept'] = 'application/json';

    late final http.Response response;

    try {
      response = await _client
          .post(
            Uri.parse(
              '$cleanBase/api/live-docs/jobs/'
              '${Uri.encodeComponent(current.jobId)}/revisions',
            ),
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'instruction': cleanInstruction,
              'formats': normalizeFormats(formatsOverride ?? current.formats),
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const KorlixLiveDocsGenerationException(
        'Report revision timed out. Please try again.',
      );
    } catch (error) {
      throw KorlixLiveDocsGenerationException(
        'Could not reach the Korlix LIVE DOCS revision service: $error',
      );
    }

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KorlixLiveDocsGenerationException(
        _responseError(
          response,
          decoded,
          fallback: 'LIVE DOCS report revision failed.',
        ),
      );
    }

    if (decoded == null) {
      throw const KorlixLiveDocsGenerationException(
        'The LIVE DOCS revision service returned an invalid response.',
      );
    }

    try {
      return KorlixLiveDocsGenerationResult.fromJson(decoded);
    } on FormatException catch (error) {
      throw KorlixLiveDocsGenerationException(error.message);
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static Map<String, dynamic> _briefPayload(KorlixLiveDocBrief brief) {
    final payload = Map<String, dynamic>.from(brief.toJson());

    payload.addAll(<String, dynamic>{
      'title': brief.title,
      'audience': brief.audience,
      'goal': brief.goal,
      'instructions': brief.goal,
      'tone': brief.tone,
      'targetLength': brief.targetLengthPages == null
          ? null
          : '${brief.targetLengthPages} pages',
      'targetPages': brief.targetLengthPages,
      'requiredSections': brief.requiredSections,
      'formats': brief.outputFormats
          .map((format) => format.wireValue)
          .toList(growable: false),
    });

    payload.removeWhere((_, value) => value == null);
    return payload;
  }

  static Map<String, dynamic>? _decodeResponse(http.Response response) {
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // The caller will surface a concise response error.
    }

    return null;
  }

  static String _responseError(
    http.Response response,
    Map<String, dynamic>? decoded, {
    required String fallback,
  }) {
    final raw =
        decoded?['details'] ??
        decoded?['error'] ??
        decoded?['message'] ??
        response.body.trim();

    final message = raw.toString().trim();

    if (response.statusCode == 404) {
      return 'The LIVE DOCS generation route is not deployed on this backend yet.';
    }

    if (response.statusCode == 401) {
      return 'Please sign in again before generating a report.';
    }

    if (response.statusCode == 429) {
      return message.isEmpty
          ? 'Your current Korlix generation allowance is not available.'
          : message;
    }

    return message.isEmpty ? fallback : message;
  }
}

Future<void> shareKorlixLiveDocsArtifact({
  required BuildContext context,
  required KorlixLiveDocsGenerationResult result,
  required KorlixLiveDocsArtifact artifact,
}) async {
  final renderObject = context.findRenderObject();
  final shareOrigin = renderObject is RenderBox
      ? renderObject.localToGlobal(Offset.zero) & renderObject.size
      : null;

  await SharePlus.instance.share(
    ShareParams(
      text: 'Korlix LIVE DOCS report: ${result.title}',
      subject: result.title,
      files: <XFile>[
        XFile.fromData(
          artifact.bytes,
          mimeType: artifact.mimeType,
          name: artifact.fileName,
        ),
      ],
      fileNameOverrides: <String>[artifact.fileName],
      sharePositionOrigin: shareOrigin,
    ),
  );
}

class KorlixLiveDocsReportCard extends StatelessWidget {
  const KorlixLiveDocsReportCard({
    super.key,
    required this.state,
    required this.result,
    required this.error,
    this.onShareArtifact,
    this.onRevise,
    this.onRetry,
  });

  final KorlixLiveDocsGenerationState state;
  final KorlixLiveDocsGenerationResult? result;
  final String? error;
  final Future<void> Function(KorlixLiveDocsArtifact artifact)? onShareArtifact;
  final Future<void> Function()? onRevise;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final readyResult = result;
    final busy = state.isBusy;
    final failed = state == KorlixLiveDocsGenerationState.failed;

    final borderColor = failed
        ? const Color(0xFF8D3344)
        : readyResult != null
        ? const Color(0xFF3FAE83)
        : const Color(0xFF2A6070);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2200D9FF),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: failed
                      ? const Color(0xFF35131A)
                      : const Color(0xFF103E38),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : busy
                      ? Icons.auto_awesome_rounded
                      : Icons.verified_rounded,
                  color: failed
                      ? const Color(0xFFFF9EAD)
                      : const Color(0xFF62D6A7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readyResult?.title ?? state.statusLabel,
                      style: const TextStyle(
                        color: Color(0xFFF1F8F9),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      readyResult == null
                          ? state.statusLabel
                          : 'Revision ${readyResult.revision} • '
                                '${readyResult.creditsUsed} credits used',
                      style: const TextStyle(
                        color: Color(0xFF8FB0B9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFF62D6A7),
                  ),
                ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 14),
            const Text(
              'Ji-A is building the actual report files. Keep this LIVE CONVO screen open until the report card is ready.',
              style: TextStyle(color: Color(0xFFBBD0D6), height: 1.4),
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              color: Color(0xFF62D6A7),
              backgroundColor: Color(0xFF13313B),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 14),
            Text(
              error?.trim().isNotEmpty == true
                  ? error!.trim()
                  : 'The report could not be generated.',
              style: const TextStyle(
                color: Color(0xFFFFB7C1),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async => onRetry!(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ],
          if (readyResult != null && !busy) ...[
            if (readyResult.executiveSummary.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                readyResult.executiveSummary,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFBBD0D6), height: 1.45),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final artifact in readyResult.artifacts)
                  FilledButton.tonalIcon(
                    onPressed: onShareArtifact == null
                        ? null
                        : () async => onShareArtifact!(artifact),
                    icon: Icon(artifact.icon, size: 19),
                    label: Text('Save / Share ${artifact.formatLabel}'),
                    style: FilledButton.styleFrom(
                      foregroundColor: const Color(0xFFEAF8FA),
                      backgroundColor: const Color(0xFF164A55),
                    ),
                  ),
                if (onRevise != null)
                  OutlinedButton.icon(
                    onPressed: () async => onRevise!(),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Revise with Ji-A'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFD166),
                      side: const BorderSide(color: Color(0xFF806A31)),
                    ),
                  ),
              ],
            ),
            if (readyResult.sourceFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Sources: ${readyResult.sourceFiles.join(', ')}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7899A3),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Review generated files before relying on them for financial, legal, medical, or other consequential decisions.',
              style: TextStyle(
                color: Color(0xFF7899A3),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

int _korlixInt(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }

  return int.tryParse((value ?? '').toString()) ?? fallback;
}

String? _korlixNullableString(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

// KORLIX_LIVE_DOCS_REALTIME_GENERATION_BUILD131_END
