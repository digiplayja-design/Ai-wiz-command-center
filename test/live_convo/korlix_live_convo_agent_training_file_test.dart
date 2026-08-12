import 'dart:typed_data';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('training updates serialize authoritative append and replace modes', () {
    const replace = KorlixLiveConvoAgentTrainingUpdate(
      instructions: 'Use the uploaded operating procedure.',
      confirmed: true,
      mode: 'replace',
      source: 'agent_training_document_reviewed',
    );

    const append = KorlixLiveConvoAgentTrainingUpdate(
      instructions: 'Add this response-format rule.',
      confirmed: true,
      mode: 'append',
    );

    expect(replace.toJson()['mode'], 'replace');

    expect(append.toJson()['mode'], 'append');

    expect(
      replace.toJson()['trainingInstructions'],
      'Use the uploaded operating procedure.',
    );
  });

  test('training-file preview requires approval and source non-retention', () {
    final preview = KorlixLiveConvoAgentTrainingFilePreview.fromJson(
      <String, dynamic>{
        'analysisVersion': 'korlix.agent.file_training.preview.build132.v1',
        'summary': 'One operating guide was analyzed.',
        'trainingDraft': 'Follow the approved operating sequence.',
        'files': <Map<String, dynamic>>[
          <String, dynamic>{
            'fileName': 'guide.pdf',
            'extension': 'pdf',
            'mimeType': 'application/pdf',
            'sizeBytes': 1200,
            'sha256': List<String>.filled(64, 'a').join(),
            'detectedSignature': 'pdf',
            'isImage': false,
          },
        ],
        'requiresApproval': true,
        'autoSaved': false,
        'sourceRetention': <String, dynamic>{
          'storedByKorlix': false,
          'message': 'The source file was not retained.',
        },
        'limits': <String, dynamic>{
          'maximumFiles': 5,
          'maximumBytesPerFile': 10 * 1024 * 1024,
          'maximumTrainingCharacters': 12000,
        },
        'creditsUsed': 1,
      },
    );

    expect(preview.trainingDraft, 'Follow the approved operating sequence.');

    expect(preview.requiresApproval, isTrue);

    expect(preview.autoSaved, isFalse);

    expect(preview.sourceStoredByKorlix, isFalse);

    expect(preview.maximumTrainingCharacters, 12000);
  });

  test('training uploads use the established safe file limits', () {
    final upload = KorlixLiveConvoAgentMemoryFileUpload(
      name: 'training.docx',
      bytes: Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]),
    );

    expect(upload.extension, 'docx');

    expect(
      KorlixLiveConvoAgentMemoryFileUpload.allowedExtensions,
      containsAll(<String>['pdf', 'docx', 'xlsx', 'pptx', 'png']),
    );

    expect(KorlixLiveConvoAgentMemoryFileUpload.maximumFiles, 5);

    expect(
      KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile,
      10 * 1024 * 1024,
    );
  });
}
