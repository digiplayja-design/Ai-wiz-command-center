import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/chat/chat_request.dart';

void main() {
  test(
    'direct picture requests route to generation; questions about pictures remain chat',
    () {
      for (final prompt in [
        'Create an image of a garden',
        'Please draw a portrait of a wizard',
        'Can you design a cafe poster?',
        'Make me a cinematic picture of space',
        'Generate a logo for my store',
      ]) {
        expect(korlixWantsNewImage(prompt), isTrue, reason: prompt);
      }
      for (final prompt in [
        'How do I create an image?',
        'Write a prompt to create a logo',
        'Explain image generation',
        'Make a list of image tools',
        'Create a video of a cat',
      ]) {
        expect(korlixWantsNewImage(prompt), isFalse, reason: prompt);
      }
    },
  );
  test(
    'history preserves order, strips authority roles and respects request budgets',
    () {
      final history = korlixChatHistory([
        {'role': 'system', 'content': 'Must be excluded'},
        for (var i = 0; i < 30; i++)
          {'role': i.isEven ? 'user' : 'assistant', 'content': 'turn $i'},
      ]);
      expect(history.length, 16);
      expect(history.first['content'], 'turn 14');
      expect(history.last['content'], 'turn 29');
      final bounded = korlixChatHistory(
        List.generate(16, (_) => {'role': 'user', 'content': 'x' * 20000}),
      );
      expect(
        bounded.fold<int>(0, (sum, m) => sum + m['content']!.length),
        96000,
      );
      expect(bounded.every((m) => m['content']!.length <= 12000), isTrue);
      expect(korlixChatHistory([]), isEmpty);
    },
  );
}
