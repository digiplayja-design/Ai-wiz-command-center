import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_docs/korlix_live_docs.dart';
import 'package:ai_wiz_command_center/live_docs/korlix_live_docs_generation.dart';

void main() {
  group('Korlix LIVE DOCS generation', () {
    test('adds Excel as a supported output format', () {
      expect(KorlixLiveDocOutputFormat.xlsx.wireValue, 'xlsx');
      expect(KorlixLiveDocOutputFormat.xlsx.displayName, 'Microsoft Excel');
    });

    test('normalizes only real generated report formats', () {
      expect(
        KorlixLiveDocsGenerationClient.normalizeFormats(<Object?>[
          'PDF',
          'xlsx',
          'md',
          'docx',
          'xlsx',
        ]),
        <String>['pdf', 'xlsx', 'docx'],
      );

      expect(
        KorlixLiveDocsGenerationClient.normalizeFormats(<Object?>['txt']),
        <String>['xlsx', 'docx', 'pdf'],
      );
    });

    test('decodes actual generated artifact bytes', () {
      final artifact = KorlixLiveDocsArtifact.fromJson(<String, dynamic>{
        'format': 'xlsx',
        'fileName': 'audit-report.xlsx',
        'mimeType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'contentBase64': base64Encode(<int>[80, 75, 3, 4]),
      });

      expect(artifact.fileName, 'audit-report.xlsx');
      expect(artifact.bytes, <int>[80, 75, 3, 4]);
      expect(artifact.formatLabel, 'Excel');
    });

    test('parses a completed report result', () {
      final result = KorlixLiveDocsGenerationResult.fromJson(<String, dynamic>{
        'jobId': 'job-1',
        'status': 'completed',
        'revision': 2,
        'title': 'December Audit Report',
        'formats': <String>['xlsx', 'pdf'],
        'sourceFiles': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Dec2024_audits.xlsx'},
        ],
        'report': <String, dynamic>{
          'executiveSummary': 'The audit report is ready.',
        },
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{
            'format': 'pdf',
            'fileName': 'December_Audit_Report.pdf',
            'mimeType': 'application/pdf',
            'contentBase64': base64Encode(<int>[37, 80, 68, 70]),
          },
        ],
        'creditsUsed': 5,
      });

      expect(result.isReady, isTrue);
      expect(result.revision, 2);
      expect(result.sourceFiles, <String>['Dec2024_audits.xlsx']);
      expect(result.toRealtimeToolSummary()['success'], isTrue);
    });

    test('extracts complete Realtime function calls from response.done', () {
      final calls = KorlixLiveDocsRealtimeToolCall.fromResponseDone(
        <String, dynamic>{
          'status': 'completed',
          'output': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'function_call',
              'name': 'generate_live_docs_report',
              'call_id': 'call-123',
              'arguments': jsonEncode(<String, dynamic>{
                'formats': <String>['xlsx', 'pdf'],
                'instructions': 'Create the final audit report.',
              }),
            },
          ],
        },
      );

      expect(calls, hasLength(1));
      expect(calls.first.name, 'generate_live_docs_report');
      expect(calls.first.callId, 'call-123');
      expect(calls.first.arguments['formats'], <String>['xlsx', 'pdf']);
    });
  });
}
