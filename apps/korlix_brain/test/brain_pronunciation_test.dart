import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_pronunciation.dart';
import 'package:korlix_brain/brain_speech_queue.dart';

void main() {
  test('speech spelling changes only the assistant name, not stored text or other words', () {
    const text =
        'Rici, meet RICI. Rici’s voice. Ricin, Patricia, Ricié and user_Rici.';
    expect(
      brainSpeechText(text),
      'Ree-see, meet Ree-see. Ree-see’s voice. Ricin, Patricia, Ricié and user_Rici.',
    );
    expect(text, startsWith('Rici,'));
    expect(
      brainDisplaySpeech('I am Ree-see. Your_R ee-see stays.'),
      'I am Rici. Your_R ee-see stays.',
    );
    expect(
      brainDisplaySpeech('user_Ree-see and Ree-seer'),
      'user_Ree-see and Ree-seer',
    );
  });

  test('Deep Think sends phonetic speech while keeping the supplied written answer', () async {
    final sent = <Map<String, dynamic>>[];
    final queue = BrainSpeechQueue(
      (event) async => sent.add(event),
      () => true,
      () => fail('Speech failed'),
    );
    const answer = "I'm Rici. The amount is 34.99 dollars.";
    queue.add(answer, 0, 'one');
    await Future<void>.delayed(Duration.zero);
    final response = sent.single['response'];
    expect(
      response['input'][0]['content'][0]['text'],
      "I'm Ree-see. The amount is 34.99 dollars.",
    );
    expect(response['instructions'], contains('pure s sound in see'));
    expect(answer, startsWith("I'm Rici"));
    queue.dispose();
  });
}
