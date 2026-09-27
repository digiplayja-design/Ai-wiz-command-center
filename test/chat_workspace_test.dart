import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/chat/chat_workspace.dart';

Widget app(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, height: 500, child: child)),
  ),
);
KorlixChatTimeline timeline(
  List<KorlixChatTurn> turns, {
  bool busy = false,
  String pending = '',
}) => KorlixChatTimeline(
  turns: turns,
  foreground: Colors.white,
  accent: Colors.cyan,
  surface: Colors.black,
  busy: busy,
  pendingQuestion: pending,
);

void main() {
  testWidgets(
    'question appears above its answer, with selectable readable text and copy',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          timeline([
            const KorlixChatTurn(
              id: 'one',
              question: 'My question',
              answer: 'A helpful answer',
            ),
          ]),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('question-one'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('answer-one'))).dy,
        ),
      );
      expect(find.byType(SelectableText), findsNWidgets(2));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, 'A helpful answer');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'older than four turns stay reachable and pending input stays visible',
    (tester) async {
      final turns = List.generate(
        9,
        (i) => KorlixChatTurn(
          id: '$i',
          question: 'Question $i',
          answer: 'Answer $i',
        ),
      );
      await tester.pumpWidget(
        app(timeline(turns, busy: true, pending: 'Next question')),
      );
      expect(find.text('Next question'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('chat-conversation')),
        const Offset(0, 4000),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.text('Question 0'),
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Question 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty chat offers a picture starter without sending a request', (
    tester,
  ) async {
    bool? image;
    String? prompt;
    await tester.pumpWidget(
      app(
        KorlixChatTimeline(
          turns: const [],
          foreground: Colors.white,
          accent: Colors.cyan,
          surface: Colors.black,
          onStarter: (p, i) {
            prompt = p;
            image = i;
          },
        ),
      ),
    );
    await tester.tap(find.text('Create a picture'));
    expect(image, isTrue);
    expect(prompt, '');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'picture controls fit narrow screens and preserve user selections',
    (tester) async {
      String size = '1024x1024', style = 'auto';
      bool mode = true;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: KorlixChatModeBar(
                imageMode: mode,
                busy: false,
                size: size,
                style: style,
                onModeChanged: (v) => setState(() => mode = v),
                onSizeChanged: (v) => setState(() => size = v),
                onStyleChanged: (v) => setState(() => style = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Square'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Portrait').last);
      await tester.pumpAndSettle();
      expect(size, '1024x1536');
      await tester.tap(find.text('Follow my prompt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Graphic design').last);
      await tester.pumpAndSettle();
      expect(style, 'design');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('image result exposes open and save controls', (tester) async {
    var opened = false, saved = false;
    await tester.pumpWidget(
      app(
        timeline([
          KorlixChatTurn(
            id: 'image',
            question: 'A garden',
            answer: 'Image generated.',
            image: const SizedBox(height: 100),
            onOpenImage: () => opened = true,
            onSaveImage: () => saved = true,
          ),
        ]),
      ),
    );
    await tester.tap(find.text('Open image'));
    await tester.tap(find.text('Save image'));
    expect(opened, isTrue);
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
