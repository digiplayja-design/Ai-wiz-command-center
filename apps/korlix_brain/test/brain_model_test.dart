import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_model.dart';

void main() {
  const headers = {
    'x-korlix-brain-voice': 'sol-6.1-max-v1',
    'x-korlix-brain-model': 'gpt-6.1-sol',
    'x-korlix-brain-reasoning': 'max',
  };
  test('Sol requires its own protocol, model and Max acknowledgement', () {
    expect(hasBrainVoiceContract(headers), isTrue);
    for (final key in headers.keys) {
      expect(hasBrainVoiceContract({...headers}..remove(key)), isFalse);
    }
    expect(
      hasBrainVoiceContract({
        ...headers,
        'x-korlix-brain-voice': 'astra-max-v1',
      }),
      isFalse,
    );
    expect(
      hasBrainVoiceContract({
        ...headers,
        'x-korlix-brain-model': 'gpt-6-astra',
      }),
      isFalse,
    );
    expect(
      hasBrainVoiceContract({...headers, 'x-korlix-brain-reasoning': 'low'}),
      isFalse,
    );
  });
  test('only Sol 6.1 aliases and snapshots can reach speech', () {
    expect(isBrainReasoningModel('gpt-6.1-sol'), isTrue);
    expect(isBrainReasoningModel('gpt-6.1-sol-2026-09-29'), isTrue);
    for (final other in [
      null,
      'gpt-6-astra',
      'gpt-6-sol',
      'gpt-6x1-sol',
      'gpt-6.1-solar',
    ]) {
      expect(isBrainReasoningModel(other), isFalse);
    }
  });
}
