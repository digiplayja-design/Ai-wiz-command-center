import 'package:flutter_test/flutter_test.dart';

import '../../lib/live_docs/korlix_live_docs.dart';

void main() {
  group('KorlixLiveDocBrief', () {
    test('serializes and restores a confirmed document brief', () {
      final createdAt = DateTime.utc(2026, 7, 15, 20);
      final confirmedAt = DateTime.utc(2026, 7, 15, 20, 5);

      final source = KorlixLiveDocSourceFile(
        id: 'source-1',
        displayName: 'quarterly-sales.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        sizeBytes: 64000,
        uploadedAt: createdAt,
        storagePath: 'users/user-1/live-docs/source-1',
      );

      final brief = KorlixLiveDocBrief(
        id: 'brief-1',
        documentType: KorlixLiveDocType.businessReport,
        title: 'Second Quarter Sales Report',
        audience: 'Board of Directors',
        goal: 'Compare Q1 and Q2 sales and identify next actions.',
        tone: 'professional and concise',
        targetLengthPages: 8,
        requiredSections: const <String>[
          'Executive Summary',
          'Sales Comparison',
          'Risks',
          'Recommendations',
        ],
        outputFormats: const <KorlixLiveDocOutputFormat>[
          KorlixLiveDocOutputFormat.docx,
          KorlixLiveDocOutputFormat.pdf,
        ],
        sourceFiles: <KorlixLiveDocSourceFile>[source],
        confirmedFacts: const <String, String>{
          'Reporting period': 'Q2 2026',
          'Currency': 'USD',
        },
        createdAt: createdAt,
        confirmedAt: confirmedAt,
        approvedToStart: true,
      );

      expect(brief.canStartJob, isTrue);
      expect(brief.validationErrors, isEmpty);

      final restored = KorlixLiveDocBrief.fromJsonString(brief.toJsonString());

      expect(restored.toJson(), equals(brief.toJson()));
      expect(restored.toAgentInstruction(), contains('Do not invent'));
      expect(restored.toAgentInstruction(), contains('quarterly-sales.xlsx'));
    });

    test('does not allow an incomplete brief to start', () {
      final brief = KorlixLiveDocBrief(
        id: 'brief-incomplete',
        documentType: KorlixLiveDocType.professionalLetter,
        title: '',
        audience: '',
        goal: '',
        outputFormats: const <KorlixLiveDocOutputFormat>[],
        unresolvedQuestions: const <String>['Confirm the recipient.'],
        createdAt: DateTime.utc(2026, 7, 15),
      );

      expect(brief.canStartJob, isFalse);
      expect(brief.validationErrors, isNotEmpty);
      expect(
        brief.validationErrors.join(' '),
        contains('Confirm the document title'),
      );
      expect(
        brief.validationErrors.join(' '),
        contains('Resolve all open questions'),
      );
    });
  });

  group('KorlixLiveDocsBriefBuilder', () {
    test('accepts structured LIVE CONVO updates and confirms a brief', () {
      final builder = KorlixLiveDocsBriefBuilder();

      builder.applyConversationUpdate(<String, dynamic>{
        'document_type': 'business_proposal',
        'title': 'Expansion Funding Proposal',
        'audience': 'Commercial lender',
        'goal': 'Request financing for a new operating location.',
        'tone': 'professional, confident, and factual',
        'target_length_pages': 12,
        'required_sections': <String>[
          'Executive Summary',
          'Company Background',
          'Use of Funds',
          'Repayment Strategy',
        ],
        'output_formats': <String>['docx', 'pdf'],
        'confirmed_facts': <String, dynamic>{
          'Requested funding': r'$250,000',
          'Company founded': '2019',
        },
        'unresolved_questions': <String>['Confirm the lender name.'],
        'allow_web_research': false,
      });

      builder.addSourceFile(
        KorlixLiveDocSourceFile(
          id: 'budget-file',
          displayName: 'draft-budget.csv',
          mimeType: 'text/csv',
          sizeBytes: 2048,
          uploadedAt: DateTime.utc(2026, 7, 15),
        ),
      );

      builder.resolveQuestion('Confirm the lender name.');

      final approved = builder.buildApproved(
        id: 'brief-proposal-1',
        createdAt: DateTime.utc(2026, 7, 15, 21),
        confirmedAt: DateTime.utc(2026, 7, 15, 21, 10),
      );

      expect(approved.canStartJob, isTrue);
      expect(approved.documentType, KorlixLiveDocType.businessProposal);
      expect(approved.sourceFiles, hasLength(1));
      expect(approved.confirmedFacts['Requested funding'], r'$250,000');

      final payload = KorlixLiveDocsApiContract.createJobPayload(
        brief: approved,
        idempotencyKey: 'user-1-brief-proposal-1',
        clientBuild: '12.0.0+131',
      );

      expect(
        payload['schema_version'],
        KorlixLiveDocsApiContract.schemaVersion,
      );
      expect(payload['client_build'], '12.0.0+131');
      expect(payload['brief'], isA<Map<String, dynamic>>());
    });

    test('rejects a backend job request before user confirmation', () {
      final builder = KorlixLiveDocsBriefBuilder();

      builder.applyConversationUpdate(<String, dynamic>{
        'document_type': 'meeting_summary',
        'title': 'Weekly Operations Meeting',
        'audience': 'Operations team',
        'goal': 'Summarize decisions and action items.',
        'output_formats': <String>['docx', 'pdf'],
      });

      final draft = builder.buildDraft(
        id: 'brief-meeting-1',
        createdAt: DateTime.utc(2026, 7, 15),
      );

      expect(draft.canRequestConfirmation, isTrue);
      expect(draft.canStartJob, isFalse);

      expect(
        () => KorlixLiveDocsApiContract.createJobPayload(
          brief: draft,
          idempotencyKey: 'draft-request',
          clientBuild: '12.0.0+131',
        ),
        throwsStateError,
      );
    });
  });

  test('job progress is safely clamped between zero and one hundred', () {
    final job = KorlixLiveDocJob(
      id: 'job-1',
      briefId: 'brief-1',
      status: KorlixLiveDocJobStatus.processing,
      progressPercent: 140,
      stage: 'Formatting Word document',
      createdAt: DateTime.utc(2026, 7, 15),
      updatedAt: DateTime.utc(2026, 7, 15, 0, 1),
    );

    expect(job.progressPercent, 100);
    expect(job.isTerminal, isFalse);
  });
}
