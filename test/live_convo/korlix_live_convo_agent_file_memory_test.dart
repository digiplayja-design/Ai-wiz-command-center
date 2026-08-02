import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingAgentMemoryClient extends http.BaseClient {
  _RecordingAgentMemoryClient(this.responseBody);

  final Map<String, dynamic> responseBody;

  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(responseBody))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

KorlixLiveConvoAgentMemoryFileUpload _upload(String name, List<int> bytes) {
  return KorlixLiveConvoAgentMemoryFileUpload(
    name: name,
    bytes: Uint8List.fromList(bytes),
  );
}

Map<String, dynamic> _previewResponse({
  bool requiresApproval = true,
  bool autoSaved = false,
  bool sourceStoredByKorlix = false,
}) {
  return <String, dynamic>{
    'ok': true,
    'analysisVersion': 'korlix.agent.file_memory.preview.build131.v1',
    'summary': 'Two durable memory suggestions were found.',
    'files': <Map<String, dynamic>>[
      <String, dynamic>{
        'fileName': 'operations.pdf',
        'extension': 'pdf',
        'mimeType': 'application/pdf',
        'sizeBytes': 12,
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'detectedSignature': 'pdf',
        'isImage': false,
      },
      <String, dynamic>{
        'fileName': 'field-photo.png',
        'extension': 'png',
        'mimeType': 'image/png',
        'sizeBytes': 10,
        'sha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'detectedSignature': 'png',
        'isImage': true,
      },
    ],
    'suggestions': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'suggestion-1',
        'selected': true,
        'draft': <String, dynamic>{
          'confirmed': true,
          'kind': 'fact',
          'label': 'Radio wiring rule',
          'content':
              'Each radio should have exactly three wires.\n\n'
              '[Source file: operations.pdf | Page 6 | MIME: application/pdf '
              '| SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]',
          'tags': <String>['radio', 'field'],
          'importance': 5,
          'sensitive': false,
          'source': 'file_memory:aaaaaaaaaaaaaaaa',
        },
        'provenance': <String, dynamic>{
          'sourceIndex': 0,
          'fileName': 'operations.pdf',
          'extension': 'pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 12,
          'sha256':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'page': '6',
          'sheet': null,
          'row': null,
          'slide': null,
          'region': null,
        },
      },
    ],
    'requiresApproval': requiresApproval,
    'autoSaved': autoSaved,
    'sourceRetention': <String, dynamic>{
      'storedByKorlix': sourceStoredByKorlix,
      'mode': 'preview_only',
      'message':
          'Korlix did not retain the uploaded source file. Only approved '
          'memories may be saved.',
    },
    'limits': <String, dynamic>{
      'maximumFiles': 5,
      'maximumBytesPerFile': 10485760,
      'maximumSuggestions': 20,
    },
    'tier': 'ultra',
    'creditsUsed': 1,
  };
}

void main() {
  group('Korlix Agent file-memory client', () {
    test(
      'uploads authenticated multipart files and parses safe preview',
      () async {
        final recording = _RecordingAgentMemoryClient(_previewResponse());

        final client = KorlixLiveConvoAgentClient(
          backendBaseUrl: 'https://backend.example',
          headersBuilder: () => <String, String>{
            'Authorization': 'Bearer test-token',
            'Content-Type': 'application/json',
            'X-Korlix-Device-Id': 'device-1',
          },
          client: recording,
        );

        final preview = await client.analyzeMemoryFiles(
          agentId: 'my_assistant',
          files: <KorlixLiveConvoAgentMemoryFileUpload>[
            _upload('operations.pdf', <int>[
              0x25,
              0x50,
              0x44,
              0x46,
              0x2D,
              0x31,
            ]),
            _upload('field-photo.png', <int>[
              0x89,
              0x50,
              0x4E,
              0x47,
              0x0D,
              0x0A,
              0x1A,
              0x0A,
            ]),
          ],
        );

        final request = recording.lastRequest as http.MultipartRequest;

        expect(
          request.url.toString(),
          'https://backend.example/api/live-convo/agents/'
          'my_assistant/memory-files/analyze',
        );

        expect(request.headers['Authorization'], 'Bearer test-token');

        expect(
          request.headers.keys
              .map((name) => name.toLowerCase())
              .contains('content-type'),
          isFalse,
        );

        expect(request.files, hasLength(2));

        expect(
          request.files.map((file) => file.field).toList(growable: false),
          <String>['files', 'files'],
        );

        expect(
          request.files.map((file) => file.filename).toList(growable: false),
          <String>['operations.pdf', 'field-photo.png'],
        );

        expect(preview.requiresApproval, isTrue);
        expect(preview.autoSaved, isFalse);
        expect(preview.sourceStoredByKorlix, isFalse);
        expect(preview.suggestions, hasLength(1));
        expect(preview.suggestions.single.draft.confirmed, isFalse);
        expect(preview.maximumFiles, 5);
        expect(preview.maximumBytesPerFile, 10485760);
        expect(preview.creditsUsed, 1);

        final confirmed = preview.suggestions.single.confirmedDraft();

        expect(confirmed.confirmed, isTrue);
        expect(confirmed.kind, 'fact');
        expect(confirmed.tags, contains('file_memory'));
        expect(confirmed.tags, contains('file_aaaaaaaaaaaa'));
        expect(confirmed.tags, contains('ext_pdf'));
        expect(confirmed.content, contains('Source file: operations.pdf'));
        expect(confirmed.content, contains('Page 6'));

        expect(
          RegExp(r'\[Source file:').allMatches(confirmed.content),
          hasLength(1),
        );

        client.close();
      },
    );

    test('rejects previews that claim automatic saving', () {
      expect(
        () => KorlixLiveConvoAgentMemoryFilePreview.fromJson(
          _previewResponse(autoSaved: true),
        ),
        throwsA(
          isA<KorlixLiveConvoAgentClientException>().having(
            (error) => error.code,
            'code',
            'agent_memory_file_approval_boundary_failed',
          ),
        ),
      );
    });

    test('rejects previews that remove explicit approval', () {
      expect(
        () => KorlixLiveConvoAgentMemoryFilePreview.fromJson(
          _previewResponse(requiresApproval: false),
        ),
        throwsA(
          isA<KorlixLiveConvoAgentClientException>().having(
            (error) => error.code,
            'code',
            'agent_memory_file_approval_boundary_failed',
          ),
        ),
      );
    });

    test('rejects previews that unexpectedly retain source files', () {
      expect(
        () => KorlixLiveConvoAgentMemoryFilePreview.fromJson(
          _previewResponse(sourceStoredByKorlix: true),
        ),
        throwsA(
          isA<KorlixLiveConvoAgentClientException>().having(
            (error) => error.code,
            'code',
            'agent_memory_file_retention_boundary_failed',
          ),
        ),
      );
    });

    test('rejects more than five files before network submission', () async {
      final recording = _RecordingAgentMemoryClient(_previewResponse());

      final client = KorlixLiveConvoAgentClient(
        backendBaseUrl: 'https://backend.example',
        headersBuilder: () => <String, String>{
          'Authorization': 'Bearer test-token',
        },
        client: recording,
      );

      final files = List<KorlixLiveConvoAgentMemoryFileUpload>.generate(
        6,
        (index) => _upload('file-$index.txt', <int>[65 + index]),
      );

      await expectLater(
        client.analyzeMemoryFiles(agentId: 'general', files: files),
        throwsA(
          isA<KorlixLiveConvoAgentClientException>().having(
            (error) => error.code,
            'code',
            'agent_memory_file_count_exceeded',
          ),
        ),
      );

      expect(recording.lastRequest, isNull);

      client.close();
    });
  });
}
