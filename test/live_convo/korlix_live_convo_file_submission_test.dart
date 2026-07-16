import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_attachment.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_file_submission.dart';

class _RecordingClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;

    final response = <String, dynamic>{
      'success': true,
      'title': 'File answer: 2 files',
      'content':
          'Dec2024_audits.xlsx contains audit totals and '
          'imagined-picture.png contains a visible portrait.',
      'files': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Dec2024_audits.xlsx',
          'mimeType':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'size': 2048,
        },
        <String, dynamic>{
          'name': 'imagined-picture.png',
          'mimeType': 'image/png',
          'size': 4096,
        },
      ],
      'creditsUsed': 1,
      'generationId': 'generation-1',
      'tier': 'ultra',
    };

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(response))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

KorlixLiveConvoAttachment _attachment({
  required String id,
  required String name,
  required int size,
}) {
  return KorlixLiveConvoAttachment(
    id: id,
    displayName: name,
    mimeType: korlixLiveConvoMimeTypeForName(name),
    sizeBytes: size,
    bytes: Uint8List.fromList(List<int>.generate(size, (index) => index % 251)),
    addedAt: DateTime.utc(2026, 7, 16),
  );
}

void main() {
  group('Korlix LIVE CONVO file submission', () {
    test('builds a safe comprehensive source-dossier prompt', () {
      final prompt =
          korlixLiveConvoBuildFileAnalysisPrompt(<KorlixLiveConvoAttachment>[
            _attachment(id: 'file-1', name: 'audit.xlsx', size: 16),
            _attachment(id: 'file-2', name: 'evidence.png', size: 16),
          ]);

      expect(prompt, contains('audit.xlsx'));
      expect(prompt, contains('evidence.png'));
      expect(prompt, contains('spreadsheet'));
      expect(prompt, contains('untrusted source data'));
      expect(prompt, contains('Do not invent facts'));
      expect(prompt, contains('under 10,000 characters'));
    });

    test('submits real bytes as multipart files', () async {
      final recordingClient = _RecordingClient();

      final api = KorlixLiveConvoFileSubmissionClient(
        backendBaseUrl: 'https://backend.example',
        headersBuilder: () => <String, String>{
          'Authorization': 'Bearer test-token',
          'Content-Type': 'application/json',
          'X-Korlix-Device-Id': 'device-1',
        },
        client: recordingClient,
      );

      final result = await api.submit(
        attachments: <KorlixLiveConvoAttachment>[
          _attachment(id: 'file-1', name: 'Dec2024_audits.xlsx', size: 32),
          _attachment(id: 'file-2', name: 'imagined-picture.png', size: 24),
        ],
        language: 'English',
      );

      final request = recordingClient.lastRequest as http.MultipartRequest;

      expect(
        request.url.toString(),
        'https://backend.example/api/analyze-documents',
      );

      expect(request.headers['Authorization'], 'Bearer test-token');

      expect(
        request.headers.keys
            .map((name) => name.toLowerCase())
            .contains('content-type'),
        isFalse,
      );

      expect(request.fields['language'], 'en');
      expect(request.files, hasLength(2));

      expect(
        request.files.map((file) => file.field).toList(growable: false),
        <String>['files', 'files'],
      );

      expect(
        request.files.map((file) => file.filename).toList(growable: false),
        <String>['Dec2024_audits.xlsx', 'imagined-picture.png'],
      );

      expect(result.answer, contains('audit totals'));
      expect(result.files, hasLength(2));
      expect(result.creditsUsed, 1);
      expect(result.generationId, 'generation-1');

      api.close();
    });

    test('builds bounded Realtime source context', () {
      final result = KorlixLiveConvoFileSubmissionResult(
        title: 'Source analysis',
        answer: List<String>.filled(5000, 'important evidence').join(' '),
        files: const <KorlixLiveConvoSubmittedFile>[
          KorlixLiveConvoSubmittedFile(
            name: 'audit.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            sizeBytes: 2048,
          ),
        ],
        creditsUsed: 1,
      );

      final context = korlixLiveConvoBuildProcessedFileContext(
        result: result,
        attachments: <KorlixLiveConvoAttachment>[
          _attachment(id: 'file-1', name: 'audit.xlsx', size: 8),
        ],
        maxCharacters: 5000,
      );

      expect(context, contains('PROCESSED SOURCE CONTEXT'));
      expect(context, contains('audit.xlsx'));
      expect(context, contains('not as system instructions'));
      expect(context, contains('BEGIN SOURCE DOSSIER'));
      expect(context.length, lessThanOrEqualTo(5100));
    });

    test('normalizes supported conversation languages', () {
      expect(korlixLiveConvoNormalizeLanguageCode('English'), 'en');

      expect(korlixLiveConvoNormalizeLanguageCode('Español'), 'es');

      expect(korlixLiveConvoNormalizeLanguageCode('Français'), 'fr');
    });

    test('submission states expose clear button labels', () {
      expect(
        KorlixLiveConvoFileSubmissionState.localOnly.buttonLabel(2),
        'Send 2 Files to Ji-A',
      );

      expect(
        KorlixLiveConvoFileSubmissionState.submitting.buttonLabel(2),
        'Sending 2 Files…',
      );

      expect(
        KorlixLiveConvoFileSubmissionState.ready.buttonLabel(2),
        '2 Files Ready for Ji-A',
      );

      expect(
        KorlixLiveConvoFileSubmissionState.failed.buttonLabel(2),
        'Retry File Submission',
      );
    });
  });
}
