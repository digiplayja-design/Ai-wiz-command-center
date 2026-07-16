import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_attachment.dart';

void main() {
  group('KorlixLiveConvoAttachment', () {
    test('converts a session attachment into LIVE DOCS metadata', () {
      final attachment = KorlixLiveConvoAttachment(
        id: 'live-doc-1',
        displayName: 'audit.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        sizeBytes: 4096,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        addedAt: DateTime.utc(2026, 7, 16),
      );

      final sourceFile = attachment.toLiveDocSourceFile();

      expect(sourceFile.id, 'live-doc-1');
      expect(sourceFile.displayName, 'audit.xlsx');
      expect(sourceFile.sizeBytes, 4096);
      expect(attachment.hasLocalBytes, isTrue);
      expect(attachment.sizeLabel, '4.0 KB');
    });

    test('infers supported MIME types', () {
      expect(korlixLiveConvoMimeTypeForName('report.pdf'), 'application/pdf');

      expect(korlixLiveConvoMimeTypeForName('sales.csv'), 'text/csv');

      expect(korlixLiveConvoMimeTypeForName('photo.PNG'), 'image/png');

      expect(
        korlixLiveConvoMimeTypeForName('unknown.bin'),
        'application/octet-stream',
      );
    });

    test('enforces file count and size limits', () {
      expect(
        KorlixLiveConvoAttachmentPolicy.validateCandidate(
          existingCount: KorlixLiveConvoAttachmentPolicy.maxFiles,
          existingBytes: 0,
          candidateBytes: 1024,
        ),
        contains('up to'),
      );

      expect(
        KorlixLiveConvoAttachmentPolicy.validateCandidate(
          existingCount: 0,
          existingBytes: 0,
          candidateBytes: KorlixLiveConvoAttachmentPolicy.maxFileBytes + 1,
        ),
        contains('15 MB'),
      );

      expect(
        KorlixLiveConvoAttachmentPolicy.validateCandidate(
          existingCount: 1,
          existingBytes: KorlixLiveConvoAttachmentPolicy.maxTotalBytes - 512,
          candidateBytes: 1024,
        ),
        contains('30 MB'),
      );
    });
  });
}
