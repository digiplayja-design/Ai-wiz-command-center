import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/voice/rici_pronunciation.dart';

void main() {
  test(
    'speech instructions preserve commands while removing ambiguous name spelling',
    () {
      final instruction = riciRealtimeInstructions(
        'Rici, read this confirmed result. Do not save or send anything. Ricin and Ricié are unchanged.',
      );
      expect(instruction, contains('Ree-see, read this confirmed result.'));
      expect(instruction, contains('Do not save or send anything.'));
      expect(instruction, contains('Ricin and Ricié are unchanged.'));
      expect(instruction, contains('Do not announce the pronunciation'));
    },
  );
  test(
    'captions restore the Rici spelling without relabeling other people',
    () {
      expect(
        riciDisplayText('I’m Ree-see. Ask Risi for help.'),
        'I’m Rici. Ask Rici for help.',
      );
      expect(
        riciDisplayText('Richie and Patricia are contacts.'),
        'Richie and Patricia are contacts.',
      );
    },
  );
}
