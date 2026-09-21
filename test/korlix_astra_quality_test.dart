import 'package:ai_wiz_command_center/korlix_ai_quality_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality headers and prompt agree on Astra while image requests retain their model', () {
    final headers = korlixOpenAIQualityHeaders();
    expect(headers['X-Korlix-OpenAI-Text-Model'], 'gpt-6-astra');
    expect(headers['X-Korlix-OpenAI-Preferred-Model'], 'gpt-6-astra');
    expect(headers['X-Korlix-OpenAI-Streaming-Model'], 'gpt-6-astra');
    expect(headers['X-Korlix-OpenAI-Image-Model'], 'gpt-image-2');
    final prompt = korlixApplyProductionQualityDirective('Write a brief');
    expect(prompt, contains('Preferred text/reasoning model: gpt-6-astra.'));
    expect(korlixStripProductionQualityDirective(prompt), 'Write a brief');
  });
}
